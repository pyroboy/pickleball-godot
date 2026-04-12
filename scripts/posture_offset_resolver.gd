class_name PostureOffsetResolver
extends RefCounted

## Phase 2: Extracted offset/rotation computation from player_paddle_posture.gd.
##
## Takes a posture ID + player state → world-space paddle position and rotation.
## All functions use PostureConstants for the literal values.
##
## The resolver is a RefCounted (not Node) so it can be used headlessly
## (e.g. by tools / tests that have no scene tree).

const _PC := preload("res://scripts/posture_constants.gd")

## Weak reference to the player — may be null for headless use.
## When non-null, enables library-backed posture resolution.
var _player: PlayerController = null

func _init(player: PlayerController = null) -> void:
	_player = player


## ── Public API ────────────────────────────────────────────────────────────

## Returns the paddle world-space position offset for the given posture.
## Tries PostureLibrary first; falls back to hardcoded values.
func get_posture_offset_for(posture: int) -> Vector3:
	if _player == null:
		return Vector3.ZERO

	# Follow-through ghosts are static — positioned at creation, not here
	if _is_ft_key(posture):
		return Vector3.ZERO

	if _player.transition_pose_blend != null and posture == _player.paddle_posture:
		return _compute_offsets_from_def(_player.transition_pose_blend)

	# Try the library first (Phase 2+), fall back to hardcoded for safety
	var lib := _get_posture_lib()
	if lib:
		var def := lib.get_def(posture)
		if def:
			return _compute_offsets_from_def(def)

	# Fallback to old hardcoded values (removed after Phase 2 verified)
	return _get_posture_offset_hardcoded(posture)


## Returns the paddle rotation offset (pitch/yaw/roll in degrees) for the given posture.
## Tries PostureLibrary first; falls back to hardcoded values.
func get_posture_rotation_offset_for(posture: int) -> Vector3:
	if _player == null:
		return Vector3.ZERO

	if _player.transition_pose_blend != null and posture == _player.paddle_posture:
		return _compute_rotation_from_def(_player.transition_pose_blend)

	var lib := _get_posture_lib()
	if lib:
		var def := lib.get_def(posture)
		if def:
			return _compute_rotation_from_def(def)

	return _get_posture_rotation_hardcoded(posture)


## Returns ±1.0 based on whether the current posture uses backhand (-1) or forehand (+1).
## Used by follow-through offset computation.
func get_posture_charge_sign() -> float:
	if _player == null:
		return 1.0
	match _player.paddle_posture:
		_player.PaddlePosture.BACKHAND,
		_player.PaddlePosture.LOW_BACKHAND,
		_player.PaddlePosture.CHARGE_BACKHAND,
		_player.PaddlePosture.WIDE_BACKHAND,
		_player.PaddlePosture.MID_LOW_BACKHAND,
		_player.PaddlePosture.MID_LOW_WIDE_BACKHAND,
		_player.PaddlePosture.LOW_WIDE_BACKHAND:
			return -_player._get_swing_sign()
		_player.PaddlePosture.FORWARD,
		_player.PaddlePosture.LOW_FORWARD,
		_player.PaddlePosture.MID_LOW_FORWARD,
		_player.PaddlePosture.MEDIUM_OVERHEAD,
		_player.PaddlePosture.HIGH_OVERHEAD,
		_player.PaddlePosture.VOLLEY_READY:
			return 0.0
	return _player._get_swing_sign()


## ── Internal helpers ───────────────────────────────────────────────────────

## Computes paddle offset from PostureDefinition using player's dynamic axes.
func _compute_offsets_from_def(def: PostureDefinition) -> Vector3:
	if _player == null:
		return Vector3.ZERO
	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	# Position = forehand_mul * forehand_axis + forward_mul * forward_axis + y_offset
	return forehand_axis * def.paddle_forehand_mul \
		+ forward_axis * def.paddle_forward_mul \
		+ Vector3(0.0, def.paddle_y_offset, 0.0)


## Computes rotation offset from PostureDefinition using sign sources.
func _compute_rotation_from_def(def: PostureDefinition) -> Vector3:
	if _player == null:
		return Vector3.ZERO
	var swing_sign: float = _player._get_swing_sign()
	var fwd_sign: float = _player._get_forward_axis().z

	var pitch := def.paddle_pitch_base_deg + def.paddle_pitch_signed_deg * _get_sign_value(def.paddle_pitch_sign_source, swing_sign, fwd_sign)
	var yaw := def.paddle_yaw_base_deg + def.paddle_yaw_signed_deg * _get_sign_value(def.paddle_yaw_sign_source, swing_sign, fwd_sign)
	var roll := def.paddle_roll_base_deg + def.paddle_roll_signed_deg * _get_sign_value(def.paddle_roll_sign_source, swing_sign, fwd_sign)

	return Vector3(pitch, yaw, roll)


func _get_sign_value(src: int, swing_sign: float, fwd_sign: float) -> float:
	match src:
		1: return swing_sign  # SwingSign
		2: return fwd_sign    # FwdSign
		_: return 1.0         # None


## ── Hardcoded fallback (to be removed after Phase 2 verified) ───────────────

## Fallback hardcoded position values.
## Kept for safety during migration — prints warnings until removed.
func _get_posture_offset_hardcoded(posture: int) -> Vector3:
	if _player == null:
		return Vector3.ZERO
	push_warning("PostureOffsetResolver: using hardcoded fallback for posture ", posture)

	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()

	# Follow-through ghosts are static — positioned at creation, not here
	if _is_ft_key(posture):
		return Vector3.ZERO

	if posture == _player.PaddlePosture.FOREHAND:
		return forehand_axis * _PC.PADDLE_SIDE_OFFSET + forward_axis * _PC.PADDLE_FORWARD_OFFSET
	if posture == _player.PaddlePosture.BACKHAND:
		return forehand_axis * -_PC.PADDLE_BACKHAND_OFFSET + forward_axis * (_PC.PADDLE_FORWARD_OFFSET * 0.9)
	if posture == _player.PaddlePosture.MEDIUM_OVERHEAD:
		return forehand_axis * _PC.PADDLE_OVERHEAD_SIDE_OFFSET + forward_axis * _PC.PADDLE_MEDIUM_OVERHEAD_FORWARD + Vector3(0.0, _PC.PADDLE_MEDIUM_OVERHEAD_HEIGHT, 0.0)
	if posture == _player.PaddlePosture.HIGH_OVERHEAD:
		return forehand_axis * _PC.PADDLE_OVERHEAD_SIDE_OFFSET + forward_axis * _PC.PADDLE_HIGH_OVERHEAD_FORWARD + Vector3(0.0, _PC.PADDLE_HIGH_OVERHEAD_HEIGHT, 0.0)
	if posture == _player.PaddlePosture.LOW_FOREHAND:
		return forehand_axis * _PC.PADDLE_SIDE_OFFSET + forward_axis * _PC.PADDLE_LOW_FORWARD_OFFSET + Vector3(0.0, _PC.PADDLE_LOW_HEIGHT, 0.0)
	if posture == _player.PaddlePosture.LOW_BACKHAND:
		return forehand_axis * -_PC.PADDLE_BACKHAND_OFFSET + forward_axis * _PC.PADDLE_LOW_FORWARD_OFFSET + Vector3(0.0, _PC.PADDLE_LOW_HEIGHT, 0.0)
	if posture == _player.PaddlePosture.LOW_FORWARD:
		return forward_axis * _PC.PADDLE_LOW_FORWARD_OFFSET + Vector3(0.0, _PC.PADDLE_LOW_HEIGHT, 0.0)
	if posture == _player.PaddlePosture.CHARGE_FOREHAND:
		return forehand_axis * _PC.PADDLE_SIDE_OFFSET + forward_axis * -_PC.PADDLE_CHARGE_FOREHAND_BEHIND + Vector3(0.0, _PC.PADDLE_CHARGE_FOREHAND_HEIGHT, 0.0)
	if posture == _player.PaddlePosture.CHARGE_BACKHAND:
		return forehand_axis * -_PC.PADDLE_BACKHAND_OFFSET + forward_axis * -_PC.PADDLE_CHARGE_BACKHAND_BEHIND + Vector3(0.0, _PC.PADDLE_CHARGE_BACKHAND_HEIGHT, 0.0)
	if posture == _player.PaddlePosture.WIDE_FOREHAND:
		return forehand_axis * 0.85 + forward_axis * 0.55
	if posture == _player.PaddlePosture.WIDE_BACKHAND:
		return forehand_axis * -0.72 + forward_axis * 0.52
	if posture == _player.PaddlePosture.VOLLEY_READY:
		return forward_axis * 0.50 + Vector3(0.0, 0.12, 0.0)
	if posture == _player.PaddlePosture.READY:
		return forward_axis * 0.55 + Vector3(0.0, -0.28, 0.0)
	# Mid-low tier
	if posture == _player.PaddlePosture.MID_LOW_FOREHAND:
		return forehand_axis * _PC.PADDLE_SIDE_OFFSET + forward_axis * 0.50 + Vector3(0.0, -0.18, 0.0)
	if posture == _player.PaddlePosture.MID_LOW_BACKHAND:
		return forehand_axis * -_PC.PADDLE_BACKHAND_OFFSET + forward_axis * 0.48 + Vector3(0.0, -0.18, 0.0)
	if posture == _player.PaddlePosture.MID_LOW_FORWARD:
		return forward_axis * 0.52 + Vector3(0.0, -0.18, 0.0)
	if posture == _player.PaddlePosture.MID_LOW_WIDE_FOREHAND:
		return forehand_axis * 0.88 + forward_axis * 0.58 + Vector3(0.0, -0.20, 0.0)
	if posture == _player.PaddlePosture.MID_LOW_WIDE_BACKHAND:
		return forehand_axis * -0.74 + forward_axis * 0.54 + Vector3(0.0, -0.20, 0.0)
	# Low-wide tier
	if posture == _player.PaddlePosture.LOW_WIDE_FOREHAND:
		return forehand_axis * 0.90 + forward_axis * 0.60 + Vector3(0.0, _PC.PADDLE_LOW_HEIGHT, 0.0)
	if posture == _player.PaddlePosture.LOW_WIDE_BACKHAND:
		return forehand_axis * -0.78 + forward_axis * 0.56 + Vector3(0.0, _PC.PADDLE_LOW_HEIGHT, 0.0)
	return forward_axis * _PC.PADDLE_CENTER_OFFSET


## Fallback hardcoded rotation values.
func _get_posture_rotation_hardcoded(posture: int) -> Vector3:
	if _player == null:
		return Vector3.ZERO
	push_warning("PostureOffsetResolver: using hardcoded rotation fallback for posture ", posture)

	var swing_sign: float = _player._get_swing_sign()
	var fwd_sign: float = _player._get_forward_axis().z

	if posture == _player.PaddlePosture.FOREHAND:
		return Vector3(0.0, 0.0, 45.0 * swing_sign)
	if posture == _player.PaddlePosture.WIDE_FOREHAND:
		return Vector3(0.0, 12.0 * swing_sign, 35.0 * swing_sign)
	if posture == _player.PaddlePosture.WIDE_BACKHAND:
		return Vector3(0.0, -10.0 * swing_sign, -30.0 * swing_sign)
	if posture == _player.PaddlePosture.VOLLEY_READY:
		return Vector3(-15.0 * fwd_sign, 0.0, 0.0)
	if posture == _player.PaddlePosture.READY:
		return Vector3(-55.0 * fwd_sign, -15.0 * swing_sign, 0.0)
	# Mid-low
	if posture == _player.PaddlePosture.MID_LOW_FOREHAND:
		return Vector3(20.0 * fwd_sign, 0.0, 38.0 * swing_sign)
	if posture == _player.PaddlePosture.MID_LOW_BACKHAND:
		return Vector3(20.0 * fwd_sign, 0.0, -32.0 * swing_sign)
	if posture == _player.PaddlePosture.MID_LOW_FORWARD:
		return Vector3(25.0 * fwd_sign, 0.0, 0.0)
	if posture == _player.PaddlePosture.MID_LOW_WIDE_FOREHAND:
		return Vector3(18.0 * fwd_sign, 10.0 * swing_sign, 30.0 * swing_sign)
	if posture == _player.PaddlePosture.MID_LOW_WIDE_BACKHAND:
		return Vector3(18.0 * fwd_sign, -8.0 * swing_sign, -28.0 * swing_sign)
	# Low: inverted
	if posture == _player.PaddlePosture.LOW_FOREHAND:
		return Vector3(0.0, 0.0, 180.0 + 10.0 * swing_sign)
	if posture == _player.PaddlePosture.LOW_BACKHAND:
		return Vector3(0.0, 0.0, 180.0 - 10.0 * swing_sign)
	if posture == _player.PaddlePosture.LOW_FORWARD:
		return Vector3(0.0, 0.0, 180.0)
	# Low-wide
	if posture == _player.PaddlePosture.LOW_WIDE_FOREHAND:
		return Vector3(0.0, 12.0 * swing_sign, 180.0 + 8.0 * swing_sign)
	if posture == _player.PaddlePosture.LOW_WIDE_BACKHAND:
		return Vector3(0.0, -10.0 * swing_sign, 180.0 - 8.0 * swing_sign)
	return Vector3.ZERO


## ── Private ────────────────────────────────────────────────────────────────

func _get_posture_lib() -> PostureLibrary:
	if _player and _player.has_method("_get_posture_library"):
		return _player._get_posture_library()
	return PostureLibrary.instance() if PostureLibrary else null


func _is_ft_key(posture: int) -> bool:
	# FT_FOREHAND=-1, FT_BACKHAND=-2, FT_CENTER=-3, FT_OVERHEAD=-4
	return posture in [-1, -2, -3, -4]


## ── Extracted from player_paddle_posture.gd ───────────────────────────────────

## Returns 0=forehand, 1=backhand, 2=center, 3=overhead family for a posture.
func get_posture_family(p: int) -> int:
	if _player == null:
		return 0
	match p:
		_player.PaddlePosture.FOREHAND, _player.PaddlePosture.WIDE_FOREHAND, \
		_player.PaddlePosture.LOW_FOREHAND, _player.PaddlePosture.CHARGE_FOREHAND, \
		_player.PaddlePosture.MID_LOW_FOREHAND, _player.PaddlePosture.MID_LOW_WIDE_FOREHAND, \
		_player.PaddlePosture.LOW_WIDE_FOREHAND:
			return 0  # forehand
		_player.PaddlePosture.BACKHAND, _player.PaddlePosture.WIDE_BACKHAND, \
		_player.PaddlePosture.LOW_BACKHAND, _player.PaddlePosture.CHARGE_BACKHAND, \
		_player.PaddlePosture.MID_LOW_BACKHAND, _player.PaddlePosture.MID_LOW_WIDE_BACKHAND, \
		_player.PaddlePosture.LOW_WIDE_BACKHAND:
			return 1  # backhand
		_player.PaddlePosture.FORWARD, _player.PaddlePosture.LOW_FORWARD, \
		_player.PaddlePosture.READY, _player.PaddlePosture.VOLLEY_READY, \
		_player.PaddlePosture.MID_LOW_FORWARD:
			return 2  # center
		_player.PaddlePosture.MEDIUM_OVERHEAD, _player.PaddlePosture.HIGH_OVERHEAD:
			return 3  # overhead
	return 0


## Returns 0=low, 1=mid-low, 2=normal height tier for a ball height above player ground.
func get_height_zone(rel_h: float) -> int:
	if rel_h < 0.15:
		return 0  # low
	if rel_h < 0.50:
		return 1  # mid-low
	return 2  # normal


## Analytical O(1) ball-projection to player's Z plane.
## Handles bounce (post-bounce arc if ball hits floor before player's Z).
func compute_contact_at_player_z(ball_pos: Vector3, ball_vel: Vector3, player_z: float) -> Vector3:
	if _player == null:
		return ball_pos
	var g: float = Ball.get_effective_gravity()
	if abs(ball_vel.z) < 0.1:
		return ball_pos
	var t: float = (player_z - ball_pos.z) / ball_vel.z
	if t < 0.0:
		return ball_pos
	# Check if ball bounces before player
	var qa: float = -0.5 * g
	var qb: float = ball_vel.y
	var qc: float = ball_pos.y - 0.08
	var disc: float = qb * qb - 4.0 * qa * qc
	if disc >= 0.0 and qa != 0.0:
		var t_floor: float = (-qb - sqrt(disc)) / (2.0 * qa)
		if t_floor > 0.0 and t_floor < t:
			var bounce_x: float = ball_pos.x + ball_vel.x * t_floor
			var bounce_z: float = ball_pos.z + ball_vel.z * t_floor
			var vy_at_floor: float = ball_vel.y - g * t_floor
			var bounce_vy: float = abs(vy_at_floor) * Ball.cor_for_impact_speed(abs(vy_at_floor))
			var rem_t: float = (player_z - bounce_z) / ball_vel.z
			if rem_t > 0.0:
				return Vector3(
					bounce_x + ball_vel.x * rem_t,
					0.08 + bounce_vy * rem_t - 0.5 * g * rem_t * rem_t,
					player_z)
	# Direct flight
	return Vector3(
		ball_pos.x + ball_vel.x * t,
		ball_pos.y + ball_vel.y * t - 0.5 * g * t * t,
		player_z)


## Returns overhead posture (HIGH_OVERHEAD / MEDIUM_OVERHEAD) or -1 if not applicable.
## Callers pass current paddle_posture so the function can apply hysteresis.
func get_overhead_posture(ball_position: Vector3, horizontal_distance: float, current_posture: int) -> int:
	if _player == null:
		return -1
	var relative_ball_height: float = ball_position.y - _player.ground_y
	if current_posture == _player.PaddlePosture.HIGH_OVERHEAD:
		if relative_ball_height >= _PC.OVERHEAD_RELEASE_HEIGHT and horizontal_distance <= _PC.OVERHEAD_RELEASE_RADIUS:
			if relative_ball_height >= _PC.HIGH_OVERHEAD_TRIGGER_HEIGHT:
				return _player.PaddlePosture.HIGH_OVERHEAD
			if relative_ball_height >= _PC.MEDIUM_OVERHEAD_TRIGGER_HEIGHT:
				return _player.PaddlePosture.MEDIUM_OVERHEAD
		return -1
	if current_posture == _player.PaddlePosture.MEDIUM_OVERHEAD:
		if relative_ball_height >= _PC.OVERHEAD_RELEASE_HEIGHT and horizontal_distance <= _PC.OVERHEAD_RELEASE_RADIUS:
			if relative_ball_height >= _PC.HIGH_OVERHEAD_TRIGGER_HEIGHT:
				return _player.PaddlePosture.HIGH_OVERHEAD
			return _player.PaddlePosture.MEDIUM_OVERHEAD
		return -1
	# From non-overhead posture
	if relative_ball_height >= _PC.HIGH_OVERHEAD_TRIGGER_HEIGHT:
		return _player.PaddlePosture.HIGH_OVERHEAD
	if relative_ball_height >= _PC.MEDIUM_OVERHEAD_TRIGGER_HEIGHT:
		return _player.PaddlePosture.MEDIUM_OVERHEAD
	return -1
