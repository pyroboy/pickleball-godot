extends SceneTree
const Navigation = preload("res://scripts/tests/mobile_pose_test_navigation.gd")
const Store = preload("res://scripts/mobile_pose_store.gd")
const Serve = preload("res://scripts/mobile_serve_pose_store.gd")
const Grip = preload("res://scripts/mobile_paddle_grip_store.gd")
const View = preload("res://scripts/mobile_pose_view_settings.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Wrist = preload("res://scripts/paddle_wrist_reach.gd")
const Contact = preload("res://scripts/serve_contact_orientation.gd")
const Size = preload("res://scripts/paddle_dimensions.gd")
var checks := 0
var failures: Array[String] = []
var game
var editor
var pause
var capture := false
var output := "/workspace/scratch/6b6e64f75bd2/verification/selected-gizmo"

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func frames(n: int = 3) -> void:
	for i in range(n): await process_frame
func select_id(id: int) -> void:
	for i in range(editor._definitions.size()):
		if editor._definitions[i].posture_id == id: editor._select_pose(i); return
	check(false, "requested pose exists")
func mode(value: int) -> void:
	editor._gizmo_mode.select(value); editor._select_gizmo_mode(value)
func mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.position = point; event.pressed = pressed
	editor._preview._camera_input(event)
func motion(point: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new(); event.position = point; event.relative = relative
	editor._preview._camera_input(event)
func move_target(g, axis: int, geometry: Dictionary, start: Vector2, distance_units: float, frozen_origin: Vector3, frozen_axis: Vector3, frozen_length: float) -> Vector2:
	if geometry.depth: return start + geometry.direction * geometry.scale * distance_units
	return editor._preview._world_screen_position(frozen_origin + frozen_axis * (frozen_length + distance_units))
func drag_axis(axis: int, units: float = .012) -> void:
	var g = editor._preview.gizmo
	g.sync_scene()
	var geometry: Dictionary = g.axis_geometry(axis)
	var point: Vector2 = geometry.end
	var next: Vector2 = move_target(g, axis, geometry, point, units, g.origin(), g.world_axes[axis].normalized(), g._length)
	check(g.hit_axis(point) == axis, "Move axis %d has independent hit target" % axis)
	mouse(point, true)
	check(g._axis == axis, "Move press captures axis %d" % axis)
	motion(next, next - point); mouse(next, false)
	check(g._axis == -1, "Move release ends drag")
func oblique_camera() -> void:
	editor._preview.cancel_gesture()
	editor._preview.yaw = .85; editor._preview.pitch = .55
	editor._preview.update_camera(); editor._preview.gizmo.sync_scene()
func ring_angle(g, axis: int, degrees: float = 6.0) -> float:
	# Ring crossings belong to more than one axis. Choose a genuinely separate
	# visible arc with a stable ray/plane intersection, never a screen circle.
	g.sync_scene()
	var best_score := -INF
	var chosen := NAN
	for step in range(96):
		var angle := TAU * step / 96.0
		var point: Vector2 = g.ring_point(axis, angle)
		var next: Vector2 = g.ring_point(axis, angle + deg_to_rad(degrees))
		if not point.is_finite() or not next.is_finite() or g.hit_axis(point) != axis: continue
		if not Rect2(Vector2.ZERO, editor._preview.size).grow(-2).has_point(point): continue
		var pixel: Vector2 = point * Vector2(editor._preview.viewport.size) / editor._preview.size
		var incidence: float = absf(g.world_axes[axis].normalized().dot(editor._preview.camera.project_ray_normal(pixel)))
		if incidence < .13: continue
		var clearance := INF
		for other in range(3):
			if other == axis or g.bindings[other].is_empty(): continue
			for sample in range(96):
				var a: Vector2 = g.ring_point(other, TAU * sample / 96.0)
				var b: Vector2 = g.ring_point(other, TAU * (sample + 1) / 96.0)
				clearance = minf(clearance, point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)))
		var score := minf(clearance, 100.0) + incidence
		if score > best_score: best_score = score; chosen = angle
	check(is_finite(chosen), "Rotate ring %d has stable, independently pickable projected arc" % axis)
	return 0.0 if not is_finite(chosen) else chosen
func drag_ring(axis: int, degrees: float = 6.0) -> void:
	var g = editor._preview.gizmo
	var angle := ring_angle(g, axis, degrees)
	var point: Vector2 = g.ring_point(axis, angle)
	# Both positions use the same pre-drag 3D plane even if editing rotates it.
	var next: Vector2 = g.ring_point(axis, angle + deg_to_rad(degrees) * float(g.angle_signs[axis]))
	check(g.hit_axis(point) == axis, "Rotate ring %d has independent hit target" % axis)
	mouse(point, true)
	check(g._axis == axis and not g._drag_edge, "Rotate press captures stable plane on axis %d" % axis)
	motion(next, next - point); mouse(next, false)
	check(g._axis == -1, "Rotate release ends drag")
func snap(label: String) -> void:
	await frames(4)
	var bounds := root.get_visible_rect()
	for control in [editor._preview, editor._scroll, editor._save, editor._gizmo_mode, editor._gizmo_show]:
		check(bounds.encloses(control.get_global_rect()), label + " fits viewport")
	if capture:
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(output + "/" + label + ".png") == OK, label + " rendered screenshot")

func run() -> void:
	create_timer(180, true).timeout.connect(func(): quit(2))
	capture = "--capture" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(output)
	var isolated := "user://pose_store_tests/selected_gizmo_%d/" % OS.get_process_id()
	Store.set_test_path(isolated + "poses.json"); Serve.set_test_path(isolated + "serves.json"); Grip.set_test_path(isolated + "grips.json"); View.set_test_path(isolated + "view.json")
	root.size = Vector2i(432, 936); root.content_scale_size = Vector2i(720, 1560)
	pause = root.get_node("PauseController")
	if capture:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game; await frames(4)
	pause.open(); game.open_mobile_pose_editor(); await frames(4); editor = game.mobile_pose_editor
	select_id(0); editor._joint_chosen("hips"); mode(0); await frames()
	var g = editor._preview.gizmo
	check(g.visible and g.enabled, "selected hips shows gizmo by default")
	check(editor._gizmo_hint.text.contains("Whole body"), "hips Move honestly describes whole body")
	for view in ["front", "side", "back", "reset"]:
		editor._preview.view(view)
		for axis in range(3):
			var before: Vector3 = editor._edit.body_position_offset
			var other: Vector3 = Path.endpoint(editor._current, 0).body_position_offset
			var camera: Transform3D = editor._preview.camera.transform
			drag_axis(axis)
			var expected := before; expected[axis] += .012
			check(editor._edit.body_position_offset.is_equal_approx(expected), "Move writes correct authored axis at " + view)
			check(Path.endpoint(editor._current, 0).body_position_offset.is_equal_approx(other), "Contact Move preserves Wind-up")
			check(editor._preview.camera.transform.is_equal_approx(camera), "handle drag never orbits")
			check(is_equal_approx(editor._body_inputs["body_position_offset:" + str(axis)].value, expected[axis]), "typed body value synchronized")
	check(editor._dirty.has(editor._key), "gizmo edit dirties current pose")
	await snap("portrait-body-move")
	# Singular screen axes still expose a finite, labelled depth handle.
	editor._preview.view("front"); g.world_axes[2] = (editor._preview.joint_world_position("hips") - editor._preview.camera.global_position).normalized()
	check(g.axis_geometry(2).depth and g.axis_geometry(2).end.is_finite(), "camera-aligned axis has usable depth fallback")
	drag_axis(2, .005)
	# Camera outside handles, and dropdown selection stays authoritative.
	var point := Vector2(10, editor._preview.size.y - 10)
	var camera: Transform3D = editor._preview.camera.transform
	mouse(point, true); motion(point + Vector2(24, 6), Vector2(24, 6)); mouse(point, false)
	check(not camera.is_equal_approx(editor._preview.camera.transform), "drag outside handles orbits")
	check(editor._preview.selected_joint == "hips", "camera gesture never changes selected part")
	for axis in range(3):
		var geometry: Dictionary = g.axis_geometry(axis)
		var before_touch: Vector3 = editor._edit.body_position_offset
		var press := InputEventScreenTouch.new(); press.index = 7; press.position = geometry.end; press.pressed = true
		editor._preview._camera_input(press)
		var frozen_origin: Vector3 = g.origin()
		var frozen_axis: Vector3 = g.world_axes[axis].normalized()
		var frozen_length: float = g._length
		var touch_move := InputEventScreenDrag.new(); touch_move.index = 7
		touch_move.position = move_target(g, axis, geometry, press.position, .003, frozen_origin, frozen_axis, frozen_length)
		touch_move.relative = touch_move.position - press.position
		editor._preview._camera_input(touch_move)
		var first: Vector2 = touch_move.position
		touch_move.position = move_target(g, axis, geometry, press.position, .006, frozen_origin, frozen_axis, frozen_length)
		touch_move.relative = touch_move.position - first; editor._preview._camera_input(touch_move)
		var expected_touch := before_touch; expected_touch[axis] += .006
		check(editor._edit.body_position_offset.is_equal_approx(expected_touch), "repeated touch drags update correct axis")
		press.pressed = false; press.position = Vector2(-500, -500); editor._preview._input(press)
		check(g._axis == -1, "touch release outside preview clears gesture")
	# Touch ownership, cancellation, emulated mouse and stale drags.
	point = g.axis_geometry(0).end
	var touch := InputEventScreenTouch.new(); touch.index = 4; touch.position = point; touch.pressed = true
	editor._preview._camera_input(touch)
	check(g._axis == 0 and g._touch == 4, "touch captures selected axis")
	var before: Vector3 = editor._edit.body_position_offset
	var second := InputEventScreenDrag.new(); second.index = 8; second.position = point + Vector2(50, 50); second.relative = Vector2(50, 50)
	editor._preview._camera_input(second)
	check(editor._edit.body_position_offset == before, "second finger cannot move active axis")
	touch.canceled = true; touch.pressed = false; editor._preview._camera_input(touch)
	check(g._axis == -1 and g._touch == -1, "touch cancel clears drag")
	editor._preview._camera_input(second)
	check(editor._edit.body_position_offset == before, "stale canceled drag changes nothing")
	mouse(g.axis_geometry(0).end, true); editor._preview._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(g._axis == -1, "focus loss clears handle")
	mouse(g.axis_geometry(0).end, true); editor._select_stage(2)
	check(g._axis == -1, "phase change clears handle")
	mouse(g.axis_geometry(0).end, true); editor._joint_chosen("right_elbow")
	check(g._axis == -1 and g.caption.contains("Bend guide"), "selection clears drag and labels elbow guide")
	var hand_before: Vector3 = editor._preview.player.right_arm_node.hand_pivot.global_position
	drag_axis(0, .015)
	check(editor._preview.player.right_arm_node.hand_pivot.global_position.distance_to(hand_before) < .0001, "elbow guide keeps seated hand target")
	check(editor._gizmo_hint.text.contains("IK"), "elbow Move describes IK constraints")
	await snap("portrait-elbow-guide")
	editor._joint_chosen("right_knee"); mode(1)
	check(editor._gizmo_mode.is_item_disabled(1) and not g.enabled, "knee Rotate unavailable")
	editor._joint_chosen("head"); mode(0)
	check(editor._gizmo_mode.is_item_disabled(0) and not g.enabled, "head Move unavailable")
	mode(1); check(g.bindings[2].is_empty(), "head has no fake roll")
	editor._joint_chosen("torso"); mode(1); oblique_camera()
	for axis in range(3):
		var field: String = g.bindings[axis].field
		var value: float = editor._edit.get(field)
		drag_ring(axis, 2.0)
		# Godot projects through float32 Vector3/viewport coordinates. Wider/taller
		# scene layouts introduce sub-millidegree ray/plane round-trip noise.
		check(absf(float(editor._edit.get(field)) - (value + 2.0)) < .001, "torso authored angle changes")
	editor._joint_chosen("paddle"); mode(1)
	for stage in range(3):
		editor._select_stage(stage)
		for axis in range(3):
			var field: String = editor.ROT[axis]
			var value: float = editor._edit.get(field)
			var other: Resource = Path.endpoint(editor._current, 2 if stage != 2 else 0)
			var wrist: Vector3 = Wrist.displayed_wrist(editor._preview.player, editor._preview.pose)
			drag_ring(axis, 3.0); await frames(1)
			check(absf(wrapf(float(editor._edit.get(field)) - (value + 3.0), -180, 180)) < .001, "paddle ring uses existing authored angle")
			check(absf(editor._angle_inputs[field].value - float(editor._edit.get(field))) <= editor._angle_inputs[field].step * .5 + .00001, "paddle numeric input synchronized at displayed precision")
			check(is_equal_approx(editor._gimbal.angles[axis], editor._edit.get(field)), "on-panel gimbal synchronized")
			check(is_equal_approx(Path.endpoint(editor._current, 2 if stage != 2 else 0).get(field), other.get(field)), "paddle rotation preserves other key")
			check(Wrist.displayed_wrist(editor._preview.player, editor._preview.pose).distance_to(wrist) < .00002, "ordinary paddle rotation preserves seated wrist")
	await snap("portrait-paddle-rotate")
	# Move handles and the Position subview are independent controls. Reveal
	# the real position sliders before checking their synchronized values.
	Navigation.select_field(editor, editor.POS[0])
	mode(0)
	for stage in range(3):
		editor._select_stage(stage)
		for axis in range(3):
			var field: String = editor.POS[axis]
			var value: float = editor._edit.get(field)
			var other_value: float = Path.endpoint(editor._current, 2 if stage != 2 else 0).get(field)
			drag_axis(axis, .005)
			check(is_equal_approx(editor._edit.get(field), value + .005), "paddle Move edits selected stage axis")
			check(absf(editor._sliders[field].value - float(editor._edit.get(field))) <= editor._sliders[field].step * .5 + .00001, "paddle Move slider synchronized at displayed precision")
			check(is_equal_approx(Path.endpoint(editor._current, 2 if stage != 2 else 0).get(field), other_value), "paddle Move preserves other stage")
	Navigation.select_field(editor, editor.ROT[0])
	mode(1)
	# Continuous angle wrap at +/-180 in the projected world-space ring.
	editor._set_paddle_angle(0, 179); await frames(1); drag_ring(0, 4); await frames(1)
	check(is_equal_approx(editor._edit.paddle_pitch_base_deg, -177), "ring crosses wrap seam continuously")
	editor._scrubbed(.24)
	check(not g.enabled, "in-between preview cannot accidentally edit selected key")
	editor._select_stage(1); editor._toggle_play()
	check(not g.enabled, "playback disables editing handles")
	editor._select_stage(1)
	# Show mode is a separate persisted view preference and never pose content.
	var payload: String = Store.export_pose_json(editor._current)
	editor._gizmo_show.set_pressed_no_signal(false); editor._toggle_gizmo()
	check(not g.visible and not View.load_gizmo().shown, "hide persists")
	check(Store.export_pose_json(editor._current) == payload, "hide never authors pose")
	View.save_inbetween_count(1)
	check(not View.load_gizmo().shown, "ghost setting preserves gizmo preference")
	editor._gizmo_show.set_pressed_no_signal(true); editor._toggle_gizmo()
	check(View.load_inbetween_count() == 1, "gizmo setting preserves ghost preference")
	editor._save_current(); check(not editor._dirty.has(editor._key), "Save persists gizmo edits")
	var saved: String = Store.export_pose_json(editor._current)
	editor._reset_field(editor.ROT[0], -1)
	check(Store.export_pose_json(editor._current) == saved, "reset uses saved value")
	editor._finish_close(); await frames(4); pause.close(); await frames(2)
	pause.open(); game.open_mobile_pose_editor(); await frames(4); editor = game.mobile_pose_editor
	select_id(0); editor._joint_chosen("paddle"); g = editor._preview.gizmo
	check(editor._gizmo_mode.selected == 1 and editor._gizmo_show.button_pressed, "mode and visibility survive reopen")
	check(Store.export_pose_json(editor._current) == saved, "authored pose survives reopen")
	# Serve Contact: real paddle rotates, fixed surface point remains exact.
	editor._select_workspace(2); editor._joint_chosen("paddle"); editor._select_stage(1); mode(0)
	check(not g.enabled and editor._gizmo_mode.is_item_disabled(0), "serve Contact Move locked")
	mode(1)
	var face := Size.HEAD_OFFSET + Vector3.BACK * Contact.CONTACT_DISTANCE
	var fixed: Vector3 = editor._preview.player.paddle_node.global_transform * face
	for axis in range(3):
		var basis: Basis = editor._preview.player.paddle_node.global_basis
		drag_ring(axis, 2); await frames(1)
		check(not basis.is_equal_approx(editor._preview.player.paddle_node.global_basis), "serve Contact ring rotates actual mesh")
		check((editor._preview.player.paddle_node.global_transform * face).distance_to(fixed) < .00002, "serve Contact ring retains fixed ball surface")
		check(Wrist.displayed_wrist(editor._preview.player, editor._preview.pose).distance_to(Wrist.wrist_world(editor._preview.player.paddle_node.global_transform, editor._preview.pose)) < .00002, "serve Contact hand seated")
	await snap("portrait-serve-contact")
	editor._joint_chosen("left_foot"); mode(0)
	check(not g.enabled, "serve Contact feet locked")
	editor._select_stage(0)
	check(g.enabled and g.bindings[1].is_empty(), "serve Wind-up foot X Z allowed, floor Y disabled")
	editor._joint_chosen("left_hand")
	check(not g.enabled, "serve held-ball hand cannot move")
	editor._select_workspace(1); editor._joint_chosen("hips"); mode(0)
	check(not g.enabled, "base stance has no fake whole body translation")
	editor._select_workspace(0); select_id(0); editor._joint_chosen("paddle"); mode(1)
	root.size = Vector2i(432, 768); root.content_scale_size = Vector2i(720, 1280); await snap("short-portrait-rotate")
	root.size = Vector2i(936, 432); root.content_scale_size = Vector2i(1560, 720); await snap("landscape-rotate")
	editor._finish_close(); await frames(3); pause.close(); game.queue_free(); await frames(2)
	print("MOBILE SELECTED GIZMO: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
