extends SceneTree
## Two fixed imports have independent receipts; historical recovery data survives.
const Store = preload("res://scripts/mobile_pose_store.gd")
const Grips = preload("res://scripts/mobile_paddle_grip_store.gd")
const Wide = preload("res://scripts/approved_wide_forehand_import.gd")
const Ready = preload("res://scripts/approved_ready_import.gd")
const Backhand = preload("res://scripts/approved_backhand_import.gd")
const WideBackhand = preload("res://scripts/approved_wide_backhand_import.gd")
const Forehand = preload("res://scripts/approved_forehand_import.gd")
var checks := 0
var failures: Array[String] = []
var directory := ""
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func run() -> void:
	directory = "user://pose_store_tests/approved_pair_%d" % OS.get_process_id()
	check(Store.set_test_path(directory + "/poses.json") == OK, "isolated pair fixture")
	check(Grips.set_test_path(directory + "/grips.json") == OK, "isolated global fixture")
	var original := _fixture()
	var before := FileAccess.get_file_as_string(Store.storage_path())
	check(DirAccess.make_dir_absolute(Store.storage_path() + ".tmp") == OK, "joint atomic failure fixture")
	var live := PostureLibrary.new()
	_exact(Store._encode_fields(live.get_def(10)), Wide)
	_exact(Store._encode_fields(live.get_def(20)), Ready)
	check(FileAccess.get_file_as_string(Store.storage_path()) == before, "failed pair commit preserves both original poses")
	check(not _document().has("approved_imports"), "failed pair commit has neither premature receipt")
	DirAccess.remove_absolute(Store.storage_path() + ".tmp")
	live = PostureLibrary.new()
	var migrated := _document()
	check(migrated.approved_imports.size() == 2, "successful pair commit records both independent receipts")
	for pair in [["10", Wide], ["20", Ready]]:
		var id: String = pair[0]; var approved: Script = pair[1]
		_exact(migrated.postures[id], approved)
		check(migrated.approved_imports[approved.ID].previous_pose == original.postures[id], "each receipt has its own exact prior pose " + id)
		check(migrated.approved_imports[approved.ID].previous_grip_generation == original.grip_generations[id], "each receipt has its own prior generation " + id)
		check(migrated.postures[id].paddle_in_hand_rotation_deg == original.postures[id].paddle_in_hand_rotation_deg and migrated.postures[id].contact_curve == original.postures[id].contact_curve, "new Contact channels retained " + id)
		check(migrated.postures[id].windup_body.paddle_in_hand_rotation_deg == original.postures[id].windup_body.paddle_in_hand_rotation_deg, "new Wind-up spin retained " + id)
		check(migrated.postures[id].body_position_offset == original.postures[id].body_position_offset, "new Contact body position retained " + id)
		for stage in ["windup_body", "follow_through_body"]:
			check(migrated.postures[id][stage].body_position_offset == original.postures[id][stage].body_position_offset, "new body position retained " + id + " " + stage)
	check(migrated.postures["3"] == original.postures["3"] and migrated.grip_generations["3"] == original.grip_generations["3"], "unrelated pose and generation unchanged")
	var committed := FileAccess.get_file_as_string(Store.storage_path())
	PostureLibrary.new()
	check(FileAccess.get_file_as_string(Store.storage_path()) == committed, "pair reload does not rewrite")
	# An already imported and subsequently edited Wide pose must not be replaced
	# when the independently approved Ready pose still needs its first import.
	var historical := original.duplicate(true)
	historical["approved_imports"] = {Wide.ID: migrated.approved_imports[Wide.ID].duplicate(true)}
	historical.postures["10"] = migrated.postures["10"].duplicate(true)
	historical.postures["10"].body_yaw_deg = 57.0
	historical.postures["10"].windup_body["main_grip_rotation_deg"] = 109.0
	historical.grip_generations["10"] = 4
	check(Store._valid_document(historical) and Store._write_document(historical) == OK, "historical Wide receipt plus pending Ready validates")
	PostureLibrary.new()
	var independent := _document()
	check(independent.postures["10"] == historical.postures["10"] and independent.grip_generations["10"] == historical.grip_generations["10"], "independent Ready import cannot reset newer Wide edits")
	check(independent.approved_imports[Wide.ID] == historical.approved_imports[Wide.ID], "historical Wide backup remains exact")
	_exact(independent.postures["20"], Ready)
	check(independent.approved_imports[Ready.ID].previous_pose == original.postures["20"], "new Ready receipt has correct original backup")
	# Mirror the sequence: Ready receipt exists, while Wide has not migrated yet.
	historical = original.duplicate(true)
	historical["approved_imports"] = {Ready.ID: migrated.approved_imports[Ready.ID].duplicate(true)}
	historical.postures["20"] = migrated.postures["20"].duplicate(true)
	historical.postures["20"].body_pitch_deg = 26.0
	check(Store._valid_document(historical) and Store._write_document(historical) == OK, "historical Ready receipt plus pending Wide validates")
	PostureLibrary.new()
	independent = _document()
	check(independent.postures["20"] == historical.postures["20"] and independent.approved_imports[Ready.ID] == historical.approved_imports[Ready.ID], "independent Wide import preserves Ready edit and backup")
	_exact(independent.postures["10"], Wide)
	check(Store.APPROVED_IMPORT_HISTORY.size() >= Store.APPROVED_POSE_IMPORTS.size(), "history registry is distinct from active pose map")
	for approved in [Wide, Ready]: check(approved in Store.APPROVED_IMPORT_HISTORY, "every current receipt has immutable historical registration")
	DirAccess.remove_absolute(Store.storage_path())
	# An unrelated ordinary save stamps all four absent approved-pose receipts. Later
	# app-authored edits are newer even when neither override existed at upgrade.
	var unrelated: Resource = Store._export_packaged_default(3, false)
	check(Store.save(unrelated) == OK, "unrelated first save succeeds")
	var absent := _document()
	check(absent.approved_imports.size() == 5 and absent.approved_imports.has_all([Wide.ID, Ready.ID, Forehand.ID, WideBackhand.ID, Backhand.ID]) and not absent.postures.has("0") and not absent.postures.has("10") and not absent.postures.has("20") and not absent.postures.has("11"), "ordinary save stamps absent receipts without inventing overrides")
	for approved in [Wide, Ready, Forehand, WideBackhand, Backhand]: check(absent.approved_imports[approved.ID].previous_pose == null, "absent receipt does not invent old pose")
	DirAccess.remove_absolute(Store.storage_path())
	print("[APPROVED POSE IMPORTS] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
func _fixture() -> Dictionary:
	var document := {"version": 1, "postures": {}, "base_poses": {}, "grip_generations": {"10": 2, "20": 3, "3": 1}}
	for id in [10, 20, 3]:
		var fields := Store._encode_fields(Store._export_packaged_default(id, false))
		fields.body_yaw_deg = 10.0 + id
		if id in [10, 20]:
			fields.paddle_in_hand_rotation_deg = 11.0 + id
			fields.contact_curve = 0.73
			fields.body_position_offset = [0.03, -0.02, 0.04]
			fields.windup_body["body_position_offset"] = [-0.06, -0.01, 0.07]
			fields.follow_through_body["body_position_offset"] = [0.04, 0.02, -0.03]
			fields.windup_body["paddle_in_hand_rotation_deg"] = 2.0 + id
			fields.windup_body["support_grip_style"] = 0.8
			fields.follow_through_body["support_grip_style"] = 0.9
		document.postures[str(id)] = fields
	document = JSON.parse_string(JSON.stringify(document))
	check(Store._valid_document(document) and Store._write_document(document) == OK, "two legacy overrides plus unrelated pose stored")
	return document
func _exact(actual: Dictionary, approved: Script) -> void:
	var expected: Dictionary = JSON.parse_string(approved.JSON_TEXT).fields
	for key in expected:
		if expected[key] is Dictionary:
			for nested in expected[key]: check(_same_value(nested, actual[key].get(nested), expected[key][nested]), approved.ID + ": exact " + key + "." + nested)
			var actual_keys: Array = actual[key].keys(); actual_keys.erase("paddle_in_hand_rotation_deg"); actual_keys.erase("body_position_offset"); actual_keys.sort()
			var expected_keys: Array = expected[key].keys(); expected_keys.sort()
			check(actual_keys == expected_keys, approved.ID + ": exact sparse keys " + key)
		else: check(_same_value(key, actual[key], expected[key]), approved.ID + ": exact " + key)
func _same_value(field: String, actual, expected) -> bool:
	# JSON doubles are converted to Godot's float32 Vector3 channels in live
	# resources. Compare exact channel values, not an arbitrary tolerance.
	if actual is Array and expected is Array:
		return Store._encode_value(Store._decode_value(field, actual)) == Store._encode_value(Store._decode_value(field, expected))
	return actual == expected
func _document() -> Dictionary: return JSON.parse_string(FileAccess.get_file_as_string(Store.storage_path()))
