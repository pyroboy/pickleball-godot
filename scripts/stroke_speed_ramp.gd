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
## Speed points (speed_<part>_points, up to MAX_POINTS of (x, speed, 0), x = time fraction inside
## the part): with any, the speed is a smooth monotone curve through the start, the points and
## the end (never below 0), scaled so the part still ends exactly on its key in its duration.
## The graph shows and edits the real (scaled) speeds.
##
## Easing keys (the Pose Studio easing curve): a point with z = 1 is (x, progress, 1), a place the
## part's progress curve passes through (x = time fraction, progress 0..1 inside the part). With
## any, the part's progress is a monotone cubic through (0, 0), the keys and (1, 1), leaving the
## start with slope `start` and arriving with slope `end` (the keys' ease handles). Without keys
## that is exactly the Hermite ramp above. z = 0 points are the older speed points.
enum { LEAD, STRIKE, FINISH }
const FIELDS := [["speed_lead_start", "speed_lead_end"], ["speed_strike_start", "speed_strike_end"], ["speed_finish_start", "speed_finish_end"]]
const NAMES := ["Ready → Wind-up", "Strike", "Follow-through"]
const POINTS := ["speed_lead_points", "speed_strike_points", "speed_finish_points"]
const MAX_SPEED := 3.0
const MAX_POINTS := 4
const STEPS := 64             # integration samples for a part with speed points

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
	if has_points(def, LEAD): return _integrated(def, LEAD, x)
	var e := ends(def, LEAD)
	if has_ease_keys(def, LEAD): return ease_value(ease_keys(def, LEAD), e.x, e.y, x)
	return hermite(x, e.x, e.y)

## The part has easing keys (z = 1 points).
static func has_ease_keys(def, part: int) -> bool:
	if not custom(def, part): return false
	for p in points(def, part): if p.z >= 0.5: return true
	return false

## [[x, progress], ...] from (0, 0) to (1, 1): the part's easing keys, sorted, strictly rising.
static func ease_keys(def, part: int) -> Array:
	var mid: Array = []
	for p in points(def, part): if p.z >= 0.5: mid.append([clampf(p.x, 0.03, 0.97), clampf(p.y, 0.01, 0.99)])
	mid.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = [[0.0, 0.0]]
	for q in mid.slice(0, MAX_POINTS):
		var last: Array = out[out.size() - 1]
		if q[0] - last[0] < 0.01: continue
		out.append([q[0], clampf(q[1], last[1] + 0.005, 0.995)])
	out.append([1.0, 1.0])
	return out

## Progress at x of the monotone cubic through keys k, with slope s0 at the start and s1 at the
## end. Inner slopes follow their neighbours; every slope is held to three times the steeper of
## its two sides at most, so the curve never runs backwards.
static func ease_value(k: Array, s0: float, s1: float, x: float) -> float:
	var t: float = clampf(x, 0.0, 1.0)
	var n := k.size()
	var i := 0
	while i < n - 2 and t > k[i + 1][0]: i += 1
	var slope := func(j: int) -> float:
		var after: float = (k[j + 1][1] - k[j][1]) / maxf(k[j + 1][0] - k[j][0], 0.0001) if j < n - 1 else -1.0
		var before: float = (k[j][1] - k[j - 1][1]) / maxf(k[j][0] - k[j - 1][0], 0.0001) if j > 0 else -1.0
		if j == 0: return clampf(s0, 0.0, 3.0 * after)
		if j == n - 1: return clampf(s1, 0.0, 3.0 * before)
		if before <= 0.0 or after <= 0.0: return 0.0
		var ha: float = k[j + 1][0] - k[j][0]; var hb: float = k[j][0] - k[j - 1][0]
		return minf(3.0 * (ha + hb) / ((2.0 * ha + hb) / before + (ha + 2.0 * hb) / after), 3.0 * minf(before, after))
	var h: float = maxf(k[i + 1][0] - k[i][0], 0.0001)
	var u: float = clampf((t - k[i][0]) / h, 0.0, 1.0)
	var m0: float = slope.call(i) * h; var m1: float = slope.call(i + 1) * h
	var y0: float = k[i][1]; var y1: float = k[i + 1][1]
	return clampf((2*u*u*u - 3*u*u + 1) * y0 + (u*u*u - 2*u*u + u) * m0 + (-2*u*u*u + 3*u*u) * y1 + (u*u*u - u*u) * m1, 0.0, 1.0)

static func points(def, part: int) -> PackedVector3Array:
	var v = def.get(POINTS[part]) if def != null else null
	return v if v is PackedVector3Array else PackedVector3Array()

## The part has the older speed points (z = 0) and no easing keys.
static func has_points(def, part: int) -> bool:
	return custom(def, part) and points(def, part).size() > 0 and not has_ease_keys(def, part)

## [[x, speed], ...] from start to end (x sorted, points kept inside 0.02..0.98).
static func keys(def, part: int) -> Array:
	var e := ends(def, part)
	var out: Array = [[0.0, e.x]]
	var mid: Array = []
	for p in points(def, part).slice(0, MAX_POINTS): mid.append([clampf(p.x, 0.02, 0.98), clampf(p.y, 0.0, MAX_SPEED)])
	mid.sort_custom(func(a, b): return a[0] < b[0])
	out.append_array(mid); out.append([1.0, e.y])
	return out

## Monotone cubic (Fritsch-Carlson) through the keys: never overshoots, so never below 0.
static func spline(k: Array, x: float) -> float:
	var t: float = clampf(x, 0.0, 1.0)
	var n := k.size()
	var i := 0
	while i < n - 2 and t > k[i + 1][0]: i += 1
	var d := func(j: int) -> float: return (k[j + 1][1] - k[j][1]) / maxf(k[j + 1][0] - k[j][0], 0.0001)
	var tan := func(j: int) -> float:
		if j == 0: return d.call(0)
		if j == n - 1: return d.call(n - 2)
		var a: float = d.call(j - 1); var b: float = d.call(j)
		if a * b <= 0.0: return 0.0
		return 3.0 * (k[j + 1][0] - k[j - 1][0]) / ((2.0 * k[j + 1][0] - k[j][0] - k[j - 1][0]) / a + (k[j + 1][0] + k[j][0] - 2.0 * k[j - 1][0]) / b)
	var h: float = maxf(k[i + 1][0] - k[i][0], 0.0001)
	var s: float = clampf((t - k[i][0]) / h, 0.0, 1.0)
	var m0: float = tan.call(i) * h; var m1: float = tan.call(i + 1) * h
	var y0: float = k[i][1]; var y1: float = k[i + 1][1]
	return maxf(0.0, (2*s*s*s - 3*s*s + 1) * y0 + (s*s*s - 2*s*s + s) * m0 + (-2*s*s*s + 3*s*s) * y1 + (s*s*s - s*s) * m1)

## Progress of a part with speed points: the running integral of its speed curve, scaled to 1.
static func _integrated(def, part: int, x: float) -> float:
	var k := keys(def, part)
	var t: float = clampf(x, 0.0, 1.0)
	var total := 0.0; var upto := 0.0
	var prev: float = spline(k, 0.0)
	for i in STEPS:
		var b: float = float(i + 1) / STEPS
		var cur: float = spline(k, b)
		var area: float = (prev + cur) * 0.5 / STEPS
		if b <= t: upto += area
		elif float(i) / STEPS < t: upto += (prev + lerpf(prev, cur, (t - float(i) / STEPS) * STEPS)) * 0.5 * (t - float(i) / STEPS)
		total += area; prev = cur
	if total <= 0.000001: return t
	return clampf(upto / total, 0.0, 1.0)

## Mean of the raw speed curve (what the raw keys are divided by): real speed = raw / mean.
static func mean(def, part: int) -> float:
	if not has_points(def, part): return 1.0
	return mean_of(keys(def, part))

static func mean_of(k: Array) -> float:
	var total := 0.0; var prev: float = spline(k, 0.0)
	for i in STEPS:
		var cur: float = spline(k, float(i + 1) / STEPS); total += (prev + cur) * 0.5 / STEPS; prev = cur
	return maxf(total, 0.000001)

## Normalized (0..1) progress of a part at time fraction x, authored ease when not custom.
## `linear_strike`: the human strike's authored timing is linear.
static func normalized(def, part: int, x: float, linear_strike := false) -> float:
	if custom(def, part):
		if has_points(def, part): return _integrated(def, part, x)
		var e := ends(def, part)
		if has_ease_keys(def, part): return ease_value(ease_keys(def, part), e.x, e.y, x)
		return hermite(x, e.x, e.y)
	if part == LEAD: return smoothstep(0.0, 1.0, x)
	if part == STRIKE and linear_strike: return clampf(x, 0.0, 1.0)
	return Tween.interpolate_value(0.0, 1.0, clampf(x, 0.0, 1.0), 1.0, transition(def), easing(def))

static func transition(def) -> Tween.TransitionType:
	return Tween.TRANS_QUAD if def.ft_ease_curve == 1 else Tween.TRANS_SINE if def.ft_ease_curve == 2 else Tween.TRANS_EXPO

static func easing(def) -> Tween.EaseType:
	return Tween.EASE_IN_OUT if def.ft_ease_curve == 2 else Tween.EASE_OUT

## Rescale the keys [[x, v], ...] of a part (start, points, end) so that their speed curve has
## mean 1 (the part covers its distance in its time): every entry whose `free` flag is true is
## multiplied by one common factor, the others stay. Returns the new keys, or [] when no factor
## does it (nothing free, or the fixed entries alone already cover more than the distance, or it
## would need a speed above MAX_SPEED).
static func solve_mean(k: Array, free: Array) -> Array:
	var any_free := false
	for i in k.size(): if free[i] and k[i][1] > 0.0001: any_free = true
	var apply := func(mu: float) -> Array:
		var out: Array = []
		for i in k.size(): out.append([k[i][0], minf(k[i][1] * mu, MAX_SPEED) if free[i] else k[i][1]])
		return out
	if not any_free:
		return k.duplicate(true) if absf(mean_of(k) - 1.0) < 0.004 else []
	var lo := 0.0; var hi := 1.0
	if mean_of(apply.call(0.0)) > 1.0: return []
	while mean_of(apply.call(hi)) < 1.0:
		hi *= 2.0
		if hi > 4096.0: return []   # capped at MAX_SPEED everywhere and still short
	for i in 28:
		var mid := (lo + hi) * 0.5
		if mean_of(apply.call(mid)) < 1.0: lo = mid
		else: hi = mid
	return apply.call((lo + hi) * 0.5)

## Relative speed (d progress / d time, 1 = average) of a part at x, for the graph.
static func speed(def, part: int, x: float) -> float:
	if has_points(def, part): return spline(keys(def, part), x) / mean(def, part)
	var h := 0.002
	var a: float = clampf(x - h, 0.0, 1.0); var b: float = clampf(x + h, 0.0, 1.0)
	return (normalized(def, part, b) - normalized(def, part, a)) / maxf(b - a, 0.000001)

## Hermite end speeds that best stand in for the authored ease (a graph's first drag starts here).
static func authored_ends(def, part: int) -> Vector2:
	var e := Vector2(clampf(speed(def, part, 0.0), 0.0, MAX_SPEED), clampf(speed(def, part, 1.0), 0.0, MAX_SPEED))
	# An ease that starts / ends at rest reads as a hair above zero (numeric slope): call it rest.
	return Vector2(0.0 if e.x < 0.03 else e.x, 0.0 if e.y < 0.03 else e.y)
