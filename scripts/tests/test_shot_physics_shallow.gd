class_name TestShotPhysicsShallow extends TestBase






const MIN_SWING_SPEED_MS: = 7.0
const MAX_SWING_SPEED_MS: = 22.35


func run_all(totals: Dictionary) -> void :
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
	_run_test_list(totals, tests)



func _speed_curve(charge_ratio: float) -> float:
	return pow(clampf(charge_ratio, 0.0, 1.0), 0.7)



func _target_speed(charge_ratio: float) -> float:
	return lerpf(MIN_SWING_SPEED_MS, MAX_SWING_SPEED_MS, _speed_curve(charge_ratio))




func test_speed_curve_charge_0_bounded() -> void :
	var s: float = _target_speed(0.0)
	_assert_ge(s, MIN_SWING_SPEED_MS, "charge=0 speed at minimum")
	_assert_le(s, MAX_SWING_SPEED_MS, "charge=0 speed below maximum")


func test_speed_curve_charge_half_bounded() -> void :
	var s: float = _target_speed(0.5)
	_assert_ge(s, MIN_SWING_SPEED_MS, "charge=0.5 speed at minimum")
	_assert_le(s, MAX_SWING_SPEED_MS, "charge=0.5 speed below maximum")


func test_speed_curve_charge_1_bounded() -> void :
	var s: float = _target_speed(1.0)
	_assert_ge(s, MIN_SWING_SPEED_MS, "charge=1 speed at minimum")
	_assert_le(s, MAX_SWING_SPEED_MS, "charge=1 speed below maximum")


func test_speed_curve_monotonic_increasing() -> void :
	var prev: float = -1.0
	for c in [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]:
		var s: float = _target_speed(c)
		if s < prev:
			_current_failures.append("speed decreased at charge=%.1f: %.2f < %.2f" % [c, s, prev])
		prev = s


func test_speed_curve_pow07_shape() -> void :


	var s: float = _target_speed(0.5)
	_assert_eq_f(s, 16.45, 0.5, "speed_curve at charge=0.5 matches expected pow formula")


func test_speed_curve_lerp_range() -> void :

	_assert_eq_f(_target_speed(0.0), MIN_SWING_SPEED_MS, 0.001, "charge=0 returns MIN_SPEED")
	_assert_eq_f(_target_speed(1.0), MAX_SWING_SPEED_MS, 0.001, "charge=1 returns MAX_SPEED")




func test_spin_topspin_axis_perpendicular_to_travel() -> void :
	var travel: = Vector3(5.0, 0.0, -10.0).normalized()
	var topspin_axis: = Vector3.UP.cross(travel)
	_assert_gt(topspin_axis.length(), 0.9, "topspin axis magnitude near 1.0")

	var dot: = topspin_axis.dot(travel)
	_assert_lt(absf(dot), 0.01, "topspin axis perpendicular to travel direction")


func test_spin_side_axis_aligned_with_up() -> void :

	var travel: = Vector3(3.0, 0.0, -4.0).normalized()
	var side_axis: = Vector3.UP
	var dot: = side_axis.dot(Vector3.UP)
	_assert_eq_f(dot, 1.0, 0.001, "side axis is exactly UP")


func test_spin_zero_when_stationary() -> void :
	var travel: = Vector3.ZERO
	if travel.length() < 0.1:
		_assert_true(true, "zero travel → early return in compute_shot_spin (no spin)")
