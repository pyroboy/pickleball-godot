extends RefCounted
## Bounded publication/one-use ownership only. Offers are never collision proof.
## Physical earliest-event selection remains MatchContactAuthority's job.
const MAX_ACTORS := 4
var _generation := 0
var _serial := 0
var _interval: Dictionary = {}
var _roster: Dictionary = {}
var _poses: Dictionary = {}
var _offers: Dictionary = {}
var _claims: Dictionary = {}
var _sealed := false

func reset() -> void:
	_generation += 1
	_interval.clear(); _roster.clear(); _poses.clear(); _offers.clear(); _claims.clear(); _sealed = false

func begin(interval: Dictionary, actors: Array) -> bool:
	reset()
	# native_serial identifies the actual sampled ball interval. Its duration
	# is supplied by the owner; this queue never substitutes current TPS.
	for key in ["frame", "reset_epoch", "flight", "native_serial", "seconds"]:
		if not interval.has(key): return false
	if not _primitive(interval): return false
	if not is_finite(float(interval.seconds)) or float(interval.seconds) <= 0.0 or actors.is_empty() or actors.size() > MAX_ACTORS: return false
	var roster: Dictionary = {}
	for actor in actors:
		if not actor is Dictionary: return false
		for key in ["actor_id", "team_id", "court_side", "instance_id"]:
			if not actor.has(key): return false
		var id: int = actor.actor_id
		if id < 0 or roster.has(id) or int(actor.team_id) not in [0, 1] or int(actor.court_side) not in [0, 1] or int(actor.instance_id) <= 0: return false
		roster[id] = actor.duplicate(true)
	_interval = interval.duplicate(true); _roster = roster
	return true

func matches_interval(interval: Dictionary) -> bool:
	return not _interval.is_empty() and _interval == interval

func publish_pose(actor_id: int, instance_id: int, interval: Dictionary, version: PackedByteArray) -> bool:
	if _sealed or not matches_interval(interval) or not _roster.has(actor_id) or version.is_empty(): return false
	if int(_roster[actor_id].instance_id) != instance_id: return false
	_poses[actor_id] = version.duplicate()
	return true

func offer(actor_id: int, instance_id: int, interval: Dictionary, stroke_serial: int, endpoint_version: PackedByteArray, intent: Dictionary) -> Dictionary:
	if _sealed or not matches_interval(interval) or not _roster.has(actor_id) or endpoint_version.is_empty(): return {"valid": false, "reason": "stale_interval"}
	if int(_roster[actor_id].instance_id) != instance_id or not _primitive(intent): return {"valid": false, "reason": "invalid_identity_or_payload"}
	# One publication per actor/frame. Repeated probes cannot silently replace
	# the commitment; callers must explicitly cancel before a new offer.
	if _offers.has(actor_id): return {"valid": false, "reason": "duplicate_offer"}
	_serial += 1
	var entry: Dictionary = {"token": _serial, "generation": _generation, "actor": _roster[actor_id].duplicate(true),
		"interval": _interval.duplicate(true), "stroke_serial": stroke_serial, "endpoint_version": endpoint_version.duplicate(), "intent": intent.duplicate(true)}
	_offers[actor_id] = entry
	return {"valid": true, "token": _serial}

func cancel(actor_id: int, token: int) -> bool:
	if not _offers.has(actor_id) or int(_offers[actor_id].token) != token: return false
	_offers.erase(actor_id); _claims.erase(token)
	return true

func seal(interval: Dictionary) -> bool:
	if _sealed or not matches_interval(interval) or _poses.size() != _roster.size(): return false
	for id in _roster:
		if not _poses.has(id): return false
	_sealed = true
	return true

func eligible(actor_id: int, instance_id: int, interval: Dictionary, stroke_serial: int) -> Dictionary:
	if not _sealed or not matches_interval(interval) or not _offers.has(actor_id): return {}
	var entry: Dictionary = _offers[actor_id]
	if int(entry.actor.instance_id) != instance_id or int(entry.stroke_serial) != stroke_serial or entry.endpoint_version != _poses[actor_id] or _claims.has(entry.token): return {}
	return entry.duplicate(true)

func claim(actor_id: int, instance_id: int, interval: Dictionary, stroke_serial: int) -> Dictionary:
	var entry: Dictionary = eligible(actor_id, instance_id, interval, stroke_serial)
	if entry.is_empty(): return {}
	_claims[entry.token] = true
	return entry

func finish_claim(token: int, generation: int) -> bool:
	if generation != _generation or not _claims.has(token): return false
	_claims.erase(token)
	for actor_id in _offers:
		if int(_offers[actor_id].token) == token:
			_offers.erase(actor_id)
			return true
	return false

func pending_count() -> int:
	return _offers.size()

static func _primitive(value: Variant, depth: int = 0) -> bool:
	return _bounded_finite(value, depth, [2048])

static func _bounded_finite(value: Variant, depth: int, remaining: Array) -> bool:
	remaining[0] -= 1
	if remaining[0] < 0 or depth > 12 or value is Object or value is Callable or value is Signal or value is RID: return false
	if value is float: return is_finite(value)
	if value is Vector2 or value is Vector3 or value is Vector4 or value is Quaternion or value is Basis or value is Transform2D or value is Transform3D: return value.is_finite()
	if value is AABB: return value.position.is_finite() and value.size.is_finite()
	if value is Plane: return value.normal.is_finite() and is_finite(value.d)
	if value is Color: return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
	if value is String or value is StringName: return str(value).length() <= 1024
	if value is Dictionary:
		if value.size() > 64: return false
		for key in value:
			if not _bounded_finite(key, depth + 1, remaining) or not _bounded_finite(value[key], depth + 1, remaining): return false
	elif value is Array or value is PackedFloat32Array or value is PackedFloat64Array or value is PackedVector2Array or value is PackedVector3Array or value is PackedVector4Array or value is PackedColorArray or value is PackedStringArray:
		if value.size() > 512: return false
		for item in value:
			if not _bounded_finite(item, depth + 1, remaining): return false
	elif value is PackedByteArray or value is PackedInt32Array or value is PackedInt64Array:
		if value.size() > 4096: return false
	return true

static func controller_payload(intent: Dictionary) -> bool:
	if not _primitive(intent): return false
	var fields: Array = []
	if intent.get("kind", "") == "human":
		fields = ["kind", "flight", "stroke_serial", "elapsed", "strike_time", "control_seconds", "charge_ratio", "spin_mode", "shot_intent", "target", "motion_context"]
		if intent.size() != fields.size(): return false
		for key in fields:
			if not intent.has(key): return false
		for key in ["flight", "stroke_serial", "spin_mode"]:
			if not intent[key] is int: return false
		for key in ["elapsed", "strike_time", "control_seconds", "charge_ratio"]:
			if not (intent[key] is float or intent[key] is int): return false
		return intent.shot_intent is String and intent.target is Vector3 and intent.motion_context is Dictionary and float(intent.strike_time) > 0.0 and float(intent.control_seconds) >= 0.0 and float(intent.charge_ratio) >= 0.0 and float(intent.charge_ratio) <= 1.0 and int(intent.spin_mode) in [0, 1, 2]
	elif intent.get("kind", "") == "ai":
		fields = ["kind", "flight", "observed_flight", "execution_token", "execution_active", "execution_flight", "charge_time", "observation_time", "deadline", "deadline_flight", "posture", "selected_time", "context", "planned_shot", "motion_context"]
		if intent.size() != fields.size(): return false
		for key in fields:
			if not intent.has(key): return false
		for key in ["flight", "observed_flight", "execution_token", "execution_flight", "deadline_flight", "posture"]:
			if not intent[key] is int: return false
		for key in ["charge_time", "observation_time", "deadline", "selected_time"]:
			if not (intent[key] is float or intent[key] is int): return false
		return intent.execution_active is bool and intent.context is Dictionary and intent.planned_shot is Dictionary and intent.motion_context is Dictionary and float(intent.charge_time) >= 0.0
	return false
