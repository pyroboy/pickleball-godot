extends RefCounted


static func attack_probability(context: Dictionary) -> float:
	if not context.get("near_kitchen", false) or not context.get("legal_volley", false): return 0.0
	if not context.get("reachable", false) or not context.get("balanced", false): return 0.0
	if not context.get("reaction_ready", false): return 0.0
	var excess: float = float(context.get("ball_height", 0.0)) - float(context.get("net_height", 1.0))
	if excess < 0.12: return 0.0
	var height_factor: float = clampf((excess - 0.05) / 0.65, 0.15, 1.0)
	var difficulty: int = clampi(int(context.get("difficulty", 1)), 0, 2)
	return [0.32, 0.58, 0.82][difficulty] * height_factor

static func choose(context: Dictionary, roll: float) -> String:
	if not context.get("near_kitchen", false): return "NORMAL"
	return "ATTACK" if roll < attack_probability(context) else "SOFT"



static func attack_kind(context: Dictionary) -> String:
	var height: float = float(context.get("ball_height", 0.0))
	var net: float = float(context.get("net_height", 1.0))
	var distance: float = float(context.get("net_distance", 2.2))
	var reach: float = float(context.get("contact_distance", 0.8))
	return "SMASH" if height >= net + 0.72 and distance <= 3.25 and reach <= 1.05 else "SPEED_UP"

static func attack_charge(context: Dictionary) -> float:
	var difficulty: int = clampi(int(context.get("difficulty", 1)), 0, 2)
	return [0.62, 0.76, 0.88][difficulty] if attack_kind(context) == "SMASH" else [0.46, 0.58, 0.7][difficulty]

static func response_kind(context: Dictionary, roll: float) -> String:
	if float(context.get("incoming_speed", 0.0)) >= 9.5 and float(context.get("ball_height", 0.0)) < float(context.get("net_height", 1.0)) + 0.55:
		return "RESET"
	return attack_kind(context) if choose(context, roll) == "ATTACK" else "SOFT"
