class_name PlayerLegIK extends Node



const _PostureSkeletonApplier = preload("res://scripts/posture_skeleton_applier.gd")
const BodyPose = preload("res://scripts/stroke_body_pose.gd")
const Dimensions = preload("res://scripts/player_body_dimensions.gd")
const MotionState = preload("res://scripts/footwork_motion_state.gd")
const ShotFootwork = preload("res://scripts/shot_footwork_profile.gd")
const DrivePreparation = preload("res://scripts/drive_preparation_state.gd")
const FootPitchGrounding = preload("res://scripts/foot_pitch_grounding.gd")
const SplitTiming = preload("res://scripts/split_step_timing.gd")
const BackhandReach = preload("res://scripts/backhand_reach_profile.gd")
const WideBackhandReach = preload("res://scripts/wide_backhand_reach_profile.gd")
const LiveArmReach = preload("res://scripts/live_transition_arm_reach.gd")
const COURT_FLOOR_Y: = PickleballConstants.FLOOR_Y
const HIP_HEIGHT: = Dimensions.HIP_HEIGHT
const THIGH_LENGTH: = Dimensions.THIGH_LENGTH
const SHIN_LENGTH: = Dimensions.SHIN_LENGTH
const STRIDE_LEN_WALK: = 0.24
const STRIDE_LEN_RUN: = 0.4
const MAX_STEP_DISTANCE: = 0.8
const STEP_DURATION_WALK: = 0.3
const STEP_DURATION_RUN: = 0.14
const STANCE_STEP_DURATION: = 0.18
const STEP_LIFT_HEIGHT: = 0.035
const STEP_RUN_LIFT_HEIGHT: = 0.065
const RUN_ENTER_SPEED: = 1.65
const RUN_EXIT_SPEED: = 1.35
const RUN_CONTACT_TRAVEL: = 0.64
const RUN_SETTLE_DURATION: = 0.14
const RUN_SWING_GROUND_MATCH := 0.0   # 0: plain smoothstep swing (as before); 1: lift-off and landing fully match the ground speed
const RUN_PLANT_AFTER_SWING := true   # false: a lifted foot may be re-planted mid-swing (as before)
const STANCE_STEP_LIFT: = 0.035
const FOOT_UNLOCK_RADIUS: = 0.35
const MIN_FOOT_SEPARATION: = 0.18
const STANCE_REPLANT_DISTANCE: = 0.04
const TELEPORT_DISTANCE: = 0.85
const MAX_SUBSTEP: = 1.0 / 120.0
const ANKLE_HEIGHT: = COURT_FLOOR_Y + 0.04
const SUPPORT_READY_SPEED: = 0.18
const SUPPORT_READY_POSITION_TOLERANCE: = 0.065
const SUPPORT_READY_YAW_TOLERANCE: = 10.0


var right_step_origin: = Vector3.ZERO
var right_step_target: = Vector3.ZERO
var left_step_origin: = Vector3.ZERO
var left_step_target: = Vector3.ZERO
var right_step_t: = 1.0
var left_step_t: = 1.0
var step_foot: = 0
var gait_arc_length: = 0.0
var double_support_timer: = 0.0
var dist_since_last_step: = 0.0
var right_foot_locked: = false
var left_foot_locked: = false
var right_foot_lock_pos: = Vector3.ZERO
var left_foot_lock_pos: = Vector3.ZERO
var right_foot_smooth: = Vector3.ZERO
var left_foot_smooth: = Vector3.ZERO
var right_foot_was_swing: = false
var left_foot_was_swing: = false
var feet_initialized: = false
var hip_shift: = 0.0
var hip_shift_applied: = Vector3.ZERO
var _live_stance_initialized: = false
var _live_step_side: = 0
var _live_step_progress: = 1.0
var _live_step_origin: = Vector3.ZERO
var _live_step_target: = Vector3.ZERO

var _player
var _last_body_position: = Vector3.ZERO
var _blocked_time: = 0.0
var _moving: = false
var _active_side: = -1
var _step_elapsed: = 0.0
var _step_duration: = STANCE_STEP_DURATION
var _step_lift: = STANCE_STEP_LIFT
var _step_velocity: = Vector3.ZERO
var _travel_velocity: = Vector3.ZERO
var _run_active: = false
var _run_phase: = 0.0
var _run_stopping: = false
var _run_stop_elapsed: = 0.0
var _run_stop_duration := RUN_SETTLE_DURATION
var _run_forward := Vector3.FORWARD
var _turn_cadence_remaining := 0.0
var _crossover_entry_side := -1
var crossover_entry_count := 0
var _run_origins: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _run_swing_starts: Array[float] = [0.0, 0.0]
var _run_previous_phases: Array[float] = [0.0, 0.0]
var _run_early_liftoff: Array[bool] = [false, false]
var _run_stop_targets: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _right_yaw: = 0.0
var _left_yaw: = 0.0


var right_contact_serial: = 0
var left_contact_serial: = 0
var _yaw_from: Array[float] = [0.0, 0.0]
var _yaw_target: Array[float] = [0.0, 0.0]
# Captured knee headings exclude authored toe-out, already present in poles.
var _knee_yaw: Array[float] = [0.0, 0.0]
var _knee_yaw_from: Array[float] = [0.0, 0.0]
var _knee_yaw_target: Array[float] = [0.0, 0.0]
var _heading_forward: = Vector3.FORWARD
var _landing_forward: = Vector3.FORWARD
var _ready_facing_deg := 0.0
var _retreat_distance := 0.0
var _heading_angle := 0.0
var _body_turn_reference_deg := 0.0
var _route_distance := 0.0
var _route_direction := Vector3.ZERO
var drive_preparation := DrivePreparation.new()
var _drive_lifecycle := "invalid"
var _split_pose_active := false
var _split_support_released := false
var _split_ground_feet: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _split_body_offset := 0.0
var _split_body_applied := false
var _split_ankle_pitch := 0.0
var applied_foot_pitch_deg: Array[float] = [0.0, 0.0]
var _pitch_reported: Array[bool] = [false, false]
var _pitch_requested: Array[float] = [0.0, 0.0]
var _pitch_procedural: Array[float] = [0.0, 0.0]
var _pitch_limited: Array[bool] = [false, false]
var _pitch_grounded: Array[bool] = [true, true]
var motion_state := MotionState.new()
var _shot_context: Dictionary = {}
var locomotion_state := "ready"
# A planted knee may oppose a modest athletic hip opening, never a half turn.
const MAX_SUPPORT_TURN_DEGREES := 42.0
var locomotion_phase := "ready"
var locomotion_gait := "stance"
const LATERAL_SHUFFLE_DISTANCE := 0.48
## Fast side shuffle (the running foot cycle while the state is lateral_shuffle): each foot lands
## this far out on its own side, and is on the ground for a shorter stretch at a quicker beat, so
## the trailing foot closes toward the lead foot but never reaches or passes it. Before, both feet
## landed 0.13 m either side of the body and travelled 0.55 m on the ground: they crossed by 0.27 m.
## Prep steps (charged footwork "adjust": the last 0.3 m to the hitting spot): quick, small
## stutter steps to set the spacing, instead of two slow ones.
const STUTTER_STRIDE := 0.15
const STUTTER_TIME := 0.10
const STUTTER_LIFT := 0.022
const SHUFFLE_HALF_WIDTH := 0.26
const SHUFFLE_CONTACT_TRAVEL := 0.30
const SHUFFLE_CADENCE := 1.65
const LATERAL_RUN_DISTANCE := 1.20
const TURN_RATE := 300.0
var locomotion_hip_yaw_deg := 0.0
var locomotion_body_weight := 1.0
var locomotion_mode: = "stance"
var _heading_def
var _locomotion_body_applied: = false
var _airborne: = false
const AIR_LEGS_FULL_HEIGHT := 0.12   # jump height (m) at which authored air legs are fully applied
var _air_time: = 0.0
var _air_right_offset: = Vector3.ZERO
var _air_left_offset: = Vector3.ZERO
var _landing_remaining: = 0.0
const LANDING_DURATION: = 0.24

func _ready() -> void :
	_player = get_parent() as CharacterBody3D

func _stance_targets(def, base: Vector3, authored: bool = false) -> Array[Vector3]:
	# Foot placement is independent of body translation and rotation.
	# Only explicit stance/foot edits or locomotion author new contacts.
	base += drive_preparation.offset if drive_preparation.active() else BodyPose.foot_position_offset(_player, def)
	var fh: Vector3 = _player._get_forehand_axis()
	var fwd: Vector3 = _player._get_forward_axis()
	if not authored and absf(_ready_facing_deg) > 0.001:
		fh = fh.rotated(Vector3.UP, -deg_to_rad(_ready_facing_deg))
		fwd = fwd.rotated(Vector3.UP, -deg_to_rad(_ready_facing_deg))
	var targets: Array[Vector3] = []
	for i: int in 2:
		var side: int = 1 - 2 * i
		var right: bool = side == 1
		var foot: Vector3 = base + fh * side * 0.27
		if (drive_preparation.state == "setup" or drive_preparation.state == "hold"):
			var local: Vector3 = drive_preparation.profile.right if right else drive_preparation.profile.left
			# The authored profile already describes court-space foot placement;
			# do not rotate it a second time by its body/hip setup heading.
			foot = base + _player._get_forehand_axis() * local.x + _player._get_forward_axis() * local.z
		elif drive_preparation.state == "recover":
			var ready = PostureLibrary.instance().get_def(20)
			var lead: bool = (right and ready.lead_foot == 0) or (not right and ready.lead_foot == 1)
			foot = base + fh * side * ready.stance_width * 0.5 + fwd * (ready.front_foot_forward if lead else ready.back_foot_back)
			foot += _PostureSkeletonApplier.stance_offset(ready.right_foot_offset if right else ready.left_foot_offset, fh, fwd)
		elif def != null:
			var lead: bool = (right and def.lead_foot == 0) or ( not right and def.lead_foot == 1)
			var forward: float = def.front_foot_forward if lead else def.back_foot_back
			var offset: Vector3 = def.right_foot_offset if right else def.left_foot_offset
			foot = base + fh * side * def.stance_width * 0.5 + fwd * forward + _PostureSkeletonApplier.stance_offset(offset, fh, fwd)


		if not authored:
			foot.y = maxf(ANKLE_HEIGHT, foot.y)
			var lateral: float = (foot - base).dot(fh) * side
			if lateral < MIN_FOOT_SEPARATION * 0.5:
				foot += fh * side * (MIN_FOOT_SEPARATION * 0.5 - lateral)
		targets.append(foot)
	return targets

func _landing_yaw(side: int) -> float:
	var authored: float = 0.0
	if (drive_preparation.state == "setup" or drive_preparation.state == "hold"):
		authored = float(drive_preparation.profile.right_yaw if side == 0 else drive_preparation.profile.left_yaw) - drive_preparation.facing_deg
	elif drive_preparation.state == "recover":
		var ready = PostureLibrary.instance().get_def(20)
		authored = ready.right_foot_yaw_deg if side == 0 else ready.left_foot_yaw_deg
	elif _heading_def != null:
		# Legacy rotated guards authored their gaze yaw into both toes. Strip
		# that visual-only yaw; it is not permission to move a planted foot.
		authored = (_heading_def.right_foot_yaw_deg if side == 0 else _heading_def.left_foot_yaw_deg) - float(_heading_def.get_meta("ready_facing_yaw_deg", 0.0))
	return atan2( - _landing_forward.x, - _landing_forward.z) - deg_to_rad(authored)

func _start_yaw_swing(side: int) -> void :
	_yaw_from[side] = _right_yaw if side == 0 else _left_yaw
	_yaw_target[side] = _landing_yaw(side)
	_knee_yaw_from[side] = _knee_yaw[side]
	_knee_yaw_target[side] = atan2(-_landing_forward.x,-_landing_forward.z)

func _swing_yaw(side: int, progress: float) -> void :
	# Re-aim only the airborne shoe. A wall reversal or braking turn can change
	# intent before touchdown; keeping the old captured target leaves a newly
	# planted knee facing the previous route for an entire extra step.
	_yaw_target[side] = _landing_yaw(side)
	_knee_yaw_target[side] = atan2(-_landing_forward.x, -_landing_forward.z)
	var angle: float = lerp_angle(_yaw_from[side],_yaw_target[side],smoothstep(0.0,1.0,progress))
	_knee_yaw[side] = lerp_angle(_knee_yaw_from[side],_knee_yaw_target[side],smoothstep(0.0,1.0,progress))
	if side == 0: _right_yaw = angle
	else: _left_yaw = angle

func _plant_yaw(side: int) -> void :
	_swing_yaw(side, 1.0)
	if side == 0: right_contact_serial += 1
	else: left_contact_serial += 1


func _charged_footwork():
	if _player == null or not "posture" in _player or _player.posture == null: return null
	if not "human_contact" in _player.posture or _player.posture.human_contact == null: return null
	var contact = _player.posture.human_contact
	return contact.footwork if "footwork" in contact else null



## Context from the committed tactical shot. It never changes player axes,
## root position, authored assets, contact legality, or limb limits.
func set_shot_context(context: Dictionary) -> void:
	_shot_context = context.duplicate(true)

func clear_shot_context() -> void:
	_shot_context.clear()

func shot_context() -> Dictionary:
	var result: Dictionary = _shot_context.duplicate()
	var charged = _charged_footwork()
	if charged != null and "active" in charged and charged.active and charged.has_method("motion_context"):
		result.merge(charged.motion_context(), true)
	elif "posture" in _player and _player.posture != null:
		var human = _player.posture.human_contact if "human_contact" in _player.posture else null
		if human != null and "contact" in human and "anticipated_contact" in human:
			var selected: Dictionary = human.contact if not human.contact.is_empty() else human.anticipated_contact
			result.merge(ShotFootwork.context_from(selected), true)
			if not selected.is_empty(): result["time_to_contact"] = selected.get("time", INF)
	if _player.has_method("_get_ball_ref"):
		var ball = _player._get_ball_ref()
		if ball != null:
			if result.has("flight_id") and int(result.flight_id) != ball.flight_id:
				result.erase("lob_retrieval"); result.erase("time_to_contact")
			result["flight_id"] = ball.flight_id
			if not ball.is_in_play or ball.last_hit_by == _player.player_num:
				result["lob_retrieval"] = false
	return result

func is_support_ready(side: int) -> bool:
	if side < 0 or side > 1 or not feet_initialized: return false
	if _airborne or _landing_remaining > 0.0 or _active_side >= 0 or _run_active or _run_stopping: return false
	if Vector2(_player.current_velocity.x, _player.current_velocity.z).length() > SUPPORT_READY_SPEED: return false
	var locked: bool = right_foot_locked if side == 0 else left_foot_locked
	var foot: Vector3 = right_foot_smooth if side == 0 else left_foot_smooth
	if not locked or absf(foot.y - ANKLE_HEIGHT) > 0.005: return false
	var yaw: float = _right_yaw if side == 0 else _left_yaw
	if absf(angle_difference(yaw, _landing_yaw(side))) > deg_to_rad(SUPPORT_READY_YAW_TOLERANCE): return false
	if absf(_player._get_forward_axis().rotated(Vector3.UP, -deg_to_rad(_ready_facing_deg)).signed_angle_to(_heading_forward, Vector3.UP)) > deg_to_rad(SUPPORT_READY_YAW_TOLERANCE): return false
	var base: = Vector3(_player.global_position.x, ANKLE_HEIGHT, _player.global_position.z)
	var targets: Array[Vector3] = _stance_targets(_heading_def, base)
	if foot.distance_to(targets[side]) > SUPPORT_READY_POSITION_TOLERANCE: return false


	var other: int = 1 - side
	var other_foot: Vector3 = right_foot_smooth if other == 0 else left_foot_smooth
	var other_locked: bool = right_foot_locked if other == 0 else left_foot_locked
	var other_yaw: float = _right_yaw if other == 0 else _left_yaw
	return other_locked and other_foot.distance_to(targets[other]) <= SUPPORT_READY_POSITION_TOLERANCE and absf(angle_difference(other_yaw, _landing_yaw(other))) <= deg_to_rad(SUPPORT_READY_YAW_TOLERANCE)

func _ready_facing_for(_def) -> float:
	var owner = _player._between_point_owner()
	if owner != null and owner.has_method("ready_facing_for_actor"): return owner.ready_facing_for_actor(_player)
	return drive_preparation.facing_deg if drive_preparation.active() else 0.0

var _updating := false
var _split_sample_ready := false
var _split_sample: Dictionary = {}
func _split_step_sample() -> Dictionary:
	# Perf: sampled once per leg update (was up to 3 dictionaries); a split-step
	# cancel inside the update clears it (_cancel_split_step).
	if _split_sample_ready: return _split_sample
	_split_sample = _read_split_step_sample()
	_split_sample_ready = _updating
	return _split_sample

func _read_split_step_sample() -> Dictionary:
	if "pose_controller" not in _player or _player.pose_controller == null or "split_step" not in _player.pose_controller: return {}
	var split = _player.pose_controller.split_step
	return split.sample() if split != null else {}

func _cancel_split_step(reason: String) -> void:
	_player.pose_controller.split_step.cancel(reason)
	_split_sample_ready = false

func _split_hard_interrupted() -> bool:
	if _motion_context() == "pickup": return true
	if "posture" in _player and _player.posture != null:
		if _player.posture.editor_preview_mode: return true
		var human = _player.posture.human_contact if "human_contact" in _player.posture else null
		if human != null:
			if human.phase in [0, 1, 2, 3]: return true
			var preparation: Dictionary = human.preparation_contact()
			if not preparation.is_empty() and float(preparation.get("time", INF)) <= SplitTiming.CONTACT_GUARD: return true
	if "hitting" in _player and _player.hitting != null:
		if _player.hitting.serving_visual_active or _player.hitting.is_in_follow_through: return true
	if "is_jumping" in _player and _player.is_jumping: return true
	if "pose_controller" in _player and _player.pose_controller != null and "split_observer" in _player.pose_controller:
		var context: Dictionary = _player.pose_controller.split_observer.last_context
		if bool(context.get("own_stroke", false)) or float(context.get("time_to_contact", INF)) <= SplitTiming.CONTACT_GUARD: return true
	if _player.has_method("_get_ball_ref"):
		var ball = _player._get_ball_ref()
		if ball == null: return true
		if not ball.is_in_play:
			var game = _player.get_parent()
			var receiving: bool = game != null and "game_serve" in game and game.game_serve != null and game.game_serve.is_release_pending() and game.serving_team != _player.player_num
			if not receiving: return true
	return false

func _finish_split_pose() -> void:
	if not _split_pose_active: return
	right_foot_smooth = _split_ground_feet[0]; left_foot_smooth = _split_ground_feet[1]
	if _split_support_released:
		# A new landing contact, never a dragged continuation of the old plant.
		right_contact_serial += 1; left_contact_serial += 1
	right_foot_lock_pos = right_foot_smooth; left_foot_lock_pos = left_foot_smooth
	right_foot_locked = true; left_foot_locked = true
	right_step_t = 1.0; left_step_t = 1.0
	_split_pose_active = false; _split_support_released = false; _split_body_offset = 0.0; _split_ankle_pitch = 0.0

func _apply_split_step(sample: Dictionary, delta: float, base: Vector3, velocity: Vector3, def) -> bool:
	var phase: String = str(sample.get("phase", "ready"))
	var can_present: bool = sample.get("active", false) and phase in ["split_load", "split_unweight", "split_land"]
	can_present = can_present and not _split_hard_interrupted()
	can_present = can_present and velocity.length() <= MotionState.IDLE_SPEED and not drive_preparation.active() and _motion_context() != "pickup"
	can_present = can_present and not ("hitting" in _player and _player.hitting != null and (_player.hitting.serving_visual_active or _player.hitting.is_in_follow_through))
	can_present = can_present and not ("is_jumping" in _player and _player.is_jumping)
	if not can_present:
		_finish_split_pose(); return false
	if not _split_pose_active:
		if _active_side >= 0 or _run_active or not right_foot_locked or not left_foot_locked: return false
		_split_ground_feet = [right_foot_smooth, left_foot_smooth]
		_split_pose_active = true; _split_support_released = false
	var lift: float = clampf(float(sample.get("foot_lift", 0.0)), 0.0, 0.025)
	right_foot_smooth = _split_ground_feet[0] + Vector3.UP * lift
	left_foot_smooth = _split_ground_feet[1] + Vector3.UP * lift
	if lift > 0.00001:
		_split_support_released = true
		right_foot_locked = false; left_foot_locked = false
		right_step_t = 0.5; left_step_t = 0.5
	elif _split_support_released:
		right_contact_serial += 1; left_contact_serial += 1
		_split_support_released = false
		right_foot_locked = true; left_foot_locked = true
		right_foot_lock_pos = right_foot_smooth; left_foot_lock_pos = left_foot_smooth
		right_step_t = 1.0; left_step_t = 1.0
	_split_body_offset = clampf(float(sample.get("body_lift", 0.0)), 0.0, 0.025) - clampf(float(sample.get("crouch", 0.0)), 0.0, 0.028)
	_split_ankle_pitch = clampf(float(sample.get("ankle_pitch_deg", 0.0)), 0.0, 12.0) if lift > 0.00001 else 0.0
	_update_heading(delta, Vector3.ZERO, 0.0)
	locomotion_state = phase; locomotion_phase = "split"; locomotion_gait = "stance"
	_last_body_position = base
	right_foot_was_swing = lift > 0.00001; left_foot_was_swing = right_foot_was_swing
	_solve_legs(delta, def)
	return true

# Perf: the drive-preparation input is written to these fields (was a new
# Dictionary per tick). _dp_candidate is empty unless a setup candidate is valid.
var _dp_lifecycle := "reset"
var _dp_authored := false
var _dp_candidate: Dictionary = {}
var _dp_no_candidate: Dictionary = {}
var _dp_ai_candidate: Dictionary = {}
func _drive_preparation_input() -> void:
	_dp_lifecycle = "reset"; _dp_authored = false; _dp_candidate = _dp_no_candidate
	if _motion_context() == "pickup" or not _player.has_method("_get_ball_ref"): return
	if "is_jumping" in _player and _player.is_jumping: return
	var split := _split_step_sample()
	if split.get("active", false):
		var phase: String = str(split.get("phase", ""))
		if phase == "split_load" or phase == "split_unweight" or phase == "split_land" and float(split.get("crouch", 0.0)) > 0.00001:
			_dp_lifecycle = "pause"; return
	if "posture" not in _player or _player.posture == null or _player.posture.editor_preview_mode: return
	if "hitting" in _player and _player.hitting != null and _player.hitting.serving_visual_active: return
	var ball = _player._get_ball_ref()
	if ball == null:
		_dp_lifecycle = "invalid"; return
	var human = _player.posture.human_contact if "human_contact" in _player.posture else null
	var candidate: Dictionary = _dp_no_candidate
	var lifecycle := "receive"
	var authored := false
	if human != null:
		authored = _player.hitting.charge_visual_active or human.phase >= 0
		if human._charge_cancel_recovering: lifecycle = "cancel"
		elif human.phase == 2 or human.phase == 3: lifecycle = "finish"
		elif human.phase == 4: lifecycle = "recover"
		elif human.phase == 1: lifecycle = "swing"
		if lifecycle == "receive": candidate = human.preparation_contact()
	elif "is_ai" in _player and _player.is_ai and "ai_brain" in _player and _player.ai_brain != null:
		var brain = _player.ai_brain
		authored = _player.hitting.charge_visual_active or _player.hitting.is_in_follow_through
		if _player.hitting.is_in_follow_through: lifecycle = "finish"
		elif brain.ai_selected_contact_reachable:
			var pose = brain.ai_reach_pose if brain.ai_reach_pose != null else PostureLibrary.instance().get_def(brain.ai_desired_posture)
			# Reused each tick (read only below); same four keys every time.
			_dp_ai_candidate["def"] = pose
			_dp_ai_candidate["point"] = brain.ai_predicted_contact_position
			_dp_ai_candidate["time"] = brain.ai_selected_contact_time
			_dp_ai_candidate["bounces"] = 0
			candidate = _dp_ai_candidate
	if lifecycle != "finish" and lifecycle != "recover" and (not ball.is_in_play or ball.last_hit_by == _player.player_num or ball.bounces_since_last_hit >= 2): lifecycle = "invalid"
	if lifecycle == "receive" and not candidate.is_empty():
		var def = candidate.get("def")
		var point: Vector3 = candidate.get("point", Vector3.INF)
		var valid: bool = def != null and def.family in [0, 1] and not candidate.get("directional_only", false) and point.is_finite()
		valid = valid and ball.bounces_since_last_hit + int(candidate.get("bounces", 0)) > 0
		# Central/overhead/volley preparations use compact Ready rather than
		# switching setup sides whenever the prediction crosses the midline.
		valid = valid and absf((point - _player.global_position).dot(_player._get_forehand_axis())) >= 0.18
		valid = valid and point.y - COURT_FLOOR_Y >= 0.30 and point.y - COURT_FLOOR_Y <= 1.50
		if valid and drive_preparation.state == "idle":
			valid = preload("res://scripts/incoming_contact_planner.gd").point_fits(_player, def, point)
		if valid:
			var profile: Dictionary = drive_preparation.profile
			if drive_preparation.state == "idle":
				var preparation_pose = preload("res://scripts/stroke_swing_path.gd").sample(def, 0.0)
				profile = DrivePreparation.profile_from(preparation_pose)
			_dp_lifecycle = lifecycle; _dp_authored = authored
			_dp_candidate = {"flight": ball.flight_id, "family": def.family, "time": candidate.get("time", 0.0), "profile": profile, "offset": BodyPose.foot_position_offset(_player, _heading_def)}
			return
	_dp_lifecycle = lifecycle; _dp_authored = authored

func _update_drive_preparation(delta: float, velocity: Vector3) -> void:
	_drive_preparation_input()
	_drive_lifecycle = _dp_lifecycle
	var was_active := drive_preparation.active()
	drive_preparation.update(delta, _dp_candidate, _drive_lifecycle, velocity.length() > MotionState.IDLE_SPEED, _dp_authored)
	if not was_active and drive_preparation.state == "setup" and _split_step_sample().get("active", false):
		_cancel_split_step("selected stance setup after grounded landing")

var _motion_context_ready := false
var _motion_context_value := "rally"
func _motion_context() -> String:
	# Perf: read once per leg update (up to 4 callers per update); see update_leg_ik.
	if _motion_context_ready: return _motion_context_value
	_motion_context_value = _read_motion_context()
	_motion_context_ready = _updating
	return _motion_context_value

func _read_motion_context() -> String:
	if _player.has_method("_between_point_owner") and _player._between_point_owner() != null:
		return "pickup"
	if _player.has_method("get_parent"):
		var game = _player.get_parent()
		if game != null and "practice_launcher" in game and game.practice_launcher != null and game.practice_launcher.is_wall():
			return "wall"
	return "rally"

func _ball_is_behind() -> bool:
	if not _player.has_method("_get_ball_ref"): return false
	var ball = _player._get_ball_ref()
	return ball != null and ball.is_in_play and (ball.global_position - _player.global_position).dot(_player._get_forward_axis()) < -0.40

func _support_limited_heading(desired: float) -> float:
	if not feet_initialized or _airborne: return desired
	var court: Vector3 = _player._get_forward_axis()
	var limit := deg_to_rad(MAX_SUPPORT_TURN_DEGREES)
	var lower := -INF
	var upper := INF
	for side: int in 2:
		if not (right_foot_locked if side == 0 else left_foot_locked): continue
		var knee_forward := Vector3.FORWARD.rotated(Vector3.UP, _knee_yaw[side])
		var support: float = court.signed_angle_to(knee_forward, Vector3.UP)
		support = _heading_angle + angle_difference(_heading_angle, support)
		lower = maxf(lower, support - limit)
		upper = minf(upper, support + limit)
	# Normally contact frames overlap. A previously airborne opposite foot can
	# land during a reversal; move towards their midpoint rather than snapping.
	if lower > upper: return (lower + upper) * 0.5
	return clampf(desired, lower, upper)

var _heading_inputs_ready := false
var _heading_charged_phase := "idle"
var _heading_motion_context := "rally"
var _heading_ball_behind := false
var _heading_shot_context: Dictionary = {}
func _update_heading(delta: float, velocity: Vector3, traveled: float) -> void:
	var court: Vector3 = _player._get_forward_axis()
	var speed := velocity.length()
	# Perf: the charged phase, ball side and shot context cannot change while the
	# legs sub-step one update, so they are read once per update (were per sub-step).
	if not _heading_inputs_ready:
		var charged = _charged_footwork()
		_heading_charged_phase = charged.state if charged != null else "idle"
		_heading_motion_context = _motion_context()
		_heading_ball_behind = _ball_is_behind()
		_heading_shot_context = shot_context()
		_heading_inputs_ready = _updating
	var ready_angle := -deg_to_rad(_ready_facing_deg)
	var unsettled := _run_active or _active_side >= 0 or absf(angle_difference(_heading_angle, ready_angle)) > deg_to_rad(2.0)
	motion_state.update(delta, velocity, traveled, court.rotated(Vector3.UP, ready_angle), _heading_motion_context, _heading_charged_phase, _heading_ball_behind, unsettled, _heading_shot_context)
	locomotion_state = motion_state.state
	locomotion_phase = motion_state.phase
	locomotion_gait = motion_state.gait
	if drive_preparation.active() and speed <= SUPPORT_READY_SPEED:
		locomotion_state = "drive_" + drive_preparation.state + "_" + drive_preparation.stance_kind
		locomotion_phase = "plant_load" if (drive_preparation.state == "setup" or drive_preparation.state == "hold") else "recover"
	locomotion_mode = locomotion_state
	_route_distance = motion_state.route_distance
	_route_direction = motion_state.route_direction
	# Keep the body in its locomotion frame until recovery steps finish. Fading
	# it early turns the hips to court while the soles still face the old route.
	var motion_owned := speed > 0.10 or unsettled or drive_preparation.body_alignment_active
	locomotion_body_weight = move_toward(locomotion_body_weight, 1.0 if motion_owned else 0.0, (4.0 if motion_owned else 1.0) * delta)
	var desired: float = _heading_angle + angle_difference(_heading_angle, motion_state.desired_heading + ready_angle)
	# At an exact half turn the shortest-arc tie must unwind the opening,
	# rather than continuing into an unnecessary complete spin.
	if motion_state.lob_active and motion_state.lob_replant and absf(_heading_angle - ready_angle) <= PI + 0.01:
		desired = ready_angle
	var landing_angle: float = _heading_angle + clampf(angle_difference(_heading_angle, desired), -deg_to_rad(MAX_SUPPORT_TURN_DEGREES), deg_to_rad(MAX_SUPPORT_TURN_DEGREES))
	_landing_forward = court.rotated(Vector3.UP, landing_angle)
	desired = _support_limited_heading(desired)
	_heading_angle = move_toward(_heading_angle, desired, deg_to_rad(TURN_RATE) * delta)
	_heading_forward = court.rotated(Vector3.UP, _heading_angle)
	locomotion_hip_yaw_deg = -rad_to_deg(_heading_angle)
	var authored: float = _heading_def.body_yaw_deg + _heading_def.hip_yaw_deg if _heading_def != null else 0.0
	var difference: float = wrapf(locomotion_hip_yaw_deg - authored, -180.0, 180.0)
	if BodyPose.locomotion_weight(_player, _heading_def) >= .999:
		_body_turn_reference_deg = difference
	else:
		_body_turn_reference_deg += wrapf(difference - _body_turn_reference_deg, -180.0, 180.0)

func _reset_feet(targets: Array[Vector3], reset_heading: bool = true) -> void :
	if reset_heading:
		motion_state.reset()
		locomotion_state = "ready"
		_heading_angle = -deg_to_rad(_ready_facing_deg)
		_heading_forward = _player._get_forward_axis().rotated(Vector3.UP, _heading_angle)
		_landing_forward = _heading_forward
		_body_turn_reference_deg = 0.0
		_route_distance = 0.0
		_route_direction = Vector3.ZERO
		_retreat_distance = 0.0
		locomotion_hip_yaw_deg = _ready_facing_deg
		locomotion_body_weight = 0.0
		for side: int in 2:
			_yaw_from[side] = _landing_yaw(side); _yaw_target[side] = _yaw_from[side]
			_knee_yaw_from[side] = atan2(-_heading_forward.x,-_heading_forward.z)
			_knee_yaw_target[side] = _knee_yaw_from[side]
			_plant_yaw(side)
	right_foot_smooth = targets[0]
	left_foot_smooth = targets[1]
	right_step_origin = targets[0]
	left_step_origin = targets[1]
	right_step_target = targets[0]
	left_step_target = targets[1]
	right_step_t = 1.0
	left_step_t = 1.0
	right_foot_lock_pos = targets[0]
	left_foot_lock_pos = targets[1]
	right_foot_locked = targets[0].y <= ANKLE_HEIGHT + .00001
	left_foot_locked = targets[1].y <= ANKLE_HEIGHT + .00001
	right_foot_was_swing = false
	left_foot_was_swing = false
	feet_initialized = true
	_active_side = -1
	_step_elapsed = 0.0
	_live_step_progress = 1.0
	_live_stance_initialized = false
	_moving = false
	_blocked_time = 0.0
	_travel_velocity = Vector3.ZERO
	_run_active = false
	_run_stopping = false
	_crossover_entry_side = -1
	_turn_cadence_remaining = 0.0
	step_foot = 0
	gait_arc_length = 0.0
	dist_since_last_step = 0.0
	double_support_timer = 0.0
	hip_shift = 0.0
	hip_shift_applied = Vector3.ZERO



## Plant a ready stance facing the current ready direction at once (no stepping
## turn). Change of ends: a player reaching their new spot faces the net immediately.
func face_ready_now(def: PostureDefinition) -> void:
	if def == null: def = _heading_def
	if def == null: return
	_ready_facing_deg = _ready_facing_for(def)
	var base: = Vector3(_player.global_position.x, ANKLE_HEIGHT, _player.global_position.z)
	_reset_feet(_stance_targets(def, base))
	_last_body_position = base
	# Feet face the new direction too, or the legs step around to turn them.
	_right_yaw = _landing_yaw(0); _left_yaw = _landing_yaw(1)

func initialize_serve_stance(def: PostureDefinition) -> void :
	clear_shot_context()
	_finish_split_pose()
	drive_preparation.reset()
	_heading_def = def
	_ready_facing_deg = 0.0
	var base: = Vector3(_player.global_position.x, ANKLE_HEIGHT, _player.global_position.z)
	_reset_feet(_stance_targets(def, base))
	_last_body_position = base
	_solve_legs(0.0, def)
	if _player.has_method("reset_support_clock"): _player.reset_support_clock()

func _separate_target(target: Vector3, side: int, moving_axis: Vector3 = Vector3.ZERO) -> Vector3:
	var fh: Vector3 = _player._get_forehand_axis().rotated(Vector3.UP, -deg_to_rad(_ready_facing_deg)) if moving_axis.length_squared() < 0.5 else moving_axis
	var sign_side: float = 1.0 if side == 0 else -1.0
	var support: Vector3 = left_foot_smooth if side == 0 else right_foot_smooth
	var gap: float = (target - support).dot(fh) * sign_side
	if gap < MIN_FOOT_SEPARATION:
		target += fh * sign_side * (MIN_FOOT_SEPARATION - gap)
	target.y = ANKLE_HEIGHT
	return target

func _begin_step(side: int, target: Vector3, duration: float, lift: float, velocity: Vector3) -> void :
	_start_yaw_swing(side)
	_active_side = side
	_step_elapsed = 0.0
	_step_duration = maxf(duration, 0.025)
	var charged = _charged_footwork()
	if velocity.length_squared() <= 0.01 and (charged == null or charged.state == "idle"):
		var turn := maxf(absf(angle_difference(_yaw_from[side], _yaw_target[side])), absf(angle_difference(_knee_yaw_from[side], _knee_yaw_target[side])))
		_step_duration = maxf(_step_duration, 1.5 * turn / deg_to_rad(TURN_RATE))
	_step_lift = lift
	_step_velocity = velocity
	_live_step_side = side
	_live_step_progress = 0.0
	_live_step_origin = right_foot_smooth if side == 0 else left_foot_smooth
	var moving_axis: = Vector3( - _heading_forward.z, 0, _heading_forward.x) if velocity.length_squared() > 0.01 else Vector3.ZERO
	_live_step_target = _separate_target(target, side, moving_axis)
	if side == 0:
		right_step_origin = _live_step_origin
		right_step_target = _live_step_target
		right_step_t = 0.0
		right_foot_locked = false
	else:
		left_step_origin = _live_step_origin
		left_step_target = _live_step_target
		left_step_t = 0.0
		left_foot_locked = false
	step_foot = 1 - side
	dist_since_last_step = 0.0

func _advance_step(delta: float) -> void :
	if _active_side < 0: return
	_step_elapsed = minf(_step_elapsed + delta, _step_duration)
	var progress: float = _step_elapsed / _step_duration
	_live_step_progress = progress
	_swing_yaw(_active_side, progress)
	var foot: Vector3 = _live_step_origin.lerp(_live_step_target, smoothstep(0.0, 1.0, progress))
	foot.y = maxf(ANKLE_HEIGHT, foot.y + sin(PI * progress) * _step_lift)
	# Turning recovery steps must clear the other planted shoe as well.
	foot = _clear_running_shoe(foot, _active_side, Vector3( - _heading_forward.z, 0, _heading_forward.x))
	if _active_side == 0:
		right_foot_smooth = foot
		right_step_t = progress
	else:
		left_foot_smooth = foot
		left_step_t = progress
	if progress >= 1.0:
		_plant_yaw(_active_side)
		if _active_side == 0:
			right_foot_smooth = _live_step_target
			right_foot_lock_pos = _live_step_target
			right_foot_locked = _live_step_target.y <= ANKLE_HEIGHT + .00001
		else:
			left_foot_smooth = _live_step_target
			left_foot_lock_pos = _live_step_target
			left_foot_locked = _live_step_target.y <= ANKLE_HEIGHT + .00001
		_active_side = -1

func _moving_target(base: Vector3, velocity: Vector3, side: int, duration: float) -> Vector3:
	var fh: = Vector3( - _heading_forward.z, 0, _heading_forward.x)
	var speed: float = velocity.length()
	var ratio: float = clampf(speed / maxf(_player.move_speed, 0.1), 0.0, 1.0)


	var half_width: float = lerpf(0.15, 0.13, ratio) if locomotion_gait == "walk" else lerpf(0.20, 0.17, ratio)
	return _separate_target(base + velocity * duration * 1.1 + fh * half_width * (1.0 if side == 0 else -1.0), side, fh)

func _update_moving_feet(delta: float, from: Vector3, to: Vector3, velocity: Vector3) -> void :
	var speed: float = velocity.length()
	# Fast court-facing shuffles/backpedals still need the bounded contact cycle;
	# the old single-step micro-strides could exceed twenty footfalls per second.
	var athletic_cycle: bool = locomotion_phase == "travel" and locomotion_gait != "drop_step" and speed >= RUN_ENTER_SPEED
	if (locomotion_gait == "jog" or locomotion_gait == "run" or locomotion_gait == "crossover" or athletic_cycle or _run_active) and speed >= (RUN_EXIT_SPEED if _run_active else RUN_ENTER_SPEED):
		if locomotion_gait == "crossover" and not _run_active:
			var outside: int = 0 if velocity.dot(_player._get_forehand_axis()) >= 0.0 else 1
			if _active_side < 0 and step_foot == outside:
				var opening_time:float=minf(.08,.24/maxf(speed,.1))
				_begin_step(outside,_moving_target(from,velocity,outside,opening_time),opening_time,.035,velocity)
			if _active_side == outside:
				_advance_step(delta)
				return
		_update_running_feet(delta, from, to, velocity)
		return
	if _run_active:
		_settle_running_feet(delta, _player.get_runtime_posture_def())
		return
	var ratio: float = clampf(speed / maxf(_player.move_speed, 0.1), 0.0, 1.0)


	var stride_budget: float = lerpf(0.20, .54 if (locomotion_gait == "shuffle" or locomotion_gait == "drop_step") else MAX_STEP_DISTANCE, ratio)
	var duration: float = minf(lerpf(STEP_DURATION_WALK, STEP_DURATION_RUN, ratio), stride_budget * 0.5 / maxf(speed, 0.1))
	if locomotion_gait == "walk": duration = clampf(.26 / maxf(speed,.35),.20,.38)
	var lateral: float = absf(velocity.normalized().dot(_player._get_forehand_axis()))
	var lift: float = lerpf(STEP_LIFT_HEIGHT, STEP_RUN_LIFT_HEIGHT, ratio) * lerpf(1.0, 0.35, lateral)
	if locomotion_gait == "walk": lift = .045
	if locomotion_phase == "adjust":
		stride_budget = minf(stride_budget, STUTTER_STRIDE)
		duration = minf(duration, STUTTER_TIME)
		lift = minf(lift, STUTTER_LIFT)
	if not _moving:
		_moving = true
		_live_stance_initialized = false
		if _active_side >= 0:
			_begin_step(_active_side, _moving_target(from, velocity, _active_side, duration), duration, lift, velocity)
		else:
			step_foot = 0 if velocity.dot(_player._get_forehand_axis()) >= 0 else 1
	elif _active_side < 0 and _travel_velocity.dot(velocity) < 0.0:


		step_foot = 0 if (right_foot_smooth - from).dot(velocity) < (left_foot_smooth - from).dot(velocity) else 1
	elif _active_side >= 0 and _step_velocity.dot(velocity) < 0.0:

		var remaining: float = clampf(_step_duration - _step_elapsed, 0.025, 0.035)
		_begin_step(_active_side, _moving_target(from, velocity, _active_side, remaining), remaining, lift * 0.5, velocity)
	_travel_velocity = velocity
	var elapsed: = 0.0
	while elapsed < delta - 1e-06:
		var dt: float = minf(MAX_SUBSTEP, delta - elapsed)
		var base: Vector3 = from.lerp(to, (elapsed + dt) / delta)
		var distance: float = from.distance_to(to) * dt / delta
		gait_arc_length += distance
		dist_since_last_step += distance
		if _active_side < 0:
			var target: Vector3 = _moving_target(base, velocity, step_foot, duration)
			var current: Vector3 = right_foot_smooth if step_foot == 0 else left_foot_smooth


			if current.distance_to(target) <= 0.045:
				var alternate: int = 1 - step_foot
				var alternate_target: Vector3 = _moving_target(base, velocity, alternate, duration)
				var alternate_foot: Vector3 = right_foot_smooth if alternate == 0 else left_foot_smooth
				if alternate_foot.distance_to(alternate_target) > 0.045:
					step_foot = alternate
					target = alternate_target
					current = alternate_foot
			if dist_since_last_step > 0.035 and current.distance_to(target) > 0.045:
				_begin_step(step_foot, target, duration, lift, velocity)
		_advance_step(dt)
		elapsed += dt





func _update_running_feet(delta: float, from: Vector3, to: Vector3, velocity: Vector3) -> void :
	var speed: float = velocity.length()
	var ratio: float = clampf((speed - RUN_ENTER_SPEED) / maxf(_player.move_speed - RUN_ENTER_SPEED, 0.1), 0.0, 1.0)
	var cadence: float = lerpf(3.2, 4.6, ratio)
	# How much of a side shuffle this is: travelling along the body's own side axis.
	var shuffle: float = 0.0
	if locomotion_state == "lateral_shuffle" and speed > 0.1:
		shuffle = smoothstep(0.5, 0.9, absf((velocity / speed).dot(Vector3(-_heading_forward.z, 0.0, _heading_forward.x))))
	cadence *= lerpf(1.0, SHUFFLE_CADENCE, shuffle)
	if _run_active and _travel_velocity.dot(velocity) < 0.0: _turn_cadence_remaining = .22
	_turn_cadence_remaining = maxf(0.0,_turn_cadence_remaining-delta)
	if _turn_cadence_remaining > 0.0: cadence *= 1.25
	var cycle: float = 2.0 / cadence
	var contact_fraction: float = minf(0.46, lerpf(RUN_CONTACT_TRAVEL, SHUFFLE_CONTACT_TRAVEL, shuffle) / maxf(speed * cycle, 0.1))
	var contact_time: float = cycle * contact_fraction
	var forward: Vector3 = _heading_forward
	_run_forward = forward
	var side_axis: = Vector3( - forward.z, 0.0, forward.x)
	var half_width: float = lerpf(0.16, 0.13, ratio)


	half_width *= lerpf(1.0, 0.86, absf(velocity.normalized().dot(_player._get_forehand_axis())))
	half_width = lerpf(half_width, SHUFFLE_HALF_WIDTH, shuffle)
	var lift: float = lerpf(0.105, 0.16, ratio)
	if locomotion_state == "backpedal" or locomotion_state == "backward_strafe" or locomotion_state == "lateral_shuffle": lift *= 0.70
	if not _run_active or _run_stopping:
		_run_active = true
		_run_stopping = false
		_live_stance_initialized = false
		var support_side: int = 1 - _active_side if _active_side >= 0 else (0 if (right_foot_smooth - from).dot(velocity) >= (left_foot_smooth - from).dot(velocity) else 1)
		_crossover_entry_side = -1
		if locomotion_gait == "crossover":
			support_side = 0 if velocity.dot(_player._get_forehand_axis()) >= 0.0 else 1
			_crossover_entry_side = 1-support_side
			crossover_entry_count += 1
		_run_phase = contact_fraction * 0.65 + (0.0 if support_side == 0 else 0.5)
		for side: int in 2:
			var foot: Vector3 = right_foot_smooth if side == 0 else left_foot_smooth
			_run_origins[side] = foot - from
			_run_swing_starts[side] = fposmod(_run_phase + side * 0.5, 1.0)
			_run_previous_phases[side] = _run_swing_starts[side]
			_run_early_liftoff[side] = false
			if side != support_side:
				_start_yaw_swing(side)
				if side == 0: right_foot_locked = false
				else: left_foot_locked = false
		_active_side = -1
	_moving = true
	_travel_velocity = velocity
	var elapsed: = 0.0
	while elapsed < delta - 1e-06:
		var dt: float = minf(MAX_SUBSTEP, delta - elapsed)
		var base: Vector3 = from.lerp(to, (elapsed + dt) / delta)
		_run_phase = fposmod(_run_phase + dt / cycle, 1.0)
		gait_arc_length += from.distance_to(to) * dt / delta
		for side: int in 2:
			var phase: float = fposmod(_run_phase + side * 0.5, 1.0)
			var foot: Vector3 = right_foot_smooth if side == 0 else left_foot_smooth
			var locked: bool = right_foot_locked if side == 0 else left_foot_locked
			var offset: Vector3 = velocity * contact_time * 0.5 + side_axis * half_width * (1.0 if side == 0 else -1.0)
			if side == _crossover_entry_side: offset += velocity.normalized()*.04
			var progress: = 1.0
			if phase < _run_previous_phases[side]: _run_early_liftoff[side] = false
			_run_previous_phases[side] = phase


			var reach: Vector3 = foot - base
			reach.y = 0.0
			if locked and reach.length() > 0.5: _run_early_liftoff[side] = true
			# A foot in the air lands only once its swing has run out (the gait phase wrapped since
			# it lifted). The contact window widens when the player slows down, and a foot that had
			# just lifted found itself "inside the window" again: it was planted at once, up to
			# 0.75 m away in a single tick, then lifted again (the drawn foot / knee pops).
			var swinging: bool = not locked and phase >= _run_swing_starts[side] and RUN_PLANT_AFTER_SWING
			if phase < contact_fraction and not _run_early_liftoff[side] and not swinging:
				if not locked:
					foot = base + offset
					foot.y = maxf(ANKLE_HEIGHT, foot.y)
					foot = _clear_running_shoe(foot, side, side_axis)
					_plant_yaw(side)
					if side == _crossover_entry_side: _crossover_entry_side = -1
					locked = true
					if side == 0: right_foot_lock_pos = foot
					else: left_foot_lock_pos = foot
			else:
				if locked:
					_start_yaw_swing(side)
					_run_origins[side] = foot - base
					_run_swing_starts[side] = phase
					locked = false
				var start: float = _run_swing_starts[side]
				progress = clampf((phase - start) / maxf(1.0 - start, 0.001), 0.0, 1.0)
				_swing_yaw(side, progress)
				var blend: float = smoothstep(0.0, 1.0, progress)
				foot = base + _run_origins[side].lerp(offset, blend)
				# The swing leaves and meets the ground at the ground's own speed (a Hermite curve
				# whose end tangents are the ground moving back under the body). With a plain
				# smoothstep the foot hung still under the body at both ends and then reversed in
				# one tick at lift-off and landing: the drawn foot and knee popped on every step.
				var ground: Vector3 = -velocity * (maxf(1.0 - start, 0.001) * cycle) * RUN_SWING_GROUND_MATCH
				foot += ground * (progress * (2.0 * progress - 1.0) * (progress - 1.0))
				foot.y = ANKLE_HEIGHT + maxf(maxf(0.0, _run_origins[side].y) * (1.0 - blend), sin(PI * progress) * lift)
				foot = _clear_running_shoe(foot, side, side_axis)
			if side == 0:
				right_foot_smooth = foot
				right_foot_locked = locked
				right_step_t = progress
				right_step_origin = base + _run_origins[side]
				right_step_target = base + offset
			else:
				left_foot_smooth = foot
				left_foot_locked = locked
				left_step_t = progress
				left_step_origin = base + _run_origins[side]
				left_step_target = base + offset
		elapsed += dt

func _clear_running_shoe(foot: Vector3, side: int, side_axis: Vector3) -> Vector3:
	var other: Vector3 = left_foot_smooth if side == 0 else right_foot_smooth
	var between: Vector3 = foot - other
	const CLEARANCE: = 0.16
	if between.length() >= CLEARANCE: return foot
	var planar: = Vector3(between.x, 0, between.z)
	if planar.length_squared() < 1e-06:
		planar = side_axis * (1.0 if side == 0 else -1.0)
	var required: float = sqrt(maxf(0.0, CLEARANCE * CLEARANCE - between.y * between.y))
	var clear: Vector3 = planar.normalized() * required
	foot.x = other.x + clear.x
	foot.z = other.z + clear.z
	return foot

func _settle_running_feet(delta: float, def) -> void :
	var base: = Vector3(_player.global_position.x, ANKLE_HEIGHT, _player.global_position.z)
	if not _run_stopping:
		_run_stopping = true
		_run_stop_elapsed = 0.0
		_run_stop_duration = RUN_SETTLE_DURATION
		_run_origins = [right_foot_smooth, left_foot_smooth]
		_run_stop_targets = _stance_targets(def, base)
		var charged = _charged_footwork()
		if charged == null or charged.state == "idle":
			# Settle under the current travel frame before sequential court-facing recovery.
			var support_side := Vector3(-_heading_forward.z, 0.0, _heading_forward.x)
			_run_stop_targets = [base + support_side * 0.24, base - support_side * 0.24]


		if right_foot_locked: _run_stop_targets[0] = right_foot_smooth
		if left_foot_locked: _run_stop_targets[1] = left_foot_smooth
		for side: int in 2:
			if not (right_foot_locked if side == 0 else left_foot_locked):
				_start_yaw_swing(side)
				if charged == null or charged.state == "idle":
					var turn := maxf(absf(angle_difference(_yaw_from[side], _yaw_target[side])), absf(angle_difference(_knee_yaw_from[side], _knee_yaw_target[side])))
					# Smoothstep peaks at 1.5; bound turn speed in the captured contact frame.
					_run_stop_duration = maxf(_run_stop_duration, 1.5 * turn / deg_to_rad(TURN_RATE))
	_run_stop_elapsed = minf(_run_stop_elapsed + delta, _run_stop_duration)
	var progress: float = _run_stop_elapsed / _run_stop_duration
	var blend: float = smoothstep(0.0, 1.0, progress)
	if not right_foot_locked:
		_swing_yaw(0, progress)
		right_foot_smooth = _clear_running_shoe(_run_origins[0].lerp(_run_stop_targets[0], blend), 0, Vector3(-_heading_forward.z, 0, _heading_forward.x))
		right_step_t = progress
	if not left_foot_locked:
		_swing_yaw(1, progress)
		left_foot_smooth = _clear_running_shoe(_run_origins[1].lerp(_run_stop_targets[1], blend), 1, Vector3(-_heading_forward.z, 0, _heading_forward.x))
		left_step_t = progress
	if progress >= 1.0:
		if not right_foot_locked: _plant_yaw(0)
		if not left_foot_locked: _plant_yaw(1)
		right_foot_locked = true
		left_foot_locked = true
		right_foot_lock_pos = right_foot_smooth
		left_foot_lock_pos = left_foot_smooth
		right_step_t = 1.0
		left_step_t = 1.0
		_run_active = false
		_run_stopping = false
		_moving = false
		_live_stance_initialized = false
		_active_side = -1

func _update_live_stance(delta: float, def) -> void :
	if _run_active:
		_settle_running_feet(delta, def)
		return
	var base: = Vector3(_player.global_position.x, ANKLE_HEIGHT, _player.global_position.z)
	var targets: Array[Vector3] = _stance_targets(def, base)
	if not _live_stance_initialized:
		_live_stance_initialized = true
		_moving = false
		gait_arc_length = 0.0
		double_support_timer = 0.0
		dist_since_last_step = 0.0
		hip_shift = 0.0


		if _active_side >= 0:
			_begin_step(_active_side, targets[_active_side], STANCE_STEP_DURATION, STANCE_STEP_LIFT, Vector3.ZERO)
	if _active_side < 0:
		var r_gap: float = right_foot_smooth.distance_to(targets[0])
		var l_gap: float = left_foot_smooth.distance_to(targets[1])

		if absf(angle_difference(_right_yaw, _landing_yaw(0))) > deg_to_rad(8): r_gap = maxf(r_gap, STANCE_REPLANT_DISTANCE + 0.001)
		if absf(angle_difference(_left_yaw, _landing_yaw(1))) > deg_to_rad(8): l_gap = maxf(l_gap, STANCE_REPLANT_DISTANCE + 0.001)
		if maxf(r_gap, l_gap) > STANCE_REPLANT_DISTANCE:
			var side: int = 0 if r_gap >= l_gap else 1
			var charged = _charged_footwork()
			if charged != null and charged.wants_plant():



				var load_side: int = clampi(charged.load_side, 0, 1)
				var load_gap: float = r_gap if load_side == 0 else l_gap
				if load_gap > STANCE_REPLANT_DISTANCE: side = load_side
			_begin_step(side, targets[side], STANCE_STEP_DURATION, STANCE_STEP_LIFT, Vector3.ZERO)
	_advance_step(delta)

const SPLIT_BODY_RATE := 0.36   # m/s the split-step body offset may change (12 mm per physics tick)
var _split_body_smooth := 0.0
var _split_body_tick := -1
func _apply_locomotion_body(def) -> void:
	var locomotion_body: bool = BodyPose.locomotion_enabled(_player, def)
	# The split step's load crouch lasts 45 ms: at 30 physics ticks a second that is one tick of
	# -28 mm and back (and a split that is cancelled drops out at once). Drawn, it is a twitch of
	# the torso and knees, not a crouch. The body offset now follows its target at
	# SPLIT_BODY_RATE, so it eases in and out over a few ticks.
	var tick: int = Engine.get_physics_frames()
	if tick != _split_body_tick:
		var step: float = SPLIT_BODY_RATE * float(tick - _split_body_tick) / float(Engine.physics_ticks_per_second) if _split_body_tick >= 0 and tick - _split_body_tick <= 2 else INF
		_split_body_smooth = move_toward(_split_body_smooth, _split_body_offset if _split_pose_active else 0.0, step)
		_split_body_tick = tick
	var split_body: bool = _split_pose_active or absf(_split_body_smooth) > 0.00001
	if locomotion_body or _locomotion_body_applied or split_body or _split_body_applied:


		var paddle = _player.paddle_node if "paddle_node" in _player else null
		var paddle_world: Transform3D = paddle.global_transform if paddle else Transform3D.IDENTITY
		if "right_arm_node" in _player: BodyPose.apply(_player, def)
		if paddle: paddle.global_transform = paddle_world
	_locomotion_body_applied = locomotion_body
	if split_body and _player.body_pivot:
		_player.body_pivot.position.y += _split_body_smooth
		hip_shift_applied += Vector3.UP * _split_body_smooth
	_split_body_applied = split_body
	if _landing_remaining > 0.0 and _player.body_pivot:
		var settle:float=1.0-_landing_remaining/LANDING_DURATION
		var landing:Vector3=Vector3.DOWN*sin(PI*settle)*.055
		_player.body_pivot.position+=landing
		hip_shift_applied+=landing

const KNEE_FOLLOW := 0.35   # share of the gap the knee target closes per physics tick (1 = follow at once, as before)
var _knee_goal: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _knee_goal_tick: Array[int] = [-1, -1]
func _solve_legs(delta: float, def, authored: bool = false) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_solve_legs(delta, def, authored)
	PerfMonitor.record("leg.solve", Time.get_ticks_usec() - _pt)

func _perf_solve_legs(delta: float, def, authored: bool = false) -> void:
	if not authored:
		_apply_locomotion_body(def)
		_fit_body_to_feet(def)
	# One feet pair for the three reach checks (they only read it; the feet do not
	# move between them).
	var feet: Array = [right_foot_smooth, left_foot_smooth]
	WideBackhandReach.apply(_player, def, feet)
	BackhandReach.apply(_player, def, feet)
	if not authored: LiveArmReach.apply(_player, def, feet)
	var fh: Vector3 = _player._get_forehand_axis()
	var fwd: Vector3 = _player._get_forward_axis()
	var tick: int = Engine.get_physics_frames()
	for side: int in 2:
		var right: bool = side == 0
		var leg = _player.right_leg_node if right else _player.left_leg_node
		var foot: Vector3 = right_foot_smooth if right else left_foot_smooth
		var pole: = Vector3(0, 0.5, 1)
		var yaw: = 0.0
		if def != null:
			pole = def.right_knee_pole if right else def.left_knee_pole
			yaw = def.right_foot_yaw_deg if right else def.left_foot_yaw_deg
		if pole.length_squared() < 0.0001: pole = Vector3(0, 0.5, 1)
		var progress: float = right_step_t if right else left_step_t
		var tilt: float = (1.0 - progress * 2.0) * 0.5 if _moving and progress < 1.0 else 0.0
		var pole_offset: Vector3 = _PostureSkeletonApplier.stance_offset(pole, fh, fwd)
		if not authored:
			var shoe_forward: Vector3 = Vector3.FORWARD.rotated(Vector3.UP,_knee_yaw[side])
			var shoe_side := Vector3(-shoe_forward.z,0,shoe_forward.x)
			# One authored pole in one contact frame through travel AND stopping.
			pole_offset = shoe_side*pole.x + Vector3.UP*pole.y + shoe_forward*pole.z
		if not authored and KNEE_FOLLOW < 1.0:
			# The knee target follows its goal over a few ticks instead of jumping with it. The
			# goal jumps whenever a pose with unset knee poles (Ready) blends with one that has
			# them (the pole is scaled from zero, so its direction flips in one tick) and when a
			# foot is planted: the drawn knee snapped up to 20 cm in a tick.
			if _knee_goal_tick[side] < 0 or tick - _knee_goal_tick[side] > 2: _knee_goal[side] = pole_offset
			elif tick != _knee_goal_tick[side]: _knee_goal[side] = _knee_goal[side].lerp(pole_offset, 1.0 - pow(1.0 - KNEE_FOLLOW, float(tick - _knee_goal_tick[side])))
			_knee_goal_tick[side] = tick
			pole_offset = _knee_goal[side]
		leg.solve_ik(foot, foot + pole_offset, tilt)
		var foot_forward: Vector3 = _run_forward if _run_active else fwd
		var target_yaw: float = atan2( - foot_forward.x, - foot_forward.z) - deg_to_rad(yaw)

		var angle: float = _right_yaw if right else _left_yaw
		if authored: angle = target_yaw
		if right: _right_yaw = angle
		else: _left_yaw = angle
		leg.foot_pivot.global_rotation.y = angle
		var pitch_field: StringName = &"right_foot_pitch_deg" if right else &"left_foot_pitch_deg"
		var requested_pitch: float = float(def.get(pitch_field)) if def != null and pitch_field in def else 0.0
		var authored_pitch: float = requested_pitch
		var procedural_pitch: float = _split_ankle_pitch if not authored else 0.0
		requested_pitch += procedural_pitch
		var grounded: bool = (right_foot_locked if right else left_foot_locked) and foot.y <= ANKLE_HEIGHT + 0.002
		applied_foot_pitch_deg[side] = FootPitchGrounding.apply(leg, angle, requested_pitch, grounded)
		# Perf: plain values per tick; foot_pitch_report() builds the dictionary on demand.
		_pitch_requested[side] = authored_pitch
		_pitch_procedural[side] = procedural_pitch
		_pitch_limited[side] = absf(requested_pitch - applied_foot_pitch_deg[side]) > 0.01
		_pitch_grounded[side] = grounded
		_pitch_reported[side] = true

func _update_authored_stance(def) -> void :
	_finish_split_pose()
	drive_preparation.reset()
	_ready_facing_deg = 0.0
	_heading_def = def
	var base: = Vector3(_player.global_position.x, ANKLE_HEIGHT, _player.global_position.z)
	# Position-edited poses and serves show gameplay floor/separation/body-fit
	# constraints. Unedited legacy authored previews retain their original solver.
	var authored_targets: bool = not bool(def.get_meta("mobile_serve_planted_stance", false)) and not BodyPose.has_position_edit(def)
	_reset_feet(_stance_targets(def, base, authored_targets))
	# Explicit authored lifts release only that contact.
	right_foot_locked = right_foot_smooth.y <= ANKLE_HEIGHT + .00001
	left_foot_locked = left_foot_smooth.y <= ANKLE_HEIGHT + .00001
	_solve_legs(0.0, def, authored_targets)
	feet_initialized = false

func _update_airborne_feet(delta: float, def, base: Vector3, elevation: float) -> void :
	if not _airborne:
		_airborne = true
		_start_yaw_swing(0);_start_yaw_swing(1)
		_run_active = false
		_air_time = 0.0
		_air_right_offset = right_foot_smooth - base
		_air_left_offset = left_foot_smooth - base
		_air_right_offset.y = 0.0
		_air_left_offset.y = 0.0
		_active_side = -1
		_moving = false
		_live_stance_initialized = false
	_air_time += delta
	var targets: Array[Vector3] = _stance_targets(def, base)
	var gather: float = smoothstep(0.0, 0.18, _air_time)
	_swing_yaw(0, clampf(_air_time / 0.18, 0, 1));_swing_yaw(1, clampf(_air_time / 0.18, 0, 1))


	var tuck: float = minf(0.045, elevation * 0.2)
	right_foot_smooth = (base + _air_right_offset).lerp(targets[0], gather)
	left_foot_smooth = (base + _air_left_offset).lerp(targets[1], gather)
	right_foot_smooth.y = ANKLE_HEIGHT + elevation + tuck
	left_foot_smooth.y = ANKLE_HEIGHT + elevation + tuck
	if def != null and "air_right_foot_offset" in def:
		# Authored air legs: the pose's own offsets, faded in with height so take-off and
		# landing still meet the floor stance. Scissor pair when the jump began moving back.
		var scissor: bool = "jump_style" in _player and int(_player.jump_style) == 1
		var air: float = smoothstep(0.0, AIR_LEGS_FULL_HEIGHT, elevation)
		var fh: Vector3 = _player._get_forehand_axis()
		var fwd: Vector3 = _player._get_forward_axis()
		var right_air: Vector3 = (def.air_scissor_right_foot_offset if scissor else def.air_right_foot_offset) * air
		var left_air: Vector3 = (def.air_scissor_left_foot_offset if scissor else def.air_left_foot_offset) * air
		right_foot_smooth += fh * right_air.x + fwd * right_air.z + Vector3.UP * right_air.y
		left_foot_smooth += fh * left_air.x + fwd * left_air.z + Vector3.UP * left_air.y
		right_foot_smooth.y = maxf(right_foot_smooth.y, ANKLE_HEIGHT)
		left_foot_smooth.y = maxf(left_foot_smooth.y, ANKLE_HEIGHT)
	right_foot_locked = false
	left_foot_locked = false
	right_step_t = 0.5
	left_step_t = 0.5
	right_foot_was_swing = true
	left_foot_was_swing = true
	right_step_target = targets[0]
	left_step_target = targets[1]
	_last_body_position = base
	_solve_legs(delta, def)

# A held serve preserves its planted stance, but movement must finish first.
# Otherwise stopping during a stride freezes the airborne/baseline-touching shoe
# indefinitely and faults every later serve from an otherwise legal root.
var _serve_stance_recovering := false

func _hold_service_stance(serving: bool, velocity: Vector3, displacement: float) -> bool:
	if not serving:
		_serve_stance_recovering = false
		return false
	if velocity.length() >= 0.1 or displacement >= 0.01:
		_serve_stance_recovering = true
		return false
	if _active_side >= 0 or _run_active or _run_stopping or _airborne or _landing_remaining > 0.0:
		_serve_stance_recovering = true
	if _serve_stance_recovering:
		if not is_support_ready(0) or not is_support_ready(1): return false
		_serve_stance_recovering = false
	return true

func update_leg_ik(delta: float, def_override = null) -> void:
	var _pt := Time.get_ticks_usec()
	# Per-update caches (motion context, heading inputs, split sample) live only
	# inside this call; nothing in it can change what they read.
	_updating = true
	_motion_context_ready = false
	_heading_inputs_ready = false
	_split_sample_ready = false
	_perf_update_leg_ik(delta, def_override)
	_updating = false
	_motion_context_ready = false
	_heading_inputs_ready = false
	_split_sample_ready = false
	PerfMonitor.record("leg.ik", Time.get_ticks_usec() - _pt)

func _perf_update_leg_ik(delta: float, def_override = null) -> void:
	if not _player.right_leg_node or not _player.left_leg_node: return
	if not is_finite(delta) or delta < 0.0: return
	if _split_pose_active and _split_hard_interrupted():
		_finish_split_pose()
		if "pose_controller" in _player and _player.pose_controller != null and "split_step" in _player.pose_controller:
			_cancel_split_step("own action or presentation context took priority")
	if _split_pose_active and delta > 0.0:
		right_foot_smooth = _split_ground_feet[0]; left_foot_smooth = _split_ground_feet[1]
	var base: = Vector3(_player.global_position.x, ANKLE_HEIGHT, _player.global_position.z)
	var def = def_override if def_override != null else _player.get_runtime_posture_def()
	_heading_def = def
	_ready_facing_deg = _ready_facing_for(def)
	if def_override != null and _player.posture.editor_preview_mode:
		_update_authored_stance(def_override)
		_last_body_position = base
		return

	hip_shift_applied = Vector3.ZERO
	var velocity: Vector3 = Vector3(_player.current_velocity.x, 0.0, _player.current_velocity.z)
	var displacement: float = base.distance_to(_last_body_position)
	if delta > 0.0:
		_update_drive_preparation(delta, velocity)
		_ready_facing_deg = _ready_facing_for(def)
	var reset: bool = not feet_initialized or displacement > maxf(TELEPORT_DISTANCE, velocity.length() * delta * 2.5 + 0.1)
	if reset:
		_finish_split_pose()
		if feet_initialized:
			drive_preparation.reset()
			_ready_facing_deg = 0.0
		_airborne = false
		_landing_remaining = 0.0
		_reset_feet(_stance_targets(def, base))
		_last_body_position = base
		displacement = 0.0
	# Zero elapsed support refresh can refit, never retarget or change planner state.
	if delta <= 0.0:
		_solve_legs(0.0,def)
		return
	if _apply_split_step(_split_step_sample(), delta, base, velocity, def): return
	var jumping: bool = "is_jumping" in _player and _player.is_jumping
	var elevation: float = maxf(0.0, _player.global_position.y - _player.ground_y) if "ground_y" in _player else 0.0
	if jumping or elevation > 0.005:
		_update_heading(delta,velocity,displacement)
		_update_airborne_feet(delta, def, base, elevation)
		return
	if _airborne:


		_airborne = false
		var landed: Array[Vector3] = [right_foot_smooth, left_foot_smooth]
		landed[0].y = ANKLE_HEIGHT
		landed[1].y = ANKLE_HEIGHT
		_plant_yaw(0);_plant_yaw(1)
		_reset_feet(landed, false)
		_landing_remaining = LANDING_DURATION
	_landing_remaining = maxf(0.0, _landing_remaining - delta)


	var serving: bool = "hitting" in _player and _player.hitting != null and _player.hitting.serving_visual_active
	if _hold_service_stance(serving, velocity, displacement):
		_last_body_position = base
		_solve_legs(delta, def)
		return
	_blocked_time = _blocked_time + delta if displacement < 1e-05 else 0.0
	var elapsed := 0.0
	while elapsed < delta-.000001:
		var dt:float=minf(MAX_SUBSTEP,delta-elapsed)
		var step_from:Vector3=_last_body_position.lerp(base,elapsed/delta)
		var step_to:Vector3=_last_body_position.lerp(base,(elapsed+dt)/delta)
		_update_heading(dt,velocity,step_from.distance_to(step_to))
		if velocity.length() > .1 and _blocked_time < .08:
			_update_moving_feet(dt,step_from,step_to,velocity)
		else:
			_update_live_stance(dt,def)
		elapsed += dt
	if drive_preparation.active() and _active_side < 0 and not _run_active and is_support_ready(0) and is_support_ready(1):
		drive_preparation.mark_settled(_drive_lifecycle not in ["cancel", "finish", "swing"])
	_last_body_position = base
	right_foot_was_swing = right_step_t < 1.0
	left_foot_was_swing = left_step_t < 1.0
	_solve_legs(delta, def)
	_player._draw_step_debug(right_step_target, left_step_target, right_step_origin, left_step_origin, right_foot_was_swing, left_foot_was_swing)


func foot_pitch_report(right: bool) -> Dictionary:
	var side := 0 if right else 1
	if not _pitch_reported[side]: return {"requested": 0.0, "applied": 0.0, "limited": false, "grounded": true, "procedural": 0.0}
	return {"requested": _pitch_requested[side], "procedural": _pitch_procedural[side], "applied": applied_foot_pitch_deg[side], "limited": _pitch_limited[side], "grounded": _pitch_grounded[side]}

func get_feet_gap() -> float:
	return Vector3(right_foot_smooth.x, 0, right_foot_smooth.z).distance_to(Vector3(left_foot_smooth.x, 0, left_foot_smooth.z))

const FIT_DROP_HALFLIFE := 0.06   # s: torso settling down onto a far foot
const FIT_RISE_HALFLIFE := 0.10   # s: torso coming back up
var _fit_lower := 0.0
var _fit_lower_prev := 0.0
var _fit_lower_tick := -10

func _fit_body_to_feet(def = null) -> void :
	if not _player.body_pivot: return
	# Keep the fixed paddle/grip reachable while ordinary live plants catch up.
	# This affects only explicitly translated poses; the locomotion state and
	# original zero-offset fit remain unchanged.
	if def != null and BodyPose.requested_position_offset(_player, def) != Vector3.ZERO:
		var report: Dictionary = BodyPose.position_report(_player, def, [right_foot_smooth, left_foot_smooth])
		var already_applied: Vector3 = _player.body_pivot.get_meta("pose_body_position_applied") if _player.body_pivot.has_meta("pose_body_position_applied") else BodyPose.position_offset(_player, def)
		var correction: Vector3 = report.world_offset - already_applied
		if correction.length_squared() > 1e-12:
			var fixed_paddle: Transform3D = _player.paddle_node.global_transform
			_player.body_pivot.position += correction
			_player.body_pivot.set_meta("pose_body_position_applied", report.world_offset)
			hip_shift_applied += correction
			_player.paddle_node.global_transform = fixed_paddle
	var lower: = 0.0
	for side: int in 2:
		var leg = _player.right_leg_node if side == 0 else _player.left_leg_node
		if not "thigh_pivot" in leg or leg.thigh_pivot == null: continue
		var foot: Vector3 = right_foot_smooth if side == 0 else left_foot_smooth
		var hip: Vector3 = leg.thigh_pivot.global_position
		var length: float = (leg.thigh_length + leg.shin_length) * 0.985
		var horizontal: float = Vector2(hip.x - foot.x, hip.z - foot.z).length()
		var maximum_height: float = sqrt(maxf(0.0, length * length - horizontal * horizontal))
		lower = maxf(lower, hip.y - foot.y - maximum_height)
	# The drop that lets the legs reach the feet is eased, not applied whole each tick: the raw
	# value jumps with every step and wide plant (bench: the torso moved 2-7 cm tick to tick and
	# shook the arms and paddle with it). A foot may sit a little short of its plant for a few
	# ticks while the torso settles; the torso height itself is now continuous.
	var tick: int = Engine.get_physics_frames()
	if tick != _fit_lower_tick:
		_fit_lower_prev = _fit_lower if tick - _fit_lower_tick <= 2 else lower
		_fit_lower_tick = tick
	var ease: float = 1.0 - pow(0.5, (1.0 / float(Engine.physics_ticks_per_second)) / (FIT_DROP_HALFLIFE if lower > _fit_lower_prev else FIT_RISE_HALFLIFE))
	_fit_lower = lerpf(_fit_lower_prev, lower, ease) if not _player.posture.editor_preview_mode else lower
	lower = _fit_lower
	if lower <= 1e-05: return
	var paddle: Node3D = _player.paddle_node if "paddle_node" in _player else null
	var paddle_world: Transform3D = paddle.global_transform if paddle else Transform3D.IDENTITY


	var offset: = Vector3.DOWN * lower
	_player.body_pivot.global_position += offset
	hip_shift_applied += offset
	if paddle: paddle.global_transform = paddle_world
