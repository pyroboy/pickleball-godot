extends SceneTree
## Exact approved pose, isolated old-save migration, atomicity, restart and recovery.
const Store = preload("res://scripts/mobile_pose_store.gd")
const GripStore = preload("res://scripts/mobile_paddle_grip_store.gd")
const ServeStore = preload("res://scripts/mobile_serve_pose_store.gd")
const Wide = preload("res://scripts/approved_wide_forehand_import.gd")
const Ready = preload("res://scripts/approved_ready_import.gd")
const Approved = preload("res://scripts/approved_forehand_import.gd")
var checks := 0
var failures: Array[String] = []
var directory := ""
var capture_dir := ""
var captured_stages: Dictionary = {}
var payload: Dictionary = JSON.parse_string(Approved.JSON_TEXT)

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func run() -> void:
	var phase := "suite"
	var id := str(OS.get_process_id())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
		if arg.begins_with("--import-id="): id = arg.trim_prefix("--import-id=")
		if arg.begins_with("--import-phase="): phase = arg.trim_prefix("--import-phase=")
	directory = "user://pose_store_tests/forehand_" + id
	_isolate()
	if phase != "suite":
		_restart(phase); _finish(); return
	check(Approved.JSON_TEXT.sha256_text() == Approved.SOURCE_SHA256, "embedded JSON retains provenance bytes")
	check(payload.baseline_sha256 == Approved.BASELINE_SHA256, "payload retains validated old exporter baseline")
	check(payload.schema == "pickleball.pose" and payload.version == 1 and payload.id == 0 and payload.kind == "stroke" and payload.scope == "whole_pose", "fixed whole-pose identity")
	check(payload.selected_stage == 2 and payload.selected_stage_name == "Finish" and payload.fields.has("windup_body"), "Finish selection remains context only")
	check(payload.fields.size() == 82 and payload.fields.windup_body.size() == 39 and payload.fields.follow_through_body.size() == 36, "every supplied field retained")
	var provenance := "res://docs/pose-imports/forehand-2026-10-02.json"
	if FileAccess.file_exists(provenance): check(FileAccess.get_file_as_string(provenance) == Approved.JSON_TEXT, "embedded JSON equals retained source")
	else: check(get_script().resource_path.ends_with(".gdc"), "compiled APK has independently hashed embedded data")
	check(Store._valid_fields(payload.fields, false), "complete old schema is accepted")
	var authored: Resource = Store._export_packaged_default(0, false)
	_check_supplied(Store._encode_fields(authored), "packaged default")
	check(authored.contact_curve == 0.5 and authored.paddle_in_hand_rotation_deg == 0, "explicit new channels match supplied values")
	check(authored.windup_body.values.right_shoulder_rotation_deg == Vector3(-120, -120, -95.5999984741211), "extreme approved shoulder rotation is not retuned")
	var library := PostureLibrary.new()
	_check_supplied(Store._encode_fields(library.get_def(0)), "fresh install")
	check(not FileAccess.file_exists(Store.storage_path()), "fresh install does not write a pose file")
	var exported := Store.export_pose_json(library.get_def(0), 2)
	_check_supplied(JSON.parse_string(exported).fields, "Copy export")
	check(not exported.is_empty() and not FileAccess.file_exists(Store.storage_path()), "Copy is read-only")
	var fresh_edit: Resource = library.get_def(0).duplicate(true)
	fresh_edit.body_yaw_deg = 61.0
	check(Store.save(fresh_edit) == OK, "first user edit saves")
	check(_document().approved_imports.has(Approved.ID), "first user save records receipt atomically")
	check(_receipt().previous_pose == null, "new install has no fake recovery record")
	check(PostureLibrary.new().get_def(0).body_yaw_deg == 61.0, "first user edit is never replaced on reload")
	_run_child("fresh_edit", id)
	_cleanup()
	_isolate()
	var legacy := _fixture(true)
	var original_bytes := FileAccess.get_file_as_string(Store.storage_path())
	var grips_bytes := FileAccess.get_file_as_string(GripStore.storage_path())
	check(not legacy.has("approved_imports"), "legacy fixture predates receipt")
	var imported := PostureLibrary.new()
	var document := _document()
	_check_supplied(Store._encode_fields(imported.get_def(0)), "migrated pose")
	_check_supplied(document.postures["0"], "persisted migration")
	check(document.postures["0"].paddle_in_hand_rotation_deg == 0.0 and document.postures["0"].contact_curve == 0.5 and _same_value("body_position_offset", document.postures["0"].body_position_offset, [0, 0, 0]), "explicit Contact channels replace old saved values")
	check(document.postures["0"].windup_body.paddle_in_hand_rotation_deg == 21.5 and _same_value("body_position_offset", document.postures["0"].windup_body.body_position_offset, [0, 0, 0]), "explicit Wind-up additive channels replace old saved values")
	check(document.postures["0"].follow_through_body.paddle_in_hand_rotation_deg == -14.0 and document.postures["0"].follow_through_body.body_position_offset == [0.02, -0.03, 0.04], "only omitted Finish additive channels survive")
	check(document.postures["3"] == legacy.postures["3"] and document.base_poses == legacy.base_poses, "other poses remain byte-value equivalent")
	check(document.grip_generations["3"] == legacy.grip_generations["3"], "unrelated generation survives")
	check(document.grip_generations["0"] == 7, "approved pose stamps current global generation")
	check(imported.get_def(0).main_grip_rotation_deg == 0.0 and imported.get_def(0).windup_body.values.main_grip_rotation_deg == -23.5, "existing global grip cannot mask imported pose")
	check(FileAccess.get_file_as_string(ServeStore.storage_path()) == "{unrelated-serve-sentinel}", "stroke ID 0 import never reads or changes separate serve ID 0 file")
	check(FileAccess.get_file_as_string(GripStore.storage_path()) == grips_bytes, "migration never rewrites global choice")
	check(_receipt().previous_pose == legacy.postures["0"] and _receipt().previous_grip_generation == 3, "previous pose and generation are recoverable in receipt")
	check(Store._valid_document(document), "new document validates before restart")
	check(not FileAccess.file_exists(Store.storage_path() + ".tmp"), "atomic commit leaves no temporary file")
	var migration_bytes := FileAccess.get_file_as_string(Store.storage_path())
	PostureLibrary.new()
	check(FileAccess.get_file_as_string(Store.storage_path()) == migration_bytes, "repeat load performs no rewrite")
	_run_child("migrated", id)
	var edited: Resource = imported.get_def(0).duplicate(true)
	edited.body_yaw_deg = -27.0
	edited.windup_body.values["spine_curve_deg"] = 9.0
	check(Store.save(edited) == OK, "post-import user edit saves")
	check(_receipt().previous_pose == legacy.postures["0"], "subsequent save retains original recovery copy")
	_run_child("edited", id)
	check(Store.reset(edited) == OK, "reset removes selected override")
	check(_document().approved_imports.has(Approved.ID) and not _document().postures.has("0"), "reset keeps receipt and recovery copy")
	_run_child("reset", id)
	# Recover the old data by restoring only the backed-up record and generation;
	# the receipt remains, otherwise the deliberate import would run again.
	document = _document()
	document.postures["0"] = document.approved_imports[Approved.ID].previous_pose.duplicate(true)
	document.grip_generations["0"] = document.approved_imports[Approved.ID].previous_grip_generation
	check(Store._write_document(document) == OK, "recoverable old pose can be restored")
	check(_document().postures["0"] == legacy.postures["0"], "backup reconstructs old pose exactly")
	_test_bad_receipts(document)
	_cleanup()
	_isolate()
	legacy = _fixture(false)
	original_bytes = FileAccess.get_file_as_string(Store.storage_path())
	check(DirAccess.make_dir_absolute(Store.storage_path() + ".tmp") == OK, "write-failure fixture created")
	var transient := PostureLibrary.new()
	_check_supplied(Store._encode_fields(transient.get_def(0)), "failed-persistence live pose")
	check(FileAccess.get_file_as_string(Store.storage_path()) == original_bytes and not _document().has("approved_imports"), "failed atomic write preserves old record and no premature marker")
	DirAccess.remove_absolute(Store.storage_path() + ".tmp")
	PostureLibrary.new()
	check(_receipt().previous_pose == legacy.postures["0"], "retry commits exact old recovery record")
	check(_document().postures["0"].contact_curve == 0.5 and _document().postures["0"].paddle_in_hand_rotation_deg == 0.0, "legacy omitted new fields acquire defaults")
	_cleanup()
	_isolate()
	var untouched := _fixture(true)
	# Saving before a library load cannot lose either the new user edit or old backup.
	var direct: Resource = Store._export_packaged_default(0, false)
	direct.body_yaw_deg = 71.0
	check(Store.save(direct) == OK and PostureLibrary.new().get_def(0).body_yaw_deg == 71.0, "direct pre-load save is newer than approved import")
	check(_receipt().previous_pose == untouched.postures["0"], "direct save backs up pre-import record")
	_cleanup()
	_isolate()
	var default_only: Resource = Store._export_packaged_default(0, false)
	check(Store.reset(default_only) == OK and _receipt().previous_pose == null, "first reset stamps receipt even without prior override")
	_cleanup()
	_isolate()
	DirAccess.make_dir_recursive_absolute(directory)
	var bad := FileAccess.open(Store.storage_path(), FileAccess.WRITE); bad.store_string("{broken"); bad.close()
	PostureLibrary.new()
	check(FileAccess.get_file_as_string(Store.storage_path()) == "{broken", "corrupt file is never overwritten by migration")
	check(Store.save(default_only) == ERR_FILE_CORRUPT, "corrupt file blocks later writes")
	_cleanup()
	_isolate()
	_test_independent_imports()
	_cleanup()
	_isolate()
	await _test_editor_views()
	_cleanup()
	_finish()

func _fixture(new_fields: bool) -> Dictionary:
	var fields := Store._encode_fields(Store._export_packaged_default(0, false))
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
		fields.body_position_offset = [0.11, 0.12, 0.13]
		fields.windup_body.body_position_offset = [0.14, 0.15, 0.16]
		fields.follow_through_body["body_position_offset"] = [0.02, -0.03, 0.04]
		fields.windup_body.paddle_in_hand_rotation_deg = 17.0
		fields.follow_through_body.paddle_in_hand_rotation_deg = -14.0
	else:
		fields.erase("paddle_in_hand_rotation_deg"); fields.erase("contact_curve")
	var other := Store._encode_fields(Store._export_packaged_default(3, false)); other.body_yaw_deg = 21.0
	var base := Store._encode_fields(Store._export_packaged_default(0, true)); base.stance_width = 0.91
	var document := {"version": 1, "postures": {"0": fields, "3": other}, "base_poses": {"0": base}, "grip_generations": {"0": 3, "3": 2}}
	document = JSON.parse_string(JSON.stringify(document))
	check(Store._valid_document(document) and Store._write_document(document) == OK, "old private fixture written")
	var grip := {"version": 1, "revision": 7, "generation": 7, "grip": {"main_rotation_deg": 45.0}, "previous": null}
	check(GripStore._write_document(grip) == OK, "preexisting global grip fixture written")
	GripStore.set_test_path(GripStore.storage_path())
	var unrelated_serve := FileAccess.open(ServeStore.storage_path(), FileAccess.WRITE)
	unrelated_serve.store_string("{unrelated-serve-sentinel}"); unrelated_serve.close()
	return JSON.parse_string(JSON.stringify(document))

func _check_supplied(actual: Dictionary, label: String) -> void:
	for field in payload.fields:
		if field in ["windup_body", "follow_through_body"]:
			var expected: Dictionary = payload.fields[field]
			for key in expected:
				check(_same_value(key, actual[field].get(key), expected[key]), "%s: %s.%s exact" % [label, field, key])
			var legacy_keys: Array = actual[field].keys()
			for additive in ["paddle_in_hand_rotation_deg", "body_position_offset"]:
				if not expected.has(additive): legacy_keys.erase(additive)
			legacy_keys.sort()
			var expected_keys: Array = expected.keys(); expected_keys.sort()
			check(legacy_keys == expected_keys, label + ": sparse legacy stage keys exactly match " + field)
		else:
			check(_same_value(field, actual[field], payload.fields[field]), label + ": supplied Contact/path field exact " + field)

func _same_value(field: String, actual, expected) -> bool:
	if actual is Array and expected is Array:
		return Store._encode_value(Store._decode_value(field, actual)) == Store._encode_value(Store._decode_value(field, expected))
	return actual == expected

func _restart(phase: String) -> void:
	var library := PostureLibrary.new()
	var def: Resource = library.get_def(0)
	if phase == "fresh_edit": check(def.body_yaw_deg == 61.0, "fresh edit survives process restart")
	elif phase == "migrated":
		_check_supplied(Store._encode_fields(def), "restarted migration")
		check(def.paddle_in_hand_rotation_deg == 0.0 and def.follow_through_body.values.paddle_in_hand_rotation_deg == -14.0, "explicit and preserved shaft spins survive process restart")
	elif phase == "edited": check(def.body_yaw_deg == -27.0 and def.windup_body.values.spine_curve_deg == 9.0, "post-import edits survive process restart")
	elif phase == "reset":
		check(not _document().postures.has("0"), "reset survives process restart")
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
	check(ServeStore.set_test_path(directory + "/serves.json") == OK, "isolate separate serve file")
func _document() -> Dictionary: return JSON.parse_string(FileAccess.get_file_as_string(Store.storage_path()))
func _receipt() -> Dictionary: return _document().approved_imports[Approved.ID]
func _cleanup() -> void:
	for name in ["poses.json", "grips.json", "serves.json"]:
		if FileAccess.file_exists(directory + "/" + name): DirAccess.remove_absolute(directory + "/" + name)
func _run_child(phase: String, id: String) -> void:
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/tests/test_approved_forehand.gd", "--", "--mobile-runtime", "--import-id=" + id, "--import-phase=" + phase], output, true)
	check(code == 0, "fresh process " + phase + ": " + "".join(output))
func _finish() -> void:
	print("[APPROVED FOREHAND] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_independent_imports() -> void:
	var old := _fixture(true)
	old.approved_imports = {}
	for pair in [["10", Wide], ["20", Ready]]:
		var id: String = pair[0]; var approved: Script = pair[1]
		old.postures[id] = Store._encode_fields(Store._export_packaged_default(int(id), false))
		old.postures[id].body_yaw_deg = 67.0 + int(id)
		old.grip_generations[id] = 7
		old.approved_imports[approved.ID] = {"baseline_sha256": approved.BASELINE_SHA256, "source_sha256": approved.SOURCE_SHA256, "previous_pose": null, "previous_grip_generation": null}
	old = JSON.parse_string(JSON.stringify(old, "", true, true))
	check(Store._valid_document(old) and Store._write_document(old) == OK, "older independent receipts plus pending Forehand validate")
	PostureLibrary.new()
	var migrated := _document()
	_check_supplied(migrated.postures["0"], "independent Forehand migration")
	check(migrated.approved_imports.size() == 3, "all three independently registered receipts remain")
	for id in ["10", "20"]:
		check(migrated.postures[id] == old.postures[id] and migrated.grip_generations[id] == old.grip_generations[id], "Forehand import preserves later approved-pose edit " + id)
	for approved in [Wide, Ready]:
		check(migrated.approved_imports[approved.ID] == old.approved_imports[approved.ID], "Forehand import preserves old recovery receipt " + approved.ID)
	check(Store.APPROVED_POSE_IMPORTS["0"] == Approved and Approved in Store.APPROVED_IMPORT_HISTORY, "Forehand has separately registered active import and append-only history")
	# The opposite ordering: Forehand was already edited; both older imports are pending.
	var reverse := old.duplicate(true)
	reverse.approved_imports = {Approved.ID: migrated.approved_imports[Approved.ID].duplicate(true)}
	reverse.postures["0"] = migrated.postures["0"].duplicate(true)
	reverse.postures["0"].body_yaw_deg = 39.0
	reverse.grip_generations["0"] = 7
	check(Store._valid_document(reverse) and Store._write_document(reverse) == OK, "Forehand receipt with two pending imports validates")
	PostureLibrary.new()
	var reloaded := _document()
	check(reloaded.postures["0"] == reverse.postures["0"] and reloaded.approved_imports[Approved.ID] == reverse.approved_imports[Approved.ID], "later Forehand edits and recovery history survive other pending imports")
	for pair in [["10", Wide], ["20", Ready]]:
		var id: String = pair[0]; var approved: Script = pair[1]
		var expected: Dictionary = JSON.parse_string(approved.JSON_TEXT).fields
		for key in expected:
			check(reloaded.postures[id][key] == expected[key], "unrelated import remains exact " + id + "." + key)
	# A deliberate later global choice is newer, but never rewrites imported data.
	var before := FileAccess.get_file_as_string(Store.storage_path())
	var global: Resource = Store._export_packaged_default(0, false)
	global.main_grip_rotation_deg = 32.0
	DirAccess.remove_absolute(ServeStore.storage_path())
	ServeStore.set_test_path(ServeStore.storage_path())
	check(GripStore.set_global_from_pose(global) == OK, "later explicit global grip saves")
	var global_live: Resource = PostureLibrary.new().get_def(0)
	check(global_live.main_grip_rotation_deg == 0.0 and global_live.paddle_in_hand_rotation_deg == -32.0, "later global grip remains authoritative")
	check(FileAccess.get_file_as_string(Store.storage_path()) == before, "global grip does not rewrite imported pose or receipt")

func _test_editor_views() -> void:
	var Editor = load("res://scripts/ui/mobile_pose_editor.gd")
	var Path = load("res://scripts/stroke_swing_path.gd")
	var View = load("res://scripts/mobile_pose_view_settings.gd")
	View.set_test_path(directory + "/views.json")
	PostureLibrary._singleton = null
	root.size = Vector2i(432, 936); root.content_scale_size = Vector2i(720, 1560)
	var authored: Resource = Store._export_packaged_default(0, false)
	var exact_fields := Store._encode_fields(authored)
	var maximum_stretch := 1.0
	var live: Resource = PostureLibrary.instance().get_def(0)
	for pass_index in range(2):
		if pass_index == 1: check(Store.save(authored) == OK, "view-only existing private-save fixture")
		var saved_bytes := FileAccess.get_file_as_string(Store.storage_path()) if FileAccess.file_exists(Store.storage_path()) else ""
		var editor = Editor.new()
		root.add_child(editor)
		for index in range(3): await process_frame
		check(editor._current.posture_id == 0 and not editor._serve and not editor._base, "editor opens the approved stroke Forehand")
		for stage in [2, 0, 1, 0, 2, 1]:
			editor._select_stage(stage)
			if not capture_dir.is_empty() and not captured_stages.has(stage): await _capture_stage(editor, stage)
			for group in range(6):
				editor._group.select(group); editor._build_fields()
				check(Store._encode_fields(editor._current) == exact_fields, "viewing stage %d group %d does not quantize current pose" % [stage, group])
				check(editor._dirty.is_empty(), "viewing controls never marks pose dirty")
				check(JSON.parse_string(Store.export_pose_json(editor._current, stage)).fields == JSON.parse_string(Store.export_pose_json(authored, stage)).fields, "view-only Copy retains every authored float")
			await process_frame
		check(Store._encode_fields(live) == exact_fields, "stage/group selection never publishes changed live pose")
		var preview = editor._preview
		for court in range(2):
			preview.player.player_num = court
			preview.player.leg_ik.feet_initialized = false
			for index in range(33):
				var progress := index / 32.0
				preview.show_pose(Path.sample(authored, progress))
				var finite := true
				for node in preview.player.find_children("*", "Node3D", true, false): finite = finite and node.global_transform.is_finite()
				check(finite, "finite actual rig court %d sample %d" % [court, index])
				for joint in preview.JOINT_NAMES: check(preview.joint_world_position(joint).is_finite(), "finite displayed selected joint " + joint)
				for arm in [preview.player.right_arm_node, preview.player.left_arm_node]:
					maximum_stretch = maxf(maximum_stretch, arm.visual_stretch)
					check(is_finite(arm.visual_stretch) and arm.visual_stretch >= 1.0, "existing authored-rig reach solver remains finite")
			check(Store._encode_fields(authored) == exact_fields, "forward sampling never rewrites approved resource")
			for progress in [1.0, 0.75, 0.5, 0.25, 0.0]: preview.show_pose(Path.sample(authored, progress))
		check(Store._encode_fields(editor._current) == exact_fields and editor._dirty.is_empty(), "rig playback preserves exact editor copy")
		editor.close()
		check(editor._closing and not editor._dialog.visible, "clean Back closes immediately without save or discard prompt")
		editor.queue_free()
		for index in range(3): await process_frame
		check(Store._encode_fields(live) == exact_fields, "closing never quantizes live approved pose")
		if saved_bytes.is_empty(): check(not FileAccess.file_exists(Store.storage_path()), "open/select/close creates no private save")
		else: check(FileAccess.get_file_as_string(Store.storage_path()) == saved_bytes, "open/select/close preserves existing save bytes exactly")
	print("FOREHAND RIG: maximum existing arm visual_stretch=", maximum_stretch, "; authored channels retained exactly")

func _capture_stage(editor, stage: int) -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "--capture-dir requires a graphical renderer"); return
	if captured_stages.is_empty(): check(DirAccess.make_dir_recursive_absolute(capture_dir) == OK, "capture directory ready")
	editor._group.select(0); editor._build_fields()
	for index in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	var name: String = ["windup", "contact", "finish"][stage]
	check(capture.save_png(capture_dir.path_join("forehand-" + name + ".png")) == OK, "capture approved Forehand " + name)
	captured_stages[stage] = true
