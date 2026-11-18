extends RefCounted
const Rotation = preload("res://scripts/paddle_rotation.gd")
## App-private data-only serve keyframes. Authored deltas overlay the original
## release/bounce/strike curves; delivery clocks and ball contact remain owned by
## the serve pipeline. save() persists, copy_values() explicitly publishes live.
const ApprovedFlat = preload("res://scripts/approved_flat_serve_import.gd")
# Append-only receipt history; retain this entry when a later release replaces Flat.
const APPROVED_IMPORT_HISTORY := [ApprovedFlat]
const ContactOrientation = preload("res://scripts/serve_contact_orientation.gd")
const GripStore = preload("res://scripts/mobile_paddle_grip_store.gd")
const Posture = preload("res://scripts/posture_definition.gd")
const BodyKey = preload("res://scripts/stroke_body_keyframe.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const ContactCurve = preload("res://scripts/contact_paddle_curve.gd")
const PoseStore = preload("res://scripts/mobile_pose_store.gd")
const DEFAULT_PATH := "user://mobile_serve_pose_overrides_v1.json"
const MAX_FILE_BYTES := 8388608
const MAX_EXPORT_BYTES := 2097152
const STYLE_NAMES := ["Flat", "Topspin", "Slice", "High Soft", "Drop Drive", "Banana", "Screwball"]
const PADDLE_FIELDS := ["paddle_forehand_mul", "paddle_y_offset", "paddle_forward_mul", "paddle_pitch_base_deg", "paddle_yaw_base_deg", "paddle_roll_base_deg"]
const PLANTED_FIELDS := ["stance_width", "front_foot_forward", "back_foot_back", "right_foot_yaw_deg", "left_foot_yaw_deg", "right_foot_pitch_deg", "left_foot_pitch_deg", "right_foot_offset", "left_foot_offset", "lead_foot"]
const LOCKED_FIELDS := ["left_hand_mode", "paddle_pitch_signed_deg", "paddle_yaw_signed_deg", "paddle_roll_signed_deg", "paddle_pitch_sign_source", "paddle_yaw_sign_source", "paddle_roll_sign_source", "support_grip_rotation_deg", "support_grip_slide_m"]
const HELD_FIELDS := ["left_hand_offset", "left_elbow_pole", "left_shoulder_rotation_deg", "shoulder_protraction_m", "support_index_closure", "support_grip_style"]
static var last_error := ""
static var _test_path := ""
static var _defaults: Dictionary = {}
static var _live: Dictionary = {}
static var _active: Dictionary = {}
static var _deltas: Dictionary = {}
static var _stances: Dictionary = {}
static var _curve_bends: Dictionary = {}
static var revision := 0
static var _loaded := false

static func style_id(def: Resource) -> int:
	if def == null or def.get_script() != Posture or not def.has_meta("mobile_serve_style"): return -1
	var value = def.get_meta("mobile_serve_style")
	if not value is int or value < 0 or value >= STYLE_NAMES.size() or def.posture_id != value: return -1
	return int(value)

static func is_serve(def: Resource) -> bool:
	return style_id(def) >= 0

static func allowed_fields(stage: int) -> Array:
	var result: Array = []
	if stage < 0 or stage > 2: return result
	for field in BodyKey.FIELDS:
		if field in LOCKED_FIELDS or (stage == 0 and field in HELD_FIELDS) or (stage != 0 and field in PLANTED_FIELDS): continue
		result.append(field)
	result.append_array(PADDLE_FIELDS if stage != 1 else PADDLE_FIELDS.slice(3))
	return result

static func is_field_editable(stage: int, field: String) -> bool:
	return field in allowed_fields(stage)

static func storage_path() -> String:
	return DEFAULT_PATH if _test_path.is_empty() else _test_path

static func set_test_path(path: String) -> Error:
	if path != "" and (not path.begins_with("user://pose_store_tests/") or ".." in path or not path.ends_with(".json")):
		return ERR_INVALID_PARAMETER
	_test_path = path
	_live.clear(); _active.clear(); _deltas.clear(); _stances.clear(); _curve_bends.clear(); _loaded = false; revision = 0
	return OK

static func _default(style: int) -> PostureDefinition:
	if style < 0 or style >= STYLE_NAMES.size(): return null
	if not _defaults.has(style):
		# Dynamic loading keeps the runtime Motion -> Store dependency acyclic.
		# Explicit use_saved=false makes these snapshots independent of disk/live edits.
		var preview: Script = load("res://scripts/posture_editor_v2/runtime_motion_preview.gd")
		var contact: PostureDefinition = preview.sample_serve(style, 0.5, 1.0, 1.0, null, false)
		var windup: PostureDefinition = preview.sample_serve(style, 0.0, 1.0, 1.0, null, false)
		var finish: PostureDefinition = preview.sample_serve(style, 1.0, 1.0, 1.0, null, false)
		var initial: PostureDefinition = preview.sample_serve(style, 0.0, 0.0, 1.0, null, false)
		# A serve plants its initial stance, rather than stepping between keys.
		for field in PLANTED_FIELDS:
			for key in [windup, contact, finish]: key.set(field, initial.get(field))
		contact.posture_id = style
		contact.display_name = STYLE_NAMES[style] + " Serve"
		contact.set_meta("mobile_serve_style", style)
		_write_endpoint(contact, windup, 0)
		_write_endpoint(contact, finish, 2)
		_defaults[style] = contact
	return _defaults[style]

static func packaged_default(style: int) -> PostureDefinition:
	var def: PostureDefinition = _default(style)
	if def == null: return null
	var result: PostureDefinition = def.duplicate(true)
	if style == 0: PoseStore._apply_fields(result, JSON.parse_string(ApprovedFlat.JSON_TEXT).fields)
	return result

static func get_default(style: int) -> PostureDefinition:
	return packaged_default(style)

static func all_definitions() -> Array:
	_ensure_loaded()
	var result: Array = []
	for style in range(STYLE_NAMES.size()): result.append(get_def(style))
	return result

static func get_def(style: int) -> PostureDefinition:
	if style < 0 or style >= STYLE_NAMES.size(): return null
	_ensure_loaded()
	if not _live.has(style):
		_live[style] = packaged_default(style)
		GripStore.apply_to_definition(_live[style])
		_refresh_runtime(style)
	return _live[style]

static func endpoint(def: PostureDefinition, stage: int) -> PostureDefinition:
	return Path.endpoint(def, stage)

static func _write_endpoint(def: PostureDefinition, pose: PostureDefinition, stage: int) -> void:
	var offset := Vector3(pose.paddle_forehand_mul - def.paddle_forehand_mul, pose.paddle_y_offset - def.paddle_y_offset, pose.paddle_forward_mul - def.paddle_forward_mul)
	var rotation := Vector3(pose.paddle_pitch_base_deg - def.paddle_pitch_base_deg, pose.paddle_yaw_base_deg - def.paddle_yaw_base_deg, pose.paddle_roll_base_deg - def.paddle_roll_base_deg)
	var body := BodyKey.new(); body.capture(pose)
	if stage == 0:
		def.charge_paddle_offset = offset; def.charge_paddle_rotation_deg = Rotation.vector(rotation); def.windup_body = body
	else:
		def.ft_paddle_offset = offset; def.ft_paddle_rotation_deg = Rotation.vector(rotation); def.follow_through_body = body

static func sample(def: PostureDefinition, progress: float) -> PostureDefinition:
	var style := style_id(def)
	if style < 0: return null
	var preview: Script = load("res://scripts/posture_editor_v2/runtime_motion_preview.gd")
	var sampled: PostureDefinition = preview.sample_serve(style, progress, 1.0, 1.0, def, false)
	sampled.set_meta("mobile_serve_planted_stance", true)
	return sampled

static func raw_pose(pose: PostureDefinition) -> PostureDefinition:
	return pose.get_meta("mobile_serve_baseline", pose) as PostureDefinition

## Carry a held Strong extension through reapplication of the same saved
## orientation correction. The former component subtraction was only valid
## for additive Euler edits and could reintroduce a branch/full-turn snap.
static func carry_extension_baseline(pose: PostureDefinition, extended: PostureDefinition) -> PostureDefinition:
	var raw:PostureDefinition=raw_pose(pose).duplicate(true)
	var correction:Basis=Rotation.displayed_basis(raw).inverse()*Rotation.displayed_basis(pose)
	for field in PADDLE_FIELDS.slice(0,3):
		raw.set(field,raw.get(field)+extended.get(field)-pose.get(field))
	var display:Basis=Rotation.displayed_basis(extended)*correction.inverse()
	Rotation.set_basis(raw,display*Basis(Vector3.UP,deg_to_rad(-raw.paddle_in_hand_rotation_deg)))
	return raw

## Applied after the authored sampler. Neutral Contact curve preserves its
## in-between motion; keyframe deltas and curve shaping use existing clocks.
static func apply_motion(baseline: PostureDefinition, style: int, weights: Vector3, custom: PostureDefinition = null, use_saved: bool = true) -> PostureDefinition:
	if custom == null and not use_saved: return baseline
	var def: PostureDefinition = custom
	if def == null:
		_ensure_loaded()
		if not _active.get(style, false) and not GripStore.has_global(): return baseline
		def = get_def(style)
		if not _active.get(style, false): return baseline
	if style_id(def) != style: return baseline
	var deltas: Array = _keyframe_deltas(def) if custom != null else _deltas.get(style, [])
	if deltas.is_empty(): return baseline
	var pose: PostureDefinition = baseline
	var stance: Dictionary = _planted_stance(def) if custom != null else _stances.get(style, {})
	for field in stance:
		if _same(baseline.get(field), stance[field]): continue
		if pose == baseline:
			pose = baseline.duplicate(true)
			pose.set_meta("mobile_serve_baseline", baseline)
		pose.set(field, stance[field])
	for stage in range(3):
		if is_zero_approx(weights[stage]): continue
		for field in deltas[stage]:
			if field in PLANTED_FIELDS or field == "__paddle_basis" or field in Rotation.BASE: continue
			if pose == baseline:
				pose = baseline.duplicate(true)
				pose.set_meta("mobile_serve_baseline", baseline)
			if field == "lead_foot":
				if weights[stage] >= 0.5: pose.set(field, deltas[stage][field])
				continue
			pose.set(field, pose.get(field) + deltas[stage][field] * weights[stage])
	var correction := Basis.IDENTITY
	var rotation_weight := 0.0
	for stage in range(3):
		var weight:float=maxf(0.0,weights[stage])
		if weight<=0.0:continue
		var frame:Basis=deltas[stage].get("__paddle_basis",Basis.IDENTITY)
		correction=frame if rotation_weight<=0.0 else Rotation.shortest(correction,frame,weight/(rotation_weight+weight))
		rotation_weight+=weight
	if rotation_weight>0.0 and not correction.is_equal_approx(Basis.IDENTITY):
		if pose==baseline:
			pose=baseline.duplicate(true);pose.set_meta("mobile_serve_baseline",baseline)
		var display:Basis=Rotation.displayed_basis(baseline)*Rotation.shortest(Basis.IDENTITY,correction,minf(rotation_weight,1.0))
		Rotation.set_basis(pose,display*Basis(Vector3.UP,deg_to_rad(-pose.paddle_in_hand_rotation_deg)))
	elif pose!=baseline and not is_equal_approx(pose.paddle_in_hand_rotation_deg,baseline.paddle_in_hand_rotation_deg):
		# An equivalent base/spin change must not rotate the displayed paddle.
		Rotation.set_basis(pose,Rotation.displayed_basis(baseline)*Basis(Vector3.UP,deg_to_rad(-pose.paddle_in_hand_rotation_deg)))
	if pose != baseline:
		# Keep physically bounded blend channels valid at every runtime charge.
		pose.crouch_amount = maxf(0.0, pose.crouch_amount)
		pose.stance_width = maxf(0.0, pose.stance_width)
		pose.weight_shift = clampf(pose.weight_shift, -2.0, 2.0)
		for field in ["head_track_ball_weight", "support_index_closure", "support_grip_style"]:
			pose.set(field, clampf(float(pose.get(field)), 0.0, 1.0))
	# The strike/follow-through clock supplies Contact weight; no ball timeline
	# or keyframe position is changed. Waiting/held/recovery remain untouched.
	if not is_equal_approx(def.contact_curve, 0.5) and weights.y > 0.0 and weights.y < 1.0:
		var progress: float = 0.5 * weights.y if weights.z <= 0.0 else 1.0 - 0.5 * weights.y
		var bend: Vector3 = _curve_bend(def) if custom != null else _curve_bends.get(style, Vector3.ZERO)
		if pose == baseline:
			pose = baseline.duplicate(true)
			pose.set_meta("mobile_serve_baseline", baseline)
		ContactCurve.apply(pose, bend, progress, def.contact_curve)
	if pose != baseline and weights.y > 0.0:
		ContactOrientation.apply_pivot(pose, baseline, weights.y)
	if pose != baseline:
		# Body-position edits remain relative to the fixed initial foot targets in
		# gameplay too, including when a saved pose refreshes a prepared server.
		pose.set_meta("mobile_serve_planted_stance", true)
	return pose

static func _curve_bend(def: PostureDefinition) -> Vector3:
	return ContactCurve.bend(ContactCurve.position(endpoint(def, 0)), ContactCurve.position(def), ContactCurve.position(endpoint(def, 2)))

static func _planted_stance(def: PostureDefinition) -> Dictionary:
	var windup: PostureDefinition = endpoint(def, 0)
	var result: Dictionary = {}
	for field in PLANTED_FIELDS: result[field] = windup.get(field)
	return result

## Built once when a live edit is published/loaded, not on every gameplay frame.
static func _keyframe_deltas(def: PostureDefinition) -> Array:
	var result: Array = []
	var original: PostureDefinition = _default(style_id(def))
	for stage in range(3):
		var delta: Dictionary = {}
		var authored: PostureDefinition = endpoint(def, stage)
		var packaged: PostureDefinition = endpoint(original, stage)
		for field in allowed_fields(stage):
			var a = authored.get(field); var b = packaged.get(field)
			if _same(a, b): continue
			var change = a - b
			if a is float and field.ends_with("_deg"): change = wrapf(float(change), -180.0, 180.0)
			delta[field] = a if field == "lead_foot" else change
		var correction:Basis=Rotation.displayed_basis(packaged).inverse()*Rotation.displayed_basis(authored)
		if not correction.is_equal_approx(Basis.IDENTITY):delta["__paddle_basis"]=correction
		result.append(delta)
	return result

static func _encode(def: Resource, generated_baseline: bool = false) -> Dictionary:
	if style_id(def) < 0: return {}
	var fields: Dictionary = PoseStore._encode_fields(def)
	if fields.is_empty(): return {}
	var base: PostureDefinition = _default(style_id(def)) if generated_baseline else packaged_default(style_id(def))
	# Reject ignored/locked edits rather than claiming they will apply in play.
	for stage in range(3):
		var a: PostureDefinition = endpoint(def, stage)
		var b: PostureDefinition = endpoint(base, stage)
		for field in BodyKey.FIELDS + PADDLE_FIELDS:
			if not is_field_editable(stage, field) and not _same(Rotation.field_value(field,a.get(field)), Rotation.field_value(field,b.get(field))): return {}
	var baseline_fields: Dictionary = PoseStore._encode_fields(base)
	var stored_editable: Array = allowed_fields(1) + ["charge_paddle_offset", "charge_paddle_rotation_deg", "ft_paddle_offset", "ft_paddle_rotation_deg", "windup_body", "follow_through_body", "contact_curve", "elbow_preset_bake"]
	for field in fields:
		if not field in stored_editable and fields[field] != baseline_fields[field]: return {}
	return fields

static func _same(a, b) -> bool:
	if a is float or a is int: return is_equal_approx(float(a), float(b))
	if a is Vector3: return a.is_equal_approx(b)
	return a == b

static func save(def: Resource) -> Error:
	last_error = ""
	var fields := _encode(def)
	if fields.is_empty(): return _fail(ERR_INVALID_DATA, "Serve has unsupported, locked, or out-of-range values")
	var loaded := _read_document()
	if loaded.error != OK: return loaded.error
	_prepare_approved_import(loaded.document)
	var key := str(style_id(def))
	loaded.document.serves[key] = fields
	if not loaded.document.has("grip_generations"): loaded.document.grip_generations = {}
	loaded.document.grip_generations[key] = GripStore.current_generation()
	var error := _write_document(loaded.document)
	if error == OK: def.set_meta("mobile_grip_saved_generation", GripStore.current_generation())
	return error

static func reset(def: Resource) -> Error:
	last_error = ""
	if style_id(def) < 0: return _fail(ERR_INVALID_DATA, "Unknown serve style")
	var loaded := _read_document()
	if loaded.error != OK: return loaded.error
	var receipt_added := _prepare_approved_import(loaded.document)
	var key := str(style_id(def))
	if not loaded.document.serves.has(key): return _write_document(loaded.document) if receipt_added else OK
	loaded.document.serves.erase(key)
	if loaded.document.has("grip_generations"): loaded.document.grip_generations.erase(key)
	return _write_document(loaded.document)

static func copy_values(source: Resource, target: Resource) -> Error:
	last_error = ""
	var style := style_id(source)
	if style < 0 or style != style_id(target): return _fail(ERR_INVALID_DATA, "Serve identities do not match")
	var fields := _encode(source)
	if fields.is_empty(): return _fail(ERR_INVALID_DATA, "Serve has unsupported, locked, or out-of-range values")
	PoseStore._apply_fields(target, fields)
	target.set_meta("mobile_grip_saved_generation", int(source.get_meta("mobile_grip_saved_generation", -1)))
	GripStore.apply_to_definition(target)
	if _live.get(style) == target:
		_refresh_runtime(style)
		revision += 1
	return OK

static func export_pose_json(def: Resource, selected_stage: int = 1) -> String:
	last_error = ""
	if selected_stage < 0 or selected_stage > 2:
		_fail(ERR_INVALID_DATA, "Invalid serve stage"); return ""
	var fields := _encode(def)
	if fields.is_empty():
		_fail(ERR_INVALID_DATA, "Serve has unsupported, locked, or out-of-range values"); return ""
	var style := style_id(def)
	var baseline: Dictionary = PoseStore._encode_fields(packaged_default(style))
	var document := {"schema": "pickleball.pose", "version": 1, "scope": "whole_pose", "kind": "serve", "id": style,
		"name": _default(style).display_name, "selected_stage": selected_stage,
		"selected_stage_name": ["Wind-up", "Contact", "Finish"][selected_stage],
		"selected_stage_context": "Editor view only; fields contain all three keyframes",
		"baseline_sha256": JSON.stringify(PoseStore._canonical_export_value(baseline), "", true, true).sha256_text(),
		"sampling": "Additive keyframe deltas on the generated serve; delivery and paddle contact remain constrained", "fields": fields}
	var encoded := JSON.stringify(PoseStore._canonical_export_value(document), "\t", true, true)
	if encoded.to_utf8_buffer().size() > MAX_EXPORT_BYTES:
		_fail(ERR_OUT_OF_MEMORY, "Serve JSON exceeds the 2 MiB size limit"); return ""
	return encoded

static func _ensure_loaded() -> void:
	if _loaded: return
	_loaded = true
	var loaded := _read_document()
	if loaded.error != OK:
		push_warning("MobileServePoseStore: " + last_error + "; using packaged serves")
		# The approved packaged Flat remains active even when a private file is corrupt.
		_live[0] = packaged_default(0)
		GripStore.apply_to_definition(_live[0]); _refresh_runtime(0)
		revision += 1
		return
	if _prepare_approved_import(loaded.document, false):
		if _write_document(loaded.document) != OK:
			push_warning("MobileServePoseStore: " + last_error + "; approved Flat is active for this session only")
	# Approved Flat is now a packaged runtime edit, even on a fresh installation.
	_live[0] = packaged_default(0)
	GripStore.apply_to_definition(_live[0]); _refresh_runtime(0)
	for key in loaded.document.serves:
		var style: int = int(key)
		_live[style] = packaged_default(style)
		PoseStore._apply_fields(_live[style], loaded.document.serves[key])
		_live[style].set_meta("mobile_grip_saved_generation", int(loaded.document.get("grip_generations", {}).get(key, -1)))
		GripStore.apply_to_definition(_live[style])
		_refresh_runtime(style)
	if _active.values().has(true): revision += 1

static func _refresh_runtime(style: int) -> void:
	_deltas[style] = _keyframe_deltas(_live[style])
	_stances[style] = _planted_stance(_live[style])
	_curve_bends[style] = _curve_bend(_live[style])
	_active[style] = not is_equal_approx(_live[style].contact_curve, 0.5) or _deltas[style].any(func(frame): return not frame.is_empty())

static func refresh_global_grips() -> void:
	if not _loaded: return
	var loaded := _read_document()
	if loaded.error != OK:
		for style in _live:
			GripStore.apply_to_definition(_live[style], true)
			_refresh_runtime(style)
		revision += 1
		return
	for style in _live:
		var raw: PostureDefinition = packaged_default(style)
		PoseStore._apply_fields(raw, loaded.document.serves.get(str(style), {}))
		PoseStore.copy_grip_values(raw, _live[style])
		_live[style].set_meta("mobile_grip_saved_generation", int(loaded.document.get("grip_generations", {}).get(str(style), -1)))
		GripStore.apply_to_definition(_live[style])
		_refresh_runtime(style)
	revision += 1

static func _empty_document() -> Dictionary:
	return {"version": 1, "serves": {}}

static func _valid_document(document) -> bool:
	if not document is Dictionary or not document.has_all(["version", "serves"]): return false
	if document.size() != 2 + (1 if document.has("grip_generations") else 0) + (1 if document.has("approved_imports") else 0): return false
	if document.has("approved_imports") and not _valid_approved_imports(document.approved_imports): return false
	if document.has("grip_generations"):
		if not document.grip_generations is Dictionary or not document.serves is Dictionary: return false
		for id in document.grip_generations:
			if not id is String or not document.serves.has(id) or not GripStore.valid_generation(document.grip_generations[id]): return false
	if not (document.version is float or document.version is int) or document.version != 1 or not document.serves is Dictionary: return false
	for key in document.serves:
		if not key is String or not key.is_valid_int() or str(int(key)) != key or int(key) < 0 or int(key) >= STYLE_NAMES.size(): return false
		if not PoseStore._valid_fields(document.serves[key], false): return false
		# Unmigrated Flat records are validated against their generated baseline.
		# Only that fixed eligible record can differ from newly packaged locked fields.
		var legacy_flat: bool = key == "0" and not document.get("approved_imports", {}).has(ApprovedFlat.ID)
		var def: PostureDefinition = _default(0).duplicate(true) if legacy_flat else packaged_default(int(key))
		PoseStore._apply_fields(def, document.serves[key])
		if _encode(def, legacy_flat).is_empty(): return false
	return true


## Requested Contact rotations remain authored data. Physical bounds are shown
## explicitly, rather than silently discarding a persisted orientation.
static func contact_diagnostics(def: PostureDefinition, player = null) -> Dictionary:
	if style_id(def) < 0: return {"limited": false, "warning": ""}
	return ContactOrientation.diagnostics(sample(def, 0.5), player)

static func contact_warning(def: PostureDefinition, player = null) -> String:
	return str(contact_diagnostics(def, player).warning)

## Atomic, once-only release migration. A normal Save/Reset stamps the receipt
## even for an absent override so a later explicit user edit stays authoritative.
static func _prepare_approved_import(document: Dictionary, include_absent: bool = true) -> bool:
	if document.get("approved_imports", {}).has(ApprovedFlat.ID): return false
	if not include_absent and not document.serves.has("0"): return false
	var previous = document.serves.get("0")
	var generation = document.get("grip_generations", {}).get("0")
	var receipt := {"baseline_sha256": ApprovedFlat.BASELINE_SHA256, "source_sha256": ApprovedFlat.SOURCE_SHA256,
		"previous_pose": previous.duplicate(true) if previous is Dictionary else null, "previous_grip_generation": generation}
	if previous is Dictionary:
		var fields:Dictionary=JSON.parse_string(ApprovedFlat.JSON_TEXT).fields.duplicate(true)
		# These channels were introduced after the approved JSON was supplied.
		# Preserve explicit later requests instead of silently replacing them.
		for additive in ["right_foot_pitch_deg","left_foot_pitch_deg"]:
			if not fields.has(additive):fields[additive]=previous.get(additive,0.0)
		for stage in ["windup_body","follow_through_body"]:
			if fields[stage] is Dictionary and previous.get(stage) is Dictionary:
				for additive in ["right_foot_pitch_deg","left_foot_pitch_deg"]:
					if not fields[stage].has(additive) and previous[stage].has(additive):fields[stage][additive]=previous[stage][additive]
		document.serves["0"] = fields
		if not document.has("grip_generations"): document.grip_generations = {}
		document.grip_generations["0"] = GripStore.current_generation()
	if not document.has("approved_imports"): document.approved_imports = {}
	document.approved_imports[ApprovedFlat.ID] = receipt
	return true

static func _valid_approved_imports(receipts) -> bool:
	if not receipts is Dictionary or receipts.is_empty() or receipts.size() > APPROVED_IMPORT_HISTORY.size(): return false
	var allowed: Dictionary = {}
	for approved in APPROVED_IMPORT_HISTORY: allowed[approved.ID] = approved
	for key in receipts:
		if not key is String or not allowed.has(key): return false
		var approved: Script = allowed[key]
		var receipt = receipts[key]
		if not receipt is Dictionary or receipt.size() != 4 or not receipt.has_all(["baseline_sha256", "source_sha256", "previous_pose", "previous_grip_generation"]): return false
		if receipt.baseline_sha256 != approved.BASELINE_SHA256 or receipt.source_sha256 != approved.SOURCE_SHA256: return false
		if receipt.previous_pose != null and not PoseStore._valid_fields(receipt.previous_pose, false): return false
		if receipt.previous_grip_generation != null and (receipt.previous_pose == null or not GripStore.valid_generation(receipt.previous_grip_generation)): return false
	return true

static func _read_document() -> Dictionary:
	var path := storage_path()
	if not FileAccess.file_exists(path): return {"error": OK, "document": _empty_document()}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"error": _fail(FileAccess.get_open_error(), "Cannot read saved serves")}
	if file.get_length() > MAX_FILE_BYTES:
		file.close(); return {"error": _fail(ERR_FILE_CORRUPT, "Saved serves exceed the size limit")}
	var json := JSON.new(); var parse_error := json.parse(file.get_as_text()); file.close()
	if parse_error != OK or not _valid_document(json.data): return {"error": _fail(ERR_FILE_CORRUPT, "Saved serves are invalid; existing file was preserved")}
	return {"error": OK, "document": json.data}

static func _write_document(document: Dictionary) -> Error:
	var path := storage_path(); var temporary := path + ".tmp"
	var mkdir_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if mkdir_error != OK: return _fail(mkdir_error, "Cannot create the serve save folder")
	var encoded := JSON.stringify(document, "\t", true, true)
	if encoded.to_utf8_buffer().size() > MAX_FILE_BYTES: return _fail(ERR_OUT_OF_MEMORY, "Saved serves exceed the size limit")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return _fail(FileAccess.get_open_error(), "Cannot write the temporary serve file")
	file.store_string(encoded); file.flush(); var write_error := file.get_error(); file.close()
	if write_error != OK or FileAccess.get_file_as_string(temporary) != encoded:
		DirAccess.remove_absolute(temporary)
		return _fail(ERR_FILE_CORRUPT if write_error == OK else write_error, "Serve write failed; previous save was preserved")
	var rename_error := DirAccess.rename_absolute(temporary, path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary)
		return _fail(rename_error, "Serve replacement failed; previous save was preserved")
	return OK

static func _fail(error: Error, message: String) -> Error:
	last_error = message
	return error
