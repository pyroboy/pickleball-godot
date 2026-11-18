extends RefCounted

const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Styles = preload("res://scripts/ai_playing_styles.gd")
const Kitchen = preload("res://scripts/ai_kitchen_tactics.gd")
const SMASH_MIN_OVER_NET := 0.6    # m above the net at contact (~1.5 m: medium overhead)
const SMASH_MAX_DEPTH := 6.0       # m from the net
const BACKCOURT_LOB_SHARE := 0.12  # of balanced back-court shots

# The roll chooses only among shots suited to this contact. There is no miss roll.
static func _choose_base(context: Dictionary, roll: float) -> String:
	var height: float = float(context.get("ball_height", 1.0))
	var net: float = float(context.get("net_height", 1.05))
	var depth: float = float(context.get("net_distance", 5.0))
	var opponent_depth: float = absf(context.get("opponent", Vector3(0, 0, 6)).z)
	var balanced: bool = bool(context.get("balanced", true))
	var stretched: bool = float(context.get("contact_distance", 0.7)) > 1.0
	var moving_fast: bool = float(context.get("movement_speed", 0.0)) > 2.6
	var rushed: bool = float(context.get("incoming_speed", 0.0)) >= 9.0 or stretched or moving_fast or not balanced
	# Occasional lob from the back (also on the opening return / third shot), so
	# rallies have high balls and smash chances at all; before this, 0 of 151
	# AI shots in 3 bench matches went more than 0.22 m above the net.
	if depth > 4.5 and balanced and not rushed and roll > 1.0 - BACKCOURT_LOB_SHARE:
		return "LOB"
	if bool(context.get("opening_return", false)):
		return "RETURN"
	# Overhead: a ball well above the net, met balanced and within reach, is
	# smashed from anywhere up to mid-court (was only near the kitchen, and only
	# after an attack roll). The launch is still validated to clear the net.
	var difficulty: int = clampi(int(context.get("difficulty", 1)), 0, 2)
	if height >= net + SMASH_MIN_OVER_NET and depth <= SMASH_MAX_DEPTH and balanced and not stretched and not moving_fast:
		if roll < [0.55, 0.75, 0.9][difficulty]: return "SMASH"
	if height < net + 0.28 and rushed:
		return "DROP" if depth > 4.5 else "RESET"
	if depth <= 3.4:
		if height >= net + 0.18 and balanced and not stretched and not moving_fast:
			var attack_context: Dictionary = context.duplicate()
			attack_context["near_kitchen"] = true
			if roll < Kitchen.attack_probability(attack_context):
				return Kitchen.attack_kind(attack_context)
		# A controlled lob is useful only with the opponent forward and time to set.
		if opponent_depth < 3.3 and height > 0.7 and balanced and not rushed and roll > 0.86:
			return "LOB"
		return "DINK"
	if height < net + 0.1 or opponent_depth < 3.5 and roll < 0.72:
		return "DROP"
	if opponent_depth < 3.2 and balanced and not rushed and roll > 0.87:
		return "LOB"
	return "DRIVE"

static func eligible_distribution(context: Dictionary) -> Dictionary:
	# Exact intervals from the existing policy. Styles cannot introduce a shot
	# that this same observed situation disallows. Physical solve stays later.
	var attack_context: Dictionary = context.duplicate()
	attack_context["near_kitchen"] = true
	var smash_p: float = [0.55, 0.75, 0.9][clampi(int(context.get("difficulty", 1)), 0, 2)]
	var boundaries: Array = [0.0, clampf(Kitchen.attack_probability(attack_context), 0.0, 1.0), 0.72, 0.86, 0.87, 1.0 - BACKCOURT_LOB_SHARE, smash_p, 1.0]
	boundaries.sort()
	var out: Dictionary = {}
	for i in range(boundaries.size() - 1):
		var width: float = float(boundaries[i + 1]) - float(boundaries[i])
		if width <= 0.0: continue
		var kind: String = _choose_base(context, (float(boundaries[i]) + float(boundaries[i + 1])) * 0.5)
		out[kind] = float(out.get(kind, 0.0)) + width
	return out

static func choose(context: Dictionary, roll: float) -> String:
	var style: int = Styles.valid_id(context.get("style_id", 0))
	if style == 0: return _choose_base(context, roll)
	var options: Dictionary = Styles.reweight(eligible_distribution(context), style)
	var remaining: float = clampf(roll, 0.0, 0.999999999)
	for kind in options:
		remaining -= float(options[kind])
		if remaining < 0.0: return kind
	return _choose_base(context, roll)

static func plan(context: Dictionary, roll: float, placement: float) -> Dictionary:
	var kind: String = choose(context, roll)
	var difficulty: int = clampi(int(context.get("difficulty", 0)), 0, 2)
	var direction: float = -1.0 if int(context.get("court_side", context.get("player_num", 1))) == 0 else 1.0
	var opponent: Vector3 = context.get("opponent", Vector3(0, 0, direction * 6.0))
	var origin: Vector3 = context.get("origin", Vector3(0, 1, -direction * 5.0))
	var style: int = Styles.valid_id(context.get("style_id", 0))
	var width: float = [1.25, 1.9, 2.25][difficulty] * float(Styles.PROFILES[style].placement_risk)
	var lane: float = lerpf(-width, width, placement)
	if absf(opponent.x) > 0.65:
		lane = -signf(opponent.x) * lerpf(width * 0.35, width, placement)
	var depth: float = lerpf(4.7, 5.75, placement)
	var charge: float = [0.24, 0.42, 0.58][difficulty]
	var shot_type: String = "GROUNDSTROKE"
	var intent: String = "AUTO"
	var arc: float = 0.0
	var spin_mode: int = 0
	if kind in ["DROP", "RESET", "DINK"]:
		intent = "DROP"
		shot_type = "DINK" if kind == "DINK" else "DROP"
		depth = lerpf(1.15, 1.5, placement)
		# Resets buy recovery time through the middle, away from sidelines.
		lane = clampf(origin.x * 0.3, -0.8, 0.8) if kind == "RESET" else lane * 0.75
		charge = 0.16 if kind == "RESET" else 0.22
	elif kind == "RETURN":
		lane *= 0.7
		charge = [0.12, 0.25, 0.36][difficulty]
		arc = 0.12
	elif kind == "LOB":
		shot_type = "LOB"
		charge = 0.08
		arc = 0.42
		depth = 5.55
	elif kind in ["SMASH", "SPEED_UP"]:
		shot_type = "SMASH" if kind == "SMASH" else "VOLLEY"
		charge = Kitchen.attack_charge(context)
		depth = 4.3 if kind == "SMASH" else 4.9
		if kind == "SPEED_UP" and bool(context.get("balanced", false)):
			# Punch a clearly elevated ball or counter incoming pressure. A lower
			# balanced attack needs upward brushing; its actual selected contact
			# horizon distinguishes the compact flick from the longer roll in
			# ShotMotionContext. Keep this spin decision in the committed plan.
			var height: float = float(context.get("ball_height", origin.y))
			var net: float = float(context.get("net_height", 1.05))
			var incoming: float = float(context.get("incoming_speed", 0.0))
			if incoming < 8.0 and height < net + 0.45: spin_mode = 1
	var perf = Engine.get_main_loop().root.get_node_or_null("PerfMonitor") if Engine.get_main_loop() is SceneTree else null
	if perf != null: perf.note("ai_plan", {"actor": int(context.get("actor_id", -1)), "team": int(context.get("team_id", -1)), "kind": kind,
		"h": snappedf(float(context.get("ball_height", 0.0)), 0.01), "net": snappedf(float(context.get("net_height", 1.0)), 0.01),
		"depth": snappedf(float(context.get("net_distance", 0.0)), 0.01), "reach": snappedf(float(context.get("contact_distance", 0.0)), 0.01),
		"balanced": bool(context.get("balanced", true)), "legal_volley": bool(context.get("legal_volley", false)), "opening": bool(context.get("opening_return", false))})
	return {"style_id": style, "kind": kind, "target": Vector3(lane, Flight.FLOOR_REST_Y, direction * depth),
		"charge": charge, "shot_type": shot_type, "intent": intent, "arc": arc, "spin_mode": spin_mode}

static func solve(physics: ShotPhysics, origin: Vector3, context: Dictionary, roll: float, placement: float) -> Dictionary:
	return solve_plan(physics, origin, context, plan(context, roll, placement))

static func solve_plan(physics: ShotPhysics, origin: Vector3, context: Dictionary, planned: Dictionary) -> Dictionary:
	var shot: Dictionary = planned.duplicate(true)
	var team: int = int(context.get("court_side", context.get("player_num", 1)))
	var launch: Dictionary = physics.solve_aimed_launch(origin, shot.target, shot.charge, team, int(shot.get("spin_mode", 0)), shot.intent, shot.shot_type, shot.arc)
	if not valid_launch(origin, launch, team):
		# Safe physical alternative when the chosen shape cannot clear the net.
		shot.kind = "RESET" if absf(origin.z) <= 4.5 else "DROP"
		shot.target = Vector3(clampf(origin.x * 0.25, -0.8, 0.8), Flight.FLOOR_REST_Y, (-1.0 if team == 0 else 1.0) * 1.5)
		shot.charge = 0.18
		shot.intent = "DROP"
		shot.shot_type = "DROP"
		shot.arc = 0.0
		shot.spin_mode = 0
		launch = physics.solve_drop_launch(origin, shot.charge, team, 0, shot.target)
	if not valid_launch(origin, launch, team):
		return {}
	launch["tactic"] = shot.kind
	var perf = Engine.get_main_loop().root.get_node_or_null("PerfMonitor") if Engine.get_main_loop() is SceneTree else null
	if perf != null: perf.note("ai_launch", {"actor": int(context.get("actor_id", -1)), "kind": shot.kind,
		"origin": [snappedf(origin.x, 0.01), snappedf(origin.y, 0.01), snappedf(origin.z, 0.01)],
		"vel": [snappedf(launch.velocity.x, 0.01), snappedf(launch.velocity.y, 0.01), snappedf(launch.velocity.z, 0.01)]})
	shot.make_read_only()
	launch["motion_plan"] = shot
	return launch

static func valid_launch(origin: Vector3, launch: Dictionary, team: int) -> bool:
	if launch.is_empty() or not launch.get("velocity", Vector3.INF).is_finite(): return false
	var flight: Dictionary = Flight.trace(origin, launch.velocity, launch.omega, 3.0, 1, false)
	var landing: Vector3 = flight.first_bounce
	var direction: float = -1.0 if team == 0 else 1.0
	return float(flight.first_bounce_time) > 0.0 and not flight.net_hit and not flight.net_crossing.is_empty() \
		and absf(landing.x) < 2.8 and landing.z * direction > 0.3 and landing.z * direction < 6.4
