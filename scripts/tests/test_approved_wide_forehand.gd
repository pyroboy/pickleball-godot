extends SceneTree
## Exact approved pose, isolated old-save migration, atomicity, restart and recovery.
const Store = preload("res://scripts/mobile_pose_store.gd")
const GripStore = preload("res://scripts/mobile_paddle_grip_store.gd")
const Approved = preload("res://scripts/approved_wide_forehand_import.gd")
var checks := 0
var failures: Array[String] = []
var directory := ""
var payload: Dictionary = JSON.parse_string(Approved.JSON_TEXT)

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func run() -> void:
	var phase := "suite"
	var id := str(OS.get_process_id())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--import-id="): id = arg.trim_prefix("--import-id=")
		if arg.begins_with("--import-phase="): phase = arg.trim_prefix("--import-phase=")
	directory = "user://pose_store_tests/wide_forehand_" + id
	_isolate()
	if phase != "suite":
		_restart(phase); _finish(); return
	check(Approved.JSON_TEXT.sha256_text() == Approved.SOURCE_SHA256, "embedded JSON retains provenance bytes")
	check(payload.baseline_sha256 == Approved.BASELINE_SHA256, "payload retains validated old exporter baseline")
	check(payload.schema == "pickleball.pose" and payload.version == 1 and payload.id == 10 and payload.kind == "stroke" and payload.scope == "whole_pose", "fixed whole-pose identity")
	check(payload.selected_stage == 0 and payload.fields.has("follow_through_body"), "Wind-up selection remains context only")
	check(Store._valid_fields(payload.fields, false), "complete old schema is accepted")
	var authored: Resource = Store._export_packaged_default(10, false)
	_check_supplied(Store._encode_fields(authored), "packaged default")
	check(authored.contact_curve == 0.5 and authored.paddle_in_hand_rotation_deg == 0, "new channels keep packaged defaults")
	var library := PostureLibrary.new()
	_check_supplied(Store._encode_fields(library.get_def(10)), "fresh install")
	check(not FileAccess.file_exists(Store.storage_path()), "fresh install does not write a pose file")
	var exported := Store.export_pose_json(library.get_def(10), 0)
	check(not exported.is_empty() and not FileAccess.file_exists(Store.storage_path()), "Copy is read-only")
	var fresh_edit: Resource = library.get_def(10).duplicate(true)
	fresh_edit.body_yaw_deg = 61.0
	check(Store.save(fresh_edit) == OK, "first user edit saves")
	check(_document().approved_imports.has(Approved.ID), "first user save records receipt atomically")
	check(_receipt().previous_pose == null, "new install has no fake recovery record")
	check(PostureLibrary.new().get_def(10).body_yaw_deg == 61.0, "first user edit is never replaced on reload")
	_run_child("fresh_edit", id)
	_cleanup()
	_isolate()
	var legacy := _fixture(true)
	var original_bytes := FileAccess.get_file_as_string(Store.storage_path())
	var grips_bytes := FileAccess.get_file_as_string(GripStore.storage_path())
	check(not legacy.has("approved_imports"), "legacy fixture predates receipt")
	var imported := PostureLibrary.new()
	var document := _document()
	_check_supplied(Store._encode_fields(imported.get_def(10)), "migrated pose")
	_check_supplied(document.postures["10"], "persisted migration")
	check(document.postures["10"].paddle_in_hand_rotation_deg == 37.0 and document.postures["10"].contact_curve == 0.86, "omitted new Contact channels survive")
	check(document.postures["10"].windup_body.paddle_in_hand_rotation_deg == 17.0 and document.postures["10"].follow_through_body.paddle_in_hand_rotation_deg == -14.0, "omitted new stage spin survives")
	check(document.postures["3"] == legacy.postures["3"] and document.base_poses == legacy.base_poses, "other poses remain byte-value equivalent")
	check(document.grip_generations["3"] == legacy.grip_generations["3"], "unrelated generation survives")
	check(document.grip_generations["10"] == 7, "approved pose stamps current global generation")
	check(imported.get_def(10).paddle_in_hand_rotation_deg == 37.0, "existing global grip cannot mask imported pose")
	check(FileAccess.get_file_as_string(GripStore.storage_path()) == grips_bytes, "migration never rewrites global choice")
	check(_receipt().previous_pose == legacy.postures["10"] and _receipt().previous_grip_generation == 3, "previous pose and generation are recoverable in receipt")
	check(Store._valid_document(document), "new document validates before restart")
	check(not FileAccess.file_exists(Store.storage_path() + ".tmp"), "atomic commit leaves no temporary file")
	var migration_bytes := FileAccess.get_file_as_string(Store.storage_path())
	PostureLibrary.new()
	check(FileAccess.get_file_as_string(Store.storage_path()) == migration_bytes, "repeat load performs no rewrite")
	_run_child("migrated", id)
	var edited: Resource = imported.get_def(10).duplicate(true)
	edited.body_yaw_deg = -27.0
	edited.windup_body.values["spine_curve_deg"] = 9.0
	check(Store.save(edited) == OK, "post-import user edit saves")
	check(_receipt().previous_pose == legacy.postures["10"], "subsequent save retains original recovery copy")
	_run_child("edited", id)
	check(Store.reset(edited) == OK, "reset removes selected override")
	check(_document().approved_imports.has(Approved.ID) and not _document().postures.has("10"), "reset keeps receipt and recovery copy")
	_run_child("reset", id)
	# Recover the old data by restoring only the backed-up record and generation;
	# the receipt remains, otherwise the deliberate import would run again.
	document = _document()
	document.postures["10"] = document.approved_imports[Approved.ID].previous_pose.duplicate(true)
	document.grip_generations["10"] = document.approved_imports[Approved.ID].previous_grip_generation
	check(Store._write_document(document) == OK, "recoverable old pose can be restored")
	check(_document().postures["10"] == legacy.postures["10"], "backup reconstructs old pose exactly")
	_test_bad_receipts(document)
	_cleanup()
	_isolate()
	legacy = _fixture(false)
	original_bytes = FileAccess.get_file_as_string(Store.storage_path())
	check(DirAccess.make_dir_absolute(Store.storage_path() + ".tmp") == OK, "write-failure fixture created")
	var transient := PostureLibrary.new()
	_check_supplied(Store._encode_fields(transient.get_def(10)), "failed-persistence live pose")
	check(FileAccess.get_file_as_string(Store.storage_path()) == original_bytes and not _document().has("approved_imports"), "failed atomic write preserves old record and no premature marker")
	DirAccess.remove_absolute(Store.storage_path() + ".tmp")
	PostureLibrary.new()
	check(_receipt().previous_pose == legacy.postures["10"], "retry commits exact old recovery record")
	check(_document().postures["10"].contact_curve == 0.5 and _document().postures["10"].paddle_in_hand_rotation_deg == 0.0, "legacy omitted new fields acquire defaults")
	_cleanup()
	_isolate()
	var untouched := _fixture(true)
	# Saving before a library load cannot lose either the new user edit or old backup.
	var direct: Resource = Store._export_packaged_default(10, false)
	direct.body_yaw_deg = 71.0
	check(Store.save(direct) == OK and PostureLibrary.new().get_def(10).body_yaw_deg == 71.0, "direct pre-load save is newer than approved import")
	check(_receipt().previous_pose == untouched.postures["10"], "direct save backs up pre-import record")
	_cleanup()
	_isolate()
	var default_only: Resource = Store._export_packaged_default(10, false)
	check(Store.reset(default_only) == OK and _receipt().previous_pose == null, "first reset stamps receipt even without prior override")
	_cleanup()
	_isolate()
	DirAccess.make_dir_recursive_absolute(directory)
	var bad := FileAccess.open(Store.storage_path(), FileAccess.WRITE); bad.store_string("{broken"); bad.close()
	PostureLibrary.new()
	check(FileAccess.get_file_as_string(Store.storage_path()) == "{broken", "corrupt file is never overwritten by migration")
	check(Store.save(default_only) == ERR_FILE_CORRUPT, "corrupt file blocks later writes")
	_cleanup()
	_finish()

func _fixture(new_fields: bool) -> Dictionary:
	var fields := Store._encode_fields(Store._export_packaged_default(10, false))
	fields.body_yaw_deg = -62.0
	fields.paddle_pitch_base_deg = 29.0
	fields.charge_paddle_rotation_deg = [3, 6, 9]
	fields.ft_paddle_offset = [1, 2, 3]
	fields.windup_body.spine_curve_deg = 42.0
	fields.windup_body.main_grip_rotation_deg = 123.0
	fields.windup_body.support_grip_slide_m = 0.19
	fields.follow_through_body.main_grip_rotation_deg = -91.0
	if new_fields:
		fields.paddle_in_hand_rotation_deg = 37.0; fields.contact_curve = 0.86
		fields.windup_body.paddle_in_hand_rotation_deg = 17.0
		fields.follow_through_body.paddle_in_hand_rotation_deg = -14.0
	else:
		fields.erase("paddle_in_hand_rotation_deg"); fields.erase("contact_curve")
	var other := Store._encode_fields(Store._export_packaged_default(3, false)); other.body_yaw_deg = 21.0
	var base := Store._encode_fields(Store._export_packaged_default(0, true)); base.stance_width = 0.91
	var document := {"version": 1, "postures": {"10": fields, "3": other}, "base_poses": {"0": base}, "grip_generations": {"10": 3, "3": 2}}
	document = JSON.parse_string(JSON.stringify(document))
	check(Store._valid_document(document) and Store._write_document(document) == OK, "old private fixture written")
	var grip := {"version": 1, "revision": 7, "generation": 7, "grip": {"main_rotation_deg": 45.0}, "previous": null}
	check(GripStore._write_document(grip) == OK, "preexisting global grip fixture written")
	GripStore.set_test_path(GripStore.storage_path())
	return JSON.parse_string(JSON.stringify(document))

func _check_supplied(actual: Dictionary, label: String) -> void:
	for field in payload.fields:
		if field in ["windup_body", "follow_through_body"]:
			var expected: Dictionary = payload.fields[field]
			for key in expected:
				check(actual[field].get(key) == expected[key], "%s: %s.%s exact" % [label, field, key])
			var legacy_keys: Array = actual[field].keys(); legacy_keys.erase("paddle_in_hand_rotation_deg"); legacy_keys.sort()
			var expected_keys: Array = expected.keys(); expected_keys.sort()
			check(legacy_keys == expected_keys, label + ": sparse legacy stage keys exactly match " + field)
		else:
			check(actual[field] == payload.fields[field], label + ": supplied Contact/path field exact " + field)

func _restart(phase: String) -> void:
	var library := PostureLibrary.new()
	var def: Resource = library.get_def(10)
	if phase == "fresh_edit": check(def.body_yaw_deg == 61.0, "fresh edit survives process restart")
	elif phase == "migrated":
		_check_supplied(Store._encode_fields(def), "restarted migration")
		check(def.paddle_in_hand_rotation_deg == 37.0, "preserved shaft spin survives process restart")
	elif phase == "edited": check(def.body_yaw_deg == -27.0 and def.windup_body.values.spine_curve_deg == 9.0, "post-import edits survive process restart")
	elif phase == "reset":
		check(not _document().postures.has("10"), "reset survives process restart")
		check(def.body_yaw_deg == payload.fields.body_yaw_deg, "reset returns imported default")
	check(_document().approved_imports.has(Approved.ID), "receipt survives process restart")
	if phase != "fresh_edit": check(_document().postures["3"].body_yaw_deg == 21.0 and _document().base_poses["0"].stance_width == 0.91, "unrelated private poses survive process restart")

func _test_bad_receipts(good: Dictionary) -> void:
	for mutation in [{}, {"other": {}}, {Approved.ID: {}}, {Approved.ID: {"baseline_sha256": "bad", "source_sha256": Approved.SOURCE_SHA256, "previous_pose": null, "previous_grip_generation": null}}]:
		var invalid := good.duplicate(true); invalid.approved_imports = mutation
		check(not Store._valid_document(invalid), "invalid receipt rejected")
	for key in ["previous_pose", "previous_grip_generation"]:
		var invalid := good.duplicate(true); invalid.approved_imports[Approved.ID][key] = "res://invalid"
		check(not Store._valid_document(invalid), "invalid recovery field rejected " + key)

func _isolate() -> void:
	check(Store.set_test_path(directory + "/poses.json") == OK, "isolate pose file")
	check(GripStore.set_test_path(directory + "/grips.json") == OK, "isolate grip file")
func _document() -> Dictionary: return JSON.parse_string(FileAccess.get_file_as_string(Store.storage_path()))
func _receipt() -> Dictionary: return _document().approved_imports[Approved.ID]
func _cleanup() -> void:
	for name in ["poses.json", "grips.json"]:
		if FileAccess.file_exists(directory + "/" + name): DirAccess.remove_absolute(directory + "/" + name)
func _run_child(phase: String, id: String) -> void:
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/tests/test_approved_wide_forehand.gd", "--", "--mobile-runtime", "--import-id=" + id, "--import-phase=" + phase], output, true)
	check(code == 0, "fresh process " + phase + ": " + "".join(output))
func _finish() -> void:
	print("[APPROVED WIDE FOREHAND] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
