class_name PostureOffsetResolver
extends RefCounted









const _PC = preload("res://scripts/posture_constants.gd")
const _Ball = preload("res://scripts/ball.gd")



var _player = null

func _init(player = null) -> void :
	_player = player






func get_posture_offset_for(posture: int) -> Vector3:
	if _player == null:
		return Vector3.ZERO


	if _is_ft_key(posture):
		return Vector3.ZERO



	var blend_def = null
	if "posture" in _player and _player.posture != null and "transition_pose_blend" in _player.posture:
		blend_def = _player.posture.transition_pose_blend
	elif "transition_pose_blend" in _player:
		blend_def = _player.transition_pose_blend

	if blend_def != null and posture == _player.paddle_posture:
		return _compute_offsets_from_def(blend_def)


	var lib = _get_posture_lib()
	if lib:
		var def = lib.get_def(posture)
		if def:
			return _compute_offsets_from_def(def)


	return _get_posture_offset_hardcoded(posture)




func get_posture_rotation_offset_for(posture: int) -> Vector3:
	if _player == null:
		return Vector3.ZERO

	var blend_def = null
	if "posture" in _player and _player.posture != null and "transition_pose_blend" in _player.posture:
		blend_def = _player.posture.transition_pose_blend
	elif "transition_pose_blend" in _player:
		blend_def = _player.transition_pose_blend

	if blend_def != null and posture == _player.paddle_posture:
		return _compute_rotation_from_def(blend_def)

	var lib = _get_posture_lib()
	if lib:
		var def = lib.get_def(posture)
		if def:
			return _compute_rotation_from_def(def)

	return _get_posture_rotation_hardcoded(posture)




func get_posture_charge_sign() -> float:
	if _player == null:
		return 1.0
	match _player.paddle_posture:
		_player.PaddlePosture.BACKHAND, _player.PaddlePosture.LOW_BACKHAND, _player.PaddlePosture.CHARGE_BACKHAND, _player.PaddlePosture.WIDE_BACKHAND, _player.PaddlePosture.MID_LOW_BACKHAND, _player.PaddlePosture.MID_LOW_WIDE_BACKHAND, _player.PaddlePosture.LOW_WIDE_BACKHAND:
			return - _player._get_swing_sign()
		_player.PaddlePosture.FORWARD, _player.PaddlePosture.LOW_FORWARD, _player.PaddlePosture.MID_LOW_FORWARD, _player.PaddlePosture.MEDIUM_OVERHEAD, _player.PaddlePosture.HIGH_OVERHEAD, _player.PaddlePosture.VOLLEY_READY:
			return 0.0
	return _player._get_swing_sign()





func _compute_offsets_from_def(def) -> Vector3:
	if _player == null:
		return Vector3.ZERO
	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()

	return forehand_axis * def.paddle_forehand_mul\
	+ forward_axis * def.paddle_forward_mul\
	+ Vector3(0.0, def.paddle_y_offset, 0.0)



func _compute_rotation_from_def(def) -> Vector3:
	if _player == null:
		return Vector3.ZERO
	var swing_sign: float = _player._get_swing_sign()
	var fwd_sign: float = _player._get_forward_axis().z

	var pitch = def.paddle_pitch_base_deg + def.paddle_pitch_signed_deg * _get_sign_value(def.paddle_pitch_sign_source, swing_sign, fwd_sign)
	var yaw = def.paddle_yaw_base_deg + def.paddle_yaw_signed_deg * _get_sign_value(def.paddle_yaw_sign_source, swing_sign, fwd_sign)
	var roll = def.paddle_roll_base_deg + def.paddle_roll_signed_deg * _get_sign_value(def.paddle_roll_sign_source, swing_sign, fwd_sign)

	return Vector3(pitch, yaw, roll)


func _get_sign_value(src: int, swing_sign: float, fwd_sign: float) -> float:
	match src:
		1: return swing_sign
		2: return fwd_sign
		_: return 1.0






func _get_posture_offset_hardcoded(posture: int) -> Vector3:
	if _player == null:
		return Vector3.ZERO

	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()


	if _is_ft_key(posture):
		return Vector3.ZERO


	if posture == _player.PaddlePosture.FOREHAND:
		return forehand_axis * _PC.PADDLE_SIDE_OFFSET + forward_axis * _PC.PADDLE_FORWARD_OFFSET
	if posture == _player.PaddlePosture.BACKHAND:
		return forehand_axis * - _PC.PADDLE_BACKHAND_OFFSET + forward_axis * _PC.PADDLE_FORWARD_OFFSET
	if posture == _player.PaddlePosture.WIDE_FOREHAND:
		return forehand_axis * 0.95 + forward_axis * _PC.PADDLE_FORWARD_OFFSET
	if posture == _player.PaddlePosture.WIDE_BACKHAND:
		return forehand_axis * -0.95 + forward_axis * _PC.PADDLE_FORWARD_OFFSET
	if posture == _player.PaddlePosture.FORWARD:
		return forward_axis * _PC.PADDLE_FORWARD_OFFSET
	if posture == _player.PaddlePosture.VOLLEY_READY:
		return forward_axis * _PC.PADDLE_FORWARD_OFFSET + Vector3(0.0, 0.12, 0.0)
	if posture == _player.PaddlePosture.READY:
		return forward_axis * 0.55 + Vector3(0.0, -0.28, 0.0)


	if posture == _player.PaddlePosture.MEDIUM_OVERHEAD:
		return forward_axis * _PC.PADDLE_MEDIUM_OVERHEAD_FORWARD + Vector3(0.0, _PC.PADDLE_MEDIUM_OVERHEAD_HEIGHT, 0.0)
	if posture == _player.PaddlePosture.HIGH_OVERHEAD:
		return forward_axis * _PC.PADDLE_HIGH_OVERHEAD_FORWARD + Vector3(0.0, _PC.PADDLE_HIGH_OVERHEAD_HEIGHT, 0.0)


	if posture == _player.PaddlePosture.MID_LOW_FOREHAND:
		return forehand_axis * _PC.PADDLE_SIDE_OFFSET + forward_axis * _PC.PADDLE_FORWARD_OFFSET + Vector3(0.0, -0.2, 0.0)
	if posture == _player.PaddlePosture.MID_LOW_BACKHAND:
		return forehand_axis * - _PC.PADDLE_BACKHAND_OFFSET + forward_axis * _PC.PADDLE_FORWARD_OFFSET + Vector3(0.0, -0.2, 0.0)
	if posture == _player.PaddlePosture.MID_LOW_FORWARD:
		return forward_axis * _PC.PADDLE_FORWARD_OFFSET + Vector3(0.0, -0.2, 0.0)
	if posture == _player.PaddlePosture.MID_LOW_WIDE_FOREHAND:
		return forehand_axis * 0.95 + forward_axis * _PC.PADDLE_FORWARD_OFFSET + Vector3(0.0, -0.2, 0.0)
	if posture == _player.PaddlePosture.MID_LOW_WIDE_BACKHAND:
		return forehand_axis * -0.95 + forward_axis * _PC.PADDLE_FORWARD_OFFSET + Vector3(0.0, -0.2, 0.0)


	if posture == _player.PaddlePosture.LOW_FOREHAND:
		return forehand_axis * _PC.PADDLE_SIDE_OFFSET + forward_axis * _PC.PADDLE_LOW_FORWARD_OFFSET + Vector3(0.0, _PC.PADDLE_LOW_HEIGHT, 0.0)
	if posture == _player.PaddlePosture.LOW_BACKHAND:
		return forehand_axis * - _PC.PADDLE_BACKHAND_OFFSET + forward_axis * _PC.PADDLE_LOW_FORWARD_OFFSET + Vector3(0.0, _PC.PADDLE_LOW_HEIGHT, 0.0)
	if posture == _player.PaddlePosture.LOW_FORWARD:
		return forward_axis * _PC.PADDLE_LOW_FORWARD_OFFSET + Vector3(0.0, _PC.PADDLE_LOW_HEIGHT, 0.0)
	if posture == _player.PaddlePosture.LOW_WIDE_FOREHAND:
		return forehand_axis * 0.95 + forward_axis * _PC.PADDLE_LOW_FORWARD_OFFSET + Vector3(0.0, _PC.PADDLE_LOW_HEIGHT, 0.0)
	if posture == _player.PaddlePosture.LOW_WIDE_BACKHAND:
		return forehand_axis * -0.95 + forward_axis * _PC.PADDLE_LOW_FORWARD_OFFSET + Vector3(0.0, _PC.PADDLE_LOW_HEIGHT, 0.0)


	if posture == _player.PaddlePosture.CHARGE_FOREHAND:
		return forehand_axis * _PC.PADDLE_SIDE_OFFSET + forward_axis * - _PC.PADDLE_CHARGE_FOREHAND_BEHIND + Vector3(0.0, _PC.PADDLE_CHARGE_FOREHAND_HEIGHT, 0.0)
	if posture == _player.PaddlePosture.CHARGE_BACKHAND:
		return forehand_axis * - _PC.PADDLE_BACKHAND_OFFSET + forward_axis * - _PC.PADDLE_CHARGE_BACKHAND_BEHIND + Vector3(0.0, _PC.PADDLE_CHARGE_BACKHAND_HEIGHT, 0.0)

	push_warning("PostureOffsetResolver: using hardcoded fallback for posture ", posture)
	return forward_axis * _PC.PADDLE_CENTER_OFFSET



func _get_posture_rotation_hardcoded(posture: int) -> Vector3:
	if _player == null:
		return Vector3.ZERO

	var swing_sign: float = _player._get_swing_sign()
	var fwd_sign: float = _player._get_forward_axis().z

	if posture == _player.PaddlePosture.FOREHAND:
		return Vector3(-30.0 * fwd_sign, 0.0, 45.0 * swing_sign)
	if posture == _player.PaddlePosture.BACKHAND:
		return Vector3(-30.0 * fwd_sign, 0.0, -45.0 * swing_sign)
	if posture == _player.PaddlePosture.FORWARD:
		return Vector3(-25.0 * fwd_sign, 0.0, 0.0)
	if posture == _player.PaddlePosture.MEDIUM_OVERHEAD:
		return Vector3(-35.0 * fwd_sign, 0.0, 0.0)
	if posture == _player.PaddlePosture.HIGH_OVERHEAD:
		return Vector3(-40.0 * fwd_sign, 0.0, 0.0)
	if posture == _player.PaddlePosture.WIDE_FOREHAND:
		return Vector3(-28.0 * fwd_sign, 12.0 * swing_sign, 35.0 * swing_sign)
	if posture == _player.PaddlePosture.WIDE_BACKHAND:
		return Vector3(-28.0 * fwd_sign, -10.0 * swing_sign, -30.0 * swing_sign)
	if posture == _player.PaddlePosture.VOLLEY_READY:
		return Vector3(-20.0 * fwd_sign, 0.0, 0.0)
	if posture == _player.PaddlePosture.READY:
		return Vector3(-55.0 * fwd_sign, -15.0 * swing_sign, 0.0)

	if posture == _player.PaddlePosture.MID_LOW_FOREHAND:
		return Vector3(-22.0 * fwd_sign, 0.0, 38.0 * swing_sign)
	if posture == _player.PaddlePosture.MID_LOW_BACKHAND:
		return Vector3(-22.0 * fwd_sign, 0.0, -32.0 * swing_sign)
	if posture == _player.PaddlePosture.MID_LOW_FORWARD:
		return Vector3(-25.0 * fwd_sign, 0.0, 0.0)
	if posture == _player.PaddlePosture.MID_LOW_WIDE_FOREHAND:
		return Vector3(-20.0 * fwd_sign, 10.0 * swing_sign, 30.0 * swing_sign)
	if posture == _player.PaddlePosture.MID_LOW_WIDE_BACKHAND:
		return Vector3(-20.0 * fwd_sign, -8.0 * swing_sign, -28.0 * swing_sign)

	if posture == _player.PaddlePosture.LOW_FOREHAND:
		return Vector3(-20.0 * fwd_sign, 0.0, 180.0 + 10.0 * swing_sign)
	if posture == _player.PaddlePosture.LOW_BACKHAND:
		return Vector3(-20.0 * fwd_sign, 0.0, 180.0 - 10.0 * swing_sign)
	if posture == _player.PaddlePosture.LOW_FORWARD:
		return Vector3(-20.0 * fwd_sign, 0.0, 180.0)

	if posture == _player.PaddlePosture.LOW_WIDE_FOREHAND:
		return Vector3(-18.0 * fwd_sign, 12.0 * swing_sign, 180.0 + 8.0 * swing_sign)
	if posture == _player.PaddlePosture.LOW_WIDE_BACKHAND:
		return Vector3(-18.0 * fwd_sign, -10.0 * swing_sign, 180.0 - 8.0 * swing_sign)

	push_warning("PostureOffsetResolver: using hardcoded rotation fallback for posture ", posture)
	return Vector3.ZERO




var _cached_library = null

func _get_posture_lib():
	if _cached_library != null:
		return _cached_library
	if _player and _player.has_method("_get_posture_library"):
		_cached_library = _player._get_posture_library()
	else:
		_cached_library = load("res://scripts/posture_library.gd").new()
	return _cached_library


func _is_ft_key(posture: int) -> bool:

	return posture in [-1, -2, -3, -4]





func compute_contact_at_player_z(ball_pos: Vector3, ball_vel: Vector3, player_z: float) -> Vector3:
	if _player == null:
		return ball_pos
	var g: float = _Ball.get_effective_gravity()
	if abs(ball_vel.z) < 0.1:
		return ball_pos
	var t: float = (player_z - ball_pos.z) / ball_vel.z
	if t < 0.0:
		return ball_pos

	var qa: float = -0.5 * g
	var qb: float = ball_vel.y
	var qc: float = ball_pos.y - 0.08
	var disc: float = qb * qb - 4.0 * qa * qc
	if disc >= 0.0 and qa != 0.0:
		var t_floor: float = ( - qb - sqrt(disc)) / (2.0 * qa)
		if t_floor > 0.0 and t_floor < t:
			var bounce_x: float = ball_pos.x + ball_vel.x * t_floor
			var bounce_z: float = ball_pos.z + ball_vel.z * t_floor
			var vy_at_floor: float = ball_vel.y - g * t_floor
			var bounce_vy: float = abs(vy_at_floor) * _Ball.cor_for_impact_speed(abs(vy_at_floor))
			var rem_t: float = (player_z - bounce_z) / ball_vel.z
			if rem_t > 0.0:
				return Vector3(
					bounce_x + ball_vel.x * rem_t, 
					0.08 + bounce_vy * rem_t - 0.5 * g * rem_t * rem_t, 
					player_z)

	return Vector3(
		ball_pos.x + ball_vel.x * t, 
		ball_pos.y + ball_vel.y * t - 0.5 * g * t * t, 
		player_z)



