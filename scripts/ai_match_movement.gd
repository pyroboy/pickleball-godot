extends RefCounted

# All values and timers are in simulation seconds, just like the ball and Blue.
# Hard can match Blue's top speed; difficulty never buys superhuman movement.
const SPEEDS: Array[float] = [4.35, 5.0, 5.8]
const ACCELERATIONS: Array[float] = [12.0, 14.0, 16.0]
const BRAKES: Array[float] = [16.0, 18.0, 20.0]
const REPLAN_SECONDS: Array[float] = [0.15, 0.12, 0.10]

static func speed(difficulty: int) -> float:
	return SPEEDS[clampi(difficulty, 0, 2)]

static func velocity(current: Vector3, input: Vector3, offset: Vector3, difficulty: int, delta: float) -> Vector3:
	var level: int = clampi(difficulty, 0, 2)
	current.y = 0.0
	offset.y = 0.0
	var desired: Vector3 = Vector3.ZERO
	if input.length_squared() > 0.0001:
		# Arrive on our feet rather than overshoot and flip at full speed.
		var arrival_speed: float = sqrt(2.0 * BRAKES[level] * maxf(offset.length() - 0.055, 0.0))
		desired = offset.normalized() * minf(speed(level), arrival_speed)
	var acceleration: float = ACCELERATIONS[level]
	if desired.length_squared() < current.length_squared() or current.dot(desired) < 0.0:
		acceleration = BRAKES[level]
	return current.move_toward(desired, acceleration * maxf(delta, 0.0)).limit_length(speed(level))

static func travel_distance(current: Vector3, direction: Vector3, seconds: float, difficulty: int) -> float:
	# Optimistic reachable bound that still pays for acceleration and reversal.
	var level: int = clampi(difficulty, 0, 2)
	var initial: float = clampf(current.dot(direction.normalized()), -speed(level), speed(level))
	var duration: float = maxf(seconds, 0.0)
	var acceleration: float = ACCELERATIONS[level]
	var ramp: float = minf(duration, (speed(level) - initial) / acceleration)
	return maxf(0.0, initial * ramp + 0.5 * acceleration * ramp * ramp + speed(level) * (duration - ramp))
