class_name PlayerAIBrain extends Node
## PlayerAIBrain — AI prediction, intercept, and hitting logic extracted from player.gd

const _PC = preload("res://scripts/player.gd")
# Alias PaddlePosture enum values as local constants to avoid class_name resolution issues
const PP_FOREHAND: int = _PC.PaddlePosture.FOREHAND
const PP_FORWARD: int = _PC.PaddlePosture.FORWARD
const PP_BACKHAND: int = _PC.PaddlePosture.BACKHAND
const PP_MEDIUM_OVERHEAD: int = _PC.PaddlePosture.MEDIUM_OVERHEAD
const PP_HIGH_OVERHEAD: int = _PC.PaddlePosture.HIGH_OVERHEAD
const PP_LOW_FOREHAND: int = _PC.PaddlePosture.LOW_FOREHAND
const PP_LOW_FORWARD: int = _PC.PaddlePosture.LOW_FORWARD
const PP_LOW_BACKHAND: int = _PC.PaddlePosture.LOW_BACKHAND
const PP_CHARGE_FOREHAND: int = _PC.PaddlePosture.CHARGE_FOREHAND
const PP_CHARGE_BACKHAND: int = _PC.PaddlePosture.CHARGE_BACKHAND
const PP_WIDE_FOREHAND: int = _PC.PaddlePosture.WIDE_FOREHAND
const PP_WIDE_BACKHAND: int = _PC.PaddlePosture.WIDE_BACKHAND
const PP_VOLLEY_READY: int = _PC.PaddlePosture.VOLLEY_READY
const PP_MID_LOW_FOREHAND: int = _PC.PaddlePosture.MID_LOW_FOREHAND
const PP_MID_LOW_BACKHAND: int = _PC.PaddlePosture.MID_LOW_BACKHAND
const PP_MID_LOW_FORWARD: int = _PC.PaddlePosture.MID_LOW_FORWARD
const PP_MID_LOW_WIDE_FOREHAND: int = _PC.PaddlePosture.MID_LOW_WIDE_FOREHAND
const PP_MID_LOW_WIDE_BACKHAND: int = _PC.PaddlePosture.MID_LOW_WIDE_BACKHAND
const PP_LOW_WIDE_FOREHAND: int = _PC.PaddlePosture.LOW_WIDE_FOREHAND
const PP_LOW_WIDE_BACKHAND: int = _PC.PaddlePosture.LOW_WIDE_BACKHAND
const PP_READY: int = _PC.PaddlePosture.READY

# ── AI constants ──────────────────────────────────────────────────────────────
const AI_RECEIVE_X_TOLERANCE := 0.25
const AI_RECEIVE_Z_TOLERANCE := 0.20
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
const _Ball := preload("res://scripts/ball.gd")
const _Flight := preload("res://scripts/ball_flight_predictor.gd")
const SMASH_FORCE_BONUS := 1.35
const SMASH_DOWNWARD_BIAS := 0.22
const AI_MARKER_HEIGHT := 0.09
const AI_TARGET_RECOMMIT_DISTANCE := 0.55
const AI_TARGET_POST_BOUNCE_RECOMMIT_DISTANCE := 0.45
const AI_RECEIVE_MARKER_LANE_OFFSET := 0.16
const AI_RECEIVE_MARKER_BOUNCE_PULL := 0.72
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

var ai_state: int = AIState.INTERCEPT_POSITION
var ai_desired_posture: int = 0  # PP_FOREHAND
var ai_target_position: Vector3 = Vector3.ZERO
var ai_predicted_bounce_position: Vector3 = Vector3.ZERO
var ai_predicted_contact_position: Vector3 = Vector3.ZERO
var ai_selected_contact_reachable: bool = false
var ai_selected_contact_time: float = -1.0
var _charge_contact_position: Vector3 = Vector3.ZERO
var _charge_target_position: Vector3 = Vector3.ZERO
var _charge_posture: int = PP_READY
var last_ai_contact_correction: float = 0.0

# GAP-47: visuomotor latency ring buffer. The AI "sees" ball state from N
# physics frames ago, matching human sensorimotor delay (~180-220 ms). Without
# this, the AI reacts to trajectory changes the same frame they happen, which
# is superhuman and asymmetric vs. the human player. Tunable per difficulty.
var _ball_history: Array = []
var _observed_flight_id: int = -1
var _perception_ready: bool = false
var _perceived_state: Dictionary = {}
var _predicted_flight: Dictionary = {}
var _predicted_flight_frame: int = -1
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
var _game_node = null  # set by game.gd for compute_shot_velocity access; untyped to allow test injection of FakeGame/RefCounted
var ai_trajectory_mesh_instance: MeshInstance3D = null
# Cache for prediction optimization
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

var _player  # set in _ready

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
		ai_selected_contact_reachable = false
		ai_selected_contact_time = -1.0
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
	if not _perception_ready:
		return input_dir

	var predicted_landing: Vector3 = _predict_first_bounce_position(ball)
	var intercept_solution: Dictionary = _get_ai_intercept_solution(predicted_landing)
	var intercept_target: Vector3 = intercept_solution["target"] as Vector3
	ai_desired_posture = int(intercept_solution["posture"])
	var selected_contact: Vector3 = intercept_solution["contact"]
	ai_selected_contact_reachable = bool(intercept_solution["reachable"])
	ai_selected_contact_time = float(intercept_solution["time"])
	if ai_is_charging and ai_state == AIState.CHARGING and _charge_contact_position != Vector3.ZERO:
		selected_contact = _charge_contact_position
		intercept_target = _charge_target_position
		ai_desired_posture = _charge_posture
		ai_selected_contact_reachable = true
		ai_selected_contact_time = 0.0

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
	if ai_state != AIState.CHARGING:
		if bool(intercept_solution["reachable"]) and paddle_target_position.distance_to(selected_contact) <= 0.5:
			ai_state = AIState.HIT_BALL
		else:
			ai_state = AIState.INTERCEPT_POSITION
	target_x = intercept_target.x
	target_z = intercept_target.z
	ai_committed_target_position = Vector3(target_x, _player.ground_y, target_z)
	ai_committed_bounce_position = predicted_landing
	ai_committed_contact_position = selected_contact
	ai_target_position = ai_committed_target_position
	ai_predicted_bounce_position = predicted_landing
	ai_predicted_contact_position = selected_contact

	# When charging, use tighter deadzone and don't oscillate
	var x_tol: float = AI_RECEIVE_X_TOLERANCE
	var z_tol: float = AI_RECEIVE_Z_TOLERANCE
	if ai_state == AIState.CHARGING:
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
		return [PP_HIGH_OVERHEAD, PP_MEDIUM_OVERHEAD]
	elif rel_height >= MEDIUM_OVERHEAD_TRIGGER_HEIGHT:
		return [PP_MEDIUM_OVERHEAD, PP_HIGH_OVERHEAD, PP_FORWARD]
	elif rel_height >= 0.55:
		# Normal height (hip and above) — full lateral coverage
		return [
			PP_FOREHAND, PP_FORWARD, PP_BACKHAND,
			PP_WIDE_FOREHAND, PP_WIDE_BACKHAND,
			PP_VOLLEY_READY,
		]
	elif rel_height >= 0.22:
		# Mid-low / knee height (0.22–0.55 m above floor)
		return [
			PP_MID_LOW_FOREHAND, PP_MID_LOW_BACKHAND,
			PP_MID_LOW_FORWARD,
			PP_MID_LOW_WIDE_FOREHAND, PP_MID_LOW_WIDE_BACKHAND,
			PP_FOREHAND, PP_BACKHAND,  # fallback for borderline
		]
	else:
		# Low / ankle height (< 0.22 m above floor — just after bounce)
		return [
			PP_LOW_FOREHAND, PP_LOW_BACKHAND, PP_LOW_FORWARD,
			PP_LOW_WIDE_FOREHAND, PP_LOW_WIDE_BACKHAND,
			PP_MID_LOW_FOREHAND, PP_MID_LOW_BACKHAND,  # fallback
		]

# ── Intercept solution ────────────────────────────────────────────────────────
func _get_ai_intercept_solution(predicted_ball_pos: Vector3) -> Dictionary:
	var ball: RigidBody3D = _player._get_ball_ref()
	var best_target: Vector3 = _player.global_position
	var best_score: float = INF
	var best_posture: int = PP_READY
	var best_contact: Vector3 = predicted_ball_pos
	var best_time: float = -1.0
	var flight: Dictionary = _get_predicted_flight(ball)
	var samples: Array = flight.get("samples", [])
	var zone_library: PostureLibrary = PostureLibrary.instance()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	var forward_axis: Vector3 = _player._get_forward_axis()
	var shoulder_offset: Vector3 = PaddleReach.shoulder_world(_player) - _player.global_position
	var move_speed: float = _player.move_speed
	var legal_after: float = 0.0
	if not ball.both_bounces_complete and not ai_ball_bounced_on_side:
		legal_after = INF
		for bounce in flight.get("bounce_events", []):
			if bounce["pos"].z < 0.0:
				legal_after = bounce["time"]
				break

	for sample_index in range(1, samples.size(), 3):
		var sample: Dictionary = samples[sample_index]
		var contact_point: Vector3 = sample["pos"]
		var contact_time: float = sample["time"]
		if contact_time < legal_after or contact_point.z < _player.min_z or contact_point.z > _player.max_z:
			continue
		if contact_point.x < _player.min_x or contact_point.x > _player.max_x:
			continue
		if contact_point.y < _Flight.FLOOR_REST_Y + 0.12:
			continue
		var rel_height: float = contact_point.y - COURT_FLOOR_Y
		var height_postures: Array[int] = _get_posture_for_height(rel_height)
		for posture in height_postures:
			var def: PostureDefinition = zone_library.get_def(posture)
			if def == null or not def.has_zone:
				continue
			var posture_offset: Vector3 = _player._get_posture_offset_for(posture)
			var candidate_target: Vector3 = contact_point - posture_offset
			candidate_target.y = _player.ground_y
			candidate_target.x = clampf(candidate_target.x, _player.min_x, _player.max_x)
			candidate_target.z = clampf(candidate_target.z, _player.min_z, _player.max_z)
			if int(sample["bounces"]) == 0 and absf(candidate_target.z) < PickleballConstants.NON_VOLLEY_ZONE:
				continue
			var travel_distance: float = Vector2(candidate_target.x - _player.global_position.x,
				candidate_target.z - _player.global_position.z).length()
			if travel_distance > move_speed * contact_time + 0.12:
				continue
			var local: Vector3 = contact_point - candidate_target
			var lateral: float = local.dot(forehand_axis)
			var forward: float = local.dot(forward_axis)
			if lateral < def.zone_x_min - 0.06 or lateral > def.zone_x_max + 0.06:
				continue
			if rel_height < def.zone_y_min - 0.06 or rel_height > def.zone_y_max + 0.06:
				continue
			if absf(forward - def.zone_forward_offset) > 0.25:
				continue
			if contact_point.distance_to(candidate_target + shoulder_offset) > PaddleReach.MAX_HEAD_DISTANCE + 0.03:
				continue
			# Take the first legal contact the AI can reach. A later, easier point
			# often leaves no swing window after the bounce.
			var travel_fraction: float = travel_distance / maxf(move_speed * contact_time, 0.1)
			var score: float = contact_time + travel_fraction * 0.15 - _get_ai_posture_preference(posture) * 0.03
			if score < best_score:
				best_score = score
				best_target = candidate_target
				best_posture = posture
				best_contact = contact_point
				best_time = contact_time

	if best_score == INF:
		best_target = predicted_ball_pos - _player._get_posture_offset_for(PP_READY)
		best_target.y = _player.ground_y
		best_target.x = clampf(best_target.x, _player.min_x, _player.max_x)
		best_target.z = clampf(best_target.z, _player.min_z, _player.max_z)
	return {
		"target": best_target,
		"posture": best_posture,
		"contact": best_contact,
		"time": best_time,
		"reachable": best_score != INF,
	}

# ── Posture preference ────────────────────────────────────────────────────────
func _get_ai_posture_preference(posture: int) -> float:
	match posture:
		PP_FOREHAND:              return AI_FOREHAND_PREFERENCE
		PP_FORWARD:               return AI_FORWARD_PREFERENCE
		PP_BACKHAND:              return AI_BACKHAND_PREFERENCE
		PP_MEDIUM_OVERHEAD:       return AI_OVERHEAD_PREFERENCE
		PP_HIGH_OVERHEAD:         return AI_OVERHEAD_PREFERENCE
		PP_LOW_FOREHAND:          return AI_LOW_FOREHAND_PREFERENCE
		PP_LOW_FORWARD:           return AI_LOW_FORWARD_PREFERENCE
		PP_LOW_BACKHAND:          return AI_LOW_BACKHAND_PREFERENCE
		PP_WIDE_FOREHAND:         return AI_WIDE_FOREHAND_PREFERENCE
		PP_WIDE_BACKHAND:         return AI_WIDE_BACKHAND_PREFERENCE
		PP_VOLLEY_READY:          return AI_VOLLEY_READY_PREFERENCE
		PP_MID_LOW_FOREHAND:      return AI_MID_LOW_FOREHAND_PREFERENCE
		PP_MID_LOW_BACKHAND:      return AI_MID_LOW_BACKHAND_PREFERENCE
		PP_MID_LOW_FORWARD:       return AI_MID_LOW_FORWARD_PREFERENCE
		PP_MID_LOW_WIDE_FOREHAND: return AI_MID_LOW_WIDE_FOREHAND_PREFERENCE
		PP_MID_LOW_WIDE_BACKHAND: return AI_MID_LOW_WIDE_BACKHAND_PREFERENCE
		PP_LOW_WIDE_FOREHAND:     return AI_LOW_WIDE_FOREHAND_PREFERENCE
		PP_LOW_WIDE_BACKHAND:     return AI_LOW_WIDE_BACKHAND_PREFERENCE
		PP_READY:
			return 0.50  # neutral ready-position — valid transition posture
		PP_CHARGE_FOREHAND, PP_CHARGE_BACKHAND:
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
	var flight_id: int = ball.flight_id if ball is Ball else 0
	if flight_id != _observed_flight_id:
		_observed_flight_id = flight_id
		_ball_history.clear()
		_predicted_flight.clear()
		_predicted_flight_frame = -1
		ai_is_charging = false
		ai_charge_time = 0.0
		ai_selected_contact_reachable = false
		ai_selected_contact_time = -1.0
		_charge_contact_position = Vector3.ZERO
		_charge_target_position = Vector3.ZERO
	var max_frames: int = _get_latency_frames() + 1
	_ball_history.append({"pos": ball.global_position, "vel": ball.linear_velocity, "omega": ball.angular_velocity})
	if _ball_history.size() > max_frames:
		_ball_history.pop_front()
	_perception_ready = _ball_history.size() >= max_frames
	if not _perception_ready:
		return
	var oldest: Dictionary = _ball_history.front()
	var delay: float = (_ball_history.size() - 1) / float(Engine.physics_ticks_per_second)
	_perceived_state = _Flight.advance(oldest["pos"], oldest["vel"], oldest["omega"], delay)
	_predicted_flight_frame = -1

func _perceived_ball_pos(ball: RigidBody3D) -> Vector3:
	return _perceived_state.get("pos", ball.global_position if ball else Vector3.ZERO)

func _perceived_ball_vel(ball: RigidBody3D) -> Vector3:
	return _perceived_state.get("vel", ball.linear_velocity if ball else Vector3.ZERO)

func _perceived_ball_omega(ball: RigidBody3D) -> Vector3:
	return _perceived_state.get("omega", ball.angular_velocity if ball else Vector3.ZERO)

func _get_predicted_flight(ball: RigidBody3D) -> Dictionary:
	if ball == null:
		return {}
	var frame: int = Engine.get_physics_frames()
	if _predicted_flight_frame != frame or _predicted_flight.is_empty():
		_predicted_flight = _Flight.trace(_perceived_ball_pos(ball), _perceived_ball_vel(ball),
			_perceived_ball_omega(ball), 3.0, 2, true)
		_predicted_flight_frame = frame
	return _predicted_flight

func _predict_first_bounce_position(ball: RigidBody3D) -> Vector3:
	var flight: Dictionary = _get_predicted_flight(ball)
	var bounce: Vector3 = flight.get("first_bounce", Vector3.ZERO)
	if bounce != Vector3.ZERO:
		return bounce
	var samples: Array = flight.get("samples", [])
	return samples.back()["pos"] if not samples.is_empty() else ball.global_position

# ── Commit functions (smoothed position updates) ─────────────────────────────
func _commit_ai_target_position(new_target: Vector3) -> void:
	var recommit_distance: float = AI_TARGET_POST_BOUNCE_RECOMMIT_DISTANCE
	if ai_committed_target_position == Vector3.ZERO or ai_committed_target_position.distance_to(new_target) >= recommit_distance:
		ai_committed_target_position = new_target
	else:
		ai_committed_target_position = ai_committed_target_position.lerp(new_target, 0.1)

# ── AI hitting ────────────────────────────────────────────────────────────────
func align_paddle_to_contact(delta: float) -> void:
	if not _player.is_ai or not ai_selected_contact_reachable or _player.paddle_node == null:
		return
	var ball: RigidBody3D = _player._get_ball_ref()
	if ball == null or ball.get_last_hit_by() == _player.player_num or ball.global_position.z >= 0.0:
		return
	var contact: Vector3 = ai_predicted_contact_position
	if ai_selected_contact_time > 0.35 and ball.global_position.distance_to(contact) > 0.75:
		return
	# Lead with the timed indicator, then follow the live ball through contact.
	if ball.global_position.distance_to(contact) < 0.55:
		contact = ball.global_position
	var shoulder: Vector3 = PaddleReach.shoulder_world(_player)
	if shoulder.distance_to(contact) > PaddleReach.MAX_HEAD_DISTANCE + 0.05:
		return
	var head: Vector3 = PaddleReach.head_world(_player)
	var target_head: Vector3 = PaddleReach.clamp_head_with_floor(contact, shoulder,
		_player.COURT_FLOOR_Y + 0.06)
	var rate: float = 42.0 if ball.global_position.distance_to(contact) < 0.55 else 22.0
	var blend: float = 1.0 - exp(-maxf(delta, 0.0) * rate)
	_player.paddle_node.global_position = head.lerp(target_head, blend) - _player.paddle_node.global_transform.basis.y * 0.4

func _ball_at_reachable_indicator(ball: RigidBody3D) -> bool:
	if not ai_selected_contact_reachable or ball.global_position.z >= 0.0:
		return false
	if ball.global_position.y < _Flight.FLOOR_REST_Y + 0.015:
		return false
	if ball.global_position.distance_to(ai_predicted_contact_position) > AI_HIT_CONTACT_WINDOW:
		return false
	return PaddleReach.shoulder_world(_player).distance_to(ball.global_position) <= PaddleReach.MAX_HEAD_DISTANCE + 0.03

func _place_paddle_head_at_ball(ball: RigidBody3D) -> void:
	last_ai_contact_correction = PaddleReach.head_world(_player).distance_to(ball.global_position)
	var offset: Vector3 = _player.paddle_node.global_transform.basis.y * 0.4
	var contact: Vector3 = PaddleReach.clamp_head_with_floor(ball.global_position,
		PaddleReach.shoulder_world(_player), _player.COURT_FLOOR_Y + 0.06)
	_player.paddle_node.global_position = contact - offset

func _on_hitbox_body_entered(_body: Node3D, _paddle: StaticBody3D) -> void:
	# AI hitting is fully controlled by _try_ai_hit_ball (charge system).
	# Hitbox auto-hit was firing prematurely, resetting ball_bounced_since_last_hit
	# via body.hit_by_player() and preventing the charge system from ever starting.
	pass

func _try_ai_hit_ball() -> void:
	if not _player.is_ai or not _perception_ready or _player.paddle_hitbox == null or ai_hit_cooldown > 0.0:
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

	var paddle_distance: float = PaddleReach.head_world(_player).distance_to(ball.global_position)

	# Phase 1: Begin charging when close enough
	# Don't charge while ball is still on opponent's side — paddle distance may be
	# artificially short when AI reaches up toward a ball still past the net.
	if not ai_is_charging and ball.global_position.z < 0.0 and (paddle_distance <= AI_CHARGE_START_DISTANCE
			or ai_selected_contact_reachable and ball.global_position.distance_to(ai_predicted_contact_position) < 1.2):
		ai_is_charging = true
		ai_charge_time = 0.0
		ai_state = AIState.CHARGING
		_charge_contact_position = ai_predicted_contact_position
		_charge_target_position = ai_committed_target_position
		_charge_posture = ai_desired_posture
		# Shot power varies by difficulty
		match ai_difficulty:
			0:  # EASY — mostly dinks, rare medium shots
				if randf() < 0.60:
					ai_swing_threshold = randf_range(0.35, 0.55)
				else:
					ai_swing_threshold = randf_range(0.55, 0.75)
			1:  # MEDIUM — mixed soft and firm
				if randf() < 0.40:
					ai_swing_threshold = randf_range(0.40, 0.60)
				else:
					ai_swing_threshold = randf_range(0.60, 0.80)
			2:  # HARD — aggressive, frequent drives
				if randf() < 0.35:
					ai_swing_threshold = randf_range(0.50, 0.70)
				else:
					ai_swing_threshold = randf_range(0.70, 0.90)
		# Switch to charge posture based on INTENDED contact posture (ai_desired_posture),
		# not the current visual posture — this way low/mid-low hits stay low.
		if _player.ai_desired_posture in _player.BACKHAND_POSTURES:
			var _is_low_bh: bool = (
				_player.ai_desired_posture == PP_LOW_BACKHAND or
				_player.ai_desired_posture == PP_LOW_WIDE_BACKHAND or
				_player.ai_desired_posture == PP_MID_LOW_BACKHAND or
				_player.ai_desired_posture == PP_MID_LOW_WIDE_BACKHAND
			)
			if not _is_low_bh:
				_player.paddle_posture = PP_CHARGE_BACKHAND
			# else: keep low backhand posture — generic charge animation applies
		elif _player.ai_desired_posture in _player.FOREHAND_POSTURES:
			# Only convert normal-height forehand to CHARGE_FOREHAND (full swing back).
			# Low/mid-low forehand postures keep their posture — generic charge animation applies.
			var _is_low: bool = (
				_player.ai_desired_posture == PP_LOW_FOREHAND or
				_player.ai_desired_posture == PP_LOW_WIDE_FOREHAND or
				_player.ai_desired_posture == PP_MID_LOW_FOREHAND or
				_player.ai_desired_posture == PP_MID_LOW_WIDE_FOREHAND
			)
			if not _is_low:
				_player.paddle_posture = PP_CHARGE_FOREHAND
			# else: keep low posture — set_serve_charge_visual's else branch handles the pullback
		else:
			# CENTER / OVERHEAD / VOLLEY_READY → default to forehand charge
			_player.paddle_posture = PP_CHARGE_FOREHAND

	# Phase 2: Charging — animate the paddle pullback
	if ai_is_charging:
		var delta: float = get_physics_process_delta_time()
		ai_charge_time += delta
		var charge_ratio: float = clamp(ai_charge_time / AI_CHARGE_DURATION, 0.0, 1.0)
		# Finish the pullback before the contact window. Reapplying it every
		# frame near the ball used to yank the head away from the indicator.
		if ai_selected_contact_time > 0.30 and ball.global_position.distance_to(ai_predicted_contact_position) > 0.75:
			_player.set_serve_charge_visual(charge_ratio)
		align_paddle_to_contact(delta)

		# Phase 3: Charge complete or ball is right at paddle — swing!
		var ready_to_swing: bool = charge_ratio >= ai_swing_threshold
		var close_enough: bool = paddle_distance <= 0.30
		var ball_very_close: bool = paddle_distance <= 0.18

		var at_indicator: bool = _ball_at_reachable_indicator(ball)
		if (ready_to_swing and close_enough) or ball_very_close or at_indicator:
			if at_indicator:
				_place_paddle_head_at_ball(ball)
			_apply_ai_hit(ball, charge_ratio)
			return

		# If charge is full but ball moved away, cancel charge and reposition
		if charge_ratio >= 1.0 and paddle_distance > AI_CHARGE_START_DISTANCE:
			ai_is_charging = false
			ai_charge_time = 0.0
			ai_state = AIState.INTERCEPT_POSITION
			_charge_contact_position = Vector3.ZERO
			_charge_target_position = Vector3.ZERO

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

	# Evaluate the complete launch, including paddle motion and contact offset.
	var charge: float = clamp(ai_charge_time / AI_CHARGE_DURATION, 0.05, 1.0)
	var ai_paddle_vel: Vector3 = _player.hitting.get_paddle_velocity().limit_length(15.0)
	var paddle_pos: Vector3 = _player.global_position + _player._get_posture_offset_for(_player.ai_desired_posture)
	var launch: Dictionary = _game_node.solve_ai_launch(body.global_position, charge,
		_player.ai_desired_posture, paddle_pos, ai_paddle_vel, _player.hitting.PADDLE_VEL_TRANSFER)
	if launch.is_empty():
		return
	var shot_velocity: Vector3 = launch["velocity"]
	body.linear_velocity = shot_velocity
	body.angular_velocity = launch["omega"]
	var shot_impulse: Vector3 = shot_velocity.normalized()
	if body.has_method("hit_by_player"):
		body.hit_by_player(_player.player_num)
	ai_hit_cooldown = AI_HIT_COOLDOWN
	_player.hit_ball.emit(body, shot_impulse.normalized())

	# Reset charge state
	ai_is_charging = false
	ai_charge_time = 0.0
	_charge_contact_position = Vector3.ZERO
	_charge_target_position = Vector3.ZERO
	ai_ball_bounced_on_side = false
	ai_state = AIState.INTERCEPT_POSITION
	print("[BOS] reset by _apply_ai_hit")

	_draw_ai_trajectory(body.global_position, body.linear_velocity, body.angular_velocity)

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

func _draw_ai_trajectory(ball_pos: Vector3, ball_vel: Vector3, spin: Vector3) -> void:
	if _game_node and not _game_node.debug_visuals_visible:
		if ai_trajectory_mesh_instance:
			ai_trajectory_mesh_instance.visible = false
		return
	if ai_trajectory_mesh == null:
		_setup_ai_trajectory()
	ai_trajectory_mesh.clear_surfaces()
	ai_trajectory_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, ai_trajectory_material)
	var flight: Dictionary = _Flight.trace(ball_pos, ball_vel, spin, 3.0, 1, true)
	for sample in flight["samples"]:
		ai_trajectory_mesh.surface_add_vertex(sample["pos"] + Vector3(0.0, 0.03, 0.0))
	ai_trajectory_mesh.surface_end()
	ai_trajectory_mesh_instance.visible = true
	ai_trajectory_timer = AI_TRAJECTORY_DURATION

func _update_ai_trajectory_fade(delta: float) -> void:
	if ai_trajectory_timer > 0.0:
		ai_trajectory_timer -= delta
		if ai_trajectory_timer <= 0.0 and ai_trajectory_mesh_instance != null:
			ai_trajectory_mesh_instance.visible = false

## ─── Trajectory helpers used by test_ai_trajectory.gd ───────────────────────

## Simulate a shot trajectory and return where it lands (court floor contact
## or net-crossing point). Uses Ball.predict_aero_step() for physics.
func _simulate_landing(pos: Vector3, vel: Vector3, omega: Vector3, detect_net: bool = true) -> Vector3:
	var grav: float = _Ball.get_effective_gravity()
	var p: Vector3 = pos
	var v: Vector3 = vel
	var o: Vector3 = omega
	var net_z: float = 0.0
	var net_h: float = 1.0
	var _local_floor_y: float = 0.075
	for _step in range(400):
		var prev_p: Vector3 = p
		var stepped: Array = _Ball.predict_aero_step(p, v, o, grav, 0.02)
		p = stepped[0]
		v = stepped[1]
		o = stepped[2]
		if detect_net:
			if (prev_p.z < net_z and p.z >= net_z) or (prev_p.z > net_z and p.z <= net_z):
				var t: float = absf(prev_p.z) / maxf(absf(p.z - prev_p.z), 0.001)
				var hit_y: float = lerpf(prev_p.y, p.y, t)
				if hit_y < net_h:
					return Vector3(lerpf(prev_p.x, p.x, t), hit_y, net_z)
		if p.y <= _local_floor_y + 0.05:
			return p
	return p

## Return the height of the ball when it crosses the net Z plane.
func _simulate_apex_height(pos: Vector3, vel: Vector3, omega: Vector3) -> float:
	var grav: float = _Ball.get_effective_gravity()
	var p: Vector3 = pos
	var v: Vector3 = vel
	var o: Vector3 = omega
	var apex_y: float = pos.y
	for _step in range(400):
		var stepped: Array = _Ball.predict_aero_step(p, v, o, grav, 0.02)
		p = stepped[0]
		v = stepped[1]
		o = stepped[2]
		apex_y = maxf(apex_y, p.y)
		if p.y <= 0.1:
			break
	return apex_y

func _simulate_net_height(pos: Vector3, vel: Vector3, omega: Vector3, net_z: float) -> float:
	var grav: float = _Ball.get_effective_gravity()
	var p: Vector3 = pos
	var v: Vector3 = vel
	var o: Vector3 = omega
	# If the ball is already past the net and moving away from it, no crossing occurs.
	var moving_toward_net: bool = (pos.z < net_z and vel.z > 0.0) or (pos.z > net_z and vel.z < 0.0)
	if not moving_toward_net:
		return INF
	for _step in range(400):
		var prev_p: Vector3 = p
		var stepped: Array = _Ball.predict_aero_step(p, v, o, grav, 0.02)
		p = stepped[0]
		v = stepped[1]
		o = stepped[2]
		if (prev_p.z < net_z and p.z >= net_z) or (prev_p.z > net_z and p.z <= net_z):
			var t: float = absf(prev_p.z) / maxf(absf(p.z - prev_p.z), 0.001)
			return lerpf(prev_p.y, p.y, t)
		if p.y <= 0.1:
			return p.y
	return p.y

## Pick a random landing target inside the service box on the AI's side (z > 0).
## difficulty 0=EASY, 1=MEDIUM, 2=HARD
func _pick_ai_target_in_service_box(difficulty: int, _charge: float) -> Vector2:
	var NON_VOLLEY_ZONE: float = 2.134
	var COURT_WIDTH_HALF: float = 3.05
	var COURT_LENGTH_HALF: float = 6.7
	var min_z: float = NON_VOLLEY_ZONE + 0.3
	var max_z: float = COURT_LENGTH_HALF - 0.3
	var lateral_range: float = COURT_WIDTH_HALF * 0.8
	var tx: float = randf_range(-lateral_range, lateral_range)
	var tz: float = randf_range(min_z, max_z)
	# HARD: pull targets toward corners
	if difficulty == 2:
		tx = signf(tx) * (COURT_WIDTH_HALF * 0.7)
		tz = randf_range(min_z + 1.0, max_z - 0.5)
	# EASY: center bias
	elif difficulty == 0:
		tx *= 0.4
		tz = lerpf(min_z + 0.5, max_z - 0.5, 0.5)
	return Vector2(tx, tz)

## Compute shot velocity toward the picked target, with arc for net clearance.
## Returns velocity vector (m/s). Public wrapper for tests.
func compute_ai_shot_velocity(ball_pos: Vector3, charge: float, difficulty: int, override_target: Vector2 = Vector2(-INF, -INF)) -> Vector3:
	return _compute_ai_shot_velocity(ball_pos, charge, difficulty, override_target)

## Internal shot velocity computation.
func _compute_ai_shot_velocity(ball_pos: Vector3, charge: float, difficulty: int, override_target: Vector2 = Vector2(-INF, -INF)) -> Vector3:
	var target: Vector2
	if override_target.x > -INF:
		target = override_target
	else:
		target = _pick_ai_target_in_service_box(difficulty, charge)
	var tx: float = target.x
	var tz: float = target.y
	var dx: float = tx - ball_pos.x
	var dz: float = tz - ball_pos.z
	var horizontal_dist: float = sqrt(dx * dx + dz * dz)
	if horizontal_dist < 0.1:
		horizontal_dist = 0.1

	var grav: float = _Ball.get_effective_gravity()
	var speed: float = 8.0 + charge * 8.0
	var t_est: float = horizontal_dist / maxf(speed * 0.7, 0.1)

	# Initial velocity estimate (parabolic, no drag)
	var vy: float = (0.5 * grav * t_est * t_est + 1.0) / maxf(t_est, 0.01)
	var vx: float = dx / maxf(t_est, 0.01)
	var vz: float = dz / maxf(t_est, 0.01)
	var vel: Vector3 = Vector3(vx, vy, vz)

	# Iteratively refine velocity using actual physics simulation
	for _iter in range(30):
		# Recompute spin each iteration (spin depends on velocity)
		var spin: Vector3 = Vector3.ZERO
		if _game_node and _game_node.has_method("compute_shot_spin"):
			spin = _game_node.compute_shot_spin("", vel, charge, 1, 0)

		var landing: Vector3 = _simulate_landing(ball_pos, vel, spin, true)
		var err_x: float = tx - landing.x
		var err_z: float = tz - landing.z
		var err_y: float = 0.08 - landing.y

		# Check net clearance
		var net_h: float = _simulate_net_height(ball_pos, vel, spin, 0.0)
		var net_ok: bool = net_h >= 1.0 or net_h == INF

		# Close enough — stop iterating
		if absf(err_x) < 0.06 and absf(err_z) < 0.06 and absf(err_y) < 0.02 and net_ok:
			break

		# If net is too low, boost vy first (highest priority)
		if not net_ok and net_h != INF:
			var t_net: float = maxf(absf(ball_pos.z) / maxf(absf(vel.z), 0.1), 0.1)
			var vy_needed: float = (1.2 - ball_pos.y + 0.5 * grav * t_net * t_net) / t_net
			vel.y = maxf(vel.y, vy_needed * 1.3)
			# Also boost horizontal speed slightly so higher arc doesn't overshoot
			vel.x *= 0.98
			vel.z *= 0.98
		else:
			# Adjust horizontal velocity to correct landing position
			var actual_dx: float = landing.x - ball_pos.x
			var actual_dz: float = landing.z - ball_pos.z
			if absf(actual_dz) > 0.03:
				var scale_z: float = dz / actual_dz
				vel.z *= clampf(lerpf(1.0, scale_z, 0.75), 0.5, 2.0)
			if absf(actual_dx) > 0.03:
				var scale_x: float = dx / actual_dx
				vel.x *= clampf(lerpf(1.0, scale_x, 0.75), 0.5, 2.0)

			# Adjust vertical velocity for landing height
			var t_flight: float = maxf(t_est, 0.1)
			vel.y += err_y / t_flight * 0.7

	# ── Ensure sufficient arc height (apex ≥ 2.0 m) ──────────────────────────────
	var spin_final: Vector3 = Vector3.ZERO
	if _game_node and _game_node.has_method("compute_shot_spin"):
		spin_final = _game_node.compute_shot_spin("", vel, charge, 1, 0)
	var apex: float = _simulate_apex_height(ball_pos, vel, spin_final)
	var target_apex: float = 2.0
	if apex < target_apex:
		# Boost vy to reach target apex, then re-converge landing
		var vy_min: float = sqrt(2.0 * grav * maxf(target_apex - ball_pos.y, 0.01))
		vel.y = maxf(vel.y, vy_min * 1.6)
		# Shrink horizontal speed so higher arc doesn't overshoot
		vel.x *= 0.88
		vel.z *= 0.88
		# Re-convergence with y-locked (only adjust horizontal)
		for _reconverge in range(20):
			if _game_node and _game_node.has_method("compute_shot_spin"):
				spin_final = _game_node.compute_shot_spin("", vel, charge, 1, 0)
			var landing2: Vector3 = _simulate_landing(ball_pos, vel, spin_final, true)
			var err_x2: float = tx - landing2.x
			var err_z2: float = tz - landing2.z
			if absf(err_x2) < 0.10 and absf(err_z2) < 0.10:
				break
			var actual_dx2: float = landing2.x - ball_pos.x
			var actual_dz2: float = landing2.z - ball_pos.z
			if absf(actual_dz2) > 0.03:
				var scale_z2: float = dz / actual_dz2
				vel.z *= clampf(scale_z2, 0.5, 2.0)
			if absf(actual_dx2) > 0.03:
				var scale_x2: float = dx / actual_dx2
				vel.x *= clampf(scale_x2, 0.5, 2.0)

	# Clamp to reasonable speed range
	var min_speed: float = 4.0
	var max_speed: float = 22.0
	var cur_speed: float = vel.length()
	if cur_speed < min_speed:
		vel = vel.normalized() * min_speed
	elif cur_speed > max_speed:
		vel = vel.normalized() * max_speed

	return vel
