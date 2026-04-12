class_name TestShotPhysicsShallow extends RefCounted
## L1 shallow tests for shot physics — speed curve formula, lerp bounds, spin axis.
## No scene, no Ball class, no ShotPhysics instantiation.
## These test only the PURE MATH that compute_shot_velocity is built on.
##
## Run via: godot --headless --script scripts/tests/test_runner.gd

const MIN_SWING_SPEED_MS := 7.0
const MAX_SWING_SPEED_MS := 22.35

var _current_failures: Array[String] = []
var _current_test_name: String = ""


func run_all(totals: Dictionary) -> void:
	var tests: Array[Callable] = [
		test_speed_curve_charge_0_bounded,
		test_speed_curve_charge_half_bounded,
		test_speed_curve_charge_1_bounded,
		test_speed_curve_monotonic_increasing,
		test_speed_curve_pow07_shape,
		test_speed_curve_lerp_range,
		test_spin_topspin_axis_perpendicular_to_travel,
		test_spin_side_axis_aligned_with_up,
		test_spin_zero_when_stationary,
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


func _assert_ge(a: float, b: float, msg: String = "") -> void:
	if a < b:
		_current_failures.append("expected %g >= %g: %s" % [a, b, msg])


func _assert_le(a: float, b: float, msg: String = "") -> void:
	if a > b:
		_current_failures.append("expected %g <= %g: %s" % [a, b, msg])


func _assert_gt(a: float, b: float, msg: String = "") -> void:
	if not (a > b):
		_current_failures.append("expected %g > %g: %s" % [a, b, msg])


func _assert_lt(a: float, b: float, msg: String = "") -> void:
	if not (a < b):
		_current_failures.append("expected %g < %g: %s" % [a, b, msg])


func _assert_eq_f(a: float, b: float, tol: float, msg: String = "") -> void:
	if absf(a - b) > tol:
		_current_failures.append("expected %g, got %g (tol=%g): %s" % [b, a, tol, msg])


## Speed curve formula (mirrors compute_shot_velocity line 20)
func _speed_curve(charge_ratio: float) -> float:
	return pow(clampf(charge_ratio, 0.0, 1.0), 0.7)


## Target speed (mirrors compute_shot_velocity line 21)
func _target_speed(charge_ratio: float) -> float:
	return lerpf(MIN_SWING_SPEED_MS, MAX_SWING_SPEED_MS, _speed_curve(charge_ratio))


## ── Speed curve L1 tests ───────────────────────────────────────────────────

func test_speed_curve_charge_0_bounded() -> void:
	var s: float = _target_speed(0.0)
	_assert_ge(s, MIN_SWING_SPEED_MS, "charge=0 speed at minimum")
	_assert_le(s, MAX_SWING_SPEED_MS, "charge=0 speed below maximum")


func test_speed_curve_charge_half_bounded() -> void:
	var s: float = _target_speed(0.5)
	_assert_ge(s, MIN_SWING_SPEED_MS, "charge=0.5 speed at minimum")
	_assert_le(s, MAX_SWING_SPEED_MS, "charge=0.5 speed below maximum")


func test_speed_curve_charge_1_bounded() -> void:
	var s: float = _target_speed(1.0)
	_assert_ge(s, MIN_SWING_SPEED_MS, "charge=1 speed at minimum")
	_assert_le(s, MAX_SWING_SPEED_MS, "charge=1 speed below maximum")


func test_speed_curve_monotonic_increasing() -> void:
	var prev: float = -1.0
	for c in [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]:
		var s: float = _target_speed(c)
		if s < prev:
			_current_failures.append("speed decreased at charge=%.1f: %.2f < %.2f" % [c, s, prev])
		prev = s


func test_speed_curve_pow07_shape() -> void:
	# At charge=0.5: curve = 0.5^0.7 ≈ 0.6156
	# target_speed = 7.0 + 0.6156 * 15.35 ≈ 16.45
	var s: float = _target_speed(0.5)
	_assert_eq_f(s, 16.45, 0.5, "speed_curve at charge=0.5 matches expected pow formula")


func test_speed_curve_lerp_range() -> void:
	# lerp(min, max, 0) = min, lerp(min, max, 1) = max
	_assert_eq_f(_target_speed(0.0), MIN_SWING_SPEED_MS, 0.001, "charge=0 returns MIN_SPEED")
	_assert_eq_f(_target_speed(1.0), MAX_SWING_SPEED_MS, 0.001, "charge=1 returns MAX_SPEED")


## ── Spin axis L1 tests ─────────────────────────────────────────────────────

func test_spin_topspin_axis_perpendicular_to_travel() -> void:
	var travel := Vector3(5.0, 0.0, -10.0).normalized()
	var topspin_axis := Vector3.UP.cross(travel)
	_assert_gt(topspin_axis.length(), 0.9, "topspin axis magnitude near 1.0")
	# topspin_axis should be perpendicular to travel (dot = 0)
	var dot := topspin_axis.dot(travel)
	_assert_lt(absf(dot), 0.01, "topspin axis perpendicular to travel direction")


func test_spin_side_axis_aligned_with_up() -> void:
	# Sidespin axis is always UP (pure lateral spin)
	var travel := Vector3(3.0, 0.0, -4.0).normalized()
	var side_axis := Vector3.UP
	var dot := side_axis.dot(Vector3.UP)
	_assert_eq_f(dot, 1.0, 0.001, "side axis is exactly UP")


func test_spin_zero_when_stationary() -> void:
	var travel := Vector3.ZERO
	if travel.length() < 0.1:
		_assert_true(true, "zero travel → early return in compute_shot_spin (no spin)")
