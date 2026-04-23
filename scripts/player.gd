class_name PlayerController extends CharacterBody3D
## Player.gd - Player paddle with movement (slimmed — modules as child nodes)

const PLAYER_SPEED := PickleballConstants.PLAYER_SPEED
const AI_SPEED := PickleballConstants.AI_SPEED
const PADDLE_FORCE := PickleballConstants.PADDLE_FORCE
const AI_PADDLE_FORCE := PickleballConstants.AI_PADDLE_FORCE
const COURT_LENGTH := PickleballConstants.COURT_LENGTH
const COURT_WIDTH := PickleballConstants.COURT_WIDTH

const COURT_FLOOR_Y := PickleballConstants.FLOOR_Y
const SIDE_BOUND_MARGIN := PickleballConstants.SIDE_BOUND_MARGIN
const BASELINE_BOUND_MARGIN := PickleballConstants.BASELINE_BOUND_MARGIN
const NET_BOUND_MARGIN := PickleballConstants.NET_BOUND_MARGIN
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
	"FH","FW","BH","MO","HO","LF","LC","LB","CF","CB","WF","WB","VR",
	"MLF","MLB","MLC","MWF","MWB","LWF","LWB","RDY",
]
const MEDIUM_OVERHEAD_TRIGGER_HEIGHT := PickleballConstants.MEDIUM_OVERHEAD_TRIGGER_HEIGHT
const HIGH_OVERHEAD_TRIGGER_HEIGHT := PickleballConstants.HIGH_OVERHEAD_TRIGGER_HEIGHT
const OVERHEAD_TRIGGER_RADIUS := PickleballConstants.OVERHEAD_TRIGGER_RADIUS
const OVERHEAD_RELEASE_HEIGHT := PickleballConstants.OVERHEAD_RELEASE_HEIGHT
const OVERHEAD_RELEASE_RADIUS := PickleballConstants.OVERHEAD_RELEASE_RADIUS
const JUMP_VELOCITY := PickleballConstants.JUMP_VELOCITY
const JUMP_GRAVITY := PickleballConstants.JUMP_GRAVITY

enum PaddlePosture {
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

enum BasePoseState {
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

enum PoseIntent {
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

enum ShotContactState {
	CLEAN,
	STRETCHED,
	POPUP,
}

enum AIState {
	INTERCEPT_POSITION,
	CHARGING,
	HIT_BALL,
}

# --- Core state ---
var player_num: int = 0
var move_speed: float = PLAYER_SPEED
var paddle_force: float = PADDLE_FORCE
var min_x: float
var max_x: float
var min_z: float
var max_z: float
var bounds_ready: bool = false
var is_ai: bool = false
var manual_crouch: bool = false  # C key toggle
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

# --- Child node references ---
var ai_brain
var hitting
var leg_ik
var body_anim
var pose_controller
var posture
var debug_visual
var arm_ik
var awareness_grid = null
var body_builder

@warning_ignore("unused_signal")
signal hit_ball(ball: RigidBody3D, direction: Vector3)

func _ready() -> void:
	_cache_existing_paddle()

func setup(player_id: int, bounds: Dictionary, paddle_color: Color, start_pos: Vector3, ai_enabled: bool = false) -> void:
	player_num = player_id
	move_speed = AI_SPEED if player_id == 1 else PLAYER_SPEED
	paddle_force = AI_PADDLE_FORCE if player_id == 1 else PADDLE_FORCE
	is_ai = ai_enabled
	ai_movement_enabled = not is_ai or true

	set_meta("player_num", player_id)
	set_meta("move_speed", move_speed)

	if player_num == 0:
		min_x = bounds.left - SIDE_BOUND_MARGIN
		max_x = bounds.right + SIDE_BOUND_MARGIN
		min_z = NET_BOUND_MARGIN
		max_z = bounds.bottom + BASELINE_BOUND_MARGIN
	else:
		min_x = bounds.left - SIDE_BOUND_MARGIN
		max_x = bounds.right + SIDE_BOUND_MARGIN
		min_z = bounds.top - BASELINE_BOUND_MARGIN
		max_z = -NET_BOUND_MARGIN

	bounds_ready = true

	global_position = start_pos
	ground_y = start_pos.y

	body_builder = load("res://scripts/player_body_builder.gd").new()
	body_builder.name = "BodyBuilder"
	body_builder._player = self
	add_child(body_builder)
	body_builder.build(paddle_color)

	# Instantiate extracted modules as child nodes
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

	arm_ik = load("res://scripts/player_arm_ik.gd").new()
	arm_ik.name = "ArmIK"
	arm_ik._player = self
	add_child(arm_ik)

	var grid_script = load("res://scripts/player_awareness_grid.gd")
	awareness_grid = grid_script.new()
	awareness_grid.name = "AwarenessGrid"
	awareness_grid._player = self
	add_child(awareness_grid)

	if is_ai:
		ai_brain._setup_ai_trajectory()

	call_deferred("_deferred_log_body")

func set_ai_movement_enabled(enabled: bool) -> void:
	ai_movement_enabled = enabled
	if not enabled:
		ai_ball_bounced_on_side = false
		ai_is_charging = false
		print("[BOS] reset by set_ai_movement_enabled(false)")

func notify_ball_bounced(bounce_pos: Vector3) -> void:
	if player_num == 1 and bounce_pos.z < 0.0:
		ai_ball_bounced_on_side = true
		print("[BOUNCE] P1 bos=true z=%.1f" % bounce_pos.z)
	elif player_num == 0 and bounce_pos.z > 0.0:
		ai_ball_bounced_on_side = true

func _wire_hitbox() -> void:
	if paddle_hitbox and ai_brain:
		paddle_hitbox.body_entered.connect(ai_brain._on_hitbox_body_entered.bind(paddle_node))
	# Posture ghosts + indicators created by child modules after they're added
	if posture:
		posture.place_paddle_at_side()
		posture.create_posture_ghosts(Color(1, 0.85, 0.2))
	if debug_visual:
		debug_visual.create_ai_indicators()
		debug_visual.create_human_indicators()

# --- Physics / Process ---

func _physics_process(delta: float) -> void:
	var input_dir: Vector3 = Vector3.ZERO
	_update_jump_state(delta)
	if ai_brain and ai_brain.ai_hit_cooldown > 0.0:
		ai_brain.ai_hit_cooldown = max(ai_brain.ai_hit_cooldown - delta, 0.0)

	if is_ai:
		if ai_movement_enabled and ai_brain:
			input_dir = ai_brain.get_ai_input()
		if ai_brain:
			ai_brain._update_ai_trajectory_fade(delta)
	elif player_num == 0:
		input_dir = _get_human_input()

	if input_dir.length() > 0.0:
		input_dir = input_dir.normalized()

	velocity = input_dir * move_speed
	current_velocity = velocity
	global_position += velocity * delta
	global_position.y += vertical_velocity * delta
	if global_position.y <= ground_y:
		global_position.y = ground_y
		vertical_velocity = 0.0
		is_jumping = false

	if bounds_ready:
		global_position.x = clamp(global_position.x, min_x, max_x)
		global_position.z = clamp(global_position.z, min_z, max_z)

	# Feed trajectory to posture and grid (must be in _physics_process with grid update)
	if not is_ai and debug_visual:
		var b: RigidBody3D = _get_ball_ref()
		if b:
			debug_visual.update_human_intercept_pools(b)
			if posture:
				posture.set_trajectory_points(debug_visual._last_trajectory_points)
			if awareness_grid:
				awareness_grid.set_trajectory_points(debug_visual._last_trajectory_points)
	if posture:
		posture.update_paddle_tracking(false)
	if pose_controller:
		pose_controller.update_runtime_pose_state(delta)
	if posture:
		posture.update_posture_ghosts()
	if awareness_grid:
		awareness_grid.update_grid(delta)
	if debug_visual:
		debug_visual.update_ai_indicators()
	if ai_brain:
		ai_brain._try_ai_hit_ball()

func _process(delta: float) -> void:
	if body_anim:
		body_anim.update_body_lean(delta)
		body_anim.update_crouch(delta)
		body_anim.update_idle_sway(delta)
		body_anim.update_body_track_ball(delta)
	# Force paddle to ghost BEFORE arm IK so arms reach the correct position
	if posture:
		posture.force_paddle_head_to_ghost()
	if arm_ik:
		var arm_def = posture.transition_pose_blend if posture and posture.editor_preview_mode else null
		arm_ik.update_arm_ik(delta, arm_def)
	if leg_ik:
		var leg_def = posture.transition_pose_blend if posture and posture.editor_preview_mode else null
		leg_ik.update_leg_ik(delta, leg_def)

# --- Utility functions (shared with child nodes) ---

func _cache_existing_paddle() -> void:
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

func _cache_paddle_rest_transform() -> void:
	if paddle_node == null:
		return
	paddle_rest_position = paddle_node.position
	paddle_rest_rotation = paddle_node.rotation_degrees

func _ensure_paddle_ready() -> bool:
	if paddle_node == null:
		_cache_existing_paddle()
	return paddle_node != null

func _get_swing_sign() -> float:
	return -1.0 if player_num == 0 else 1.0

func _get_forward_axis() -> Vector3:
	if player_num == 0:
		return Vector3(0.0, 0.0, -1.0)
	return Vector3(0.0, 0.0, 1.0)

func _get_forehand_axis() -> Vector3:
	if player_num == 0:
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
	return load("res://scripts/posture_library.gd").new().get_def(paddle_posture)

func _get_human_input() -> Vector3:
	var input_2d: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return Vector3(input_2d.x, 0.0, input_2d.y)

func _update_jump_state(delta: float) -> void:
	if player_num == 0 and not is_ai and Input.is_key_pressed(KEY_J) and not is_jumping and is_equal_approx(global_position.y, ground_y):
		vertical_velocity = JUMP_VELOCITY
		is_jumping = true
	if is_jumping or global_position.y > ground_y:
		vertical_velocity -= JUMP_GRAVITY * delta

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

# --- External API wrappers (called by game.gd) ---

# Used by ball.gd's body-hit detection. Centralizes access to player_num so the
# ball doesn't have to touch the field directly.
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

func set_serve_charge_visual(charge_ratio: float) -> void:
	if hitting:
		hitting.set_serve_charge_visual(charge_ratio)

func animate_serve_release(charge_ratio: float) -> void:
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

func _update_paddle_tracking(force: bool = false) -> void:
	if posture:
		posture.update_paddle_tracking(force)

func _draw_step_debug(r_target: Vector3, l_target: Vector3, r_origin: Vector3, l_origin: Vector3, r_swing: bool, l_swing: bool) -> void:
	if debug_visual:
		debug_visual.draw_step_debug(r_target, l_target, r_origin, l_origin, r_swing, l_swing)

func _deferred_log_body() -> void:
	if body_builder:
		await get_tree().process_frame
		await get_tree().process_frame
		body_builder.log_positions()
