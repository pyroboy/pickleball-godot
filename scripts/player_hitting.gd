class_name PlayerHitting extends Node
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")
const PlaybackClock = preload("res://scripts/stroke_playback_clock.gd")
const Ramp = preload("res://scripts/stroke_speed_ramp.gd")
const SwingPath = preload("res://scripts/stroke_swing_path.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")


const PADDLE_CHARGE_BEHIND_OFFSET: = 0.42
const PADDLE_CHARGE_LIFT: = 0.1
const PADDLE_CHARGE_PULLBACK: = 0.24
const BODY_CHARGE_ROTATION_DEGREES: = 35.0
const PADDLE_FOLLOW_THROUGH_DEGREES: = 18.0
const PADDLE_BACKSWING_DEGREES: = 65.0
const SMASH_FORCE_BONUS: = 1.35
const SMASH_DOWNWARD_BIAS: = 0.22
const AI_HIT_COOLDOWN: = 0.16
const AI_CHARGE_DURATION: = 0.28
const AI_TRAJECTORY_DURATION: = 0.6





const PADDLE_VEL_SMOOTH_HALFLIFE: = 0.08
const PADDLE_VEL_TRANSFER: = 0.4
var _prev_paddle_pos: Vector3 = Vector3.ZERO
var _paddle_velocity: Vector3 = Vector3.ZERO


var charge_visual_active: bool = false
var serving_visual_active: bool = false
var _serve_release_start: PostureDefinition
var _serve_release_spin: int = 0
var is_in_follow_through: bool = false
var _ft_target_pos: Vector3 = Vector3.ZERO
var _ft_debug_timer: float = 0.0
var _ft_reached: bool = false
const FT_DEBUG_LOG: = false
var _ft_contact_pos: Vector3 = Vector3.ZERO
var _ft_peak_pos: Vector3 = Vector3.ZERO
var _ft_ghost_pos: Vector3 = Vector3.ZERO
var _ft_phase_times: Array = []
var paddle_swing_tween: Tween = null


var _player

func _ready() -> void :
	_player = get_parent() as CharacterBody3D


func _get_posture_def(posture_id: int):
	return PostureLibrary.instance().get_def(posture_id)


func _has_authored_follow_through(def) -> bool:
	if def == null:
		return false
	return def.ft_paddle_offset.length_squared() > 0.0001\
	or def.ft_paddle_rotation_deg.length_squared() > 0.0001


func _tween_transition_for_curve(curve: int) -> Tween.TransitionType:
	return PlaybackClock.transition_for_curve(curve)


func _authored_follow_through_data(posture_id: int, _charge_ratio: float) -> Dictionary:
	var def = _get_posture_def(posture_id)
	if not _has_authored_follow_through(def):
		return {}





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

func _process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_process(delta)
	PerfMonitor.record("proc.player_hitting", Time.get_ticks_usec() - _pt)

func _perf_process(delta: float) -> void:




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

			var phase: String = "?"
			var expected: Vector3 = _ft_target_pos
			if _ft_phase_times.size() == 4:
				if _ft_debug_timer <= _ft_phase_times[0]:
					phase = "STRIKE";expected = _ft_contact_pos
				elif _ft_debug_timer <= _ft_phase_times[1]:
					phase = "SWEEP";expected = _ft_peak_pos
				elif _ft_debug_timer <= _ft_phase_times[2]:
					phase = "SETTLE";expected = _ft_target_pos
				else:
					phase = "HOLD";expected = _ft_target_pos

			if not _ft_reached:
				_ft_reached = true
				if RuntimePolicy.developer_tools: print("[FT] START paddle=(%.2f,%.2f,%.2f) ghost=(%.2f,%.2f,%.2f)" % [
					pp.x, pp.y, pp.z, _ft_ghost_pos.x, _ft_ghost_pos.y, _ft_ghost_pos.z])
				if RuntimePolicy.developer_tools: print("[FT]   keyframes: contact=(%.2f,%.2f,%.2f) peak=(%.2f,%.2f,%.2f) final=(%.2f,%.2f,%.2f)" % [
					_ft_contact_pos.x, _ft_contact_pos.y, _ft_contact_pos.z, 
					_ft_peak_pos.x, _ft_peak_pos.y, _ft_peak_pos.z, 
					_ft_target_pos.x, _ft_target_pos.y, _ft_target_pos.z])
			elif fmod(_ft_debug_timer, 0.05) < delta:
				if RuntimePolicy.developer_tools: print("[FT] t=%.2f %s paddle=(%.2f,%.2f,%.2f) expect=(%.2f,%.2f,%.2f)" % [
					_ft_debug_timer, phase, pp.x, pp.y, pp.z, expected.x, expected.y, expected.z])
	elif FT_DEBUG_LOG and _ft_reached and not is_in_follow_through:
		if RuntimePolicy.developer_tools: print("[FT] END t=%.2f — tracking resumed" % _ft_debug_timer)
		_ft_reached = false





func _apply_hardcoded_charge(clamped_ratio: float, charge_pull_sign: float, forward_axis: Vector3) -> void :
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


	if _player.body_pivot and _player.paddle_posture != _player.PaddlePosture.CHARGE_BACKHAND:
		var body_rotation_sign: float = 0.0
		if _player.paddle_posture in _player.FOREHAND_POSTURES:
			body_rotation_sign = _player._get_swing_sign()
		elif _player.paddle_posture in _player.BACKHAND_POSTURES:
			body_rotation_sign = - _player._get_swing_sign()
		var target_y: float = deg_to_rad(BODY_CHARGE_ROTATION_DEGREES) * body_rotation_sign
		_player.body_pivot.rotation.y = lerpf(0.0, target_y, clamped_ratio)




func clear_charge_visual() -> void :
	_live_swing_presentation.clear()
	serving_visual_active = false
	committed_motion_context = {}
	stroke_contact_active = false
	_player.set_meta("legal_net_followthrough_flight", -1)
	_player.set_meta("legal_return_over_net_flight", -1)
	preload("res://scripts/rally_motion_context.gd").clear_feet(_player)
	_serve_release_start = null
	var had_swing: bool = charge_visual_active or is_in_follow_through
	if _player.posture and "human_contact" in _player.posture and _player.posture.human_contact:
		_player.posture.human_contact.cancel()
	charge_visual_active = false
	if had_swing and _player.posture and not ("editor_preview_mode" in _player.posture and _player.posture.editor_preview_mode):
		var human = _player.posture.human_contact if "human_contact" in _player.posture else null
		_player.posture.transition_pose_blend = human.visual_pose if human != null else null
	if paddle_swing_tween != null and paddle_swing_tween.is_valid():
		paddle_swing_tween.kill()


	is_in_follow_through = false


func set_serve_charge_visual(charge_ratio: float, control_delta: float = -1.0) -> void :
	_live_swing_presentation.clear()


	var game = _player.get_parent()
	if game and "game_serve" in game and game.game_serve and game.game_serve.is_charging() and game.game_state == game.GameState.WAITING:
		if game.serving_team == _player.player_num:
			if control_delta >= 0.0: game.game_serve.advance_held_visual(control_delta)
			set_underhand_serve_charge(charge_ratio)
		return
	serving_visual_active = false
	if _player.posture and "human_contact" in _player.posture and _player.posture.human_contact and _player.posture.human_contact.phase >= 1:
		return
	if not _player._ensure_paddle_ready():
		return

	if paddle_swing_tween != null and paddle_swing_tween.is_valid():
		paddle_swing_tween.kill()
		is_in_follow_through = false

	charge_visual_active = true
	var clamped_ratio: float = clamp(charge_ratio, 0.0, 1.0)
	if not _player.is_ai and "human_contact" in _player.posture and _player.posture.human_contact != null:
		var human = _player.posture.human_contact
		if game and "game_state" in game and game.game_state == game.GameState.PLAYING:



			human.set_charge(clamped_ratio, control_delta)
			return
	var charge_pull_sign: float = _player._get_posture_charge_sign()
	var forward_axis: Vector3 = _player._get_forward_axis()
	var swing_sign: float = _player._get_swing_sign()
	var current_def = PostureLibrary.instance().get_def(_player.paddle_posture)
	var context: Dictionary = _runtime_motion_context()
	var committed: Dictionary = committed_motion_context
	stroke_serial += 1
	stroke_contact_active = context.active
	if context.active:
		if _player.is_ai and "ai_desired_posture" in _player:
			current_def = _get_posture_def(_player.ai_desired_posture)
		if current_def:
			_apply_motion_pose(Motion.held_drive_pose(current_def, clamped_ratio, context.volley, context.spin, context.near))
			return
	if current_def and current_def.charge_paddle_offset.length_squared() > 0.0001:
		var windup: PostureDefinition = SwingPath.endpoint(current_def, 0)
		_player.posture.transition_pose_blend = current_def.lerp_with(windup, clamped_ratio)
		_player.posture.force_posture_update(_player.posture.transition_pose_blend)
		return


	_apply_hardcoded_charge(clamped_ratio, charge_pull_sign, forward_axis)


	if FT_DEBUG_LOG and not _player.is_ai and int(clamped_ratio * 100) % 20 == 0 and clamped_ratio > 0.0 and clamped_ratio < 1.0:
		var fam_c: String = "CENTER"
		var gk: int = _player.posture.FT_CENTER
		if _player.paddle_posture in _player.FOREHAND_POSTURES:
			fam_c = "FH";gk = _player.posture.FT_FOREHAND
		elif _player.paddle_posture in _player.BACKHAND_POSTURES:
			fam_c = "BH";gk = _player.posture.FT_BACKHAND
		elif _player.paddle_posture in [_player.PaddlePosture.MEDIUM_OVERHEAD, _player.PaddlePosture.HIGH_OVERHEAD]:
			fam_c = "OH";gk = _player.posture.FT_OVERHEAD
		var gp: Vector3 = Vector3.ZERO
		if _player.posture.ft_ghosts.has(gk):
			gp = _player.posture.ft_ghosts[gk].position

		var fwd_c: Vector3 = _player._get_forward_axis()
		var fh_c: Vector3 = _player._get_forehand_axis()
		var sgn_c: float = _player._get_posture_charge_sign()
		var ft_preview: Dictionary = _get_follow_through_offsets(clamped_ratio, fwd_c, fh_c, sgn_c, _player.paddle_posture)
		var ft_tgt: Vector3 = _player.paddle_rest_position + ft_preview["pos"]
		var pp_c: Vector3 = _player.paddle_node.position
		if RuntimePolicy.developer_tools: print("[CHARGE] %s %.0f%% paddle=(%.2f,%.2f,%.2f) ft_ghost=(%.2f,%.2f,%.2f) ft_anim=(%.2f,%.2f,%.2f)" % [
			fam_c, clamped_ratio * 100, 
			pp_c.x, pp_c.y, pp_c.z, 
			gp.x, gp.y, gp.z, 
			ft_tgt.x, ft_tgt.y, ft_tgt.z])







func _get_follow_through_offsets(ratio: float, fwd: Vector3, fh: Vector3, swing_sign: float, override_posture: int = -1) -> Dictionary:
	var posture: int = override_posture if override_posture >= 0 else _player.paddle_posture
	var pos: = Vector3.ZERO
	var rot: = Vector3.ZERO


	var def = _get_posture_def(posture)
	if _has_authored_follow_through(def):

		pos = def.ft_paddle_offset * ratio
		rot = def.ft_paddle_rotation_deg * ratio
		return {"pos": pos, "rot": rot}



	if posture in [_player.PaddlePosture.MEDIUM_OVERHEAD, _player.PaddlePosture.HIGH_OVERHEAD]:
		var is_high: bool = posture == _player.PaddlePosture.HIGH_OVERHEAD
		pos += fwd * (0.12 + 0.44 * ratio)
		pos.y -= 0.1 + 0.42 * ratio
		rot.x += (72.0 if is_high else 52.0) * ratio
		rot.z += 6.0 * ratio


	elif posture in _player.FOREHAND_POSTURES:
		pos += fwd * (0.14 + 0.28 * ratio)
		pos += fh * swing_sign * (0.18 + 0.36 * ratio)
		pos.y -= 0.06 + 0.16 * ratio
		rot.x += 20.0 * ratio
		rot.y += swing_sign * PADDLE_FOLLOW_THROUGH_DEGREES * (0.5 + ratio)
		rot.z -= 30.0 * ratio


	elif posture in _player.BACKHAND_POSTURES:
		pos += fwd * (0.14 + 0.28 * ratio)
		pos += fh * - swing_sign * (0.18 + 0.36 * ratio)
		pos.y -= 0.06 + 0.16 * ratio
		rot.x += 20.0 * ratio
		rot.y -= swing_sign * PADDLE_FOLLOW_THROUGH_DEGREES * (0.5 + ratio)
		rot.z += 30.0 * ratio


	else:
		pos += fwd * (0.14 + 0.3 * ratio)
		pos.y += 0.03 + 0.08 * ratio
		rot.x += 30.0 * ratio
		rot.z += 16.0 * ratio

	return {"pos": pos, "rot": rot}



func animate_serve_release(charge_ratio: float) -> void :
	if not _player._ensure_paddle_ready():
		return

	if paddle_swing_tween != null and paddle_swing_tween.is_valid():
		paddle_swing_tween.kill()
		is_in_follow_through = false


	var hit_posture: int = _player.paddle_posture
	charge_visual_active = false
	var clamped_ratio: float = clamp(charge_ratio, 0.0, 1.0)
	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	var follow_through_position: Vector3 = _player.paddle_rest_position
	var follow_through_rotation: Vector3 = _player.paddle_rest_rotation
	var release_sign: float = _player._get_posture_charge_sign()
	var authored_ft: = _authored_follow_through_data(hit_posture, clamped_ratio)
	if not authored_ft.is_empty():
		_animate_authored_swing(hit_posture, clamped_ratio)
		return


	var fam: String = "OVERHEAD"
	var ghost_key: int = _player.posture.FT_CENTER
	if not authored_ft.is_empty():
		follow_through_position = authored_ft["position"]
		follow_through_rotation = authored_ft["rotation"]
	else:

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


	var charge_pos: Vector3 = _player.paddle_node.position
	var charge_rot: Vector3 = _player.paddle_node.rotation_degrees

	if clamped_ratio < 1.0:
		follow_through_position = _player.paddle_rest_position.lerp(follow_through_position, clamped_ratio)



	var contact_pos: Vector3 = charge_pos.lerp(follow_through_position, 0.4)
	var contact_rot: Vector3 = charge_rot.lerp(follow_through_rotation, 0.35)
	contact_pos.y += 0.04 * clamped_ratio


	var overshoot: float = 0.15 * clamped_ratio
	var peak_dir: Vector3 = (follow_through_position - charge_pos).normalized()
	var peak_pos: Vector3 = follow_through_position + peak_dir * overshoot
	var peak_rot: Vector3 = follow_through_rotation * 1.12


	var t_strike: float = lerp(0.1, 0.08, clamped_ratio)
	var t_sweep: float = lerp(0.16, 0.2, clamped_ratio)
	var t_settle: float = lerp(0.12, 0.18, clamped_ratio)
	var t_hold: float = lerp(0.06, 0.2, clamped_ratio)
	var ft_curve: int = 0
	if not authored_ft.is_empty():
		t_strike = authored_ft["strike"]
		t_sweep = authored_ft["sweep"]
		t_settle = authored_ft["settle"]
		t_hold = authored_ft["hold"]
		ft_curve = authored_ft["curve"]
	var strike_trans: = _tween_transition_for_curve(ft_curve)
	var sweep_trans: = Tween.TRANS_QUAD if authored_ft.is_empty() else strike_trans
	var settle_trans: = Tween.TRANS_SINE if authored_ft.is_empty() else strike_trans


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


	paddle_swing_tween.tween_property(_player.paddle_node, "position", contact_pos, t_strike).set_trans(strike_trans).set_ease(Tween.EASE_OUT)
	paddle_swing_tween.parallel().tween_property(_player.paddle_node, "rotation_degrees", contact_rot, t_strike).set_trans(strike_trans).set_ease(Tween.EASE_OUT)
	if _player.body_pivot:
		paddle_swing_tween.parallel().tween_property(_player.body_pivot, "rotation:y", 0.0, t_strike).set_trans(strike_trans).set_ease(Tween.EASE_OUT)


	paddle_swing_tween.chain().tween_property(_player.paddle_node, "position", peak_pos, t_sweep).set_trans(sweep_trans).set_ease(Tween.EASE_OUT)
	paddle_swing_tween.parallel().tween_property(_player.paddle_node, "rotation_degrees", peak_rot, t_sweep).set_trans(sweep_trans).set_ease(Tween.EASE_OUT)


	paddle_swing_tween.chain().tween_property(_player.paddle_node, "position", follow_through_position, t_settle).set_trans(settle_trans).set_ease(Tween.EASE_IN_OUT)
	paddle_swing_tween.parallel().tween_property(_player.paddle_node, "rotation_degrees", follow_through_rotation, t_settle).set_trans(settle_trans).set_ease(Tween.EASE_IN_OUT)


	paddle_swing_tween.chain().tween_interval(t_hold)

	paddle_swing_tween.finished.connect(_on_paddle_release_finished)



func set_underhand_serve_charge(charge_ratio: float) -> void :
	if not _player._ensure_paddle_ready() or is_in_follow_through:
		return
	serving_visual_active = true
	charge_visual_active = true
	var game = _player.get_parent()
	var spin_mode: int = game.selected_spin_mode if game and "selected_spin_mode" in game else 0
	var pose: PostureDefinition = game.game_serve.get_preparation_pose(charge_ratio) if game and "game_serve" in game and game.game_serve else Motion.serve_preparation(charge_ratio, spin_mode)
	_apply_motion_pose(pose)


func begin_underhand_serve_release(charge_ratio: float, spin_mode: int = 0) -> void :
	_live_swing_presentation.clear()
	if paddle_swing_tween != null and paddle_swing_tween.is_valid(): paddle_swing_tween.kill()
	_serve_release_start = _player.posture.transition_pose_blend
	if _serve_release_start == null or not serving_visual_active:
		_serve_release_start = Motion.serve_preparation(charge_ratio, spin_mode)
	_serve_release_spin = spin_mode
	serving_visual_active = true
	charge_visual_active = false
	is_in_follow_through = true
	update_underhand_serve_strike(0.0)


func update_underhand_serve_strike(progress: float) -> void :
	if _serve_release_start == null: return
	var t: float = clampf(progress, 0.0, 1.0)


	var pose: PostureDefinition = Motion.serve_strike(_serve_release_start, t, _serve_release_spin)
	_apply_motion_pose(pose)


func _apply_motion_pose(pose: PostureDefinition) -> void :
	_player.posture.transition_pose_blend = pose
	_player.posture.force_posture_update(pose)


	if serving_visual_active and _player.leg_ik and _player.leg_ik.feet_initialized:
		_player.leg_ik._solve_legs(0.0, pose)




func _on_paddle_release_finished() -> void :



	var ready: PostureDefinition = _player.posture.transition_pose_blend if _player.posture else null
	if ready == null: ready = _get_posture_def(_player.PaddlePosture.READY)
	serving_visual_active = false
	committed_motion_context = {}
	stroke_contact_active = false
	_player.set_meta("legal_net_followthrough_flight", -1)
	_player.set_meta("legal_return_over_net_flight", -1)
	preload("res://scripts/rally_motion_context.gd").clear_feet(_player)
	_serve_release_start = null
	is_in_follow_through = false
	charge_visual_active = false
	if _player.is_ai and _player.ai_brain != null:
		_player.ai_brain.incoming_pose_override = ready
	if _player.posture:
		_player.posture.reset_incoming_highlight()
		_player.posture.transition_pose_blend = ready
		if ready: _player.posture.force_posture_update(ready)
		if _player.posture.human_contact != null:
			_player.posture.human_contact.visual_pose = ready
	_player.posture_lerp_initialized = true


var committed_motion_context: Dictionary = {}
var stroke_serial: int = 0
var stroke_contact_active: bool = false

func _runtime_motion_context() -> Dictionary:
	var ball = _player._get_ball_ref() if _player.has_method("_get_ball_ref") else null
	var game = _player.get_parent()
	return {"active": ball != null and ball.is_in_play, 
		"volley": ball != null and ball.bounces_since_last_hit == 0, 
		"near": "global_position" in _player and absf(_player.global_position.z) <= PickleballConstants.NON_VOLLEY_ZONE + 0.65, 
		"spin": game.selected_spin_mode if game and "selected_spin_mode" in game and not _player.is_ai else 0}


var _live_swing_presentation: Dictionary = {}
const RECOVERY_MAX_TICKS := 24   # physics ticks (0.8 s at 30 Hz) the ready-pose recovery may own the arm

func present_live_swing_physics(delta: float) -> bool:
	if _live_swing_presentation.is_empty() or not is_in_follow_through: return false
	var tick: int = Engine.get_physics_frames()
	if int(_live_swing_presentation.tick) == tick: return true
	_live_swing_presentation.tick = tick
	# Consume this physics step against the previously owned physical anchors
	# before forecasting a new hand frame. Subsequent solves use zero delta.
	_player.posture.transition_pose_blend = _live_swing_presentation.presented
	_player.posture.force_posture_update(_live_swing_presentation.presented)
	var pose: PostureDefinition = preload("res://scripts/live_joint_preparation_path.gd").sample(_player, _live_swing_presentation.desired, _live_swing_presentation.presented, delta)
	_live_swing_presentation.presented = pose
	_player.posture.transition_pose_blend = pose
	_player.posture.force_posture_update(pose)
	if bool(_live_swing_presentation.finish):
		# The recovery also ends when the arm has stopped moving or after
		# RECOVERY_MAX_TICKS. The joint path can settle a few centimetres short of
		# the ready pose (bench: every AI swing stalled 5.9 cm / 12 degrees off),
		# and waiting for an exact match kept the arm owned by the finished swing,
		# so the AI could not raise its paddle for its next ball in the rally.
		var head: Vector3 = preload("res://scripts/stroke_swing_path.gd").world_transform(_player, pose).origin - _player.global_position
		var previous_head: Vector3 = _live_swing_presentation.get("recovery_head", Vector3.INF)
		_live_swing_presentation["recovery_head"] = head
		_live_swing_presentation["recovery_ticks"] = int(_live_swing_presentation.get("recovery_ticks", 0)) + 1
		var stalled: bool = previous_head.is_finite() and previous_head.distance_to(head) < 0.0005
		if stalled or int(_live_swing_presentation.recovery_ticks) >= RECOVERY_MAX_TICKS or _live_recovery_converged(pose, _live_swing_presentation.desired):
			_live_swing_presentation.clear()
			_on_paddle_release_finished()
	return true

func begin_settled_recovery(charge_ratio: float, endpoint_pose: PostureDefinition) -> void:
	# Geometry is already sealed. Preserve all hand/support clocks and the
	# raw displayed rig; only next-frame recovery ownership changes here.
	if endpoint_pose == null or not _player.is_ai or not _runtime_motion_context().active: return
	if paddle_swing_tween != null and paddle_swing_tween.is_valid(): paddle_swing_tween.kill()
	_animate_authored_swing(endpoint_pose.posture_id, clampf(charge_ratio, 0.0, 1.0), endpoint_pose)

func _animate_authored_swing(posture_id: int, charge_ratio: float, settled_endpoint: PostureDefinition = null) -> void :
	var context: Dictionary = _runtime_motion_context()
	var committed: Dictionary = committed_motion_context
	stroke_serial += 1
	stroke_contact_active = context.active
	if settled_endpoint == null and context.active and _player.is_ai and "ai_desired_posture" in _player:
		var actual_contact: PostureDefinition = _player.posture.transition_pose_blend
		posture_id = actual_contact.posture_id if actual_contact != null and actual_contact.posture_id != _player.PaddlePosture.READY else _player.ai_desired_posture
	var def: PostureDefinition = _get_posture_def(posture_id).lerp_with(_get_posture_def(posture_id), 0.0)
	if settled_endpoint != null:
		def = settled_endpoint.duplicate(true)
	elif context.active and _player.is_ai:
		var accepted: PostureDefinition = _player.posture.transition_pose_blend
		if accepted != null and accepted.posture_id == posture_id:
			def = accepted.duplicate(false)
		else:
			def = load("res://scripts/incoming_contact_planner.gd").pose_at(_player, def, PaddleReach.head_world(_player))

	is_in_follow_through = true
	charge_visual_active = false
	_ft_debug_timer = 0.0
	_ft_phase_times.clear()
	paddle_swing_tween = _player.create_tween()
	if context.active and _player.is_ai: paddle_swing_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var joint_state: Dictionary = {"pose": def, "frame": Engine.get_physics_frames() if context.active and _player.is_ai else Engine.get_process_frames()}
	if context.active and _player.is_ai:
		_live_swing_presentation = {"desired": def, "presented": def if settled_endpoint == null else settled_endpoint, "finish": false, "tick": -1 if settled_endpoint == null else Engine.get_physics_frames()}
	var apply: = func(progress: float):
		var pose: PostureDefinition = Motion.sample_drive(def, progress, charge_ratio, context.volley, context.spin, context.near, str(committed.get("shot_intent", "AUTO")), committed) if context.active else def.lerp_with(SwingPath.sample(def, progress), charge_ratio)
		if context.active and _player.is_ai and (settled_endpoint != null or not is_equal_approx(progress, .5)):
			_live_swing_presentation.desired = pose
			return
		joint_state.pose = pose
		_player.posture.transition_pose_blend = pose
		_player.posture.force_posture_update(pose)

	var at_contact: bool = context.active and _player.is_ai
	if settled_endpoint == null: apply.call(0.5 if at_contact else 0.0)
	var transition: = _tween_transition_for_curve(def.ft_ease_curve)
	var easing: Tween.EaseType = PlaybackClock.ease_for_curve(def.ft_ease_curve)
	# Speed ramp (Pose Studio): a custom part runs on linear time through its own timing curve.
	if not at_contact:
		if Ramp.custom(def, Ramp.STRIKE): paddle_swing_tween.tween_method(func(x: float): apply.call(0.5 * Ramp.normalized(def, Ramp.STRIKE, x)), 0.0, 1.0, PlaybackClock.strike_duration(def))
		else: paddle_swing_tween.tween_method(apply, 0.0, 0.5, PlaybackClock.strike_duration(def)).set_trans(transition).set_ease(easing)
	if Ramp.custom(def, Ramp.FINISH): paddle_swing_tween.tween_method(func(x: float): apply.call(0.5 + 0.5 * Ramp.normalized(def, Ramp.FINISH, x)), 0.0, 1.0, PlaybackClock.sweep_duration(def))
	else: paddle_swing_tween.tween_method(apply, 0.5, 1.0, PlaybackClock.sweep_duration(def)).set_trans(transition).set_ease(easing)
	paddle_swing_tween.tween_callback(func(): stroke_contact_active = false)

	paddle_swing_tween.tween_interval(PlaybackClock.hold_duration(def))
	var finish: PostureDefinition = Motion.sample_drive(def, 1.0, charge_ratio, context.volley, context.spin, context.near, str(committed.get("shot_intent", "AUTO")), committed) if context.active else def.lerp_with(SwingPath.endpoint(def, 2), charge_ratio)
	var ready: PostureDefinition = _get_posture_def(_player.PaddlePosture.READY)
	if ready:
		# A committed recovery owns its target even if the paused editor saves READY.
		ready = ready.duplicate(true)
		var recovery_state: Dictionary = {"start": null}
		var recover: = func(factor: float):
			var grip = preload("res://scripts/grip_transition.gd")
			if recovery_state.start == null: recovery_state.start = _live_swing_presentation.presented if context.active and _player.is_ai else finish
			var start: PostureDefinition = recovery_state.start
			var pose: PostureDefinition = grip.sample(start, ready, factor) if grip.supports_both_joined(start, ready) else SwingPath.blend_pose(start, ready, factor)
			if context.active and _player.is_ai:
				_live_swing_presentation.desired = pose
				return
			_player.posture.transition_pose_blend = pose
			_player.posture.force_posture_update(pose)
		var joined_regrip: bool = preload("res://scripts/grip_transition.gd").supports_both_joined(finish, ready)
		var recovery_time: float = PlaybackClock.recovery_duration(def, finish, ready)
		paddle_swing_tween.tween_method(recover, 0.0, 1.0, recovery_time).set_trans(Tween.TRANS_LINEAR if joined_regrip else Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	paddle_swing_tween.finished.connect(func():
		if context.active and _player.is_ai: _live_swing_presentation.finish = true
		else: _on_paddle_release_finished())



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

	if not silent:
		var posture_name: String = _player.DEBUG_POSTURE_NAMES[_player.paddle_posture] if _player.paddle_posture < _player.DEBUG_POSTURE_NAMES.size() else "?"
		if RuntimePolicy.developer_tools: print("[HIT P", _player.player_num, "] ", posture_name, 
			" dist=", snapped(distance_to_ball, 0.01), 
			" ballY=", snapped(ball_height, 0.01), 
			" charge=", snapped(charge_clamped, 0.01), 
			" contact=", contact_name, 
			" popup=", snapped(popup_factor, 0.01))

	var dir: Vector3 = Vector3.ZERO
	if _player.player_num == 0:
		dir = Vector3((ball_position.x - _player.global_position.x) * 0.22, 0.12 + popup_factor, -1.0)
	else:

		var target_z: float = randf_range(2.0, 5.5)
		var dist_z: float = target_z - ball_position.z

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


	var charge_gain: float = lerpf(0.6, 1.25, charge_clamped)
	var base_impulse: Vector3 = dir.normalized() * _player.paddle_force * force_scale * charge_gain


	var body_vel_contribution: Vector3 = Vector3(0, _player.vertical_velocity * 0.3, 0)
	return base_impulse + body_vel_contribution

func _live_recovery_converged(presented: PostureDefinition, desired: PostureDefinition) -> bool:
	var path = preload("res://scripts/stroke_swing_path.gd")
	var a: Transform3D = path.world_transform(_player, presented)
	var b: Transform3D = path.world_transform(_player, desired)
	if a.origin.distance_to(b.origin) > .001 or a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion()) > .001: return false
	var support = _player.right_arm_node if desired.paddle_hand == 1 else _player.left_arm_node
	var state: Dictionary = support.get_meta("live_support_frame", {})
	if float(state.get("open_weight", 0.0)) > .001: return false
	if path._support_mode(desired) == 1:
		var expected: Basis = preload("res://scripts/paddle_grip_frame.gd").basis(b.basis, desired.paddle_hand == 0, desired.support_grip_rotation_deg - desired.paddle_in_hand_rotation_deg)
		if support.hand_mesh.global_basis.orthonormalized().get_rotation_quaternion().angle_to(expected.get_rotation_quaternion()) > .001: return false
	return true
