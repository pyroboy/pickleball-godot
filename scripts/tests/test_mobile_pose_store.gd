extends SceneTree
## Isolated app-private persistence, corruption and fresh-process regressions.
## Run: godot --headless --path . --script res://scripts/tests/test_mobile_pose_store.gd -- --mobile-runtime
const Store = preload("res://scripts/mobile_pose_store.gd")
const BodyKeyframe = preload("res://scripts/stroke_body_keyframe.gd")
var checks := 0
var failures: Array[String] = []
var test_path := ""


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func run() -> void:
	var phase := "suite"
	var test_id := str(OS.get_process_id())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--store-phase="):
			phase = arg.trim_prefix("--store-phase=")
		if arg.begins_with("--store-id="):
			test_id = arg.trim_prefix("--store-id=")
	test_path = "user://pose_store_tests/%s/poses.json" % test_id
	check(Store.set_test_path(test_path) == OK, "test file isolated from real save")
	if not failures.is_empty():
		_finish()
		return
	if phase != "suite":
		_fresh_process_phase(phase)
		_finish()
		return
	check(Store.set_test_path(Store.DEFAULT_PATH) == ERR_INVALID_PARAMETER, "test path cannot target production file")
	check(Store.set_test_path("user://pose_store_tests/../mobile_pose_overrides_v1.json") == ERR_INVALID_PARAMETER, "test path rejects traversal")
	var strokes := PostureLibrary.new()
	var bases := BasePoseLibrary.new()
	check(strokes.definitions.size() == 21 and bases.definitions.size() == 22, "packaged taxonomy remains complete")
	for def in strokes.definitions + bases.definitions:
		check(Store.save(def) == OK, "every authored pose fits safe schema: " + def.display_name + " " + Store.last_error)
	_remove_test_file()
	var live: Resource = strokes.get_def(0)
	var original: Resource = live.duplicate(true)
	var changed: Resource = _changed_stroke(live)
	check(Store.save(changed) == OK, "stroke save succeeds")
	check(live.paddle_forehand_mul == original.paddle_forehand_mul, "save alone does not mutate live resources")
	var before_id := live.get_instance_id()
	check(Store.copy_values(changed, live) == OK and live.get_instance_id() == before_id, "publication preserves live reference identity")
	check(live.paddle_forehand_mul == 0.875, "publication applies edited values")
	check(live.windup_body != changed.windup_body, "publication deep-copies nested keyframe")
	var other: Resource = strokes.get_def(2).duplicate(true)
	other.body_yaw_deg = 19.0
	check(Store.save(other) == OK, "second stroke save succeeds")
	var base: Resource = bases.get_def(0).duplicate(true)
	base.stance_width = 0.77
	check(Store.save(base) == OK, "body pose save succeeds")
	var fresh := PostureLibrary.new()
	check(fresh.get_def(0).paddle_forehand_mul == 0.875 and fresh.get_def(0).left_hand_mode == 4, "library reload applies saved stroke")
	check(fresh.get_def(0).windup_body.values.right_elbow_pole == Vector3(0.25, -0.3, 0.4), "nested vectors round-trip safely")
	check(fresh.get_def(0).right_elbow_path == PackedVector3Array([Vector3(0.1, 0.2, 0.3)]), "authored elbow path round-trips")
	check(BasePoseLibrary.new().get_def(0).stance_width == 0.77, "base library reload applies saved body pose")
	var packaged: Resource = Store.packaged_default(0, false)
	check(packaged.paddle_forehand_mul == original.paddle_forehand_mul, "reset source ignores disk override")
	packaged.paddle_forehand_mul = -2.0
	check(Store.packaged_default(0, false).paddle_forehand_mul == original.paddle_forehand_mul, "packaged defaults are detached copies")
	check(Store.copy_values(changed, other) == ERR_INVALID_DATA, "publication rejects identity mismatch")
	var good_bytes := FileAccess.get_file_as_string(test_path)
	check(not good_bytes.contains("res://") and not good_bytes.contains("resource_path") and not good_bytes.contains("\"script\""), "saved payload contains data only")
	var invalid: Resource = changed.duplicate(true)
	invalid.paddle_forehand_mul = NAN
	check(Store.save(invalid) == ERR_INVALID_DATA, "save rejects nonfinite scalar")
	invalid = changed.duplicate(true)
	invalid.windup_body.values["script"] = "res://scripts/player.gd"
	check(Store.save(invalid) == ERR_INVALID_DATA, "save rejects unexpected nested properties")
	invalid = changed.duplicate(true)
	invalid.windup_body = Resource.new()
	check(Store.save(invalid) == ERR_INVALID_DATA, "save rejects arbitrary nested resources")
	check(FileAccess.get_file_as_string(test_path) == good_bytes, "invalid edits leave previous save byte-identical")
	# A directory occupying the temp filename is a deterministic ordinary write failure.
	check(DirAccess.make_dir_absolute(test_path + ".tmp") == OK, "write-failure fixture created")
	check(Store.save(changed) != OK and Store.reset(changed) != OK, "save and reset report file write failures")
	check(FileAccess.get_file_as_string(test_path) == good_bytes, "failed writes preserve the last good save")
	DirAccess.remove_absolute(test_path + ".tmp")
	_run_child("read", test_id)
	_run_child("reset", test_id)
	_run_child("after_reset", test_id)
	check(not JSON.parse_string(FileAccess.get_file_as_string(test_path)).postures.has("0"), "reset removes only the selected override")
	_test_malformed(good_bytes, original)
	var restored := FileAccess.open(test_path, FileAccess.WRITE)
	restored.store_string(good_bytes)
	restored.close()
	check(Store.reset(base) == OK, "base pose reset succeeds")
	check(BasePoseLibrary.new().get_def(0).stance_width == Store.packaged_default(0, true).stance_width, "base pose reset restores packaged values")
	check(PostureLibrary.new().get_def(0).paddle_forehand_mul == 0.875, "base pose reset preserves stroke overrides")
	check(Store.reset(base) == OK, "already-default reset is idempotent")
	var totals := {"pass": 0, "fail": 0, "errors": []}
	_remove_test_file()
	load("res://scripts/tests/test_base_pose_system.gd").new().run_all(totals)
	load("res://scripts/tests/test_posture_persistence.gd").new().run_all(totals)
	check(totals.fail == 0, "neighbor base-pose and posture-persistence suites: %s" % totals)
	_remove_test_file()
	_finish()


func _changed_stroke(source: Resource) -> Resource:
	var def: Resource = source.duplicate(true)
	def.paddle_forehand_mul = 0.875
	def.left_hand_mode = 4
	def.right_elbow_path = PackedVector3Array([Vector3(0.1, 0.2, 0.3)])
	var body := BodyKeyframe.new()
	body.values = {"stance_width": 0.6, "right_elbow_pole": Vector3(0.25, -0.3, 0.4), "support_index_closure": 0.3}
	def.windup_body = body
	return def


func _run_child(phase: String, test_id: String) -> void:
	var output: Array = []
	var result := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://scripts/tests/test_mobile_pose_store.gd", "--", "--mobile-runtime", "--store-phase=" + phase, "--store-id=" + test_id], output, true)
	check(result == 0, "fresh process " + phase + " passed: " + "".join(output))


func _fresh_process_phase(phase: String) -> void:
	var strokes := PostureLibrary.new()
	var bases := BasePoseLibrary.new()
	check(FileAccess.file_exists(test_path), "previous process left a save")
	check(strokes.get_def(2).body_yaw_deg == 19.0, "other stroke persists independently")
	check(bases.get_def(0).stance_width == 0.77, "base pose persists independently")
	if phase == "after_reset":
		check(strokes.get_def(0).paddle_forehand_mul == Store.packaged_default(0, false).paddle_forehand_mul, "selected stroke reset survives restart")
	else:
		check(strokes.get_def(0).paddle_forehand_mul == 0.875, "selected stroke survives independent startup")
		check(strokes.get_def(0).windup_body.values.stance_width == 0.6, "keyframe survives independent startup")
		if phase == "reset":
			check(Store.reset(strokes.get_def(0)) == OK, "selected reset persisted")


func _test_malformed(good_bytes: String, original: Resource) -> void:
	var bad_payloads: Array[String] = ["{malformed", "[]", "null", " ".repeat(Store.MAX_FILE_BYTES + 1)]
	for mutation in [
		["script", "res://scripts/player.gd"], ["resource_path", "res://data/postures/00_forehand.tres"],
		["posture_id", 1], ["display_name", "Renamed"], ["left_hand_mode", 4.5], ["paddle_hand", 2],
		["stance_width", -1.0], ["paddle_y_offset", 1e20], ["body_yaw_deg", 721.0],
		["head_track_ball_weight", 1.1], ["has_zone", 1], ["weight_shift", "1.0"],
		["right_hand_offset", [1, 2]], ["right_hand_offset", [1, "2", 3]], ["right_hand_offset", [1, 2, 6]],
		["windup_body", {"script": "res://scripts/player.gd"}], ["windup_body", {"left_hand_mode": 99}],
		["windup_body", {"windup_body": {}}], ["windup_body", []],
		["right_elbow_path", [[0, 0, 0], [0, INF, 0]]], ["zone_x_min", 4.0],
	]:
		var document: Dictionary = JSON.parse_string(good_bytes)
		document.postures["0"][mutation[0]] = mutation[1]
		bad_payloads.append(JSON.stringify(document))
	for bad_id in ["-1", "21", "001", "../0", "1.5"]:
		var document: Dictionary = JSON.parse_string(good_bytes)
		document.postures[bad_id] = document.postures["0"]
		bad_payloads.append(JSON.stringify(document))
	var bad_version: Dictionary = JSON.parse_string(good_bytes)
	bad_version.version = 2
	bad_payloads.append(JSON.stringify(bad_version))
	var extra_root: Dictionary = JSON.parse_string(good_bytes)
	extra_root.script = "res://scripts/player.gd"
	bad_payloads.append(JSON.stringify(extra_root))
	var invalid_base: Dictionary = JSON.parse_string(good_bytes)
	invalid_base.base_poses["22"] = invalid_base.base_poses["0"]
	bad_payloads.append(JSON.stringify(invalid_base))
	var excessive_path: Dictionary = JSON.parse_string(good_bytes)
	excessive_path.postures["0"].right_elbow_path = []
	for i in range(Store.MAX_PATH_POINTS + 1):
		excessive_path.postures["0"].right_elbow_path.append([0, 0, 0])
	bad_payloads.append(JSON.stringify(excessive_path))
	var partial: Dictionary = JSON.parse_string(good_bytes)
	partial.postures["0"] = {"zone_x_min": 4.0}
	bad_payloads.append(JSON.stringify(partial))
	bad_payloads.append(good_bytes.replace('"paddle_forehand_mul": 0.875', '"paddle_forehand_mul": 1e400'))
	for index in range(bad_payloads.size()):
		var file := FileAccess.open(test_path, FileAccess.WRITE)
		file.store_string(bad_payloads[index])
		file.close()
		var fresh := PostureLibrary.new()
		check(fresh.get_def(0).paddle_forehand_mul == original.paddle_forehand_mul, "malformed payload %d falls back to packaged defaults" % index)
		check(Store.save(original) == ERR_FILE_CORRUPT, "malformed payload %d blocks destructive overwrite" % index)
		check(FileAccess.get_file_as_string(test_path) == bad_payloads[index], "malformed payload %d is preserved" % index)


func _remove_test_file() -> void:
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(test_path)


func _finish() -> void:
	print("[MOBILE POSE STORE] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
