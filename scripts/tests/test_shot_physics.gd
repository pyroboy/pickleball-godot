class_name TestShotPhysics extends RefCounted
## Unit tests for ShotPhysics — compute_shot_velocity, compute_shot_spin.
## Uses FakePlayer fakes for player position mocks.
##
## Run via: godot --headless --script scripts/tests/test_runner.gd

const _ShotPhysics := preload("res://scripts/shot_physics.gd")
const _FakeBallNode := preload("res://scripts/tests/fakes/fake_ball_node.gd")
const _FakePlayer := preload("res://scripts/tests/fakes/fake_player.gd")

var _current_failures: Array[String] = []
var _current_test_name: String = ""


func run_all(totals: Dictionary) -> void:
	var tests: Array[Callable] = [
		# Speed bounds (3)
		test_speed_at_charge_0_bounded,
		test_speed_at_charge_1_bounded,
		test_speed_at_charge_half_bounded,
		# Monotonicity (3)
		test_speed_monotonic_increasing_charge,
		test_speed_zero_charge_less_than_full_charge,
		# Speed curve formula (1)
		test_speed_curve_pow07_shape,
		# Shot type modifiers (4)
		test_shot_type_smash_faster_than_default,
		test_shot_type_drop_slower_than_default,
		test_shot_type_lob_higher_arc_than_default,
		test_shot_type_volley_slight_speed_reduction,
		# Spin (3)
		test_spin_smash_topspin,
		test_spin_drop_backspin,
		test_spin_dink_light_backspin,
		# AI targeting (2)
		test_ai_aims_away_from_opponent_left,
		test_ai_aims_away_from_opponent_right,
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


func _shooter() -> _ShotPhysics:
	var s := _ShotPhysics.new()
	s.setup(_FakeBallNode.new(), _FakePlayer.new(0, Vector3.ZERO), _FakePlayer.new(1, Vector3.ZERO))
	return s


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


func _assert_eq_f(a: float, b: float, tol: float, msg: String = "") -> void:
	if absf(a - b) > tol:
		_current_failures.append("expected %g, got %g (tol=%g): %s" % [b, a, tol, msg])


## ── Speed bounds ─────────────────────────────────────────────────────────────

func test_speed_at_charge_0_bounded() -> void:
	var sp := _shooter()
	var vel: Vector3 = sp.compute_shot_velocity(Vector3.ZERO, 0.0, 0, "", 0)
	var speed: float = vel.length()
	_assert_ge(speed, _ShotPhysics.MIN_SWING_SPEED_MS, "charge=0 speed above minimum")
	_assert_le(speed, _ShotPhysics.MAX_SWING_SPEED_MS, "charge=0 speed below maximum")


func test_speed_at_charge_1_bounded() -> void:
	var sp := _shooter()
	var vel: Vector3 = sp.compute_shot_velocity(Vector3.ZERO, 1.0, 0, "", 0)
	var speed: float = vel.length()
	_assert_ge(speed, _ShotPhysics.MIN_SWING_SPEED_MS, "charge=1 speed above minimum")
	_assert_le(speed, _ShotPhysics.MAX_SWING_SPEED_MS, "charge=1 speed below maximum")


func test_speed_at_charge_half_bounded() -> void:
	var sp := _shooter()
	var vel: Vector3 = sp.compute_shot_velocity(Vector3.ZERO, 0.5, 0, "", 0)
	var speed: float = vel.length()
	_assert_ge(speed, _ShotPhysics.MIN_SWING_SPEED_MS, "charge=0.5 speed above minimum")
	_assert_le(speed, _ShotPhysics.MAX_SWING_SPEED_MS, "charge=0.5 speed below maximum")


## ── Monotonicity ─────────────────────────────────────────────────────────────

func test_speed_monotonic_increasing_charge() -> void:
	var sp := _shooter()
	var speeds: Array = []
	for c in [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]:
		var vel: Vector3 = sp.compute_shot_velocity(Vector3(0, 0.5, 2.0), c, 0, "", 0)
		speeds.append(vel.length())
	for i in range(1, speeds.size()):
		if speeds[i] < speeds[i - 1]:
			_current_failures.append("speed decreased: charge=%.1f→%.1f: %.2f→%.2f m/s" % [
				(i - 1) * 0.1, i * 0.1, speeds[i - 1], speeds[i]])


func test_speed_zero_charge_less_than_full_charge() -> void:
	var sp := _shooter()
	var v0: Vector3 = sp.compute_shot_velocity(Vector3(0, 0.5, 2.0), 0.0, 0, "", 0)
	var v1: Vector3 = sp.compute_shot_velocity(Vector3(0, 0.5, 2.0), 1.0, 0, "", 0)
	_assert_gt(v1.length(), v0.length(), "full charge faster than zero charge")


## ── Speed curve formula ───────────────────────────────────────────────────────

func test_speed_curve_pow07_shape() -> void:
	# speed_curve = pow(charge, 0.7) → at charge=0.5, curve ≈ 0.5^0.7 ≈ 0.616
	# target_speed = lerp(7.0, 22.35, 0.616) ≈ 7.0 + 0.616*15.35 ≈ 16.45
	var sp := _shooter()
	var vel: Vector3 = sp.compute_shot_velocity(Vector3(0, 0.5, 2.0), 0.5, 0, "", 0)
	var expected_mid: float = 7.0 + pow(0.5, 0.7) * (22.35 - 7.0)  # ≈ 16.5
	_assert_eq_f(vel.length(), expected_mid, 0.5, "speed_curve at charge=0.5 matches pow formula")


## ── Shot type modifiers ──────────────────────────────────────────────────────

func test_shot_type_smash_faster_than_default() -> void:
	var sp := _shooter()
	var ball_pos := Vector3(0, 1.5, 2.0)
	var def_vel: Vector3 = sp.compute_shot_velocity(ball_pos, 0.7, 0, "", 0)
	var smash_vel: Vector3 = sp.compute_shot_velocity(ball_pos, 0.7, 0, "SMASH", 0)
	_assert_gt(smash_vel.length(), def_vel.length(), "SMASH faster than default at same charge")


func test_shot_type_drop_slower_than_default() -> void:
	var sp := _shooter()
	var ball_pos := Vector3(0, 0.3, 2.0)
	var def_vel: Vector3 = sp.compute_shot_velocity(ball_pos, 0.5, 0, "", 0)
	var drop_vel: Vector3 = sp.compute_shot_velocity(ball_pos, 0.5, 0, "DROP", 0)
	_assert_lt(drop_vel.length(), def_vel.length(), "DROP slower than default at same charge")
	_assert_lt(drop_vel.length(), 7.5, "DROP capped at speed_floor 7.5")


func test_shot_type_lob_higher_arc_than_default() -> void:
	var sp := _shooter()
	var ball_pos := Vector3(0, 0.5, 3.0)
	var def_vel: Vector3 = sp.compute_shot_velocity(ball_pos, 0.5, 0, "", 0)
	var lob_vel: Vector3 = sp.compute_shot_velocity(ball_pos, 0.5, 0, "LOB", 0)
	_assert_gt(lob_vel.y, def_vel.y, "LOB has higher upward arc than default")


func test_shot_type_volley_slight_speed_reduction() -> void:
	var sp := _shooter()
	var ball_pos := Vector3(0, 1.0, 2.0)
	var def_vel: Vector3 = sp.compute_shot_velocity(ball_pos, 0.5, 0, "", 0)
	var volley_vel: Vector3 = sp.compute_shot_velocity(ball_pos, 0.5, 0, "VOLLEY", 0)
	_assert_gt(def_vel.length(), volley_vel.length(), "VOLLEY slightly slower than default")
	_assert_lt(volley_vel.length(), def_vel.length(), "VOLLEY faster than default")


## ── Spin ─────────────────────────────────────────────────────────────────────

func test_spin_smash_topspin() -> void:
	var sp := _shooter()
	var vel := Vector3(5.0, 0.0, -10.0)
	var omega: Vector3 = sp.compute_shot_spin("SMASH", vel, 0.8, 0)
	_assert_gt(omega.length(), 0.0, "SMASH spin magnitude > 0")
	var travel_dir := Vector3(vel.x, 0.0, vel.z).normalized()
	var topspin_axis := Vector3.UP.cross(travel_dir)
	_assert_gt(omega.dot(topspin_axis), 0.0, "SMASH spin is topspin (positive on topspin axis)")


func test_spin_drop_backspin() -> void:
	var sp := _shooter()
	var vel := Vector3(3.0, -2.0, -5.0)
	var omega: Vector3 = sp.compute_shot_spin("DROP", vel, 0.5, 0)
	_assert_lt(omega.dot(Vector3.UP), 0.0, "DROP spin is backspin (negative on UP axis)")


func test_spin_dink_light_backspin() -> void:
	var sp := _shooter()
	var vel := Vector3(1.0, 0.0, -3.0)
	var omega: Vector3 = sp.compute_shot_spin("DINK", vel, 0.4, 0)
	var up_comp: float = omega.dot(Vector3.UP)
	_assert_lt(up_comp, 0.0, "DINK spin is backspin (negative on UP)")


## ── AI targeting ─────────────────────────────────────────────────────────────

func test_ai_aims_away_from_opponent_left() -> void:
	# When opponent (player_left) is at x > 0.5, AI (player_num=1) aims left (x < 0)
	var sp := _shooter()
	var opp := _FakePlayer.new(0, Vector3(1.5, 1.0, 4.0))   # opponent on left side
	var me := _FakePlayer.new(1, Vector3(0.0, 1.0, -3.0))   # AI on right side
	var sp2 := _ShotPhysics.new()
	sp2.setup(_FakeBallNode.new(), opp, me)
	var ball_pos := Vector3(0, 0.5, -2.0)
	var vel: Vector3 = sp2.compute_shot_velocity(ball_pos, 0.6, 1, "", 1)
	_assert_lt(vel.x, 0.0, "AI aims LEFT (x<0) when opponent is on left side (x>0.5)")


func test_ai_aims_away_from_opponent_right() -> void:
	# When opponent is at x < -0.5, AI aims right (x > 0)
	var sp := _shooter()
	var opp := _FakePlayer.new(0, Vector3(-1.5, 1.0, 4.0))  # opponent on right side
	var me := _FakePlayer.new(1, Vector3(0.0, 1.0, -3.0))  # AI on right side
	var sp2 := _ShotPhysics.new()
	sp2.setup(_FakeBallNode.new(), opp, me)
	var ball_pos := Vector3(0, 0.5, -2.0)
	var vel: Vector3 = sp2.compute_shot_velocity(ball_pos, 0.6, 1, "", 1)
	_assert_gt(vel.x, 0.0, "AI aims RIGHT (x>0) when opponent is on right side (x<-0.5)")


func _assert_lt(a: float, b: float, msg: String = "") -> void:
	if not (a < b):
		_current_failures.append("expected %g < %g: %s" % [a, b, msg])
