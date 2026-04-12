class_name PlayerAIBrain extends Node
## PlayerAIBrain — AI prediction, intercept, and hitting logic extracted from player.gd

# ── AI constants ──────────────────────────────────────────────────────────────
const AI_RECEIVE_X_TOLERANCE := 0.25
const AI_RECEIVE_Z_TOLERANCE := 0.20
const AI_LANDING_PREDICTION_STEP := 0.08
const AI_LANDING_PREDICTION_STEPS := 14  # Mobile: reduced from 28
const AI_CONTACT_PREDICTION_STEP := 0.06
const AI_CONTACT_PREDICTION_STEPS := 44
const AI_INTERCEPT_MARKER_MIN_HEIGHT := 0.28
const AI_INTERCEPT_MARKER_MAX_HEIGHT := 1.45
const AI_RECEIVE_BEHIND_BOUNCE_OFFSET := 0.32
const AI_WEAK_SERVE_SPEED_THRESHOLD := 7.2
const AI_STRONG_SERVE_SPEED_THRESHOLD := 11.2
const AI_WEAK_SERVE_FORWARD_BIAS := 0.55
const AI_STRONG_SERVE_BACK_BIAS := 0.7
const AI_FOREHAND_PREFERENCE := 1.00          # top priority at normal heights
const AI_FORWARD_PREFERENCE := 0.78           # slightly boosted
const AI_BACKHAND_PREFERENCE := 0.55          # slightly boosted for variety
const AI_OVERHEAD_PREFERENCE := 0.92          # demoted below forehand; only wins at true overhead
const AI_LOW_FOREHAND_PREFERENCE := 0.95      # near-top at low heights
const AI_LOW_FORWARD_PREFERENCE := 0.70       # boosted
const AI_LOW_BACKHAND_PREFERENCE := 0.45      # boosted
const AI_WIDE_FOREHAND_PREFERENCE := 0.62
const AI_WIDE_BACKHAND_PREFERENCE := 0.28
const AI_VOLLEY_READY_PREFERENCE := 0.70      # used more aggressively at net
const AI_MID_LOW_FOREHAND_PREFERENCE := 0.90  # strong at knee/shin height
const AI_MID_LOW_BACKHAND_PREFERENCE := 0.45  # boosted
const AI_MID_LOW_FORWARD_PREFERENCE := 0.65   # boosted
const AI_MID_LOW_WIDE_FOREHAND_PREFERENCE := 0.48
const AI_MID_LOW_WIDE_BACKHAND_PREFERENCE := 0.20
const AI_LOW_WIDE_FOREHAND_PREFERENCE := 0.60
const AI_LOW_WIDE_BACKHAND_PREFERENCE := 0.22
const AI_INTERCEPT_BODY_BACK_OFFSET := 0.28
const AI_INTERCEPT_PADDLE_CLEARANCE := 0.12
const AI_INTERCEPT_BODY_LATERAL_WEIGHT := 0.2
const MEDIUM_OVERHEAD_TRIGGER_HEIGHT := 1.05  # ~1.125m actual — shoulder height, not waist
const HIGH_OVERHEAD_TRIGGER_HEIGHT := 1.40   # ~1.475m actual — clearly above head
const OVERHEAD_TRIGGER_RADIUS := 1.7
const OVERHEAD_RELEASE_HEIGHT := 0.62
const OVERHEAD_RELEASE_RADIUS := 2.0
const JUMP_VELOCITY := PickleballConstants.JUMP_VELOCITY
const JUMP_GRAVITY := PickleballConstants.JUMP_GRAVITY
const SMASH_FORCE_BONUS := 1.35
const SMASH_DOWNWARD_BIAS := 0.22
const AI_MARKER_HEIGHT := 0.09
const AI_MARKER_SMOOTHING := 0.08
const AI_POST_BOUNCE_MARKER_SMOOTHING := 0.12
const AI_TARGET_RECOMMIT_DISTANCE := 0.55
const AI_TARGET_RECOMMIT_BOUNCE_DISTANCE := 0.55
const AI_TARGET_POST_BOUNCE_RECOMMIT_DISTANCE := 0.45
const AI_RECEIVE_MARKER_LANE_OFFSET := 0.16
const AI_RECEIVE_MARKER_BOUNCE_PULL := 0.72
const AI_HIT_REACH_DISTANCE := 1.1
const AI_HIT_COOLDOWN := 0.16
const AI_HIT_CONTACT_WINDOW := 0.34
const AI_CHARGE_DURATION := 0.32        # balanced — AI can hit medium shots but not always max power
const AI_CHARGE_START_DISTANCE := 2.4   # start charging earlier to beat fast serves
const AI_TRAJECTORY_DURATION := 0.6
const COURT_FLOOR_Y := PickleballConstants.FLOOR_Y

# ── AI state ──────────────────────────────────────────────────────────────────
enum AIState {
	INTERCEPT_POSITION,
	CHARGING,
	HIT_BALL,
}

var ai_state: int = PlayerController.AIState.INTERCEPT_POSITION
var ai_desired_posture: int = 0  # PlayerController.PaddlePosture.FOREHAND
var ai_target_position: Vector3 = Vector3.ZERO
var ai_predicted_bounce_position: Vector3 = Vector3.ZERO
var ai_predicted_contact_position: Vector3 = Vector3.ZERO

# GAP-47: visuomotor latency ring buffer. The AI "sees" ball state from N
# physics frames ago, matching human sensorimotor delay (~180-220 ms). Without
# this, the AI reacts to trajectory changes the same frame they happen, which
# is superhuman and asymmetric vs. the human player. Tunable per difficulty.
var _ball_history: Array = []
const REACTION_LATENCY_FRAMES_EASY := 18   # 300 ms at 60 Hz
const REACTION_LATENCY_FRAMES_MED := 12    # 200 ms at 60 Hz
const REACTION_LATENCY_FRAMES_HARD := 8    # 133 ms at 60 Hz
var ai_committed_target_position: Vector3 = Vector3.ZERO
var ai_committed_bounce_position: Vector3 = Vector3.ZERO
var ai_committed_contact_position: Vector3 = Vector3.ZERO
var ai_hit_cooldown: float = 0.0
var ai_charge_time: float = 0.0
var ai_is_charging: bool = false
var ai_swing_threshold: float = 0.20
var ai_difficulty: int = 0  # 0=Easy, 1=Medium, 2=Hard — set by game.gd via X key
var ai_ball_bounced_on_side: bool = false
var _game_node: Node = null  # set by game.gd for compute_shot_velocity access
var ai_trajectory_mesh_instance: MeshInstance3D = null
# Cache for prediction optimization
var _last_ball_pos_cached: Vector3 = Vector3.INF
var _last_ball_vel_cached: Vector3 = Vector3.INF
var _prediction_cache_valid: bool = false
var _cached_predicted_bounce: Vector3 = Vector3.ZERO
var _cached_contact_candidates: Array[Vector3] = []
var ai_trajectory_mesh: ImmediateMesh = null
var ai_trajectory_material: StandardMaterial3D = null
var ai_trajectory_timer: float = 0.0
var ai_movement_enabled: bool = true
var _ai_debug_frame: int = 0
var _ai_last_state: int = -1

# AI indicator position tracking (smoothed positions, NOT node refs)
var ai_target_indicator_position: Vector3 = Vector3.ZERO
var ai_bounce_indicator_position: Vector3 = Vector3.ZERO
var ai_contact_indicator_position: Vector3 = Vector3.ZERO

# Human intercept pool data — used by AI to decide positioning
var human_committed_pre_intercepts: Array[Vector3] = []
var human_committed_post_intercepts: Array[Vector3] = []
var human_committed_contact_position: Vector3 = Vector3.ZERO
var human_committed_target_position: Vector3 = Vector3.ZERO
var human_last_hit_by_seen: int = -1
var human_last_ball_vel_sign: float = 0.0

var _player: PlayerController  # set in _ready

func _ready() -> void:
	_player = get_parent() as CharacterBody3D

# ── Main AI input ─────────────────────────────────────────────────────────────
func get_ai_input() -> Vector3:
	var input_dir: Vector3 = Vector3.ZERO

	var ball: RigidBody3D = _player._get_ball_ref()

	if ball == null:
		return input_dir

	# GAP-47: update the perception ring buffer once per AI tick. All predictors
	# called below this line will use the delayed snapshot via _perceived_ball_*.
	_sample_ball_history(ball)

	var _ball_pos: Vector3 = ball.global_position
	var my_pos: Vector3 = _player.global_position
	var target_x: float = my_pos.x
	var target_z: float = my_pos.z

	# After AI hits, return to ready position (center of its side) instead of chasing
	if ball.has_method("get_last_hit_by") and ball.get_last_hit_by() == _player.player_num:
		var ready_z: float = (_player.min_z + _player.max_z) * 0.6  # slightly behind center
		var ready_x: float = 0.0
		target_x = ready_x
		target_z = ready_z
		_commit_ai_target_position(Vector3(target_x, _player.ground_y, target_z))
		ai_predicted_contact_position = Vector3(ready_x, _player.ground_y + 0.5, ready_z)
		var ready_x_tol: float = 0.4
		var ready_z_tol: float = 0.4
		if my_pos.x > target_x + ready_x_tol:
			input_dir.x = -1
		elif my_pos.x < target_x - ready_x_tol:
			input_dir.x = 1
		if my_pos.z > target_z + ready_z_tol:
			input_dir.z = -1
		elif my_pos.z < target_z - ready_z_tol:
			input_dir.z = 1
		return input_dir

	var predicted_landing: Vector3 = _predict_first_bounce_position(ball)
	_commit_ai_bounce_prediction(predicted_landing)
	var proactive_contact_point: Vector3 = _predict_ai_contact_point(ball)
	var intercept_marker_point: Vector3 = _predict_ai_intercept_marker_point(ball)
	_commit_ai_contact_prediction(intercept_marker_point)
	var intercept_solution: Dictionary = _get_ai_intercept_solution(proactive_contact_point)
	var intercept_target: Vector3 = intercept_solution["target"] as Vector3
	ai_desired_posture = int(intercept_solution["posture"])
	if intercept_solution.has("contact"):
		ai_predicted_contact_position = intercept_solution["contact"]

	# --- Smart positioning from intercept pool dots ---
	# Before two-bounce rule: go to RETURN (post-bounce) dot for legal play
	# After two-bounce rule: prioritize VOLLEY/SMASH (pre-bounce) dots for aggression
	if _player.is_ai and not human_committed_post_intercepts.is_empty() and not human_committed_pre_intercepts.is_empty():
		var two_bounce_done: bool = ball.both_bounces_complete
		if not two_bounce_done:
			# Must let ball bounce — go to the RETURN position (first post-bounce dot)
			var return_pt = human_committed_post_intercepts[0]
			var body_offset = _player._get_posture_offset_for(ai_desired_posture)
			intercept_target = Vector3(return_pt.x - body_offset.x, _player.ground_y, return_pt.z - body_offset.z)
			ai_predicted_contact_position = return_pt
		else:
			# Two-bounce rule cleared — aggressively intercept pre-bounce (volley/smash)
			if not human_committed_pre_intercepts.is_empty():
				# Prefer highest tier: smash > semi-smash > volley (last element = highest)
				var best_pre = human_committed_pre_intercepts[human_committed_pre_intercepts.size() - 1]
				var body_offset = _player._get_posture_offset_for(ai_desired_posture)
				intercept_target = Vector3(best_pre.x - body_offset.x, _player.ground_y, best_pre.z - body_offset.z)
				ai_predicted_contact_position = best_pre

	# Clamp intercept target to court bounds so AI never chases out-of-bounds predictions
	intercept_target.x = clamp(intercept_target.x, _player.min_x, _player.max_x)
	intercept_target.z = clamp(intercept_target.z, _player.min_z, _player.max_z)

	var paddle_target_position: Vector3 = intercept_target + _player._get_posture_offset_for(ai_desired_posture)

	# AI debug log — DO NOT REMOVE: needed for gameplay debugging
	# Throttled: prints on state change or ~1/sec
	var _state_changed: bool = ai_state != _ai_last_state
	_ai_debug_frame += 1
	if _state_changed or _ai_debug_frame >= 120:
		_ai_debug_frame = 0
		_ai_last_state = ai_state
		var _posture_name: String = _player.DEBUG_POSTURE_NAMES[ai_desired_posture] if ai_desired_posture < _player.DEBUG_POSTURE_NAMES.size() else "??"
		var _state_name: String = ["INTERCEPT", "CHARGING", "HIT"][ai_state] if ai_state < 3 else "??"
		print("[AI] %s %s | bodyZ=%.1f ballZ=%.1f tgtZ=%.1f p2b=%.1f ballY=%.2f bnc=%s bos=%s chg=%s" % [
			_state_name, _posture_name, my_pos.z, ball.global_position.z,
			intercept_target.z, my_pos.distance_to(ball.global_position),
			ball.global_position.y, ball.ball_bounced_since_last_hit,
			ai_ball_bounced_on_side, ai_is_charging])

	# Don't override CHARGING state — AI is committed to swinging
	if ai_state != PlayerController.AIState.CHARGING:
		if paddle_target_position.distance_to(proactive_contact_point) <= 0.5:
			ai_state = PlayerController.AIState.HIT_BALL
		else:
			ai_state = PlayerController.AIState.INTERCEPT_POSITION
	target_x = intercept_target.x
	target_z = intercept_target.z
	_commit_ai_target_position(Vector3(target_x, _player.ground_y, target_z))
	ai_target_position = ai_committed_target_position
	ai_predicted_bounce_position = ai_committed_bounce_position
	ai_predicted_contact_position = ai_committed_contact_position
	target_x = ai_committed_target_position.x
	target_z = ai_committed_target_position.z

	# When charging, use tighter deadzone and don't oscillate
	var x_tol: float = AI_RECEIVE_X_TOLERANCE
	var z_tol: float = AI_RECEIVE_Z_TOLERANCE
	if ai_state == PlayerController.AIState.CHARGING:
		x_tol = 0.06
		z_tol = 0.06

	if my_pos.x > target_x + x_tol:
		input_dir.x = -1
	elif my_pos.x < target_x - x_tol:
		input_dir.x = 1

	if my_pos.z > target_z + z_tol:
		input_dir.z = -1
	elif my_pos.z < target_z - z_tol:
		input_dir.z = 1

	return input_dir

# ── Posture height mapping ────────────────────────────────────────────────────
func _get_posture_for_height(rel_height: float) -> Array[int]:
	# rel_height = contact_point.y - COURT_FLOOR_Y (0.075).
	# Typical rally ball heights: 0.4–1.8 m above floor.
	# Thresholds match _update_paddle_tracking (also floor-relative now).
	if rel_height >= HIGH_OVERHEAD_TRIGGER_HEIGHT:
		return [PlayerController.PaddlePosture.HIGH_OVERHEAD, PlayerController.PaddlePosture.MEDIUM_OVERHEAD]
	elif rel_height >= MEDIUM_OVERHEAD_TRIGGER_HEIGHT:
		return [PlayerController.PaddlePosture.MEDIUM_OVERHEAD, PlayerController.PaddlePosture.HIGH_OVERHEAD, PlayerController.PaddlePosture.FORWARD]
	elif rel_height >= 0.55:
		# Normal height (hip and above) — full lateral coverage
		return [
			PlayerController.PaddlePosture.FOREHAND, PlayerController.PaddlePosture.FORWARD, PlayerController.PaddlePosture.BACKHAND,
			PlayerController.PaddlePosture.WIDE_FOREHAND, PlayerController.PaddlePosture.WIDE_BACKHAND,
			PlayerController.PaddlePosture.VOLLEY_READY,
		]
	elif rel_height >= 0.22:
		# Mid-low / knee height (0.22–0.55 m above floor)
		return [
			PlayerController.PaddlePosture.MID_LOW_FOREHAND, PlayerController.PaddlePosture.MID_LOW_BACKHAND,
			PlayerController.PaddlePosture.MID_LOW_FORWARD,
			PlayerController.PaddlePosture.MID_LOW_WIDE_FOREHAND, PlayerController.PaddlePosture.MID_LOW_WIDE_BACKHAND,
			PlayerController.PaddlePosture.FOREHAND, PlayerController.PaddlePosture.BACKHAND,  # fallback for borderline
		]
	else:
		# Low / ankle height (< 0.22 m above floor — just after bounce)
		return [
			PlayerController.PaddlePosture.LOW_FOREHAND, PlayerController.PaddlePosture.LOW_BACKHAND, PlayerController.PaddlePosture.LOW_FORWARD,
			PlayerController.PaddlePosture.LOW_WIDE_FOREHAND, PlayerController.PaddlePosture.LOW_WIDE_BACKHAND,
			PlayerController.PaddlePosture.MID_LOW_FOREHAND, PlayerController.PaddlePosture.MID_LOW_BACKHAND,  # fallback
		]

# ── Intercept solution ────────────────────────────────────────────────────────
func _get_ai_intercept_solution(predicted_ball_pos: Vector3) -> Dictionary:
	var ball: RigidBody3D = _player._get_ball_ref()
	var contact_candidates: Array[Vector3] = [predicted_ball_pos]
	if ball != null:
		contact_candidates = _predict_ai_contact_candidates(ball)

	var best_target: Vector3 = _player.global_position
	var best_score: float = INF
	var best_posture: int = PlayerController.PaddlePosture.FOREHAND
	var best_contact: Vector3 = predicted_ball_pos

	for contact_point in contact_candidates:
		var rel_height: float = contact_point.y - COURT_FLOOR_Y  # from floor, not player origin
		var height_postures: Array[int] = _get_posture_for_height(rel_height)
		for posture in height_postures:
			var posture_offset: Vector3 = _player._get_posture_offset_for(posture)
			var candidate_target: Vector3 = contact_point - posture_offset
			candidate_target.y = _player.ground_y

			var reposition_cost: float = _player.global_position.distance_to(candidate_target)
			var posture_preference: float = _get_ai_posture_preference(posture)
			var paddle_world_pos: Vector3 = candidate_target + posture_offset
			var paddle_error: float = paddle_world_pos.distance_to(contact_point) * 2.1
			var body_cost: float = candidate_target.distance_to(contact_point) * 0.24
			var score: float = reposition_cost + paddle_error + body_cost - posture_preference
			if score < best_score:
				best_score = score
				best_target = candidate_target
				best_posture = posture
				best_contact = contact_point

	return {
		"target": best_target,
		"posture": best_posture,
		"contact": best_contact,
	}

# ── Posture preference ────────────────────────────────────────────────────────
func _get_ai_posture_preference(posture: int) -> float:
	match posture:
		PlayerController.PaddlePosture.FOREHAND:              return AI_FOREHAND_PREFERENCE
		PlayerController.PaddlePosture.FORWARD:               return AI_FORWARD_PREFERENCE
		PlayerController.PaddlePosture.BACKHAND:              return AI_BACKHAND_PREFERENCE
		PlayerController.PaddlePosture.MEDIUM_OVERHEAD:       return AI_OVERHEAD_PREFERENCE
		PlayerController.PaddlePosture.HIGH_OVERHEAD:         return AI_OVERHEAD_PREFERENCE
		PlayerController.PaddlePosture.LOW_FOREHAND:          return AI_LOW_FOREHAND_PREFERENCE
		PlayerController.PaddlePosture.LOW_FORWARD:           return AI_LOW_FORWARD_PREFERENCE
		PlayerController.PaddlePosture.LOW_BACKHAND:          return AI_LOW_BACKHAND_PREFERENCE
		PlayerController.PaddlePosture.WIDE_FOREHAND:         return AI_WIDE_FOREHAND_PREFERENCE
		PlayerController.PaddlePosture.WIDE_BACKHAND:         return AI_WIDE_BACKHAND_PREFERENCE
		PlayerController.PaddlePosture.VOLLEY_READY:          return AI_VOLLEY_READY_PREFERENCE
		PlayerController.PaddlePosture.MID_LOW_FOREHAND:      return AI_MID_LOW_FOREHAND_PREFERENCE
		PlayerController.PaddlePosture.MID_LOW_BACKHAND:      return AI_MID_LOW_BACKHAND_PREFERENCE
		PlayerController.PaddlePosture.MID_LOW_FORWARD:       return AI_MID_LOW_FORWARD_PREFERENCE
		PlayerController.PaddlePosture.MID_LOW_WIDE_FOREHAND: return AI_MID_LOW_WIDE_FOREHAND_PREFERENCE
		PlayerController.PaddlePosture.MID_LOW_WIDE_BACKHAND: return AI_MID_LOW_WIDE_BACKHAND_PREFERENCE
		PlayerController.PaddlePosture.LOW_WIDE_FOREHAND:     return AI_LOW_WIDE_FOREHAND_PREFERENCE
		PlayerController.PaddlePosture.LOW_WIDE_BACKHAND:     return AI_LOW_WIDE_BACKHAND_PREFERENCE
		PlayerController.PaddlePosture.READY:
			return 0.50  # neutral ready-position — valid transition posture
		PlayerController.PaddlePosture.CHARGE_FOREHAND, PlayerController.PaddlePosture.CHARGE_BACKHAND:
			return 0.0  # AI shouldn't auto-select charge postures
	return 0.30  # safe fallback — neutral, low priority

# ── Prediction functions ──────────────────────────────────────────────────────
## GAP-47 helpers: visuomotor latency ring buffer + perceived-state accessors.
## `_sample_ball_history` is called once per AI update (at the top of `get_ai_input`)
## so every predictor in this frame reads the same delayed snapshot.
func _get_latency_frames() -> int:
	match ai_difficulty:
		0: return REACTION_LATENCY_FRAMES_EASY
		2: return REACTION_LATENCY_FRAMES_HARD
		_: return REACTION_LATENCY_FRAMES_MED

func _sample_ball_history(ball: RigidBody3D) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	
	# Use fixed-size ring buffer to avoid O(n) pop_front()
	var max_frames: int = _get_latency_frames() + 2
	
	# Grow array only if not at max size (avoid recreating every frame)
	if _ball_history.size() < max_frames:
		_ball_history.append({
			"pos": ball.global_position,
			"vel": ball.linear_velocity,
			"omega": ball.angular_velocity,
		})
	else:
		# Ring buffer: shift elements manually (cheaper than pop_front when full)
		for i in range(max_frames - 1):
			_ball_history[i] = _ball_history[i + 1]
		_ball_history[max_frames - 1] = {
			"pos": ball.global_position,
			"vel": ball.linear_velocity,
			"omega": ball.angular_velocity,
		}

func _perceived_ball_pos(ball: RigidBody3D) -> Vector3:
	# Guard against empty array - return live state as fallback
	if _ball_history.is_empty() or ball == null:
		return ball.global_position if ball else Vector3.ZERO
	if _ball_history.size() >= _get_latency_frames() and _ball_history.size() > 0:
		return _ball_history[0]["pos"]
	return ball.global_position  # buffer warming up, use live state

func _perceived_ball_vel(ball: RigidBody3D) -> Vector3:
	if _ball_history.is_empty() or ball == null:
		return ball.linear_velocity if ball else Vector3.ZERO
	if _ball_history.size() >= _get_latency_frames() and _ball_history.size() > 0:
		return _ball_history[0]["vel"]
	return ball.linear_velocity

func _perceived_ball_omega(ball: RigidBody3D) -> Vector3:
	if _ball_history.is_empty() or ball == null:
		return ball.angular_velocity if ball else Vector3.ZERO
	if _ball_history.size() >= _get_latency_frames() and _ball_history.size() > 0:
		return _ball_history[0]["omega"]
	return ball.angular_velocity

func _predict_first_bounce_position(ball: RigidBody3D) -> Vector3:
	# Use cached result if ball state hasn't changed significantly
	var perceived_pos: Vector3 = _perceived_ball_pos(ball)
	var perceived_vel: Vector3 = _perceived_ball_vel(ball)
	var _cache_key: String = "%v_%v" % [perceived_pos, perceived_vel]
	
	if _prediction_cache_valid and _last_ball_pos_cached == perceived_pos and _last_ball_vel_cached == perceived_vel:
		return _cached_predicted_bounce
	
	# Invalidate cache if ball state changed significantly
	if _last_ball_pos_cached != Vector3.INF and perceived_pos.distance_squared_to(_last_ball_pos_cached) > 0.01:
		_prediction_cache_valid = false
	
	_last_ball_pos_cached = perceived_pos
	_last_ball_vel_cached = perceived_vel
	
	var gravity: float = Ball.get_effective_gravity()
	var predicted_position: Vector3 = perceived_pos
	var predicted_velocity: Vector3 = perceived_vel
	var predicted_omega: Vector3 = _perceived_ball_omega(ball)
	var floor_height: float = 0.08

	for _step in range(AI_LANDING_PREDICTION_STEPS):
		var stepped: Array = Ball.predict_aero_step(
			predicted_position, predicted_velocity, predicted_omega,
			gravity, AI_LANDING_PREDICTION_STEP
		)
		predicted_position = stepped[0]
		predicted_velocity = stepped[1]
		predicted_omega = stepped[2]
		if predicted_position.y <= floor_height:
			predicted_position.y = floor_height
			_cached_predicted_bounce = predicted_position
			_prediction_cache_valid = true
			return predicted_position

	_cached_predicted_bounce = predicted_position
	_prediction_cache_valid = true
	return predicted_position

func _predict_ball_position(ball: RigidBody3D, time_ahead: float) -> Vector3:
	var gravity: float = Ball.get_effective_gravity()
	# GAP-47: perceived state seeds the prediction.
	var predicted_position: Vector3 = _perceived_ball_pos(ball) + _perceived_ball_vel(ball) * time_ahead
	predicted_position.y += -0.5 * gravity * time_ahead * time_ahead
	return predicted_position

func _predict_ai_contact_candidates(ball: RigidBody3D) -> Array[Vector3]:
	# Check cache - reuse if ball state hasn't changed significantly
	var perceived_pos: Vector3 = _perceived_ball_pos(ball)
	var perceived_vel: Vector3 = _perceived_ball_vel(ball)
	
	if _prediction_cache_valid and _last_ball_pos_cached.distance_squared_to(perceived_pos) < 0.005:
		return _cached_contact_candidates
	
	var gravity: float = Ball.get_effective_gravity()
	var predicted_position: Vector3 = perceived_pos
	var predicted_velocity: Vector3 = perceived_vel
	var predicted_omega: Vector3 = _perceived_ball_omega(ball)
	var floor_height: float = 0.08
	var has_bounced: bool = false
	var candidates: Array[Vector3] = []
	var last_valid: Vector3 = predicted_position
	var z_limit_min: float = _player.min_z
	var z_limit_max: float = _player.max_z
	var _has_entered_ai_side: bool = predicted_position.z <= z_limit_max

	for _step in range(AI_CONTACT_PREDICTION_STEPS):
		var stepped: Array = Ball.predict_aero_step(
			predicted_position, predicted_velocity, predicted_omega,
			gravity, AI_CONTACT_PREDICTION_STEP
		)
		predicted_position = stepped[0]
		predicted_velocity = stepped[1]
		predicted_omega = stepped[2]
		if not _has_entered_ai_side:
			_has_entered_ai_side = predicted_position.z <= z_limit_max
		if _has_entered_ai_side and (predicted_position.z < z_limit_min or predicted_position.z > z_limit_max):
			break
		if predicted_position.y <= floor_height:
			predicted_position.y = floor_height
			if not has_bounced:
				has_bounced = true
				var bounced: Array = Ball.predict_bounce_spin(predicted_velocity, predicted_omega)
				predicted_velocity = bounced[0]
				predicted_omega = bounced[1]
			else:
				break
		if has_bounced and _is_ball_hittable_for_ai(predicted_position):
			if candidates.size() == 0 and predicted_position.y > floor_height + 0.1:
				candidates.append(predicted_position)
			elif candidates.size() == 1 and predicted_position.y > 0.5:
				candidates.append(predicted_position)
			elif candidates.size() == 2 and predicted_position.y > 0.85:
				candidates.append(predicted_position)
				break
			last_valid = predicted_position

	if candidates.is_empty():
		if last_valid != ball.global_position:
			candidates.append(last_valid)
		else:
			candidates.append(ball.global_position)
	
	_cached_contact_candidates = candidates
	return candidates

func _predict_ai_contact_point(ball: RigidBody3D) -> Vector3:
	var candidates := _predict_ai_contact_candidates(ball)
	if candidates.is_empty():
		return ball.global_position if ball else Vector3.ZERO
	return candidates[0]

func _predict_ai_intercept_marker_point(ball: RigidBody3D) -> Vector3:
	var gravity: float = Ball.get_effective_gravity()
	# GAP-47: perceived state seeds the prediction.
	var predicted_position: Vector3 = _perceived_ball_pos(ball)
	var predicted_velocity: Vector3 = _perceived_ball_vel(ball)
	var predicted_omega: Vector3 = _perceived_ball_omega(ball)
	var floor_height: float = 0.08
	var has_bounced: bool = false
	# Tight limits — don't predict targets the AI can't reach
	var z_limit_min: float = _player.min_z
	var z_limit_max: float = _player.max_z
	var fallback_contact: Vector3 = predicted_position
	var _has_entered_ai_side: bool = predicted_position.z <= z_limit_max

	for _step in range(AI_CONTACT_PREDICTION_STEPS):
		var stepped: Array = Ball.predict_aero_step(
			predicted_position, predicted_velocity, predicted_omega,
			gravity, AI_CONTACT_PREDICTION_STEP
		)
		predicted_position = stepped[0]
		predicted_velocity = stepped[1]
		predicted_omega = stepped[2]
		if not _has_entered_ai_side:
			_has_entered_ai_side = predicted_position.z <= z_limit_max
		if _has_entered_ai_side and (predicted_position.z < z_limit_min or predicted_position.z > z_limit_max):
			break
		if predicted_position.y <= floor_height:
			predicted_position.y = floor_height
			if not has_bounced:
				has_bounced = true
				var bounced: Array = Ball.predict_bounce_spin(predicted_velocity, predicted_omega)
				predicted_velocity = bounced[0]
				predicted_omega = bounced[1]
				continue
			return Vector3(
				clamp(fallback_contact.x, _player.min_x, _player.max_x),
				fallback_contact.y,
				clamp(fallback_contact.z, _player.min_z, _player.max_z))

		if has_bounced:
			fallback_contact = predicted_position
			if predicted_position.y >= AI_INTERCEPT_MARKER_MIN_HEIGHT and predicted_position.y <= AI_INTERCEPT_MARKER_MAX_HEIGHT and _is_ball_hittable_for_ai(predicted_position):
				return predicted_position

	return Vector3(
		clamp(fallback_contact.x, _player.min_x, _player.max_x),
		fallback_contact.y,
		clamp(fallback_contact.z, _player.min_z, _player.max_z))

func _is_ball_hittable_for_ai(predicted_position: Vector3) -> bool:
	if _player.player_num == 0:
		return predicted_position.z >= _player.min_z - 1.0
	return predicted_position.z <= _player.max_z + 1.2

# ── Commit functions (smoothed position updates) ─────────────────────────────
func _commit_ai_target_position(new_target: Vector3) -> void:
	var recommit_distance: float = AI_TARGET_POST_BOUNCE_RECOMMIT_DISTANCE
	if ai_committed_target_position == Vector3.ZERO or ai_committed_target_position.distance_to(new_target) >= recommit_distance:
		ai_committed_target_position = new_target
	else:
		ai_committed_target_position = ai_committed_target_position.lerp(new_target, 0.1)

func _commit_ai_bounce_prediction(new_bounce_position: Vector3) -> void:
	if ai_committed_bounce_position == Vector3.ZERO or ai_committed_bounce_position.distance_to(new_bounce_position) >= AI_TARGET_RECOMMIT_BOUNCE_DISTANCE:
		ai_committed_bounce_position = new_bounce_position
	else:
		ai_committed_bounce_position = ai_committed_bounce_position.lerp(new_bounce_position, 0.12)

func _commit_ai_contact_prediction(new_contact_position: Vector3) -> void:
	if ai_committed_contact_position == Vector3.ZERO or ai_committed_contact_position.distance_to(new_contact_position) >= AI_TARGET_RECOMMIT_BOUNCE_DISTANCE:
		ai_committed_contact_position = new_contact_position
	else:
		ai_committed_contact_position = ai_committed_contact_position.lerp(new_contact_position, 0.08)

# ── AI hitting ────────────────────────────────────────────────────────────────
func _on_hitbox_body_entered(_body: Node3D, _paddle: StaticBody3D) -> void:
	# AI hitting is fully controlled by _try_ai_hit_ball (charge system).
	# Hitbox auto-hit was firing prematurely, resetting ball_bounced_since_last_hit
	# via body.hit_by_player() and preventing the charge system from ever starting.
	pass

func _try_ai_hit_ball() -> void:
	if not _player.is_ai or _player.paddle_hitbox == null or ai_hit_cooldown > 0.0:
		return
	var ball: RigidBody3D = _player._get_ball_ref()
	if ball == null:
		return
	if ball.get_last_hit_by() == _player.player_num:
		return

	# Before two-bounce rule is met: must wait for ball to bounce on AI's side
	# After two-bounce rule: can volley freely (skip bounce requirement)
	var can_volley_now: bool = ball.both_bounces_complete
	if not can_volley_now and not ai_ball_bounced_on_side:
		return

	# Enforce two-bounce rule: no volleys until both sides have bounced
	if not ball.both_bounces_complete and not ball.ball_bounced_since_last_hit:
		return

	# Kitchen rule: can't volley from kitchen
	if abs(_player.global_position.z) < PickleballConstants.NON_VOLLEY_ZONE and not ball.ball_bounced_since_last_hit:
		return

	var paddle_distance: float = _player.get_paddle_position().distance_to(ball.global_position)

	# Phase 1: Begin charging when close enough
	# Don't charge while ball is still on opponent's side — paddle distance may be
	# artificially short when AI reaches up toward a ball still past the net.
	if not ai_is_charging and paddle_distance <= AI_CHARGE_START_DISTANCE and ball.global_position.z < 0.0:
		ai_is_charging = true
		ai_charge_time = 0.0
		ai_state = PlayerController.AIState.CHARGING
		# Shot power varies by difficulty
		match ai_difficulty:
			0:  # EASY — mostly dinks, rare medium shots
				if randf() < 0.80:
					ai_swing_threshold = randf_range(0.08, 0.25)
				else:
					ai_swing_threshold = randf_range(0.25, 0.40)
			1:  # MEDIUM — mixed soft and firm
				if randf() < 0.55:
					ai_swing_threshold = randf_range(0.12, 0.35)
				else:
					ai_swing_threshold = randf_range(0.40, 0.60)
			2:  # HARD — aggressive, frequent drives
				if randf() < 0.35:
					ai_swing_threshold = randf_range(0.15, 0.40)
				else:
					ai_swing_threshold = randf_range(0.50, 0.85)
		# Switch to charge posture based on INTENDED contact posture (ai_desired_posture),
		# not the current visual posture — this way low/mid-low hits stay low.
		if _player.ai_desired_posture in _player.BACKHAND_POSTURES:
			var _is_low_bh := (
				_player.ai_desired_posture == PlayerController.PaddlePosture.LOW_BACKHAND or
				_player.ai_desired_posture == PlayerController.PaddlePosture.LOW_WIDE_BACKHAND or
				_player.ai_desired_posture == PlayerController.PaddlePosture.MID_LOW_BACKHAND or
				_player.ai_desired_posture == PlayerController.PaddlePosture.MID_LOW_WIDE_BACKHAND
			)
			if not _is_low_bh:
				_player.paddle_posture = PlayerController.PaddlePosture.CHARGE_BACKHAND
			# else: keep low backhand posture — generic charge animation applies
		elif _player.ai_desired_posture in _player.FOREHAND_POSTURES:
			# Only convert normal-height forehand to CHARGE_FOREHAND (full swing back).
			# Low/mid-low forehand postures keep their posture — generic charge animation applies.
			var _is_low := (
				_player.ai_desired_posture == PlayerController.PaddlePosture.LOW_FOREHAND or
				_player.ai_desired_posture == PlayerController.PaddlePosture.LOW_WIDE_FOREHAND or
				_player.ai_desired_posture == PlayerController.PaddlePosture.MID_LOW_FOREHAND or
				_player.ai_desired_posture == PlayerController.PaddlePosture.MID_LOW_WIDE_FOREHAND
			)
			if not _is_low:
				_player.paddle_posture = PlayerController.PaddlePosture.CHARGE_FOREHAND
			# else: keep low posture — set_serve_charge_visual's else branch handles the pullback
		else:
			# CENTER / OVERHEAD / VOLLEY_READY → default to forehand charge
			_player.paddle_posture = PlayerController.PaddlePosture.CHARGE_FOREHAND

	# Phase 2: Charging — animate the paddle pullback
	if ai_is_charging:
		var delta: float = get_physics_process_delta_time()
		ai_charge_time += delta
		var charge_ratio: float = clamp(ai_charge_time / AI_CHARGE_DURATION, 0.0, 1.0)
		_player.set_serve_charge_visual(charge_ratio)

		# Phase 3: Charge complete or ball is right at paddle — swing!
		var ready_to_swing: bool = charge_ratio >= ai_swing_threshold
		var close_enough: bool = paddle_distance <= AI_HIT_REACH_DISTANCE * 1.2
		var ball_very_close: bool = paddle_distance <= AI_HIT_REACH_DISTANCE * 0.8

		if (ready_to_swing and close_enough) or ball_very_close:
			_apply_ai_hit(ball, charge_ratio)
			return

		# If charge is full but ball moved away, cancel charge and reposition
		if charge_ratio >= 1.0 and paddle_distance > AI_CHARGE_START_DISTANCE:
			ai_is_charging = false
			ai_charge_time = 0.0
			ai_state = PlayerController.AIState.INTERCEPT_POSITION

	# Fallback: paddle hitbox overlap (ball flew right into paddle)
	if ai_ball_bounced_on_side or can_volley_now:
		var overlapping_bodies: Array[Node3D] = _player.paddle_hitbox.get_overlapping_bodies()
		for body in overlapping_bodies:
			if body == ball:
				if not ai_is_charging:
					ai_is_charging = true
					ai_charge_time = AI_CHARGE_DURATION * 0.5
				_apply_ai_hit(ball, clamp(ai_charge_time / AI_CHARGE_DURATION, 0.0, 1.0))
				return

func _apply_ai_hit(body: Node3D, charge_ratio: float = 0.55) -> void:
	if ai_hit_cooldown > 0.0:
		return
	if not (body is RigidBody3D):
		return
	if body.has_method("get_last_hit_by") and body.get_last_hit_by() == _player.player_num:
		return
	# Animate the swing release
	_player.animate_serve_release(charge_ratio)
	if _player.posture:
		_player.posture.notify_ball_hit()

	# AI uses shared velocity targeting — same ballistic math as human swing
	var charge: float = clamp(ai_charge_time / AI_CHARGE_DURATION, 0.05, 1.0)
	var shot_velocity: Vector3 = _game_node.compute_shot_velocity(body.global_position, charge, 1, "")
	# GAP-X: paddle velocity at impact contributes to ball speed (same as human swing).
	var ai_paddle_vel: Vector3 = _player.hitting.get_paddle_velocity()
	var ai_shot_dir: Vector3 = shot_velocity.normalized()
	var ai_paddle_comp: float = ai_paddle_vel.dot(ai_shot_dir)
	var ai_vel_transfer: float = _player.hitting.PADDLE_VEL_TRANSFER
	if absf(ai_paddle_comp) > 0.5:
		shot_velocity += ai_shot_dir * ai_paddle_comp * ai_vel_transfer
	# GAP-15: sweet-spot speed reduction — off-center hits lose up to 40% speed
	var speed_factor: float = _game_node.compute_sweet_spot_speed(body.global_position, _player.get_paddle_position(), shot_velocity)
	shot_velocity = shot_velocity * speed_factor
	body.linear_velocity = shot_velocity
	# Step 2 spin coupling — AI inherits the same shot_type → ω model as human.
	var _ai_shot_spin: Vector3 = _game_node.compute_shot_spin("", shot_velocity, charge, 1, _player.paddle_posture)
	# Step 3 sweet-spot injection — off-center contact adds rim-strike torque.
	var _ai_sweet_spin: Vector3 = _game_node.compute_sweet_spot_spin(body.global_position, _player.get_paddle_position(), shot_velocity)
	body.angular_velocity = _ai_shot_spin + _ai_sweet_spin
	var shot_impulse: Vector3 = shot_velocity.normalized()
	if body.has_method("hit_by_player"):
		body.hit_by_player(_player.player_num)
	ai_hit_cooldown = AI_HIT_COOLDOWN
	_player.hit_ball.emit(body, shot_impulse.normalized())

	# Reset charge state
	ai_is_charging = false
	ai_charge_time = 0.0
	ai_ball_bounced_on_side = false
	ai_state = PlayerController.AIState.INTERCEPT_POSITION
	print("[BOS] reset by _apply_ai_hit")

	# Draw AI trajectory line (estimate post-impulse velocity)
	var post_hit_vel: Vector3 = body.linear_velocity + (shot_impulse / body.mass)
	_draw_ai_trajectory(body.global_position, post_hit_vel)

# ── AI trajectory visualization ───────────────────────────────────────────────
func _setup_ai_trajectory() -> void:
	ai_trajectory_mesh_instance = MeshInstance3D.new()
	ai_trajectory_mesh_instance.name = "AITrajectoryPredictor"
	ai_trajectory_mesh = ImmediateMesh.new()
	ai_trajectory_mesh_instance.mesh = ai_trajectory_mesh
	ai_trajectory_material = StandardMaterial3D.new()
	ai_trajectory_material.albedo_color = Color(1.0, 0.4, 0.2, 0.85)
	ai_trajectory_material.emission_enabled = true
	ai_trajectory_material.emission = Color(1.0, 0.35, 0.1, 1.0)
	ai_trajectory_material.emission_energy_multiplier = 0.7
	ai_trajectory_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ai_trajectory_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ai_trajectory_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ai_trajectory_mesh_instance.visible = false
	get_tree().root.call_deferred("add_child", ai_trajectory_mesh_instance)

func _draw_ai_trajectory(ball_pos: Vector3, ball_vel: Vector3) -> void:
	if _game_node and not _game_node.debug_visuals_visible:
		if ai_trajectory_mesh_instance:
			ai_trajectory_mesh_instance.visible = false
		return
	if ai_trajectory_mesh == null:
		_setup_ai_trajectory()
	ai_trajectory_mesh.clear_surfaces()
	ai_trajectory_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, ai_trajectory_material)
	var gravity: float = Ball.get_effective_gravity()
	var pos: Vector3 = ball_pos
	var vel: Vector3 = ball_vel
	for step in range(28):
		ai_trajectory_mesh.surface_add_vertex(pos + Vector3(0.0, 0.03, 0.0))
		vel.y -= gravity * 0.08
		pos += vel * 0.08
		if pos.y <= 0.08:
			pos.y = 0.08
			ai_trajectory_mesh.surface_add_vertex(pos + Vector3(0.0, 0.03, 0.0))
			break
	ai_trajectory_mesh.surface_end()
	ai_trajectory_mesh_instance.visible = true
	ai_trajectory_timer = AI_TRAJECTORY_DURATION

func _update_ai_trajectory_fade(delta: float) -> void:
	if ai_trajectory_timer > 0.0:
		ai_trajectory_timer -= delta
		if ai_trajectory_timer <= 0.0 and ai_trajectory_mesh_instance != null:
			ai_trajectory_mesh_instance.visible = false
