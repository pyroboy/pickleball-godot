extends RefCounted

# Standard gameplay rule, deliberately not a persisted opt-out setting.
# All time is simulation time, matching ball travel and movement during focus.
# Gameplay v2 numbers live in gameplay_tuning.gd (STAMINA_ON); off = the old rule.
const Tuning = preload("res://scripts/gameplay_tuning.gd")
const MAXIMUM := 100.0
const LOW_THRESHOLD := 25.0
const MIN_SPEED_FACTOR := 0.85
var value := MAXIMUM
var recovery_delay := 0.0
## Difficulty scale of the low-stamina penalty (set by the game; 1 = full).
var penalty_scale := 1.0
## Bench experiments only (RuntimePolicy.stamina_pins): -1 = normal, else the value is held here.
var pinned := -1.0

func _pin() -> void:
	if pinned >= 0.0: value = pinned

func reset_match() -> void:
	value = MAXIMUM
	recovery_delay = 0.0
	power_streak = 0
	seconds_low = 0.0
	_pin()

func speed_factor() -> float:
	if Tuning.STAMINA_ON:
		var low: float = clampf(1.0 - value / Tuning.STAMINA_PENALTY_AT, 0.0, 1.0) * penalty_scale
		return lerpf(1.0, Tuning.STAMINA_MIN_SPEED, low)
	return lerpf(MIN_SPEED_FACTOR, 1.0, clampf(value / LOW_THRESHOLD, 0.0, 1.0))

## 0 at or above the penalty line, 1 at empty (times the difficulty scale).
func tiredness() -> float:
	if not Tuning.STAMINA_ON: return 0.0
	return clampf(1.0 - value / Tuning.STAMINA_PENALTY_AT, 0.0, 1.0) * penalty_scale

func advance(delta: float, actual_speed: float, rally: bool, resting: bool) -> void:
	if delta <= 0.0: return
	if value < Tuning.STAMINA_PENALTY_AT: seconds_low += delta
	var recovery_seconds := maxf(0.0, delta - recovery_delay)
	recovery_delay = maxf(0.0, recovery_delay - delta)
	if resting:
		var rest: float = Tuning.STAMINA_REST_RECOVERY + Tuning.STAMINA_REST_DEFICIT * (MAXIMUM - value) if Tuning.STAMINA_ON else 12.0
		value = minf(MAXIMUM, value + rest * delta)
	elif rally:
		var speed := maxf(actual_speed, 0.0)
		var cost_per_meter := lerpf(Tuning.MOVE_COST_WALK, Tuning.MOVE_COST_SPRINT, clampf((speed - 2.0) / 3.8, 0.0, 1.0)) if Tuning.STAMINA_ON else lerpf(0.5, 1.5, clampf((speed - 2.0) / 3.8, 0.0, 1.0))
		var recovery := (Tuning.STAMINA_RALLY_RECOVERY if Tuning.STAMINA_ON else 7.0) * clampf(1.0 - speed / 2.0, 0.0, 1.0)
		value = clampf(value + recovery * recovery_seconds - speed * cost_per_meter * delta, 0.0, MAXIMUM)
	_pin()

func contact_cost(kind: String, outgoing_speed: float) -> float:
	if kind in ["DROP", "DINK", "RESET"]: return 1.0
	if Tuning.STAMINA_ON and Tuning.STAMINA_HARD_COST.has(kind): return float(Tuning.STAMINA_HARD_COST[kind])
	if kind in ["SMASH", "SPEED_UP"]: return 8.0 if kind == "SMASH" else 6.0
	if kind in ["DRIVE", "GROUNDSTROKE"]: return 6.0
	if kind in ["RETURN", "VOLLEY", "LOB", "SERVE"]: return 3.0
	return 6.0 if outgoing_speed >= 10.0 else 3.0

## Extra costs at each contact (Gameplay v2 player-feel pass): power shots in a row cost
## more each time; blocking or volleying a fast ball costs a reflex.
var power_streak := 0
func note_contact(power: bool, incoming_speed: float) -> void:
	if not Tuning.STAMINA_ON: return
	power_streak = power_streak + 1 if power else 0
	var extra: float = Tuning.STREAK_COST * maxf(0.0, float(power_streak - 1))
	last_cost["streak"] = extra
	var block: float = Tuning.FAST_BLOCK_COST_HARD if incoming_speed >= 16.0 else (Tuning.FAST_BLOCK_COST if incoming_speed >= 12.0 else 0.0)
	last_cost["block"] = block
	extra += block
	value = maxf(0.0, value - extra)
	_pin()

func refill(amount: float) -> void:
	value = minf(MAXIMUM, value + amount)
	_pin()

## Data: the last contact's cost split (base, streak extra, fast-block extra) and seconds
## spent below the penalty line this match.
var last_cost := {"base": 0.0, "streak": 0.0, "block": 0.0}
var seconds_low := 0.0

func spend_contact(kind: String, outgoing_speed: float) -> void:
	last_cost["base"] = contact_cost(kind, outgoing_speed)
	value = maxf(0.0, value - contact_cost(kind, outgoing_speed))
	_pin()
	recovery_delay = 0.2 if kind in ["DROP", "DINK", "RESET"] else 0.8
