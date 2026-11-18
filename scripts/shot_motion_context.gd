extends RefCounted

# A strike owns one immutable snapshot. Planning/held previews may replace their
# snapshot, but a committed strike must keep it until recovery has finished.
const VERSION: int = 1
const PROFILES: Array[String] = ["LEGACY", "BLOCK", "RESET", "PUNCH", "COUNTER", "ROLL", "FLICK", "HALF_VOLLEY", "JAMMED", "OFFENSIVE_LOB", "SMASH"]

static func commit(base: PostureDefinition, raw: Dictionary) -> Dictionary:
	var velocity: Vector3 = _vector(raw.get("incoming_velocity", Vector3.ZERO), 60.0)
	var fallback: = Vector3(base.paddle_forehand_mul, maxf(0.08, 1.0 + base.paddle_y_offset), base.paddle_forward_mul)
	var local: Vector3 = _vector(raw.get("contact_local", fallback), 4.0)
	local.y = clampf(_number(raw.get("contact_height", local.y), local.y), 0.05, 3.5)
	var bounces: int = clampi(int(_number(raw.get("bounces", 0 if bool(raw.get("is_volley", false)) else 1), 1)), 0, 2)
	var context: Dictionary = {
		"version": VERSION,
		"incoming_velocity": velocity,
		"incoming_speed": minf(60.0, velocity.length()),
		"contact_local": local,
		"contact_height": local.y,
		"bounces": bounces,
		"is_volley": bounces == 0,
		"time_since_bounce": clampf(_number(raw.get("time_since_bounce", -1.0), -1.0), -1.0, 10.0),
		"time_to_contact": clampf(_number(raw.get("time_to_contact", 1.0), 1.0), 0.0, 5.0),
		"charge": clampf(_number(raw.get("charge", 0.5), 0.5), 0.0, 1.0),
		"spin_mode": clampi(int(_number(raw.get("spin_mode", 0), 0)), 0, 2),
		"shot_intent": _label(raw.get("shot_intent", "AUTO"), "AUTO"),
		"shot_type": _label(raw.get("shot_type", "GROUNDSTROKE"), "GROUNDSTROKE"),
		"tactic": _label(raw.get("tactic", ""), ""),
		"target": _vector(raw.get("target", Vector3.ZERO), 20.0),
		"arc": clampf(_number(raw.get("arc", 0.0), 0.0), -0.5, 0.6),
		"near_kitchen": bool(raw.get("near_kitchen", false)),
		"flight_id": int(clampf(_number(raw.get("flight_id", 0), 0), 0, 2147483647)),
		"ball_behind": bool(raw.get("ball_behind", false)),
		"lob_retrieval": bool(raw.get("lob_retrieval", false)),
		"recovery_kind": _label(raw.get("recovery_kind", ""), ""),
		"velocity_source": _label(raw.get("velocity_source", "OBSERVED"), "OBSERVED"),
		"bounce_age_source": _label(raw.get("bounce_age_source", "OBSERVED"), "OBSERVED"),
		"required_bounces": clampi(int(_number(raw.get("required_bounces", bounces), bounces)), 0, 2),
	}
	context["profile"] = "LEGACY" if raw.is_empty() else select_profile(base, context)
	context.make_read_only()
	return context

static func select_profile(base: PostureDefinition, context: Dictionary) -> String:
	var intent: String = str(context.get("shot_intent", "AUTO"))
	var tactic: String = str(context.get("tactic", ""))
	var shot_type: String = str(context.get("shot_type", "GROUNDSTROKE"))
	var height: float = float(context.get("contact_height", 1.0))
	var pace: float = float(context.get("incoming_speed", 0.0))
	var charge: float = float(context.get("charge", 0.5))
	var volley: bool = bool(context.get("is_volley", false))
	var side: float = absf((context.get("contact_local", Vector3.ONE) as Vector3).x)
	# These modules do not own serve delivery or the overhead's authored geometry.
	if shot_type == "SERVE" or tactic == "SERVE" or base.posture_id in [9, 20]: return "LEGACY"
	if base.family == 3:
		if tactic == "SMASH" or shot_type == "SMASH" or intent == "SMASH": return "SMASH"
		if not (tactic == "SPEED_UP" and base.posture_id == 3):
			if height >= 1.5 and intent != "DROP" and charge >= 0.48: return "SMASH"
			return "LEGACY"
	# Intent wins over pace; a player deliberately choosing a lob should see lift.
	var target: Vector3 = context.get("target", Vector3.ZERO)
	if tactic == "LOB" or shot_type == "LOB" or intent == "LOB" or (float(context.get("arc", 0.0)) >= 0.3 and absf(target.z) >= 3.8):
		return "OFFENSIVE_LOB"
	var since: float = float(context.get("time_since_bounce", -1.0))
	if int(context.get("bounces", 0)) == 1 and height <= 0.5 and since >= 0.0 and since <= 0.22:
		return "HALF_VOLLEY"
	# Center corridor, short forward reach, and actual arriving pace identify a
	# jam. A centered soft dink is not automatically a body-ball emergency.
	if side <= 0.22 and height >= 0.4 and height <= 1.5 and pace >= 6.0 and float((context.get("contact_local", Vector3.ONE) as Vector3).z) <= 0.56:
		return "JAMMED"
	if tactic == "RESET" or intent == "RESET": return "RESET"
	if volley:
		if intent == "DROP" or tactic in ["DROP", "DINK"]: return "RESET" if pace >= 7.0 else "BLOCK"
		if pace >= 8.0 and charge < 0.48: return "BLOCK"
		# Incoming pace owns the compact counter; topspin does not require a long roll.
		if pace >= 8.0 and charge >= 0.48: return "COUNTER"
		if int(context.get("spin_mode", 0)) == 1 and charge >= 0.45:
			return "FLICK" if height >= 1.0 and pace < 8.0 and float(context.get("time_to_contact", 1.0)) <= 0.18 else "ROLL"
		if charge >= 0.38 or tactic == "SPEED_UP": return "PUNCH"
	return "LEGACY"

static func _number(value: Variant, fallback: float) -> float:
	if not (value is float or value is int): return fallback
	var number: float = float(value)
	return number if is_finite(number) else fallback

static func _vector(value: Variant, bound: float) -> Vector3:
	if not value is Vector3: return Vector3.ZERO
	var vector: Vector3 = value
	if not vector.is_finite(): return Vector3.ZERO
	return vector.limit_length(bound)

static func _label(value: Variant, fallback: String) -> String:
	return str(value).strip_edges().to_upper().left(32) if value is String or value is StringName else fallback
