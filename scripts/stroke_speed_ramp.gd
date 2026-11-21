extends RefCounted
## Speed ramp of a stroke's three motion parts (Pose Studio speed graph). Each part keeps its
## duration and its end keys; only how fast the paddle moves inside the part changes.
##   LEAD    Ready -> Wind-up (held Hit, visual only)
##   STRIKE  Wind-up -> Contact (gameplay: Contact still lands at the end of the strike)
##   FINISH  Contact -> Finish (the ball has gone)
## Per part, speed_<part>_start / _end: relative speed at the part's two ends (1 = the part's
## average speed, 0 = at rest). Both -1 (the default) = the authored ease, unchanged: lead-in
## smoothstep, strike / finish the ft_ease_curve tween (the human strike is linear).
## Custom = cubic Hermite timing curve; ends in 0..3 keep it monotone (never runs backwards).
enum { LEAD, STRIKE, FINISH }
const FIELDS := [["speed_lead_start", "speed_lead_end"], ["speed_strike_start", "speed_strike_end"], ["speed_finish_start", "speed_finish_end"]]
const NAMES := ["Ready → Wind-up", "Strike", "Follow-through"]
const MAX_SPEED := 3.0

static func custom(def, part: int) -> bool:
	return def != null and float(def.get(FIELDS[part][0])) >= 0.0 and float(def.get(FIELDS[part][1])) >= 0.0

static func ends(def, part: int) -> Vector2:
	return Vector2(clampf(float(def.get(FIELDS[part][0])), 0.0, MAX_SPEED), clampf(float(def.get(FIELDS[part][1])), 0.0, MAX_SPEED))

static func hermite(x: float, s0: float, s1: float) -> float:
	var t: float = clampf(x, 0.0, 1.0)
	return (t*t*t - 2.0*t*t + t) * s0 + (-2.0*t*t*t + 3.0*t*t) + (t*t*t - t*t) * s1

## Lead-in blend progress (0..1) at fraction x of the Ready -> Wind-up time.
static func lead(def, x: float) -> float:
	if not custom(def, LEAD): return smoothstep(0.0, 1.0, x)
	var e := ends(def, LEAD)
	return hermite(x, e.x, e.y)

## Normalized (0..1) progress of a part at time fraction x, authored ease when not custom.
## `linear_strike`: the human strike's authored timing is linear.
static func normalized(def, part: int, x: float, linear_strike := false) -> float:
	if custom(def, part):
		var e := ends(def, part)
		return hermite(x, e.x, e.y)
	if part == LEAD: return smoothstep(0.0, 1.0, x)
	if part == STRIKE and linear_strike: return clampf(x, 0.0, 1.0)
	return Tween.interpolate_value(0.0, 1.0, clampf(x, 0.0, 1.0), 1.0, transition(def), easing(def))

static func transition(def) -> Tween.TransitionType:
	return Tween.TRANS_QUAD if def.ft_ease_curve == 1 else Tween.TRANS_SINE if def.ft_ease_curve == 2 else Tween.TRANS_EXPO

static func easing(def) -> Tween.EaseType:
	return Tween.EASE_IN_OUT if def.ft_ease_curve == 2 else Tween.EASE_OUT

## Relative speed (d progress / d time, 1 = average) of a part at x, for the graph.
static func speed(def, part: int, x: float) -> float:
	var h := 0.002
	var a: float = clampf(x - h, 0.0, 1.0); var b: float = clampf(x + h, 0.0, 1.0)
	return (normalized(def, part, b) - normalized(def, part, a)) / maxf(b - a, 0.000001)

## Hermite end speeds that best stand in for the authored ease (a graph's first drag starts here).
static func authored_ends(def, part: int) -> Vector2:
	return Vector2(clampf(speed(def, part, 0.0), 0.0, MAX_SPEED), clampf(speed(def, part, 1.0), 0.0, MAX_SPEED))
