extends SceneTree
## Data-only overlay roundtrip, stale-source retention and adversarial validation.
const Store = preload("res://scripts/mobile_pose_store.gd")
const Bake = preload("res://scripts/elbow_preset_bake.gd")
const ServeStore = preload("res://scripts/mobile_serve_pose_store.gd")
const Grip = preload("res://scripts/mobile_paddle_grip_store.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
var checks := 0
var failures: Array[String] = []
var test_id := ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func same_data(a, b) -> bool:
	return JSON.stringify(Bake._canonical(a), "", true, true) == JSON.stringify(Bake._canonical(b), "", true, true)

func fixture(pose: PostureDefinition, count: int = 3) -> Dictionary:
	var transform := [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.123456789012345, 1.123456789012345, -0.123456789012345]
	var samples: Array = []
	var knots: Array = []
	for i in range(count):
		var p := float(i) / float(count - 1)
		samples.append({"p": p, "body": transform.duplicate(), "paddle": transform.duplicate(), "shoulders": [[0.2, 0.9, 0.0], [-0.2, 0.9, 0.0]], "hands": [transform.duplicate(), transform.duplicate()], "elbows": [[0.4, 0.8, 0.0], [-0.4, 0.8, 0.0]], "skin": [transform.duplicate(), transform.duplicate(), transform.duplicate()], "modes": ["GRIP", "RELAXED"], "weight": 0.0})
		knots.append([p, 0.123456789012345 + p, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0])
	return Bake.seal({"version": Bake.VERSION, "model": Bake.MODEL_VERSION, "scope": "stroke_authored", "source_id": pose.posture_id, "source_sha256": Store.authored_fingerprint(pose), "handedness": pose.paddle_hand, "active_sides": [true, false], "rotation_deg": [0.0, 0.0, 0.0], "offsets": [[0.01, 0.0, 0.0], [0.0, 0.0, 0.0]], "duration": 1.0, "rig": {"links": [[0.3, 0.3], [0.3, 0.3]], "sockets": [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]], "anatomy": [transform.slice(0, 9), transform.slice(0, 9)]}, "routes": [{"knots": knots}, {}], "samples": samples})

func run() -> void:
	test_id = "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var child := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bake-id="): test_id = arg.trim_prefix("--bake-id=")
		if arg == "--bake-read": child = true
	var directory := "user://pose_store_tests/elbow_bake_" + test_id + "/"
	check(Store.set_test_path(directory + "poses.json") == OK, "isolated pose file")
	check(ServeStore.set_test_path(directory + "serves.json") == OK, "isolated serve file")
	check(Grip.set_test_path(directory + "grips.json") == OK, "isolated grip file")
	var library := PostureLibrary.new()
	var pose: PostureDefinition = library.get_def(5).duplicate(true)
	if child:
		check(Bake.valid(pose.elbow_preset_bake) and not pose.elbow_preset_bake.is_empty(), "fresh process rehydrates baked data")
		check(pose.elbow_preset_bake.get("source_sha256", "") == Store.authored_fingerprint(pose), "fresh process source fingerprint agrees")
		finish(); return
	check(pose.elbow_preset_bake.is_empty(), "old packaged resource defaults empty")
	var fractional_source: PostureDefinition = pose.duplicate(true)
	fractional_source.body_yaw_deg = 1.0 / 480.0
	var fractional_reload: PostureDefinition = pose.duplicate(true)
	Store._apply_fields(fractional_reload, JSON.parse_string(JSON.stringify(Store._encode_fields(fractional_source), "", true, true)))
	check(Store.authored_fingerprint(fractional_source) == Store.authored_fingerprint(fractional_reload), "source fingerprint survives arbitrary fractional authored scalar JSON")
	var fields := Store._encode_fields(pose)
	fields.erase("elbow_preset_bake")
	check(Store._valid_fields(fields, false), "old whole-pose payload with no bake remains valid")
	pose.elbow_preset_bake = fixture(pose)
	var original := pose.elbow_preset_bake.duplicate(true)
	check(Bake.valid(original), "strict fixture valid")
	var boundary := original.duplicate(true)
	boundary.offsets[0][0] = Vector3(0.2, 0, 0).x
	boundary.rotation_deg[0] = rad_to_deg(Basis(Vector3.RIGHT, deg_to_rad(15.0)).get_euler().x)
	boundary = Bake.seal(boundary)
	check(not boundary.is_empty() and Bake.valid(boundary), "float32 offset and rotation envelope endpoints valid")
	check(Bake.valid(JSON.parse_string(JSON.stringify(original, "", true, true))), "checksum survives fullprecision JSON numeric roundtrip")
	var corrupt := original.duplicate(true)
	corrupt.routes[0].knots[1][1] += 0.01
	check(not Bake.valid(corrupt), "checksum rejects structurally finite accidental route corruption")
	corrupt = original.duplicate(true)
	corrupt.samples[1].elbows[0][0] += 0.001
	check(not Bake.valid(corrupt), "checksum rejects accidental envelope corruption")
	corrupt = original.duplicate(true)
	corrupt.routes[0].knots[1][1] += Bake.CHECKSUM_QUANTUM * 10.0
	check(not Bake.valid(corrupt), "checksum detects numeric corruption above its documented quantum")
	var admitted := original.duplicate(true)
	check(Bake.admit(admitted), "valid runtime payload admitted")
	check(admitted.is_read_only() and admitted.samples.is_read_only() and admitted.routes[0].knots[0].is_read_only(), "runtime admission recursively freezes containers")
	check(Bake.admit(admitted), "same frozen reference admitted through cache")
	var detached := admitted.duplicate(true)
	check(not is_same(admitted, detached) and not detached.is_read_only(), "deep copy creates independent mutable admission candidate")
	detached.routes[0].knots[0][1] += 0.01
	check(not Bake.admit(detached), "corrupt deep copy cannot reuse admitted identity")
	detached = original.duplicate(true); detached.routes[0].knots = []
	check(not Bake.admit(detached), "truncated route fails admission safely")
	detached = original.duplicate(true); detached.samples[0].p = NAN
	check(not Bake.admit(detached), "nonfinite route fails admission safely")
	check(Store.authored_fingerprint(pose) == original.source_sha256, "bake excluded from source fingerprint")
	check(Store.authored_fingerprint(pose, "stroke_runtime") != original.source_sha256, "runtime and authored scopes distinct")
	check(Path.endpoint(pose, 0).elbow_preset_bake == original, "endpoint carries bake")
	check(Path.sample(pose, 0.3).elbow_preset_bake == original, "sample carries bake")
	check(Store.save(pose) == OK, "baked pose persists: " + Store.last_error)
	var corrupt_document: Dictionary = Store._read_document().document.duplicate(true)
	corrupt_document.postures["5"].elbow_preset_bake.routes[0].knots[1][1] += 0.01
	check(not Store._valid_document(corrupt_document), "file validation rejects accidental finite route corruption")
	check(library.get_def(5).elbow_preset_bake.is_empty(), "save alone does not publish")
	check(Store.copy_values(pose, library.get_def(5)) == OK, "explicit publication succeeds")
	pose.elbow_preset_bake = pose.elbow_preset_bake.duplicate(true)
	pose.elbow_preset_bake.offsets[0][0] = 0.02
	check(library.get_def(5).elbow_preset_bake.offsets[0][0] == 0.01, "live bake deeply detached")
	pose.elbow_preset_bake = original.duplicate(true)
	var reload: PostureDefinition = PostureLibrary.new().get_def(5)
	check(same_data(reload.elbow_preset_bake, original), "save and reload preserve full bake")
	var exported := Store.export_pose_json(pose)
	check(not exported.is_empty() and same_data(JSON.parse_string(exported).fields.elbow_preset_bake, original), "Copy JSON includes full unsaved bake")
	var output: Array = []
	var status := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/tests/test_elbow_preset_persistence.gd", "--", "--mobile-runtime", "--bake-read", "--bake-id=" + test_id], output, true)
	check(status == 0, "independent-process bake roundtrip: " + "".join(output))
	pose.right_elbow_pole += Vector3(0.01, 0, 0)
	check(Store.authored_fingerprint(pose) != original.source_sha256, "manual authored edit invalidates source")
	check(Store.save(pose) == OK, "well-formed stale bake remains persistable")
	check(same_data(PostureLibrary.new().get_def(5).elbow_preset_bake, original), "stale bake retained on reload")
	var before_grip := Store.authored_fingerprint(pose)
	pose.paddle_in_hand_rotation_deg += 7.0
	check(Store.authored_fingerprint(pose) != before_grip, "effective main grip participates in fingerprint")
	Store._apply_fields(pose, fields)
	check(pose.elbow_preset_bake.is_empty(), "legacy application explicitly clears previous bake")
	var invalids: Array = []
	var value := original.duplicate(true); value.extra = true; invalids.append(value)
	value = original.duplicate(true); value.version = 2; invalids.append(value)
	value = original.duplicate(true); value.rotation_deg[0] = 15.1; invalids.append(value)
	value = original.duplicate(true); value.offsets[0][0] = 0.201; invalids.append(value)
	value = original.duplicate(true); value.source_sha256 = "z".repeat(64); invalids.append(value)
	value = original.duplicate(true); value.rotation_deg[0] = NAN; invalids.append(value)
	value = original.duplicate(true); value.samples[0].paddle[0] = INF; invalids.append(value)
	value = original.duplicate(true); value.samples[1].p = 0.0; invalids.append(value)
	value = original.duplicate(true); value.routes[0].knots[1][0] = 0.0; invalids.append(value)
	value = original.duplicate(true); value.routes[0].knots[0][3] = 0.0; invalids.append(value)
	value = original.duplicate(true); value.active_sides = [true, 0]; invalids.append(value)
	value = original.duplicate(true); value.samples[0].modes[0] = "res://bad.gd"; invalids.append(value)
	value = original.duplicate(true); value.samples[0].body = Resource.new(); invalids.append(value)
	value = original.duplicate(true); value.rig.links[0][0] = -0.3; invalids.append(value)
	value = original.duplicate(true); value.samples.resize(Bake.MAX_SAMPLES + 1); invalids.append(value)
	value = original.duplicate(true); value.samples[-1].p = 0.99; invalids.append(value)
	var good_bytes := FileAccess.get_file_as_string(Store.storage_path())
	for index in range(invalids.size()):
		check(not Bake.valid(invalids[index]), "malformed bake rejected %d" % index)
		pose.elbow_preset_bake = invalids[index]
		check(Store.save(pose) == ERR_INVALID_DATA, "malformed save rejected %d" % index)
		check(FileAccess.get_file_as_string(Store.storage_path()) == good_bytes, "rejected save preserves bytes %d" % index)
	pose.elbow_preset_bake = fixture(pose, Bake.MAX_SAMPLES)
	check(Bake.valid(pose.elbow_preset_bake), "largest allowed sample count validates")
	var large_roundtrip: Dictionary = JSON.parse_string(JSON.stringify(pose.elbow_preset_bake, "", true, true))
	check(Bake.valid(large_roundtrip), "largest payload checksum survives JSON roundtrip")
	exported = Store.export_pose_json(pose)
	check(not exported.is_empty() and exported.to_utf8_buffer().size() <= Store.MAX_EXPORT_BYTES, "largest bake fits bounded Copy JSON")
	check(Store.save(pose) == OK, "largest bake fits bounded atomic file")
	print("MAX_BAKE_EXPORT_BYTES ", exported.to_utf8_buffer().size())
	check(Store.reset(pose) == OK, "Default removes overlay override")
	check(PostureLibrary.new().get_def(5).elbow_preset_bake.is_empty(), "Default reload has no bake")
	check(ServeStore._encode(ServeStore.get_def(1)).has("elbow_preset_bake"), "serve schema includes optional empty bake")
	check(not Store._encode_fields(BasePoseLibrary.new().get_def(0)).has("elbow_preset_bake"), "base-stance schema unchanged")
	finish()

func finish() -> void:
	print("ELBOW_PRESET_PERSISTENCE ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
