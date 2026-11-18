class_name PlayerAIBrain extends Node
const WristReach = preload("res://scripts/paddle_wrist_reach.gd")
const PaddleDimensions = preload("res://scripts/paddle_dimensions.gd")
const PlannedGrip = preload("res://scripts/held_preparation_reach.gd")
const MotionContext = preload("res://scripts/rally_motion_context.gd")
const DriveMotion = preload("res://scripts/drive_serve_motion.gd")
const Movement = preload("res://scripts/ai_match_movement.gd")
const MatchTactics = preload("res://scripts/ai_match_tactics.gd")
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")


const _PC = preload("res://scripts/player.gd")

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


const AI_RECEIVE_X_TOLERANCE: = 0.25
const AI_RECEIVE_Z_TOLERANCE: = 0.2
const AI_WEAK_SERVE_SPEED_THRESHOLD: = 7.2
const AI_STRONG_SERVE_SPEED_THRESHOLD: = 11.2
const AI_WEAK_SERVE_FORWARD_BIAS: = 0.55
const AI_STRONG_SERVE_BACK_BIAS: = 0.7
const AI_FOREHAND_PREFERENCE: = 1.0
const AI_FORWARD_PREFERENCE: = 0.78
const AI_BACKHAND_PREFERENCE: = 0.55
const AI_OVERHEAD_PREFERENCE: = 0.92
const AI_LOW_FOREHAND_PREFERENCE: = 0.95
const AI_LOW_FORWARD_PREFERENCE: = 0.7
const AI_LOW_BACKHAND_PREFERENCE: = 0.45
const AI_WIDE_FOREHAND_PREFERENCE: = 0.62
const AI_WIDE_BACKHAND_PREFERENCE: = 0.28
const AI_VOLLEY_READY_PREFERENCE: = 0.7
const AI_MID_LOW_FOREHAND_PREFERENCE: = 0.9
const AI_MID_LOW_BACKHAND_PREFERENCE: = 0.45
const AI_MID_LOW_FORWARD_PREFERENCE: = 0.65
const AI_MID_LOW_WIDE_FOREHAND_PREFERENCE: = 0.48
const AI_MID_LOW_WIDE_BACKHAND_PREFERENCE: = 0.2
const AI_LOW_WIDE_FOREHAND_PREFERENCE: = 0.6
const AI_LOW_WIDE_BACKHAND_PREFERENCE: = 0.22
const AI_INTERCEPT_BODY_BACK_OFFSET: = 0.28
const AI_INTERCEPT_PADDLE_CLEARANCE: = 0.12
const AI_INTERCEPT_BODY_LATERAL_WEIGHT: = 0.2
const MEDIUM_OVERHEAD_TRIGGER_HEIGHT: = 1.05
const HIGH_OVERHEAD_TRIGGER_HEIGHT: = 1.4
const OVERHEAD_TRIGGER_RADIUS: = 1.7
const OVERHEAD_RELEASE_HEIGHT: = 0.62
const OVERHEAD_RELEASE_RADIUS: = 2.0
const JUMP_VELOCITY: = PickleballConstants.JUMP_VELOCITY
const JUMP_GRAVITY: = PickleballConstants.JUMP_GRAVITY
const _Ball: = preload("res://scripts/ball.gd")
const _Flight: = preload("res://scripts/ball_flight_predictor.gd")
const SMASH_FORCE_BONUS: = 1.35
const SMASH_DOWNWARD_BIAS: = 0.22
const AI_MARKER_HEIGHT: = 0.09
const AI_TARGET_RECOMMIT_DISTANCE: = 0.55
const AI_TARGET_POST_BOUNCE_RECOMMIT_DISTANCE: = 0.45
const AI_RECEIVE_MARKER_LANE_OFFSET: = 0.16
const AI_RECEIVE_MARKER_BOUNCE_PULL: = 0.72
const AI_HIT_COOLDOWN: = 0.16
const AI_HIT_CONTACT_WINDOW: = 0.34
const AI_CHARGE_DURATION: = 0.32
const AI_CHARGE_START_DISTANCE: = 2.4
const AI_TRAJECTORY_DURATION: = 0.6
const COURT_FLOOR_Y: = PickleballConstants.FLOOR_Y


enum AIState{
	INTERCEPT_POSITION, 
	CHARGING, 
	HIT_BALL, 
}

var ai_state: int = AIState.INTERCEPT_POSITION
var ai_desired_posture: int = 0
var ai_target_position: Vector3 = Vector3.ZERO
var ai_predicted_bounce_position: Vector3 = Vector3.ZERO
var ai_predicted_contact_position: Vector3 = Vector3.ZERO
var ai_selected_contact_reachable: bool = false
var ai_selected_contact_time: float = -1.0
var _charge_contact_position: Vector3 = Vector3.ZERO
var _charge_contact_deadline: float = -1.0
var _charge_contact_flight: int = -1
var last_contact_execution: Dictionary = {}
var _execution_commit_token: int = 0
var _execution_commit_flight: int = -1
var _execution_commit_active := false
var _execution_reaction_latency := -1.0
var _charge_target_position: Vector3 = Vector3.ZERO
var _charge_posture: int = PP_READY
var last_ai_contact_correction: float = 0.0

var last_ai_support_refresh_evidence: Dictionary = {}
var _last_support_attempt_tick: int = -1
var _exchange_align_head: = Vector3.ZERO
var _exchange_align_flight: = -1
var incoming_pose_override: PostureDefinition
var ai_reach_pose: PostureDefinition
var _charge_reach_pose: PostureDefinition
var last_kitchen_tactic: = "NORMAL"
var extra_reaction_delay: = 0.0
var _tactic_rng: = RandomNumberGenerator.new()
var playing_style_id: int = 0





var _ball_history: Array = []
var _observation_time: float = 0.0
var _observed_opponent: Vector3 = Vector3(0, 0, 6.0)
var _movement_plan: Dictionary = {}
var _movement_plan_due: float = 0.0
var last_match_tactic: String = "RETURN"
var last_match_shot: Dictionary = {}
var motion_context: Dictionary = {}
var _planned_shot: Dictionary = {}
var _planned_flight: int = -1
var _planned_bounces: int = -1
var _planned_contact_grip: PostureDefinition
var _observed_flight_id: int = -1
var _perception_ready: bool = false
# Availability of this callback's coherent opponent observation is separate
# from the already delayed, flight-bound Ball perception.
var _opponent_sample_available: bool = true
var _perceived_state: Dictionary = {}
var _predicted_flight: Dictionary = {}
var _predicted_flight_frame: int = -1
const REACTION_LATENCY_FRAMES_EASY: = 18
const REACTION_LATENCY_FRAMES_MED: = 12
const REACTION_LATENCY_FRAMES_HARD: = 8
var ai_committed_target_position: Vector3 = Vector3.ZERO
var ai_committed_bounce_position: Vector3 = Vector3.ZERO
var ai_committed_contact_position: Vector3 = Vector3.ZERO
var ai_hit_cooldown: float = 0.0
var ai_charge_time: float = 0.0
var ai_is_charging: bool = false
var ai_swing_threshold: float = 0.2
var ai_difficulty: int = 0
var ai_ball_bounced_on_side: bool = false
var _game_node = null
var ai_trajectory_mesh_instance: MeshInstance3D = null

var ai_trajectory_mesh: ImmediateMesh = null
var ai_trajectory_material: StandardMaterial3D = null
var ai_trajectory_timer: float = 0.0
var ai_movement_enabled: bool = true
var _ai_debug_frame: int = 0
var _ai_last_state: int = -1


var ai_target_indicator_position: Vector3 = Vector3.ZERO
var ai_bounce_indicator_position: Vector3 = Vector3.ZERO
var ai_contact_indicator_position: Vector3 = Vector3.ZERO

var _player

const OVERHEAD_PREFER_HEIGHT := 1.5   # m above the floor
const OVERHEAD_PREFERENCE := 0.35     # score bonus (score is roughly seconds to contact)

const LUNGE_ALLOWANCE := 0.45   # m of the final approach a lunge / reach covers

func _ready() -> void :
	_player = get_parent() as CharacterBody3D
	RuntimePolicy.seed_rng(_tactic_rng, 13)


func ground_velocity(input_dir: Vector3, delta: float) -> Vector3:
	_player.move_speed = Movement.speed(ai_difficulty)
	var desired: Vector3 = Movement.velocity(_player.current_velocity, input_dir, ai_target_position - _player.global_position, ai_difficulty, delta)
	var coordination = _team_coordination()
	return coordination.filter_ground_velocity(self, desired, delta) if coordination != null else desired

func _team_coordination():
	return _game_node.team_coordination if _game_node != null and "team_coordination" in _game_node else null

func get_ai_input(delta: float = -1.0) -> Vector3:
	var _pt := Time.get_ticks_usec()
	var _pr = _perf_get_ai_input(delta)
	PerfMonitor.record("ai.input", Time.get_ticks_usec() - _pt)
	return _pr

func _perf_get_ai_input(delta: float = -1.0) -> Vector3:
	var input_dir: Vector3 = Vector3.ZERO

	var ball: RigidBody3D = _player._get_ball_ref()

	if ball == null:
		return input_dir

	_update_foot_legality()


	_player.move_speed = Movement.speed(ai_difficulty)
	_sample_ball_history(ball, delta)

	var _ball_pos: Vector3 = ball.global_position
	var my_pos: Vector3 = _player.global_position
	var target_x: float = my_pos.x
	var target_z: float = my_pos.z


	if ball.has_method("get_last_hit_by") and ball.get_last_hit_by() == _player.player_num:
		ai_selected_contact_reachable = false
		ai_selected_contact_time = -1.0
		var coordination = _team_coordination()
		if coordination != null:
			return coordination.cover_input(self, coordination.advise(self, {}, delta))
		var ready_z: float = (_player.min_z + _player.max_z) * 0.6
		# Follow a soft ball/return toward a legal kitchen-line position. Keep the
		# server back until the compulsory return bounce has happened.
		if ball.both_bounces_complete or ball.serve_team != _player.player_num:
			var recovery_depth: float = 4.4 if last_match_tactic == "DRIVE" else PickleballConstants.NON_VOLLEY_ZONE + 0.75
			ready_z = (-1.0 if _player.court_side == 1 else 1.0) * recovery_depth
		var ready_x: float = 0.0
		var practice = _exchange_practice()
		if practice:
			var home: Vector3 = practice.get_exchange_home(_player.team_id)
			ready_x = home.x
			ready_z = home.z
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

	var predicted_landing: Vector3
	var intercept_solution: Dictionary
	if not _opponent_sample_available:
		if not _has_latched_observed_stroke(ball):
			ai_selected_contact_reachable = false
			ai_selected_contact_time = -1.0
			return input_dir
		# Continue only the actual previously captured stroke. Do not run a new
		# intercept/tactical choice using unavailable opponent observations.
		predicted_landing = ai_predicted_bounce_position
		intercept_solution = {"target": _charge_target_position, "contact": _charge_contact_position,
			"posture": _charge_posture, "def": _charge_reach_pose, "reachable": true,
			"time": maxf(0.0, _charge_contact_deadline - _observation_time)}
	else:
		predicted_landing = _predict_first_bounce_position(ball)
		# Reconsider foot travel at a human cadence; contact support may still track
		# continuously inside the physically reachable paddle envelope.
		# Perf: an intercept solve can cost ~25 ms (select_extended fallback). After a
		# hit every AI re-plans on the same tick, stacking into one long frame, so at
		# most one AI re-plans per physics tick; the others keep their plan (or hold
		# position) for a tick or two, like a slightly longer reaction.
		var tick: int = Engine.get_physics_frames()
		if (_movement_plan.is_empty() or _observation_time >= _movement_plan_due) and _intercept_slot_tick != tick:
			_intercept_slot_tick = tick
			_movement_plan = _get_ai_intercept_solution(predicted_landing)
			_movement_plan_due = _observation_time + Movement.REPLAN_SECONDS[clampi(ai_difficulty, 0, 2)]
			_movement_plan["observed_at"] = _observation_time
		if _movement_plan.is_empty():
			intercept_solution = {"target": _player.global_position, "posture": PP_READY, "contact": predicted_landing,
				"time": -1.0, "reachable": false, "observed_at": _observation_time, "deferred": true}
		else:
			intercept_solution = _movement_plan.duplicate()
		if float(intercept_solution.time) > 0.0:
			intercept_solution.time = maxf(0.0, float(intercept_solution.time) - (_observation_time - float(intercept_solution.observed_at)))
		if not intercept_solution.get("deferred", false): _retire_uncommitted_unreachable_charge(ball, intercept_solution)
	var coordination = _team_coordination()
	if coordination != null:
		var decision: Dictionary = coordination.advise(self, intercept_solution, delta)
		if not decision.pursue:
			ai_selected_contact_reachable = false
			ai_selected_contact_time = -1.0
			return coordination.cover_input(self, decision)
	var intercept_target: Vector3 = intercept_solution["target"] as Vector3
	ai_desired_posture = int(intercept_solution["posture"])
	ai_reach_pose = intercept_solution.get("def")
	var selected_contact: Vector3 = intercept_solution["contact"]
	ai_selected_contact_reachable = bool(intercept_solution["reachable"])
	ai_selected_contact_time = float(intercept_solution["time"])
	# Jump smash: a reachable High Overhead contact gets the same small jump the
	# human uses, timed by request_contextual_jump to peak at contact.
	if ai_selected_contact_reachable and ai_desired_posture == PP_HIGH_OVERHEAD and ai_reach_pose != null and not _player.is_jumping:
		_player.request_contextual_jump({"posture": PP_HIGH_OVERHEAD, "def": ai_reach_pose, "point": selected_contact,
			"time": ai_selected_contact_time, "bounces": ball.bounces_since_last_hit}, 1.0)
	if ai_is_charging and ai_state == AIState.CHARGING and _charge_contact_position != Vector3.ZERO:
		selected_contact = _charge_contact_position
		intercept_target = _charge_target_position
		ai_desired_posture = _charge_posture
		ai_reach_pose = _charge_reach_pose
		ai_selected_contact_reachable = true
		ai_selected_contact_time = maxf(0.0, _charge_contact_deadline - _observation_time)


	# Ordinary prediction and its movement/contact policy have priority. Special
	# actions see the same real flight only when that ordinary route is absent.
	if not ai_selected_contact_reachable:
		if _player.erne_action != null and _player.erne_action.maybe_start_ai(ball, _get_predicted_flight(ball), {"normal_reachable": false, "flight_id": ball.flight_id}):
			return Vector3.ZERO
		if _player.special_reach_driver != null and _player.special_reach_driver.maybe_start_ai():
			return Vector3.ZERO

	intercept_target.x = clamp(intercept_target.x, _player.min_x, _player.max_x)
	intercept_target.z = clamp(intercept_target.z, _player.min_z, _player.max_z)

	var paddle_target_position: Vector3 = intercept_target + _player._get_posture_offset_for(ai_desired_posture)



	var _state_changed: bool = ai_state != _ai_last_state
	_ai_debug_frame += 1
	if _state_changed or _ai_debug_frame >= 120:
		_ai_debug_frame = 0
		_ai_last_state = ai_state
		var _posture_name: String = _player.DEBUG_POSTURE_NAMES[ai_desired_posture] if ai_desired_posture < _player.DEBUG_POSTURE_NAMES.size() else "??"
		var _state_name: String = ["INTERCEPT", "CHARGING", "HIT"][ai_state] if ai_state < 3 else "??"
		if RuntimePolicy.developer_tools: print("[AI] %s %s | bodyZ=%.1f ballZ=%.1f tgtZ=%.1f p2b=%.1f ballY=%.2f bnc=%s bos=%s chg=%s" % [
			_state_name, _posture_name, my_pos.z, ball.global_position.z, 
			intercept_target.z, my_pos.distance_to(ball.global_position), 
			ball.global_position.y, ball.ball_bounced_since_last_hit, 
			ai_ball_bounced_on_side, ai_is_charging])


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


func _get_posture_for_height(rel_height: float) -> Array[int]:


	var candidates: Array[int] = []
	for def in PostureLibrary.instance().all_definitions():
		if def.has_zone and rel_height >= def.zone_y_min - 0.03 and rel_height <= def.zone_y_max + 0.03:
			candidates.append(def.posture_id)
	return candidates


static var _intercept_slot_tick: int = -1   # physics tick of the last AI intercept solve (any AI)

func _get_ai_intercept_solution(predicted_ball_pos: Vector3) -> Dictionary:
	var _pt := Time.get_ticks_usec()
	var _pr = _perf_get_ai_intercept_solution(predicted_ball_pos)
	PerfMonitor.record("ai.get_ai_intercept_solution", Time.get_ticks_usec() - _pt)
	return _pr

func _perf_get_ai_intercept_solution(predicted_ball_pos: Vector3) -> Dictionary:
	var ball: RigidBody3D = _player._get_ball_ref()
	var best_target: Vector3 = _player.global_position
	var best_score: float = INF
	var best_posture: int = PP_READY
	var best_contact: Vector3 = predicted_ball_pos
	var best_time: float = -1.0
	var flight: Dictionary = _get_predicted_flight(ball)
	var samples: Array = flight.get("samples", [])
	var bounce_origin: int = _observed_contact_bounces()
	if bounce_origin < 0 or bounce_origin >= 2 or not ball.is_in_play or ball.bounces_since_last_hit >= 2:
		return {"target": best_target, "posture": best_posture, "contact": best_contact, "time": -1.0, "reachable": false}
	# A read-only public ball-state view changes only the forecast's bounce base.
	# The extended planner must not add current live bounces to delayed samples.
	var forecast_ball := {"bounces_since_last_hit": bounce_origin, "is_in_play": ball.is_in_play,
		"last_hit_by": ball.last_hit_by, "last_hit_court_side": ball.last_hit_court_side,
		"both_bounces_complete": ball.both_bounces_complete, "global_position": ball.global_position,
		"linear_velocity": ball.linear_velocity, "wall_practice_active": ball.wall_practice_active,
		"wall_return_ready": ball.wall_return_ready, "BALL_RADIUS": ball.BALL_RADIUS}

	var zone_library: PostureLibrary = PostureLibrary.instance()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	var forward_axis: Vector3 = _player._get_forward_axis()
	var shoulder_offset: Vector3 = PaddleReach.shoulder_world(_player) - _player.global_position
	var move_speed: float = _player.move_speed
	var legal_after: float = 0.0
	if not ball.both_bounces_complete and bounce_origin == 0:
		legal_after = INF
		for bounce in flight.get("bounce_events", []):
			if _on_own_half(bounce["pos"]):
				legal_after = bounce["time"]
				break

	for sample_index in range(1, samples.size(), 3):
		var sample: Dictionary = samples[sample_index]
		var contact_point: Vector3 = sample["pos"]
		var contact_time: float = sample["time"]
		var total_bounces: int = bounce_origin + int(sample.get("bounces", 0))
		if total_bounces >= 2: continue
		var practice = _exchange_practice()
		if practice and practice.needs_bounce() and total_bounces == 0:
			continue
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
			if practice and practice.drill_mode == "HANDS":
				candidate_target.z = _outside_kitchen_depth(candidate_target.z, practice.HANDS_SAFE_Z)
				candidate_target.x = clampf(candidate_target.x, -0.14, 0.14)
			if total_bounces == 0:


				candidate_target.z = _outside_kitchen_depth(candidate_target.z, PickleballConstants.NON_VOLLEY_ZONE + 0.42)
			var travel_distance: float = Vector2(candidate_target.x - _player.global_position.x, 
				candidate_target.z - _player.global_position.z).length()
			var travel_direction: Vector3 = candidate_target - _player.global_position
			# Lunge allowance: the last ~0.45 m is covered by a lunge / arm reach,
			# not footwork (was 0.12 m). Over 5 bench matches the AI let balls hit
			# its body after falling short by only 0.12-0.51 m; the physical
			# contact check still decides whether the paddle really meets the ball.
			if travel_distance > Movement.travel_distance(_player.current_velocity, travel_direction, contact_time, ai_difficulty) + LUNGE_ALLOWANCE:
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


			var travel_fraction: float = travel_distance / maxf(move_speed * contact_time, 0.1)
			var score: float = contact_time + travel_fraction * 0.15 + travel_distance * 0.10 - _get_ai_posture_preference(posture) * 0.03
			# A small numerical prediction change must not make the body alternate
			# between running forward and backward on successive observations.
			if not _movement_plan.is_empty():
				score += candidate_target.distance_to(_movement_plan.target) * 0.18
			if _player.current_velocity.length() > 1.0 and _player.current_velocity.dot(travel_direction) < -0.10:
				score += 0.25


			if posture == ai_desired_posture: score -= 0.025
			# Take a high ball in the air when the rally allows it (both bounces
			# done): an overhead contact scores better, which opens the smash.
			# Without this the earliest-time score always let it drop low.
			if total_bounces == 0 and ball.both_bounces_complete and rel_height >= OVERHEAD_PREFER_HEIGHT:
				score -= OVERHEAD_PREFERENCE
			# Exact same ordering score; an uncompetitive candidate cannot win.
			# The skipped checks are pure geometry/dependency-cache work.
			if not score < best_score: continue

			var relative_contact: Vector3 = contact_point - candidate_target + _player.global_position
			if not preload("res://scripts/incoming_contact_planner.gd").point_fits(_player, def, relative_contact):
				continue
			var supported_shoulder: Vector3 = preload("res://scripts/stroke_body_pose.gd").shoulder_world(_player, def)
			var contact_wrist: Vector3 = WristReach.wrist_from_head(relative_contact, preload("res://scripts/stroke_swing_path.gd").paddle_basis(_player, def), def)
			# Keep a little arm room for a real paddle-face contact, rather than
			# planning an edge-of-reach graze that cannot be legally seated.
			if contact_wrist.distance_to(supported_shoulder) > WristReach.link_budget(_player, def) - 0.035:
				continue



			if score < best_score:
				best_score = score
				best_target = candidate_target
				best_posture = posture
				best_contact = contact_point
				best_time = contact_time

	if best_score == INF:
		var exchange = _exchange_practice()
		var extended: Dictionary = preload("res://scripts/incoming_contact_planner.gd").select_extended(_player, forecast_ball, flight, ai_desired_posture, exchange != null and exchange.needs_bounce())
		if not extended.is_empty():
			return {"target": _player.global_position, "posture": extended.posture, "contact": extended.point, 
				"time": extended.time, "reachable": true, "def": extended.def}
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


func _get_ai_posture_preference(posture: int) -> float:
	match posture:
		PP_FOREHAND: return AI_FOREHAND_PREFERENCE
		PP_FORWARD: return AI_FORWARD_PREFERENCE
		PP_BACKHAND: return AI_BACKHAND_PREFERENCE
		PP_MEDIUM_OVERHEAD: return AI_OVERHEAD_PREFERENCE
		PP_HIGH_OVERHEAD: return AI_OVERHEAD_PREFERENCE
		PP_LOW_FOREHAND: return AI_LOW_FOREHAND_PREFERENCE
		PP_LOW_FORWARD: return AI_LOW_FORWARD_PREFERENCE
		PP_LOW_BACKHAND: return AI_LOW_BACKHAND_PREFERENCE
		PP_WIDE_FOREHAND: return AI_WIDE_FOREHAND_PREFERENCE
		PP_WIDE_BACKHAND: return AI_WIDE_BACKHAND_PREFERENCE
		PP_VOLLEY_READY: return AI_VOLLEY_READY_PREFERENCE
		PP_MID_LOW_FOREHAND: return AI_MID_LOW_FOREHAND_PREFERENCE
		PP_MID_LOW_BACKHAND: return AI_MID_LOW_BACKHAND_PREFERENCE
		PP_MID_LOW_FORWARD: return AI_MID_LOW_FORWARD_PREFERENCE
		PP_MID_LOW_WIDE_FOREHAND: return AI_MID_LOW_WIDE_FOREHAND_PREFERENCE
		PP_MID_LOW_WIDE_BACKHAND: return AI_MID_LOW_WIDE_BACKHAND_PREFERENCE
		PP_LOW_WIDE_FOREHAND: return AI_LOW_WIDE_FOREHAND_PREFERENCE
		PP_LOW_WIDE_BACKHAND: return AI_LOW_WIDE_BACKHAND_PREFERENCE
		PP_READY:
			return 0.5
		PP_CHARGE_FOREHAND, PP_CHARGE_BACKHAND:
			return 0.0
	return 0.3





func _selected_reaction_seconds() -> float:
	var base: int = REACTION_LATENCY_FRAMES_MED
	if ai_difficulty == 0: base = REACTION_LATENCY_FRAMES_EASY
	elif ai_difficulty == 2: base = REACTION_LATENCY_FRAMES_HARD
	return base / 60.0 + clampf(extra_reaction_delay, 0.0, 0.5)

func _get_latency_frames() -> int:
	# A committed stroke cannot forget the already observed incoming ball
	# when the user changes difficulty while paused. New flights use the new setting.
	var seconds: float = _execution_reaction_latency if _execution_commit_active and _execution_commit_flight == _observed_flight_id else _selected_reaction_seconds()
	return roundi(seconds * Engine.physics_ticks_per_second)

func _sample_ball_history(ball: RigidBody3D, delta: float = -1.0) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_sample_ball_history(ball, delta)
	PerfMonitor.record("ai.sample_ball_history", Time.get_ticks_usec() - _pt)

func _perf_sample_ball_history(ball: RigidBody3D, delta: float = -1.0) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	var flight_id: int = ball.flight_id if ball is Ball else 0
	if _exchange_practice() and _execution_commit_active: cancel_execution_commit()
	if flight_id != _observed_flight_id:
		cancel_execution_commit()
		_observed_flight_id = flight_id
		_planned_shot = {}
		motion_context = {}
		_planned_flight = -1
		_planned_contact_grip = null
		MotionContext.clear_feet(_player)
		incoming_pose_override = PostureLibrary.instance().get_def(PP_READY) if ball.is_in_play and ball.last_hit_by != _player.player_num else null
		ai_reach_pose = null
		_charge_reach_pose = null
		_ball_history.clear()
		_observation_time = 0.0
		_movement_plan.clear()
		_movement_plan_due = 0.0
		_perception_ready = false
		_predicted_flight.clear()
		_predicted_flight_frame = -1
		ai_is_charging = false
		if not _player.hitting.is_in_follow_through and not _player.hitting.serving_visual_active:
			_player.hitting.charge_visual_active = false
		ai_charge_time = 0.0
		ai_selected_contact_reachable = false
		ai_selected_contact_time = -1.0
		_charge_contact_position = Vector3.ZERO
		_charge_target_position = Vector3.ZERO
	# Physics delta is scaled by focus. Counting rendered/physics frames instead
	# made a 0.30 s old sample advance 0.30 s even when only 0.02 s had passed.
	var step: float = 1.0 / float(Engine.physics_ticks_per_second) if delta < 0.0 else maxf(delta, 0.0)
	if not _ball_history.is_empty(): _observation_time += step
	_opponent_sample_available = true
	var opponent_position: Vector3 = _observed_opponent
	if _game_node != null:
		var coordination = _team_coordination()
		if coordination != null:
			var opponent_sample: Dictionary = coordination.opponent_centroid_for_frame(_player)
			if not bool(opponent_sample.get("valid", false)):
				# No fresh opponent row or new tactical choice is authorized here.
				# Existing same-flight Ball history still advances on its old clock.
				_opponent_sample_available = false
				_advance_recorded_ball_history()
				return
			opponent_position = opponent_sample.position
		else:
			# Singles has no doubles world snapshot; retain its existing path.
			var opponents: Array = _game_node.get_team_players(1 - _player.team_id)
			if not opponents.is_empty():
				opponent_position = Vector3.ZERO
				for opponent in opponents: opponent_position += opponent.global_position
				opponent_position /= float(opponents.size())
	_ball_history.append({"pos": ball.global_position, "vel": ball.linear_velocity, "omega": ball.angular_velocity,
		"time": _observation_time, "opponent": opponent_position, "bounces": ball.bounces_since_last_hit})
	_advance_recorded_ball_history()

func _advance_recorded_ball_history() -> void:
	# Empty history cannot establish readiness. Flight/reset admission already
	# clears it in the sampler; this helper never revives a canceled observation.
	if _ball_history.is_empty(): return
	var latency: float = _get_latency_frames() / float(Engine.physics_ticks_per_second)
	while _ball_history.size() > 1 and _observation_time - float(_ball_history[1].time) >= latency - 0.000001:
		_ball_history.pop_front()
	var oldest: Dictionary = _ball_history.front()
	var age: float = _observation_time - float(oldest.time)
	_perception_ready = age >= latency - 0.000001
	if not _perception_ready: return
	_perceived_state = _Flight.advance(oldest.pos, oldest.vel, oldest.omega, age)
	_observed_opponent = oldest.opponent
	_predicted_flight_frame = -1

func _perceived_ball_pos(ball: RigidBody3D) -> Vector3:
	return _perceived_state.get("pos", ball.global_position if ball else Vector3.ZERO)

func _perceived_ball_vel(ball: RigidBody3D) -> Vector3:
	return _perceived_state.get("vel", ball.linear_velocity if ball else Vector3.ZERO)

func _perceived_ball_omega(ball: RigidBody3D) -> Vector3:
	return _perceived_state.get("omega", ball.angular_velocity if ball else Vector3.ZERO)

func _observed_contact_bounces() -> int:
	if not _perception_ready or _ball_history.is_empty(): return -1
	var ball = _player._get_ball_ref()
	if ball == null or ball.flight_id != _observed_flight_id: return -1
	var base: int = int(_ball_history.front().get("bounces", -1))
	var advanced: int = int(_perceived_state.get("bounces", -1))
	if base < 0 or advanced < 0: return -1
	return base + advanced

func _get_predicted_flight(ball: RigidBody3D) -> Dictionary:
	var _pt := Time.get_ticks_usec()
	var _pr = _perf_get_predicted_flight(ball)
	PerfMonitor.record("ai.get_predicted_flight", Time.get_ticks_usec() - _pt)
	return _pr

func _perf_get_predicted_flight(ball: RigidBody3D) -> Dictionary:
	if ball == null:
		return {}
	var frame: int = Engine.get_physics_frames()
	if _predicted_flight_frame != frame or _predicted_flight.is_empty():
		_predicted_flight = _Flight.trace(_perceived_ball_pos(ball), _perceived_ball_vel(ball), 
			_perceived_ball_omega(ball), 3.0, 2, true)
		_predicted_flight_frame = frame
	return _predicted_flight

func _predict_first_bounce_position(ball: RigidBody3D) -> Vector3:
	var _pt := Time.get_ticks_usec()
	var _pr = _perf_predict_first_bounce_position(ball)
	PerfMonitor.record("ai.predict_first_bounce_position", Time.get_ticks_usec() - _pt)
	return _pr

func _perf_predict_first_bounce_position(ball: RigidBody3D) -> Vector3:
	var flight: Dictionary = _get_predicted_flight(ball)
	var bounce: Vector3 = flight.get("first_bounce", Vector3.ZERO)
	if bounce != Vector3.ZERO:
		return bounce
	var samples: Array = flight.get("samples", [])
	return samples.back()["pos"] if not samples.is_empty() else ball.global_position


func _commit_ai_target_position(new_target: Vector3) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_commit_ai_target_position(new_target)
	PerfMonitor.record("ai.commit_ai_target_position", Time.get_ticks_usec() - _pt)

func _perf_commit_ai_target_position(new_target: Vector3) -> void:
	var recommit_distance: float = AI_TARGET_POST_BOUNCE_RECOMMIT_DISTANCE
	if ai_committed_target_position == Vector3.ZERO or ai_committed_target_position.distance_to(new_target) >= recommit_distance:
		ai_committed_target_position = new_target
	else:
		ai_committed_target_position = ai_committed_target_position.lerp(new_target, 0.1)


var coordination_forward_progress: float = 0.0
var _pose_alignment_tick: = -1
var _pose_alignment_flight: = -1

func align_paddle_to_contact(delta: float) -> void :
	# Receipt describes this actual presentation call, never a prior flight.
	coordination_forward_progress = 0.0
	if not _player.is_ai or _player.paddle_node == null:
		incoming_pose_override = null
		return
	if _player.hitting.present_live_swing_physics(delta): return
	var ball: RigidBody3D = _player._get_ball_ref()
	if ball == null or not ball.is_in_play:
		incoming_pose_override = null
		return
	if _player.hitting.serving_visual_active: return
	var previous_support: PostureDefinition = incoming_pose_override if incoming_pose_override != null else _player.posture.capture_displayed_pose()
	# Legacy paddle-only tracking ran earlier in Player.physics. Restore the
	# actual owner before feet advance, so body fitting sees its seated grip.
	_player.posture.transition_pose_blend = previous_support
	_player.posture.force_posture_update(previous_support)
	var coordination = _team_coordination()
	if ball.get_last_hit_by() == _player.player_num or coordination != null and not coordination.may_begin_stroke(_player):
		if _player.hitting.is_in_follow_through or _player.hitting.serving_visual_active: return
		var ready: PostureDefinition = PostureLibrary.instance().get_def(PP_READY)
		var previous: PostureDefinition = incoming_pose_override if incoming_pose_override != null else _player.posture.capture_displayed_pose()
		ready = preload("res://scripts/incoming_ready_motion.gd").blend_pose(previous, ready, delta, .07)
		ready = preload("res://scripts/live_joint_preparation_path.gd").sample(_player, ready, previous, delta)
		incoming_pose_override = ready
		_player.posture.transition_pose_blend = ready
		_player.posture.force_posture_update(ready)
		return


	if not ai_selected_contact_reachable:
		if incoming_pose_override != null:
			_player.posture.transition_pose_blend = incoming_pose_override
			_player.posture.force_posture_update(incoming_pose_override)
		return
	var contact: Vector3 = ai_predicted_contact_position
	var base: PostureDefinition = ai_reach_pose if ai_reach_pose else PostureLibrary.instance().get_def(ai_desired_posture)
	if ai_selected_contact_time <= 0.35:
		# Retain the existing plan-selection clock and random sequence, but
		# capture its context before fitting the Contact endpoint this frame.
		_prepare_motion_plan(ball, base, contact)
	if ai_selected_contact_time <= 0.65 and preload("res://scripts/incoming_contact_planner.gd").point_fits(_player, base, contact):
		var intended: PostureDefinition = preload("res://scripts/incoming_contact_planner.gd").pose_at(_player, base, contact)
		if not motion_context.is_empty():
			intended = DriveMotion.sample_drive(intended, .5, float(motion_context.charge), bool(motion_context.is_volley), int(motion_context.spin_mode), bool(motion_context.near_kitchen), str(motion_context.shot_intent), motion_context)
		var compact_reception: bool = base.height_tier == 0 or str(motion_context.get("profile", "")) == "JAMMED"
		var preferred: PostureDefinition = _planned_contact_grip
		if compact_reception and preferred == null:
			preferred = incoming_pose_override if incoming_pose_override != null else _player.posture.capture_displayed_pose()
		_planned_contact_grip = PlannedGrip.fit_planned_contact_grip(_player, intended, preferred, compact_reception)
		base = base.duplicate(false)
		base.main_grip_rotation_deg = _planned_contact_grip.main_grip_rotation_deg
		if compact_reception and absf(float(_planned_contact_grip.get_meta("planned_live_grip_plane_deg", 0.0))) > .00001:
			for field in preload("res://scripts/paddle_rotation.gd").BASE + preload("res://scripts/paddle_rotation.gd").SIGNED:
				base.set(field, _planned_contact_grip.get(field))
	if ai_selected_contact_time <= 0.35:
		if not motion_context.is_empty():
			coordination_forward_progress = 0.5 * (1.0 - clampf(ai_selected_contact_time / 0.18, 0.0, 1.0))
			base = DriveMotion.sample_drive(base, coordination_forward_progress, float(motion_context.charge), bool(motion_context.is_volley), int(motion_context.spin_mode), bool(motion_context.near_kitchen), str(motion_context.shot_intent), motion_context)


	var tick: int = Engine.get_physics_frames()
	var pose_delta: float = delta if tick != _pose_alignment_tick or ball.flight_id != _pose_alignment_flight else 0.0
	_pose_alignment_tick = tick
	_pose_alignment_flight = ball.flight_id
	if ai_selected_contact_time > 0.35 and ball.global_position.distance_to(contact) > 0.75:


		var ready: PostureDefinition = PostureLibrary.instance().get_def(PP_READY)
		var prepare: PostureDefinition = preload("res://scripts/incoming_ready_motion.gd").prepare(base, ready, ai_selected_contact_time, ball.bounces_since_last_hit == 0, absf(_player.global_position.z) <= PickleballConstants.NON_VOLLEY_ZONE + 0.65)
		var previous_preparation: PostureDefinition = incoming_pose_override if incoming_pose_override else ready
		incoming_pose_override = preload("res://scripts/incoming_ready_motion.gd").blend_pose(incoming_pose_override if incoming_pose_override else ready, prepare, pose_delta)
		incoming_pose_override = preload("res://scripts/live_joint_preparation_path.gd").sample(_player, incoming_pose_override, previous_preparation, pose_delta)
		_player.posture.transition_pose_blend = incoming_pose_override
		_player.posture.force_posture_update(incoming_pose_override)
		_player.hitting.charge_visual_active = false
		_exchange_align_flight = -1
		return

	if ai_selected_contact_time <= maxf(delta, 0.0) and ball.global_position.distance_to(contact) < 0.55 and preload("res://scripts/incoming_contact_planner.gd").point_fits(_player, base, ball.global_position):
		contact = ball.global_position
	var shoulder: Vector3 = PaddleReach.shoulder_world(_player)
	if shoulder.distance_to(contact) > PaddleReach.MAX_HEAD_DISTANCE + 0.05:
		return
	var head: Vector3 = PaddleReach.head_world(_player)
	if _exchange_align_flight != ball.flight_id:
		_exchange_align_flight = ball.flight_id
		_exchange_align_head = head
	head = _exchange_align_head
	var target_head: Vector3 = PaddleReach.clamp_head_with_floor(contact, shoulder, 
		_player.COURT_FLOOR_Y + 0.06)
	var rate: float = 42.0 if ball.global_position.distance_to(contact) < 0.55 else 22.0
	var blend: float = 1.0 - exp( - maxf(delta, 0.0) * rate)
	var aligned: Vector3 = head.lerp(target_head, blend)
	# A low reception passes the handle around the planted front thigh.
	# The small approach arc is zero before the physical Contact deadline.
	var approach_offset := Vector3.ZERO
	if str(motion_context.get("profile", "")) == "HALF_VOLLEY" and ai_selected_contact_time > .033333333333333 and ai_selected_contact_time < .20:
		var approach_phase: float = (.20 - ai_selected_contact_time) / (.20 - .033333333333333)
		approach_offset = _player._get_forward_axis() * (.04 * sin(PI * approach_phase))
		aligned += approach_offset



	base = preload("res://scripts/incoming_ready_motion.gd").blend_pose(incoming_pose_override, base, pose_delta, 0.035)


	var wrist_offset: Vector3 = WristReach.head_to_wrist_offset(preload("res://scripts/stroke_swing_path.gd").paddle_basis(_player, base), base)
	var supported_shoulder: Vector3 = preload("res://scripts/stroke_body_pose.gd").shoulder_world(_player, base)
	var wrist_delta: Vector3 = aligned + wrist_offset - supported_shoulder
	var preparation_budget: float = maxf(0.0, WristReach.link_budget(_player, base) - 0.002)
	if wrist_delta.length() > preparation_budget:
		aligned = supported_shoulder + wrist_delta.normalized() * preparation_budget - wrist_offset
	_exchange_align_head = aligned
	var pose: PostureDefinition = preload("res://scripts/incoming_contact_planner.gd").pose_at(_player, base, aligned)
	pose = preload("res://scripts/live_joint_preparation_path.gd").sample(_player, pose, incoming_pose_override, pose_delta)
	aligned = preload("res://scripts/stroke_swing_path.gd").world_transform(_player, pose) * PaddleDimensions.HEAD_OFFSET
	_exchange_align_head = aligned - approach_offset
	pose.set_meta("live_approach_offset", approach_offset)
	incoming_pose_override = pose
	_player.hitting.charge_visual_active = false
	_player.posture.transition_pose_blend = pose
	_player.posture.force_posture_update(pose)
	_player.paddle_node.global_position = aligned - _player.paddle_node.global_transform.basis.y * PaddleDimensions.HEAD_CENTER_Y
func _ball_at_reachable_indicator(ball: RigidBody3D) -> bool:
	if not ai_selected_contact_reachable or not _on_own_half(ball.global_position):
		return false
	if ball.global_position.y < _Flight.FLOOR_REST_Y + 0.015:
		return false
	if ball.global_position.distance_to(ai_predicted_contact_position) > AI_HIT_CONTACT_WINDOW:
		return false
	return PaddleReach.shoulder_world(_player).distance_to(ball.global_position) <= PaddleReach.MAX_HEAD_DISTANCE + 0.03

func _place_paddle_head_at_ball(ball: RigidBody3D) -> void :
	last_ai_contact_correction = PaddleReach.head_world(_player).distance_to(ball.global_position)
	var offset: Vector3 = _player.paddle_node.global_transform.basis.y * PaddleDimensions.HEAD_CENTER_Y
	var contact: Vector3 = PaddleReach.clamp_head_with_floor(ball.global_position, 
		PaddleReach.shoulder_world(_player), _player.COURT_FLOOR_Y + 0.06)
	_player.paddle_node.global_position = contact - offset

func _on_hitbox_body_entered(_body: Node3D, _paddle: StaticBody3D) -> void :



	pass

func _refresh_raw_contact_support(ball: RigidBody3D) -> void :



	if not _player.is_ai or not _perception_ready or not ai_is_charging or ai_hit_cooldown > 0.0: return
	if not ball.is_in_play or ball.last_hit_by == _player.player_num or ball.flight_id != _observed_flight_id: return
	if not _on_own_half(ball.global_position) or ball.bounces_since_last_hit >= 2: return
	if not ball.both_bounces_complete and not ball.ball_bounced_since_last_hit: return
	var tick: int = Engine.get_physics_frames()
	if _last_support_attempt_tick == tick: return
	var raw_paddle: Transform3D = _player.paddle_node.global_transform
	var raw_ball: Vector3 = ball.global_position
	var geometry = preload("res://scripts/paddle_clearance.gd")
	var raw_gap: float = geometry.distance_to_head_shape(raw_paddle.affine_inverse() * raw_ball) - _Ball.BALL_RADIUS
	if raw_gap > geometry.contact_surface_tolerance(): return
	var pose: PostureDefinition = _active_contact_pose()
	var raw_shoulder: Vector3 = WristReach.live_shoulder(_player, pose)
	var raw_wrist_distance: float = WristReach.wrist_world(raw_paddle, pose).distance_to(raw_shoulder)
	var raw_velocity: Vector3 = ball.linear_velocity
	_last_support_attempt_tick = tick
	var refreshed: bool = _player.refresh_contact_support(pose)
	last_ai_support_refresh_evidence = {"physics_tick": tick, "flight": ball.flight_id, 
		"raw_paddle": raw_paddle, "raw_ball": raw_ball, "raw_velocity": raw_velocity, "raw_head_gap": raw_gap, 
		"raw_shoulder": raw_shoulder, "raw_wrist_distance": raw_wrist_distance, 
		"refreshed": refreshed, "after_paddle": _player.paddle_node.global_transform, 
		"after_ball": ball.global_position, "after_velocity": ball.linear_velocity, "after_shoulder": WristReach.live_shoulder(_player, pose), 
		"after_wrist_distance": WristReach.wrist_world(_player.paddle_node.global_transform, pose).distance_to(WristReach.live_shoulder(_player, pose))}

var _contact_sweep: Dictionary = {}
var last_swept_contact_evidence: Dictionary = {}

func _try_ai_hit_ball() -> void:
	_try_ai_hit_ball_owned()
	_publish_two_phase_intent()
	var ball = _player._get_ball_ref()
	_contact_sweep = {}
	if ball == null or not ball.is_in_play or ball.last_hit_by == _player.player_num: return
	if incoming_pose_override == null or _player.paddle_node == null: return
	_contact_sweep = {"ball": ball.global_position, "paddle": _player.paddle_node.global_transform,
		"pose": incoming_pose_override.duplicate(false), "flight": ball.flight_id,
		"bounces": ball.bounces_since_last_hit, "tick": Engine.get_physics_frames()}

func _contact_sweep_valid(ball) -> bool:
	return not _contact_sweep.is_empty() and int(_contact_sweep.tick) == Engine.get_physics_frames() - 1 \
		and int(_contact_sweep.flight) == ball.flight_id and int(_contact_sweep.bounces) == ball.bounces_since_last_hit \
		and incoming_pose_override != null

func _try_swept_ai_contact(ball, delta: float, charge: float) -> bool:
	if _game_node.contact_authority != null and _game_node.contact_authority.uses_two_phase_contact(_player): return false
	if delta <= 0.0 or not _contact_sweep_valid(ball): return false
	var finite = preload("res://scripts/finite_paddle_contact.gd")
	var path = preload("res://scripts/stroke_swing_path.gd")
	var endpoint: PostureDefinition = incoming_pose_override
	var current_ball: Vector3 = ball.global_position
	var current_paddle: Transform3D = _player.paddle_node.global_transform
	# Preview tolerance must not pull a full-extension contact outward. Use
	# the earliest physical sphere/head contact inside this same interval.
	var fraction: float = finite.physical_sweep_fraction(_contact_sweep.ball, current_ball, _contact_sweep.paddle, current_paddle, ball.BALL_RADIUS)
	if fraction < 0.0:
		last_swept_contact_evidence = {"no_sweep": true, "ball_from": _contact_sweep.ball, "ball_to": current_ball}
		return false
	var swept: Transform3D = finite.interpolate_head_transform(_contact_sweep.paddle, current_paddle, fraction)
	var pose: PostureDefinition = path.blend_pose(endpoint, _contact_sweep.pose, 1.0 - fraction)
	pose = preload("res://scripts/paddle_pose_encoding.gd").encode(_player, pose, swept)
	incoming_pose_override = pose
	_player.posture.transition_pose_blend = pose
	_player.posture.force_posture_update(pose)
	ball.global_position = Vector3(_contact_sweep.ball).lerp(current_ball, fraction)
	last_swept_contact_evidence = {"swept": true, "fraction": fraction, "full_delta": delta, "ball_from": _contact_sweep.ball,
		"ball_to": current_ball, "paddle_from": _contact_sweep.paddle, "paddle_to": current_paddle, "swept_paddle": swept}
	var actual: Transform3D = _player.paddle_node.global_transform
	var reproduced: bool = actual.origin.distance_to(swept.origin) <= .0001 and actual.basis.x.distance_to(swept.basis.x) <= .0001 and actual.basis.y.distance_to(swept.basis.y) <= .0001 and actual.basis.z.distance_to(swept.basis.z) <= .0001
	var incoming_flight: int = ball.flight_id
	var callback_epoch: int = ball.contact_callback_epoch()
	if reproduced: _apply_ai_hit(ball, charge, last_swept_contact_evidence)
	else: last_swept_contact_evidence["reject"] = "reproduction"
	if callback_epoch != ball.contact_callback_epoch(): return false
	var accepted: bool = ball.flight_id != incoming_flight and ball.last_hit_by == _player.player_num
	incoming_pose_override = endpoint
	_player.posture.transition_pose_blend = endpoint
	_player.posture.force_posture_update(endpoint)
	if not accepted:
		ball.global_position = current_ball
		return false
	if not _player.hitting._live_swing_presentation.is_empty():
		_player.hitting._live_swing_presentation.presented = endpoint
	var authority = _game_node.contact_authority
	if authority != null:
		authority.capture_remainder_endpoint()
		last_swept_contact_evidence["remainder"] = authority.continue_paddle_remainder(_player, delta, fraction)
	return true

func _try_ai_hit_ball_owned() -> void :
	var coordination = _team_coordination()
	if coordination != null and not coordination.may_begin_stroke(_player): return
	if not _player.is_ai or not _perception_ready or _player.paddle_hitbox == null or ai_hit_cooldown > 0.0:
		return
	var ball: RigidBody3D = _player._get_ball_ref()
	if ball == null:
		return
	if ball.get_last_hit_by() == _player.player_num:
		return

	if not _opponent_sample_available and not _has_latched_observed_stroke(ball): return

	var practice = _exchange_practice()
	if practice and practice.needs_bounce() and not ball.ball_bounced_since_last_hit:
		return



	var can_volley_now: bool = ball.both_bounces_complete
	if not can_volley_now and not ai_ball_bounced_on_side:
		return


	if not ball.both_bounces_complete and not ball.ball_bounced_since_last_hit:
		return

	_refresh_raw_contact_support(ball)



	if not ball.ball_bounced_since_last_hit and not _feet_established_outside_kitchen():
		return

	var paddle_distance: float = PaddleReach.head_world(_player).distance_to(ball.global_position)




	if not ai_is_charging and not _charge_reentry_blocked_by_recovery_offer(ball) and _on_own_half(ball.global_position) and (paddle_distance <= AI_CHARGE_START_DISTANCE
			or ai_selected_contact_reachable and ball.global_position.distance_to(ai_predicted_contact_position) < 1.2):
		ai_is_charging = true
		ai_charge_time = 0.0
		ai_state = AIState.CHARGING
		_charge_contact_position = ai_predicted_contact_position
		_charge_contact_deadline = _observation_time + maxf(ai_selected_contact_time, 0.0)
		_charge_contact_flight = ball.flight_id
		_charge_target_position = ai_committed_target_position
		_charge_posture = ai_desired_posture
		_charge_reach_pose = ai_reach_pose

		match ai_difficulty:
			0:
				if randf() < 0.6:
					ai_swing_threshold = randf_range(0.35, 0.55)
				else:
					ai_swing_threshold = randf_range(0.55, 0.75)
			1:
				if randf() < 0.4:
					ai_swing_threshold = randf_range(0.4, 0.6)
				else:
					ai_swing_threshold = randf_range(0.6, 0.8)
			2:
				if randf() < 0.35:
					ai_swing_threshold = randf_range(0.5, 0.7)
				else:
					ai_swing_threshold = randf_range(0.7, 0.9)
		if practice: ai_swing_threshold = 0.25


		if incoming_pose_override == null:
			if _player.ai_desired_posture in _player.BACKHAND_POSTURES:
				var _is_low_bh: bool = (
					_player.ai_desired_posture == PP_LOW_BACKHAND or 
					_player.ai_desired_posture == PP_LOW_WIDE_BACKHAND or 
					_player.ai_desired_posture == PP_MID_LOW_BACKHAND or 
					_player.ai_desired_posture == PP_MID_LOW_WIDE_BACKHAND
				)
				if not _is_low_bh:
					_player.paddle_posture = PP_CHARGE_BACKHAND

			elif _player.ai_desired_posture in _player.FOREHAND_POSTURES:


				var _is_low: bool = (
					_player.ai_desired_posture == PP_LOW_FOREHAND or 
					_player.ai_desired_posture == PP_LOW_WIDE_FOREHAND or 
					_player.ai_desired_posture == PP_MID_LOW_FOREHAND or 
					_player.ai_desired_posture == PP_MID_LOW_WIDE_FOREHAND
				)
				if not _is_low:
					_player.paddle_posture = PP_CHARGE_FOREHAND

			else:

				_player.paddle_posture = PP_CHARGE_FOREHAND


	if ai_is_charging:
		var delta: float = get_physics_process_delta_time()
		ai_charge_time += delta
		var charge_ratio: float = clamp(ai_charge_time / AI_CHARGE_DURATION, 0.0, 1.0)


		if incoming_pose_override == null and ai_selected_contact_time > 0.3 and ball.global_position.distance_to(ai_predicted_contact_position) > 0.75:
			_player.set_serve_charge_visual(charge_ratio)
		if _pose_alignment_tick != Engine.get_physics_frames() or _pose_alignment_flight != ball.flight_id:
			align_paddle_to_contact(delta)
		_refresh_raw_contact_support(ball)


		# A valid physical interval owns its earliest contact. A later endpoint
		# overlap cannot retry an earlier rejected body/anatomy intersection.
		if _contact_sweep_valid(ball):
			_try_swept_ai_contact(ball, delta, charge_ratio)
			return

		var ready_to_swing: bool = charge_ratio >= ai_swing_threshold
		var close_enough: bool = paddle_distance <= 0.3
		var ball_very_close: bool = paddle_distance <= 0.18

		var at_indicator: bool = _ball_at_reachable_indicator(ball)


		paddle_distance = PaddleReach.head_world(_player).distance_to(ball.global_position)
		close_enough = _exchange_surface_contact(ball)
		ball_very_close = close_enough
		at_indicator = at_indicator and close_enough
		if (ready_to_swing and close_enough) or ball_very_close or at_indicator:
			_apply_ai_hit(ball, charge_ratio)
			return


		if charge_ratio >= 1.0 and paddle_distance > AI_CHARGE_START_DISTANCE:
			cancel_execution_commit()
			ai_is_charging = false
			_player.hitting.charge_visual_active = false
			ai_charge_time = 0.0
			ai_state = AIState.INTERCEPT_POSITION
			_charge_contact_position = Vector3.ZERO
			_charge_target_position = Vector3.ZERO


	if ai_ball_bounced_on_side or can_volley_now:
		var overlapping_bodies: Array[Node3D] = _player.paddle_hitbox.get_overlapping_bodies()
		for body in overlapping_bodies:
			if body == ball:
				if not ai_is_charging:
					ai_is_charging = true
					ai_charge_time = AI_CHARGE_DURATION * 0.5
				_apply_ai_hit(ball, clamp(ai_charge_time / AI_CHARGE_DURATION, 0.0, 1.0))
				return

func _apply_ai_hit(body: Node3D, charge_ratio: float = 0.55, contact_evidence: Dictionary = {}) -> bool :
	if _game_node.contact_authority != null and _game_node.contact_authority.uses_two_phase_contact(_player): return false
	if ai_hit_cooldown > 0.0:
		last_swept_contact_evidence["reject"] = "cooldown"
		return false
	if not (body is RigidBody3D):
		last_swept_contact_evidence["reject"] = "not_ball"
		return false
	if body.has_method("get_last_hit_by") and body.get_last_hit_by() == _player.player_num:
		last_swept_contact_evidence["reject"] = "own_outgoing"
		return false
	_refresh_raw_contact_support(body)


	if not preload("res://scripts/incoming_contact_planner.gd").legal_contact(_player, body):
		last_swept_contact_evidence["reject"] = "illegal_contact"
		return false
	if body.flight_id != _observed_flight_id:
		last_swept_contact_evidence["reject"] = "unobserved_flight"
		return false
	var practice = _exchange_practice()
	var active_pose: PostureDefinition = _active_contact_pose()
	if not body.is_in_play or not _on_own_half(body.global_position) or not _exchange_surface_contact(body, active_pose):
		last_swept_contact_evidence["reject"] = "not_finite_contact"
		return false
	if not body.ball_bounced_since_last_hit and ( not body.both_bounces_complete or not _feet_established_outside_kitchen()):
		last_swept_contact_evidence["reject"] = "illegal_volley"
		return false
	if practice: charge_ratio = 0.25
	var surface_pose: PostureDefinition = preload("res://scripts/paddle_clearance.gd").contact_surface_pose(_player, active_pose, body.global_position, body.linear_velocity, WristReach.live_shoulder(_player, active_pose))
	if surface_pose == null:
		last_swept_contact_evidence["reject"] = "unreachable_seating"
		last_swept_contact_evidence["reach"] = WristReach.wrist_world(_player.paddle_node.global_transform, active_pose).distance_to(WristReach.live_shoulder(_player, active_pose))
		last_swept_contact_evidence["actual"] = _player.paddle_node.global_transform
		last_swept_contact_evidence["expected"] = preload("res://scripts/stroke_swing_path.gd").world_transform(_player, active_pose)
		last_swept_contact_evidence["rig"] = preload("res://scripts/live_arm_budget.gd").displayed_report(_player)
		return false
	_player.posture.transition_pose_blend = surface_pose
	_player.posture.force_posture_update(surface_pose)


	if not _exchange_surface_contact(body, surface_pose):
		_player.posture.transition_pose_blend = active_pose
		_player.posture.force_posture_update(active_pose)
		last_swept_contact_evidence["reject"] = "seating_not_finite"
		return false
	if "contact_authority" in _game_node and _game_node.contact_authority != null:
		if not _game_node.contact_authority.before_paddle(_player, contact_evidence):
			last_swept_contact_evidence["reject"] = "earlier_surface_or_rig"
			return false
	# A reach refresh may leave desired posture at READY even while the
	# accepted finite contact is LOW/WIDE. Recovery starts from that real pose.
	_player.ai_desired_posture = surface_pose.posture_id
	incoming_pose_override = surface_pose
	var contact_transform: Transform3D = _player.paddle_node.global_transform


	# Solve before starting a committed motion. The accepted launch plan is
	# shared by this contact, follow-through and the planted-foot controller.
	var charge: float = clamp(ai_charge_time / AI_CHARGE_DURATION, 0.05, 1.0)
	var ai_paddle_vel: Vector3 = _player.hitting.get_paddle_velocity().limit_length(15.0)
	var paddle_pos: Vector3 = _player.global_position + _player._get_posture_offset_for(_player.ai_desired_posture)
	var launch: Dictionary = _game_node.solve_ai_launch(body.global_position, charge,
		_player.ai_desired_posture, paddle_pos, ai_paddle_vel, _player.hitting.PADDLE_VEL_TRANSFER, _player)
	if launch.is_empty():
		last_swept_contact_evidence["reject"] = "no_physical_launch"
		return false
	var accepted: Dictionary = launch.get("motion_plan", {"kind": str(launch.get("tactic", "")),
		"charge": charge_ratio, "intent": str(launch.get("profile", {}).get("shot_intent", "AUTO")),
		"shot_type": str(launch.get("profile", {}).get("shot_type", "GROUNDSTROKE")),
		"target": launch.get("target", body.global_position), "arc": 0.0})
	if not _same_motion_plan(motion_context, accepted):
		motion_context = _capture_plan_context(body, surface_pose, body.global_position, 0.0, accepted)
	# Compare the actual TOI clock with the incoming flight's predicted
	# deadline. Preserve signed lateness and the consumed subframe fraction.
	var timing_error := -maxf(ai_selected_contact_time, 0.0)
	if _charge_contact_flight == body.flight_id and _charge_contact_deadline >= 0.0:
		timing_error = _observation_time - _charge_contact_deadline
	if contact_evidence.get("swept", false):
		timing_error -= (1.0 - float(contact_evidence.fraction)) * float(contact_evidence.get("full_delta", 0.0))
	# Cooperative exchanges keep their scripted feeds and consume no error draw.
	if not practice and _game_node.has_method("apply_contact_execution"):
		_commit_execution_for_motion(body)
		launch = _game_node.apply_contact_execution(_player, launch, float(motion_context.charge), timing_error, false)
		last_contact_execution = {"incoming_flight": body.flight_id, "commit_token": _execution_commit_token, "rng_draw_count": _game_node.shot_physics.accuracy.samples, "deadline": _charge_contact_deadline,
			"observation_time": _observation_time, "fraction": contact_evidence.get("fraction", 1.0),
			"full_delta": contact_evidence.get("full_delta", 0.0), "timing_error_seconds": timing_error,
			"profile": launch.get("profile", {}).duplicate(true)}
	_player.hitting.committed_motion_context = motion_context
	MotionContext.apply_feet(_player, motion_context)
	_player.animate_serve_release(float(motion_context.charge))
	_player.paddle_node.global_transform = contact_transform
	body.suppress_paddle_collision(_player.paddle_node)
	if _player.posture: _player.posture.notify_ball_hit()
	if launch.has("profile"):
		launch["profile"] = launch.profile.duplicate(true)
		launch.profile["motion_profile"] = motion_context.profile
	var shot_velocity: Vector3 = launch["velocity"]
	body.linear_velocity = shot_velocity
	body.angular_velocity = launch["omega"]
	var shot_impulse: Vector3 = shot_velocity.normalized()
	var event: Dictionary = {}
	if body.has_method("hit_by_player"):
		var recorded: bool = body.hit_by_actor(_player) if body.has_method("hit_by_actor") else body.hit_by_player(_player.player_num)
		if not recorded: return false
		event = body.paddle_contact_context()
		_player.set_meta("legal_net_followthrough_flight", body.flight_id)
		if "contact_authority" in _game_node and _game_node.contact_authority: _game_node.contact_authority.note_paddle_contact(_player)
	var stamina_kind: String = str(launch.get("tactic", launch.get("profile", {}).get("shot_type", "")))
	_player.stamina.spend_contact(stamina_kind, shot_velocity.length())
	ai_hit_cooldown = AI_HIT_COOLDOWN
	_player.hit_ball.emit(body, shot_impulse.normalized())
	if not event.is_empty() and not body.paddle_contact_is_current(event): return false


	ai_is_charging = false
	ai_charge_time = 0.0
	_charge_contact_position = Vector3.ZERO
	_charge_target_position = Vector3.ZERO
	ai_ball_bounced_on_side = false
	ai_state = AIState.INTERCEPT_POSITION
	if RuntimePolicy.developer_tools: print("[BOS] reset by _apply_ai_hit")

	_draw_ai_trajectory(body.global_position, body.linear_velocity, body.angular_velocity)

	return true

func _setup_ai_trajectory() -> void :
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

func _draw_ai_trajectory(ball_pos: Vector3, ball_vel: Vector3, spin: Vector3) -> void :
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

func _update_ai_trajectory_fade(delta: float) -> void :
	if ai_trajectory_timer > 0.0:
		ai_trajectory_timer -= delta
		if ai_trajectory_timer <= 0.0 and ai_trajectory_mesh_instance != null:
			ai_trajectory_mesh_instance.visible = false





func _simulate_landing(pos: Vector3, vel: Vector3, omega: Vector3, detect_net: bool = true) -> Vector3:
	var _pt := Time.get_ticks_usec()
	var _pr = _perf_simulate_landing(pos, vel, omega, detect_net)
	PerfMonitor.record("ai.simulate_landing", Time.get_ticks_usec() - _pt)
	return _pr

func _perf_simulate_landing(pos: Vector3, vel: Vector3, omega: Vector3, detect_net: bool = true) -> Vector3:
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



func _pick_ai_target_in_service_box(difficulty: int, _charge: float) -> Vector2:
	var NON_VOLLEY_ZONE: float = 2.134
	var COURT_WIDTH_HALF: float = 3.05
	var COURT_LENGTH_HALF: float = 6.7
	var min_z: float = NON_VOLLEY_ZONE + 0.3
	var max_z: float = COURT_LENGTH_HALF - 0.3
	var lateral_range: float = COURT_WIDTH_HALF * 0.8
	var tx: float = randf_range( - lateral_range, lateral_range)
	var tz: float = randf_range(min_z, max_z)

	if difficulty == 2:
		tx = signf(tx) * (COURT_WIDTH_HALF * 0.7)
		tz = randf_range(min_z + 1.0, max_z - 0.5)

	elif difficulty == 0:
		tx *= 0.4
		tz = lerpf(min_z + 0.5, max_z - 0.5, 0.5)
	return Vector2(tx, tz * (1.0 if _player.court_side == 1 else -1.0))



func compute_ai_shot_velocity(ball_pos: Vector3, charge: float, difficulty: int, override_target: Vector2 = Vector2( - INF, - INF)) -> Vector3:
	return _compute_ai_shot_velocity(ball_pos, charge, difficulty, override_target)


func _compute_ai_shot_velocity(ball_pos: Vector3, charge: float, difficulty: int, override_target: Vector2 = Vector2( - INF, - INF)) -> Vector3:
	var target: Vector2
	if override_target.x > - INF:
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


	var vy: float = (0.5 * grav * t_est * t_est + 1.0) / maxf(t_est, 0.01)
	var vx: float = dx / maxf(t_est, 0.01)
	var vz: float = dz / maxf(t_est, 0.01)
	var vel: Vector3 = Vector3(vx, vy, vz)


	for _iter in range(30):

		var spin: Vector3 = Vector3.ZERO
		if _game_node and _game_node.has_method("compute_shot_spin"):
			spin = _game_node.compute_shot_spin("", vel, charge, 1, 0)

		var landing: Vector3 = _simulate_landing(ball_pos, vel, spin, true)
		var err_x: float = tx - landing.x
		var err_z: float = tz - landing.z
		var err_y: float = 0.08 - landing.y


		var net_h: float = _simulate_net_height(ball_pos, vel, spin, 0.0)
		var net_ok: bool = net_h >= 1.0 or net_h == INF


		if absf(err_x) < 0.06 and absf(err_z) < 0.06 and absf(err_y) < 0.02 and net_ok:
			break


		if not net_ok and net_h != INF:
			var t_net: float = maxf(absf(ball_pos.z) / maxf(absf(vel.z), 0.1), 0.1)
			var vy_needed: float = (1.2 - ball_pos.y + 0.5 * grav * t_net * t_net) / t_net
			vel.y = maxf(vel.y, vy_needed * 1.3)

			vel.x *= 0.98
			vel.z *= 0.98
		else:

			var actual_dx: float = landing.x - ball_pos.x
			var actual_dz: float = landing.z - ball_pos.z
			if absf(actual_dz) > 0.03:
				var scale_z: float = dz / actual_dz
				vel.z *= clampf(lerpf(1.0, scale_z, 0.75), 0.5, 2.0)
			if absf(actual_dx) > 0.03:
				var scale_x: float = dx / actual_dx
				vel.x *= clampf(lerpf(1.0, scale_x, 0.75), 0.5, 2.0)


			var t_flight: float = maxf(t_est, 0.1)
			vel.y += err_y / t_flight * 0.7


	var spin_final: Vector3 = Vector3.ZERO
	if _game_node and _game_node.has_method("compute_shot_spin"):
		spin_final = _game_node.compute_shot_spin("", vel, charge, 1, 0)
	var apex: float = _simulate_apex_height(ball_pos, vel, spin_final)
	var target_apex: float = 2.0
	if apex < target_apex:

		var vy_min: float = sqrt(2.0 * grav * maxf(target_apex - ball_pos.y, 0.01))
		vel.y = maxf(vel.y, vy_min * 1.6)

		vel.x *= 0.88
		vel.z *= 0.88

		for _reconverge in range(20):
			if _game_node and _game_node.has_method("compute_shot_spin"):
				spin_final = _game_node.compute_shot_spin("", vel, charge, 1, 0)
			var landing2: Vector3 = _simulate_landing(ball_pos, vel, spin_final, true)
			var err_x2: float = tx - landing2.x
			var err_z2: float = tz - landing2.z
			if absf(err_x2) < 0.1 and absf(err_z2) < 0.1:
				break
			var actual_dx2: float = landing2.x - ball_pos.x
			var actual_dz2: float = landing2.z - ball_pos.z
			if absf(actual_dz2) > 0.03:
				var scale_z2: float = dz / actual_dz2
				vel.z *= clampf(scale_z2, 0.5, 2.0)
			if absf(actual_dx2) > 0.03:
				var scale_x2: float = dx / actual_dx2
				vel.x *= clampf(scale_x2, 0.5, 2.0)


	var min_speed: float = 4.0
	var max_speed: float = 22.0
	var cur_speed: float = vel.length()
	if cur_speed < min_speed:
		vel = vel.normalized() * min_speed
	elif cur_speed > max_speed:
		vel = vel.normalized() * max_speed

	return vel


func _exchange_practice():
	var _pt := Time.get_ticks_usec()
	_perf_exchange_practice()
	PerfMonitor.record("ai.exchange_practice", Time.get_ticks_usec() - _pt)

func _perf_exchange_practice():
	if _game_node and "practice_launcher" in _game_node and _game_node.practice_launcher and _game_node.practice_launcher.is_exchange():
		return _game_node.practice_launcher
	return null

func _active_contact_pose() -> PostureDefinition:
	if incoming_pose_override != null: return incoming_pose_override
	if _player.posture.transition_pose_blend != null: return _player.posture.transition_pose_blend
	return PostureLibrary.instance().get_def(ai_desired_posture)

func _exchange_surface_contact(ball, active_pose: PostureDefinition = null) -> bool:
	var base: PostureDefinition = active_pose if active_pose != null else _active_contact_pose()
	if not WristReach.fits(_player.paddle_node.global_transform, base, WristReach.live_shoulder(_player, base), WristReach.link_budget(_player, base)): return false
	var local: Vector3 = _player.paddle_node.to_local(ball.global_position)
	var geometry = preload("res://scripts/paddle_clearance.gd")
	return geometry.distance_to_head_shape(local) <= _Ball.BALL_RADIUS + geometry.contact_surface_tolerance()

func choose_kitchen_tactic(ball_pos: Vector3) -> String:
	if _game_node == null or not "rally_scorer" in _game_node: return "NORMAL"
	var ball = _player._get_ball_ref()
	var scorer = _game_node.rally_scorer
	var feet_outside: bool = _feet_established_outside_kitchen()
	var legal_volley: bool = ball.both_bounces_complete and feet_outside and not _player.is_jumping
	var context: Dictionary = {"near_kitchen": absf(_player.global_position.z) <= PickleballConstants.NON_VOLLEY_ZONE + 1.4, 
		"legal_volley": legal_volley, "reachable": ai_selected_contact_reachable, 
		"balanced": scorer._has_regained_balance(_player), "reaction_ready": _perception_ready, 
		"ball_height": ball_pos.y, "net_height": _Flight.net_clear_y_at(ball_pos.x), "difficulty": ai_difficulty}
	last_kitchen_tactic = preload("res://scripts/ai_kitchen_tactics.gd").choose(context, _tactic_rng.randf())
	return last_kitchen_tactic

func _update_foot_legality() -> void:
	var _pt := Time.get_ticks_usec()
	_perf_update_foot_legality()
	PerfMonitor.record("ai.update_foot_legality", Time.get_ticks_usec() - _pt)

func _perf_update_foot_legality() -> void:
	_player.can_volley_from_feet()

func _feet_established_outside_kitchen() -> bool:

	return _player.can_volley_from_feet()

func set_tactic_seed(value: int) -> void :
	cancel_execution_commit()
	_tactic_rng.seed = value
	_planned_shot = {}
	_planned_flight = -1
	motion_context = {}


func set_playing_style(value: int) -> void:
	# Existing plans and motion_context remain latched until their normal expiry.
	playing_style_id = preload("res://scripts/ai_playing_styles.gd").valid_id(value)

func style_position_preferences() -> Dictionary:
	var data: Dictionary = preload("res://scripts/ai_playing_styles.gd").profile(_style_for_incoming_flight(_player._get_ball_ref()))
	return {"cover_depth": data.cover_depth, "poach_tendency": data.poach_tendency}

func _style_for_incoming_flight(ball) -> int:
	if ball != null and _planned_flight == ball.flight_id and not _planned_shot.is_empty():
		return int(_planned_shot.get("style_id", playing_style_id))
	return playing_style_id

func match_context(ball_pos: Vector3) -> Dictionary:
	var ball = _player._get_ball_ref()
	var balanced: bool = _game_node.rally_scorer._has_regained_balance(_player) if _game_node else true
	return {"origin": ball_pos, "player_num": _player.team_id, "actor_id": _player.get_actor_id(), "team_id": _player.team_id, "court_side": _player.court_side, "opponent": _observed_opponent,
		"style_id": _style_for_incoming_flight(ball), "difficulty": ai_difficulty, "ball_height": ball_pos.y, "net_height": _Flight.net_clear_y_at(ball_pos.x),
		"net_distance": absf(ball_pos.z), "contact_distance": PaddleReach.shoulder_world(_player).distance_to(ball_pos),
		"incoming_speed": ball.linear_velocity.length() if ball else 0.0, "time_to_contact": ai_selected_contact_time, "movement_speed": _player.current_velocity.length(),
		"opening_return": ball != null and not ball.both_bounces_complete, "balanced": balanced,
		"near_kitchen": absf(ball_pos.z) <= 3.4, "legal_volley": ball != null and ball.both_bounces_complete and _feet_established_outside_kitchen(),
		"reachable": ai_selected_contact_reachable, "reaction_ready": _perception_ready}

func solve_match_launch(ball_pos: Vector3) -> Dictionary:
	var context: Dictionary = match_context(ball_pos)
	var ball = _player._get_ball_ref()
	if _planned_shot.is_empty() or ball == null or _planned_flight != ball.flight_id or _planned_bounces != ball.bounces_since_last_hit:
		if not _opponent_sample_available: return {}
		_planned_shot = MatchTactics.plan(context, _tactic_rng.randf(), _tactic_rng.randf())
		_planned_flight = ball.flight_id if ball else -1
		_planned_bounces = ball.bounces_since_last_hit if ball else -1
	var launch: Dictionary = MatchTactics.solve_plan(_game_node.shot_physics, ball_pos, context, _planned_shot)
	if not launch.is_empty():
		last_match_tactic = launch.tactic
		last_kitchen_tactic = last_match_tactic
		last_match_shot = {"kind": last_match_tactic, "target": launch.target, "velocity": launch.velocity,
			"opponent_observed": _observed_opponent, "origin": ball_pos}
	return launch


func solve_practice_launch(ball_pos: Vector3) -> Dictionary:
	# Keep drill patterns and cooperative/demo feeds authored by the practice
	# controller, while retaining its legal kitchen attacks and defensive reset.
	var practice = _game_node.practice_launcher
	var context: Dictionary = practice.kitchen_context(ball_pos, _player.player_num)
	var response: String = preload("res://scripts/ai_kitchen_tactics.gd").response_kind(context, _tactic_rng.randf())
	if response in ["SMASH", "SPEED_UP"]:
		return practice.solve_kitchen_attack(ball_pos, _player.player_num, context)
	last_kitchen_tactic = response
	return practice.solve_exchange_launch(ball_pos, _player.player_num)

func _capture_plan_context(ball, base: PostureDefinition, point: Vector3, time: float, shot: Dictionary) -> Dictionary:
	return MotionContext.capture(_player, ball, base, point, time, {
		"charge": float(shot.get("charge", 0.5)), "spin_mode": int(shot.get("spin_mode", 0)),
		"shot_intent": str(shot.get("intent", "AUTO")), "shot_type": str(shot.get("shot_type", "GROUNDSTROKE")),
		"tactic": str(shot.get("kind", "")), "target": shot.get("target", Vector3.ZERO), "arc": float(shot.get("arc", 0.0))})

func get_or_commit_motion_intent(point: Vector3, time: float) -> Dictionary:
	# A validated special-reach opportunity may precede ordinary pose selection.
	# It shares one actual tactical decision with the eventual accepted launch.
	var ball = _player._get_ball_ref()
	if ball == null or not ball.is_in_play or ball.last_hit_by == _player.player_num or not point.is_finite() or time < 0.0: return {}
	if _planned_flight != ball.flight_id or _planned_shot.is_empty():
		if not _opponent_sample_available: return {}
		_planned_shot = MatchTactics.plan(match_context(point), _tactic_rng.randf(), _tactic_rng.randf())
		_planned_flight = ball.flight_id
		_planned_bounces = ball.bounces_since_last_hit
		var base: PostureDefinition = ai_reach_pose if ai_reach_pose != null else PostureLibrary.instance().get_def(ai_desired_posture)
		motion_context = _capture_plan_context(ball, base, point, time, _planned_shot)
		_commit_execution_for_motion(ball)
	return _planned_shot.duplicate(true)

func _prepare_motion_plan(ball, base: PostureDefinition, point: Vector3) -> void:
	# Cooperative drill feeds retain their authored pacing. Their accepted
	# launch still gets an exact snapshot before follow-through at contact.
	if _exchange_practice(): return
	if _planned_flight != ball.flight_id or _planned_bounces != ball.bounces_since_last_hit or _planned_shot.is_empty():
		if not _opponent_sample_available: return
		_planned_shot = MatchTactics.plan(match_context(point), _tactic_rng.randf(), _tactic_rng.randf())
		_planned_flight = ball.flight_id
		_planned_bounces = ball.bounces_since_last_hit
		motion_context = _capture_plan_context(ball, base, point, ai_selected_contact_time, _planned_shot)
		_commit_execution_for_motion(ball)
		MotionContext.apply_feet(_player, motion_context)

func _same_motion_plan(context: Dictionary, shot: Dictionary) -> bool:
	if context.is_empty(): return false
	return str(context.tactic) == str(shot.get("kind", "")) \
		and str(context.shot_intent) == str(shot.get("intent", "AUTO")) \
		and str(context.shot_type) == str(shot.get("shot_type", "GROUNDSTROKE")) \
		and int(context.spin_mode) == int(shot.get("spin_mode", 0)) \
		and is_equal_approx(float(context.charge), float(shot.get("charge", 0.5))) \
		and is_equal_approx(float(context.arc), float(shot.get("arc", 0.0))) \
		and Vector3(context.target).is_equal_approx(shot.get("target", Vector3.ZERO))

func cancel_execution_commit() -> void:
	# Cancellation invalidates only the pending execution latch, not a live
	# visual recovery or a completed contact's replay evidence.
	_execution_commit_active = false
	_execution_reaction_latency = -1.0
	_execution_commit_flight = -1
	_charge_contact_deadline = -1.0
	_charge_contact_flight = -1

func _commit_execution_for_motion(ball) -> void:
	if ball == null or not _game_node.has_method("commit_execution_settings"): return
	var existing: Dictionary = _game_node._execution_commits.get(_player.get_actor_id(), {})
	if _execution_commit_active and _execution_commit_flight == ball.flight_id and int(existing.get("flight_id", -1)) == ball.flight_id: return
	_game_node.commit_execution_settings(_player)
	_execution_commit_token += 1
	_execution_reaction_latency = _selected_reaction_seconds()
	_execution_commit_flight = ball.flight_id
	_execution_commit_active = true


func _on_own_half(point: Vector3) -> bool:
	return point.z < 0.0 if _player.court_side == 1 else point.z > 0.0

func _outside_kitchen_depth(z: float, minimum_depth: float) -> float:
	return minf(z, -minimum_depth) if _player.court_side == 1 else maxf(z, minimum_depth)

func _has_latched_observed_stroke_core(ball) -> bool:
	return ball != null and ball.is_in_play and ball.flight_id == _observed_flight_id \
		and ai_is_charging and ai_hit_cooldown <= 0.0 and _charge_contact_flight == ball.flight_id \
		and _execution_commit_active and _execution_commit_flight == ball.flight_id \
		and _planned_flight == ball.flight_id \
		and not _planned_shot.is_empty() and not motion_context.is_empty()

func _has_latched_observed_stroke(ball) -> bool:
	return _has_latched_observed_stroke_core(ball) and _planned_bounces == ball.bounces_since_last_hit

func _publish_two_phase_intent() -> void:
	if not _player.is_ai or _game_node == null: return
	var ball = _player._get_ball_ref()
	var authority = _game_node.contact_authority
	if authority == null or not authority.uses_two_phase_contact(_player) or ball == null or not ai_is_charging or ai_hit_cooldown > 0.0 or not _perception_ready or ball.flight_id != _observed_flight_id: return
	if not _opponent_sample_available and not _has_latched_observed_stroke(ball): return
	if ball.get_last_hit_team_id() == _player.team_id: return
	var coordination = _team_coordination()
	if coordination != null and not coordination.may_begin_stroke(_player): return
	var pose: PostureDefinition = _active_contact_pose()
	if pose == null: return
	authority.publish_contact_intent(_player, {"kind": "ai", "flight": ball.flight_id, "observed_flight": _observed_flight_id,
		"execution_token": _execution_commit_token, "execution_active": _execution_commit_active, "execution_flight": _execution_commit_flight, "charge_time": ai_charge_time, "observation_time": _observation_time,
		"deadline": _charge_contact_deadline, "deadline_flight": _charge_contact_flight, "posture": pose.posture_id,
		"selected_time": ai_selected_contact_time, "context": match_context(ball.global_position),
		"planned_shot": _planned_shot.duplicate(true) if _planned_flight == ball.flight_id else {},
		"motion_context": motion_context.duplicate(true)})

func contact_intent_is_current(intent: Dictionary, certificate: Dictionary = {}) -> bool:
	var ball = _player._get_ball_ref()
	if ball == null or not ball.is_in_play or not ai_is_charging or ai_hit_cooldown > 0.0 or not _perception_ready: return false
	if not _opponent_sample_available and not _has_latched_observed_stroke(ball):
		# No planning/publication privilege: only the selected event's already
		# sealed stroke can explain its authority-owned first floor transition.
		if not _has_latched_observed_stroke_core(ball) or _planned_bounces != 0 or intent.get("planned_shot", {}) != _planned_shot or intent.get("motion_context", {}) != motion_context: return false
		if _game_node == null or _game_node.contact_authority == null or not _game_node.contact_authority.validates_owned_first_floor_intent(_player, intent, certificate): return false
	if ball.flight_id != int(intent.get("flight", -1)) or _observed_flight_id != int(intent.get("observed_flight", -1)) or _execution_commit_token != int(intent.get("execution_token", -1)): return false
	if _execution_commit_active != bool(intent.get("execution_active", false)) or _execution_commit_flight != int(intent.get("execution_flight", -1)): return false
	if ai_charge_time != float(intent.get("charge_time", -1.0)) or _observation_time != float(intent.get("observation_time", -1.0)): return false
	if not certificate.is_empty():
		return _game_node != null and _game_node.contact_authority != null and _game_node.contact_authority.validates_intent_settlement(_player, intent, certificate)
	var coordination = _team_coordination()
	return coordination == null or coordination.may_begin_stroke(_player)

func finish_contact_intent(_intent: Dictionary) -> void:
	pass

func settle_contact_intent(intent: Dictionary, certificate: Dictionary) -> Dictionary:
	if not contact_intent_is_current(intent, certificate) or not _game_node.contact_authority.validates_settlement(_player, certificate): return {}
	var body = _player._get_ball_ref()
	var endpoint_pose: PostureDefinition = _player.posture.transition_pose_blend
	if endpoint_pose == null: return {}
	var practice = _exchange_practice()
	if practice and practice.needs_bounce() and not body.ball_bounced_since_last_hit: return {}
	var launch: Dictionary
	var context: Dictionary = intent.context.duplicate(true)
	# The tactical target/input is frozen. Only physical origin and current
	# ordered bounce facts are supplied by the actual contact event.
	context.origin = body.global_position
	context.ball_height = body.global_position.y
	context.net_height = _Flight.net_clear_y_at(body.global_position.x)
	context.net_distance = absf(body.global_position.z)
	context.incoming_speed = body.linear_velocity.length()
	context.opening_return = not body.both_bounces_complete
	var plan: Dictionary = intent.planned_shot.duplicate(true)
	if practice:
		launch = _game_node.solve_ai_launch(body.global_position, clampf(float(intent.charge_time) / AI_CHARGE_DURATION, .05, 1.0), int(intent.posture), certificate.paddle.origin, Vector3.ZERO, 0.0, _player)
	else:
		if plan.is_empty(): plan = MatchTactics.plan(context, _tactic_rng.randf(), _tactic_rng.randf())
		launch = MatchTactics.solve_plan(_game_node.shot_physics, body.global_position, context, plan)
	if launch.is_empty(): return {}
	if not _game_node.contact_authority.intended_velocity_leaves_surface(_player, certificate, launch.velocity, "authored"): return {"accepted": false, "passive_fallback": true}
	var accepted: Dictionary = launch.get("motion_plan", {"kind": str(launch.get("tactic", "")), "charge": .25,
		"intent": str(launch.get("profile", {}).get("shot_intent", "AUTO")), "shot_type": str(launch.get("profile", {}).get("shot_type", "GROUNDSTROKE")), "target": launch.get("target", body.global_position), "arc": 0.0})
	motion_context = intent.motion_context.duplicate(true)
	if not _same_motion_plan(motion_context, accepted): motion_context = _capture_plan_context(body, endpoint_pose, body.global_position, 0.0, accepted)
	var timing_error: float = -maxf(float(intent.selected_time), 0.0)
	if int(intent.deadline_flight) == body.flight_id and float(intent.deadline) >= 0.0: timing_error = float(intent.observation_time) - float(intent.deadline)
	timing_error -= (1.0 - float(certificate.evidence.fraction)) * float(certificate.control_seconds)
	if not practice and _game_node.has_method("apply_contact_execution"):
		_commit_execution_for_motion(body)
		launch = _game_node.apply_contact_execution(_player, launch, float(motion_context.charge), timing_error, false, certificate)
		last_contact_execution = {"incoming_flight": body.flight_id, "commit_token": _execution_commit_token,
			"rng_draw_count": _game_node.shot_physics.accuracy.samples, "deadline": intent.deadline,
			"observation_time": intent.observation_time, "fraction": certificate.evidence.fraction,
			"full_delta": certificate.physical_seconds, "control_delta": certificate.control_seconds,
			"timing_error_seconds": timing_error, "profile": launch.get("profile", {}).duplicate(true)}
	if not _game_node.contact_authority.intended_velocity_leaves_surface(_player, certificate, launch.velocity, "executed"): return {"accepted": false, "passive_fallback": true}
	_player.hitting.committed_motion_context = motion_context
	MotionContext.apply_feet(_player, motion_context)
	_player.hitting.begin_settled_recovery(float(motion_context.charge), endpoint_pose)
	body.suppress_paddle_collision(_player.paddle_node)
	if _player.posture: _player.posture.notify_ball_hit()
	if launch.has("profile"):
		launch.profile = launch.profile.duplicate(true); launch.profile["motion_profile"] = motion_context.profile
	body.linear_velocity = launch.velocity; body.angular_velocity = launch.omega
	if not body.hit_by_actor(_player): return {"accepted": true, "interrupted": true}
	var event: Dictionary = body.paddle_contact_context()
	if int(certificate.epoch) != _game_node.contact_authority._interval_reset_epoch: return {"accepted": true, "interrupted": true}
	_player.set_meta("legal_net_followthrough_flight", body.flight_id)
	_player.stamina.spend_contact(str(launch.get("tactic", launch.get("profile", {}).get("shot_type", ""))), body.linear_velocity.length())
	ai_hit_cooldown = AI_HIT_COOLDOWN
	_player.hit_ball.emit(body, body.linear_velocity.normalized())
	if not body.paddle_contact_is_current(event) or int(certificate.epoch) != _game_node.contact_authority._interval_reset_epoch: return {"accepted": true, "interrupted": true}
	ai_is_charging = false; ai_charge_time = 0.0
	_charge_contact_position = Vector3.ZERO; _charge_target_position = Vector3.ZERO
	ai_ball_bounced_on_side = false; ai_state = AIState.INTERCEPT_POSITION
	last_swept_contact_evidence = certificate.evidence.duplicate(true)
	last_swept_contact_evidence["settled"] = true
	_draw_ai_trajectory(body.global_position, body.linear_velocity, body.angular_velocity)
	return {"accepted": true}

func _retire_uncommitted_unreachable_charge(ball, ordinary_offer: Dictionary) -> bool:
	var _pt := Time.get_ticks_usec()
	var _pr = _perf_retire_uncommitted_unreachable_charge(ball, ordinary_offer)
	PerfMonitor.record("ai.retire_uncommitted_unreachable_charge", Time.get_ticks_usec() - _pt)
	return _pr

func _perf_retire_uncommitted_unreachable_charge(ball, ordinary_offer: Dictionary) -> bool:
	# A fresh failed prediction can retire an uncommitted charge, without
	# canceling the previous accepted contact's still-continuous recovery.
	# The predicted timestamp is never treated as a physical contact cutoff.
	if ball == null or not ball.is_in_play or not ai_is_charging: return false
	if not _perception_ready or not _opponent_sample_available or _observed_flight_id != ball.flight_id or _charge_contact_flight != ball.flight_id: return false
	if _execution_commit_active or not _planned_shot.is_empty() or not motion_context.is_empty(): return false
	if not ordinary_offer.has("observed_at") or float(ordinary_offer.observed_at) != _observation_time: return false
	var offer_time: float = float(ordinary_offer.get("time", 0.0))
	if not is_finite(offer_time) or bool(ordinary_offer.get("reachable", true)) or offer_time >= 0.0: return false
	cancel_execution_commit()
	ai_is_charging = false
	ai_charge_time = 0.0
	ai_state = AIState.INTERCEPT_POSITION
	_charge_contact_position = Vector3.ZERO
	_charge_target_position = Vector3.ZERO
	_charge_reach_pose = null
	_planned_flight = -1
	_planned_bounces = -1
	_planned_contact_grip = null
	ai_selected_contact_reachable = false
	ai_selected_contact_time = -1.0
	# Do not clear the just-refreshed movement plan, support clocks, incoming
	# pose, live recovery, contact sweep or any passive collision geometry.
	return true

func _charge_reentry_blocked_by_recovery_offer(ball) -> bool:
	# A queued, uncommitted charge must not immediately re-arm from proximity
	# while the old physical recovery owns the rig and the current offer failed.
	# Real overlapping/paddle-sweep contact and already committed strokes keep
	# their existing paths. A new reachable observation admits charge normally.
	if ai_is_charging or ball == null or not ball.is_in_play or _player == null or _player.hitting == null: return false
	if _player.hitting._live_swing_presentation.is_empty(): return false
	if not _perception_ready or not _opponent_sample_available or _observed_flight_id != ball.flight_id: return false
	if _execution_commit_active or not _planned_shot.is_empty() or not motion_context.is_empty(): return false
	if not _movement_plan.has("observed_at"): return false
	var observed_at: float = float(_movement_plan.observed_at)
	var offer_time: float = float(_movement_plan.get("time", 0.0))
	return is_finite(observed_at) and observed_at >= 0.0 and observed_at <= _observation_time \
		and is_finite(offer_time) and offer_time < 0.0 and not bool(_movement_plan.get("reachable", true))
