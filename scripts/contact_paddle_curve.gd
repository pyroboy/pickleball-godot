extends RefCounted
## A bounded, symmetric curvature adjustment around the real Contact key.
## The correction and its first derivative are zero at Wind-up, Contact and
## Finish. Its second derivative also vanishes at both ends. No retiming,
## additional keyframes, orientation changes, or endpoint movement is involved.
const DEFAULT := 0.5
const MAX_BEND_METERS := 1.2

static func position(pose: PostureDefinition) -> Vector3:
	return Vector3(pose.paddle_forehand_mul, pose.paddle_y_offset, pose.paddle_forward_mul)

static func bend(windup: Vector3, contact: Vector3, finish: Vector3) -> Vector3:
	var tangent: Vector3 = finish - windup
	var normal: Vector3 = windup - 2.0 * contact + finish
	# Normal-only displacement changes the bend without pulling along the
	# contact tangent. A genuinely straight path stays straight.
	if tangent.length_squared() > 0.00000001:
		normal -= tangent * normal.dot(tangent) / tangent.length_squared()
	return normal.limit_length(MAX_BEND_METERS)

static func offset(bend_vector: Vector3, progress: float, amount: float) -> Vector3:
	var t: float = clampf(progress, 0.0, 1.0)
	if t <= 0.0 or t >= 1.0 or t == 0.5 or amount == DEFAULT:
		return Vector3.ZERO
	var x: float = 2.0 * t - 1.0
	var envelope: float = x * x * pow(1.0 - x * x, 3.0)
	return bend_vector * envelope * (2.0 * clampf(amount, 0.0, 1.0) - 1.0)

static func apply(pose: PostureDefinition, bend_vector: Vector3, progress: float, amount: float) -> void:
	if amount == DEFAULT: return
	var delta: Vector3 = offset(bend_vector, progress, amount)
	pose.paddle_forehand_mul += delta.x
	pose.paddle_y_offset += delta.y
	pose.paddle_forward_mul += delta.z
