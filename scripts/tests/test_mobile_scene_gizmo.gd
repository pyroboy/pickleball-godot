extends "res://scripts/tests/test_mobile_selected_gizmo.gd"
## Scene geometry regression: the visual handle and the pick/drag math must
## describe the same three-dimensional object in the private preview world.

func projected_metrics(g, axis: int) -> Dictionary:
	var points := PackedVector2Array()
	var mean := Vector2.ZERO
	var bounds := Rect2(g.ring_point(axis, 0.0), Vector2.ZERO)
	for index in range(96):
		var point: Vector2 = g.ring_point(axis, TAU * index / 96.0)
		points.append(point); mean += point; bounds = bounds.expand(point)
	mean /= float(points.size())
	var xx := 0.0; var xy := 0.0; var yy := 0.0
	for point in points:
		var d: Vector2 = point - mean
		xx += d.x * d.x; xy += d.x * d.y; yy += d.y * d.y
	xx /= points.size(); xy /= points.size(); yy /= points.size()
	var discriminant := sqrt(maxf(0.0, (xx - yy) * (xx - yy) + 4.0 * xy * xy))
	var major := sqrt(maxf(0.0, (xx + yy + discriminant) * .5))
	var minor := sqrt(maxf(0.0, (xx + yy - discriminant) * .5))
	return {"bounds": bounds, "ratio": minor / maxf(major, .0001), "major": major, "minor": minor, "angle": .5 * atan2(2.0 * xy, xx - yy)}

func verify_mesh_geometry(label: String) -> void:
	var g = editor._preview.gizmo
	g.sync_scene()
	check(g.scene_root is Node3D and g.scene_root.get_viewport() == editor._preview.viewport, label + " has a real Node3D in isolated viewport")
	check(editor._preview.viewport.own_world_3d and g.scene_root.get_world_3d() == editor._preview.player.get_world_3d(), label + " shares only the private player world")
	check(g.scene_root.global_position.distance_to(editor._preview.joint_world_position(editor._preview.selected_joint)) < .000002, label + " root follows actual solved part")
	check(g.center().distance_to(editor._preview.joint_screen_position(editor._preview.selected_joint)) < .0001, label + " projected center is the actual part")
	check(g._arrows.size() == 3 and g._rings.size() == 3, label + " owns three arrows and three rings")
	for axis in range(3):
		var arrow: Node3D = g._arrows[axis]
		var ring: MeshInstance3D = g._rings[axis]
		check(arrow.get_child_count() >= 2 and arrow.get_child(0) is MeshInstance3D and arrow.get_child(1) is MeshInstance3D, label + " axis %d has shaft and tip meshes" % axis)
		check(ring.mesh is TorusMesh and ring.get_viewport() == editor._preview.viewport, label + " axis %d has world-space torus mesh" % axis)
		check(arrow.global_basis.y.normalized().dot(g.world_axes[axis].normalized()) > .99999, label + " arrow %d aligned to world axis" % axis)
		check(ring.global_basis.y.normalized().dot(g.world_axes[axis].normalized()) > .99999, label + " ring %d plane normal aligned to world axis" % axis)
		check(absf(ring.global_basis.x.length() - g.world_radius(axis)) < .000002 and absf(ring.global_basis.z.length() - g.world_radius(axis)) < .000002, label + " torus %d has the interaction radius" % axis)
		var projected_end: Vector2 = editor._preview._world_screen_position(arrow.global_transform * Vector3.UP)
		check(projected_end.distance_to(g.axis_geometry(axis).end) < .002, label + " mesh tip %d and hit tip agree" % axis)
		for angle in [0.0, .4, 1.6, 3.2, 5.3]:
			var world: Vector3 = g.ring_world_point(axis, angle)
			var local: Vector3 = ring.to_local(world)
			check(absf(local.y) < .00001 and absf(Vector2(local.x, local.z).length() - 1.0) < .00001, label + " ring sample lies on actual torus centerline")
			check(g.ring_point(axis, angle).distance_to(editor._preview._world_screen_position(world)) < .0001, label + " pick ring uses camera projection")
		check(g.unit_scales[axis] == 1.0, label + " world units do not use screen authoring multipliers")

func scene_snap(label: String) -> void:
	await snap(label)
	if capture:
		var image: Image = editor._preview.viewport.get_texture().get_image()
		check(not image.is_empty(), label + " private 3D viewport is rendered")
		check(image.save_png(output + "/" + label + "-viewport.png") == OK, label + " saved isolated scene")

func run() -> void:
	create_timer(180, true).timeout.connect(func(): quit(2))
	capture = "--capture" in OS.get_cmdline_user_args()
	output = "/workspace/scratch/6b6e64f75bd2/verification/scene-gizmo"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): output = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(output)
	var isolated := "user://pose_store_tests/scene_gizmo_%d/" % OS.get_process_id()
	Store.set_test_path(isolated + "poses.json"); Serve.set_test_path(isolated + "serves.json"); Grip.set_test_path(isolated + "grips.json"); View.set_test_path(isolated + "view.json")
	root.size = Vector2i(432, 936); root.content_scale_size = Vector2i(720, 1560)
	pause = root.get_node("PauseController")
	if capture:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game; await frames(4)
	pause.open(); game.open_mobile_pose_editor(); await frames(4); editor = game.mobile_pose_editor
	select_id(0); editor._joint_chosen("hips"); mode(1); await frames()
	var g = editor._preview.gizmo
	var payload: String = Store.export_pose_json(editor._current)
	var views := {}
	for direction in ["front", "back", "side", "oblique"]:
		if direction == "oblique": oblique_camera()
		else: editor._preview.view(direction)
		g.sync_scene(); verify_mesh_geometry(direction)
		var metrics: Array = []
		for axis in range(3):
			var metric := projected_metrics(g, axis); metrics.append(metric)
			check(metric.bounds.size.x > 1.0 or metric.bounds.size.y > 1.0, direction + " ring %d has visible extent" % axis)
			check(metric.major > 20.0 and metric.major < 130.0, direction + " ring %d retains useful projected scale" % axis)
		views[direction] = metrics
		await scene_snap("portrait-" + direction + "-rotate")
	check(views.front[0].ratio < .35 and views.back[0].ratio < .35, "front/back X ring is genuinely foreshortened")
	check(views.side[0].ratio > .75 and views.side[0].ratio > views.front[0].ratio + .45, "side view opens X ring from edge to face")
	check(views.front[2].ratio > .75 and views.side[2].ratio < .35, "camera switches which world ring faces the viewer")
	check(absf(wrapf(views.oblique[0].angle - views.front[0].angle, -PI*.5, PI*.5)) > .1, "oblique camera rotates the projected ellipse major axis")
	check(Store.export_pose_json(editor._current) == payload, "camera and scene geometry never author pose content")
	# Arrow tips are projected world coordinates, including the depth fallback.
	mode(0)
	for direction in ["front", "back", "side", "oblique"]:
		if direction == "oblique": oblique_camera()
		else: editor._preview.view(direction)
		g.sync_scene(); verify_mesh_geometry(direction + " Move")
		for axis in range(3):
			var before: Vector3 = editor._edit.body_position_offset
			drag_axis(axis, .004)
			var expected := before; expected[axis] += .004
			check(editor._edit.body_position_offset.distance_to(expected) < .00001, direction + " world axis %d writes four millimetres" % axis)
	await scene_snap("portrait-oblique-move")
	# The root must stay attached even where the projected handle crosses the
	# preview edge. An inset billboard or tether would fail these checks.
	var saved_camera: Transform3D = editor._preview.camera.global_transform
	var center_depth: float = -editor._preview.camera.to_local(g.origin()).z
	var world_width: float = center_depth * 2.0 * tan(deg_to_rad(editor._preview.camera.fov * .5)) * editor._preview.size.x / editor._preview.size.y
	for side in [-1.0, 1.0]:
		editor._preview.camera.global_transform = saved_camera
		editor._preview.camera.global_position += editor._preview.camera.global_basis.x * world_width * .47 * side
		g.sync_scene()
		check(g.center().distance_to(g.anchor()) < .0001, "near-edge center has no inset or tether")
		check(g.scene_root.global_position.distance_to(g.origin()) < .000002, "near-edge Node3D stays on solved hips")
		check(g.center().x < 100.0 or g.center().x > editor._preview.size.x - 100.0, "near-edge fixture actually reaches preview edge")
		await scene_snap("portrait-edge-" + ("left" if side > 0 else "right"))
	editor._preview.camera.global_transform = saved_camera; g.sync_scene()
	# Repeated moves keep the press frame even as solved geometry is updated.
	oblique_camera(); mode(1); editor._joint_chosen("torso")
	var angle := ring_angle(g, 0, 4.0)
	var p0: Vector2 = g.ring_point(0, angle)
	var p1: Vector2 = g.ring_point(0, angle + deg_to_rad(2) * float(g.angle_signs[0]))
	var p2: Vector2 = g.ring_point(0, angle + deg_to_rad(4) * float(g.angle_signs[0]))
	var before_angle: float = editor._edit.torso_pitch_deg
	mouse(p0, true); motion(p1, p1-p0); motion(p2, p2-p1); mouse(p2, false)
	check(absf(editor._edit.torso_pitch_deg - before_angle - 4.0) < .0002, "two moves rotate four degrees in frozen press frame")
	# Edge-on rotation uses the local projected tangent of the actual ring.
	editor._joint_chosen("hips"); mode(1)
	editor._preview.camera.global_position = g.origin() + Vector3.BACK * 3.0
	editor._preview.camera.look_at(g.origin()); g.sync_scene()
	var edge_angle := NAN
	for index in range(192):
		var candidate := TAU * index / 192.0
		var point: Vector2 = g.ring_point(0, candidate)
		var tangent: Vector2 = (g.ring_point(0, candidate + .01) - point) / .01
		if g.hit_axis(point) == 0 and tangent.length() > 30.0: edge_angle = candidate; break
	check(is_finite(edge_angle), "edge-on ring retains independently selectable tangent arc")
	if is_finite(edge_angle):
		p0 = g.ring_point(0, edge_angle)
		var tangent: Vector2 = (g.ring_point(0, edge_angle + .01) - p0) / .01
		before_angle = editor._edit.body_pitch_deg
		mouse(p0, true); check(g._axis == 0 and g._drag_edge, "parallel camera ray activates edge-on fallback")
		p1 = p0 + tangent * deg_to_rad(2) * float(g.angle_signs[0])
		motion(p1, p1-p0); mouse(p1, false)
		check(absf(editor._edit.body_pitch_deg - before_angle - 2.0) < .002, "edge-on drag follows local 3D projected tangent")
	# Camera, resize, visibility and input ownership cannot leave stale drags.
	oblique_camera(); mode(0)
	p0 = g.axis_geometry(0).end; mouse(p0, true)
	check(g._axis == 0, "camera interruption fixture captures axis")
	var before_position: Vector3 = editor._edit.body_position_offset
	editor._preview.camera.position += Vector3(.1, 0, 0)
	motion(p0 + Vector2(30, 0), Vector2(30, 0))
	check(g._axis == -1 and editor._edit.body_position_offset == before_position, "external camera transform cancels without a pose jump")
	oblique_camera(); p0 = g.axis_geometry(0).end
	var touch := InputEventScreenTouch.new(); touch.index = 3; touch.position = p0; touch.pressed = true
	editor._preview._camera_input(touch)
	check(g._axis == 0 and g._touch == 3, "first touch owns the 3D handle")
	var other := InputEventScreenTouch.new(); other.index = 5; other.position = p0; other.pressed = true
	editor._preview._camera_input(other)
	var unrelated := InputEventScreenDrag.new(); unrelated.index = 5; unrelated.position = p0 + Vector2(40, 30); unrelated.relative = Vector2(40, 30)
	editor._preview._camera_input(unrelated)
	var emulated := InputEventMouseButton.new(); emulated.device = InputEvent.DEVICE_ID_EMULATION; emulated.button_index = MOUSE_BUTTON_LEFT; emulated.pressed = false; emulated.position = p0
	editor._preview._camera_input(emulated)
	check(g._axis == 0 and g._touch == 3 and editor._edit.body_position_offset == before_position, "second touch and emulated mouse cannot steal or release owner")
	touch.pressed = false; touch.canceled = true; editor._preview._camera_input(touch)
	check(g._axis == -1 and g._touch == -1, "owner cancellation clears touch and axis")
	editor._preview._camera_input(unrelated)
	check(editor._edit.body_position_offset == before_position, "stale second-finger motion remains inert")
	mouse(g.axis_geometry(0).end, true)
	root.size = Vector2i(432, 768); root.content_scale_size = Vector2i(720, 1280); await frames()
	check(g._axis == -1, "viewport resize cancels active geometry drag")
	await scene_snap("short-portrait-move")
	payload = Store.export_pose_json(editor._current)
	mouse(g.axis_geometry(0).end, true)
	editor._gizmo_show.set_pressed_no_signal(false); editor._toggle_gizmo(); g.sync_scene()
	check(g._axis == -1 and not g.scene_root.visible, "hide cancels drag and hides actual scene geometry")
	check(Store.export_pose_json(editor._current) == payload, "hide only changes view preference")
	editor._gizmo_show.set_pressed_no_signal(true); editor._toggle_gizmo(); g.sync_scene()
	check(g.scene_root.visible, "show restores the same scene root")
	# Numeric/export/save must continue using normal authoring, not mesh-only edits.
	oblique_camera(); editor._joint_chosen("paddle"); mode(1)
	var saved_before: float = editor._edit.paddle_pitch_base_deg
	drag_ring(0, 3.0)
	check(absf(wrapf(editor._edit.paddle_pitch_base_deg - saved_before, -180, 180) - 3.0) < .0002, "scene ring authors the existing paddle field")
	check(absf(editor._angle_inputs.paddle_pitch_base_deg.value - editor._edit.paddle_pitch_base_deg) <= editor._angle_inputs.paddle_pitch_base_deg.step*.5 + .00001, "scene drag keeps displayed numeric value synchronized")
	var exported: Dictionary = JSON.parse_string(Store.export_pose_json(editor._current))
	check(absf(float(exported.fields.paddle_pitch_base_deg) - editor._edit.paddle_pitch_base_deg) < .0002, "export contains authored scene-ring value")
	editor._save_current(); var saved: String = Store.export_pose_json(editor._current)
	check(not editor._dirty.has(editor._key), "scene drag saves through normal store")
	root.size = Vector2i(936, 432); root.content_scale_size = Vector2i(1560, 720); await frames()
	await scene_snap("landscape-rotate")
	var scene_root: Node3D = g.scene_root
	editor._finish_close(); await frames(4)
	check(not is_instance_valid(scene_root), "closing editor disposes scene gizmo root")
	pause.close(); await frames(2); pause.open(); game.open_mobile_pose_editor(); await frames(4); editor = game.mobile_pose_editor
	select_id(0)
	check(Store.export_pose_json(editor._current) == saved, "saved scene edit survives editor reopen")
	editor._finish_close(); await frames(3); pause.close(); game.queue_free(); await frames(2)
	print("MOBILE SCENE GIZMO: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
