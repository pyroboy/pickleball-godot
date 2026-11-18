class_name TestPlayerHitting extends TestBase






const _PhysicsUtils: = preload("res://scripts/physics.gd")
const _PADDLE_VEL_SMOOTH_HALFLIFE: float = 0.08
const _PADDLE_VEL_TRANSFER: float = 0.4


func run_all(totals: Dictionary) -> void :
	var tests: Array[Callable] = [

		test_velocity_converges_to_target, 
		test_velocity_tracks_constant_motion, 

		test_transfer_scalar_bounds, 

		test_halflife_reasonable_range, 

		test_charge_visual_sets_active, 
		test_charge_visual_clears_on_abort, 
	]
	_run_test_list(totals, tests)




func _ema_step(prev_vel: Vector3, prev_pos: Vector3, new_pos: Vector3, halflife: float, dt: float) -> Vector3:
	var raw_delta: Vector3 = (new_pos - prev_pos) / maxf(dt, 0.0001)
	return _PhysicsUtils._damp_v3(prev_vel, raw_delta, halflife, dt)




func test_velocity_converges_to_target() -> void :

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


func test_velocity_tracks_constant_motion() -> void :

	var vel: Vector3 = Vector3.ZERO
	var prev_pos: Vector3 = Vector3.ZERO
	var new_pos: Vector3 = Vector3.ZERO
	var target: Vector3 = Vector3(5.0, 2.0, -1.0)
	var dt: float = 0.016

	for i in range(10):
		new_pos = prev_pos + target * dt
		vel = _ema_step(vel, prev_pos, new_pos, _PADDLE_VEL_SMOOTH_HALFLIFE, dt)
		prev_pos = new_pos



	var expected_10f: float = target.length() * (1.0 - exp(-0.693 * 10.0 * 0.016 / _PADDLE_VEL_SMOOTH_HALFLIFE))
	_assert_eq_f(vel.length(), expected_10f, 0.15, "EMA velocity after 10 frames matches exponential model")




func test_transfer_scalar_bounds() -> void :


	_assert_true(_PADDLE_VEL_TRANSFER >= 0.0, "transfer scalar is non-negative")
	_assert_true(_PADDLE_VEL_TRANSFER <= 1.0, "transfer scalar is <= 1 (fraction of paddle speed)")


	var max_contribution: float = 15.0 * _PADDLE_VEL_TRANSFER
	_assert_true(max_contribution > 1.0, "max paddle velocity contribution > 1 m/s (meaningful)")
	_assert_true(max_contribution < 12.0, "max paddle velocity contribution < 12 m/s (ball physics still dominant)")




func test_halflife_reasonable_range() -> void :



	var dt: float = 0.016
	var fraction_per_frame: float = 1.0 - exp(-0.693 * dt / _PADDLE_VEL_SMOOTH_HALFLIFE)
	_assert_true(fraction_per_frame > 0.05, "per-frame smoothing > 5% (responsive enough)")
	_assert_true(fraction_per_frame < 0.3, "per-frame smoothing < 30% (smooth, not jittery)")

	var frames_to_95: float = - _PADDLE_VEL_SMOOTH_HALFLIFE / dt * log(0.05) / 0.693
	_assert_true(frames_to_95 < 40.0, "95% convergence in < 40 frames (~0.64s)")




class _FakePlayerForHitting extends Node:
	enum PaddlePosture{
		FOREHAND, FORWARD, BACKHAND, 
		MEDIUM_OVERHEAD, HIGH_OVERHEAD, 
		LOW_FOREHAND, LOW_FORWARD, LOW_BACKHAND, 
		CHARGE_FOREHAND, CHARGE_BACKHAND, 
		WIDE_FOREHAND, WIDE_BACKHAND, 
		VOLLEY_READY, 
		MID_LOW_FOREHAND, MID_LOW_BACKHAND, MID_LOW_FORWARD, 
		MID_LOW_WIDE_FOREHAND, MID_LOW_WIDE_BACKHAND, 
		LOW_WIDE_FOREHAND, LOW_WIDE_BACKHAND, 
		READY, 
	}
	const FOREHAND_POSTURES: = [PaddlePosture.FOREHAND, PaddlePosture.LOW_FOREHAND, PaddlePosture.WIDE_FOREHAND, PaddlePosture.MID_LOW_FOREHAND, PaddlePosture.MID_LOW_WIDE_FOREHAND, PaddlePosture.LOW_WIDE_FOREHAND]
	const BACKHAND_POSTURES: = [PaddlePosture.BACKHAND, PaddlePosture.LOW_BACKHAND, PaddlePosture.WIDE_BACKHAND, PaddlePosture.MID_LOW_BACKHAND, PaddlePosture.MID_LOW_WIDE_BACKHAND, PaddlePosture.LOW_WIDE_BACKHAND]
	const CENTER_POSTURES: = [PaddlePosture.FORWARD, PaddlePosture.LOW_FORWARD, PaddlePosture.MID_LOW_FORWARD, PaddlePosture.VOLLEY_READY]
	const FT_FOREHAND: = -1
	const FT_BACKHAND: = -2
	const FT_CENTER: = -3
	const FT_OVERHEAD: = -4

	var paddle_node: Node3D = Node3D.new()
	var body_pivot: Node3D = Node3D.new()
	var posture = self
	var transition_pose_blend = null
	var is_ai: bool = false
	var paddle_posture: int = PaddlePosture.READY
	var paddle_rest_position: Vector3 = Vector3.ZERO
	var paddle_rest_rotation: Vector3 = Vector3.ZERO

	func _init() -> void :
		add_child(paddle_node)
		add_child(body_pivot)

	func _ensure_paddle_ready() -> bool:
		return true
	func _get_posture_charge_sign() -> float:
		return 1.0
	func _get_forward_axis() -> Vector3:
		return Vector3(0.0, 0.0, -1.0)
	func _get_forehand_axis() -> Vector3:
		return Vector3(1.0, 0.0, 0.0)
	func _get_swing_sign() -> float:
		return 1.0
	func _get_posture_offset_for(_p: int) -> Vector3:
		return Vector3.ZERO
	func _get_posture_rotation_offset_for(_p: int) -> Vector3:
		return Vector3.ZERO

func test_charge_visual_sets_active() -> void :

	var hitting: = preload("res://scripts/player_hitting.gd").new()
	var fake_player: = _FakePlayerForHitting.new()
	hitting._player = fake_player

	_assert_true( not hitting.charge_visual_active, "charge_visual_active starts false")
	hitting.set_serve_charge_visual(0.5)
	_assert_true(hitting.charge_visual_active, "set_serve_charge_visual sets charge_visual_active true")

	fake_player.queue_free()
	hitting.queue_free()

func test_charge_visual_clears_on_abort() -> void :

	var hitting: = preload("res://scripts/player_hitting.gd").new()
	var fake_player: = _FakePlayerForHitting.new()
	hitting._player = fake_player

	hitting.set_serve_charge_visual(0.5)
	_assert_true(hitting.charge_visual_active, "charge is active before abort")
	hitting.clear_charge_visual()
	_assert_true( not hitting.charge_visual_active, "clear_charge_visual resets charge_visual_active")
	_assert_true( not hitting.is_in_follow_through, "clear_charge_visual resets is_in_follow_through")

	fake_player.queue_free()
	hitting.queue_free()
