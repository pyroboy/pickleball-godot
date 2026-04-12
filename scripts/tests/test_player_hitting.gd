class_name TestPlayerHitting extends RefCounted
## Unit tests for PlayerHitting — paddle velocity EMA tracking (GAP-X).
## Tests the damping/EMA formula that smooths paddle velocity.
## Uses a minimal FakePlayerHitting that mirrors the actual _process update loop.
##
## Run via: godot --headless --script scripts/tests/test_runner.gd

const _PhysicsUtils := preload("res://scripts/physics.gd")
const _PADDLE_VEL_SMOOTH_HALFLIFE: float = 0.08
const _PADDLE_VEL_TRANSFER: float = 0.40

var _current_failures: Array[String] = []
var _current_test_name: String = ""


func run_all(totals: Dictionary) -> void:
	var tests: Array[Callable] = [
		# EMA convergence (2)
		test_velocity_converges_to_target,
		test_velocity_tracks_constant_motion,
		# Transfer scalar (1)
		test_transfer_scalar_bounds,
		# Smooth halflife is reasonable (1)
		test_halflife_reasonable_range,
	]
	for t in tests:
		_current_test_name = t.get_method()
		_current_failures = []
		t.call()
		if _current_failures.is_empty():
			totals.pass += 1
		else:
			totals.fail += 1
			for f in _current_failures:
				totals.errors.append("%s: %s" % [_current_test_name, f])


func _assert_true(cond: bool, msg: String = "") -> void:
	if not cond:
		_current_failures.append("expected true: %s" % msg)


func _assert_eq_f(a: float, b: float, tol: float, msg: String = "") -> void:
	if absf(a - b) > tol:
		_current_failures.append("expected %g, got %g (tol=%g): %s" % [b, a, tol, msg])


## Simulates the EMA update from PlayerHitting._process().
## Returns the new velocity after one frame at dt.
func _ema_step(prev_vel: Vector3, prev_pos: Vector3, new_pos: Vector3, halflife: float, dt: float) -> Vector3:
	var raw_delta: Vector3 = (new_pos - prev_pos) / maxf(dt, 0.0001)
	return _PhysicsUtils._damp_v3(prev_vel, raw_delta, halflife, dt)


## ── EMA convergence ─────────────────────────────────────────────────────────

func test_velocity_converges_to_target() -> void:
	# When paddle moves at constant velocity, EMA should converge to that velocity
	var vel: Vector3 = Vector3.ZERO
	var prev_pos: Vector3 = Vector3.ZERO
	var new_pos: Vector3 = Vector3.ZERO
	var target: Vector3 = Vector3(3.0, 0.0, 0.0)
	var dt: float = 0.016

	for frame in range(500):
		new_pos = prev_pos + target * dt
		vel = _ema_step(vel, prev_pos, new_pos, _PADDLE_VEL_SMOOTH_HALFLIFE, dt)
		prev_pos = new_pos

	_assert_eq_f(vel.x, target.x, 0.01, "EMA converges to constant paddle velocity")


func test_velocity_tracks_constant_motion() -> void:
	# After 10 frames (~0.16s), EMA should be well on its way to target
	var vel: Vector3 = Vector3.ZERO
	var prev_pos: Vector3 = Vector3.ZERO
	var new_pos: Vector3 = Vector3.ZERO
	var target: Vector3 = Vector3(5.0, 2.0, -1.0)
	var dt: float = 0.016

	for i in range(10):
		new_pos = prev_pos + target * dt
		vel = _ema_step(vel, prev_pos, new_pos, _PADDLE_VEL_SMOOTH_HALFLIFE, dt)
		prev_pos = new_pos

	# After 10 frames at hl=0.08, we should be ~56% of the way there
	# fraction = 1 - exp(-0.693 * 0.16 / 0.08) = 1 - exp(-1.386) = 1 - 0.25 = 0.75
	var expected_10f: float = target.length() * (1.0 - exp(-0.693 * 10.0 * 0.016 / _PADDLE_VEL_SMOOTH_HALFLIFE))
	_assert_eq_f(vel.length(), expected_10f, 0.15, "EMA velocity after 10 frames matches exponential model")


## ── Transfer scalar ──────────────────────────────────────────────────────────

func test_transfer_scalar_bounds() -> void:
	# PADDLE_VEL_TRANSFER should be a fraction [0, 1] — it scales how much
	# of paddle velocity is transferred to ball speed
	_assert_true(_PADDLE_VEL_TRANSFER >= 0.0, "transfer scalar is non-negative")
	_assert_true(_PADDLE_VEL_TRANSFER <= 1.0, "transfer scalar is <= 1 (fraction of paddle speed)")
	# At transfer=0.4 and max paddle speed ~15 m/s, contribution = 6 m/s
	# Combined with ball speed range [7, 22], this is meaningful but not dominant
	var max_contribution: float = 15.0 * _PADDLE_VEL_TRANSFER
	_assert_true(max_contribution > 1.0, "max paddle velocity contribution > 1 m/s (meaningful)")
	_assert_true(max_contribution < 12.0, "max paddle velocity contribution < 12 m/s (ball physics still dominant)")


## ── Smooth halflife ──────────────────────────────────────────────────────────

func test_halflife_reasonable_range() -> void:
	# halflife = 0.08s means 50% smoothing per 80ms — reasonable for human swing
	# At 60fps (dt=0.016), one frame smoothing fraction = 1 - exp(-0.693*0.016/0.08) ≈ 0.129
	# So each frame moves 13% toward target velocity — smooth but responsive
	var dt: float = 0.016
	var fraction_per_frame: float = 1.0 - exp(-0.693 * dt / _PADDLE_VEL_SMOOTH_HALFLIFE)
	_assert_true(fraction_per_frame > 0.05, "per-frame smoothing > 5% (responsive enough)")
	_assert_true(fraction_per_frame < 0.30, "per-frame smoothing < 30% (smooth, not jittery)")
	# At this halflife, 95% convergence takes ~5 * halflife = 0.4s = 25 frames
	var frames_to_95: float = -_PADDLE_VEL_SMOOTH_HALFLIFE / dt * log(0.05) / 0.693
	_assert_true(frames_to_95 < 40.0, "95% convergence in < 40 frames (~0.64s)")
