extends RefCounted


const D = preload("res://scripts/paddle_dimensions.gd")
const Surface = preload("res://scripts/paddle_clearance.gd")
const MAX_COARSE_STEPS: = 30
const REFINEMENT_STEPS: = 8
const MAX_SWEEP_QUERIES: = 40

static func touches(paddle: Transform3D, ball: Vector3, radius: float) -> bool:
	return Surface.distance_to_head_shape(paddle.affine_inverse() * ball) <= radius + Surface.contact_surface_tolerance()

static func interpolate_head_transform(from: Transform3D, to: Transform3D, fraction: float) -> Transform3D:
	var basis: = Basis(from.basis.orthonormalized().get_rotation_quaternion().slerp(to.basis.orthonormalized().get_rotation_quaternion(), fraction))
	var head: Vector3 = (from * D.HEAD_OFFSET).lerp(to * D.HEAD_OFFSET, fraction)
	return Transform3D(basis, head - basis * D.HEAD_OFFSET)

static func _gap(ball_from: Vector3, ball_to: Vector3, head_from: Vector3, head_to: Vector3, start_q: Quaternion, end_q: Quaternion, fraction: float, limit: float) -> float:
	var basis: = Basis(start_q.slerp(end_q, fraction))
	var local: Vector3 = basis.transposed() * (ball_from.lerp(ball_to, fraction) - head_from.lerp(head_to, fraction)) + D.HEAD_OFFSET
	return Surface.distance_to_head_shape(local) - limit

static func _refine(ball_from: Vector3, ball_to: Vector3, head_from: Vector3, head_to: Vector3, start_q: Quaternion, end_q: Quaternion, lower: float, upper: float, limit: float) -> float:


	for step in REFINEMENT_STEPS:
		var middle: float = (lower + upper) * 0.5
		if _gap(ball_from, ball_to, head_from, head_to, start_q, end_q, middle, limit) <= 0.0: upper = middle
		else: lower = middle
	return upper

static func first_sweep_fraction(ball_from: Vector3, ball_to: Vector3, paddle_from: Transform3D, paddle_to: Transform3D, radius: float, max_fraction: float = 1.0) -> float:
	return _sweep_fraction(ball_from, ball_to, paddle_from, paddle_to, radius, max_fraction, Surface.contact_surface_tolerance())

static func physical_sweep_fraction(ball_from: Vector3, ball_to: Vector3, paddle_from: Transform3D, paddle_to: Transform3D, radius: float, max_fraction: float = 1.0) -> float:
	# Actual contact uses the physical sphere, without the preview seating gap.
	return _sweep_fraction(ball_from, ball_to, paddle_from, paddle_to, radius, max_fraction, 0.0)

static func _sweep_fraction(ball_from: Vector3, ball_to: Vector3, paddle_from: Transform3D, paddle_to: Transform3D, radius: float, max_fraction: float, gap: float) -> float:
	var end: float = clampf(max_fraction, 0.0, 1.0)
	var head_from: Vector3 = paddle_from * D.HEAD_OFFSET
	var head_to: Vector3 = paddle_to * D.HEAD_OFFSET
	var relative: Vector3 = ball_from - head_from
	var relative_motion: Vector3 = (ball_to - head_to) - relative
	var motion_squared: float = relative_motion.length_squared()
	var closest: float = clampf( - relative.dot(relative_motion) / motion_squared, 0.0, end) if motion_squared > 1e-18 else 0.0
	var head_radius: float = Vector2(D.HEAD_LENGTH * 0.5, D.HEAD_HALF_THICKNESS).length()
	var limit: float = radius + gap
	if (relative + relative_motion * closest).length() > head_radius + limit: return -1.0
	var start_q: Quaternion = paddle_from.basis.orthonormalized().get_rotation_quaternion()
	var end_q: Quaternion = paddle_to.basis.orthonormalized().get_rotation_quaternion()
	if _gap(ball_from, ball_to, head_from, head_to, start_q, end_q, 0.0, limit) <= 0.0: return 0.0
	if end <= 0.0: return -1.0
	var angle: float = 2.0 * acos(clampf(absf(start_q.dot(end_q)), 0.0, 1.0))


	var travel: float = (relative_motion.length() + angle * head_radius) * end
	var count: int = clampi(ceili(travel / maxf(radius * 0.5, 0.0001)), 4, MAX_COARSE_STEPS)
	var previous: = 0.0
	for index in range(1, count + 1):
		var fraction: float = end * index / count
		if _gap(ball_from, ball_to, head_from, head_to, start_q, end_q, fraction, limit) <= 0.0:
			return _refine(ball_from, ball_to, head_from, head_to, start_q, end_q, previous, fraction, limit)
		previous = fraction


	if _gap(ball_from, ball_to, head_from, head_to, start_q, end_q, closest, limit) <= 0.0:
		var lower: float = floorf(closest / end * count) * end / count
		return _refine(ball_from, ball_to, head_from, head_to, start_q, end_q, lower, closest, limit)
	return -1.0
