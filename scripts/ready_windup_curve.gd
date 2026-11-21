extends RefCounted
## Ready -> Wind-up paddle path shape (visual preparation only; the held-Hit clock and the
## planned shot are unchanged). The base move is the existing blend (straight hand line plus
## the around-body nudge). This adds a bow sideways to that line, read from the stroke's
## Wind-up pose (its own fields), zero at both ends so Ready and Wind-up never move.
##   ready_curve_auto     smooth the lead-in into the swing (0 = straight line, 1 = full loop)
##   ready_curve_bow      0 = straight (as before) .. 1 = half-circle (peak = half the line length)
##   ready_curve_round    0 = pointed bulge, 0.5 = sine, 1 = full / round-shouldered
##   ready_curve_dir_deg  which way the bow points around the line: 0 up, 180 down, +-90 the sides
##   ready_curve_peak     where along the move the bulge is biggest (0.5 = middle)
## Plus path keys (ready_path_times / _offsets, dragged on the AutoPose arc's grey lead-in): the
## paddle passes through each key's offset; zero offset and slope at Ready and Wind-up.
const Path = preload("res://scripts/stroke_swing_path.gd")
const Grip = preload("res://scripts/grip_transition.gd")

## The whole Ready -> Wind-up sample: the existing blend, then the bow.
static func sample(ready: PostureDefinition, windup: PostureDefinition, progress: float) -> PostureDefinition:
	var pose: PostureDefinition = Grip.sample(ready, windup, progress) if Grip.supports_both_joined(ready, windup) else Path.blend_pose(ready, windup, progress)
	apply(pose, ready, windup, progress)
	return pose

static func apply(pose: PostureDefinition, ready: PostureDefinition, windup: PostureDefinition, progress: float) -> void:
	var delta: Vector3 = offset(ready, windup, progress)
	pose.paddle_forehand_mul += delta.x
	pose.paddle_y_offset += delta.y
	pose.paddle_forward_mul += delta.z

## Paddle head offset in the pose's (forehand, up, forward) field space.
static func offset(ready: PostureDefinition, windup: PostureDefinition, progress: float) -> Vector3:
	var u: float = clampf(progress, 0.0, 1.0)
	if u <= 0.0 or u >= 1.0: return Vector3.ZERO
	return smooth_offset(ready, windup, u) + bow_offset(ready, windup, u) + key_offset(windup, u)

## ready_curve_auto (0 = straight line, 1 = full): a cubic Bezier Ready -> Wind-up that leaves
## Ready rising and arrives at Wind-up coming down and toward Contact, so the lead-in loops into
## the swing instead of meeting it at a corner. Relative to the straight line (0 = no change).
const SMOOTH_LIFT := 0.6       # how much the lead-in rises leaving Ready (per unit along the line)
const SMOOTH_FORWARD := 1.4    # how much the arrival at Wind-up already heads toward Contact
const SMOOTH_START := 0.35     # Bezier handle lengths, fraction of the line length
const SMOOTH_END := 0.45
static func smooth_offset(ready: PostureDefinition, windup: PostureDefinition, u: float) -> Vector3:
	var amount: float = clampf(windup.ready_curve_auto, 0.0, 1.0)
	if amount <= 0.0: return Vector3.ZERO
	var a := Vector3(ready.paddle_forehand_mul, ready.paddle_y_offset, ready.paddle_forward_mul)
	var b := Vector3(windup.paddle_forehand_mul, windup.paddle_y_offset, windup.paddle_forward_mul)
	var chord: Vector3 = b - a
	var length: float = chord.length()
	if length < 0.001: return Vector3.ZERO
	# Swing leaving Wind-up: toward Contact (Wind-up = Contact + charge_paddle_offset).
	var swing: Vector3 = -windup.charge_paddle_offset
	swing = swing.normalized() if swing.length_squared() > 0.000001 else chord.normalized()
	var down: Vector3 = Vector3.DOWN - swing * swing.dot(Vector3.DOWN)
	down = down.normalized() if down.length_squared() > 0.0025 else (chord - swing * swing.dot(chord)).normalized()
	var leave: Vector3 = (chord.normalized() + Vector3.UP * SMOOTH_LIFT).normalized()
	var arrive: Vector3 = (down + swing * SMOOTH_FORWARD).normalized()
	var p1: Vector3 = a + (chord / 3.0).lerp(leave * length * SMOOTH_START, amount)
	var p2: Vector3 = b - (chord / 3.0).lerp(arrive * length * SMOOTH_END, amount)
	var v: float = 1.0 - u
	var curve: Vector3 = a * (v * v * v) + p1 * (3.0 * v * v * u) + p2 * (3.0 * v * u * u) + b * (u * u * u)
	return curve - a.lerp(b, u)

## Cubic Hermite through (0, 0), the keys, (1, 0); slope zero at Ready and Wind-up.
static func key_offset(windup: PostureDefinition, u: float) -> Vector3:
	var n: int = mini(windup.ready_path_times.size(), windup.ready_path_offsets.size())
	if n == 0: return Vector3.ZERO
	var ts: Array = [0.0, 1.0]
	var os: Array = [Vector3.ZERO, Vector3.ZERO]
	for i in n:
		var k: float = windup.ready_path_times[i]
		if k <= 0.0 or k >= 1.0: continue
		var j := ts.size() - 1
		for m in ts.size(): if ts[m] > k: j = m; break
		ts.insert(j, k); os.insert(j, windup.ready_path_offsets[i])
	var i := 0
	while i < ts.size() - 2 and u > ts[i + 1]: i += 1
	var h: float = ts[i + 1] - ts[i]
	if h <= 0.0: return Vector3.ZERO
	var s: float = clampf((u - ts[i]) / h, 0.0, 1.0)
	var slope := func(m: int) -> Vector3:
		if m == 0 or m == ts.size() - 1: return Vector3.ZERO
		return (os[m + 1] - os[m - 1]) / (ts[m + 1] - ts[m - 1])
	var m0: Vector3 = slope.call(i); var m1: Vector3 = slope.call(i + 1)
	return (2*s*s*s - 3*s*s + 1) * os[i] + (s*s*s - 2*s*s + s) * h * m0 + (-2*s*s*s + 3*s*s) * os[i + 1] + (s*s*s - s*s) * h * m1

static func bow_offset(ready: PostureDefinition, windup: PostureDefinition, u: float) -> Vector3:
	var bow: float = clampf(windup.ready_curve_bow, 0.0, 1.0)
	if bow <= 0.0: return Vector3.ZERO
	var a := Vector3(ready.paddle_forehand_mul, ready.paddle_y_offset, ready.paddle_forward_mul)
	var b := Vector3(windup.paddle_forehand_mul, windup.paddle_y_offset, windup.paddle_forward_mul)
	var chord: Vector3 = b - a
	var length: float = chord.length()
	if length < 0.001: return Vector3.ZERO
	return direction(chord, windup.ready_curve_dir_deg) * (bow * 0.5 * length * profile(u, windup.ready_curve_round, windup.ready_curve_peak))

## Unit bow direction around the line: 0 deg = up (or forward when the line is vertical).
static func direction(chord: Vector3, deg: float) -> Vector3:
	var d: Vector3 = chord.normalized()
	var n0: Vector3 = Vector3.UP - d * d.dot(Vector3.UP)
	if n0.length_squared() < 0.0025: n0 = Vector3.BACK - d * d.dot(Vector3.BACK)
	n0 = n0.normalized()
	var n1: Vector3 = d.cross(n0)
	var r: float = deg_to_rad(deg)
	return n0 * cos(r) + n1 * sin(r)

## 0 at both ends, 1 at the peak.
static func profile(u: float, round_amount: float, peak: float) -> float:
	var k: float = log(0.5) / log(clampf(peak, 0.05, 0.95))
	var s: float = sin(PI * pow(u, k))
	return pow(maxf(s, 0.0), pow(2.0, (0.5 - clampf(round_amount, 0.0, 1.0)) * 1.6))
