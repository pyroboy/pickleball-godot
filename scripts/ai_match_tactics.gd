extends RefCounted

const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Styles = preload("res://scripts/ai_playing_styles.gd")
const Kitchen = preload("res://scripts/ai_kitchen_tactics.gd")
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")
const Tuning = preload("res://scripts/gameplay_tuning.gd")
const SMASH_MIN_OVER_NET := 0.6    # m above the net at contact (~1.5 m: medium overhead)
const SMASH_MAX_DEPTH := 6.0       # m from the net
const LOB_SHARE := 0.3         # rally lobs from mid-court back
const LOB_SHARE_VS_NET := 0.45 # ... when the opponent is at the kitchen line
# Lob shape: deep and only as high as it needs to be. Before (arc 0.42, depth 5.55) it went
# 5 m up and came down short: 2.3-2.5 m high at 4.4 m from the net, so the net player
# stepped back and smashed it (bench: 37 of 89 lobs smashed, 2% won the point).
const LOB_ARC := 0.2      # extra flight time over the flattest solution (x1.2 s)
const LOB_DEPTH := 5.9    # m from the net (safe-risk shots must land inside 6.0)
const SOFT_NET_MARGIN := 0.2   # m a dink / reset / drop is planned to clear the net by

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
	# Opening return / third shot must bounce on the other side, so a high one
	# can't be smashed: no lobs there (the returns already arc high).
	if bool(context.get("opening_return", false)):
		return "RETURN"
	# Overhead first: a ball well above the net, met balanced and within reach,
	# is smashed from anywhere up to mid-court (was only near the kitchen, after
	# an attack roll). The launch is still validated to clear the net.
	var difficulty: int = clampi(int(context.get("difficulty", 1)), 0, 2)
	# No balance requirement: players smash right after moving under the ball.
	# Reach for an overhead is judged along the court: the straight-line distance
	# to a ball 2.4 m up always read as "stretched", so lobs were never smashed.
	var overhead_stretched: bool = float(context.get("contact_horizontal", context.get("contact_distance", 0.7))) > 1.0
	if height >= net + SMASH_MIN_OVER_NET and depth <= SMASH_MAX_DEPTH and not overhead_stretched and not moving_fast:
		if roll < [0.55, 0.75, 0.9][difficulty]: return "SMASH"
	# Rally lobs make the high balls that can be smashed: over an opponent at
	# the kitchen line more often, otherwise now and then from mid-court back.
	# (Bench: 290 of 374 rejected high contacts were opening shots; rally
	# shots were almost all low, 7 lobs in 280 AI shots.)
	var lob_share: float = LOB_SHARE_VS_NET if opponent_depth < 3.5 else LOB_SHARE
	# Rushed counts too: under pressure from the back, a defensive lob is the
	# classic reply (nearly every rally shot was "rushed", so this gate made
	# lobs rarer, not more common).
	if depth > 3.4 and roll > 1.0 - lob_share:
		return "LOB"
	# Pop-up: attack a ball well over the tape even on the move (roll).
	if roll < Kitchen.popup_attack_probability(context):
		var popup_context: Dictionary = context.duplicate()
		popup_context["near_kitchen"] = true
		return Kitchen.attack_kind(popup_context)
	# Firefight: counter a fast ball met at or above the net (roll), else block it.
	if roll < Kitchen.counter_probability(context): return "SPEED_UP"
	# Patience runs out: a low speed-up, decided by its own per-flight roll.
	if float(context.get("patience_roll", 1.0)) < Kitchen.low_speedup_probability(context): return "SPEED_UP"
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
	# Deep recovery: reset into the kitchen and move up behind it (POSITION_PLAN.md).
	if Tuning.BRACE_ON and RuntimePolicy.position_rules_for(int(context.get("team_id", -1))) and depth > Tuning.RESET_DEEP_FROM and height < net + 0.3 and opponent_depth < 3.5 \
			and fposmod(float(context.get("position_roll", 1.0)) * 7.0, 1.0) < float(Tuning.RESET_FROM_DEEP[difficulty]):
		return "DROP" if depth > 4.5 else "RESET"
	if Tuning.DRIVES_ON and depth > Tuning.DRIVE_MIN_DEPTH and not stretched and roll < float(Tuning.DRIVE_SHARE[difficulty]) * Kitchen.stamina_aggression(context):
		return "DRIVE"
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
	var boundaries: Array = [0.0, clampf(Kitchen.attack_probability(attack_context), 0.0, 1.0), 0.72, 0.86, 0.87, 1.0 - LOB_SHARE, 1.0 - LOB_SHARE_VS_NET, smash_p, 1.0]
	if Tuning.DRIVES_ON: boundaries.append(float(Tuning.DRIVE_SHARE[clampi(int(context.get("difficulty", 1)), 0, 2)]) * Kitchen.stamina_aggression(context))
	if Tuning.COUNTER_ON: boundaries.append(Kitchen.counter_probability(context))
	if Tuning.POPUP_ATTACK_ON: boundaries.append(Kitchen.popup_attack_probability(context))
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
	var pressure: bool = RuntimePolicy.pressure_team >= 0 and int(context.get("team_id", -1)) == RuntimePolicy.pressure_team and not bool(context.get("opening_return", false))
	if pressure: kind = "SMASH" if float(context.get("ball_height", 0.0)) >= float(context.get("net_height", 1.05)) + SMASH_MIN_OVER_NET else "DRIVE"
	var difficulty: int = clampi(int(context.get("difficulty", 0)), 0, 2)
	var run_t: int = _run_target(context, pressure, placement)
	# Run them: lob back over the tired opponent when both are at the line.
	if run_t >= 0 and kind in ["DINK", "RESET", "DROP"] and not bool(context.get("opening_return", false)) \
			and float(context.get("ball_height", 0.0)) > 0.7 and bool(context.get("balanced", true)) and float(context.get("contact_distance", 0.7)) <= 1.0 \
			and absf(context.opponents[0].z) < 3.2 and absf(context.opponents[1].z) < 3.2 \
			and fposmod(placement * Tuning.SALT_RUN * 0.79, 1.0) < float(Tuning.RUN_LOB[difficulty]):
		kind = "LOB"
	var direction: float = -1.0 if int(context.get("court_side", context.get("player_num", 1))) == 0 else 1.0
	var opponent: Vector3 = context.get("opponent", Vector3(0, 0, direction * 6.0))
	var origin: Vector3 = context.get("origin", Vector3(0, 1, -direction * 5.0))
	var style: int = Styles.valid_id(context.get("style_id", 0))
	var width: float = [1.25, 1.9, 2.25][difficulty] * float(Styles.PROFILES[style].placement_risk)
	var risk: String = risk_level(context)
	var R: Dictionary = Tuning.RISK[risk]
	width = maxf(0.6, width + float(R.lane)) if Tuning.RISK_ON else width
	var lane: float = lerpf(-width, width, placement)
	if absf(opponent.x) > 0.65:
		lane = -signf(opponent.x) * lerpf(width * 0.35, width, placement)
	var depth: float = lerpf(float(R.deep[0]), float(R.deep[1]), placement) if Tuning.RISK_ON else lerpf(4.7, 5.75, placement)
	var aim: String = ""
	var charge: float = [0.24, 0.42, 0.58][difficulty]
	var shot_type: String = "GROUNDSTROKE"
	var intent: String = "AUTO"
	var arc: float = 0.0
	var spin_mode: int = 0
	var cross_court: bool = false
	if kind in ["DROP", "RESET", "DINK"]:
		intent = "DROP"
		shot_type = "DINK" if kind == "DINK" else "DROP"
		depth = lerpf(1.15, 1.5, placement)
		if kind == "RESET":
			# Resets used to land in the same middle spot every time. Now about half
			# go cross-court, a third through the middle and the rest down the line,
			# at varied depth, all still inside the kitchen and clear of the sidelines.
			var side: float = signf(origin.x) if absf(origin.x) >= 0.3 else (signf(opponent.x) if absf(opponent.x) >= 0.3 else (1.0 if placement < 0.5 else -1.0))
			var spread: float = fposmod(placement * 7.0, 1.0)   # second value from the same roll
			if placement < 0.5:
				cross_court = true
				lane = -side * lerpf(0.9, 1.9, spread)
			elif placement < 0.82:
				lane = lerpf(-0.6, 0.6, spread)
			else:
				lane = side * lerpf(0.9, 1.7, spread)
			depth = lerpf(1.0, 1.8, fposmod(placement * 13.0, 1.0))
		else:
			lane *= 0.75
		charge = 0.16 if kind == "RESET" else 0.22
		# Cross-court dink: from off-centre, go diagonally (lowest part of the net,
		# longest kitchen) when the opponent stands straight ahead, and about half
		# the time otherwise.
		if kind == "DINK" and absf(origin.x) >= 0.5 and (opponent.x * origin.x > 0.0 or placement >= 0.5):
			cross_court = true
			lane = -signf(origin.x) * lerpf(1.3, 2.0, placement)
			depth = lerpf(1.2, 1.7, placement)
			if Tuning.RISK_ON and risk == "aggressive" and Tuning.WIDE_DINKS:
				# Wide cross-court dink toward the sideline: pulls the receiver wide
				# and is what gives Erne chances (GAME_MECHANICS_PLAN change 8).
				lane = -signf(origin.x) * lerpf(Tuning.WIDE_DINK_LANE.x, Tuning.WIDE_DINK_LANE.y, placement)
				depth = lerpf(1.0, 1.5, placement)
	elif kind == "RETURN":
		lane *= 0.7
		charge = [0.12, 0.25, 0.36][difficulty]
		arc = 0.12
	elif kind == "LOB":
		shot_type = "LOB"
		charge = 0.08
		arc = LOB_ARC
		depth = LOB_DEPTH
	elif kind in ["SMASH", "SPEED_UP"]:
		shot_type = "SMASH" if kind == "SMASH" else "VOLLEY"
		charge = Kitchen.attack_charge(context)
		depth = 4.3 if kind == "SMASH" else 4.9
		var low_excess: float = float(context.get("ball_height", 0.0)) - float(context.get("net_height", 1.0))
		if Tuning.ATTACK_CHARGE_ON and not Tuning.AIM_AWAY and (kind == "SMASH" or low_excess >= 0.18):
			# Put the pop-up away: at the nearest opponent's feet or hip, or the gap.
			var opp_t: Vector3 = _nearest_opponent(context, origin)
			var opps_t: Array = context.get("opponents", [])
			if fposmod(placement * 5.0, 1.0) < 0.6 or opps_t.size() < 2:
				# At the feet (lands just in front) and off the hip, not into the chest.
				lane = clampf(opp_t.x + Tuning.ATTACK_FEET_OFFSET.x, -2.6, 2.6)
				depth = clampf(absf(opp_t.z) - Tuning.ATTACK_FEET_OFFSET.y, 2.3, 6.0)
			else:
				lane = clampf((opps_t[0].x + opps_t[1].x) * 0.5, -1.6, 1.6)
				depth = clampf((absf(opps_t[0].z) + absf(opps_t[1].z)) * 0.5, 2.3, 6.0)
		if kind == "SPEED_UP" and low_excess < 0.18 and (Tuning.PATIENCE_ON or Tuning.COUNTER_ON):
			# Low speed-up / counter: flatter and slower, at the body (by level) or
			# the off-hand hip, so it can be countered.
			charge = float(Tuning.LOW_SPEEDUP_CHARGE[difficulty])
			var target_opp: Vector3 = _nearest_opponent(context, origin)
			if not Tuning.AIM_AWAY and fposmod(placement * 5.0, 1.0) < float(Tuning.LOW_SPEEDUP_AT_BODY[difficulty]):
				lane = clampf(target_opp.x + 0.25, -2.6, 2.6)
				depth = clampf(absf(target_opp.z) - 0.3, 2.4, 6.0)
		if kind == "SPEED_UP" and bool(context.get("balanced", false)):
			# Punch a clearly elevated ball or counter incoming pressure. A lower
			# balanced attack needs upward brushing; its actual selected contact
			# horizon distinguishes the compact flick from the longer roll in
			# ShotMotionContext. Keep this spin decision in the committed plan.
			var height: float = float(context.get("ball_height", origin.y))
			var net: float = float(context.get("net_height", 1.05))
			var incoming: float = float(context.get("incoming_speed", 0.0))
			if incoming < 8.0 and height < net + 0.45: spin_mode = 1
	# Through the middle / at the feet (second and third values from the same roll).
	var opps: Array = context.get("opponents", [])
	if kind in ["DRIVE", "DROP"] and Tuning.FEET_ON and not Tuning.AIM_AWAY and not pressure:
		for o in opps:
			var od: float = absf(o.z)
			if od > 3.0 and od < 5.5 and fposmod(placement * 17.0, 1.0) < 0.6:
				lane = clampf(o.x, -2.4, 2.4); depth = maxf(2.4, od - 0.4); aim = "feet"; cross_court = false
				break
	if aim == "" and kind in ["DINK", "RESET", "DRIVE", "SPEED_UP"] and Tuning.MIDDLE_ON and opps.size() == 2 and not pressure \
			and fposmod(placement * 11.0, 1.0) < Tuning.MIDDLE_SHARE:
		var gap_x: float = (opps[0].x + opps[1].x) * 0.5
		if absf(opps[0].x - opps[1].x) > 1.2:
			lane = clampf(gap_x, -1.5, 1.5); aim = "middle"; cross_court = false
	# Position read (POSITION_PLAN.md): the target follows where the opponents are and
	# where they are going, on this share of shots by level.
	if not pressure and opps.size() == 2 and RuntimePolicy.position_rules_for(int(context.get("team_id", -1))) and float(context.get("position_roll", 1.0)) < float(Tuning.POSITION_READ[difficulty]):
		var read: Dictionary = position_target(kind, opps, context.get("opponents_vel", []), lane, depth)
		if not read.is_empty() and not (Tuning.AIM_AWAY and read.aim in ["feet_running", "back_player_feet"]):
			lane = read.lane; depth = read.depth; aim = read.aim; cross_court = false
	# Run them: the tired opponent's half, the edge farther from where they are heading.
	if run_t >= 0:
		var ro: Vector3 = opps[run_t]
		if kind == "LOB" and absf(ro.z) < 3.2:
			lane = clampf(ro.x, -2.0, 2.0); aim = "lob_back"; cross_court = false
		elif aim in ["", "middle"] and kind in ["DINK", "RESET", "DROP", "DRIVE"] and fposmod(placement * Tuning.SALT_RUN, 1.0) < float(Tuning.RUN_SHARE[difficulty]):
			var rv: Array = context.get("opponents_vel", [])
			var px: float = ro.x + (0.4 * float(rv[run_t].x) if run_t < rv.size() else 0.0)
			var half: float = signf(ro.x) if absf(ro.x) > 0.3 else -signf(opps[1 - run_t].x + 0.001)
			var wide: float = half * Tuning.RUN_WIDE_LANE
			var inner: float = half * Tuning.RUN_INNER_LANE
			lane = wide if absf(wide - px) >= absf(inner - px) else inner
			aim = "run_wide"; cross_court = false
	# Short return (make them run): a soft, high return of serve that lands near the kitchen line.
	if kind == "RETURN" and Tuning.AIM_AWAY and not pressure and fposmod(placement * Tuning.SALT_SHORT_RETURN, 1.0) < float(Tuning.SHORT_RETURN_SHARE[difficulty]):
		depth = lerpf(Tuning.SHORT_RETURN_DEPTH.x, Tuning.SHORT_RETURN_DEPTH.y, fposmod(placement * 7.0, 1.0))
		charge = 0.1
		arc = 0.3
		if opps.size() == 2: lane = open_lane(opps, context.get("opponents_vel", []), depth, Tuning.OPEN_LANE_SOFT)
		aim = "short_return"; cross_court = false
	# Open court: no other aim, so put it where the opponents are not (they must move).
	var open_kinds: Array = ["DINK", "RESET", "DROP", "DRIVE", "RETURN"] + (["SPEED_UP", "SMASH"] if Tuning.AIM_AWAY else [])
	if aim == "" and not pressure and opps.size() == 2 and kind in open_kinds \
			and fposmod(placement * Tuning.SALT_OPEN, 1.0) < float(Tuning.OPEN_COURT_SHARE[difficulty]):
		lane = open_lane(opps, context.get("opponents_vel", []), depth, Tuning.OPEN_LANE_SOFT if depth < 2.5 else Tuning.OPEN_LANE_DEEP)
		aim = "open"; cross_court = false
	# Stamina strategy: put power shots on a tired opponent (their blocks pop up).
	if not pressure and not Tuning.AIM_AWAY and kind in ["DRIVE", "SPEED_UP", "SMASH"] and Tuning.STAMINA_STRATEGY_ON and RuntimePolicy.stamina_strategy_for(int(context.get("team_id", -1))):
		var opp_st: Array = context.get("opponents_stamina", [])
		if opps.size() == 2 and opp_st.size() == 2:
			var tired_i: int = 0 if float(opp_st[0]) <= float(opp_st[1]) else 1
			if float(opp_st[tired_i]) < Tuning.STAMINA_PENALTY_AT and absf(float(opp_st[0]) - float(opp_st[1])) > 10.0:
				lane = clampf(opps[tired_i].x + _side_of(opps[tired_i].x) * 0.4, -2.4, 2.4); aim = "tired_player"
	# Level gradient: pull a wide target in toward the opponent it is nearest to (not for lobs
	# or the short return, whose point is the distance).
	if Tuning.AIM_AWAY and not pressure and opps.size() == 2 and kind != "LOB" and aim != "short_return":
		var reach: float = float(Tuning.AIM_MAX_SIDEWAYS[difficulty])
		var near: Vector3 = opps[0] if absf(lane - opps[0].x) <= absf(lane - opps[1].x) else opps[1]
		if absf(lane - near.x) > reach:
			lane = clampf(near.x + signf(lane - near.x) * reach, -2.4, 2.4)
	if pressure: charge = 1.0
	var perf = Engine.get_main_loop().root.get_node_or_null("PerfMonitor") if Engine.get_main_loop() is SceneTree else null
	if perf != null: perf.note("ai_plan", {"actor": int(context.get("actor_id", -1)), "team": int(context.get("team_id", -1)), "kind": kind,
		"h": snappedf(float(context.get("ball_height", 0.0)), 0.01), "net": snappedf(float(context.get("net_height", 1.0)), 0.01),
		"depth": snappedf(float(context.get("net_distance", 0.0)), 0.01), "reach": snappedf(float(context.get("contact_distance", 0.0)), 0.01),
		"balanced": bool(context.get("balanced", true)), "legal_volley": bool(context.get("legal_volley", false)), "opening": bool(context.get("opening_return", false)), "cross": cross_court, "from_x": snappedf(origin.x, 0.01), "to": [snappedf(lane, 0.01), snappedf(depth, 0.01)],
		"roll": snappedf(roll, 0.01), "p_popup": snappedf(Kitchen.popup_attack_probability(context), 0.01), "p_counter": snappedf(Kitchen.counter_probability(context), 0.01),
		"p_patience": snappedf(Kitchen.low_speedup_probability(context), 0.01), "patience_roll": snappedf(float(context.get("patience_roll", 1.0)), 0.01),
		"risk": risk if Tuning.RISK_ON else "", "aim": aim, "soft_run": int(context.get("soft_run", 0)),
		"opp": context.get("opponents", []).map(func(o): return [snappedf(o.x, 0.01), snappedf(absf(o.z), 0.01)])})
	return {"style_id": style, "kind": kind, "target": Vector3(lane, Flight.FLOOR_REST_Y, direction * depth),
		"charge": charge, "shot_type": shot_type, "intent": intent, "arc": arc, "spin_mode": spin_mode,
		"risk": risk if Tuning.RISK_ON else "", "aim": aim}

## Run them: index of the opponent to move (lowest stamina; a near tie by the roll), or -1.
static func _run_target(context: Dictionary, pressure: bool, placement: float) -> int:
	if not Tuning.RUN_ON or pressure or not Tuning.STAMINA_STRATEGY_ON or not RuntimePolicy.stamina_strategy_for(int(context.get("team_id", -1))): return -1
	var opps: Array = context.get("opponents", []); var st: Array = context.get("opponents_stamina", [])
	if opps.size() != 2 or st.size() != 2: return -1
	if absf(float(st[0]) - float(st[1])) < 5.0: return 0 if fposmod(placement * 3.0, 1.0) < 0.5 else 1
	return 0 if float(st[0]) < float(st[1]) else 1

## Safe / normal / aggressive from the per-flight risk roll in the context.
static func risk_level(context: Dictionary) -> String:
	if not Tuning.RISK_ON: return "normal"
	var d: int = clampi(int(context.get("difficulty", 1)), 0, 2)
	var roll: float = float(context.get("risk_roll", 0.5))
	var aggressive: float = float(Tuning.RISK_AGGRESSIVE[d]) * float(Tuning.RISK_STYLE[Styles.valid_id(context.get("style_id", 0))])
	if roll < aggressive: return "aggressive"
	if roll > 1.0 - float(Tuning.RISK_SAFE[d]): return "safe"
	return "normal"

## Target from the opponents' court position. opps: positions, vels: velocities (same order).
## Returns {lane, depth (m past the net), aim} or {} when no read applies.
static func position_target(kind: String, opps: Array, vels: Array, lane: float, depth: float) -> Dictionary:
	var soft: bool = kind in ["DINK", "RESET", "DROP"]
	var d: Array = [absf(opps[0].z), absf(opps[1].z)]
	var toward: Array = [0.0, 0.0]   # speed toward the net
	for i in 2:
		if i < vels.size(): toward[i] = -signf(opps[i].z) * float(vels[i].z)
	var deep: int = 0 if d[0] >= d[1] else 1
	# Deep (or backing off): short into the kitchen in front of them: they must run up and hit up.
	if soft and (d[deep] > 3.5 or toward[deep] < -1.0):
		return {"lane": clampf(opps[deep].x + _side_of(opps[deep].x) * 0.6, -2.2, 2.2), "depth": 1.25, "aim": "short_on_deep"}
	# Running forward through transition: at the feet.
	for i in 2:
		if kind != "LOB" and toward[i] > 1.2 and d[i] > 2.6 and d[i] < 5.5:
			return {"lane": clampf(opps[i].x + _side_of(opps[i].x) * 0.35, -2.4, 2.4), "depth": maxf(2.2, d[i] - 0.4 - 0.3 * toward[i]), "aim": "feet_running"}
	# One up, one back: power at the back player's feet.
	if not soft and kind != "LOB" and absf(d[0] - d[1]) > 1.5:
		return {"lane": clampf(opps[deep].x + _side_of(opps[deep].x) * 0.5, -2.4, 2.4), "depth": clampf(d[deep] - 0.6, 2.3, 6.0), "aim": "back_player_feet"}
	var gap: float = absf(opps[0].x - opps[1].x)
	# Split wide: through the middle.
	if gap > 3.0 and kind in ["DINK", "RESET", "DRIVE", "SPEED_UP"]:
		return {"lane": clampf((opps[0].x + opps[1].x) * 0.5, -1.4, 1.4), "depth": depth, "aim": "middle"}
	# Both at the line, close together: a sharp angle wide, away from them.
	if kind == "DINK" and gap < 2.0 and d[0] < 3.0 and d[1] < 3.0:
		var mid: float = (opps[0].x + opps[1].x) * 0.5
		return {"lane": (-1.0 if mid > 0.0 else 1.0) * 2.3, "depth": 1.3, "aim": "angle"}
	return {}

## Lane (of five across the court) farthest from both opponents, counted from where each
## will be in 0.4 s, so a ball behind a moving player scores as open. Depth counts half.
static func open_lane(opps: Array, vels: Array, depth: float, half_width: float) -> float:
	var best: float = 0.0
	var best_d: float = -1.0
	for i in 5:
		var x: float = lerpf(-half_width, half_width, i / 4.0)
		var nearest: float = INF
		for j in opps.size():
			var px: float = opps[j].x + (0.4 * float(vels[j].x) if j < vels.size() else 0.0)
			nearest = minf(nearest, Vector2(x - px, (depth - absf(opps[j].z)) * 0.5).length())
		if nearest > best_d: best_d = nearest; best = x
	return best

## Off to the open side of a player standing at x (toward the middle when they are wide).
static func _side_of(x: float) -> float:
	return -signf(x) if absf(x) > 0.4 else 1.0

static func _nearest_opponent(context: Dictionary, origin: Vector3) -> Vector3:
	var best: Vector3 = context.get("opponent", Vector3.ZERO)
	var best_d: float = INF
	for o in context.get("opponents", []):
		var d: float = Vector2(o.x - origin.x, o.z - origin.z).length()
		if d < best_d: best_d = d; best = o
	return best

static func solve(physics: ShotPhysics, origin: Vector3, context: Dictionary, roll: float, placement: float) -> Dictionary:
	return solve_plan(physics, origin, context, plan(context, roll, placement))

static func solve_plan(physics: ShotPhysics, origin: Vector3, context: Dictionary, planned: Dictionary) -> Dictionary:
	var shot: Dictionary = planned.duplicate(true)
	var team: int = int(context.get("court_side", context.get("player_num", 1)))
	var launch: Dictionary = physics.solve_aimed_launch(origin, shot.target, shot.charge, team, int(shot.get("spin_mode", 0)), shot.intent, shot.shot_type, shot.arc)
	var box: Dictionary = Tuning.RISK.get(str(shot.get("risk", "")), Tuning.RISK.normal) if Tuning.RISK_ON else Tuning.RISK.normal
	if not valid_launch(origin, launch, team, float(box.x_max), float(box.z_max)):
		var perf_fb = Engine.get_main_loop().root.get_node_or_null("PerfMonitor") if Engine.get_main_loop() is SceneTree else null
		if perf_fb != null: perf_fb.note("ai_fallback", {"actor": int(context.get("actor_id", -1)), "kind": str(planned.get("kind", "")), "risk": str(planned.get("risk", "")),
			"origin": [snappedf(origin.x, 0.01), snappedf(origin.y, 0.01), snappedf(origin.z, 0.01)]})
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
		var perf_fail = Engine.get_main_loop().root.get_node_or_null("PerfMonitor") if Engine.get_main_loop() is SceneTree else null
		if perf_fail != null: perf_fail.note("ai_unsolved", {"actor": int(context.get("actor_id", -1)), "kind": str(planned.get("kind", "")),
			"origin": [snappedf(origin.x, 0.01), snappedf(origin.y, 0.01), snappedf(origin.z, 0.01)]})
		return {}
	if str(shot.intent) == "DROP": launch = _with_net_margin(origin, launch, team, float(box.net) if Tuning.RISK_ON else SOFT_NET_MARGIN)
	launch["tactic"] = shot.kind
	var perf = Engine.get_main_loop().root.get_node_or_null("PerfMonitor") if Engine.get_main_loop() is SceneTree else null
	if perf != null: perf.note("ai_launch", {"actor": int(context.get("actor_id", -1)), "kind": shot.kind,
		"origin": [snappedf(origin.x, 0.01), snappedf(origin.y, 0.01), snappedf(origin.z, 0.01)],
		"vel": [snappedf(launch.velocity.x, 0.01), snappedf(launch.velocity.y, 0.01), snappedf(launch.velocity.z, 0.01)]})
	shot.make_read_only()
	launch["motion_plan"] = shot
	return launch

## Mishit: the paddle face was too far off for the planned shot (see
## match_contact_authority.contact_launch). The ball pops up soft and high to
## mid-court, an attackable ball, instead of deflecting into the net.
## No RNG: placement follows the contact.
static func popup_launch(physics: ShotPhysics, origin: Vector3, team: int) -> Dictionary:
	var direction: float = -1.0 if team == 0 else 1.0
	var lane: float = clampf(origin.x * 0.4, -1.6, 1.6)
	for depth in [3.6, 3.0, 4.4]:
		var target := Vector3(lane, Flight.FLOOR_REST_Y, direction * depth)
		for arc in [0.3, 0.2, 0.42]:
			var launch: Dictionary = physics.solve_aimed_launch(origin, target, 0.06, team, 0, "AUTO", "LOB", arc)
			if valid_launch(origin, launch, team) and launch.velocity.y > 0.0:
				launch = _with_net_margin(origin, launch, team)
				launch["tactic"] = "POPUP"
				launch["motion_plan"] = {"kind": "POPUP", "charge": 0.06, "intent": "AUTO", "shot_type": "LOB", "target": target, "arc": arc}
				return launch
	return {}

## Soft shots are aimed just over the tape, and the execution error then nets
## some of them (bench: 8 of 82 resets). Add lift until the planned flight
## clears the net by SOFT_NET_MARGIN, keeping the launch only if it still lands in.
static func _with_net_margin(origin: Vector3, launch: Dictionary, team: int, margin: float = SOFT_NET_MARGIN) -> Dictionary:
	var lifted: Dictionary = launch.duplicate(true)
	for step in 8:
		var flight: Dictionary = Flight.trace(origin, lifted.velocity, lifted.omega, 3.0, 1, false)
		var crossing: Dictionary = flight.net_crossing
		if crossing.is_empty(): return launch
		var point: Vector3 = crossing.get("pos", crossing.get("position", Vector3.INF))
		if not point.is_finite(): return launch
		if point.y - Flight.net_clear_y_at(point.x) >= margin:
			return lifted if step == 0 or valid_launch(origin, lifted, team) else launch
		lifted.velocity += Vector3.UP * 0.12
	return launch

static func valid_launch(origin: Vector3, launch: Dictionary, team: int, x_max: float = 2.8, z_max: float = 6.4) -> bool:
	if launch.is_empty() or not launch.get("velocity", Vector3.INF).is_finite(): return false
	var flight: Dictionary = Flight.trace(origin, launch.velocity, launch.omega, 3.0, 1, false)
	var landing: Vector3 = flight.first_bounce
	var direction: float = -1.0 if team == 0 else 1.0
	return float(flight.first_bounce_time) > 0.0 and not flight.net_hit and not flight.net_crossing.is_empty() \
		and absf(landing.x) < x_max and landing.z * direction > 0.3 and landing.z * direction < z_max
