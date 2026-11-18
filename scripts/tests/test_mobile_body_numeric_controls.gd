extends "res://scripts/tests/test_mobile_pose_controls.gd"
## Expanded body authoring bounds, native numeric input, per-key persistence,
## unchanged imports, physical caps and mobile viewport fit. Reuses UI helpers.
const Body = preload("res://scripts/stroke_body_pose.gd")
const BodyKey = preload("res://scripts/stroke_body_keyframe.gd")
const Fields = preload("res://scripts/ui/mobile_pose_fields.gd")
const GripStore = preload("res://scripts/mobile_paddle_grip_store.gd")
const ViewSettings = preload("res://scripts/mobile_pose_view_settings.gd")

func descriptor(field: String) -> Dictionary: return Fields.body_descriptor(field)
func enter(field: String, axis: int, text: String) -> void:
	var key: String = field + ("" if axis < 0 else ":" + str(axis))
	check(editor._body_inputs.has(key), "numeric input exists: " + key)
	if not editor._body_inputs.has(key): return
	var line: LineEdit = editor._body_inputs[key].get_line_edit()
	line.text = text; line.text_submitted.emit(text)
func endpoints() -> Array:
	var result: Array = []
	for stage in range(3): result.append(ServeStore.endpoint(editor._current, stage) if editor._serve else Path.endpoint(editor._current, stage))
	return result
func same_field(a: Resource, b: Resource, field: String) -> bool:
	return a.get(field).is_equal_approx(b.get(field)) if a.get(field) is Vector3 else is_equal_approx(float(a.get(field)), float(b.get(field)))
func check_other_keys(before: Array, selected: int) -> void:
	var after := endpoints()
	for stage in range(3):
		if stage == selected: continue
		for field in BodyKey.FIELDS + editor.POS + editor.ROT:
			check(same_field(before[stage], after[stage], field), "stage %d body edit preserves other key %d field %s" % [selected, stage, field])
func body_group(group: int) -> void:
	editor._group.select(group); editor._build_fields()

func run() -> void:
	create_timer(180, true).timeout.connect(func(): quit(2))
	output = "/workspace/scratch/6b6e64f75bd2/verification/body-numeric-controls"
	DirAccess.make_dir_recursive_absolute(output)
	var isolated := "user://pose_store_tests/body_numeric_%d_%d/" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(Store.set_test_path(isolated + "poses.json") == OK, "isolated pose save")
	check(ServeStore.set_test_path(isolated + "serves.json") == OK, "isolated serve save")
	check(GripStore.set_test_path(isolated + "grips.json") == OK, "isolated grip save")
	check(ViewSettings.set_test_path(isolated + "view.json") == OK, "isolated view settings")
	for group in range(4):
		for d in Fields.fields(group, false):
			if d.type == "option": continue
			check(Store._valid_number(d.field, d.min) and Store._valid_number(d.field, d.max), "every new input endpoint is saveable: " + d.field)
			check(is_nan(Fields.body_input_value(d, NAN)) and is_nan(Fields.body_input_value(d, INF)), "every input rejects nonfinite: " + d.field)
			check(Fields.body_input_value(d, -1e12) >= d.min and Fields.body_input_value(d, 1e12) <= d.max, "extreme finite input remains bounded: " + d.field)
	root.size = Vector2i(432, 936); root.content_scale_size = Vector2i(720, 1560)
	pause = root.get_node("PauseController")
	if capture:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	await frames(4); pause.open(); game.open_mobile_pose_editor(); await frames(4); editor = game.mobile_pose_editor
	for id in [10, 20]:
		select_id(id)
		var original: String = Store.export_pose_json(editor._current)
		for group in range(4):
			body_group(group)
			for stage in range(3): editor._select_stage(stage)
		check(Store.export_pose_json(editor._current) == original and not editor._dirty.has(editor._key), "viewing every body field preserves exact imported pose %d" % id)
	select_id(0); body_group(0); editor._select_stage(1)
	# Legacy values outside the new editing envelope are displayed without edits.
	editor._current.body_pitch_deg = 88.125
	editor._build_fields()
	check(is_equal_approx(editor._edit.body_pitch_deg, 88.125) and is_equal_approx(editor._body_inputs.body_pitch_deg.value, 88.125), "opening legacy out-of-range body value never clamps it")
	editor._toggle_fine(); editor._toggle_fine()
	check(is_equal_approx(editor._current.body_pitch_deg, 88.125), "Fine/Normal never normalizes a legacy value")
	var original: String = Store.export_pose_json(editor._current)
	enter("body_yaw_deg", -1, "NaN")
	enter("body_yaw_deg", -1, "1e999")
	enter("body_yaw_deg", -1, "invalid")
	editor._changed("body_position_offset", Vector3(NAN, 0, 0))
	check(Store.export_pose_json(editor._current) == original, "nonfinite/invalid typing keeps all authored data")
	enter("body_yaw_deg", -1, "-1081.5")
	check(is_equal_approx(editor._edit.body_yaw_deg, -1.5), "negative whole body turns wrap")
	enter("body_yaw_deg", -1, "10080.25")
	check(is_equal_approx(editor._edit.body_yaw_deg, .25), "large positive whole body turns wrap")
	enter("body_pitch_deg", -1, "99999")
	check(is_equal_approx(editor._edit.body_pitch_deg, 75), "anatomical lean clamps to wider maximum")
	enter("body_roll_deg", -1, "-99999")
	check(is_equal_approx(editor._edit.body_roll_deg, -60), "negative anatomical lean clamps")
	enter("crouch_amount", -1, "-123")
	check(is_zero_approx(editor._edit.crouch_amount), "negative crouch clamps to zero")
	enter("shoulder_protraction_m", -1, ".9")
	check(is_equal_approx(editor._edit.shoulder_protraction_m, .05), "shoulder protraction follows real rig limit")
	body_group(1); enter("right_foot_yaw_deg", -1, "721.125")
	check(is_equal_approx(editor._edit.right_foot_yaw_deg, 1.125), "foot yaw wraps with precise typed decimals")
	body_group(2); enter("right_shoulder_rotation_deg", 1, "-721.25")
	check(is_equal_approx(editor._edit.right_shoulder_rotation_deg.y, -1.25), "shoulder guide wraps")
	body_group(3); enter("head_pitch_deg", -1, "-9999")
	check(is_equal_approx(editor._edit.head_pitch_deg, -80), "head tilt clamps")
	editor._revert_current(); body_group(0)
	for workspace in [0, 2]:
		editor._select_workspace(workspace)
		if workspace == 0: select_id(0)
		else: editor._select_pose(0)
		body_group(0)
		var expected: Array = []
		for stage in range(3):
			editor._select_stage(stage)
			var before := endpoints()
			var fixed: Transform3D = editor._preview.player.paddle_node.global_transform
			var request := Vector3([1.2345, -1.1234, .8765][stage], [-.625, -.725, .625][stage], [-.85, 1.25, -1.35][stage])
			for axis in range(3): enter("body_position_offset", axis, str(request[axis]))
			check(editor._edit.body_position_offset.is_equal_approx(request), "requested larger XYZ survives reach cap stage%d workspace%d" % [stage, workspace])
			check(editor._preview.player.paddle_node.global_transform.is_equal_approx(fixed), "body XYZ never moves fixed paddle target")
			var report: Dictionary = Body.position_report(editor._preview.player, editor._preview.pose)
			check(report.limited and report.requested.is_equal_approx(request), "physical cap reports requested versus applied")
			check(editor._body_position_status.text.contains("Requested XYZ") and editor._body_position_status.text.contains("Applied XYZ") and editor._body_position_status.text.contains("kept"), "body cap visible and honest")
			check_other_keys(before, stage)
			enter("hip_yaw_deg", -1, str([115, -110, 105][stage]))
			enter("body_pitch_deg", -1, str([65, -60, 55][stage]))
			enter("weight_shift", -1, str([1.75, -1.65, 1.55][stage]))
			expected.append(endpoints()[stage])
			check_other_keys(before, stage)
			check(editor._preview.player.body_pivot.global_transform.is_finite(), "expanded authored body remains finite")
			for leg in [editor._preview.player.right_leg_node, editor._preview.player.left_leg_node]:
				var lowest := INF
				for corner in range(8): lowest = minf(lowest, (leg.foot_mesh.global_transform * leg.foot_mesh.mesh.get_aabb().get_endpoint(corner)).y)
				check(lowest >= PickleballConstants.FLOOR_Y - .0001, "expanded body never pushes visible sole through floor")
		var exported: Dictionary = JSON.parse_string(ServeStore.export_pose_json(editor._current) if workspace == 2 else Store.export_pose_json(editor._current))
		check(Store._valid_fields(exported.fields, false), "expanded pose export remains validator compatible")
		editor._save_current(); check(not editor._dirty.has(editor._key), "expanded controls save without dropping values")
		var fresh: Resource
		if workspace == 2:
			ServeStore.set_test_path(ServeStore.storage_path()); fresh = ServeStore.get_def(0)
		else: fresh = PostureLibrary.new().get_def(0)
		for stage in range(3):
			var restored: Resource = ServeStore.endpoint(fresh, stage) if workspace == 2 else Path.endpoint(fresh, stage)
			for field in ["body_position_offset", "hip_yaw_deg", "body_pitch_deg", "weight_shift"]:
				check(same_field(restored, expected[stage], field), "wide value reloads exactly stage%d %s" % [stage, field])
		if workspace == 2:
			editor._joint_chosen("right_foot")
			for stage in [1, 2]:
				editor._select_stage(stage); check(not editor._body_inputs.has("right_foot_yaw_deg") and not editor._body_inputs.has("right_foot_offset:0"), "numeric entry cannot bypass planted serve foot locks")
			var first: PostureDefinition = ServeStore.sample(editor._current, 0)
			for t in [0.0, .25, .5, .75, 1.0]:
				var pose: PostureDefinition = ServeStore.sample(editor._current, t)
				for field in ServeStore.PLANTED_FIELDS: check(same_field(first, pose, field), "serve body editing retains planted stance across playback")
	editor._select_workspace(1); editor._select_pose(0); body_group(0)
	enter("body_pitch_deg", -1, "70.125"); enter("weight_shift", -1, "-1.875")
	check(not editor._has_motion() and editor._stage == 1, "body stance remains static with numeric controls")
	editor._save_current()
	var static_pose: Resource = BasePoseLibrary.new().get_def(editor._current.base_pose_id)
	check(is_equal_approx(static_pose.body_pitch_deg, 70.125) and is_equal_approx(static_pose.weight_shift, -1.875), "static body stance saves expanded numeric edits")
	# All typed controls must fit the scroll viewport in phone-like orientations.
	editor._select_workspace(2); editor._select_pose(0); editor._select_stage(1); body_group(0)
	for geometry in [[Vector2i(432,936),Vector2i(720,1560),"portrait"],[Vector2i(432,760),Vector2i(720,1267),"short-portrait"],[Vector2i(936,432),Vector2i(1560,720),"landscape"]]:
		root.size = geometry[0]; root.content_scale_size = geometry[1]; editor._layout(); await frames(5)
		for group in range(4):
			body_group(group); await frames(3)
			for key in editor._body_inputs:
				var control: SpinBox = editor._body_inputs[key]
				var rect: Rect2 = control.get_global_rect(); var scroll: Rect2 = editor._scroll.get_global_rect()
				check(rect.size.x >= 100 * editor._s and rect.end.x <= scroll.end.x + .1, "%s numeric input fits width %s" % [geometry[2], key])
		body_group(0); await frames(3); editor._scroll.ensure_control_visible(editor._body_inputs.crouch_amount)
		await snapshot(str(geometry[2]) + "-body-numbers")
		editor._joint_chosen("hips"); await frames(3); editor._scroll.ensure_control_visible(editor._body_inputs["body_position_offset:0"])
		await snapshot(str(geometry[2]) + "-body-xyz")
	var controls: Array[WeakRef] = []
	for node in editor._root.find_children("*", "SpinBox", true, false): controls.append(weakref(node))
	editor._finish_close(); await frames(3)
	for control in controls: check(control.get_ref() == null, "closing editor frees body numeric controls")
	paused = false; game.queue_free(); await frames(3)
	print("MOBILE BODY NUMERIC CONTROLS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
