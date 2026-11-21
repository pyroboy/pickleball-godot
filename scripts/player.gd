class_name PlayerController extends CharacterBody3D
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")
const HeadGaze = preload("res://scripts/player_head_gaze.gd")
const ReadyTracking = preload("res://scripts/ready_ball_tracking.gd")
const NVZState = preload("res://scripts/player_nvz_state.gd")
var _nvz_state = NVZState.new()
var stamina = preload("res://scripts/player_stamina.gd").new()


const PLAYER_SPEED: = PickleballConstants.PLAYER_SPEED
const AI_SPEED: = PickleballConstants.AI_SPEED
const PADDLE_FORCE: = PickleballConstants.PADDLE_FORCE
const AI_PADDLE_FORCE: = PickleballConstants.AI_PADDLE_FORCE
const COURT_LENGTH: = PickleballConstants.COURT_LENGTH
const COURT_WIDTH: = PickleballConstants.COURT_WIDTH

const COURT_FLOOR_Y: = PickleballConstants.FLOOR_Y
const SIDE_BOUND_MARGIN: = PickleballConstants.SIDE_BOUND_MARGIN
const BASELINE_BOUND_MARGIN: = PickleballConstants.BASELINE_BOUND_MARGIN
const NET_BOUND_MARGIN: = PickleballConstants.NET_BOUND_MARGIN
const BACKHAND_POSTURES: Array[int] = [
	PaddlePosture.BACKHAND, PaddlePosture.LOW_BACKHAND, PaddlePosture.CHARGE_BACKHAND, 
	PaddlePosture.WIDE_BACKHAND, PaddlePosture.MID_LOW_BACKHAND, 
	PaddlePosture.MID_LOW_WIDE_BACKHAND, PaddlePosture.LOW_WIDE_BACKHAND, 
]
const FOREHAND_POSTURES: Array[int] = [
	PaddlePosture.FOREHAND, PaddlePosture.LOW_FOREHAND, PaddlePosture.WIDE_FOREHAND, 
	PaddlePosture.MID_LOW_FOREHAND, PaddlePosture.MID_LOW_WIDE_FOREHAND, 
	PaddlePosture.LOW_WIDE_FOREHAND, PaddlePosture.CHARGE_FOREHAND, 
]
const CENTER_POSTURES: Array[int] = [
	PaddlePosture.FORWARD, PaddlePosture.LOW_FORWARD, PaddlePosture.MID_LOW_FORWARD, 
	PaddlePosture.MEDIUM_OVERHEAD, PaddlePosture.HIGH_OVERHEAD, PaddlePosture.VOLLEY_READY, 
	PaddlePosture.READY, 
]
const DEBUG_POSTURE_NAMES: Array[String] = [
	"FH", "FW", "BH", "MO", "HO", "LF", "LC", "LB", "CF", "CB", "WF", "WB", "VR", 
	"MLF", "MLB", "MLC", "MWF", "MWB", "LWF", "LWB", "RDY", 
]
const MEDIUM_OVERHEAD_TRIGGER_HEIGHT: = PickleballConstants.MEDIUM_OVERHEAD_TRIGGER_HEIGHT
const HIGH_OVERHEAD_TRIGGER_HEIGHT: = PickleballConstants.HIGH_OVERHEAD_TRIGGER_HEIGHT
const OVERHEAD_TRIGGER_RADIUS: = PickleballConstants.OVERHEAD_TRIGGER_RADIUS
const OVERHEAD_RELEASE_HEIGHT: = PickleballConstants.OVERHEAD_RELEASE_HEIGHT
const OVERHEAD_RELEASE_RADIUS: = PickleballConstants.OVERHEAD_RELEASE_RADIUS
const JUMP_VELOCITY: = PickleballConstants.JUMP_VELOCITY
const JUMP_GRAVITY: = PickleballConstants.JUMP_GRAVITY

enum PaddlePosture{
	FOREHAND, 
	FORWARD, 
	BACKHAND, 
	MEDIUM_OVERHEAD, 
	HIGH_OVERHEAD, 
	LOW_FOREHAND, 
	LOW_FORWARD, 
	LOW_BACKHAND, 
	CHARGE_FOREHAND, 
	CHARGE_BACKHAND, 
	WIDE_FOREHAND, 
	WIDE_BACKHAND, 
	VOLLEY_READY, 
	MID_LOW_FOREHAND, 
	MID_LOW_BACKHAND, 
	MID_LOW_FORWARD, 
	MID_LOW_WIDE_FOREHAND, 
	MID_LOW_WIDE_BACKHAND, 
	LOW_WIDE_FOREHAND, 
	LOW_WIDE_BACKHAND, 
	READY, 
}

enum BasePoseState{
	ATHLETIC_READY, 
	SPLIT_STEP, 
	RECOVERY_READY, 
	KITCHEN_NEUTRAL, 
	DINK_BASE, 
	DROP_RESET_BASE, 
	PUNCH_VOLLEY_READY, 
	DINK_VOLLEY_READY, 
	DEEP_VOLLEY_READY, 
	GROUNDSTROKE_BASE, 
	LOB_DEFENSE_BASE, 
	FOREHAND_LUNGE, 
	BACKHAND_LUNGE, 
	LOW_SCOOP_LUNGE, 
	OVERHEAD_PREP, 
	JUMP_TAKEOFF, 
	AIR_SMASH, 
	LANDING_RECOVERY, 
	LATERAL_SHUFFLE, 
	CROSSOVER_RUN, 
	BACKPEDAL, 
	DECEL_PLANT, 
}

enum PoseIntent{
	NEUTRAL, 
	DINK, 
	DROP_RESET, 
	PUNCH_VOLLEY, 
	DINK_VOLLEY, 
	DEEP_VOLLEY, 
	GROUNDSTROKE, 
	LOB_DEFENSE, 
	OVERHEAD_SMASH, 
}

enum ShotContactState{
	CLEAN, 
	STRETCHED, 
	POPUP, 
}

enum AIState{
	INTERCEPT_POSITION, 
	CHARGING, 
	HIT_BALL, 
}


# Legacy team alias. Unique actor and physical court end are separate.
var player_num: int = 0
var actor_id: int = -1
var team_id: int:
	get: return player_num
	set(value): player_num = value
var _court_side: int = -1
var court_side: int:
	get: return player_num if _court_side < 0 else _court_side
	set(value): _court_side = value
var _court_bounds: Dictionary = {}
var move_speed: float = PLAYER_SPEED
var paddle_force: float = PADDLE_FORCE
var min_x: float
var max_x: float
var min_z: float
var max_z: float
var bounds_ready: bool = false
var is_ai: bool = false
var manual_crouch: bool = false
var ball_ref: RigidBody3D = null
var paddle_node: Node3D = null
var right_arm_node: Node3D = null
var left_arm_node: Node3D = null
var body_pivot: Node3D = null
var right_leg_node: Node3D = null
var left_leg_node: Node3D = null
var skeleton: Skeleton3D = null
var skeleton_bones: Dictionary = {}
var current_velocity: Vector3 = Vector3.ZERO
const MANUAL_ACCEL := 72.0
const MANUAL_REVERSE_ACCEL := 84.0
const MANUAL_BRAKE := 34.0
var _manual_motion_active := false
var paddle_rest_position: Vector3 = Vector3.ZERO
var paddle_rest_rotation: Vector3 = Vector3.ZERO
var paddle_hitbox: Area3D = null
var paddle_posture: int:
	get: return posture.paddle_posture if posture else PaddlePosture.FOREHAND
	set(v):
		if posture:
			posture.paddle_posture = v
			if pose_controller:
				pose_controller.invalidate_cache()
			posture._apply_full_body_posture()
var base_pose_state: int:
	get: return pose_controller.base_pose_state if pose_controller else BasePoseState.ATHLETIC_READY
	set(v):
		if pose_controller:
			pose_controller.base_pose_state = v
			pose_controller.invalidate_cache()
var pose_intent: int:
	get: return pose_controller.pose_intent if pose_controller else PoseIntent.NEUTRAL
	set(v):
		if pose_controller:
			pose_controller.pose_intent = v
			pose_controller.invalidate_cache()
var posture_lerp_pos: Vector3:
	get: return posture._posture_lerp_pos if posture else Vector3.ZERO
	set(v):
		if posture: posture._posture_lerp_pos = v
var posture_lerp_initialized: bool:
	get: return posture._posture_lerp_initialized if posture else false
	set(v):
		if posture: posture._posture_lerp_initialized = v
var ai_movement_enabled: bool = true
var ground_y: float = 0.0
var vertical_velocity: float = 0.0
var is_jumping: bool = false


var jump_landing_remaining: float = 0.0
var jump_takeoff_position: = Vector3.ZERO
var _contextual_jump: Dictionary = {}
var _jump_last_position: = Vector3.ZERO
var _jump_position_initialized: = false
var _jump_was_airborne: = false
const CONTEXTUAL_JUMP_CHARGE: = 0.65
const CONTEXTUAL_JUMP_HEIGHT: = 0.24
const CONTEXTUAL_JUMP_LANDING_TIME: = 0.24
var ai_state: int:
	get: return ai_brain.ai_state if ai_brain else AIState.INTERCEPT_POSITION
	set(v):
		if ai_brain: ai_brain.ai_state = v
var ai_desired_posture: int:
	get: return ai_brain.ai_desired_posture if ai_brain else PaddlePosture.FOREHAND
	set(v):
		if ai_brain: ai_brain.ai_desired_posture = v
var ai_charge_time: float:
	get: return ai_brain.ai_charge_time if ai_brain else 0.0
	set(v):
		if ai_brain: ai_brain.ai_charge_time = v
var ai_is_charging: bool:
	get: return ai_brain.ai_is_charging if ai_brain else false
	set(v):
		if ai_brain: ai_brain.ai_is_charging = v
var ai_ball_bounced_on_side: bool:
	get: return ai_brain.ai_ball_bounced_on_side if ai_brain else false
	set(v):
		if ai_brain: ai_brain.ai_ball_bounced_on_side = v
var left_hand_rest_pos: Vector3 = Vector3.ZERO
var has_debug_printed: bool = false
var _head_gaze = HeadGaze.new()
var _ready_tracking = ReadyTracking.new()


var ai_brain
var hitting
var leg_ik
var erne_action
var special_reach_driver
var _physics_human_presentation := false
var _physics_ai_presentation := false
var body_anim
var pose_controller
var posture
var debug_visual
var arm_ik
var awareness_grid = null
var body_builder

signal initial_paddle_setup_completed
var initial_paddle_setup_complete: bool = false

@warning_ignore("unused_signal")
signal hit_ball(ball: RigidBody3D, direction: Vector3)

func _ready() -> void :
	_cache_existing_paddle()

func configure_identity(unique_actor: int, stable_team: int, physical_side: int) -> bool:
	if unique_actor < 0 or stable_team not in [0, 1] or physical_side not in [0, 1]: return false
	var registered: Array = get_meta("registered_actor_identity", [])
	if not registered.is_empty() and (unique_actor != registered[0] or stable_team != registered[1]): return false
	if body_pivot != null and body_pivot.has_meta("articulated_torso"):
		load("res://scripts/runtime_court_frame.gd").set_visual_court_side(self, physical_side)
	actor_id = unique_actor
	team_id = stable_team
	court_side = physical_side
	set_meta("actor_id", actor_id)
	set_meta("team_id", team_id)
	set_meta("player_num", team_id)
	set_meta("court_side", court_side)
	if not _court_bounds.is_empty(): _apply_court_bounds()
	return true

func get_actor_id() -> int:
	# Compatibility for isolated old rig fixtures that never call setup.
	return actor_id if actor_id >= 0 else player_num

func get_team_id() -> int:
	return team_id

func get_court_side() -> int:
	return court_side

func _apply_court_bounds() -> void:
	min_x = _court_bounds.left - SIDE_BOUND_MARGIN
	max_x = _court_bounds.right + SIDE_BOUND_MARGIN
	if court_side == 0:
		min_z = NET_BOUND_MARGIN
		max_z = _court_bounds.bottom + BASELINE_BOUND_MARGIN
	else:
		min_z = _court_bounds.top - BASELINE_BOUND_MARGIN
		max_z = -NET_BOUND_MARGIN
	bounds_ready = true

func setup(player_id: int, bounds: Dictionary, paddle_color: Color, start_pos: Vector3, ai_enabled: bool = false, unique_actor: int = -1, stable_team: int = -1, physical_side: int = -1) -> void :
	if not configure_identity(player_id if unique_actor < 0 else unique_actor, player_id if stable_team < 0 else stable_team, player_id if physical_side < 0 else physical_side): return
	is_ai = ai_enabled
	move_speed = AI_SPEED if is_ai or player_id == 1 else PLAYER_SPEED
	paddle_force = AI_PADDLE_FORCE if is_ai or player_id == 1 else PADDLE_FORCE
	ai_movement_enabled = not is_ai or true

	set_meta("move_speed", move_speed)

	_court_bounds = bounds.duplicate()
	_apply_court_bounds()

	global_position = start_pos
	ground_y = start_pos.y
	reset_support_clock()

	body_builder = load("res://scripts/player_body_builder.gd").new()
	body_builder.name = "BodyBuilder"
	body_builder._player = self
	add_child(body_builder)
	body_builder.build(paddle_color)
	# 2.5D pixel cards on the posture joints (visual only; classic meshes kept for gameplay reads).
	PixelCardRig.attach.call_deferred(self)
	# Realistic paddle look (visual only, data/paddles.json); the gameplay paddle stays.
	Callable(load("res://scripts/graphics/paddle_skin.gd"), "attach").call_deferred(self)


	ai_brain = load("res://scripts/player_ai_brain.gd").new()
	ai_brain.name = "AIBrain"
	ai_brain._player = self
	add_child(ai_brain)

	hitting = load("res://scripts/player_hitting.gd").new()
	hitting.name = "Hitting"
	hitting._player = self
	add_child(hitting)

	leg_ik = load("res://scripts/player_leg_ik.gd").new()
	leg_ik.name = "LegIK"
	leg_ik._player = self
	add_child(leg_ik)
	erne_action = preload("res://scripts/match_erne_action.gd").new(self)

	body_anim = load("res://scripts/player_body_animation.gd").new()
	body_anim.name = "BodyAnim"
	body_anim._player = self
	add_child(body_anim)

	pose_controller = load("res://scripts/pose_controller.gd").new()
	pose_controller.name = "PoseController"
	add_child(pose_controller)

	posture = load("res://scripts/player_paddle_posture.gd").new()
	posture.name = "Posture"
	posture._player = self
	add_child(posture)

	debug_visual = load("res://scripts/player_debug_visual.gd").new()
	debug_visual.name = "DebugVisual"
	debug_visual._player = self
	add_child(debug_visual)


	if player_num == 0 and not is_ai:
		var reach_rings = load("res://scripts/player_reach_indicator.gd").new()
		reach_rings.name = "ReachRings"
		add_child(reach_rings)

	arm_ik = load("res://scripts/player_arm_ik.gd").new()
	arm_ik.name = "ArmIK"
	arm_ik._player = self
	add_child(arm_ik)

	if RuntimePolicy.developer_tools:
		var grid_script = load("res://scripts/player_awareness_grid.gd")
		awareness_grid = grid_script.new()
		awareness_grid.name = "AwarenessGrid"
		awareness_grid._player = self
		add_child(awareness_grid)

		if is_ai:
			ai_brain._setup_ai_trajectory()

		call_deferred("_deferred_log_body")

func set_ai_movement_enabled(enabled: bool) -> void :
	ai_movement_enabled = enabled
	if not enabled:
		ai_ball_bounced_on_side = false
		ai_is_charging = false
		if RuntimePolicy.developer_tools: print("[BOS] reset by set_ai_movement_enabled(false)")

func notify_ball_bounced(bounce_pos: Vector3) -> void :
	if court_side == 1 and bounce_pos.z < 0.0:
		ai_ball_bounced_on_side = true
		if RuntimePolicy.developer_tools: print("[BOUNCE] P1 bos=true z=%.1f" % bounce_pos.z)
	elif court_side == 0 and bounce_pos.z > 0.0:
		ai_ball_bounced_on_side = true

func _wire_hitbox() -> void :
	if paddle_hitbox and ai_brain:
		paddle_hitbox.body_entered.connect(ai_brain._on_hitbox_body_entered.bind(paddle_node))

	if posture:
		posture.place_paddle_at_side()
		if RuntimePolicy.developer_tools:
			posture.create_posture_ghosts(Color(1, 0.85, 0.2))
	if debug_visual:
		debug_visual.create_ai_indicators()
		debug_visual.create_human_indicators()

	# One-time completion of the existing deferred constructor work.
	# The loading owner observes it; setup is never reordered or replayed.
	if not initial_paddle_setup_complete:
		initial_paddle_setup_complete = true
		initial_paddle_setup_completed.emit()


func _physics_process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_physics_process(delta)
	PerfMonitor.record("player.physics", Time.get_ticks_usec() - _pt)

func _perf_physics_process(delta: float) -> void:
	_physics_human_presentation = false
	_physics_ai_presentation = false
	_advance_support_clock(delta)
	if special_reach_driver != null and special_reach_driver.owns_movement():
		var manual: Vector3 = _get_human_input() if not is_ai and player_num == 0 else Vector3.ZERO
		if manual.length_squared() > 0.0001:
			special_reach_driver.cancel("manual movement requested; recovering support")
		if special_reach_driver.owns_movement():
			special_reach_driver.physics_step(delta, manual)
			return
	if special_reach_driver != null:
		special_reach_driver.idle_step(delta)
		special_reach_driver.before_normal_movement()
	var between = _between_point_owner()
	if special_reach_driver != null and special_reach_driver.bridge_active(): between = null
	var input_dir: Vector3 = Vector3.ZERO
	if erne_action: erne_action.before_physics(delta, _get_ball_ref())
	var special_movement: bool = erne_action != null and erne_action.active
	if special_movement: between = null
	_update_jump_state(delta)
	if ai_brain and ai_brain.ai_hit_cooldown > 0.0:
		ai_brain.ai_hit_cooldown = max(ai_brain.ai_hit_cooldown - delta, 0.0)

	if between != null:
		pass
	elif is_ai:
		if ai_movement_enabled and ai_brain:
			input_dir = ai_brain.get_ai_input(delta)
			if special_reach_driver != null and special_reach_driver.owns_presentation(): return
		if ai_brain:
			ai_brain._update_ai_trajectory_fade(delta)
	elif player_num == 0 and not (posture and posture.editor_preview_mode):
		input_dir = _get_human_input()




	if input_dir.length() > 1.0 or (is_ai and input_dir.length() > 0.0):
		input_dir = input_dir.normalized()

	velocity = between.velocity_for(get_actor_id()) if between != null else input_dir * move_speed
	if between == null and is_ai and ai_brain:
		velocity = ai_brain.ground_velocity(input_dir, delta) if ai_movement_enabled else Vector3.ZERO
	if between == null and not is_ai and posture and posture.human_contact != null:
		velocity = posture.human_contact.footwork.movement(delta, input_dir)
	if special_movement: velocity = erne_action.ground_velocity()
	var assisted: bool = posture != null and posture.human_contact != null and posture.human_contact.footwork.active
	if between == null and not is_ai and not assisted and not special_movement and not (posture and posture.editor_preview_mode):
		var human = posture.human_contact if posture != null else null
		var queued_travel:bool=human != null and human.phase == 0 and human.queued_movement_allowed
		var game=get_parent()
		var plant_lock:bool=not queued_travel and not (special_reach_driver != null and special_reach_driver.bridge_active()) and game != null and "aim_controller" in game and game.aim_controller != null and game.aim_controller.should_plant_player()
		if plant_lock:
			_manual_motion_active=false
			velocity=Vector3.ZERO
		else:
			velocity = _manual_ground_velocity(velocity, input_dir.length_squared() > .0001, delta)
	else:
		_manual_motion_active = false
	velocity.y = 0.0
	if between == null:
		# Cap speed, rather than multiply velocity each frame (which changes acceleration).
		velocity = velocity.limit_length(move_speed * stamina.speed_factor())
	current_velocity = velocity
	var movement_origin := global_position
	global_position += velocity * delta
	global_position.y += vertical_velocity * delta
	if global_position.y <= ground_y:
		global_position.y = ground_y
		vertical_velocity = 0.0
		is_jumping = false

	if bounds_ready and between == null:
		global_position.x = clamp(global_position.x, min_x, max_x)
		global_position.z = clamp(global_position.z, min_z, max_z)
	if delta > .000001:
		current_velocity = Vector3(global_position.x-movement_origin.x,0,global_position.z-movement_origin.z)/delta
		velocity = current_velocity

	var stamina_game = get_parent()
	var stamina_active: bool = stamina_game != null and "game_state" in stamina_game and not stamina_game._tool_state_active()
	var _pp_stamina := Time.get_ticks_usec()
	if stamina_active:
		stamina.advance(delta, current_velocity.length(), stamina_game.game_state == stamina_game.GameState.PLAYING, stamina_game.game_state != stamina_game.GameState.PLAYING)
	PerfMonitor.record("pp.stamina", Time.get_ticks_usec() - _pp_stamina)
	if special_reach_driver != null and special_reach_driver.bridge_active():
		special_reach_driver.bridge_step(delta)
		return
	if between != null: return
	if _owns_carried_cup_pose():
		_nvz_state.update(self)
		_advance_physics_head_gaze(delta)
		return
	if _owns_waiting_receiver_pose():
		var ready: PostureDefinition = PostureLibrary.instance().get_def(PaddlePosture.READY)
		posture.transition_pose_blend = ready
		posture.force_posture_update(ready)
		if posture.human_contact != null: posture.human_contact.visual_pose = ready
		_nvz_state.update(self)
		_advance_physics_head_gaze(delta)
		return


	if not is_ai and debug_visual:
		var b: RigidBody3D = _get_ball_ref()
		if b:
			debug_visual.update_human_intercept_pools(b)
			if posture:
				posture.set_trajectory_points(debug_visual._last_trajectory_points)
			if awareness_grid:
				awareness_grid.set_trajectory_points(debug_visual._last_trajectory_points)
	# Perf LOD: an AI the ball is not coming toward re-poses its arms/legs on
	# alternate ticks (movement still runs every tick). Accumulated time is passed
	# on the update tick so pose blends keep their speed.
	_lod_delta += delta
	var lod_skip: bool = _rig_lod_skip()
	# On a skipped tick the paddle stays where the last aligned pose put it. Running
	# the legacy tracking here moved it to a different spot every other tick, so
	# waiting AI players flickered between two poses (bench: 20 cm paddle jumps).
	var _pp_paddle_tracking := Time.get_ticks_usec()
	if posture and not lod_skip:
		posture.update_paddle_tracking(false)
	PerfMonitor.record("pp.paddle_tracking", Time.get_ticks_usec() - _pp_paddle_tracking)
	var _pp_align := Time.get_ticks_usec()
	if is_ai and ai_brain and not lod_skip:
		ai_brain.align_paddle_to_contact(_lod_delta)
	PerfMonitor.record("pp.align", Time.get_ticks_usec() - _pp_align)
	var _pp_clamp_paddle := Time.get_ticks_usec()
	PaddleReach.clamp_paddle_for_player(self)
	PerfMonitor.record("pp.clamp_paddle", Time.get_ticks_usec() - _pp_clamp_paddle)
	# Body-contact authority observes the physics endpoint before render.
	# Finish each normal owner's actual seated rig after its final clamp.
	var _pp_contact_support := Time.get_ticks_usec()
	if posture != null and not posture.editor_preview_mode and not lod_skip:
		refresh_contact_support(posture._presented_body_pose if posture._presented_body_pose != null else posture.capture_displayed_pose(), true)
	PerfMonitor.record("pp.contact_support", Time.get_ticks_usec() - _pp_contact_support)
	if not lod_skip: _lod_delta = 0.0
	_physics_human_presentation = _human_owns_physics_pose()
	_physics_ai_presentation = _ai_owns_physics_pose()
	if _physics_human_presentation or _physics_ai_presentation: _advance_physics_head_gaze(delta)
	var _pp_pose_state := Time.get_ticks_usec()
	if pose_controller:
		pose_controller.update_runtime_pose_state(delta)
	PerfMonitor.record("pp.pose_state", Time.get_ticks_usec() - _pp_pose_state)
	var _pp_ghosts := Time.get_ticks_usec()
	if posture:
		posture.update_posture_ghosts()
	PerfMonitor.record("pp.ghosts", Time.get_ticks_usec() - _pp_ghosts)
	if awareness_grid:
		awareness_grid.update_grid(delta)
	if debug_visual:
		debug_visual.update_ai_indicators()
	var _pp_try_hit := Time.get_ticks_usec()
	if ai_brain:
		ai_brain._try_ai_hit_ball()
	PerfMonitor.record("pp.try_hit", Time.get_ticks_usec() - _pp_try_hit)

var _lod_delta: float = 0.0
const LOD_FAR_M := 5.0
const LOD_NEAR_M := 2.5

## True on alternate ticks for an AI that cannot be the next hitter: the ball is
## flying to the other half, or far away and moving away.
func _rig_lod_skip() -> bool:
	if not is_ai or (Engine.get_physics_frames() + actor_id) % 2 == 0: return false
	if hitting != null and (hitting.is_in_follow_through or hitting.serving_visual_active): return false
	var b: RigidBody3D = _get_ball_ref()
	if b == null or not b.is_in_play: return false
	var to_me: Vector3 = global_position - b.global_position
	to_me.y = 0.0
	if to_me.length() < LOD_NEAR_M: return false
	# Ball flying toward the other team's half: nobody on this side can hit it.
	if b.linear_velocity.z * global_position.z < 0.0: return true
	return to_me.length() > LOD_FAR_M and b.linear_velocity.dot(to_me) < 0.0

func _manual_ground_velocity(target: Vector3, has_input: bool, delta: float) -> Vector3:
	if has_input: _manual_motion_active = true
	if not _manual_motion_active: return target
	var current := Vector3(current_velocity.x,0,current_velocity.z)
	var acceleration: float = MANUAL_ACCEL if has_input else MANUAL_BRAKE
	if has_input and current.dot(target) < 0.0: acceleration = MANUAL_REVERSE_ACCEL
	var result: Vector3 = current.move_toward(target, acceleration*maxf(delta,0.0))
	if not has_input and result.length_squared() < .0001:
		_manual_motion_active = false
		return Vector3.ZERO
	return result

var _ai_guard_active := false
var _ai_incoming_active: = false
var _between_pose_active: = false
var _between_last_pose: PostureDefinition



var _support_sim_time: = 0.0
var _support_consumed_time: = 0.0
var _support_last_refresh_tick: int = -1

func reset_support_clock() -> void :
	_physics_head_gaze_tick = -1

	_support_consumed_time = _support_sim_time
	_support_last_refresh_tick = -1

func _advance_support_clock(delta: float) -> void :
	if not is_finite(delta) or delta <= 0.0 or (is_inside_tree() and get_tree().paused): return
	if posture != null and posture.editor_preview_mode:
		reset_support_clock()
		return
	_support_sim_time += delta

func _consume_support_delta() -> float:
	if is_inside_tree() and get_tree().paused: return 0.0
	var pending: float = maxf(0.0, _support_sim_time - _support_consumed_time)

	_support_consumed_time = _support_sim_time
	if leg_ik == null or not leg_ik.feet_initialized or (posture != null and posture.editor_preview_mode): return 0.0
	var base: = Vector3(global_position.x, leg_ik.ANKLE_HEIGHT, global_position.z)
	var travel_limit: float = maxf(leg_ik.TELEPORT_DISTANCE, Vector2(current_velocity.x, current_velocity.z).length() * pending * 2.5 + 0.1)
	if base.distance_to(leg_ik._last_body_position) > travel_limit: return 0.0
	return pending



func refresh_contact_support(owned_pose: PostureDefinition, physics_presentation: bool = false) -> bool:
	if special_reach_driver != null and special_reach_driver.owns_presentation(): return false
	if owned_pose == null or (not physics_presentation and not is_ai) or not is_inside_tree() or get_tree().paused: return false
	if posture == null or posture.editor_preview_mode or _between_point_owner() != null: return false
	if leg_ik == null or arm_ik == null or body_pivot == null or paddle_node == null: return false
	if not physics_presentation and hitting != null and (hitting.serving_visual_active or hitting.is_in_follow_through): return false
	var tick: int = Engine.get_physics_frames()
	if _support_last_refresh_tick == tick: return false
	_support_last_refresh_tick = tick
	var raw: Transform3D = paddle_node.global_transform
	# Perf: the owner already fully solved this exact pose this tick and nothing has
	# moved the paddle since (e.g. no reach clamp) -> re-solving would repeat it.
	var stamp: Array = posture.full_solve_stamp
	if stamp.size() == 3 and stamp[0] == tick and stamp[1] == owned_pose and (stamp[2] as Transform3D).is_equal_approx(raw):
		PerfMonitor.record("rig.refresh_skipped", 0)
		_cache_paddle_rest_transform()
		_nvz_state.update(self)
		return true
	var lerp_pos: Vector3 = posture._posture_lerp_pos
	var lerp_rot: Vector3 = posture._posture_lerp_rot
	var lerp_basis: Basis = posture._posture_lerp_basis
	var lerp_initialized: bool = posture._posture_lerp_initialized


	posture.force_posture_update(owned_pose, false)
	paddle_node.global_transform = raw
	leg_ik.update_leg_ik(_consume_support_delta(), owned_pose)
	paddle_node.global_transform = raw
	arm_ik.update_arm_ik(0.0, owned_pose)
	paddle_node.global_transform = raw
	posture._posture_lerp_pos = lerp_pos
	posture._posture_lerp_rot = lerp_rot
	posture._posture_lerp_basis = lerp_basis
	posture._posture_lerp_initialized = lerp_initialized

	_cache_paddle_rest_transform()
	_nvz_state.update(self)
	return true

func _human_owns_physics_pose() -> bool:
	if is_ai or posture == null or posture.editor_preview_mode or _between_point_owner() != null: return false
	if leg_ik == null or not leg_ik.feet_initialized: return false
	var human = posture.human_contact
	if human == null or human.visual_pose == null: return false
	if hitting != null and human.phase < 0 and (hitting.serving_visual_active or hitting.is_in_follow_through): return false
	return true

func _ai_owns_physics_pose() -> bool:
	if not is_ai or posture == null or posture.editor_preview_mode or _between_point_owner() != null: return false
	if leg_ik == null or not leg_ik.feet_initialized: return false
	return (ai_brain != null and ai_brain.incoming_pose_override != null) or (hitting != null and not hitting._live_swing_presentation.is_empty())

var _between_presentation_tick: int = -1
func present_between_point_physics(owner, pose, delta: float) -> void:
	if owner == null or pose == null or posture == null or posture.editor_preview_mode: return
	posture.transition_pose_blend = pose
	posture.force_posture_update(pose)
	owner.present_arm_path(self, pose)
	_between_last_pose = posture.capture_displayed_pose()
	_between_pose_active = true
	_between_presentation_tick = Engine.get_physics_frames()
	_nvz_state.update(self)
	_head_gaze.update(self, _get_ball_ref(), delta)

func _owns_waiting_receiver_pose() -> bool:
	if posture == null or posture.editor_preview_mode or _between_point_owner() != null or get_tree().paused: return false
	var game = get_parent()
	if game == null or not "game_state" in game or game.game_state not in [game.GameState.WAITING, game.GameState.SERVING]: return false
	if game._is_practice() or game._tool_state_active() or game.get_server_actor() == self: return false
	if game.game_serve == null: return false
	var ball = _get_ball_ref()
	return ball != null and not ball.is_in_play

func _owns_carried_cup_pose() -> bool:
	var game = get_parent()
	return game != null and "game_serve" in game and game.game_serve != null and game.game_serve.owns_carried_cup_presentation(self)

# GameServe publishes only after the actual service pose and seated rig finish.
# This token survives the same-tick follow-through-to-READY flag transition.
var _physics_head_gaze_tick: int = -1
func complete_service_physics_presentation(delta: float) -> bool:
	if posture == null or posture.editor_preview_mode or not is_inside_tree() or get_tree().paused: return false
	if paddle_node == null or arm_ik == null or leg_ik == null or not leg_ik.feet_initialized: return false
	var pose: PostureDefinition = posture.transition_pose_blend
	if pose == null: return false
	# Hitting's service presenter ends with a leg/body refit. Finish the hands
	# against that actual body before either finite contact or publication.
	var committed_paddle: Transform3D = paddle_node.global_transform
	arm_ik.update_arm_ik(0.0, pose)
	paddle_node.global_transform = committed_paddle
	_cache_paddle_rest_transform()
	_nvz_state.update(self)
	if delta > 0.0: _advance_physics_head_gaze(delta)
	return true

func _advance_physics_head_gaze(delta: float) -> void:
	# An earlier physics owner may already have consumed this tick's interval.
	# Still refit the head to the final body with zero additional clock advance.
	var tick: int = Engine.get_physics_frames()
	var elapsed: float = maxf(delta, 0.0) if _physics_head_gaze_tick != tick else 0.0
	_physics_head_gaze_tick = tick
	_head_gaze.update(self, _get_ball_ref(), elapsed)

func _process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_process(delta)
	PerfMonitor.record("proc.player", Time.get_ticks_usec() - _pt)

func _perf_process(delta: float) -> void:
	if special_reach_driver != null and special_reach_driver.owns_presentation():
		special_reach_driver.present(delta)
		return
	if _between_point_owner() != null and _between_presentation_tick == Engine.get_physics_frames() and not posture.editor_preview_mode: return
	if posture != null and not posture.editor_preview_mode:
		var game = get_parent()
		if game != null and "game_serve" in game and game.game_serve != null and game.game_serve.has_committed_physics_presentation(self): return
	if _owns_waiting_receiver_pose() or _owns_carried_cup_pose(): return
	# The Human controller has already advanced and solved this actual rig in
	# physics. Unscaled held-input updates also solve their pose immediately.
	if _physics_human_presentation and _human_owns_physics_pose(): return
	if _physics_ai_presentation and _ai_owns_physics_pose(): return
	var editor_preview: bool = posture != null and posture.editor_preview_mode
	var incoming_pose: bool = posture != null and posture.human_contact != null and posture.human_contact.visual_pose != null
	var authored_swing: bool = hitting != null and (hitting.is_in_follow_through or hitting.charge_visual_active or hitting.serving_visual_active)
	var between = _between_point_owner()
	if between != null and not editor_preview and posture:
		var pose: PostureDefinition = between.pose_for(get_actor_id())
		if pose == null: pose = PostureLibrary.instance().get_def(PaddlePosture.READY)


		_between_last_pose = pose.lerp_with(pose, 0.0)
		var support_target: Vector3 = between.support_hand_target_for(get_actor_id())
		if support_target.is_finite():
			var local: Vector3 = support_target - global_position
			_between_last_pose.left_hand_mode = 4
			_between_last_pose.left_hand_offset = Vector3(local.dot(_get_forehand_axis()) + 0.15, local.y - 0.15, local.dot(_get_forward_axis()) - 0.55)
		posture.transition_pose_blend = pose
		authored_swing = true
		_between_pose_active = true
	elif _between_pose_active:
		_between_pose_active = false
		if not editor_preview and not authored_swing and posture:
			if posture.human_contact != null and _between_last_pose != null:
				posture.human_contact.visual_pose = _between_last_pose
				posture.transition_pose_blend = _between_last_pose
				incoming_pose = true
			else:
				posture.transition_pose_blend = null
		_between_last_pose = null
	var ball = _get_ball_ref()
	var neutral_ai: bool = is_ai and not editor_preview and not authored_swing and ball != null and ( not ball.is_in_play or ball.last_hit_by == player_num)
	if neutral_ai and posture:
		var guard: PostureDefinition = PostureLibrary.instance().get_def(PaddlePosture.READY)
		guard = _ready_tracking.apply(guard, self, ball.global_position, delta)
		posture.transition_pose_blend = guard
		incoming_pose = true
		_ai_guard_active = true
	elif _ai_guard_active:



		var waiting_for_incoming_owner: bool = between == null and not editor_preview and not authored_swing and ball != null and ball.is_in_play and ball.last_hit_by != player_num and ai_brain != null and ai_brain.incoming_pose_override == null and posture != null and posture.transition_pose_blend != null
		if waiting_for_incoming_owner:
			incoming_pose = true
		else:
			_ai_guard_active = false
			if not editor_preview and not authored_swing and posture: posture.transition_pose_blend = null
	var ai_pose: PostureDefinition = ai_brain.incoming_pose_override if is_ai and ai_brain and "incoming_pose_override" in ai_brain else null
	if ai_pose != null and between == null and not editor_preview and not (hitting and hitting.is_in_follow_through) and posture:
		posture.transition_pose_blend = ai_pose
		incoming_pose = true
		_ai_incoming_active = true
	elif _ai_incoming_active:
		_ai_incoming_active = false
		if not editor_preview and not authored_swing and not neutral_ai and not _ai_guard_active and posture:
			posture.transition_pose_blend = null
	var paddle_world: Transform3D = paddle_node.global_transform if paddle_node else Transform3D.IDENTITY


	if body_anim and not editor_preview and not incoming_pose and not authored_swing:
		body_anim.update_body_lean(delta)
		body_anim.update_crouch(delta)
		body_anim.update_idle_sway(delta)
		body_anim.update_body_track_ball(delta)
		if paddle_node:
			paddle_node.global_transform = paddle_world
	if posture and posture.transition_pose_blend and (editor_preview or authored_swing or incoming_pose):
		posture.force_posture_update(posture.transition_pose_blend, false)

	if posture:
		posture.force_paddle_head_to_ghost()
	PaddleReach.clamp_paddle_for_player(self)
	if leg_ik:
		var leg_def = posture.transition_pose_blend if posture and (editor_preview or authored_swing or incoming_pose) else null
		leg_ik.update_leg_ik(_consume_support_delta(), leg_def)


	if arm_ik:
		var arm_def = posture.transition_pose_blend if posture and (editor_preview or authored_swing or incoming_pose) else null
		arm_ik.update_arm_ik(delta, arm_def)
	if not editor_preview:
		_nvz_state.update(self)
		_head_gaze.update(self, _get_ball_ref(), delta)



func _cache_existing_paddle() -> void :
	body_pivot = get_node_or_null("BodyPivot")
	skeleton = get_node_or_null("Skeleton3D")
	if body_pivot:
		paddle_node = body_pivot.get_node_or_null("Paddle")
		right_arm_node = body_pivot.get_node_or_null("RightArm")
		left_arm_node = body_pivot.get_node_or_null("LeftArm")
		right_leg_node = body_pivot.get_node_or_null("RightLeg")
		left_leg_node = body_pivot.get_node_or_null("LeftLeg")
	else:
		paddle_node = get_node_or_null("Paddle")
		right_arm_node = get_node_or_null("RightArm")
		left_arm_node = get_node_or_null("LeftArm")
	if paddle_node == null:
		return

func _damp(current: float, target: float, halflife: float, dt: float) -> float:
	return lerpf(current, target, 1.0 - exp(-0.693 * dt / maxf(halflife, 0.001)))

func _damp_v3(current: Vector3, target: Vector3, halflife: float, dt: float) -> Vector3:
	var a: float = 1.0 - exp(-0.693 * dt / maxf(halflife, 0.001))
	return current.lerp(target, a)

func _cache_paddle_rest_transform() -> void :
	if paddle_node == null:
		return
	paddle_rest_position = paddle_node.position
	paddle_rest_rotation = paddle_node.rotation_degrees

func _ensure_paddle_ready() -> bool:
	if paddle_node == null:
		_cache_existing_paddle()
	return paddle_node != null

func _get_swing_sign() -> float:
	return -1.0 if court_side == 0 else 1.0

func _get_forward_axis() -> Vector3:
	if court_side == 0:
		return Vector3(0.0, 0.0, -1.0)
	return Vector3(0.0, 0.0, 1.0)

func _get_forehand_axis() -> Vector3:
	if court_side == 0:
		return Vector3(1.0, 0.0, 0.0)
	return Vector3(-1.0, 0.0, 0.0)

func _clamp_to_court(pos: Vector3) -> Vector3:
	pos.x = clamp(pos.x, min_x, max_x)
	if player_num == 0:
		pos.z = clamp(pos.z, min_z, max_z)
	else:
		pos.z = clamp(pos.z, min_z, max_z)
	return pos

func _get_ball_ref() -> RigidBody3D:
	if ball_ref != null and is_instance_valid(ball_ref):
		return ball_ref
	var game_node: Node3D = get_parent()
	if game_node == null:
		return null
	var found_ball: Node = game_node.find_child("Ball", true, false)
	if found_ball is RigidBody3D:
		ball_ref = found_ball
		return ball_ref
	return null

func get_runtime_posture_def(def_override = null):
	if def_override != null:
		return def_override
	if pose_controller:
		var composed = pose_controller.compose_runtime_posture(def_override)
		if composed != null:
			return composed
	return PostureLibrary.instance().get_def(paddle_posture)

func _get_human_input() -> Vector3:
	var game = get_parent()
	if game != null and game.has_method("_point_transition_blocks_movement") and game._point_transition_blocks_movement(): return Vector3.ZERO
	if game and "practice_launcher" in game and game.practice_launcher and game.practice_launcher.has_method("is_exchange_demo") and game.practice_launcher.is_exchange_demo():
		return game.practice_launcher.get_demo_movement()
	var input_2d: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Screen-relative: with the view turned for the far end, up is +z.
	if game != null and game.has_method("view_flipped") and game.view_flipped(): input_2d = -input_2d


	if posture and posture.human_contact:
		var human = posture.human_contact
		if human.phase == 0 and human.queued_movement_allowed or human.footwork.active and not human.footwork.ready_to_strike():
			return Vector3(input_2d.x, 0.0, input_2d.y)
	if game and "aim_controller" in game and game.aim_controller and game.aim_controller.should_plant_player():
		return Vector3.ZERO
	return Vector3(input_2d.x, 0.0, input_2d.y)

func request_contextual_jump(contact: Dictionary, charge: float) -> bool:
	var game = get_parent()
	if game != null and game.has_method("_point_transition_blocks_attempt") and game._point_transition_blocks_attempt(): return false
	if is_jumping or jump_landing_remaining > 0.0 or not _contextual_jump.is_empty(): return false
	if posture and posture.editor_preview_mode: return false
	if not is_equal_approx(global_position.y, ground_y) or charge < CONTEXTUAL_JUMP_CHARGE: return false
	if contact.get("posture", -1) != PaddlePosture.HIGH_OVERHEAD: return false
	var ball = _get_ball_ref()
	var def: PostureDefinition = contact.get("def")
	if ball == null or def == null: return false
	var point: Vector3 = contact.get("point", Vector3.ZERO)
	var lead: float = contact.get("time", 0.0)
	var launch_speed: float = sqrt(2.0 * JUMP_GRAVITY * CONTEXTUAL_JUMP_HEIGHT)
	var apex_time: float = launch_speed / JUMP_GRAVITY


	if point.y < ground_y + 0.85 or lead < apex_time + 0.025 or lead > 0.85: return false
	if Vector2(current_velocity.x, current_velocity.z).length() > 1.2: return false
	if not load("res://scripts/incoming_contact_planner.gd").legal_ball(self, ball, contact.get("bounces", 0)): return false
	if not load("res://scripts/incoming_contact_planner.gd").point_fits(self, def, point): return false
	var shoulder: Vector3 = load("res://scripts/stroke_body_pose.gd").shoulder_world(self, def) + Vector3.UP * CONTEXTUAL_JUMP_HEIGHT
	if shoulder.distance_to(point) > PaddleReach.MAX_HEAD_DISTANCE: return false


	var toward_net: float = maxf(0.0, current_velocity.dot(_get_forward_axis()))
	if absf(global_position.z) <= PickleballConstants.NON_VOLLEY_ZONE + 0.55 + toward_net * (lead + apex_time): return false
	if leg_ik and leg_ik.feet_initialized:
		for foot in [leg_ik.right_foot_smooth, leg_ik.left_foot_smooth]:
			if absf(foot.z) <= PickleballConstants.NON_VOLLEY_ZONE + 0.13: return false
	_contextual_jump = {"flight": ball.flight_id, "delay": lead - apex_time, 
		"speed": launch_speed}
	_jump_last_position = global_position
	_jump_position_initialized = true
	return true

func cancel_contextual_jump() -> void :

	_contextual_jump.clear()

func _update_jump_state(delta: float) -> void :
	if not is_finite(delta) or delta <= 0.0: return
	var displaced: bool = _jump_position_initialized and global_position.distance_to(_jump_last_position) > maxf(0.9, current_velocity.length() * delta * 2.5 + 0.1)
	var reset_to_floor: bool = is_jumping and _jump_was_airborne and global_position.y <= ground_y + 0.001
	if displaced or reset_to_floor:
		_contextual_jump.clear()
		global_position.y = ground_y
		vertical_velocity = 0.0
		is_jumping = false
		_jump_was_airborne = false
		jump_landing_remaining = 0.0
	if _jump_was_airborne and not is_jumping:
		jump_landing_remaining = CONTEXTUAL_JUMP_LANDING_TIME
	jump_landing_remaining = maxf(0.0, jump_landing_remaining - delta)
	if not _contextual_jump.is_empty():
		var ball = _get_ball_ref()
		var human = posture.human_contact if posture else null
		var legal_queue: bool = ball != null and ball.is_in_play and ball.flight_id == _contextual_jump.flight
		legal_queue = legal_queue and posture != null and not posture.editor_preview_mode
		if is_ai and ai_brain != null:
			# AI jump smash: keep the queued jump while the AI still plans that
			# High Overhead contact on this flight.
			legal_queue = legal_queue and ai_brain.ai_desired_posture == PaddlePosture.HIGH_OVERHEAD and ai_brain.ai_selected_contact_reachable
		else:
			legal_queue = legal_queue and human != null and human.phase == 0 and not human.contact.is_empty()
		if legal_queue and not (is_ai and ai_brain != null):
			legal_queue = human.contact.get("posture", -1) == PaddlePosture.HIGH_OVERHEAD
			legal_queue = legal_queue and human.contact.point.y >= ground_y + 0.85
			legal_queue = legal_queue and load("res://scripts/incoming_contact_planner.gd").legal_ball(self, ball, human.contact.get("bounces", 0))
			legal_queue = legal_queue and load("res://scripts/incoming_contact_planner.gd").point_fits(self, human.contact.def, human.contact.point)
		legal_queue = legal_queue and Vector2(current_velocity.x, current_velocity.z).length() <= 1.2
		legal_queue = legal_queue and absf(global_position.z) > PickleballConstants.NON_VOLLEY_ZONE + 0.55
		if legal_queue and leg_ik and leg_ik.feet_initialized:
			for foot in [leg_ik.right_foot_smooth, leg_ik.left_foot_smooth]:
				if absf(foot.z) <= PickleballConstants.NON_VOLLEY_ZONE + 0.13:
					legal_queue = false
		if not legal_queue:
			_contextual_jump.clear()
		else:
			_contextual_jump.delay -= delta
			if _contextual_jump.delay <= 0.0:
				vertical_velocity = _contextual_jump.speed
				is_jumping = true
				jump_takeoff_position = global_position
				_contextual_jump.clear()


	if is_jumping or global_position.y > ground_y:
		is_jumping = true
		vertical_velocity -= JUMP_GRAVITY * delta
	_jump_was_airborne = is_jumping
	_jump_last_position = global_position
	_jump_position_initialized = true

func _get_contact_state(distance_to_ball: float, ball_height: float, charge_ratio: float) -> int:
	if ball_height > 1.0 or distance_to_ball > 0.72 or charge_ratio < 0.18:
		return ShotContactState.POPUP
	if ball_height > 0.55 or distance_to_ball > 0.52 or charge_ratio < 0.32:
		return ShotContactState.STRETCHED
	return ShotContactState.CLEAN

func _get_popup_tendency(contact_state: int, distance_to_ball: float, ball_height: float, charge_ratio: float) -> float:
	var height_error: float = 0.0
	if ball_height < 0.4:
		height_error = clamp((0.4 - ball_height) * 0.8, 0.0, 0.3)
	elif ball_height > 0.9:
		height_error = clamp((ball_height - 0.9) * 0.5, 0.0, 0.3)
	var distance_error: float = clamp((distance_to_ball - 0.4) * 0.7, 0.0, 0.3)
	var charge_error: float = clamp((0.5 - charge_ratio) * 0.6, 0.0, 0.25)
	var contact_penalty: float = 0.0
	if contact_state == ShotContactState.STRETCHED:
		contact_penalty = 0.08
	elif contact_state == ShotContactState.POPUP:
		contact_penalty = 0.15
	return clamp(height_error + distance_error + charge_error + contact_penalty, 0.0, 0.6)

func _get_overhead_posture(ball_position: Vector3, horizontal_distance: float) -> int:
	var relative_ball_height: float = ball_position.y - ground_y
	if paddle_posture == PaddlePosture.HIGH_OVERHEAD:
		if relative_ball_height >= OVERHEAD_RELEASE_HEIGHT and horizontal_distance <= OVERHEAD_RELEASE_RADIUS:
			if relative_ball_height >= HIGH_OVERHEAD_TRIGGER_HEIGHT:
				return PaddlePosture.HIGH_OVERHEAD
			if relative_ball_height >= MEDIUM_OVERHEAD_TRIGGER_HEIGHT:
				return PaddlePosture.MEDIUM_OVERHEAD
		return -1
	if paddle_posture == PaddlePosture.MEDIUM_OVERHEAD:
		if relative_ball_height >= OVERHEAD_RELEASE_HEIGHT and horizontal_distance <= OVERHEAD_RELEASE_RADIUS:
			if relative_ball_height >= HIGH_OVERHEAD_TRIGGER_HEIGHT:
				return PaddlePosture.HIGH_OVERHEAD
			return PaddlePosture.MEDIUM_OVERHEAD
		return -1
	if horizontal_distance > OVERHEAD_TRIGGER_RADIUS:
		return -1
	if relative_ball_height >= HIGH_OVERHEAD_TRIGGER_HEIGHT:
		return PaddlePosture.HIGH_OVERHEAD
	if relative_ball_height >= MEDIUM_OVERHEAD_TRIGGER_HEIGHT:
		return PaddlePosture.MEDIUM_OVERHEAD
	return -1





func get_player_num() -> int:
	return player_num

func get_paddle_position() -> Vector3:
	if _ensure_paddle_ready():
		return paddle_node.global_position
	return global_position

func get_shot_impulse(ball_position: Vector3, charge_ratio: float = 0.5, silent: bool = false) -> Vector3:
	if hitting:
		return hitting.get_shot_impulse(ball_position, charge_ratio, silent)
	return Vector3.ZERO

func set_serve_charge_visual(charge_ratio: float, control_delta: float = -1.0) -> void :
	if hitting:
		hitting.set_serve_charge_visual(charge_ratio, control_delta)

func animate_serve_release(charge_ratio: float) -> void :
	if hitting:
		hitting.animate_serve_release(charge_ratio)

func _get_posture_charge_sign() -> float:
	if posture:
		return posture.get_posture_charge_sign()
	return 1.0

func _get_posture_offset_for(p: int) -> Vector3:
	if posture:
		return posture.get_posture_offset_for(p)
	return Vector3.ZERO

func _update_paddle_tracking(force: bool = false) -> void :
	if posture:
		posture.update_paddle_tracking(force)

func _draw_step_debug(r_target: Vector3, l_target: Vector3, r_origin: Vector3, l_origin: Vector3, r_swing: bool, l_swing: bool) -> void :
	if debug_visual:
		debug_visual.draw_step_debug(r_target, l_target, r_origin, l_origin, r_swing, l_swing)

func _deferred_log_body() -> void :
	if body_builder:
		await get_tree().process_frame
		await get_tree().process_frame
		body_builder.log_positions()

func can_volley_from_feet() -> bool:
	return _nvz_state.can_volley(self)

func _between_point_owner():
	var game = get_parent()
	if game == null or not "between_point_controller" in game: return null
	var owner = game.between_point_controller
	return owner if is_instance_valid(owner) and owner.is_active() else null
