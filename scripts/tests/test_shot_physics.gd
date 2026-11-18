class_name TestShotPhysics extends TestBase





const _ShotPhysics: = preload("res://scripts/shot_physics.gd")
const _Ball: = preload("res://scripts/ball.gd")
const _FakeBallNode: = preload("res://scripts/tests/fakes/fake_ball_node.gd")
const _FakePlayer: = preload("res://scripts/tests/fakes/fake_player.gd")


var _fixture_nodes: Array[Node] = []

func run_all(totals: Dictionary) -> void :
	var tests: Array[Callable] = [

		test_speed_at_charge_0_bounded, 
		test_speed_at_charge_1_bounded, 
		test_speed_at_charge_half_bounded, 

		test_speed_zero_charge_less_than_full_charge, 

		test_shot_type_smash_faster_than_default, 
		test_shot_type_drop_slower_than_default, 
		test_shot_type_lob_higher_arc_than_default, 


		test_spin_smash_topspin, 
		test_spin_drop_backspin, 
		test_spin_dink_light_backspin, 

		test_ai_aims_away_from_opponent_left, 
		test_ai_aims_away_from_opponent_right, 
	]
	_run_test_list(totals, tests)
	for node in _fixture_nodes:
		if is_instance_valid(node): node.free()
	_fixture_nodes.clear()


func _shooter() -> _ShotPhysics:
	var s: = _ShotPhysics.new()
	var ball: = _FakeBallNode.new()
	var left: = _FakePlayer.new(0, Vector3.ZERO)
	var right: = _FakePlayer.new(1, Vector3.ZERO)
	_fixture_nodes.append_array([ball, left, right])
	s.setup(ball, left, right)
	return s




func test_speed_at_charge_0_bounded() -> void :
	var sp: = _shooter()
	var vel: Vector3 = sp.compute_shot_velocity(Vector3.ZERO, 0.0, 0, "", 0)
	var speed: float = vel.length()
	_assert_ge(speed, _ShotPhysics.MIN_SWING_SPEED_MS, "charge=0 speed above minimum")
	_assert_le(speed, _ShotPhysics.MAX_SWING_SPEED_MS, "charge=0 speed below maximum")


func test_speed_at_charge_1_bounded() -> void :
	var sp: = _shooter()
	var vel: Vector3 = sp.compute_shot_velocity(Vector3.ZERO, 1.0, 0, "", 0)
	var speed: float = vel.length()
	_assert_ge(speed, _ShotPhysics.MIN_SWING_SPEED_MS, "charge=1 speed above minimum")
	_assert_le(speed, _ShotPhysics.MAX_SWING_SPEED_MS, "charge=1 speed below maximum")


func test_speed_at_charge_half_bounded() -> void :
	var sp: = _shooter()
	var vel: Vector3 = sp.compute_shot_velocity(Vector3.ZERO, 0.5, 0, "", 0)
	var speed: float = vel.length()
	_assert_ge(speed, _ShotPhysics.MIN_SWING_SPEED_MS, "charge=0.5 speed above minimum")
	_assert_le(speed, _ShotPhysics.MAX_SWING_SPEED_MS, "charge=0.5 speed below maximum")




func test_speed_monotonic_increasing_charge() -> void :
	var sp: = _shooter()
	var speeds: Array = []
	for c in [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]:
		var vel: Vector3 = sp.compute_shot_velocity(Vector3(0, 0.5, 2.0), c, 0, "", 0)
		speeds.append(vel.length())
	for i in range(1, speeds.size()):
		if speeds[i] < speeds[i - 1]:
			_current_failures.append("speed decreased: charge=%.1f→%.1f: %.2f→%.2f m/s" % [
				(i - 1) * 0.1, i * 0.1, speeds[i - 1], speeds[i]])


func test_speed_zero_charge_less_than_full_charge() -> void :
	var sp: = _shooter()
	var v0: Vector3 = sp.compute_shot_velocity(Vector3(0, 0.5, 2.0), 0.0, 0, "", 0)
	var v1: Vector3 = sp.compute_shot_velocity(Vector3(0, 0.5, 2.0), 1.0, 0, "", 0)
	_assert_gt(v1.length(), v0.length(), "full charge faster than zero charge")




func test_speed_curve_pow07_shape() -> void :


	var sp: = _shooter()
	var vel: Vector3 = sp.compute_shot_velocity(Vector3(0, 0.5, 2.0), 0.5, 0, "", 0)
	var expected_mid: float = 7.0 + pow(0.5, 0.7) * (22.35 - 7.0)
	_assert_eq_f(vel.length(), expected_mid, 0.5, "speed_curve at charge=0.5 matches pow formula")




func test_shot_type_smash_faster_than_default() -> void :
	var sp: = _shooter()
	var ball_pos: = Vector3(0, 1.5, 2.0)
	var def_vel: Vector3 = sp.compute_shot_velocity(ball_pos, 0.7, 0, "", 0)
	var smash_vel: Vector3 = sp.compute_shot_velocity(ball_pos, 0.7, 0, "SMASH", 0)
	_assert_gt(smash_vel.length(), def_vel.length(), "SMASH faster than default at same charge")


func test_shot_type_drop_slower_than_default() -> void :
	var sp: = _shooter()
	var ball_pos: = Vector3(0, 0.3, 2.0)
	var def_vel: Vector3 = sp.compute_shot_velocity(ball_pos, 0.5, 0, "", 0)
	var drop_vel: Vector3 = sp.compute_shot_velocity(ball_pos, 0.5, 0, "DROP", 0)
	_assert_lt(drop_vel.length(), def_vel.length(), "DROP slower than default at same charge")
	_assert_le(drop_vel.length(), 7.5, "DROP capped at speed_cap 7.5")


func test_shot_type_lob_higher_arc_than_default() -> void :
	var sp: = _shooter()


	var ball_pos: = Vector3(0, 0.5, -1.0)
	var def_vel: Vector3 = sp.compute_shot_velocity(ball_pos, 0.5, 0, "", 0)
	var lob_vel: Vector3 = sp.compute_shot_velocity(ball_pos, 0.5, 0, "LOB", 0)


	var grav: float = _Ball.get_effective_gravity()
	var def_apex: float = ball_pos.y + (def_vel.y * def_vel.y) / (2.0 * grav)
	var lob_apex: float = ball_pos.y + (lob_vel.y * lob_vel.y) / (2.0 * grav)
	_assert_gt(lob_apex, def_apex, "LOB has higher apex than default")




func test_spin_smash_topspin() -> void :
	var sp: = _shooter()
	var vel: = Vector3(5.0, 0.0, -10.0)
	var omega: Vector3 = sp.compute_shot_spin("SMASH", vel, 0.8, 0)
	_assert_gt(omega.length(), 0.0, "SMASH spin magnitude > 0")
	var travel_dir: = Vector3(vel.x, 0.0, vel.z).normalized()
	var topspin_axis: = Vector3.UP.cross(travel_dir)
	_assert_gt(omega.dot(topspin_axis), 0.0, "SMASH spin is topspin (positive on topspin axis)")


func test_spin_drop_backspin() -> void :
	var sp: = _shooter()
	var vel: = Vector3(3.0, -2.0, -5.0)
	var omega: Vector3 = sp.compute_shot_spin("DROP", vel, 0.5, 0)
	var travel_dir: = Vector3(vel.x, 0.0, vel.z).normalized()
	var topspin_axis: = Vector3.UP.cross(travel_dir)
	_assert_lt(omega.dot(topspin_axis), 0.0, "DROP spin is backspin (opposite to topspin axis)")


func test_spin_dink_light_backspin() -> void :
	var sp: = _shooter()
	var vel: = Vector3(1.0, 0.0, -3.0)
	var omega: Vector3 = sp.compute_shot_spin("DINK", vel, 0.4, 0)
	var travel_dir: = Vector3(vel.x, 0.0, vel.z).normalized()
	var topspin_axis: = Vector3.UP.cross(travel_dir)
	_assert_lt(omega.dot(topspin_axis), 0.0, "DINK spin is backspin (opposite to topspin axis)")




func test_ai_aims_away_from_opponent_left() -> void :

	var sp: = _shooter()
	var opp: = _FakePlayer.new(0, Vector3(1.5, 1.0, 4.0))
	var me: = _FakePlayer.new(1, Vector3(0.0, 1.0, -3.0))
	var sp2: = _ShotPhysics.new()
	var ball: = _FakeBallNode.new()
	_fixture_nodes.append_array([ball, opp, me])
	sp2.setup(ball, opp, me)
	var ball_pos: = Vector3(0, 0.5, -2.0)
	var vel: Vector3 = sp2.compute_shot_velocity(ball_pos, 0.6, 1, "", 1)
	_assert_lt(vel.x, 0.0, "AI aims LEFT (x<0) when opponent is on left side (x>0.5)")


func test_ai_aims_away_from_opponent_right() -> void :

	var sp: = _shooter()
	var opp: = _FakePlayer.new(0, Vector3(-1.5, 1.0, 4.0))
	var me: = _FakePlayer.new(1, Vector3(0.0, 1.0, -3.0))
	var sp2: = _ShotPhysics.new()
	var ball: = _FakeBallNode.new()
	_fixture_nodes.append_array([ball, opp, me])
	sp2.setup(ball, opp, me)
	var ball_pos: = Vector3(0, 0.5, -2.0)
	var vel: Vector3 = sp2.compute_shot_velocity(ball_pos, 0.6, 1, "", 1)
	_assert_gt(vel.x, 0.0, "AI aims RIGHT (x>0) when opponent is on right side (x<-0.5)")
