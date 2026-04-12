class_name PlayerLegIK extends Node

# === Gait constants ===
const STRIDE_FREQ_WALK := 5.0
const STRIDE_FREQ_RUN := 8.0
const STRIDE_LEN_WALK := 0.24
const STRIDE_LEN_RUN := 0.40
const STEP_TRIGGER_DIST := 0.18
const STEP_DURATION_WALK := 0.25
const STEP_DURATION_RUN := 0.14
const STEP_LIFT_HEIGHT := 0.06
const STEP_RUN_LIFT_HEIGHT := 0.10
const STEP_AHEAD_BASE := 0.06
const STEP_AHEAD_VEL_SCALE := 0.04
const MAX_STEP_DISTANCE := 1.20
const DOUBLE_SUPPORT_WALK := 0.08
const DOUBLE_SUPPORT_RUN := 0.02
const SUPPORT_COMPRESS_RATIO := 0.3
const ANKLE_TILT_MAX := 0.3
const FOOT_LOCK_HALFLIFE := 0.04
const FOOT_UNLOCK_RADIUS := 0.35
const FOOT_SMOOTH_HALFLIFE := 0.06
const FOOT_SMOOTH_MOVE_HALFLIFE := 0.05
const HIP_SHIFT_AMOUNT := 0.04
const HIP_SHIFT_HALFLIFE := 0.1
const COM_SWAY_RATIO := 0.6
const COM_SWAY_WAVELENGTH := 1.0
const SWING_ANTICIPATION_DIST := 4.0
const SWING_FOOT_OFFSET := 0.08

# Skeleton proportions
const COURT_FLOOR_Y := PickleballConstants.FLOOR_Y
const HIP_HEIGHT := -0.15
const THIGH_LENGTH := 0.52
const SHIN_LENGTH := 0.50

# Debug
const DEBUG_STEP_PLANNER := true

# === Step planner state ===
var right_step_origin: Vector3 = Vector3.ZERO
var right_step_target: Vector3 = Vector3.ZERO
var left_step_origin: Vector3 = Vector3.ZERO
var left_step_target: Vector3 = Vector3.ZERO
var right_step_t: float = 1.0
var left_step_t: float = 1.0
var step_foot: int = 0
var gait_arc_length: float = 0.0
var double_support_timer: float = 0.0
var dist_since_last_step: float = 0.0

# === Foot lock state ===
var right_foot_locked: bool = false
var left_foot_locked: bool = false
# GAP-40: the _lock_pos and _was_swing state vars below are now CONSUMED by
# the wired _apply_foot_lock call in update_legs (previously dead code).
var right_foot_lock_pos: Vector3 = Vector3.ZERO
var left_foot_lock_pos: Vector3 = Vector3.ZERO
var right_foot_smooth: Vector3 = Vector3.ZERO
var left_foot_smooth: Vector3 = Vector3.ZERO
var right_foot_was_swing: bool = false
var left_foot_was_swing: bool = false
var feet_initialized: bool = false

# === Hip sway state ===
var hip_shift: float = 0.0
var hip_shift_applied: Vector3 = Vector3.ZERO

# === Stance step animation (posture change triggers foot replant) ===
const STANCE_STEP_DURATION := 0.38
const STANCE_STEP_LIFT := 0.10
var stance_step_t: float = 1.0
var stance_step_origin: Vector3 = Vector3.ZERO
var stance_step_foot: int = 0  # 0=left, 1=right
var _prev_posture: int = -1
var _prev_posture_group: int = -1  # 0=center, 1=forehand, 2=backhand

# === Debug visualization ===
var _debug_frame_count: int = 0

# Parent player reference
var _player: PlayerController

func _ready() -> void:
	_player = get_parent() as CharacterBody3D

func update_leg_ik(delta: float) -> void:
	if not _player.right_leg_node or not _player.left_leg_node:
		return

	var fh_axis: Vector3 = _player._get_forehand_axis()
	var fwd_axis: Vector3 = _player._get_forward_axis()
	# Feet target the actual court floor surface
	var gnd_y: float = COURT_FLOOR_Y + 0.04

	# Velocity-based step offset — step targets placed ahead of movement
	var vel_flat: Vector3 = Vector3(_player.current_velocity.x, 0.0, _player.current_velocity.z)
	var speed: float = vel_flat.length()
	var speed_ratio: float = clampf(speed / _player.move_speed, 0.0, 1.0)

	var cur_posture: int = _player.paddle_posture
	var cur_group: int = 0  # 0=center
	if cur_posture in _player.BACKHAND_POSTURES:
		cur_group = 2
	elif cur_posture in _player.FOREHAND_POSTURES:
		cur_group = 1
	var group_changed: bool = cur_group != _prev_posture_group and _prev_posture_group != -1
	_prev_posture = cur_posture
	_prev_posture_group = cur_group

	# Rotate foot rest positions to match body pivot stance (backhand turn etc.)
	# Blend to world axes when running — step planner overrides anyway
	var body_yaw: float = _player.body_pivot.rotation.y if _player.body_pivot else 0.0
	var stance_blend: float = clampf(1.0 - speed_ratio * 1.5, 0.0, 1.0)
	var stance_yaw: float = -body_yaw * stance_blend
	var _cy: float = cos(stance_yaw)
	var _sy: float = sin(stance_yaw)
	var stance_fh: Vector3 = Vector3(fh_axis.x * _cy - fh_axis.z * _sy, 0.0, fh_axis.x * _sy + fh_axis.z * _cy)
	var stance_fwd: Vector3 = Vector3(fwd_axis.x * _cy - fwd_axis.z * _sy, 0.0, fwd_axis.x * _sy + fwd_axis.z * _cy)

	var step_ahead: Vector3 = Vector3.ZERO
	if speed > 0.1:
		# Velocity-proportional prediction: foot aims where body will be, not where it is
		var step_predict: float = STEP_AHEAD_BASE + speed * STEP_AHEAD_VEL_SCALE
		step_ahead = vel_flat.normalized() * step_predict

	# --- Swing anticipation: bias stance when ball is committed-incoming ---
	# GAP-44: was distance-gated (ball_dist < 4.0m). Now gated on posture
	# commit stage (PURPLE or BLUE) so the stance shift fires when the
	# system believes a shot is actually coming, not just because the ball
	# happens to be close. Falls back to distance if no posture module.
	var swing_bias: Vector3 = Vector3.ZERO
	var anticipation: float = 0.0
	if _player.posture and _player.posture._last_commit_stage >= 1:
		# PURPLE (1) or BLUE (2). Scale with stage: PURPLE=0.7, BLUE=1.0.
		anticipation = 0.7 if _player.posture._last_commit_stage == 1 else 1.0
	elif _player.ball_ref and is_instance_valid(_player.ball_ref):
		# Fallback: old distance-based gate for non-committed early warning.
		var ball_dist: float = _player.global_position.distance_to(_player.ball_ref.global_position)
		if ball_dist < SWING_ANTICIPATION_DIST and ball_dist > 0.5:
			anticipation = (1.0 - ball_dist / SWING_ANTICIPATION_DIST) * 0.5  # weaker than committed
	if anticipation > 0.0:
		# Forehand: dominant foot steps back, non-dominant forward. Backhand: opposite.
		if _player.paddle_posture in _player.BACKHAND_POSTURES:
			swing_bias = stance_fwd * SWING_FOOT_OFFSET * anticipation
		else:
			swing_bias = -stance_fwd * SWING_FOOT_OFFSET * anticipation

	# Base foot positions — stance widens with speed, lead foot predicts movement direction
	var base: Vector3 = Vector3(_player.global_position.x, gnd_y, _player.global_position.z)
	var lateral_half_idle: float = 0.14  # narrow at rest
	var lateral_half_move: float = 0.28  # wide when moving — prevents feet crossing
	var lateral_half: float = lerpf(lateral_half_idle, lateral_half_move, speed_ratio)

	var right_lateral_half: float = lateral_half
	var left_lateral_half: float = lateral_half
	var right_back_offset: float = 0.0
	var left_back_offset: float = 0.0
	var t: float = 1.0 - speed_ratio  # full effect at idle, fades when running

	if cur_posture == _player.PaddlePosture.CHARGE_BACKHAND:
		left_lateral_half = lerpf(lateral_half, 0.52, t)
		right_lateral_half = lerpf(lateral_half, 0.30, t)
		left_back_offset = lerpf(0.0, -0.38, t)
	elif cur_posture == _player.PaddlePosture.CHARGE_FOREHAND:
		right_lateral_half = lerpf(lateral_half, 0.52, t)
		left_lateral_half = lerpf(lateral_half, 0.30, t)
		right_back_offset = lerpf(0.0, -0.38, t)
	elif cur_group == 2:  # backhand postures
		left_lateral_half = lerpf(lateral_half, 0.38, t)
		right_lateral_half = lerpf(lateral_half, 0.22, t)
		left_back_offset = lerpf(0.0, -0.20, t)
	elif cur_group == 1:  # forehand postures
		right_lateral_half = lerpf(lateral_half, 0.38, t)
		left_lateral_half = lerpf(lateral_half, 0.22, t)
		right_back_offset = lerpf(0.0, -0.20, t)
	elif cur_group == 0:  # center/forward postures
		right_lateral_half = lerpf(lateral_half, 0.24, t)
		left_lateral_half = lerpf(lateral_half, 0.24, t)

	var right_rest: Vector3 = base + stance_fh * right_lateral_half + stance_fwd * (-0.06 + right_back_offset) + step_ahead + swing_bias
	var left_rest: Vector3 = base + stance_fh * -left_lateral_half + stance_fwd * (0.06 + left_back_offset) + step_ahead - swing_bias

	var pdef_feet: PostureDefinition = _player.get_runtime_posture_def()
	if pdef_feet:
		var dr := Vector3.ZERO
		var dl := Vector3.ZERO
		if pdef_feet.lead_foot == 0:
			dr += stance_fwd * pdef_feet.front_foot_forward
			dl += stance_fwd * pdef_feet.back_foot_back
		else:
			dl += stance_fwd * pdef_feet.front_foot_forward
			dr += stance_fwd * pdef_feet.back_foot_back
		dr += PostureSkeletonApplier.stance_offset(pdef_feet.right_foot_offset, stance_fh, stance_fwd)
		dl += PostureSkeletonApplier.stance_offset(pdef_feet.left_foot_offset, stance_fh, stance_fwd)
		var half_excess: float = (pdef_feet.stance_width - 0.35) * 0.5
		dr += stance_fh * half_excess
		dl -= stance_fh * half_excess
		var y_r: float = dr.y
		dr = Vector3(dr.x, 0, dr.z).rotated(Vector3.UP, deg_to_rad(pdef_feet.right_foot_yaw_deg)) + Vector3(0, y_r, 0)
		var y_l: float = dl.y
		dl = Vector3(dl.x, 0, dl.z).rotated(Vector3.UP, deg_to_rad(pdef_feet.left_foot_yaw_deg)) + Vector3(0, y_l, 0)
		right_rest += dr
		left_rest += dl

	var right_animated: Vector3 = right_rest
	var left_animated: Vector3 = left_rest
	var r_is_swing: bool = false
	var l_is_swing: bool = false

	# Initialize step planner positions on first frame
	if not feet_initialized:
		right_step_target = right_rest
		left_step_target = left_rest
		right_step_origin = right_rest
		left_step_origin = left_rest

	if speed > 0.1:
		var move_dir: Vector3 = vel_flat.normalized()
		var stride_len: float = lerpf(STRIDE_LEN_WALK, STRIDE_LEN_RUN, speed_ratio)
		var step_duration: float = lerpf(STEP_DURATION_WALK, STEP_DURATION_RUN, speed_ratio)
		var lift_height: float = lerpf(STEP_LIFT_HEIGHT, STEP_RUN_LIFT_HEIGHT, speed_ratio)

		# Lateral shuffle: reduce lift for sideways movement
		var lateral_ratio: float = absf(move_dir.dot(fh_axis))
		if lateral_ratio > 0.5:
			lift_height *= lerpf(1.0, 0.35, clampf((lateral_ratio - 0.5) / 0.5, 0.0, 1.0))

		# === FOOTSTEP PLANNING (robotics-style) ===
		# foot_target = body_projected + (W/2) × normal × side_sign
		#
		# Key insight: project ahead by speed × step_duration (where body WILL be
		# when the foot lands), NOT by stride_len (which is a distance constant).

		# Project far ahead: swing foot lands where body will be AFTER the next full stride
		var predict_time: float = step_duration + stride_len / maxf(speed, 0.5) + step_duration
		var body_projected: Vector3 = base + move_dir * speed * predict_time

		# Normal vector: perpendicular to movement direction on XZ plane
		var step_move_normal: Vector3 = Vector3(-move_dir.z, 0.0, move_dir.x)

		# Desired landing positions: straddle the projected body position
		var right_desired: Vector3 = body_projected + step_move_normal * lateral_half
		right_desired.y = gnd_y
		var left_desired: Vector3 = body_projected - step_move_normal * lateral_half
		left_desired.y = gnd_y

		# === ODOMETER: track distance traveled since last step ===
		dist_since_last_step += speed * delta

		# === DOUBLE-SUPPORT TIMER ===
		if double_support_timer > 0.0:
			double_support_timer -= delta

		# === STEP TRIGGERING ===
		# First step triggers at half stride (immediate response), subsequent at full stride
		var ds_ready: bool = double_support_timer <= 0.0
		var other_planted: bool
		var first_step: bool = right_step_t >= 1.0 and left_step_t >= 1.0  # both planted = no steps taken yet
		var trigger_stride: float = stride_len * (0.15 if first_step else 1.0)
		var should_step: bool = dist_since_last_step >= trigger_stride and ds_ready

		# Emergency: force step if any planted foot is too far from body (prevents leg stretch)
		var max_reach: float = (THIGH_LENGTH + SHIN_LENGTH) * 0.75  # 75% of full leg extension
		var body_xz: Vector3 = Vector3(_player.global_position.x, gnd_y, _player.global_position.z)
		var r_body_gap: float = Vector3(right_animated.x, gnd_y, right_animated.z).distance_to(body_xz)
		var l_body_gap: float = Vector3(left_animated.x, gnd_y, left_animated.z).distance_to(body_xz)
		var emergency_step: bool = false

		if right_step_t >= 1.0 and r_body_gap > max_reach and left_step_t >= 1.0:
			# Right foot is overextended — force it to step
			should_step = true
			step_foot = 0
			emergency_step = true
		elif left_step_t >= 1.0 and l_body_gap > max_reach and right_step_t >= 1.0:
			should_step = true
			step_foot = 1
			emergency_step = true

		if should_step:
			if step_foot == 0:
				other_planted = left_step_t >= 1.0
				if right_step_t >= 1.0 and (other_planted or emergency_step):
					right_step_origin = Vector3(right_animated.x, gnd_y, right_animated.z)
					var raw_target: Vector3 = right_desired
					var step_vec: Vector3 = raw_target - right_step_origin
					if step_vec.length() > MAX_STEP_DISTANCE:
						raw_target = right_step_origin + step_vec.normalized() * MAX_STEP_DISTANCE
					right_step_target = raw_target
					right_step_t = 0.0
					step_foot = 1
					dist_since_last_step = 0.0
					double_support_timer = 0.0 if emergency_step else lerpf(DOUBLE_SUPPORT_WALK, DOUBLE_SUPPORT_RUN, speed_ratio)
			else:
				other_planted = right_step_t >= 1.0
				if left_step_t >= 1.0 and (other_planted or emergency_step):
					left_step_origin = Vector3(left_animated.x, gnd_y, left_animated.z)
					var raw_target: Vector3 = left_desired
					var step_vec: Vector3 = raw_target - left_step_origin
					if step_vec.length() > MAX_STEP_DISTANCE:
						raw_target = left_step_origin + step_vec.normalized() * MAX_STEP_DISTANCE
					left_step_target = raw_target
					left_step_t = 0.0
					step_foot = 0
					dist_since_last_step = 0.0
					double_support_timer = 0.0 if emergency_step else lerpf(DOUBLE_SUPPORT_WALK, DOUBLE_SUPPORT_RUN, speed_ratio)

		# === SWING PROGRESS (fixed duration — no distance scaling) ===
		# At high speed, steps must complete in constant time to keep cadence.
		if right_step_t < 1.0:
			right_step_t = minf(right_step_t + delta / step_duration, 1.0)
		if left_step_t < 1.0:
			left_step_t = minf(left_step_t + delta / step_duration, 1.0)

		# === FOOT INTERPOLATION ===
		# Horizontal: smoothstep from origin → target
		var r_t: float = right_step_t * right_step_t * (3.0 - 2.0 * right_step_t)
		var l_t: float = left_step_t * left_step_t * (3.0 - 2.0 * left_step_t)

		if right_step_t < 1.0:
			right_animated = right_step_origin.lerp(right_step_target, r_t)
		else:
			# Planted: locked to ground (natural — body walks past it)
			right_animated = right_step_target

		if left_step_t < 1.0:
			left_animated = left_step_origin.lerp(left_step_target, l_t)
		else:
			left_animated = left_step_target

		# === LEG REACH CLAMP: never let foot exceed max leg length from body ===
		var max_leg: float = (THIGH_LENGTH + SHIN_LENGTH) * 0.85
		var body_ground: Vector3 = Vector3(_player.global_position.x, gnd_y, _player.global_position.z)
		var r_to_body: Vector3 = Vector3(right_animated.x, gnd_y, right_animated.z) - body_ground
		if r_to_body.length() > max_leg:
			var clamped: Vector3 = body_ground + r_to_body.normalized() * max_leg
			right_animated.x = clamped.x
			right_animated.z = clamped.z
			# Also update step_target so it doesn't drift back out
			if right_step_t >= 1.0:
				right_step_target = right_animated
		var l_to_body: Vector3 = Vector3(left_animated.x, gnd_y, left_animated.z) - body_ground
		if l_to_body.length() > max_leg:
			var clamped: Vector3 = body_ground + l_to_body.normalized() * max_leg
			left_animated.x = clamped.x
			left_animated.z = clamped.z
			if left_step_t >= 1.0:
				left_step_target = left_animated

		# Vertical: parabolic arc z(t) = 4·H·t·(1-t)
		var r_arc: float = 4.0 * right_step_t * (1.0 - right_step_t) if right_step_t < 1.0 else 0.0
		var l_arc: float = 4.0 * left_step_t * (1.0 - left_step_t) if left_step_t < 1.0 else 0.0
		right_animated.y += r_arc * lift_height
		left_animated.y += l_arc * lift_height

		r_is_swing = right_step_t < 1.0
		l_is_swing = left_step_t < 1.0

		# Enforce minimum lateral separation — prevent feet crossing
		var feet_vec: Vector3 = right_animated - left_animated
		var feet_lateral: float = feet_vec.dot(step_move_normal)
		var min_gap: float = lateral_half * 0.8
		if feet_lateral < min_gap:
			var push: float = (min_gap - feet_lateral) * 0.5
			right_animated += step_move_normal * push
			left_animated -= step_move_normal * push

		# Support leg spring compression
		if not r_is_swing and l_is_swing:
			right_animated.y -= l_arc * lift_height * SUPPORT_COMPRESS_RATIO
		elif not l_is_swing and r_is_swing:
			left_animated.y -= r_arc * lift_height * SUPPORT_COMPRESS_RATIO
	else:
		# Idle: reset step planner and return feet to rest
		gait_arc_length = 0.0
		double_support_timer = 0.0
		dist_since_last_step = 0.0
		right_step_target = right_rest
		left_step_target = left_rest
		right_step_origin = right_rest
		left_step_origin = left_rest
		right_step_t = 1.0
		left_step_t = 1.0
		right_animated = right_rest

		# Posture group change: animate dominant foot stepping to new stance
		if group_changed:
			stance_step_t = 0.0
			if cur_group == 2:  # backhand — left foot is dominant
				stance_step_foot = 0
				stance_step_origin = left_foot_smooth
			elif cur_group == 1:  # forehand — right foot is dominant
				stance_step_foot = 1
				stance_step_origin = right_foot_smooth
			else:  # center — left foot steps
				stance_step_foot = 0
				stance_step_origin = left_foot_smooth

		if stance_step_t < 1.0:
			stance_step_t = minf(stance_step_t + delta / STANCE_STEP_DURATION, 1.0)
			var ct: float = stance_step_t * stance_step_t * (3.0 - 2.0 * stance_step_t)
			var arc_y: float = 4.0 * stance_step_t * (1.0 - stance_step_t) * STANCE_STEP_LIFT
			if stance_step_foot == 0:
				left_animated = stance_step_origin.lerp(left_rest, ct)
				left_animated.y += arc_y
			else:
				right_animated = stance_step_origin.lerp(right_rest, ct)
				right_animated.y += arc_y
		else:
			left_animated = left_rest

	var right_foot: Vector3 = right_animated
	var left_foot: Vector3 = left_animated

	# --- CoM lateral sway (sinusoidal perturbation from Argo reference) ---
	# Body sways toward support foot during single-support phase
	_player.body_pivot.position -= hip_shift_applied  # undo previous frame
	if speed > 0.1:
		var _stride_len_local: float = lerpf(STRIDE_LEN_WALK, STRIDE_LEN_RUN, speed_ratio)
		gait_arc_length += speed * delta
		var sway_wavelength: float = COM_SWAY_WAVELENGTH  # matches Argo reference lambda=1.0
		var sway_amplitude: float = lateral_half * COM_SWAY_RATIO
		var sway: float = sin(TAU * gait_arc_length / sway_wavelength) * sway_amplitude * speed_ratio
		var target_shift: float = sway
		hip_shift = _player._damp(hip_shift, target_shift, HIP_SHIFT_HALFLIFE, delta)
	else:
		gait_arc_length = 0.0
		var idle_shift_target: float = 0.0
		var pdef_shift: PostureDefinition = _player.get_runtime_posture_def()
		if pdef_shift:
			idle_shift_target = pdef_shift.weight_shift * 0.12
		hip_shift = _player._damp(hip_shift, idle_shift_target, HIP_SHIFT_HALFLIFE, delta)

	var _feet_mid: Vector3 = (right_foot + left_foot) * 0.5
	var center_offset: Vector3 = Vector3.ZERO  # body follows physics, feet follow body

	var move_normal: Vector3 = Vector3.ZERO
	if speed > 0.1:
		var md: Vector3 = vel_flat.normalized()
		move_normal = Vector3(-md.z, 0.0, md.x)
	else:
		move_normal = fh_axis

	var shift_vec: Vector3 = move_normal * hip_shift + center_offset
	hip_shift_applied = Vector3(shift_vec.x, 0.0, shift_vec.z)
	_player.body_pivot.position += hip_shift_applied

	# GAP-40: wire the previously-dead _apply_foot_lock. Keeps the planted foot
	# stationary in world space while the other foot is in swing phase — the
	# "stance continuity" behavior that prevents foot drift during steps.
	var r_lock_result: Array = _apply_foot_lock(right_foot, r_is_swing, right_foot_was_swing, right_foot_locked, right_foot_lock_pos, delta)
	right_foot = r_lock_result[0]
	right_foot_locked = r_lock_result[1]
	right_foot_lock_pos = r_lock_result[2]
	right_foot_was_swing = r_is_swing
	var l_lock_result: Array = _apply_foot_lock(left_foot, l_is_swing, left_foot_was_swing, left_foot_locked, left_foot_lock_pos, delta)
	left_foot = l_lock_result[0]
	left_foot_locked = l_lock_result[1]
	left_foot_lock_pos = l_lock_result[2]
	left_foot_was_swing = l_is_swing

	# Pole vectors: knees bend forward (posture overrides when non-zero)
	var right_pole: Vector3 = right_foot + stance_fwd * 1.0 + Vector3(0, 0.5, 0)
	var left_pole: Vector3 = left_foot + stance_fwd * 1.0 + Vector3(0, 0.5, 0)
	var pdef_pole: PostureDefinition = _player.get_runtime_posture_def()
	if pdef_pole:
		if pdef_pole.right_knee_pole.length_squared() > 1e-10:
			right_pole = right_foot + PostureSkeletonApplier.stance_offset(pdef_pole.right_knee_pole, stance_fh, stance_fwd)
		if pdef_pole.left_knee_pole.length_squared() > 1e-10:
			left_pole = left_foot + PostureSkeletonApplier.stance_offset(pdef_pole.left_knee_pole, stance_fh, stance_fwd)

	# --- Smooth foot positions (always on — faster during movement, slower at idle) ---
	if not feet_initialized:
		right_foot_smooth = right_foot
		left_foot_smooth = left_foot
		feet_initialized = true
	else:
		var hl: float = FOOT_SMOOTH_MOVE_HALFLIFE if speed > 0.1 else FOOT_SMOOTH_HALFLIFE
		right_foot_smooth = _player._damp_v3(right_foot_smooth, right_foot, hl, delta)
		left_foot_smooth = _player._damp_v3(left_foot_smooth, left_foot, hl, delta)

	# Ankle tilt from step progress: toe-off at start, heel-strike at end
	var r_tilt: float = (1.0 - right_step_t * 2.0) * speed_ratio if right_step_t < 1.0 else 0.0
	var l_tilt: float = (1.0 - left_step_t * 2.0) * speed_ratio if left_step_t < 1.0 else 0.0

	if _player.right_leg_node.has_method("solve_ik"):
		_player.right_leg_node.solve_ik(right_foot_smooth, right_pole, r_tilt)
	if _player.left_leg_node.has_method("solve_ik"):
		_player.left_leg_node.solve_ik(left_foot_smooth, left_pole, l_tilt)

	# --- Debug: console log ~1/sec ---
	_debug_frame_count += 1
	if DEBUG_STEP_PLANNER and _debug_frame_count % 120 == 0 and speed > 0.1:
		var _fps: float = Engine.get_frames_per_second()
		var r_dist: float = right_step_origin.distance_to(right_step_target)
		var l_dist: float = left_step_origin.distance_to(left_step_target)
		var feet_gap: float = right_foot_smooth.distance_to(left_foot_smooth)
		var _r_drift_log: float = right_step_target.distance_to(right_rest + vel_flat.normalized() * lerpf(STRIDE_LEN_WALK, STRIDE_LEN_RUN, speed_ratio) * 0.5) if speed > 0.1 else 0.0
		print("[STEP P%d] R:%s L:%s gap=%.2f body=(%.1f,%.1f) spd=%.1f" % [
			_player.player_num,
			"SW%.2f" % r_dist if r_is_swing else "PL",
			"SW%.2f" % l_dist if l_is_swing else "PL",
			feet_gap,
			_player.global_position.x, _player.global_position.z,
			speed])

	# --- Debug: visualize step targets ---
	_player._draw_step_debug(right_step_target, left_step_target, right_step_origin, left_step_origin, r_is_swing, l_is_swing)

## Locks a foot in world space during the planted phase, releases during swing.
func _apply_foot_lock(
	animated_pos: Vector3, is_swing: bool, was_swing: bool,
	locked: bool, lock_pos: Vector3, delta: float
) -> Array:
	var foot_target: Vector3

	if is_swing:
		locked = false
		foot_target = animated_pos
	else:
		if was_swing and not is_swing:
			locked = true
			lock_pos = animated_pos

		if locked:
			var drift: float = Vector3(lock_pos.x - animated_pos.x, 0, lock_pos.z - animated_pos.z).length()
			if drift > FOOT_UNLOCK_RADIUS:
				locked = false
				foot_target = animated_pos
			else:
				foot_target = _player._damp_v3(animated_pos, lock_pos, FOOT_LOCK_HALFLIFE, delta)
		else:
			foot_target = animated_pos

	return [foot_target, locked, lock_pos]

func get_feet_gap() -> float:
	return Vector3(right_foot_smooth.x, 0, right_foot_smooth.z).distance_to(
		Vector3(left_foot_smooth.x, 0, left_foot_smooth.z))
