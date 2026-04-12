class_name PhysicsUtils
extends RefCounted
## Pure math utilities for pickleball physics — damping, smoothing, decay.
## All functions are static/deterministic: no scene dependencies, fully unit-testable.

const BALL_MASS := PickleballConstants.BALL_MASS
const BALL_RADIUS := PickleballConstants.BALL_RADIUS
const GRAVITY_SCALE := PickleballConstants.GRAVITY_SCALE
const MAX_SPEED := PickleballConstants.MAX_SPEED

const PLAYER_SPEED := PickleballConstants.PLAYER_SPEED
const PADDLE_FORCE := PickleballConstants.PADDLE_FORCE

const COURT_LENGTH := PickleballConstants.COURT_LENGTH
const COURT_WIDTH := PickleballConstants.COURT_WIDTH
const NET_HEIGHT := PickleballConstants.NET_HEIGHT
const LINE_WIDTH := PickleballConstants.LINE_WIDTH
const NON_VOLLEY_ZONE := PickleballConstants.NON_VOLLEY_ZONE


static func _damp(current: float, target: float, halflife: float, dt: float) -> float:
	return lerpf(current, target, 1.0 - exp(-0.693 * dt / maxf(halflife, 0.001)))


static func _damp_v3(current: Vector3, target: Vector3, halflife: float, dt: float) -> Vector3:
	var a: float = 1.0 - exp(-0.693 * dt / maxf(halflife, 0.001))
	return current.lerp(target, a)
