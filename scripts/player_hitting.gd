class_name PlayerHitting extends Node
## PlayerHitting — serve charge visuals, shot impulse, AI hitting & trajectory

const PADDLE_CHARGE_BEHIND_OFFSET := 0.42
const PADDLE_CHARGE_LIFT := 0.1
const PADDLE_CHARGE_PULLBACK := 0.24
const BODY_CHARGE_ROTATION_DEGREES := 35.0
const PADDLE_FOLLOW_THROUGH_DEGREES := 18.0
const PADDLE_BACKSWING_DEGREES := 65.0
const SMASH_FORCE_BONUS := 1.35
const SMASH_DOWNWARD_BIAS := 0.22
const AI_HIT_COOLDOWN := 0.16
const AI_CHARGE_DURATION := 0.28
const AI_TRAJECTORY_DURATION := 0.6
const _PL = preload("res://scripts/posture_library.gd")

# ── Paddle velocity tracking (GAP-X: animation → ball speed coupling) ─────────
# Tracks paddle world-space velocity so the kinetic chain's final velocity
# contributes to ball speed at impact. Without this, ball speed is purely a
# function of charge_ratio → MIN/MAX_SPEED table lookup (decoupled from physics).
const PADDLE_VEL_SMOOTH_HALFLIFE := 0.08   # EMA halflife — smooths jitter from IK solves
const PADDLE_VEL_TRANSFER := 0.40            # fraction of paddle velocity (in shot dir) added to ball speed
var _prev_paddle_pos: Vector3 = Vector3.ZERO
var _paddle_velocity: Vector3 = Vector3.ZERO  # raw per-frame delta

# ── Charge visual state ──────────────────────────────────────────────────────
var charge_visual_active: bool = false
var is_in_follow_through: bool = false
var _ft_target_pos: Vector3 = Vector3.ZERO
var _ft_debug_timer: float = 0.0
var _ft_reached: bool = false
const FT_DEBUG_LOG := false
var _ft_contact_pos: Vector3 = Vector3.ZERO
var _ft_peak_pos: Vector3 = Vector3.ZERO
var _ft_ghost_pos: Vector3 = Vector3.ZERO
var _ft_phase_times: Array = []  # [strike_end, sweep_end, settle_end, hold_end]
var paddle_swing_tween: Tween = null

# ── Parent reference ─────────────────────────────────────────────────────────
var _player

func _ready() -> void:
	_player = get_parent() as CharacterBody3D


func _get_posture_def(posture_id: int):
	return load("res://scripts/posture_library.gd").new().get_def(posture_id)


func _has_authored_follow_through(def) -> bool:
	if def == null:
		return false
	return def.ft_paddle_offset.length_squared() > 0.0001 \
		or def.ft_paddle_rotation_deg.length_squared() > 0.0001


func _tween_transition_for_curve(curve: int) -> Tween.TransitionType:
	match curve:
		1:
			return Tween.TRANS_QUAD
		2:
			return Tween.TRANS_SINE
		_:
			return Tween.TRANS_EXPO


func _authored_follow_through_data(posture_id: int, _charge_ratio: float) -> Dictionary:
	var def = _get_posture_def(posture_id)
	if not _has_authored_follow_through(def):
		return {}

	# Returns FULL FT endpoint (ratio=1.0). The animate_serve_release lerp
	# at line 325 applies clamped_ratio scaling — this matches the ghost path
	# where ghost_position is the full FT and lerp(ghost, clamped_ratio) = full * clamped_ratio.
	# Formerly we pre-scaled here AND lerped again = double-scaling (ft_dist = ratio²).
	var target_pos: Vector3 = _player.paddle_rest_position + def.ft_paddle_offset
	var target_rot: Vector3 = _player.paddle_rest_rotation + def.ft_paddle_rotation_deg
	return {
		"position": target_pos,
		"rotation": target_rot,
		"strike": maxf(0.01, def.ft_duration_strike),
		"sweep": maxf(0.01, def.ft_duration_sweep),
		"settle": maxf(0.01, def.ft_duration_settle),
		"hold": maxf(0.0, def.ft_duration_hold),
		"curve": def.ft_ease_curve,
	}

func snapped_v3(v: Vector3) -> String:
	return "(%s, %s, %s)" % [snapped(v.x, 0.01), snapped(v.y, 0.01), snapped(v.z, 0.01)]

func _process(delta: float) -> void:
	# ── Paddle velocity tracking ────────────────────────────────────────────────
	# Updated every frame (after IK solves, before rendering) so the velocity
	# reflects the true animated paddle motion. Smoothed to avoid jitter from
	# discrete IK solutions.
	if _player.paddle_node and delta > 0.0001:
		var current_pos: Vector3 = _player.paddle_node.global_position
		var raw_vel: Vector3 = (current_pos - _prev_paddle_pos) / delta
		_paddle_velocity = _player._damp_v3(_paddle_velocity, raw_vel, PADDLE_VEL_SMOOTH_HALFLIFE, delta)
		_prev_paddle_pos = current_pos
	elif _prev_paddle_pos == Vector3.ZERO and _player.paddle_node:
		_prev_paddle_pos = _player.paddle_node.global_position

	if FT_DEBUG_LOG and is_in_follow_through and _player.paddle_node and not _player.is_ai:
		_ft_debug_timer += delta
		if _ft_debug_timer < 1.0:
			var pp: Vector3 = _player.paddle_node.position
			# Determine current phase and expected target
			var phase: String = "?"
			var expected: Vector3 = _ft_target_pos
			if _ft_phase_times.size() == 4:
				if _ft_debug_timer <= _ft_phase_times[0]:
					phase = "STRIKE"; expected = _ft_contact_pos
				elif _ft_debug_timer <= _ft_phase_times[1]:
					phase = "SWEEP"; expected = _ft_peak_pos
				elif _ft_debug_timer <= _ft_phase_times[2]:
					phase = "SETTLE"; expected = _ft_target_pos
				else:
					phase = "HOLD"; expected = _ft_target_pos

			if not _ft_reached:
				_ft_reached = true
				print("[FT] START paddle=(%.2f,%.2f,%.2f) ghost=(%.2f,%.2f,%.2f)" % [
					pp.x, pp.y, pp.z, _ft_ghost_pos.x, _ft_ghost_pos.y, _ft_ghost_pos.z])
				print("[FT]   keyframes: contact=(%.2f,%.2f,%.2f) peak=(%.2f,%.2f,%.2f) final=(%.2f,%.2f,%.2f)" % [
					_ft_contact_pos.x, _ft_contact_pos.y, _ft_contact_pos.z,
					_ft_peak_pos.x, _ft_peak_pos.y, _ft_peak_pos.z,
					_ft_target_pos.x, _ft_target_pos.y, _ft_target_pos.z])
			elif fmod(_ft_debug_timer, 0.05) < delta:
				print("[FT] t=%.2f %s paddle=(%.2f,%.2f,%.2f) expect=(%.2f,%.2f,%.2f)" % [
					_ft_debug_timer, phase, pp.x, pp.y, pp.z, expected.x, expected.y, expected.z])
	elif FT_DEBUG_LOG and _ft_reached and not is_in_follow_through:
		print("[FT] END t=%.2f — tracking resumed" % _ft_debug_timer)
		_ft_reached = false

# ── Serve charge visual ─────────────────────────────────────────────────────

## Fallback for postures without authored charge_paddle_offset data.
## Preserves exact pre-refactor behavior so postures with zero charge data still work.
func _apply_hardcoded_charge(clamped_ratio: float, charge_pull_sign: float, forward_axis: Vector3) -> void:
	var charged_position: Vector3 = _player.paddle_rest_position
	var charged_rotation: Vector3 = _player.paddle_rest_rotation

	if _player.paddle_posture == _player.PaddlePosture.MEDIUM_OVERHEAD or _player.paddle_posture == _player.PaddlePosture.HIGH_OVERHEAD:
		charged_position -= forward_axis * (PADDLE_CHARGE_BEHIND_OFFSET * 0.45) * clamped_ratio
		if _player.paddle_posture == _player.PaddlePosture.HIGH_OVERHEAD:
			charged_position.y += (PADDLE_CHARGE_LIFT + 0.22) * clamped_ratio
			charged_rotation.x += -62.0 * clamped_ratio
		else:
			charged_position.y += (PADDLE_CHARGE_LIFT + 0.12) * clamped_ratio
			charged_rotation.x += -46.0 * clamped_ratio
		charged_rotation.z += -8.0 * clamped_ratio
	else:
		charged_position.x -= charge_pull_sign * PADDLE_CHARGE_PULLBACK * 0.35 * clamped_ratio
		charged_position.y += PADDLE_CHARGE_LIFT * 0.7 * clamped_ratio
		charged_rotation.x += -40.0 * clamped_ratio
		charged_rotation.z += -12.0 * clamped_ratio

	_player.paddle_node.position = charged_position
	_player.paddle_node.rotation_degrees = charged_rotation

	# Body rotation — CHARGE_BACKHAND handled by update_body_track_ball
	if _player.body_pivot and _player.paddle_posture != _player.PaddlePosture.CHARGE_BACKHAND:
		var body_rotation_sign: float = 0.0
		if _player.paddle_posture in _player.FOREHAND_POSTURES:
			body_rotation_sign = _player._get_swing_sign()
		elif _player.paddle_posture in _player.BACKHAND_POSTURES:
			body_rotation_sign = -_player._get_swing_sign()
		var target_y: float = deg_to_rad(BODY_CHARGE_ROTATION_DEGREES) * body_rotation_sign
		_player.body_pivot.rotation.y = lerpf(0.0, target_y, clamped_ratio)


func set_serve_charge_visual(charge_ratio: float) -> void:
	if not _player._ensure_paddle_ready():
		return

	if paddle_swing_tween != null and paddle_swing_tween.is_valid():
		paddle_swing_tween.kill()
		is_in_follow_through = false

	charge_visual_active = true
	var clamped_ratio: float = clamp(charge_ratio, 0.0, 1.0)
	var charge_pull_sign: float = _player._get_posture_charge_sign()
	var forward_axis: Vector3 = _player._get_forward_axis()
	var swing_sign: float = _player._get_swing_sign()
	var posture_lib = load("res://scripts/posture_library.gd").new()
	var current_def = posture_lib.get_def(_player.paddle_posture)

	# ── Per-posture authored charge data (new path) ────────────────────
	if current_def != null and current_def.charge_paddle_offset.length_squared() > 0.0001:
		# Use authored charge offset: paddle lerps from rest toward rest + charge_offset
		var charge_offset: Vector3 = current_def.charge_paddle_offset
		var charge_rot: Vector3 = current_def.charge_paddle_rotation_deg
		# Apply swing-sign to yaw if authored value uses swing_sign convention
		var signed_charge_rot: Vector3 = charge_rot
		if absf(charge_rot.y) > 0.001:
			signed_charge_rot.y = absf(charge_rot.y) * charge_pull_sign

		var start_pos: Vector3 = _player.paddle_rest_position
		var start_rot: Vector3 = _player.paddle_rest_rotation
		# Target = rest + authored offset (scaled by charge ratio)
		var charge_target_pos: Vector3 = start_pos + charge_offset * clamped_ratio
		_player.paddle_node.position = charge_target_pos
		_player.paddle_node.rotation_degrees = start_rot.lerp(signed_charge_rot, clamped_ratio)

		# Body rotation from authored data
		if _player.body_pivot and absf(current_def.charge_body_rotation_deg) > 0.001:
			var body_sign: float = 0.0
			if _player.paddle_posture in _player.FOREHAND_POSTURES:
				body_sign = swing_sign
			elif _player.paddle_posture in _player.BACKHAND_POSTURES:
				body_sign = -swing_sign
			elif _player.paddle_posture in [_player.PaddlePosture.MEDIUM_OVERHEAD, _player.PaddlePosture.HIGH_OVERHEAD]:
				body_sign = swing_sign
			var body_target: float = deg_to_rad(current_def.charge_body_rotation_deg) * body_sign
			_player.body_pivot.rotation.y = lerpf(0.0, body_target, clamped_ratio)

	# ── Fallback: hardcoded behavior for postures without authored data ──
	else:
		_apply_hardcoded_charge(clamped_ratio, charge_pull_sign, forward_axis)

	# Debug: log charge state, paddle pos, FT ghost pos, and FT target preview
	if FT_DEBUG_LOG and not _player.is_ai and int(clamped_ratio * 100) % 20 == 0 and clamped_ratio > 0.0 and clamped_ratio < 1.0:
		var fam_c: String = "CENTER"
		var gk: int = _player.posture.FT_CENTER
		if _player.paddle_posture in _player.FOREHAND_POSTURES:
			fam_c = "FH"; gk = _player.posture.FT_FOREHAND
		elif _player.paddle_posture in _player.BACKHAND_POSTURES:
			fam_c = "BH"; gk = _player.posture.FT_BACKHAND
		elif _player.paddle_posture in [_player.PaddlePosture.MEDIUM_OVERHEAD, _player.PaddlePosture.HIGH_OVERHEAD]:
			fam_c = "OH"; gk = _player.posture.FT_OVERHEAD
		var gp: Vector3 = Vector3.ZERO
		if _player.posture.ft_ghosts.has(gk):
			gp = _player.posture.ft_ghosts[gk].position
		# Preview where the FT animation will target
		var fwd_c: Vector3 = _player._get_forward_axis()
		var fh_c: Vector3 = _player._get_forehand_axis()
		var sgn_c: float = _player._get_posture_charge_sign()
		var ft_preview: Dictionary = _get_follow_through_offsets(clamped_ratio, fwd_c, fh_c, sgn_c, _player.paddle_posture)
		var ft_tgt: Vector3 = _player.paddle_rest_position + ft_preview["pos"]
		var pp_c: Vector3 = _player.paddle_node.position
		print("[CHARGE] %s %.0f%% paddle=(%.2f,%.2f,%.2f) ft_ghost=(%.2f,%.2f,%.2f) ft_anim=(%.2f,%.2f,%.2f)" % [
			fam_c, clamped_ratio * 100,
			pp_c.x, pp_c.y, pp_c.z,
			gp.x, gp.y, gp.z,
			ft_tgt.x, ft_tgt.y, ft_tgt.z])

	# Body rotation is handled inside the per-posture and fallback blocks above.

# ── Follow-through families ──────────────────────────────────────────────────
# 4 categories: FOREHAND, BACKHAND, CENTER, OVERHEAD
# charge_ratio (0.0–1.0) scales how far the paddle travels through the swing.

func _get_follow_through_offsets(ratio: float, fwd: Vector3, fh: Vector3, swing_sign: float, override_posture: int = -1) -> Dictionary:
	var posture: int = override_posture if override_posture >= 0 else _player.paddle_posture
	var pos := Vector3.ZERO
	var rot := Vector3.ZERO

	# ── Per-posture authored FT data ──────────────────────────────────
	var def = _get_posture_def(posture)
	if _has_authored_follow_through(def):
		# Authored offsets are FROM contact TO FT end — scale by ratio for intermediate positions
		pos = def.ft_paddle_offset * ratio
		rot = def.ft_paddle_rotation_deg * ratio
		return {"pos": pos, "rot": rot}

	# ── Fallback: hardcoded family-level formulas ──
	# OVERHEAD (MEDIUM_OVERHEAD, HIGH_OVERHEAD)
	if posture in [_player.PaddlePosture.MEDIUM_OVERHEAD, _player.PaddlePosture.HIGH_OVERHEAD]:
		var is_high: bool = posture == _player.PaddlePosture.HIGH_OVERHEAD
		pos += fwd * (0.12 + 0.44 * ratio)
		pos.y -= 0.10 + 0.42 * ratio
		rot.x += (72.0 if is_high else 52.0) * ratio
		rot.z += 6.0 * ratio

	# FOREHAND
	elif posture in _player.FOREHAND_POSTURES:
		pos += fwd * (0.14 + 0.28 * ratio)
		pos += fh * swing_sign * (0.18 + 0.36 * ratio)
		pos.y -= 0.06 + 0.16 * ratio
		rot.x += 20.0 * ratio
		rot.y += swing_sign * PADDLE_FOLLOW_THROUGH_DEGREES * (0.5 + ratio)
		rot.z -= 30.0 * ratio

	# BACKHAND
	elif posture in _player.BACKHAND_POSTURES:
		pos += fwd * (0.14 + 0.28 * ratio)
		pos += fh * -swing_sign * (0.18 + 0.36 * ratio)
		pos.y -= 0.06 + 0.16 * ratio
		rot.x += 20.0 * ratio
		rot.y -= swing_sign * PADDLE_FOLLOW_THROUGH_DEGREES * (0.5 + ratio)
		rot.z += 30.0 * ratio

	# CENTER
	else:
		pos += fwd * (0.14 + 0.30 * ratio)
		pos.y += 0.03 + 0.08 * ratio
		rot.x += 30.0 * ratio
		rot.z += 16.0 * ratio

	return {"pos": pos, "rot": rot}

# ── Serve release animation ──────────────────────────────────────────────────

func animate_serve_release(charge_ratio: float) -> void:
	if not _player._ensure_paddle_ready():
		return

	if paddle_swing_tween != null and paddle_swing_tween.is_valid():
		paddle_swing_tween.kill()
		is_in_follow_through = false

	# Capture posture NOW before charge_visual_active clears and tracking could overwrite
	var hit_posture: int = _player.paddle_posture
	charge_visual_active = false
	var clamped_ratio: float = clamp(charge_ratio, 0.0, 1.0)
	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	var follow_through_position: Vector3 = _player.paddle_rest_position
	var follow_through_rotation: Vector3 = _player.paddle_rest_rotation
	var release_sign: float = _player._get_posture_charge_sign()
	var authored_ft := _authored_follow_through_data(hit_posture, clamped_ratio)

	# Priority: authored per-posture FT data > ghosts (family fallback) > hardcoded formula
	var fam: String = "OVERHEAD"
	var ghost_key: int = _player.posture.FT_CENTER
	if not authored_ft.is_empty():
		follow_through_position = authored_ft["position"]
		follow_through_rotation = authored_ft["rotation"]
	else:
		# Fallback: ghost or hardcoded
		if hit_posture in _player.FOREHAND_POSTURES: fam = "FOREHAND"
		elif hit_posture in _player.BACKHAND_POSTURES: fam = "BACKHAND"
		elif hit_posture in _player.CENTER_POSTURES: fam = "CENTER"
		if fam == "FOREHAND": ghost_key = _player.posture.FT_FOREHAND
		elif fam == "BACKHAND": ghost_key = _player.posture.FT_BACKHAND
		elif fam == "OVERHEAD": ghost_key = _player.posture.FT_OVERHEAD
		if _player.posture.ft_ghosts.has(ghost_key):
			follow_through_position = _player.posture.ft_ghosts[ghost_key].position
		else:
			var ft: Dictionary = _get_follow_through_offsets(clamped_ratio, forward_axis, forehand_axis, release_sign, hit_posture)
			follow_through_position += ft["pos"]
			follow_through_rotation += ft["rot"]

	# Scale position toward ghost based on charge (weak hit = partial follow-through)
	var charge_pos: Vector3 = _player.paddle_node.position
	var charge_rot: Vector3 = _player.paddle_node.rotation_degrees
	# At partial charge, interpolate between rest and ghost position
	if clamped_ratio < 1.0:
		follow_through_position = _player.paddle_rest_position.lerp(follow_through_position, clamped_ratio)

	# Keyframe positions: charge → contact → peak follow-through → settle
	# Contact point: ~40% of the way to follow-through (ball strike moment)
	var contact_pos: Vector3 = charge_pos.lerp(follow_through_position, 0.4)
	var contact_rot: Vector3 = charge_rot.lerp(follow_through_rotation, 0.35)
	contact_pos.y += 0.04 * clamped_ratio

	# Peak follow-through: overshoot past target then settle back
	var overshoot: float = 0.15 * clamped_ratio
	var peak_dir: Vector3 = (follow_through_position - charge_pos).normalized()
	var peak_pos: Vector3 = follow_through_position + peak_dir * overshoot
	var peak_rot: Vector3 = follow_through_rotation * 1.12

	# Timing — longer durations so the swing arc is visible
	var t_strike: float = lerp(0.10, 0.08, clamped_ratio)    # charge → contact (explosive)
	var t_sweep: float = lerp(0.16, 0.20, clamped_ratio)     # contact → peak (the main arc)
	var t_settle: float = lerp(0.12, 0.18, clamped_ratio)    # peak → final (gentle ease)
	var t_hold: float = lerp(0.06, 0.20, clamped_ratio)      # hold at final position
	var ft_curve: int = 0
	if not authored_ft.is_empty():
		t_strike = authored_ft["strike"]
		t_sweep = authored_ft["sweep"]
		t_settle = authored_ft["settle"]
		t_hold = authored_ft["hold"]
		ft_curve = authored_ft["curve"]
	var strike_trans := _tween_transition_for_curve(ft_curve)
	var sweep_trans := Tween.TRANS_QUAD if authored_ft.is_empty() else strike_trans
	var settle_trans := Tween.TRANS_SINE if authored_ft.is_empty() else strike_trans

	# Debug: compare animation target vs ghost position
	if FT_DEBUG_LOG: print("[FT] %s charge=%.2f target=(%.2f,%.2f,%.2f) ghost=(%.2f,%.2f,%.2f)" % [
		fam, clamped_ratio,
		follow_through_position.x, follow_through_position.y, follow_through_position.z,
		_player.posture.ft_ghosts[ghost_key].position.x if _player.posture.ft_ghosts.has(ghost_key) else 0.0,
		_player.posture.ft_ghosts[ghost_key].position.y if _player.posture.ft_ghosts.has(ghost_key) else 0.0,
		_player.posture.ft_ghosts[ghost_key].position.z if _player.posture.ft_ghosts.has(ghost_key) else 0.0])

	_ft_target_pos = follow_through_position
	_ft_contact_pos = contact_pos
	_ft_peak_pos = peak_pos
	_ft_phase_times = [t_strike, t_strike + t_sweep, t_strike + t_sweep + t_settle, t_strike + t_sweep + t_settle + t_hold]
	_ft_ghost_pos = follow_through_position
	_ft_debug_timer = 0.0
	_ft_reached = false
	is_in_follow_through = true
	paddle_swing_tween = _player.create_tween()

	# Phase 1: Strike — explosive acceleration from charge to contact point
	paddle_swing_tween.tween_property(_player.paddle_node, "position", contact_pos, t_strike).set_trans(strike_trans).set_ease(Tween.EASE_OUT)
	paddle_swing_tween.parallel().tween_property(_player.paddle_node, "rotation_degrees", contact_rot, t_strike).set_trans(strike_trans).set_ease(Tween.EASE_OUT)
	if _player.body_pivot:
		paddle_swing_tween.parallel().tween_property(_player.body_pivot, "rotation:y", 0.0, t_strike).set_trans(strike_trans).set_ease(Tween.EASE_OUT)

	# Phase 2: Sweep — fast deceleration through to peak overshoot
	paddle_swing_tween.chain().tween_property(_player.paddle_node, "position", peak_pos, t_sweep).set_trans(sweep_trans).set_ease(Tween.EASE_OUT)
	paddle_swing_tween.parallel().tween_property(_player.paddle_node, "rotation_degrees", peak_rot, t_sweep).set_trans(sweep_trans).set_ease(Tween.EASE_OUT)

	# Phase 3: Settle — gentle ease back from overshoot to final follow-through
	paddle_swing_tween.chain().tween_property(_player.paddle_node, "position", follow_through_position, t_settle).set_trans(settle_trans).set_ease(Tween.EASE_IN_OUT)
	paddle_swing_tween.parallel().tween_property(_player.paddle_node, "rotation_degrees", follow_through_rotation, t_settle).set_trans(settle_trans).set_ease(Tween.EASE_IN_OUT)

	# Phase 4: Hold — let the follow-through pose read
	paddle_swing_tween.chain().tween_interval(t_hold)

	paddle_swing_tween.finished.connect(_on_paddle_release_finished)

# ── Paddle release callback ──────────────────────────────────────────────────

func _on_paddle_release_finished() -> void:
	is_in_follow_through = false
	charge_visual_active = false
	if _player.posture:
		_player.posture.reset_incoming_highlight()

	if _player.body_pivot:
		_player.body_pivot.rotation.y = 0.0

	# Reset to READY stance after any hit — posture module picks up active posture when ball returns
	_player.paddle_posture = _player.PaddlePosture.READY

	if _player.paddle_node != null:
		_player.posture_lerp_pos = _player.paddle_node.position
		_player.posture_lerp_initialized = true
		_player._update_paddle_tracking(true)

# ── Paddle position & shot impulse ───────────────────────────────────────────

func get_paddle_position() -> Vector3:
	if _player._ensure_paddle_ready():
		return _player.paddle_node.global_position
	return _player.global_position

func get_paddle_velocity() -> Vector3:
	return _paddle_velocity

func get_shot_impulse(ball_position: Vector3, charge_ratio: float = 0.5, silent: bool = false) -> Vector3:
	var paddle_pos: Vector3 = get_paddle_position()
	var distance_to_ball: float = paddle_pos.distance_to(ball_position)
	var ball_height: float = ball_position.y
	var charge_clamped: float = clamp(charge_ratio, 0.0, 1.0)
	var contact_state: int = _player._get_contact_state(distance_to_ball, ball_height, charge_clamped)
	var popup_factor: float = _player._get_popup_tendency(contact_state, distance_to_ball, ball_height, charge_clamped)
	var contact_name: String = ["CLEAN", "STRETCH", "POPUP"][contact_state]
	# Log popup error breakdown on every hit — DO NOT REMOVE
	if not silent:
		var posture_name: String = _player.DEBUG_POSTURE_NAMES[_player.paddle_posture] if _player.paddle_posture < _player.DEBUG_POSTURE_NAMES.size() else "?"
		print("[HIT P", _player.player_num, "] ", posture_name,
			" dist=", snapped(distance_to_ball, 0.01),
			" ballY=", snapped(ball_height, 0.01),
			" charge=", snapped(charge_clamped, 0.01),
			" contact=", contact_name,
			" popup=", snapped(popup_factor, 0.01))

	var dir: Vector3 = Vector3.ZERO
	if _player.player_num == 0:
		dir = Vector3((ball_position.x - _player.global_position.x) * 0.22, 0.12 + popup_factor, -1.0)
	else:
		# AI aims for a landing zone inside the opponent's court (Z between 2.0 and 5.5)
		var target_z: float = randf_range(2.0, 5.5)
		var dist_z: float = target_z - ball_position.z
		# More arc for longer distances — lob the ball over the net
		var arc: float = clamp(0.25 + dist_z * 0.04, 0.18, 0.55) + popup_factor
		var lateral: float = (ball_position.x - _player.global_position.x) * 0.22
		dir = Vector3(lateral, arc, 1.0)

	var force_scale: float = 1.0
	if contact_state == _player.ShotContactState.STRETCHED:
		force_scale = 0.8
	elif contact_state == _player.ShotContactState.POPUP:
		force_scale = 0.65

	if (_player.paddle_posture == _player.PaddlePosture.MEDIUM_OVERHEAD or _player.paddle_posture == _player.PaddlePosture.HIGH_OVERHEAD) and (_player.is_jumping or ball_height > _player.MEDIUM_OVERHEAD_TRIGGER_HEIGHT):
		dir.y = max(dir.y - SMASH_DOWNWARD_BIAS, -0.08)
		if _player.paddle_posture == _player.PaddlePosture.HIGH_OVERHEAD:
			force_scale *= SMASH_FORCE_BONUS
		else:
			force_scale *= 1.12

	# GAP-3: charge directly scales final impulse (half-charge 60%, full 125%)
	var charge_gain: float = lerpf(0.60, 1.25, charge_clamped)
	var base_impulse: Vector3 = dir.normalized() * _player.paddle_force * force_scale * charge_gain
	# GAP-28: add body vertical velocity (scaled for arm compliance). Makes
	# jumping smashes meatier and upward-rising contacts feel naturally lifted.
	var body_vel_contribution: Vector3 = Vector3(0, _player.vertical_velocity * 0.3, 0)
	return base_impulse + body_vel_contribution
