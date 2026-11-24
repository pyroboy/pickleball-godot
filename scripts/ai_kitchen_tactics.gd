extends RefCounted
const Tuning = preload("res://scripts/gameplay_tuning.gd")
const Styles = preload("res://scripts/ai_playing_styles.gd")
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")


## The incoming ball's flight grade (flight_grade.gd, read as it left the paddle): a LOW ball
## has to be lifted, so attacking it is rare; a HIGH one invites the attack.
static func grade_factor(context: Dictionary) -> float:
	if not Tuning.GRADE_READ_ON: return 1.0
	match str(context.get("incoming_grade", "")):
		"LOW": return Tuning.GRADE_LOW_ATTACK
		"HIGH": return Tuning.GRADE_HIGH_ATTACK
	return 1.0

static func attack_probability(context: Dictionary) -> float:
	if not context.get("near_kitchen", false) or not context.get("legal_volley", false): return 0.0
	if not context.get("reachable", false) or not context.get("balanced", false): return 0.0
	if not context.get("reaction_ready", false): return 0.0
	var excess: float = float(context.get("ball_height", 0.0)) - float(context.get("net_height", 1.0))
	if excess < 0.12: return 0.0
	var height_factor: float = clampf((excess - 0.05) / 0.65, 0.15, 1.0)
	var difficulty: int = clampi(int(context.get("difficulty", 1)), 0, 2)
	return minf(0.98, [0.32, 0.58, 0.82][difficulty] * height_factor * grade_factor(context))

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
	if Tuning.ATTACK_CHARGE_ON:
		return float((Tuning.SMASH_CHARGE if attack_kind(context) == "SMASH" else Tuning.SPEEDUP_CHARGE)[difficulty])
	return [0.62, 0.76, 0.88][difficulty] if attack_kind(context) == "SMASH" else [0.46, 0.58, 0.7][difficulty]

static func response_kind(context: Dictionary, roll: float) -> String:
	if float(context.get("incoming_speed", 0.0)) >= 9.5 and float(context.get("ball_height", 0.0)) < float(context.get("net_height", 1.0)) + 0.55:
		return "RESET"
	return attack_kind(context) if choose(context, roll) == "ATTACK" else "SOFT"


## Patience runs out (GAME_MECHANICS_PLAN change 4): chance of a low speed-up from a
## ball near net height, rising with the soft shots already in the rally.
static func low_speedup_probability(context: Dictionary) -> float:
	if not Tuning.PATIENCE_ON: return 0.0
	if float(context.get("net_distance", 5.0)) > 3.4 or bool(context.get("opening_return", false)): return 0.0
	if not context.get("reachable", false) or not context.get("reaction_ready", false): return 0.0
	if float(context.get("contact_distance", 0.7)) > 1.05: return 0.0
	var excess: float = float(context.get("ball_height", 0.0)) - float(context.get("net_height", 1.0))
	var d: int = clampi(int(context.get("difficulty", 1)), 0, 2)
	if excess < float(Tuning.PATIENCE_MIN_EXCESS[d]): return 0.0
	var run: float = float(context.get("soft_run", 0)) - float(Tuning.PATIENCE_START[d])
	if run <= 0.0: return 0.0
	var style_w: float = float(Styles.PROFILES[Styles.valid_id(context.get("style_id", 0))].weights.get("SPEED_UP", 1.0))
	var p: float = float(Tuning.PATIENCE_BASE[d]) * clampf(run / float(Tuning.PATIENCE_RAMP[d]), 0.0, 1.0) * style_w
	if excess > 0.0: p *= 1.5
	# Tired: conserve (fewer risky low speed-ups); fresh: no extra (a low speed-up is a gamble).
	return clampf(p * minf(1.0, stamina_aggression(context)) * grade_factor(context), 0.0, Tuning.PATIENCE_MAX)

## Firefight reply to a fast ball at the kitchen: counter if it is at or above the net.
static func counter_probability(context: Dictionary) -> float:
	if not Tuning.COUNTER_ON: return 0.0
	if float(context.get("net_distance", 5.0)) > 3.4 or float(context.get("incoming_speed", 0.0)) < 9.0: return 0.0
	if not context.get("legal_volley", false) or not context.get("reachable", false): return 0.0
	if float(context.get("ball_height", 0.0)) < float(context.get("net_height", 1.0)): return 0.0
	var habit: float = Tuning.HABIT_COUNTER_STEP * clampf(float(context.get("opp_power_streak", 0)) - 1.0, 0.0, 3.0)
	var fresh: float = lerpf(Tuning.COUNTER_STAMINA_MIN, 1.0, clampf(float(context.get("stamina", 100.0)) / 100.0, 0.0, 1.0))
	return clampf((float(Tuning.COUNTER_CHANCE[clampi(int(context.get("difficulty", 1)), 0, 2)]) + habit) * fresh * minf(1.0, stamina_aggression(context)), 0.0, 0.95)

## Pop-up attack (GAME_MECHANICS_PLAN step 3): a ball well over the tape, in reach,
## is attacked even on the move. Hard finishes nearly every real pop-up.
static func popup_attack_probability(context: Dictionary) -> float:
	if not Tuning.POPUP_ATTACK_ON: return 0.0
	var off_bounce: bool = Tuning.POPUP_OFF_BOUNCE and bool(context.get("bounced", false))
	if float(context.get("net_distance", 5.0)) > 3.4 or not (context.get("legal_volley", false) or off_bounce): return 0.0
	if not context.get("reachable", false) or not context.get("reaction_ready", false): return 0.0
	if float(context.get("contact_distance", 0.7)) > Tuning.POPUP_REACH: return 0.0
	var excess: float = float(context.get("ball_height", 0.0)) - float(context.get("net_height", 1.0))
	var min_excess: float = float(Tuning.POPUP_MIN_EXCESS[clampi(int(context.get("difficulty", 1)), 0, 2)])
	if excess < min_excess: return 0.0
	var h: float = clampf((excess - min_excess) / maxf(0.01, Tuning.POPUP_FULL - min_excess), 0.0, 1.0)
	return clampf(float(Tuning.POPUP_ATTACK_PROB[clampi(int(context.get("difficulty", 1)), 0, 2)]) * lerpf(0.6, 1.0, h) * stamina_aggression(context) * grade_factor(context), 0.0, 0.98)


## Stamina strategy: >1 when fresh (spend on attacks), <1 when tired (conserve).
static func stamina_aggression(context: Dictionary) -> float:
	if not Tuning.STAMINA_STRATEGY_ON or not RuntimePolicy.stamina_strategy_for(int(context.get("team_id", -1))): return 1.0
	var st: float = float(context.get("stamina", 100.0))
	if st >= Tuning.STRATEGY_EVEN:
		return lerpf(1.0, Tuning.STRATEGY_FRESH, clampf((st - Tuning.STRATEGY_EVEN) / (100.0 - Tuning.STRATEGY_EVEN), 0.0, 1.0))
	return maxf(lerpf(Tuning.STRATEGY_TIRED, 1.0, clampf(st / Tuning.STRATEGY_EVEN, 0.0, 1.0)), float(Tuning.ATTACK_STAMINA_FLOOR[clampi(int(context.get("difficulty", 1)), 0, 2)]))
