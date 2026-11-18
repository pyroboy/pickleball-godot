extends SceneTree
## Exact payload, old procedural fingerprint, recoverable targeted migration.
const Store = preload("res://scripts/mobile_serve_pose_store.gd")
const Poses = preload("res://scripts/mobile_pose_store.gd")
const Grips = preload("res://scripts/mobile_paddle_grip_store.gd")
const Approved = preload("res://scripts/approved_flat_serve_import.gd")
var checks := 0
var failures: Array[String] = []
var payload: Dictionary = JSON.parse_string(Approved.JSON_TEXT)
var path := ""
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func exact(actual: Dictionary, expected: Dictionary, label: String) -> void:
	var legacy_keys:Array=actual.keys()
	for additive in ["right_foot_pitch_deg","left_foot_pitch_deg"]:
		if actual.has(additive) and not expected.has(additive):
			check(is_zero_approx(float(actual[additive])),label+" additive "+additive+" retains neutral default")
			legacy_keys.erase(additive)
	check(legacy_keys.size() == expected.size(), label + " exact supplied field count")
	for field in expected:
		if expected[field] is Dictionary:
			exact(actual[field], expected[field], label + "." + field)
		else:
			var value = Poses._encode_value(Poses._decode_value(field, expected[field]))
			var observed = Poses._encode_value(Poses._decode_value(field, actual[field]))
			check(observed == value, label + "." + field)
func raw_write(document: Dictionary) -> String:
	var bytes := JSON.stringify(document, "\t", true, true)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(bytes); file.close()
	return bytes
func run() -> void:
	var child_id := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--approved-flat-id="): child_id = arg.trim_prefix("--approved-flat-id=")
	var id := child_id if not child_id.is_empty() else str(OS.get_process_id())
	path = "user://pose_store_tests/approved_flat_%s/serves.json" % id
	Store.set_test_path(path); Grips.set_test_path(path.replace("serves.json", "grips.json"))
	if not child_id.is_empty():
		check(is_equal_approx(Store.get_def(0).paddle_pitch_base_deg, Store.get_default(0).paddle_pitch_base_deg + 6), "fresh process keeps later contact rotation")
		check(Store._read_document().document.approved_imports.has(Approved.ID), "fresh process keeps receipt")
		finish(); return
	check(Approved.JSON_TEXT.sha256_text() == Approved.SOURCE_SHA256, "embedded exact source bytes")
	var source := "res://docs/pose-imports/flat-serve-user-2026-10-02.json"
	if FileAccess.file_exists(source): check(FileAccess.get_file_as_string(source) == Approved.JSON_TEXT, "retained source equals embedded data")
	else: check(get_script().resource_path.ends_with(".gdc"), "compiled APK independently hashed embedded data")
	check(payload.id == 0 and payload.kind == "serve" and payload.scope == "whole_pose", "fixed Flat serve identity")
	check(payload.baseline_sha256 == Approved.BASELINE_SHA256, "supplied source fingerprint")
	var generated := Poses._encode_fields(Store._default(0))
	var legacy_generated:Dictionary=generated.duplicate(true)
	# The historical fingerprint predates these additive zero-default channels.
	# Strip only those fields to verify every original generated value unchanged.
	for fields in [legacy_generated,legacy_generated.windup_body,legacy_generated.follow_through_body]:
		for additive in ["right_foot_pitch_deg","left_foot_pitch_deg"]:
			check(is_zero_approx(float(fields[additive])),"procedural baseline pitch remains exactly neutral")
			fields.erase(additive)
	check(JSON.stringify(Poses._canonical_export_value(legacy_generated), "", true, true).sha256_text() == Approved.BASELINE_SHA256, "old procedural exporter fingerprint is unchanged")
	exact(Poses._encode_fields(Store.get_default(0)), payload.fields, "packaged Flat")
	exact(Poses._encode_fields(Store.get_def(0)), payload.fields, "fresh Flat")
	check(not FileAccess.file_exists(path), "fresh read creates no save")
	check(not Store.export_pose_json(Store.get_def(0), 0).is_empty(), "whole-pose Copy succeeds")
	check(not FileAccess.file_exists(path), "Copy creates no save")
	for style in range(1, 7): exact(Poses._encode_fields(Store.get_default(style)), Poses._encode_fields(Store._default(style)), "other packaged style%d unchanged" % style)
	var old: Dictionary = generated.duplicate(true); old.body_yaw_deg += 13
	var other := Poses._encode_fields(Store.get_default(2)); other.body_yaw_deg += 19
	var document := {"version": 1, "serves": {"0": old, "2": other}, "grip_generations": {"0": 0, "2": 0}}
	var before := raw_write(document)
	Store.set_test_path(path)
	check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "atomic-failure fixture")
	exact(Poses._encode_fields(Store.get_def(0)), payload.fields, "failed-write session uses approved Flat")
	check(FileAccess.get_file_as_string(path) == before, "failed migration preserves exact previous bytes")
	DirAccess.remove_absolute(path + ".tmp")
	Store.set_test_path(path)
	exact(Poses._encode_fields(Store.get_def(0)), payload.fields, "retry migrates Flat")
	var saved: Dictionary = Store._read_document().document
	var receipt: Dictionary = saved.approved_imports[Approved.ID]
	exact(receipt.previous_pose, old, "recoverable previous record")
	check(receipt.previous_grip_generation == 0, "recoverable previous grip generation")
	exact(saved.serves["2"], other, "unrelated saved style preserved")
	check(saved.grip_generations["2"] == 0, "other grip generation preserved")
	var edit: PostureDefinition = Store.get_def(0).duplicate(true)
	edit.paddle_pitch_base_deg += 6
	# Contact-only edit freezes the other authored rotation endpoints.
	edit.charge_paddle_rotation_deg.x -= 6; edit.ft_paddle_rotation_deg.x -= 6
	check(Store.save(edit) == OK and Store.copy_values(edit, Store.get_def(0)) == OK, "later contact rotation saves and publishes")
	var expected := Poses._encode_fields(edit)
	Store.set_test_path(path)
	exact(Poses._encode_fields(Store.get_def(0)), expected, "migration never overwrites later edit")
	var output: Array = []
	var result := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/tests/test_approved_flat_serve.gd", "--", "--mobile-runtime", "--approved-flat-id=" + id], output, true)
	check(result == 0, "independent-process reload: " + "".join(output))
	check(Store.reset(Store.get_def(0)) == OK, "reset removes only Flat override")
	Store.set_test_path(path)
	exact(Poses._encode_fields(Store.get_def(0)), payload.fields, "reset restores approved Flat after reload")
	saved = Store._read_document().document
	check(not saved.serves.has("0") and saved.approved_imports.has(Approved.ID), "reset keeps receipt")
	exact(saved.serves["2"], other, "reset preserves other style")
	# Direct save into a fresh installation must stamp before next startup.
	DirAccess.remove_absolute(path); Store.set_test_path(path)
	check(Store.save(edit) == OK, "fresh direct save")
	Store.set_test_path(path)
	exact(Poses._encode_fields(Store.get_def(0)), expected, "fresh direct save survives next startup")
	DirAccess.remove_absolute(path); Store.set_test_path(path)
	check(Store.reset(Store.get_default(0)) == OK, "fresh reset stamps receipt")
	check(Store._read_document().document.approved_imports.has(Approved.ID), "fresh reset receipt")
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string("{broken"); file.close()
	Store.set_test_path(path)
	exact(Poses._encode_fields(Store.get_def(0)), payload.fields, "corrupt startup keeps packaged Flat")
	check(FileAccess.get_file_as_string(path) == "{broken", "corrupt file never repaired or overwritten")
	check(Store.save(edit) == ERR_FILE_CORRUPT, "save respects corrupt file")
	DirAccess.remove_absolute(path)
	finish()
func finish() -> void:
	print("APPROVED FLAT SERVE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
