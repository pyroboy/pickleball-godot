extends RefCounted
const PaddleRotation = preload("res://scripts/paddle_rotation.gd")
## App-private JSON only. No user-controlled ResourceLoader paths or executable resources.
## Saving does not publish an edit: callers copy_values() into live resources after OK.
const GripStore = preload("res://scripts/mobile_paddle_grip_store.gd")
const APPROVED_POSE_IMPORTS := {
	"2": preload("res://scripts/approved_backhand_import.gd"),
	"11": preload("res://scripts/approved_wide_backhand_import.gd"),
	"0": preload("res://scripts/approved_forehand_import.gd"),
	"10": preload("res://scripts/approved_wide_forehand_import.gd"),
	"20": preload("res://scripts/approved_ready_import.gd"),
}
# Append-only receipt registry. Keep old entries when a later import replaces
# an active pose entry above, so its recovery history never invalidates a save.
const APPROVED_IMPORT_HISTORY := [
	preload("res://scripts/approved_wide_forehand_import.gd"),
	preload("res://scripts/approved_ready_import.gd"),
	preload("res://scripts/approved_forehand_import.gd"),
	preload("res://scripts/approved_wide_backhand_import.gd"),
	preload("res://scripts/approved_backhand_import.gd"),
]
const Posture = preload("res://scripts/posture_definition.gd")
const BasePose = preload("res://scripts/base_pose_definition.gd")
const BodyKeyframe = preload("res://scripts/stroke_body_keyframe.gd")
const ElbowBake = preload("res://scripts/elbow_preset_bake.gd")
const DEFAULT_PATH := "user://mobile_pose_overrides_v1.json"
const MAX_FILE_BYTES := 8388608
const MAX_PATH_POINTS := 64
const EXPORT_SCHEMA := "pickleball.pose"
const EXPORT_VERSION := 1
const MAX_EXPORT_BYTES := 2097152

# Explicit schema. Identity, metadata, resource_path and script are never writable.
const COMMON_FIELDS := [
	"right_hand_offset", "right_elbow_pole", "right_shoulder_rotation_deg",
	"right_elbow_swivel_deg", "left_elbow_swivel_deg", "elbow_swivel_weight",
	"left_hand_mode", "left_hand_offset", "left_elbow_pole", "left_shoulder_rotation_deg",
	"stance_width", "front_foot_forward", "back_foot_back", "right_foot_yaw_deg", "left_foot_yaw_deg",
	"right_foot_pitch_deg", "left_foot_pitch_deg",
	"right_knee_pole", "left_knee_pole", "right_foot_offset", "left_foot_offset", "lead_foot",
	"crouch_amount", "weight_shift", "hip_yaw_deg", "torso_yaw_deg", "torso_pitch_deg", "torso_roll_deg",
	"spine_curve_deg", "body_yaw_deg", "body_pitch_deg", "body_roll_deg",
	"head_yaw_deg", "head_pitch_deg", "head_track_ball_weight",
]
const STROKE_FIELDS := [
	"body_position_offset",
	"paddle_forehand_mul", "paddle_forward_mul", "paddle_y_offset",
	"paddle_pitch_base_deg", "paddle_pitch_signed_deg", "paddle_pitch_sign_source",
	"paddle_yaw_base_deg", "paddle_yaw_signed_deg", "paddle_yaw_sign_source",
	"paddle_roll_base_deg", "paddle_roll_signed_deg", "paddle_roll_sign_source",
	"paddle_floor_clearance", "has_zone", "zone_x_min", "zone_x_max", "zone_y_min", "zone_y_max", "zone_forward_offset",
	"paddle_hand", "main_grip_rotation_deg", "paddle_in_hand_rotation_deg", "support_grip_rotation_deg", "support_grip_slide_m",
	"support_index_closure", "support_grip_style", "right_elbow_path", "left_elbow_path", "elbow_preset_bake", "shoulder_protraction_m",
	"charge_paddle_offset", "charge_paddle_rotation_deg", "charge_body_rotation_deg", "charge_hip_coil_deg", "charge_back_foot_load",
	"ft_paddle_offset", "ft_paddle_rotation_deg", "ft_hip_uncoil_deg", "ft_front_foot_load",
	"ft_duration_strike", "ft_duration_sweep", "ft_duration_settle", "ft_duration_hold", "ft_ease_curve",
	"compact_finish_lateral_scale", "compact_motion_scale", "compact_finish_elbow_offset", "swing_path_blend", "contact_curve",
	"ready_curve_auto", "ready_curve_bow", "ready_curve_round", "ready_curve_dir_deg", "ready_curve_peak",
	"paddle_path_times", "paddle_path_offsets", "ready_path_times", "ready_path_offsets",
	"paddle_path_tangents", "ready_path_tangents",
	"speed_lead_start", "speed_lead_end", "speed_strike_start", "speed_strike_end", "speed_finish_start", "speed_finish_end",
	"speed_lead_points", "speed_strike_points", "speed_finish_points",
	"windup_body", "follow_through_body", "charge_duration",
]
const BASE_FIELDS := [
	"canonical_intent", "stroke_overlay_mix", "recovery_time", "landing_lockout_time", "jump_window",
	"split_step_hop_height", "lunge_distance",
]
const UNIT_FIELDS := [
	"head_track_ball_weight", "support_index_closure", "support_grip_style", "charge_back_foot_load",
	"ft_front_foot_load", "compact_finish_lateral_scale", "compact_motion_scale", "swing_path_blend", "contact_curve", "stroke_overlay_mix",
	"ready_curve_auto", "ready_curve_bow", "ready_curve_round", "ready_curve_peak",
]
const INTEGER_MAX := {"left_hand_mode": 4, "lead_foot": 1, "paddle_hand": 1, "paddle_pitch_sign_source": 2,
	"paddle_yaw_sign_source": 2, "paddle_roll_sign_source": 2, "ft_ease_curve": 2, "canonical_intent": 8}
const POSITIVE_FIELDS := ["stance_width", "crouch_amount", "paddle_floor_clearance", "split_step_hop_height", "lunge_distance"]

static var last_error: String = ""
static var _test_path: String = ""
static var _packaged: Dictionary = {"postures": {}, "base_poses": {}}
static var skip_overrides := false  # Pose Studio (--pose-studio): show the repo pose files only


## Test-only isolation: accepts a private subdirectory, never the production save path.
static func set_test_path(path: String) -> Error:
	if path != "" and (not path.begins_with("user://pose_store_tests/") or ".." in path or not path.ends_with(".json")):
		return ERR_INVALID_PARAMETER
	_test_path = path
	return OK


static func storage_path() -> String:
	return DEFAULT_PATH if _test_path.is_empty() else _test_path


static func save(def: Resource) -> Error:
	last_error = ""
	var identity := _identity(def)
	if identity.is_empty():
		return _fail(ERR_INVALID_DATA, "Unknown pose type or ID")
	var fields := _encode_fields(def)
	if fields.is_empty():
		return _fail(ERR_INVALID_DATA, "Pose has unsupported or out-of-range values")
	var loaded := _read_document()
	if loaded.error != OK:
		return loaded.error
	var document: Dictionary = loaded.document
	# A direct save is newer than this release's approved import. Record the
	# receipt with that save so a later startup never overwrites the user's edit.
	_prepare_approved_pose_imports(document)
	document[identity.group][identity.id] = fields
	if identity.group == "postures":
		if not document.has("grip_generations"): document.grip_generations = {}
		document.grip_generations[identity.id] = GripStore.current_generation()
	var error := _write_document(document)
	if error == OK and identity.group == "postures": def.set_meta("mobile_grip_saved_generation", GripStore.current_generation())
	return error


static func reset(def: Resource) -> Error:
	last_error = ""
	var identity := _identity(def)
	if identity.is_empty():
		return _fail(ERR_INVALID_DATA, "Unknown pose type or ID")
	var loaded := _read_document()
	if loaded.error != OK:
		return loaded.error
	var document: Dictionary = loaded.document
	var receipt_added := _prepare_approved_pose_imports(document)
	if not document[identity.group].has(identity.id):
		return _write_document(document) if receipt_added else OK
	document[identity.group].erase(identity.id)
	if identity.group == "postures" and document.has("grip_generations"): document.grip_generations.erase(identity.id)
	return _write_document(document)


static func apply_overrides(definitions: Array, is_base: bool) -> void:
	var group := "base_poses" if is_base else "postures"
	# Retain deep packaged snapshots before the first overlay, including nested body keys.
	for def in definitions:
		var identity := _identity(def)
		if not identity.is_empty() and identity.group == group and not _packaged[group].has(identity.id):
			_packaged[group][identity.id] = def.duplicate(true)
		# Godot CACHE_MODE_REPLACE can retain a newly added property when an old
		# .tres omits it. An absent override must never retain an old live bake.
		if not is_base and not identity.is_empty() and _packaged[group].has(identity.id):
			def.elbow_preset_bake = _packaged[group][identity.id].elbow_preset_bake.duplicate(true)
	if skip_overrides: return
	var loaded := _read_document()
	if loaded.error != OK:
		push_warning("MobilePoseStore: " + last_error + "; using packaged poses")
		if not is_base:
			for def in definitions: GripStore.apply_to_definition(def)
		return
	# Fresh installations use the authored default without creating a save.
	# Existing approved-pose snapshots must not mask the requested whole-pose edits.
	if not is_base and _prepare_approved_pose_imports(loaded.document, false):
		if _write_document(loaded.document) != OK:
			# Keep the old file recoverable, show the approved pose this session,
			# and retry the atomic migration at the next load.
			push_warning("MobilePoseStore: " + last_error + "; approved poses are active for this session only")
	for def in definitions:
		var identity := _identity(def)
		if not identity.is_empty() and identity.group == group:
			_apply_fields(def, loaded.document[group].get(identity.id, {}))
			if not is_base:
				def.set_meta("mobile_grip_saved_generation", int(loaded.document.get("grip_generations", {}).get(identity.id, -1)))
				GripStore.apply_to_definition(def)


## Rehydrate raw persisted grip channels before applying a newer global default.
## All unrelated live pose values and resource identities are left untouched.
static func refresh_live_grips(definitions: Array) -> void:
	var loaded := _read_document()
	if loaded.error != OK:
		# Preserve live bodies and the corrupt file; a valid global choice still
		# applies to the currently visible poses without trusting invalid data.
		for def in definitions: GripStore.apply_to_definition(def, true)
		return
	for def in definitions:
		var identity := _identity(def)
		if identity.is_empty() or identity.group != "postures": continue
		var raw: Resource = packaged_default(int(identity.id), false)
		if raw == null: continue
		_apply_fields(raw, loaded.document.postures.get(identity.id, {}))
		copy_grip_values(raw, def)
		def.set_meta("mobile_grip_saved_generation", int(loaded.document.get("grip_generations", {}).get(identity.id, -1)))
		GripStore.apply_to_definition(def)


static func copy_grip_values(source: Resource, target: Resource) -> void:
	for field in ["main_grip_rotation_deg", "paddle_in_hand_rotation_deg"]: target.set(field, source.get(field))
	for property in ["windup_body", "follow_through_body"]:
		var source_body: Resource = source.get(property)
		var target_body: Resource = target.get(property)
		for field in ["main_grip_rotation_deg", "paddle_in_hand_rotation_deg"]:
			if source_body != null and source_body.values.has(field):
				if target_body == null: target_body = BodyKeyframe.new(); target.set(property, target_body)
				target_body.values[field] = source_body.values[field]
			elif target_body != null: target_body.values.erase(field)


static func packaged_default(id: int, is_base: bool) -> Resource:
	var group := "base_poses" if is_base else "postures"
	var key := str(id)
	if not _packaged[group].has(key):
		# Dynamic load avoids a preload cycle; the library registers defaults before overlaying.
		var library_script: Script = load("res://scripts/base_pose_library.gd" if is_base else "res://scripts/posture_library.gd")
		var _library: RefCounted = library_script.new()
	var value: Resource = _packaged[group].get(key)
	return value.duplicate(true) if value != null else null


## In-place publication preserves references held by active players/controllers.
static func copy_values(source: Resource, target: Resource) -> Error:
	var identity := _identity(source)
	if identity.is_empty() or identity != _identity(target):
		return _fail(ERR_INVALID_DATA, "Pose identities do not match")
	var fields := _encode_fields(source)
	if fields.is_empty():
		return _fail(ERR_INVALID_DATA, "Pose has unsupported or out-of-range values")
	_apply_fields(target, fields)
	if identity.group == "postures":
		target.set_meta("mobile_grip_saved_generation", int(source.get_meta("mobile_grip_saved_generation", -1)))
		GripStore.apply_to_definition(target)
	return OK


## A portable whole-pose snapshot of the editor's current (possibly unsaved) copy.
## selected_stage is view context only: 0 wind-up, 1 contact/body, 2 finish.
## This never saves, publishes live values, or initializes a pose-library singleton.
## Returns an empty string on validation failure; callers can present last_error.
static func export_pose_json(def: Resource, selected_stage: int = 1) -> String:
	last_error = ""
	var identity := _identity(def)
	if identity.is_empty():
		_fail(ERR_INVALID_DATA, "Unknown pose type or ID")
		return ""
	var is_base: bool = identity.group == "base_poses"
	if selected_stage < 0 or selected_stage > 2 or (is_base and selected_stage != 1):
		_fail(ERR_INVALID_DATA, "Invalid selected stage for this pose kind")
		return ""
	var fields := _encode_fields(def)
	if fields.is_empty():
		_fail(ERR_INVALID_DATA, "Pose has unsupported or out-of-range values")
		return ""
	var packaged := _export_packaged_default(int(identity.id), is_base)
	if packaged == null:
		_fail(ERR_INVALID_DATA, "Pose ID is not available in the packaged poses")
		return ""
	var baseline := _encode_fields(packaged)
	if baseline.is_empty():
		_fail(ERR_INVALID_DATA, "Packaged pose cannot be fingerprinted")
		return ""
	var document := {
		"schema": EXPORT_SCHEMA, "version": EXPORT_VERSION, "scope": "whole_pose",
		"kind": "base" if is_base else "stroke", "id": int(identity.id),
		"name": packaged.display_name,
		"selected_stage": selected_stage,
		"selected_stage_name": "Body stance" if is_base else ["Wind-up", "Contact", "Finish"][selected_stage],
		"selected_stage_context": "Editor view only; fields contain the whole pose and all keyframes",
		"baseline_sha256": JSON.stringify(_canonical_export_value(baseline), "", true, true).sha256_text(),
		"fields": fields,
	}
	if not is_base:
		document.family = packaged.family
	var encoded := JSON.stringify(_canonical_export_value(document), "\t", true, true)
	if encoded.to_utf8_buffer().size() > MAX_EXPORT_BYTES:
		_fail(ERR_OUT_OF_MEMORY, "Pose JSON exceeds the 2 MiB size limit")
		return ""
	return encoded


static func _export_packaged_default(id: int, is_base: bool) -> Resource:
	var group := "base_poses" if is_base else "postures"
	var registered: Resource = _packaged[group].get(str(id))
	if registered != null:
		return registered.duplicate(true)
	# Cold export must not load private overrides or replace cached live poses.
	# The paths come only from these trusted packaged directories, never user data.
	var directory := "res://data/base_poses/" if is_base else "res://data/postures/"
	var files := ResourceLoader.list_directory(directory)
	files.sort()
	for file_name in files:
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var resource := ResourceLoader.load(directory + file_name, "", ResourceLoader.CACHE_MODE_IGNORE)
		if _identity(resource) == {"group": group, "id": str(id)}:
			return resource.duplicate(true)
	return null


## JSON has one number type. Normalize integral floats without changing values,
## so nested keyframe Dictionary literals and typed pose floats encode identically.
static func _canonical_export_value(value):
	if value is Dictionary:
		var copy: Dictionary = {}
		for key in value:
			copy[key] = _canonical_export_value(value[key])
		return copy
	if value is Array:
		var copy: Array = []
		for item in value:
			copy.append(_canonical_export_value(item))
		return copy
	if value is float and value == floor(value):
		return int(value)
	return value


static func _identity(def: Resource) -> Dictionary:
	if def == null:
		return {}
	if def.get_script() == BasePose and def.base_pose_id >= 0 and def.base_pose_id <= 21:
		return {"group": "base_poses", "id": str(def.base_pose_id)}
	if def.get_script() == Posture and def.posture_id >= 0 and def.posture_id <= 20:
		return {"group": "postures", "id": str(def.posture_id)}
	return {}


static func _fields(is_base: bool) -> Array:
	return COMMON_FIELDS + (BASE_FIELDS if is_base else STROKE_FIELDS)


## Fingerprints effective authored values, including any applied global grip.
## The bake itself and transient sampled metadata cannot authorize their source.
static func authored_fingerprint(def: Resource, scope: String = "stroke_authored") -> String:
	if def == null or def.get_script() != Posture: return ""
	var fields := _encode_fields(def, false)
	if fields.is_empty(): return ""
	return ElbowBake.fingerprint_fields(fields, scope, def.posture_id, def.paddle_hand)


static func _encode_fields(def: Resource, include_bake: bool = true) -> Dictionary:
	var is_base: bool = def.get_script() == BasePose
	var fields: Dictionary = {}
	for field in _fields(is_base):
		if field == "elbow_preset_bake" and not include_bake: continue
		var value = def.get(field)
		if field == "elbow_preset_bake":
			if not ElbowBake.valid(value): return {}
			fields[field] = value.duplicate(true)
		elif field in ["windup_body", "follow_through_body"]:
			if value == null:
				fields[field] = null
			elif value is Resource and value.get_script() == BodyKeyframe:
				var body: Dictionary = {}
				for key in value.values:
					if not key is String or not key in BodyKeyframe.FIELDS:
						return {}
					body[key] = _encode_value(PaddleRotation.field_value(key, value.values[key]))
				fields[field] = body
			else:
				return {}
		else:
			fields[field] = _encode_value(PaddleRotation.field_value(field, value))
	return fields if _valid_fields(fields, is_base) else {}


static func _encode_value(value):
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is PackedFloat32Array:
		return Array(value)
	if value is PackedVector3Array:
		var encoded: Array = []
		for point in value:
			encoded.append([point.x, point.y, point.z])
		return encoded
	return value


static func _valid_fields(fields, is_base: bool, nested: bool = false) -> bool:
	if not fields is Dictionary:
		return false
	var allowed: Array = BodyKeyframe.FIELDS if nested else _fields(is_base)
	# Top-level entries are complete snapshots. Reject partial edits that could
	# evade paired checks (for example changing only a contact zone minimum).
	if not nested:
		# Version 1 snapshots may predate additive spin/curve/body-position fields.
		# All older whole-pose fields remain mandatory.
		var required := allowed.duplicate()
		for additive in ["right_foot_pitch_deg", "left_foot_pitch_deg"]:
			if not fields.has(additive): required.erase(additive)
		if not is_base:
			for additive in ["paddle_in_hand_rotation_deg", "contact_curve", "body_position_offset", "elbow_preset_bake", "paddle_path_times", "paddle_path_offsets", "ready_curve_auto", "ready_curve_bow", "ready_curve_round", "ready_curve_dir_deg", "ready_curve_peak", "ready_path_times", "ready_path_offsets", "speed_lead_start", "speed_lead_end", "speed_strike_start", "speed_strike_end", "speed_finish_start", "speed_finish_end", "speed_lead_points", "speed_strike_points", "speed_finish_points", "paddle_path_tangents", "ready_path_tangents"]:
				if not fields.has(additive): required.erase(additive)
		if fields.size() != required.size() or not fields.has_all(required): return false
	var template: Resource = BasePose.new() if is_base else Posture.new()
	for field in fields:
		if not field is String or not field in allowed:
			return false
		var value = fields[field]
		if field == "elbow_preset_bake":
			if not ElbowBake.valid(value): return false
		elif field in ["windup_body", "follow_through_body"]:
			if value != null and not _valid_fields(value, false, true):
				return false
		elif template.get(field) is Vector3:
			if not _valid_vector(field, value):
				return false
		elif template.get(field) is PackedFloat32Array:   # path key times: progress inside (0, 1)
			if not value is Array or value.size() > MAX_PATH_POINTS: return false
			for k in value:
				if not (k is int or k is float) or not is_finite(float(k)) or k <= 0.0 or k >= 1.0: return false
		elif template.get(field) is PackedVector3Array:
			if not value is Array or value.size() > MAX_PATH_POINTS:
				return false
			for point in value:
				if not _valid_vector(field, point):
					return false
		elif template.get(field) is bool:
			if not value is bool:
				return false
		elif not _valid_number(field, value):
			return false
	if not nested and not is_base:
		for axis in ["x", "y"]:
			var low := "zone_%s_min" % axis
			var high := "zone_%s_max" % axis
			if fields.has(low) and fields.has(high) and fields[low] > fields[high]:
				return false
	return true


static func _valid_number(field: String, value) -> bool:
	if not (value is int or value is float) or not is_finite(float(value)):
		return false
	if INTEGER_MAX.has(field):
		return float(value) == floor(float(value)) and value >= 0 and value <= INTEGER_MAX[field]
	if field in UNIT_FIELDS:
		return value >= 0.0 and value <= 1.0
	if field == "weight_shift":
		return absf(value) <= 2.0
	if field == "shoulder_protraction_m":
		return value >= 0.0 and value <= 0.05
	if field.contains("duration") or field in ["recovery_time", "landing_lockout_time", "jump_window"]:
		return value >= 0.0 and value <= 10.0
	if field in POSITIVE_FIELDS:
		return value >= 0.0 and value <= 5.0
	# Generous finite envelopes include authored multi-turn grips and all editor ranges.
	return absf(value) <= (720.0 if field.ends_with("_deg") else 5.0)


static func _valid_vector(field: String, value) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for component in value:
		if not _valid_number(field, component):
			return false
	return true


static func _apply_fields(def: Resource, fields: Dictionary) -> void:
	if def.get_script() == Posture and not fields.is_empty() and not fields.has("elbow_preset_bake"):
		def.elbow_preset_bake = {}
	if not fields.is_empty():
		for additive in ["right_foot_pitch_deg", "left_foot_pitch_deg"]:
			if not fields.has(additive): def.set(additive, 0.0)
	if def.get_script() == Posture and not fields.is_empty() and not fields.has("body_position_offset"):
		def.body_position_offset = Vector3.ZERO
	if def.get_script() == Posture and not fields.is_empty() and not fields.has("contact_curve"):
		def.contact_curve = 0.5
	if def.get_script() == Posture and not fields.is_empty() and not fields.has("paddle_in_hand_rotation_deg"):
		def.paddle_in_hand_rotation_deg = 0.0
	if def.get_script() == Posture and not fields.is_empty() and not fields.has("paddle_path_times"):
		def.paddle_path_times = PackedFloat32Array(); def.paddle_path_offsets = PackedVector3Array()
	if def.get_script() == Posture and not fields.is_empty() and not fields.has("ready_path_times"):
		def.ready_path_times = PackedFloat32Array(); def.ready_path_offsets = PackedVector3Array()
	if def.get_script() == Posture and not fields.is_empty() and not fields.has("speed_lead_start"):
		for f in ["speed_lead_start", "speed_lead_end", "speed_strike_start", "speed_strike_end", "speed_finish_start", "speed_finish_end"]: def.set(f, -1.0)
	if def.get_script() == Posture and not fields.is_empty() and not fields.has("paddle_path_tangents"):
		def.paddle_path_tangents = PackedVector3Array(); def.ready_path_tangents = PackedVector3Array()
	if def.get_script() == Posture and not fields.is_empty() and not fields.has("speed_lead_points"):
		for f in ["speed_lead_points", "speed_strike_points", "speed_finish_points"]: def.set(f, PackedVector3Array())
	if def.get_script() == Posture and not fields.is_empty() and not fields.has("ready_curve_bow"):
		def.ready_curve_auto = 1.0; def.ready_curve_bow = 0.0; def.ready_curve_round = 0.5; def.ready_curve_dir_deg = 0.0; def.ready_curve_peak = 0.5
	for field in fields:
		var value = fields[field]
		if field in ["windup_body", "follow_through_body"]:
			if value == null:
				def.set(field, null)
			else:
				var body := BodyKeyframe.new()
				for key in value:
					body.values[key] = PaddleRotation.field_value(key, _decode_value(key, value[key]))
				def.set(field, body)
		else:
			def.set(field, PaddleRotation.field_value(field, _decode_value(field, value)))


static func _decode_value(field: String, value):
	if field == "elbow_preset_bake": return value.duplicate(true)
	if field in ["paddle_path_times", "ready_path_times"]: return PackedFloat32Array(value)
	if field in ["right_elbow_path", "left_elbow_path", "paddle_path_offsets", "ready_path_offsets", "speed_lead_points", "speed_strike_points", "speed_finish_points", "paddle_path_tangents", "ready_path_tangents"]:
		var path := PackedVector3Array()
		for point in value:
			path.append(Vector3(point[0], point[1], point[2]))
		return path
	if value is Array:
		return Vector3(value[0], value[1], value[2])
	if INTEGER_MAX.has(field):
		return int(value)
	return value


static func _empty_document() -> Dictionary:
	return {"version": 1, "postures": {}, "base_poses": {}}


## Fixed, explicitly approved release imports only. Each pose has an independent
## receipt and recovery record in the same atomic file as its replacement.
## Read-time migration skips absent overrides; an ordinary save/reset stamps all
## receipts, including absent poses, so later user edits always remain newer.
static func _prepare_approved_pose_imports(document: Dictionary, include_absent: bool = true) -> bool:
	var changed := false
	for id in APPROVED_POSE_IMPORTS:
		if not include_absent and not document.postures.has(id): continue
		var approved: Script = APPROVED_POSE_IMPORTS[id]
		if document.get("approved_imports", {}).has(approved.ID): continue
		var previous = document.postures.get(id)
		var previous_generation = document.get("grip_generations", {}).get(id)
		var receipt := {
			"baseline_sha256": approved.BASELINE_SHA256,
			"source_sha256": approved.SOURCE_SHA256,
			"previous_pose": previous.duplicate(true) if previous is Dictionary else null,
			"previous_grip_generation": previous_generation,
		}
		if previous is Dictionary:
			var payload: Dictionary = JSON.parse_string(approved.JSON_TEXT)
			var fields: Dictionary = approved.applied_fields() if approved.has_method("applied_fields") else payload.fields.duplicate(true)
			var defaults := _encode_fields(_export_packaged_default(int(id), false))
			for additive in ["paddle_in_hand_rotation_deg", "contact_curve", "body_position_offset", "right_foot_pitch_deg", "left_foot_pitch_deg", "paddle_path_times", "paddle_path_offsets", "ready_curve_auto", "ready_curve_bow", "ready_curve_round", "ready_curve_dir_deg", "ready_curve_peak", "ready_path_times", "ready_path_offsets", "speed_lead_start", "speed_lead_end", "speed_strike_start", "speed_strike_end", "speed_finish_start", "speed_finish_end", "speed_lead_points", "speed_strike_points", "speed_finish_points", "paddle_path_tangents", "ready_path_tangents"]:
				if not fields.has(additive): fields[additive] = previous.get(additive, defaults[additive])
			for stage in ["windup_body", "follow_through_body"]:
				# Sparse legacy keys are intentional: absence inherits Contact. Only
				# preserve an omitted channel introduced after the supplied schema.
				if fields[stage] is Dictionary and previous.get(stage) is Dictionary:
					for additive in ["paddle_in_hand_rotation_deg", "body_position_offset", "right_foot_pitch_deg", "left_foot_pitch_deg"]:
						if not fields[stage].has(additive) and previous[stage].has(additive):
							fields[stage][additive] = previous[stage][additive]
			document.postures[id] = fields
			if not document.has("grip_generations"): document.grip_generations = {}
			document.grip_generations[id] = GripStore.current_generation()
		if not document.has("approved_imports"): document.approved_imports = {}
		document.approved_imports[approved.ID] = receipt
		changed = true
	return changed


static func _valid_approved_imports(receipts) -> bool:
	if not receipts is Dictionary or receipts.is_empty() or receipts.size() > APPROVED_IMPORT_HISTORY.size(): return false
	var allowed: Dictionary = {}
	for approved in APPROVED_IMPORT_HISTORY:
		allowed[approved.ID] = approved
	for key in receipts:
		if not key is String or not allowed.has(key): return false
		var approved: Script = allowed[key]
		var receipt = receipts[key]
		if not receipt is Dictionary or receipt.size() != 4 or not receipt.has_all([
			"baseline_sha256", "source_sha256", "previous_pose", "previous_grip_generation"]): return false
		if receipt.baseline_sha256 != approved.BASELINE_SHA256 or receipt.source_sha256 != approved.SOURCE_SHA256: return false
		if receipt.previous_pose != null and not _valid_fields(receipt.previous_pose, false): return false
		if receipt.previous_grip_generation != null and (receipt.previous_pose == null or not GripStore.valid_generation(receipt.previous_grip_generation)): return false
	return true


static func _read_document() -> Dictionary:
	var path := storage_path()
	if not FileAccess.file_exists(path):
		return {"error": OK, "document": _empty_document()}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": _fail(FileAccess.get_open_error(), "Cannot read saved poses")}
	if file.get_length() > MAX_FILE_BYTES:
		file.close()
		return {"error": _fail(ERR_FILE_CORRUPT, "Saved poses exceed the size limit")}
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not _valid_document(json.data):
		return {"error": _fail(ERR_FILE_CORRUPT, "Saved poses are invalid; existing file was preserved")}
	return {"error": OK, "document": json.data}


static func _valid_document(document) -> bool:
	if not document is Dictionary or not document.has_all(["version", "postures", "base_poses"]): return false
	if document.size() != 3 + (1 if document.has("grip_generations") else 0) + (1 if document.has("approved_imports") else 0): return false
	if document.has("approved_imports") and not _valid_approved_imports(document.approved_imports): return false
	if document.has("grip_generations"):
		if not document.grip_generations is Dictionary or not document.postures is Dictionary: return false
		for id in document.grip_generations:
			if not id is String or not document.postures.has(id) or not GripStore.valid_generation(document.grip_generations[id]): return false
	if not (document.version is int or document.version is float) or document.version != 1:
		return false
	for group in ["postures", "base_poses"]:
		if not document[group] is Dictionary:
			return false
		var max_id: int = 21 if group == "base_poses" else 20
		for key in document[group]:
			if not key is String or not key.is_valid_int() or str(key.to_int()) != key or key.to_int() < 0 or key.to_int() > max_id:
				return false
			if not _valid_fields(document[group][key], group == "base_poses"):
				return false
	return true


static func _write_document(document: Dictionary) -> Error:
	var path := storage_path()
	var temporary := path + ".tmp"
	var mkdir_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if mkdir_error != OK:
		return _fail(mkdir_error, "Cannot create the pose save folder")
	var encoded := JSON.stringify(document, "\t", true, true)
	if encoded.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return _fail(ERR_OUT_OF_MEMORY, "Saved poses exceed the size limit")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _fail(FileAccess.get_open_error(), "Cannot write the temporary pose file")
	file.store_string(encoded)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return _fail(write_error, "Pose write failed; previous save was preserved")
	if FileAccess.get_file_as_string(temporary) != encoded:
		DirAccess.remove_absolute(temporary)
		return _fail(ERR_FILE_CORRUPT, "Pose write verification failed; previous save was preserved")
	# Same-directory rename replaces the destination atomically on mobile filesystems.
	# Never delete the last good file first, including on a failed rename.
	var rename_error := DirAccess.rename_absolute(temporary, path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary)
		return _fail(rename_error, "Pose replacement failed; previous save was preserved")
	return OK


static func _fail(error: Error, message: String) -> Error:
	last_error = message
	return error
