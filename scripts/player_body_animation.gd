class_name PlayerBodyAnimation extends Node

# Body animation constants
const BODY_CHARGE_ROTATION_DEGREES := 35.0
const BODY_TRACK_BALL_MAX_DEGREES := 25.0
const BODY_TRACK_HALFLIFE := 0.08
const STANCE_BASE_ROTATION_DEGREES := 12.0
const BODY_BACKHAND_ROTATION_DEGREES := 35.0
const BODY_CHARGE_BACKHAND_ROTATION_DEGREES := 110.0  # body angled to match staggered foot stance
const BODY_LEAN_MAX_DEGREES := 14.0
const BODY_LEAN_HALFLIFE := 0.1
const CROUCH_BASE_AMOUNT := 0.0
const CROUCH_READY_AMOUNT := 0.10
const CROUCH_LOW_POSTURE_AMOUNT := 0.28
const CROUCH_MID_LOW_POSTURE_AMOUNT := 0.16
const CROUCH_HALFLIFE := 0.15
const CROUCH_LOW_HALFLIFE := 0.12
const CROUCH_BALL_DISTANCE := 6.0
const STRIDE_LEN_WALK := 0.24
const STRIDE_LEN_RUN := 0.40
const IDLE_SWAY_SPEED := 1.8
const IDLE_SWAY_AMOUNT := 0.025
const WALK_BOB_AMOUNT := 0.04
const RUN_BOB_AMOUNT := 0.02

# Body animation state
var body_lean_x: float = 0.0
var body_lean_z: float = 0.0
var crouch_amount: float = 0.0
var idle_sway_phase: float = 0.0
var prev_velocity: Vector3 = Vector3.ZERO

var _player: PlayerController

func _ready() -> void:
	_player = get_parent() as CharacterBody3D

func update_body_lean(delta: float) -> void:
	if not _player.body_pivot or delta < 0.0001:
		return

	var fh_axis: Vector3 = _player._get_forehand_axis()
	var fwd_axis: Vector3 = _player._get_forward_axis()
	var runtime_def: PostureDefinition = _player.get_runtime_posture_def()
	var base_pitch_deg: float = runtime_def.body_pitch_deg if runtime_def else 0.0
	var base_roll_deg: float = runtime_def.body_roll_deg * _player._get_swing_sign() if runtime_def else 0.0

	# Acceleration-based lean (responsive to direction changes)
	var accel: Vector3 = (_player.current_velocity - prev_velocity) / delta
	prev_velocity = _player.current_velocity
	var accel_lateral: float = accel.dot(fh_axis)
	var accel_forward: float = accel.dot(fwd_axis)

	# Velocity-based lean (sustained lean into movement direction)
	var vel_lateral: float = _player.current_velocity.dot(fh_axis)
	var vel_forward: float = _player.current_velocity.dot(fwd_axis)

	# Combine: acceleration for snappy response + velocity for sustained lean
	var accel_scale: float = BODY_LEAN_MAX_DEGREES / 8.0
	var vel_scale: float = BODY_LEAN_MAX_DEGREES / (_player.move_speed * 1.5)
	var target_lean_z: float = clampf(-accel_lateral * accel_scale - vel_lateral * vel_scale, -BODY_LEAN_MAX_DEGREES, BODY_LEAN_MAX_DEGREES)
	var target_lean_x: float = clampf(accel_forward * accel_scale + vel_forward * vel_scale, -BODY_LEAN_MAX_DEGREES, BODY_LEAN_MAX_DEGREES)

	# Lean toward ghost expansion direction (reaching for wide balls)
	if _player.posture and _player.posture._committed_incoming_posture >= 0:
		var contact: Vector3 = _player.posture._contact_point_local
		if contact != Vector3.ZERO:
			var reach_lateral: float = contact.dot(fh_axis)
			var lean_boost: float = clampf(abs(reach_lateral) - 0.2, 0.0, 0.7) * 12.0 * sign(reach_lateral)
			target_lean_z -= lean_boost

	body_lean_z = _player._damp(body_lean_z, target_lean_z + base_roll_deg, BODY_LEAN_HALFLIFE, delta)
	body_lean_x = _player._damp(body_lean_x, target_lean_x + base_pitch_deg, BODY_LEAN_HALFLIFE, delta)

	_player.body_pivot.rotation.z = deg_to_rad(body_lean_z)
	_player.body_pivot.rotation.x = deg_to_rad(body_lean_x)

func update_crouch(delta: float) -> void:
	if not _player.body_pivot:
		return
	# Crouch: auto from posture + manual toggle stacks (deepest wins)
	var target_crouch: float = CROUCH_BASE_AMOUNT
	var halflife: float = CROUCH_HALFLIFE
	var p: int = _player.paddle_posture
	if p in [_player.PaddlePosture.LOW_FOREHAND, _player.PaddlePosture.LOW_BACKHAND,
			_player.PaddlePosture.LOW_FORWARD, _player.PaddlePosture.LOW_WIDE_FOREHAND,
			_player.PaddlePosture.LOW_WIDE_BACKHAND]:
		target_crouch = CROUCH_LOW_POSTURE_AMOUNT
		halflife = CROUCH_LOW_HALFLIFE
	elif p in [_player.PaddlePosture.MID_LOW_FOREHAND, _player.PaddlePosture.MID_LOW_BACKHAND,
			_player.PaddlePosture.MID_LOW_FORWARD, _player.PaddlePosture.MID_LOW_WIDE_FOREHAND,
			_player.PaddlePosture.MID_LOW_WIDE_BACKHAND]:
		target_crouch = CROUCH_MID_LOW_POSTURE_AMOUNT
	# Manual crouch adds on top — always at least this deep
	if _player.manual_crouch:
		target_crouch = maxf(target_crouch, CROUCH_LOW_POSTURE_AMOUNT)
		halflife = CROUCH_LOW_HALFLIFE
	var pdef_c: PostureDefinition = _player.get_runtime_posture_def()
	if pdef_c:
		target_crouch = maxf(target_crouch, pdef_c.crouch_amount)
	crouch_amount = _player._damp(crouch_amount, target_crouch, halflife, delta)

	# Walking body bob — body dips between steps, rises over planted foot
	var speed: float = Vector3(_player.current_velocity.x, 0.0, _player.current_velocity.z).length()
	var bob: float = 0.0
	if speed > 0.1:
		var speed_ratio: float = clampf(speed / _player.move_speed, 0.0, 1.0)
		var bob_amount: float = lerpf(WALK_BOB_AMOUNT, RUN_BOB_AMOUNT, speed_ratio)
		# CoM height from arc-length: lowest during double-support, highest over support foot
		var stride_len_bob: float = lerpf(STRIDE_LEN_WALK, STRIDE_LEN_RUN, speed_ratio)
		var bob_phase: float = TAU * _player.leg_ik.gait_arc_length / maxf(stride_len_bob * 2.0, 0.01)
		bob = (1.0 - cos(bob_phase)) * 0.5 * bob_amount

	_player.body_pivot.position.y = -crouch_amount - bob

func update_idle_sway(delta: float) -> void:
	if not _player.body_pivot:
		return
	var speed: float = Vector3(_player.current_velocity.x, 0.0, _player.current_velocity.z).length()
	if speed < 0.1:
		idle_sway_phase += IDLE_SWAY_SPEED * delta
		# Lateral sway
		var sway: float = sin(idle_sway_phase) * IDLE_SWAY_AMOUNT
		_player.body_pivot.position.x = _player._damp(_player.body_pivot.position.x, sway, 0.12, delta)
		# Subtle breathing bob
		var breath_bob: float = sin(idle_sway_phase * 1.3) * 0.008
		_player.body_pivot.position.y += breath_bob
	else:
		_player.body_pivot.position.x = _player._damp(_player.body_pivot.position.x, 0.0, 0.06, delta)

func update_body_track_ball(delta: float) -> void:
	if not _player.body_pivot:
		return

	# CHARGE_BACKHAND rotation must run even when charge_visual_active
	var p_now: int = _player.paddle_posture
	if p_now == _player.PaddlePosture.CHARGE_BACKHAND:
		var target: float = -deg_to_rad(BODY_CHARGE_BACKHAND_ROTATION_DEGREES) * _player._get_swing_sign()
		_player.body_pivot.rotation.y = _player._damp(_player.body_pivot.rotation.y, target, BODY_TRACK_HALFLIFE, delta)
		return

	# Skip tracking when charging (forehand) or swing tween is playing
	if _player.hitting.charge_visual_active:
		return
	if _player.hitting.paddle_swing_tween != null and _player.hitting.paddle_swing_tween.is_valid():
		return

	# Base stance rotation — backhand postures rotate body perpendicular, forehand slight angle
	var runtime_def: PostureDefinition = _player.get_runtime_posture_def()
	var stance_base: float
	if runtime_def and absf(runtime_def.body_yaw_deg) > 0.01:
		stance_base = deg_to_rad(runtime_def.body_yaw_deg) * _player._get_swing_sign()
	elif p_now in _player.BACKHAND_POSTURES:
		stance_base = -deg_to_rad(BODY_BACKHAND_ROTATION_DEGREES) * _player._get_swing_sign()
	else:
		stance_base = deg_to_rad(STANCE_BASE_ROTATION_DEGREES) * _player._get_swing_sign()
	# Minimize body rotation during committed tracking so body doesn't drag paddle off ghost
	if _player.posture and _player.posture._committed_incoming_posture >= 0:
		stance_base *= 0.2

	var b = _player._get_ball_ref()
	if b == null:
		_player.body_pivot.rotation.y = _player._damp(_player.body_pivot.rotation.y, stance_base, BODY_TRACK_HALFLIFE, delta)
		return

	var to_ball: Vector3 = b.global_position - _player.global_position
	to_ball.y = 0.0
	if to_ball.length_squared() < 0.01:
		return

	var forward: Vector3 = _player._get_forward_axis()
	var angle_to_ball: float = forward.signed_angle_to(to_ball.normalized(), Vector3.UP)
	var track_w: float = 1.0
	var pdef_t: PostureDefinition = runtime_def
	if pdef_t:
		track_w = pdef_t.head_track_ball_weight
	var max_rad: float = deg_to_rad(BODY_TRACK_BALL_MAX_DEGREES) * clampf(track_w, 0.0, 1.0)
	var target_y: float = clampf(angle_to_ball, -max_rad, max_rad) + stance_base
	# Smooth lerp toward target
	_player.body_pivot.rotation.y = _player._damp(_player.body_pivot.rotation.y, target_y, BODY_TRACK_HALFLIFE, delta)
