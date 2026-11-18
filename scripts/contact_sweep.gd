extends RefCounted


static func closest_fraction(ball_from: Vector3, ball_to: Vector3, paddle_from: Vector3, paddle_to: Vector3, radius: float) -> float:
	var start: Vector3 = ball_from - paddle_from
	var motion: Vector3 = (ball_to - paddle_to) - start
	if motion.length_squared() < 1e-08: return -1.0
	var fraction: float = clampf( - start.dot(motion) / motion.length_squared(), 0.0, 1.0)
	return fraction if (start + motion * fraction).length() <= radius else -1.0
