extends SceneTree
## Copy-only portable JSON regression. No import or clipboard access.
## Run: godot --headless --path . --script res://scripts/tests/test_mobile_pose_export.gd -- --mobile-runtime
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
	test_path = "user://pose_store_tests/export_%d/poses.json" % OS.get_process_id()
	check(Store.set_test_path(test_path) == OK, "export test isolates its save fixture")
	_test_cold_export()
	var strokes := PostureLibrary.new()
	var bases := BasePoseLibrary.new()
	check(strokes.definitions.size() == 21 and bases.definitions.size() == 22, "all 43 packaged poses available")
	for def in strokes.definitions + bases.definitions:
		_test_packaged_pose(def)
	check(not FileAccess.file_exists(test_path), "exporting all 43 poses does not create a save")
	var saved: Resource = strokes.get_def(2).duplicate(true)
	saved.body_yaw_deg = 14.0
	check(Store.save(saved) == OK, "existing unrelated private-save fixture created")
	var saved_bytes := FileAccess.get_file_as_string(test_path)
	var live: Resource = PostureLibrary.instance().get_def(0)
	var live_fields := _encoded_fields(live)
	var packaged_fields := _encoded_fields(Store.packaged_default(0, false))
	var singleton_id := PostureLibrary.instance().get_instance_id()
	var edited := _edited_stroke(live)
	var edited_fields := _encoded_fields(edited)
	var windup_id: int = edited.windup_body.get_instance_id()
	var finish_id: int = edited.follow_through_body.get_instance_id()
	for stage in range(3):
		var encoded := Store.export_pose_json(edited, stage)
		var document: Dictionary = JSON.parse_string(encoded)
		check(document.selected_stage == stage, "selected stage %d is retained as context" % stage)
		check(document.selected_stage_name == ["Wind-up", "Contact", "Finish"][stage], "stage %d has human label" % stage)
		check(document.scope == "whole_pose" and document.selected_stage_context.contains("whole pose"), "stage %d explicitly describes whole-pose scope" % stage)
		check(document.fields == JSON.parse_string(edited_fields), "stage %d includes every unsaved field and both full keyframes" % stage)
		check(document.fields.windup_body.body_yaw_deg == 31.25 and document.fields.follow_through_body.body_yaw_deg == -24.5, "both keyframes survive copying from stage %d" % stage)
		check(document.fields.paddle_forehand_mul == 0.875, "contact value survives copying from stage %d" % stage)
		check(encoded == Store.export_pose_json(edited, stage), "stage %d JSON is deterministic" % stage)
		check(encoded == _roundtrip_export(edited, document, stage), "stage %d JSON is canonical after JSON roundtrip" % stage)
		check(document.baseline_sha256 == packaged_fields.sha256_text(), "fingerprint uses packaged baseline rather than edited values")
		check(not encoded.contains("PRIVATE_NOTE") and not encoded.contains("DO_NOT_COPY") and not encoded.contains("res://") and not encoded.contains("resource_path") and not encoded.contains('"script"'), "export excludes private metadata and paths")
	check(_encoded_fields(edited) == edited_fields, "copy leaves unsaved working fields untouched")
	check(edited.windup_body.get_instance_id() == windup_id and edited.follow_through_body.get_instance_id() == finish_id, "copy preserves working keyframe resources")
	check(_encoded_fields(live) == live_fields, "copy leaves live pose untouched")
	check(_encoded_fields(Store.packaged_default(0, false)) == packaged_fields, "copy leaves packaged snapshot untouched")
	check(PostureLibrary.instance().get_instance_id() == singleton_id, "copy preserves library singleton")
	_test_base_edits(bases.get_def(0))
	_test_canonical_order(edited)
	_test_identity_metadata(edited)
	_test_invalid_exports(edited, bases.get_def(0))
	_test_largest_allowed_paths(edited)
	_test_export_size_limit(edited)
	check(FileAccess.get_file_as_string(test_path) == saved_bytes, "valid and invalid exports preserve saved file byte for byte")
	check(not FileAccess.file_exists(test_path + ".tmp"), "exports create no temporary save")
	check(not Store.new().has_method("parse_pose_json"), "store has no JSON import API")
	DirAccess.remove_absolute(test_path)
	print("[MOBILE POSE EXPORT] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_cold_export() -> void:
	check(PostureLibrary._singleton == null and BasePoseLibrary._singleton == null, "cold export starts without library singletons")
	check(Store._packaged.postures.is_empty() and Store._packaged.base_poses.is_empty(), "cold export starts without registered snapshots")
	# Keep a cached resource alive with deliberately modified live values. The
	# baseline fallback must neither replace that cache nor fingerprint its edits.
	var cached: Resource = load("res://data/postures/00_forehand.tres")
	var original: float = cached.body_yaw_deg
	cached.body_yaw_deg = 47.25
	var encoded := Store.export_pose_json(cached)
	check(not encoded.is_empty(), "cold export resolves a known packaged ID")
	if not encoded.is_empty():
		var document: Dictionary = JSON.parse_string(encoded)
		var detached: Resource = ResourceLoader.load("res://data/postures/00_forehand.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
		check(document.fields.body_yaw_deg == 47.25, "cold export includes current unsaved value")
		check(document.baseline_sha256 == _encoded_fields(detached).sha256_text(), "cold fingerprint reads trusted packaged values")
	check(cached.body_yaw_deg == 47.25, "cold export does not replace cached live resource")
	check(PostureLibrary._singleton == null and BasePoseLibrary._singleton == null, "cold export never initializes singletons")
	check(Store._packaged.postures.is_empty() and Store._packaged.base_poses.is_empty(), "cold export never registers mutable snapshots")
	check(not FileAccess.file_exists(test_path), "cold export does not create private saves")
	cached.body_yaw_deg = original


func _test_packaged_pose(def: Resource) -> void:
	var is_base: bool = def.get_script() == Store.BasePose
	var before := _encoded_fields(def)
	var encoded := Store.export_pose_json(def)
	check(not encoded.is_empty(), "packaged pose exports: " + def.display_name + " " + Store.last_error)
	if encoded.is_empty():
		return
	var document: Dictionary = JSON.parse_string(encoded)
	check(document.schema == Store.EXPORT_SCHEMA and document.version == Store.EXPORT_VERSION, "portable schema and version present")
	check(document.kind == ("base" if is_base else "stroke") and document.id == (def.base_pose_id if is_base else def.posture_id), "kind and numeric identity retained")
	check(document.name == def.display_name and document.scope == "whole_pose", "packaged name and complete scope retained")
	check((not document.has("family")) if is_base else document.family == def.family, "family metadata follows actual pose kind")
	check(document.fields == JSON.parse_string(before), "all packaged whitelisted fields roundtrip")
	check(encoded == Store.export_pose_json(def) and encoded == _roundtrip_export(def, document, 1), "packaged JSON is stable and canonical")
	check(encoded.to_utf8_buffer().size() <= Store.MAX_EXPORT_BYTES and encoded.contains("\n\t"), "packaged JSON is bounded and readable")
	check(document.baseline_sha256.length() == 64 and document.baseline_sha256.is_valid_hex_number(false), "SHA256 packaged baseline is present")
	check(_encoded_fields(def) == before, "packaged export leaves input values unchanged")


func _edited_stroke(source: Resource) -> Resource:
	var edited: Resource = source.duplicate(true)
	edited.paddle_forehand_mul = 0.875
	edited.body_yaw_deg = 12.75
	edited.right_elbow_path = PackedVector3Array([Vector3(0.15, -0.25, 0.35), Vector3(-0.5, 0.125, 0.75)])
	edited.left_elbow_path = PackedVector3Array([Vector3(-0.1, 0.2, -0.3)])
	var windup := BodyKeyframe.new()
	windup.capture(edited)
	windup.values.body_yaw_deg = 31.25
	windup.values.right_elbow_pole = Vector3(0.25, -0.5, 0.75)
	edited.windup_body = windup
	var finish := BodyKeyframe.new()
	finish.capture(edited)
	finish.values.body_yaw_deg = -24.5
	finish.values.stance_width = 0.72
	edited.follow_through_body = finish
	edited.notes = "PRIVATE_NOTE"
	edited.last_tuned_by = "PRIVATE_NOTE"
	edited.set_meta("private_tag", "DO_NOT_COPY")
	return edited


func _test_base_edits(source: Resource) -> void:
	var edited: Resource = source.duplicate(true)
	edited.stance_width = 0.77
	edited.crouch_amount = 0.23
	edited.right_hand_offset = Vector3(0.2, -0.1, 0.3)
	var before := _encoded_fields(source)
	var document: Dictionary = JSON.parse_string(Store.export_pose_json(edited))
	check(document.selected_stage == 1 and document.selected_stage_name == "Body stance", "base export labels body-only context")
	check(document.fields.stance_width == 0.77 and document.fields.crouch_amount == 0.23, "base export contains unsaved stance values")
	check(not document.fields.has("windup_body") and not document.fields.has("follow_through_body"), "base export contains only base whitelist")
	check(document.fields == JSON.parse_string(_encoded_fields(edited)), "all base fields roundtrip")
	check(_encoded_fields(source) == before, "base source remains unchanged")


func _test_identity_metadata(edited: Resource) -> void:
	var renamed: Resource = edited.duplicate(true)
	renamed.display_name = "DO_NOT_COPY".repeat(7000)
	renamed.family = 99
	var document: Dictionary = JSON.parse_string(Store.export_pose_json(renamed))
	var packaged := Store.packaged_default(edited.posture_id, false)
	check(document.name == packaged.display_name and document.family == packaged.family, "identity labels are taken from recognized packaged ID, never mutable metadata")
	check(not document.fields.has("posture_id") and not document.fields.has("display_name") and not document.fields.has("family"), "identity is separate from editable whitelist")


func _test_invalid_exports(stroke: Resource, base: Resource) -> void:
	for value in [null, Resource.new(), Store.Posture.new(), Store.BasePose.new()]:
		check(Store.export_pose_json(value).is_empty() and not Store.last_error.is_empty(), "invalid resource type or missing ID rejected")
	for stage in [-1, 3]:
		check(Store.export_pose_json(stroke, stage).is_empty(), "stroke rejects invalid stage %d" % stage)
	for stage in [-1, 0, 2, 3]:
		check(Store.export_pose_json(base, stage).is_empty(), "base rejects non-body stage %d" % stage)
	for bad_id in [-1, 21, 999]:
		var invalid: Resource = stroke.duplicate(true)
		invalid.posture_id = bad_id
		check(Store.export_pose_json(invalid).is_empty(), "invalid stroke ID rejected")
	for mutation in [
		["paddle_forehand_mul", NAN], ["body_yaw_deg", INF], ["body_yaw_deg", -INF],
		["body_yaw_deg", 721.0], ["stance_width", -1.0], ["weight_shift", 2.01],
		["right_hand_offset", Vector3(0.0, NAN, 0.0)], ["paddle_hand", 2],
		["left_hand_mode", 5], ["head_track_ball_weight", 1.1],
		["windup_body", Resource.new()], ["zone_x_min", 4.0],
		["right_elbow_path", PackedVector3Array([Vector3(0.0, INF, 0.0)])],
	]:
		var invalid: Resource = stroke.duplicate(true)
		invalid.set(mutation[0], mutation[1])
		check(Store.export_pose_json(invalid).is_empty() and not Store.last_error.is_empty(), "invalid field rejected: " + mutation[0])
	for mutation in [["script", "res://scripts/player.gd"], ["resource_path", "user://private"], ["body_yaw_deg", NAN], ["left_hand_mode", 4.5], ["stance_width", "0.7"]]:
		var invalid: Resource = stroke.duplicate(true)
		invalid.windup_body.values[mutation[0]] = mutation[1]
		check(Store.export_pose_json(invalid).is_empty(), "invalid nested keyframe rejected: " + mutation[0])
	var invalid_base: Resource = base.duplicate(true)
	invalid_base.base_pose_id = 22
	check(Store.export_pose_json(invalid_base).is_empty(), "invalid base ID rejected")
	invalid_base.base_pose_id = 0
	invalid_base.canonical_intent = 9
	check(Store.export_pose_json(invalid_base).is_empty(), "invalid base field enum rejected")
	check(not Store.export_pose_json(stroke).is_empty() and Store.last_error.is_empty(), "successful retry clears export error")


func _test_largest_allowed_paths(stroke: Resource) -> void:
	var edited: Resource = stroke.duplicate(true)
	var points := PackedVector3Array()
	for index in range(Store.MAX_PATH_POINTS):
		points.append(Vector3(4.123456, -3.123456, 2.123456))
	edited.right_elbow_path = points
	edited.left_elbow_path = points
	var encoded := Store.export_pose_json(edited)
	check(not encoded.is_empty() and encoded.to_utf8_buffer().size() <= Store.MAX_EXPORT_BYTES, "maximum allowed paths and both full keyframes remain within byte limit")
	points.append(Vector3.ZERO)
	edited.right_elbow_path = points
	check(Store.export_pose_json(edited).is_empty(), "oversized elbow path rejected before serialization")


func _encoded_fields(def: Resource) -> String:
	return JSON.stringify(Store._canonical_export_value(Store._encode_fields(def)), "", true, true)


## Godot parses every JSON number as float; restore the whitelist's declared
## resource types before comparing the canonical export bytes. This is test-only.
func _roundtrip_export(source: Resource, document: Dictionary, stage: int) -> String:
	var copy: Resource = source.duplicate(true)
	Store._apply_fields(copy, document.fields)
	return Store.export_pose_json(copy, stage)


func _test_canonical_order(source: Resource) -> void:
	var copy: Resource = source.duplicate(true)
	var reverse: Dictionary = {}
	var keys: Array = copy.windup_body.values.keys()
	keys.reverse()
	for key in keys:
		reverse[key] = copy.windup_body.values[key]
	copy.windup_body.values = reverse
	check(Store.export_pose_json(copy) == Store.export_pose_json(source), "canonical export ignores nested dictionary insertion order")
	copy.windup_body.values.body_yaw_deg = 0
	var integer_bytes := Store.export_pose_json(copy)
	copy.windup_body.values.body_yaw_deg = 0.0
	check(Store.export_pose_json(copy) == integer_bytes, "canonical export gives equal integer and float values identical JSON spelling")
	check(integer_bytes.contains('"id": 0,') and integer_bytes.contains('"version": 1'), "canonical IDs and version remain integer-readable")


func _test_export_size_limit(source: Resource) -> void:
	# Simulate oversized packaged metadata without touching disk or the original.
	var original: Resource = Store._packaged.postures[str(source.posture_id)]
	var oversized: Resource = original.duplicate(true)
	oversized.display_name = "x".repeat(Store.MAX_EXPORT_BYTES)
	Store._packaged.postures[str(source.posture_id)] = oversized
	var encoded := Store.export_pose_json(source)
	Store._packaged.postures[str(source.posture_id)] = original
	check(encoded.is_empty() and Store.last_error.contains("size limit"), "oversized JSON is rejected by the final UTF-8 byte bound")
	check(not Store.export_pose_json(source).is_empty(), "normal export succeeds after oversized fixture is removed")
