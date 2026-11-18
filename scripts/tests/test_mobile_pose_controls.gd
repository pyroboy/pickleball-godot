extends SceneTree
const Navigation = preload("res://scripts/tests/mobile_pose_test_navigation.gd")
## Focused usability/motion regression. All edits use an isolated synthetic save.
## Run headless, or use tools/check_mobile_pose_controls_render.gd for captures.
const Store = preload("res://scripts/mobile_pose_store.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const ServeStore = preload("res://scripts/mobile_serve_pose_store.gd")
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
var checks := 0
var failures: Array[String] = []
var game
var pause
var editor
var capture := false
var output := "/workspace/scratch/6b6e64f75bd2/verification/mobile-pose-controls"
var report: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count: int = 3) -> void:
	for i in range(count):
		await process_frame
		await physics_frame

func select_id(id: int) -> void:
	for index in range(editor._definitions.size()):
		if editor._definitions[index].posture_id == id:
			editor._select_pose(index)
			return
	check(false, "requested pose exists: %d" % id)

func snapshot(tag: String) -> void:
	editor._refresh_status()
	if capture: print("RENDER SNAPSHOT: " + tag)
	await frames(4)
	var bounds := root.get_visible_rect()
	var bar: VScrollBar = editor._scroll.get_v_scroll_bar()
	report[tag] = {
		"viewport": str(root.size), "canvas": str(bounds.size),
		"preview": str(editor._preview.get_global_rect()),
		"inspector": str(editor._scroll.get_global_rect()),
		"save": str(editor._save.get_global_rect()),
		"status": str(editor._status.get_global_rect()),
		"scrollbar_width": bar.size.x,
		"motion_rebuilds": editor._preview.motion_rebuild_count,
		"ghost_count": editor._preview.ghost_transforms.size(),
		"path_samples": editor._preview.sample_heads.size(),
	}
	check(bounds.encloses(editor._preview.get_global_rect()), tag + ": preview fits viewport")
	check(bounds.encloses(editor._scroll.get_global_rect()), tag + ": inspector fits viewport")
	check(bounds.encloses(editor._save.get_global_rect()), tag + ": save remains accessible")
	check(bounds.encloses(editor._status.get_global_rect()), tag + ": status remains accessible")
	check(editor._scroll.size.y >= 110.0 * editor._s, tag + ": inspector remains usable")
	check(bar.size.x >= 48.0 * editor._s, tag + ": scrollbar has enlarged touch width")
	if capture:
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output + "/" + tag + ".png")
		check(error == OK, tag + ": screenshot saved")

func run() -> void:
	create_timer(90, true).timeout.connect(func(): quit(2))
	DirAccess.make_dir_recursive_absolute(output)
	check(Store.set_test_path("user://pose_store_tests/controls_%d_%d/poses.json" % [OS.get_process_id(), Time.get_ticks_usec()]) == OK, "save is isolated")
	check(ServeStore.set_test_path("user://pose_store_tests/controls_serve_%d_%d/poses.json" % [OS.get_process_id(), Time.get_ticks_usec()]) == OK, "serve save is isolated")
	root.size = Vector2i(432, 936)
	root.content_scale_size = Vector2i(720, 1560)
	pause = root.get_node("PauseController")
	if capture:
		if root.focus_exited.is_connected(pause._on_window_focus_exited):
			root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered):
			root.focus_entered.disconnect(pause._on_window_focus_entered)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(4)
	var baseline: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	if capture: report.before_render = await render_sample()
	pause.open()
	game.open_mobile_pose_editor()
	await frames(4)
	editor = game.mobile_pose_editor
	check(is_instance_valid(editor), "editor opens")
	if not is_instance_valid(editor):
		quit(1)
		return
	check(editor._last_tick > 0 and is_instance_valid(editor._dialog), "editor initialization completed without interruption")
	check(editor._preview.has_method("set_motion"), "motion preview API available")
	if not editor._preview.has_method("set_motion"):
		quit(1)
		return
	select_id(0)
	editor._select_category(7)
	editor._build_fields()
	await frames()
	var stages: Array[String] = []
	for stage in editor._stages:
		stages.append(stage.text)
		check(stage.icon != null, stage.text + " has a real icon texture")
	check(stages == ["Wind-up", "Contact", "Finish"], "exactly three named authored keyframes")
	var icon_actions := ["Copy pose JSON", "Back", "Front", "Side", "Play", "Save pose", "Revert", "Default"]
	for caption in icon_actions:
		var found := false
		for node in editor._root.find_children("*", "Button", true, false):
			if node.text == caption:
				found = true
				check(node.icon != null, caption + " has a real icon texture")
		check(found, caption + " action remains present")
	check(is_instance_valid(editor._gizmo_mode) and is_instance_valid(editor._gizmo_show), "Move / Rotate and Show replace Reset view")
	var fields: Dictionary = {}
	for descriptor in editor.Fields.fields(4, false):
		fields[descriptor.field] = descriptor
	for field in ["paddle_forehand_mul", "paddle_y_offset", "paddle_forward_mul", "paddle_pitch_base_deg", "paddle_yaw_base_deg", "paddle_roll_base_deg", "support_grip_style", "paddle_floor_clearance", "paddle_pitch_signed_deg", "paddle_yaw_signed_deg", "paddle_roll_signed_deg"]:
		Navigation.select_field(editor, field)
		check(fields.has(field) and editor._sliders.has(field), "paddle slider exposed: " + field)
	for axis in ["pitch", "yaw", "roll"]:
		var field: String = "paddle_" + axis + "_sign_source"
		check(fields.has(field) and fields[field].type == "option", "signed paddle source selector exposed: " + field)
	check(editor._preview.ghost_transforms.size() == 3, "exactly three authored paddle ghosts")
	check(editor._preview.sample_heads.size() > 3, "connecting arc has intermediate sampled points")
	check(is_instance_valid(editor._preview.motion_root), "motion visuals belong to isolated preview")
	for stage in range(3):
		var sample_index: int = stage * (editor._preview.sample_heads.size() - 1) / 2
		var head: Vector3 = editor._preview.ghost_transforms[stage] * PaddleSize.HEAD_OFFSET
		check(head.distance_to(editor._preview.sample_heads[sample_index]) < .00001, "ghost %d head lies on the solved sampled path" % stage)
		var ghost: Node3D = editor._preview._ghosts[stage]
		check(not ghost.find_children("*", "MeshInstance3D", true, false).is_empty(), "ghost %d contains actual paddle geometry" % stage)
		check(ghost.find_children("*", "CollisionObject3D", true, false).is_empty(), "ghost %d has no live paddle collision body" % stage)
	var rebuilds: int = editor._preview.motion_rebuild_count
	var authored_before := Store.export_pose_json(editor._current)
	for progress in [0.0, .25, .5, .75, 1.0, .11, .89]:
		editor._scrub.value = progress
		check(editor._preview.motion_rebuild_count == rebuilds, "scrubbing %.2f reuses path geometry" % progress)
		check(Store.export_pose_json(editor._current) == authored_before, "scrubbing %.2f creates no authored keyframes" % progress)
	check(editor._phase.text == "Preview", "in-between progress is labelled as preview")
	editor._select_stage(1)
	check(editor._preview.motion_rebuild_count == rebuilds, "selecting authored stage reuses path geometry")
	editor._toggle_play()
	editor._last_tick -= 40000
	editor._process(0.0)
	check(editor._playing and editor._timeline.elapsed > 0 and editor._timeline.sample.phase.begins_with("Charging"), "play advances held-charge preview")
	check(editor._preview.motion_rebuild_count == rebuilds, "play does not regenerate the sampled arc")
	editor._stop()
	var live: Resource = PostureLibrary.instance().get_def(0)
	var live_before := Store.export_pose_json(live)
	editor._select_stage(0)
	Navigation.select_field(editor, "paddle_forehand_mul")
	var windup_before: float = editor._sliders.paddle_forehand_mul.value
	Navigation.select_field(editor, "paddle_forehand_mul")
	editor._sliders.paddle_forehand_mul.value = windup_before + .08
	check(editor._preview.motion_rebuild_count > rebuilds, "authored paddle edit rebuilds path")
	check(is_equal_approx(Path.endpoint(editor._current, 0).paddle_forehand_mul, windup_before + .08), "Wind-up paddle edit is stored in endpoint offset")
	check(Store.export_pose_json(live) == live_before, "unsaved paddle edit leaves live pose untouched")
	editor._select_stage(1)
	Navigation.select_field(editor, "support_grip_style")
	editor._sliders.support_grip_style.value = .4
	Navigation.select_field(editor, "paddle_floor_clearance")
	editor._sliders.paddle_floor_clearance.value = .09
	Navigation.select_field(editor, "paddle_pitch_signed_deg")
	editor._sliders.paddle_pitch_signed_deg.value = 13
	editor._changed("paddle_pitch_sign_source", 1)
	await snapshot("portrait-paddle-controls")
	editor._copy_current_pose()
	await frames()
	var data: Dictionary = JSON.parse_string(editor._copy_payload.substr(editor._copy_payload.find("{")))
	check(is_equal_approx(data.fields.support_grip_style, .4) and is_equal_approx(data.fields.paddle_floor_clearance, .09), "Copy includes added unsaved paddle controls")
	check(data.fields.paddle_pitch_signed_deg == 13 and data.fields.paddle_pitch_sign_source == 1, "Copy includes signed paddle rotation and source")
	check(not FileAccess.file_exists(Store.storage_path()), "Copy does not persist edits")
	check(editor._dirty.has(editor._key), "Copy leaves unsaved flag intact")
	check(root.get_visible_rect().encloses(editor._copy_box.get_global_rect()), "copy dialog fits portrait")
	if capture:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + "/portrait-copy-dialog.png")
	editor._hide_copy()
	editor._save_current()
	check(not editor._dirty.has(editor._key) and is_equal_approx(live.support_grip_style, .4), "Save applies added paddle control and clears dirty state")
	var reloaded: Resource = PostureLibrary.new().get_def(0)
	check(is_equal_approx(reloaded.support_grip_style, .4) and reloaded.paddle_pitch_signed_deg == 13, "added controls survive save reload")
	Navigation.select_field(editor, "support_grip_style")
	editor._sliders.support_grip_style.value = .6
	editor._request_revert()
	check(editor._dialog.visible, "Revert asks before discarding")
	editor._revert_current()
	check(is_equal_approx(editor._current.support_grip_style, .4) and not editor._dirty.has(editor._key), "Revert restores saved added control")
	editor._request_default()
	check(editor._dialog.visible, "Default asks before resetting")
	editor._reset_default()
	check(Store.export_pose_json(live) == live_before, "Default restores full packaged pose after added-control save")
	await test_joint_controls()
	await test_phase_ik()
	await test_displayed_geometry()
	await test_authored_elbow_path()
	await test_serve_workspace()
	await test_serve_foot_controls()
	await test_playback_and_contact()
	select_id(2)
	await snapshot("portrait-backhand-arc")
	root.size = Vector2i(432, 768)
	root.content_scale_size = Vector2i(720, 1280)
	await snapshot("short-portrait-backhand-arc")
	root.size = Vector2i(936, 432)
	root.content_scale_size = Vector2i(1560, 720)
	await snapshot("landscape-backhand-arc")
	editor._copy_current_pose()
	await frames()
	check(root.get_visible_rect().encloses(editor._copy_box.get_global_rect()), "copy dialog fits landscape")
	editor._hide_copy()
	root.size = Vector2i(432, 936)
	root.content_scale_size = Vector2i(720, 1560)
	select_id(20)
	await frames()
	check(not editor._stage_row.visible and editor._play.disabled and not editor._scrub.editable, "Ready20 is static with no motion controls")
	check(not editor._preview.motion_root.visible, "Ready20 hides motion ghosts and arc")
	editor._select_stage(0)
	editor._toggle_play()
	check(editor._stage == 1 and not editor._playing, "Ready20 cannot acquire a Wind-up or playback state")
	await snapshot("portrait-ready-static")
	editor._select_workspace(1)
	editor._select_category(1)
	editor._build_fields()
	await frames()
	check(not editor._stage_row.visible and editor._play.disabled and not editor._scrub.editable, "body stance is static")
	check(not editor._preview.motion_root.visible, "body stance hides motion ghosts and arc")
	await snapshot("portrait-body-static")
	editor._select_workspace(0)
	select_id(0)
	await frames()
	check(editor._preview.ghost_transforms.size() == 3, "returning from static stance restores three ghosts")
	if capture: print("RENDER: closing editor")
	editor._finish_close()
	await frames(5)
	if capture: print("RENDER: editor freed; resuming match")
	# Resume in the UI/process context, as a real button does. frames() ends in
	# physics_frame; unpausing there can hit Godot's SelfList active-body assertion.
	await process_frame
	pause.close()
	if capture: print("RENDER: pause.close returned")
	await frames(5)
	if capture: print("RENDER: match resumed")
	if capture: report.after_render = await render_sample()
	check(game.mobile_pose_editor == null, "editor frees on close")
	check(Performance.get_monitor(Performance.OBJECT_NODE_COUNT) <= baseline + 2, "closing motion editor returns to baseline node count")
	report.checks = checks
	report.failures = failures
	report.rendered = capture
	report.renderer = RenderingServer.get_video_adapter_name()
	var file := FileAccess.open(output + "/" + ("render" if capture else "headless") + "-controls-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	if capture: print("RENDER: freeing game")
	game.queue_free()
	await frames()
	print("MOBILE POSE CONTROLS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func test_phase_ik() -> void:
	editor._select_category(2)
	editor._select_stage(0)
	var exact_authored_elbow: Vector3 = editor._edit.right_elbow_pole
	editor._build_fields()
	check(editor._edit.right_elbow_pole == exact_authored_elbow, "viewing rounded controls preserves exact imported elbow values")
	check(editor._fine, "fine increment mode is enabled initially")
	var fine_step: float = editor._sliders["right_elbow_pole:1"].step
	editor._toggle_fine()
	check(is_equal_approx(editor._sliders["right_elbow_pole:1"].step, fine_step * 10.0), "normal elbow increments are ten times fine increments")
	editor._toggle_fine()
	check(is_equal_approx(editor._sliders["right_elbow_pole:1"].step, fine_step), "returning to fine mode restores precise increments")
	var expected: Array[Dictionary] = []
	for stage in range(3):
		expected.append({})
		editor._select_category(2)
		editor._select_stage(stage)
		for field in ["right_elbow_pole", "left_elbow_pole"]:
			Navigation.select_field(editor, field)
			var vector := Vector3(.06 + stage * .03, .09 + stage * .04, -.08 - stage * .02)
			for axis in range(3):
				move_slider_to(editor._sliders[field + ":" + str(axis)], vector[axis])
			expected[stage][field] = vector
		editor._select_category(4)
		editor._build_fields()
		for field in ["right_knee_pole", "left_knee_pole", "right_foot_offset", "left_foot_offset"]:
			Navigation.select_field(editor, field)
			var vector := Vector3(.03 + stage * .02, .02 + stage * .01, -.04 - stage * .03)
			for axis in range(3):
				move_slider_to(editor._sliders[field + ":" + str(axis)], vector[axis])
			expected[stage][field] = vector
		for field in ["right_foot_yaw_deg", "left_foot_yaw_deg"]:
			Navigation.select_field(editor, field)
			var angle: float = 11.2 + stage * 8.3
			move_slider_to(editor._sliders[field], angle)
			expected[stage][field] = angle
		for field in expected[stage]:
			var value = Path.endpoint(editor._current, stage).get(field)
			check(value.is_equal_approx(expected[stage][field]) if value is Vector3 else is_equal_approx(value, expected[stage][field]), "phase %d stores independent %s" % [stage, field])
	editor._select_stage(0)
	var saved_endpoint: Resource = Path.endpoint(PostureLibrary.instance().get_def(0), 0)
	var retained_y: float = editor._edit.right_foot_offset.y
	Navigation.select_field(editor, "right_foot_offset")
	editor._reset_field("right_foot_offset", 0)
	check(is_equal_approx(editor._edit.right_foot_offset.x, saved_endpoint.right_foot_offset.x) and is_equal_approx(editor._edit.right_foot_offset.y, retained_y), "per-axis reset restores only selected saved foot component")
	editor._sliders["right_foot_offset:0"].value = expected[0].right_foot_offset.x
	editor._reset_field("right_foot_yaw_deg", -1)
	check(is_equal_approx(editor._edit.right_foot_yaw_deg, saved_endpoint.right_foot_yaw_deg), "scalar reset restores saved foot angle")
	Navigation.select_field(editor, "right_foot_yaw_deg")
	editor._sliders.right_foot_yaw_deg.value = expected[0].right_foot_yaw_deg
	editor._save_current()
	var fresh: Resource = PostureLibrary.new().get_def(0)
	var encoded: Dictionary = JSON.parse_string(Store.export_pose_json(fresh))
	for stage in range(3):
		var from_disk: Resource = Path.endpoint(fresh, stage)
		var live_endpoint: Resource = Path.endpoint(PostureLibrary.instance().get_def(0), stage)
		var json_fields: Dictionary = encoded.fields.windup_body if stage == 0 else encoded.fields.follow_through_body if stage == 2 else encoded.fields
		for field in expected[stage]:
			var value = from_disk.get(field)
			check(value.is_equal_approx(expected[stage][field]) if value is Vector3 else is_equal_approx(value, expected[stage][field]), "phase %d reloads saved %s" % [stage, field])
			value = live_endpoint.get(field)
			check(value.is_equal_approx(expected[stage][field]) if value is Vector3 else is_equal_approx(value, expected[stage][field]), "phase %d publishes runtime %s" % [stage, field])
			var json_value = json_fields[field]
			check(Vector3(json_value[0], json_value[1], json_value[2]).is_equal_approx(expected[stage][field]) if value is Vector3 else is_equal_approx(json_value, expected[stage][field]), "phase %d exports distinct %s" % [stage, field])
	editor._copies.erase(editor._key)
	editor._select_pose(editor._pose_picker.selected)
	editor._select_stage(2)
	Navigation.select_field(editor, "right_knee_pole")
	check(editor._edit.right_foot_offset.is_equal_approx(expected[2].right_foot_offset), "reselecting pose preserves saved phase foot edit")
	for node in editor._fields.get_children():
		if node is Button and node.text.begins_with("Right knee"):
			node.button_pressed = true
	await frames()
	editor._scroll.ensure_control_visible(editor._sliders["right_knee_pole:1"])
	await snapshot("portrait-fine-knee-controls")
	editor._select_category(2)
	editor._build_fields()
	for node in editor._fields.get_children():
		if node is Button and node.text.begins_with("Right elbow"):
			node.button_pressed = true
	await frames()
	editor._scroll.ensure_control_visible(editor._sliders["right_elbow_pole:1"])
	await snapshot("portrait-fine-elbow-controls")
	editor._request_default()
	editor._reset_default()
	editor._select_category(7)
	editor._build_fields()


func test_joint_controls() -> void:
	check(editor._joint_picker.item_count >= editor.Fields.JOINT_IDS.size(), "joint dropdown lists all supported targets")
	for index in range(editor.Fields.JOINT_IDS.size()):
		var id: String = editor.Fields.JOINT_IDS[index]
		var choice := -1
		for item in range(editor._joint_picker.item_count):
			if editor._joint_picker.get_item_text(item) == editor.Fields.JOINT_LABELS[index]:
				choice = item
		check(choice >= 0, "joint has a readable dropdown choice: " + id)
		if choice < 0: continue
		editor._joint_picker.select(choice)
		editor._joint_picker.item_selected.emit(choice)
		check(editor._selected_joint == id and editor._category.selected == editor.Fields.category_for_joint(id) and editor._category.visible, "joint selection routes to visible body-part category: " + id)
		check(editor._preview.selected_joint == id, "joint dropdown highlights the selected body point: " + id)
		for descriptor in editor.Fields.joint_fields(id, false):
			Navigation.select_field(editor, descriptor.field)
			if descriptor.type == "vector":
				for axis in range(3):
					check(editor._sliders.has(descriptor.field + ":" + str(axis)), "joint " + id + " exposes XYZ " + descriptor.field)
			elif descriptor.type == "float":
				check(editor._sliders.has(descriptor.field), "joint " + id + " exposes scalar " + descriptor.field)
	editor._joint_chosen("right_elbow")
	Navigation.reveal_field(editor, "right_elbow_pole")
	await frames()
	check(editor._sliders["right_elbow_pole:1"].is_visible_in_tree(), "joint category exposes vector controls when expanded")
	await snapshot("portrait-joint-elbow-controls")
	editor._select_stage(0)
	editor._sliders["right_elbow_pole:1"].value = .137
	check(is_equal_approx(Path.endpoint(editor._current, 0).right_elbow_pole.y, .137), "joint dropdown controls edit selected Wind-up endpoint")
	editor._reset_field("right_elbow_pole", 1)
	editor._request_revert()
	editor._revert_current()
	editor._joint_chosen("paddle")
	await frames()
	Navigation.select_field(editor, "main_grip_rotation_deg")
	var grip: String = ("left_hand_offset" if editor._current.paddle_hand == 1 else "right_hand_offset") + ":1"
	check(editor._sliders.has(grip), "paddle controls include main grip slide along handle")
	var rebuilds: int = editor._preview.motion_rebuild_count
	editor._preview.view("side")
	editor._preview.zoom(-.2)
	check(editor._preview.motion_rebuild_count == rebuilds, "camera orbit and zoom reuse path geometry")
	editor._preview.view("reset")
	editor._select_category(7)
	editor._build_fields()


func render_sample() -> Dictionary:
	var draws: Array = []
	var objects: Array = []
	for frame in range(40):
		await process_frame
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	draws.sort()
	objects.sort()
	var meshes := 0
	var shaders: Dictionary = {}
	for node in game.find_children("*", "MeshInstance3D", true, false):
		meshes += 1
		if node.mesh:
			for surface in range(node.mesh.get_surface_count()):
				var material = node.get_active_material(surface)
				if material is ShaderMaterial and material.shader:
					shaders[material.shader.get_instance_id()] = true
	return {"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "mesh_nodes": meshes, "active_shader_resources": shaders.size(), "draw_calls_median": draws[20], "draw_calls_min": draws[0], "draw_calls_max": draws[-1], "render_objects_median": objects[20]}


func test_displayed_geometry() -> void:
	select_id(0)
	editor._select_category(1)
	editor._select_stage(1)
	Navigation.select_field(editor, "crouch_amount")
	editor._sliders.crouch_amount.value = .25
	var measures: Dictionary = {}
	for joint in ["right_elbow", "left_elbow", "right_knee", "left_knee"]:
		editor._joint_chosen(joint)
		var field: String = joint + "_pole"
		editor._changed(field, Vector3(.35, .2, .3))
		var first: Vector3 = editor._preview.joint_world_position(joint)
		editor._changed(field, Vector3(-.35, -.2, .3))
		var second: Vector3 = editor._preview.joint_world_position(joint)
		measures[joint + "_movement_m"] = first.distance_to(second)
		check(first.is_finite() and second.is_finite() and first.distance_to(second) > .001, joint + " control changes the actual solved joint position")
	editor._joint_chosen("right_foot")
	var before: Vector3 = editor._preview.joint_world_position("right_foot")
	editor._sliders["right_foot_offset:0"].value += .08
	var after: Vector3 = editor._preview.joint_world_position("right_foot")
	measures.foot_movement_m = before.distance_to(after)
	check(before.distance_to(after) > .01, "foot placement moves displayed foot geometry")
	var foot: MeshInstance3D = editor._preview.player.right_leg_node.foot_mesh
	var floor_min := INF
	for corner in range(8):
		floor_min = minf(floor_min, (foot.global_transform * foot.mesh.get_aabb().get_endpoint(corner)).y)
	measures.foot_lowest_y = floor_min
	check(floor_min >= PickleballConstants.FLOOR_Y - .001, "foot placement respects visible shoe floor clearance")
	var foot_basis: Basis = foot.global_basis
	Navigation.select_field(editor, "right_foot_yaw_deg")
	editor._sliders.right_foot_yaw_deg.value += 18
	check(not foot.global_basis.is_equal_approx(foot_basis), "foot angle rotates the displayed shoe")
	editor._request_revert()
	editor._revert_current()
	editor._joint_chosen("paddle")
	editor._select_stage(1)
	# A close, reachable paddle fixture isolates grip rotation from reach limiting.
	Navigation.select_field(editor, "paddle_forehand_mul")
	editor._sliders.paddle_forehand_mul.value = .20
	Navigation.select_field(editor, "paddle_forward_mul")
	editor._sliders.paddle_forward_mul.value = .24
	Navigation.select_field(editor, "paddle_y_offset")
	editor._sliders.paddle_y_offset.value = .12
	Navigation.select_field(editor, "main_grip_rotation_deg")
	editor._sliders.main_grip_rotation_deg.value = 0
	var player = editor._preview.player
	var paddle_before: Transform3D = player.paddle_node.global_transform
	var hand_before: Basis = player.right_arm_node.hand_mesh.global_basis
	Navigation.select_field(editor, "main_grip_rotation_deg")
	editor._sliders.main_grip_rotation_deg.value = 25
	var paddle_after: Transform3D = player.paddle_node.global_transform
	var hand_after: Basis = player.right_arm_node.hand_mesh.global_basis
	measures.grip_paddle_anchor_delta_m = paddle_before.origin.distance_to(paddle_after.origin)
	check(paddle_before.is_equal_approx(paddle_after), "main grip rotation keeps the reachable paddle anchor and orientation fixed")
	check(not hand_before.is_equal_approx(hand_after), "main grip rotation turns actual hand mesh around handle")
	var grip: Vector3 = player.paddle_node.to_global(PaddleSize.MAIN_GRIP_OFFSET + editor._preview.pose.right_hand_offset)
	check(player.right_arm_node.hand_pivot.global_position.distance_to(grip) < .001, "rotated hand remains seated at virtual grip")
	var local_before: Vector3 = player.paddle_node.to_local(player.right_arm_node.hand_pivot.global_position)
	Navigation.select_field(editor, "right_hand_offset")
	editor._sliders["right_hand_offset:1"].value += .012
	var local_after: Vector3 = player.paddle_node.to_local(player.right_arm_node.hand_pivot.global_position)
	check(is_equal_approx(local_after.y - local_before.y, .012) and is_equal_approx(local_after.x, local_before.x) and is_equal_approx(local_after.z, local_before.z), "main grip slide moves actual hold along handle only")
	report.displayed_geometry = measures
	editor._request_revert()
	editor._revert_current()
	editor._select_category(7)
	editor._build_fields()

func test_authored_elbow_path() -> void:
	select_id(2)
	for stage in range(3):
		editor._joint_chosen("right_elbow")
		editor._select_stage(stage)
		var original: PackedVector3Array = editor._current.right_elbow_path.duplicate()
		check(original.size() == 63, "Backhand retains authorized smoothed63-point elbow route")
		var index: int = stage * (original.size() - 1) / 2
		var edited: Vector3 = original[index] + Vector3(.02, .01, -.01)
		editor._changed("right_elbow_pole", edited)
		check(editor._current.right_elbow_path.size() == original.size(), "stage edit preserves authored elbow path sample count")
		for other in range(original.size()):
			if other != index:
				check(editor._current.right_elbow_path[other].is_equal_approx(original[other]), "stage %d preserves unrelated elbow path knot %d" % [stage, other])
		check(Path.sample(editor._current, float(stage) * .5).right_elbow_pole.is_equal_approx(edited), "Backhand stage %d edit reaches actual sampler" % stage)
		check(editor._preview.pose.right_elbow_pole.is_equal_approx(edited), "Backhand stage %d edit reaches displayed solver" % stage)
	editor._request_revert()
	editor._revert_current()
	editor._select_category(7)
	editor._build_fields()


func test_serve_workspace() -> void:
	editor._select_workspace(2)
	check(editor._serve and editor._definitions.size() == 7, "Serves workspace contains seven actual serve styles")
	var shapes: Dictionary = {}
	for style in range(7):
		editor._select_pose(style)
		editor._select_category(1)
		editor._build_fields()
		check(editor._key == "serve:" + str(style), "serve workspace uses distinct style identity %d" % style)
		check(editor._preview.pose.get_meta("runtime_preview_serve", false) and editor._preview.pose.get_meta("preview_serve_style", -1) == style, "serve %d uses actual runtime serve sampler" % style)
		check(editor._preview.ghost_transforms.size() == 3 and editor._preview.sample_heads.size() > 3, "serve %d previews three paddle ghosts and sampled delivery arc" % style)
		shapes[str(editor._preview.ghost_transforms)] = true
		var rebuilds: int = editor._preview.motion_rebuild_count
		editor._scrub.value = .21
		check(editor._preview.motion_rebuild_count == rebuilds, "serve %d scrubbing reuses sampled path" % style)
		editor._select_stage(1)
	check(shapes.size() > 1, "serve styles have genuinely distinct generated motion")
	editor._select_pose(0)
	editor._select_category(1)
	editor._build_fields()
	var before: String = ServeStore.export_pose_json(ServeStore.get_def(0))
	var expected: Array[float] = []
	for stage in range(3):
		editor._select_stage(stage)
		Navigation.select_field(editor, "body_yaw_deg")
		var value: float = editor._sliders.body_yaw_deg.value + [3.0, 5.0, -4.0][stage]
		Navigation.select_field(editor, "body_yaw_deg")
		editor._sliders.body_yaw_deg.value = value
		expected.append(value)
		check(is_equal_approx(ServeStore.endpoint(editor._current, stage).body_yaw_deg, value), "serve stage %d stores independent body edit" % stage)
	check(ServeStore.export_pose_json(ServeStore.get_def(0)) == before, "unsaved serve edits stay private")
	editor._copy_current_pose()
	var document: Dictionary = JSON.parse_string(editor._copy_payload.substr(editor._copy_payload.find("{")))
	check(document.kind == "serve" and int(document.id) == 0 and document.scope == "whole_pose", "serve Copy identifies exact whole serve style")
	check(is_equal_approx(document.fields.body_yaw_deg, expected[1]) and is_equal_approx(document.fields.windup_body.body_yaw_deg, expected[0]) and is_equal_approx(document.fields.follow_through_body.body_yaw_deg, expected[2]), "serve Copy includes all unsaved stage edits")
	check(not FileAccess.file_exists(ServeStore.storage_path()), "serve Copy does not persist")
	editor._hide_copy()
	editor._save_current()
	check(not editor._dirty.has(editor._key), "serve Save commits valid edits")
	for stage in range(3):
		check(is_equal_approx(ServeStore.endpoint(ServeStore.get_def(0), stage).body_yaw_deg, expected[stage]), "serve Save publishes stage %d to runtime" % stage)
	var test_path: String = ServeStore.storage_path()
	ServeStore.set_test_path(test_path)
	for stage in range(3):
		check(is_equal_approx(ServeStore.endpoint(ServeStore.get_def(0), stage).body_yaw_deg, expected[stage]), "serve stage %d survives disk reload" % stage)
	editor._select_workspace(2)
	editor._select_category(1)
	editor._select_stage(1)
	Navigation.select_field(editor, "body_yaw_deg")
	editor._sliders.body_yaw_deg.value += 2
	editor._request_revert()
	check(editor._dialog.visible, "serve Revert asks before discard")
	editor._revert_current()
	check(is_equal_approx(editor._current.body_yaw_deg, expected[1]), "serve Revert restores saved edits")
	editor._select_stage(0)
	await snapshot("portrait-serve-windup")
	editor._select_stage(1)
	await snapshot("portrait-serve-contact")
	editor._select_stage(2)
	await snapshot("portrait-serve-finish")
	editor._request_default()
	check(editor._dialog.visible, "serve Default asks before reset")
	editor._reset_default()
	check(ServeStore.export_pose_json(ServeStore.get_def(0)) == before, "serve Default restores generated packaged motion")
	editor._select_workspace(0)
	editor._select_category(7)
	editor._build_fields()


func test_playback_and_contact() -> void:
	for workspace in [0, 2]:
		editor._select_workspace(workspace)
		editor._select_pose(0)
		editor._select_category(7)
		editor._build_fields()
		var tag: String = "serve" if workspace == 2 else "stroke"
		var helper = editor._preview.contact_preview
		check(is_instance_valid(helper) and helper.visible, tag + " has an isolated illustrative ball")
		check(helper.find_children("*", "CollisionObject3D", true, false).is_empty(), tag + " illustrative ball adds no live collision objects")
		var live_ball: Transform3D = game.ball.global_transform
		var live_paddle: Transform3D = game.player_left.paddle_node.global_transform
		var rebuilds: int = editor._preview.motion_rebuild_count
		editor._toggle_play()
		for tick in range(8):
			editor._last_tick -= 40000
			editor._process(0.0)
		var paused_progress: float = editor._progress
		editor._toggle_play()
		check(not editor._playing and editor._play.text == "Resume" and is_equal_approx(editor._progress, paused_progress), tag + " Pause preserves exact playback position")
		editor._last_tick -= 40000
		editor._process(0.0)
		check(is_equal_approx(editor._progress, paused_progress), tag + " paused playhead remains stationary")
		editor._toggle_play()
		check(editor._playing and is_equal_approx(editor._progress, paused_progress), tag + " Resume continues without a jump")
		var crossed_contact := false
		for tick in range(50):
			editor._last_tick -= 40000
			editor._process(0.0)
			if editor._progress > .5 and editor._progress < 1:
				crossed_contact = crossed_contact or editor._playing
			check(helper.ball.global_position.distance_to(helper.ball_position_at(ball_clock_progress())) < .00001, tag + " displayed ball tracks the current playhead")
		check(crossed_contact and is_equal_approx(editor._progress, 1) and not editor._playing, tag + " full swing plays continuously through Contact to Finish")
		check(editor._preview.motion_rebuild_count == rebuilds, tag + " full playback reuses ghost and path geometry")
		editor._select_stage(1)
		check(not editor._playing and is_equal_approx(editor._progress, .5), tag + " Contact button seeks and freezes exact contact")
		check(helper.ball.global_position.distance_to(helper.contact_point) < .00001, tag + " Contact ball meets solved paddle face")
		var head: Vector3 = editor._preview.player.paddle_node.global_transform * PaddleSize.HEAD_OFFSET
		check(is_equal_approx(head.distance_to(helper.ball.global_position), PaddleSize.HEAD_HALF_THICKNESS + Ball.BALL_RADIUS), tag + " ball radius touches paddle head at Contact")
		check(game.ball.global_transform == live_ball and game.player_left.paddle_node.global_transform == live_paddle, tag + " preview playback leaves paused match geometry unchanged")
		if editor._current.has_zone:
			var minimum_y: float = 0 if editor._current.height_tier == 0 else editor._current.zone_y_min
			var expected_size := Vector3(editor._current.zone_x_max - editor._current.zone_x_min, editor._current.zone_y_max - minimum_y, .15)
			check(helper.block.visible and helper.block.mesh.size.is_equal_approx(expected_size), tag + " preparation block uses authored bounds")
		await snapshot("portrait-" + tag + "-contact-ball")
	editor._select_workspace(0)
	editor._select_category(7)
	editor._build_fields()


func test_serve_foot_controls() -> void:
	editor._select_workspace(2)
	editor._select_pose(0)
	editor._joint_chosen("right_foot")
	for stage in [1, 2]:
		editor._select_stage(stage)
		check(not editor._sliders.has("right_foot_offset:0") and not editor._sliders.has("right_foot_yaw_deg"), "serve phase %d correctly locks planted foot placement and toe angle" % stage)
	var jump: Button = null
	for node in editor._fields.find_children("*", "Button", true, false):
		if node.text.begins_with("Edit Wind-up"): jump = node
	check(is_instance_valid(jump), "locked serve feet offer direct Wind-up edit action")
	if is_instance_valid(jump): jump.pressed.emit()
	check(editor._stage == 0 and editor._sliders.has("right_foot_offset:0") and editor._sliders.has("right_foot_yaw_deg"), "Edit Wind-up reveals initial serve stance controls")
	if editor._sliders.has("right_foot_offset:0"):
		editor._sliders["right_foot_offset:0"].value += .06
		var planted: Vector3 = editor._preview.joint_world_position("right_foot")
		for progress in [0.0, .25, .5, .75, 1.0]:
			editor._scrub.value = progress
			check(editor._preview.joint_world_position("right_foot").distance_to(planted) < .001, "serve %.2f retains edited initial foot plant" % progress)
	editor._request_revert()
	editor._revert_current()
	editor._select_workspace(0)
	editor._select_category(7)
	editor._build_fields()

func move_slider_to(slider: HSlider, value: float) -> void:
	# An imported .089759 request can display as .090. Setting that already
	# displayed value is not a user edit and correctly emits no value_changed.
	# Perform an actual away/back gesture before testing exact save semantics.
	slider.value = value + slider.step * 2.0
	slider.value = value

func ball_clock_progress() -> float:
	# Runtime playback eases the paddle separately. The illustrative ball is
	# driven by elapsed release/contact time, while authored scrub uses progress.
	var timeline = editor._timeline
	if not timeline.active: return editor._progress
	var sequence = timeline.sequence
	var local: float = clampf(timeline.elapsed - sequence.prefix_seconds, 0.0, sequence.stroke_seconds)
	if local <= sequence.release_seconds:
		return 0.5 * local / maxf(sequence.release_seconds, 0.001)
	return 0.5 + 0.5 * (local - sequence.release_seconds) / maxf(sequence.stroke_seconds - sequence.release_seconds, 0.001)
