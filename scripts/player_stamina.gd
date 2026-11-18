extends RefCounted

# Standard gameplay rule, deliberately not a persisted opt-out setting.
# All time is simulation time, matching ball travel and movement during focus.
const MAXIMUM := 100.0
const LOW_THRESHOLD := 25.0
const MIN_SPEED_FACTOR := 0.85
var value := MAXIMUM
var recovery_delay := 0.0

func reset_match() -> void:
	value = MAXIMUM
	recovery_delay = 0.0

func speed_factor() -> float:
	return lerpf(MIN_SPEED_FACTOR, 1.0, clampf(value / LOW_THRESHOLD, 0.0, 1.0))

func advance(delta: float, actual_speed: float, rally: bool, resting: bool) -> void:
	if delta <= 0.0: return
	var recovery_seconds := maxf(0.0, delta - recovery_delay)
	recovery_delay = maxf(0.0, recovery_delay - delta)
	if resting:
		value = minf(MAXIMUM, value + 12.0 * delta)
	elif rally:
		var speed := maxf(actual_speed, 0.0)
		var cost_per_meter := lerpf(0.5, 1.5, clampf((speed - 2.0) / 3.8, 0.0, 1.0))
		var recovery := 7.0 * clampf(1.0 - speed / 2.0, 0.0, 1.0)
		value = clampf(value + recovery * recovery_seconds - speed * cost_per_meter * delta, 0.0, MAXIMUM)

func contact_cost(kind: String, outgoing_speed: float) -> float:
	if kind in ["DROP", "DINK", "RESET"]: return 1.0
	if kind in ["SMASH", "SPEED_UP"]: return 8.0 if kind == "SMASH" else 6.0
	if kind in ["DRIVE", "GROUNDSTROKE"]: return 6.0
	if kind in ["RETURN", "VOLLEY", "LOB", "SERVE"]: return 3.0
	return 6.0 if outgoing_speed >= 10.0 else 3.0

func spend_contact(kind: String, outgoing_speed: float) -> void:
	value = maxf(0.0, value - contact_cost(kind, outgoing_speed))
	recovery_delay = 0.2 if kind in ["DROP", "DINK", "RESET"] else 0.8
