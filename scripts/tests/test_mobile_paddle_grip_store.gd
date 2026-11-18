extends SceneTree
## Main-grip presets, fixed-palm shaft spin, safe inheritance and restart coverage.
const Store = preload("res://scripts/mobile_paddle_grip_store.gd")
const PoseStore = preload("res://scripts/mobile_pose_store.gd")
const ServeStore = preload("res://scripts/mobile_serve_pose_store.gd")
const Styles = preload("res://scripts/paddle_grip_styles.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Grip = preload("res://scripts/paddle_grip_frame.gd")
const Wrist = preload("res://scripts/paddle_wrist_reach.gd")
const Size = preload("res://scripts/paddle_dimensions.gd")
var checks := 0
var failures: Array[String] = []
var directory := ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func run() -> void:
	var phase := "suite"
	var id := str(OS.get_process_id())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--grip-id="): id = arg.trim_prefix("--grip-id=")
		if arg.begins_with("--grip-phase="): phase = arg.trim_prefix("--grip-phase=")
	directory = "user://pose_store_tests/grip_" + id
	check(Store.set_test_path(directory + "/grips.json") == OK, "isolated global file")
	check(PoseStore.set_test_path(directory + "/poses.json") == OK, "isolated pose file")
	check(ServeStore.set_test_path(directory + "/serves.json") == OK, "isolated serve file")
	if phase != "suite":
		_restart_checks(phase); _finish(); return
	check(Store.set_test_path(Store.DEFAULT_PATH) == ERR_INVALID_PARAMETER, "test hook cannot overwrite real global grip")
	check(Store.set_test_path("user://pose_store_tests/../bad.json") == ERR_INVALID_PARAMETER, "test hook rejects traversal")
	check(not Store.has_global(), "installation begins with no global grip")
	var library := PostureLibrary.instance()
	var initial: PostureDefinition = library.get_def(20).duplicate(true)
	check(is_zero_approx(initial.paddle_in_hand_rotation_deg), "Ready remains authored by default")
	_math_checks(initial)
	var edited: PostureDefinition = library.get_def(0).duplicate(true)
	edited.torso_yaw_deg += 7.0
	edited.windup_body.values["torso_pitch_deg"] = 19.0
	Styles.apply_preset(edited, 2)
	check(PoseStore.save(edited) == OK, "pre-global pose saves")
	check(PoseStore.copy_values(edited, library.get_def(0)) == OK, "pre-global pose publishes")
	var pose_bytes := FileAccess.get_file_as_string(PoseStore.storage_path())
	var serve: PostureDefinition = ServeStore.get_def(0).duplicate(true)
	serve.windup_body.values["torso_yaw_deg"] += 5.0
	check(ServeStore.save(serve) == OK, "pre-global serve saves")
	check(ServeStore.copy_values(serve, ServeStore.get_def(0)) == OK, "pre-global serve publishes")
	var serve_bytes := FileAccess.get_file_as_string(ServeStore.storage_path())
	var chosen: PostureDefinition = initial.duplicate(true)
	Styles.apply_preset(chosen, 1)
	check(Store.set_global_from_pose(chosen) == OK, "explicit global action succeeds")
	check(FileAccess.get_file_as_string(PoseStore.storage_path()) == pose_bytes, "global does not rewrite whole-pose file")
	check(FileAccess.get_file_as_string(ServeStore.storage_path()) == serve_bytes, "global does not rewrite serve body file")
	check(library.get_def(0).torso_yaw_deg == edited.torso_yaw_deg and library.get_def(0).windup_body.values.torso_pitch_deg == 19.0, "saved body channels preserved")
	check(ServeStore.get_def(0).windup_body.values.torso_yaw_deg == serve.windup_body.values.torso_yaw_deg, "saved serve body preserved")
	_check_global_all(45.0)
	var local: PostureDefinition = library.get_def(0).duplicate(true)
	local.windup_body.values["paddle_in_hand_rotation_deg"] = Styles.spin_for_relative(Path.endpoint(local, 0), -45.0)
	check(PoseStore.save(local) == OK and PoseStore.copy_values(local, library.get_def(0)) == OK, "local stage override saves after global")
	check(_near(Styles.relative_rotation(Path.endpoint(library.get_def(0), 0)), -45.0), "wind-up override applies")
	check(_near(Styles.relative_rotation(Path.endpoint(library.get_def(0), 1)), 45.0) and _near(Styles.relative_rotation(Path.endpoint(library.get_def(0), 2)), 45.0), "other stages stay global")
	var serve_local: PostureDefinition = ServeStore.get_def(0).duplicate(true)
	serve_local.follow_through_body.values["paddle_in_hand_rotation_deg"] = Styles.spin_for_relative(Path.endpoint(serve_local, 2), 90.0)
	check(ServeStore.save(serve_local) == OK and ServeStore.copy_values(serve_local, ServeStore.get_def(0)) == OK, "serve stage override saves")
	_run_child("first", id)
	Styles.apply_preset(chosen, 0)
	check(Store.set_global_from_pose(chosen) == OK, "second global supersedes prior stage overrides")
	_check_global_all(0.0)
	check(Store.undo_global() == OK, "Undo restores previous global generation")
	check(_near(Styles.relative_rotation(Path.endpoint(library.get_def(0), 0)), -45.0), "Undo restores previous saved stroke override")
	check(_near(Styles.relative_rotation(Path.endpoint(ServeStore.get_def(0), 2)), 90.0), "Undo restores previous saved serve override")
	_run_child("first", id)
	check(Store.clear_global() == OK and not Store.has_global(), "global can be cleared explicitly")
	check(is_zero_approx(library.get_def(20).paddle_in_hand_rotation_deg), "clear restores raw unsaved Ready grip")
	check(Store.undo_global() == OK and _near(Store.global_rotation(), 45.0), "Undo clear restores global")
	var private_copy: PostureDefinition = library.get_def(1).duplicate(true)
	private_copy.torso_pitch_deg += 11.0
	var private_pitch := private_copy.torso_pitch_deg
	Styles.apply_preset(private_copy, 2)
	Store.refresh_copy_grips(private_copy)
	check(private_copy.torso_pitch_deg == private_pitch and _near(Styles.relative_rotation(private_copy), 45.0), "copy rebase preserves unsaved body edit")
	_legacy_checks()
	_corruption_checks(chosen)
	for name in ["grips.json", "poses.json", "serves.json"]: DirAccess.remove_absolute(directory + "/" + name)
	_finish()

func _math_checks(source: PostureDefinition) -> void:
	for hand in [0, 1]:
		for angle in [-170.0, -90.0, -20.0, 0.0, 45.0, 175.0]:
			var pose: PostureDefinition = source.duplicate(true)
			pose.paddle_hand = hand
			pose.right_hand_offset = Vector3(.011, .016, -.009)
			pose.left_hand_offset = Vector3(-.007, .012, .004)
			var before: Transform3D = Path.canonical_transform(pose)
			var palm_before: Basis = Grip.basis(before.basis, hand == 1, pose.main_grip_rotation_deg)
			var wrist_before: Vector3 = Wrist.wrist_world(before, pose)
			Styles.set_relative_rotation(pose, angle)
			var after: Transform3D = Path.canonical_transform(pose)
			var palm_after: Basis = Grip.basis(after.basis, hand == 1, pose.main_grip_rotation_deg - pose.paddle_in_hand_rotation_deg)
			check(palm_before.is_equal_approx(palm_after), "shaft spin preserves actual main palm basis")
			check(Wrist.wrist_world(after, pose).distance_to(wrist_before) < 0.000001, "shaft spin preserves actual anatomical wrist with off-axis hand offset")
			check(before.basis.y.distance_to(after.basis.y) < 0.000001, "shaft spin preserves shaft direction")
			check(Path.remove_in_hand_transform(after, pose).is_equal_approx(before), "capture inverts spin without double application")
			check(_near(Styles.relative_rotation(pose), angle), "relative grip target mirrors left hand")
		for preset in range(4):
			var pose: PostureDefinition = source.duplicate(true); pose.paddle_hand = hand
			Styles.apply_preset(pose, preset)
			check(Styles.preset_index(pose) == preset, "preset recognized for both dominant hands")

func _check_global_all(angle: float) -> void:
	var left_guard: PostureDefinition = preload("res://scripts/ready_guard_profile.gd").authored_guard(1)
	check(_near(Styles.relative_rotation(left_guard), angle), "left-handed Ready fallback inherits mirrored global")
	for def in PostureLibrary.instance().definitions + ServeStore.all_definitions():
		for stage in range(3):
			check(_near(Styles.relative_rotation(Path.endpoint(def, stage)), angle), "global includes every stroke/serve stage: %s %s" % [def.display_name, stage])
	for style in range(7):
		var def: PostureDefinition = ServeStore.get_def(style)
		var contact: PostureDefinition = ServeStore.sample(def, .5)
		var baseline: PostureDefinition = ServeStore.sample(ServeStore.packaged_default(style), .5)
		check(_near(contact.paddle_in_hand_rotation_deg, def.paddle_in_hand_rotation_deg), "serve contact shaft spin stays authored")
		check(_near(Styles.relative_rotation(contact), angle), "serve contact still applies desired relative grip")
		var face := preload("res://scripts/paddle_dimensions.gd").HEAD_OFFSET + Vector3.BACK * (preload("res://scripts/paddle_dimensions.gd").HEAD_HALF_THICKNESS + .0375)
		check((Path.canonical_transform(contact) * face).distance_to(Path.canonical_transform(baseline) * face) < .000002, "spun serve Contact pivots about the fixed ball")

func _restart_checks(_phase: String) -> void:
	check(Store.has_global() and _near(Store.global_rotation(), 45.0), "global survives independent process")
	var def: PostureDefinition = PostureLibrary.instance().get_def(0)
	check(_near(Styles.relative_rotation(Path.endpoint(def, 0)), -45.0), "local stroke override survives independent process")
	check(_near(Styles.relative_rotation(Path.endpoint(PostureLibrary.instance().get_def(1), 2)), 45.0), "nonlocal stroke inherits on restart")
	check(_near(Styles.relative_rotation(Path.endpoint(ServeStore.get_def(0), 2)), 90.0), "serve override survives independent process")
	check(_near(Styles.relative_rotation(Path.endpoint(ServeStore.get_def(1), 0)), 45.0), "unsaved serve inherits on restart")

func _legacy_checks() -> void:
	var def: Resource = PoseStore.packaged_default(0, false)
	var fields: Dictionary = PoseStore._encode_fields(def)
	fields.erase("paddle_in_hand_rotation_deg")
	check(PoseStore._valid_fields(fields, false), "old v1 whole-pose snapshots remain valid")
	fields.erase("stance_width")
	check(not PoseStore._valid_fields(fields, false), "old snapshot compatibility does not allow unrelated missing fields")

func _corruption_checks(chosen: PostureDefinition) -> void:
	var path := Store.storage_path()
	var good := FileAccess.get_file_as_string(path)
	check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "global write-failure fixture")
	var generation := Store.current_generation()
	check(Store.set_global_from_pose(chosen) != OK, "global write failure reports error")
	check(Store.current_generation() == generation and FileAccess.get_file_as_string(path) == good, "failed global leaves live state and file unchanged")
	DirAccess.remove_absolute(path + ".tmp")
	var pose_path := PoseStore.storage_path()
	var pose_bytes := FileAccess.get_file_as_string(pose_path)
	var broken := FileAccess.open(pose_path, FileAccess.WRITE); broken.store_string("{bad"); broken.close()
	check(Store.set_global_from_pose(chosen) == ERR_FILE_CORRUPT, "corrupt source poses block partial global publication")
	check(FileAccess.get_file_as_string(path) == good and Store.current_generation() == generation, "source failure preserves global file and active generation")
	broken = FileAccess.open(pose_path, FileAccess.WRITE); broken.store_string(pose_bytes); broken.close()
	for bytes in ["{bad", "[]", '{"version":1,"revision":1,"generation":1,"grip":{"main_rotation_deg":999},"previous":null}', " ".repeat(Store.MAX_FILE_BYTES + 1)]:
		var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(bytes); file.close()
		check(Store.set_global_from_pose(chosen) == ERR_FILE_CORRUPT, "malformed global blocks overwrite")
		check(FileAccess.get_file_as_string(path) == bytes, "malformed global remains byte-identical")
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(good); file.close()

func _run_child(phase: String, id: String) -> void:
	var output: Array = []
	var result := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/tests/test_mobile_paddle_grip_store.gd", "--", "--mobile-runtime", "--grip-phase=" + phase, "--grip-id=" + id], output, true)
	check(result == 0, "restart passed: " + "".join(output))
func _near(a: float, b: float) -> bool: return absf(wrapf(a-b, -180.0, 180.0)) < .001
func _finish() -> void:
	print("[MOBILE PADDLE GRIP STORE] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
