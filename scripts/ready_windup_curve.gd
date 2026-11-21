extends RefCounted
## Ready -> Wind-up paddle path shape (visual preparation only; the held-Hit clock and the
## planned shot are unchanged). The base move is the existing blend (straight hand line plus
## the around-body nudge). This adds a bow sideways to that line, read from the stroke's
## Wind-up pose (its own fields), zero at both ends so Ready and Wind-up never move.
##   ready_curve_bow      0 = straight (as before) .. 1 = half-circle (peak = half the line length)
##   ready_curve_round    0 = pointed bulge, 0.5 = sine, 1 = full / round-shouldered
##   ready_curve_dir_deg  which way the bow points around the line: 0 up, 180 down, +-90 the sides
##   ready_curve_peak     where along the move the bulge is biggest (0.5 = middle)
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
	var bow: float = clampf(windup.ready_curve_bow, 0.0, 1.0)
	var u: float = clampf(progress, 0.0, 1.0)
	if bow <= 0.0 or u <= 0.0 or u >= 1.0: return Vector3.ZERO
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
