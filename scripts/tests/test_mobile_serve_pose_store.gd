extends SceneTree
## Isolated persistence and live, generated-curve parity for all seven serves.
const Store = preload("res://scripts/mobile_serve_pose_store.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Preview = preload("res://scripts/posture_editor_v2/runtime_motion_preview.gd")
const Styles = preload("res://scripts/serve_style.gd")
const PoseStore = preload("res://scripts/mobile_pose_store.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
var checks := 0
var failures: Array[String] = []
var test_path := ""
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func same(a: PostureDefinition, b: PostureDefinition, label: String) -> void:
	for field in Store.allowed_fields(0) + Store.allowed_fields(1) + Store.PADDLE_FIELDS:
		check(Store._same(a.get(field), b.get(field)), label + ": " + field)
func run() -> void:
	var child := false
	var test_id := str(OS.get_process_id())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--serve-store-id="): test_id = arg.trim_prefix("--serve-store-id="); child = true
	test_path = "user://pose_store_tests/serve_%s/serves.json" % test_id
	check(Store.set_test_path(test_path) == OK, "isolated save path")
	if child:
		for style in range(7):
			var live: PostureDefinition = Store.get_def(style)
			check(is_equal_approx(live.body_yaw_deg, Store.get_default(style).body_yaw_deg + 7.0), "independent process loads saved contact")
			check(is_equal_approx(live.windup_body.values.torso_yaw_deg, Store.get_default(style).windup_body.values.torso_yaw_deg + 6.0), "independent process loads wind-up")
			check(is_equal_approx(live.follow_through_body.values.main_grip_rotation_deg, Store.get_default(style).follow_through_body.values.main_grip_rotation_deg + 8.0), "independent process loads finish grip")
			check(is_equal_approx(live.windup_body.values.right_foot_offset.x, Store.get_default(style).windup_body.values.right_foot_offset.x + 0.025), "independent process loads planted foot offset")
		_finish(); return
	DirAccess.remove_absolute(test_path)
	check(Store.set_test_path(Store.DEFAULT_PATH) == ERR_INVALID_PARAMETER, "cannot use production save for tests")
	check(Store.set_test_path("user://pose_store_tests/../bad.json") == ERR_INVALID_PARAMETER, "reject path traversal")
	var cold: PostureDefinition = Motion.serve_style_preparation(0, 0.5, Styles.hold_offset(0))
	check(cold != null and Store._defaults.size() == 1 and Store._live.size() == 1 and Store._live.has(0), "fresh startup activates approved Flat only")
	check(Store.all_definitions().size() == 7, "seven serve styles")
	for style in range(7):
		var original: PostureDefinition = Store.get_default(style)
		check(Store.style_id(original) == style, "identity and style metadata")
		check(Store.save(original) == OK, "default fits safe schema: " + Store.last_error)
		for charge in [0.0, 0.5, 1.0]:
			for t in [0.0, 0.2, 0.49, 0.5, 0.7, 1.0]:
				same(Preview.sample_serve(style, t, charge), Preview.sample_serve(style, t, charge, 1.0, original if style == 0 else null, false), "unmodified serve baseline parity")
		var edit: PostureDefinition = original.duplicate(true)
		edit.body_yaw_deg += 7.0
		edit.right_knee_pole.y += 0.02
		edit.windup_body.values.torso_yaw_deg += 6.0
		edit.windup_body.values.right_foot_offset.x += 0.025
		edit.charge_paddle_offset.x += 0.03
		edit.charge_paddle_rotation_deg.z += 5.0
		edit.follow_through_body.values.main_grip_rotation_deg += 8.0
		edit.follow_through_body.values.left_hand_offset.y += 0.04
		edit.ft_paddle_offset.y += 0.06
		check(Store.save(edit) == OK, "save all three authored serve keys: " + Store.last_error)
		check(is_equal_approx(Store.get_def(style).body_yaw_deg, original.body_yaw_deg), "save alone never publishes")
		var identifier: int = Store.get_def(style).get_instance_id()
		check(Store.copy_values(edit, Store.get_def(style)) == OK, "publish into shared live resource")
		check(Store.get_def(style).get_instance_id() == identifier, "live identity preserved")
		check(Store.get_def(style).windup_body != edit.windup_body, "nested keys detached")
		for t in [0.0, 0.17, 0.49, 0.5, 0.8, 1.0]:
			same(Store.sample(edit, t), Preview.sample_serve(style, t, 1.0), "unsaved preview and saved live sampler parity")
		var prep: PostureDefinition = Store.sample(edit, 0.0)
		var raw_prep: PostureDefinition = Preview.sample_serve(style, 0.0, 1.0, 1.0, original, false)
		check(is_equal_approx(prep.paddle_forehand_mul, raw_prep.paddle_forehand_mul + 0.03), "wind-up paddle delta applied")
		check(prep.right_foot_offset == Store.endpoint(edit, 0).right_foot_offset, "saved wind-up feet use planted stance")
		check(is_equal_approx(prep.torso_yaw_deg, raw_prep.torso_yaw_deg + 6.0), "wind-up body delta applied")
		check(prep.left_hand_offset == raw_prep.left_hand_offset and prep.left_elbow_pole == raw_prep.left_elbow_pole, "held support hand protected")
		var contact: PostureDefinition = Store.sample(edit, 0.5)
		var raw_contact: PostureDefinition = Preview.sample_serve(style, 0.5, 1.0, 1.0, original, false)
		for field in Store.PADDLE_FIELDS: check(contact.get(field) == raw_contact.get(field), "exact contact paddle alignment preserved")
		check(is_equal_approx(contact.body_yaw_deg, raw_contact.body_yaw_deg + 7.0), "contact body applied")
		check(is_equal_approx(Store.sample(edit, 1.0).main_grip_rotation_deg, Store.sample(original, 1.0).main_grip_rotation_deg + 8.0), "finish grip applied")
		var json: String = Store.export_pose_json(edit, 2)
		var payload = JSON.parse_string(json)
		check(payload is Dictionary and payload.kind == "serve" and payload.id == style and payload.selected_stage == 2, "portable whole-serve export identity")
		check(payload.fields.windup_body.has("torso_yaw_deg") and payload.fields.follow_through_body.has("main_grip_rotation_deg"), "export contains all keyframes")
		check(not json.contains("user://") and not json.contains("res://") and not json.contains("mobile_serve_baseline"), "export data only")
		var invalid: PostureDefinition = edit.duplicate(true); invalid.paddle_y_offset += 0.1
		check(Store.save(invalid) == ERR_INVALID_DATA, "contact paddle position locked")
		invalid = edit.duplicate(true); invalid.windup_body.values.left_hand_offset.x += 0.1
		check(Store.save(invalid) == ERR_INVALID_DATA, "held ball support lock validated")
		invalid = edit.duplicate(true); invalid.body_yaw_deg = NAN
		check(Store.save(invalid) == ERR_INVALID_DATA, "non-finite edit rejected")
		invalid = edit.duplicate(true); invalid.windup_body.values["script"] = "res://scripts/player.gd"
		check(Store.save(invalid) == ERR_INVALID_DATA, "nested injection rejected")
		# Charge-scaled additive overlays retain baseline non-linear intermediate shape.
		var q := 0.4; var t := 0.62
		var raw: PostureDefinition = Preview.sample_serve(style, t, q, 1.0, original, false)
		var actual: PostureDefinition = Preview.sample_serve(style, t, q)
		var u: float = 1.0 - pow(1.0 - (t - 0.5) * 2.0, 2.0)
		if style != 0: check(is_equal_approx(actual.paddle_y_offset, raw.paddle_y_offset + 0.06 * u * lerpf(0.72, 1.0, q)), "preserves authored curve with scaled additive finish")
		else: check(is_equal_approx(actual.ft_duration_strike, raw.ft_duration_strike), "approved Flat curve preserves delivery timing")
	var good := FileAccess.get_file_as_string(test_path)
	var output: Array = []
	var result := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/tests/test_mobile_serve_pose_store.gd", "--", "--mobile-runtime", "--serve-store-id=" + test_id], output, true)
	check(result == 0, "fresh-process persistence: " + "".join(output))
	check(DirAccess.make_dir_absolute(test_path + ".tmp") == OK, "write-failure fixture")
	check(Store.save(Store.get_def(0)) != OK, "failed write reported")
	check(FileAccess.get_file_as_string(test_path) == good, "failed write preserves good bytes")
	DirAccess.remove_absolute(test_path + ".tmp")
	var f := FileAccess.open(test_path, FileAccess.WRITE); f.store_string("{malformed"); f.close()
	check(Store.save(Store.get_def(0)) == ERR_FILE_CORRUPT and FileAccess.get_file_as_string(test_path) == "{malformed", "corrupt file preserved on save")
	Store.set_test_path(test_path)
	same(Preview.sample_serve(0, 0.7, 1.0), Preview.sample_serve(0, 0.7, 1.0, 1.0, Store.get_default(0), false), "corrupt startup falls back to unedited defaults")
	f = FileAccess.open(test_path, FileAccess.WRITE); f.store_string(good); f.close()
	Store.set_test_path(test_path)
	check(Store.reset(Store.get_def(0)) == OK, "reset selected saved serve")
	check(Store.copy_values(Store.get_default(0), Store.get_def(0)) == OK, "publish exact packaged reset")
	for t in [0.0, 0.3, 0.5, 0.8, 1.0]: same(Preview.sample_serve(0, t, 1.0), Preview.sample_serve(0, t, 1.0, 1.0, Store.get_default(0), false), "reset restores unchanged baseline")
	check(is_equal_approx(Store.get_def(1).body_yaw_deg, Store.get_default(1).body_yaw_deg + 7.0), "reset leaves other serve saved")
	Store.set_test_path(test_path)
	check(is_equal_approx(Store.get_def(0).body_yaw_deg, Store.get_default(0).body_yaw_deg), "reset survives reload")
	DirAccess.remove_absolute(test_path)
	_finish()
func _finish() -> void:
	print("MOBILE SERVE POSE STORE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
