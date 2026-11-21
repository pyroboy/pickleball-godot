class_name PlayerPaddlePosture extends Node
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")

const _PostureColors = preload("res://scripts/posture_colors.gd")
const HumanContact = preload("res://scripts/human_contact_controller.gd")
const SwingPath = preload("res://scripts/stroke_swing_path.gd")
const VisibleBody = preload("res://scripts/stroke_body_pose.gd")
var human_contact = null
const _BallInfo = preload("res://scripts/ball.gd")

var _posture_lib


var _skeleton_applier = null


var _offset_resolver


var _commit_selector







signal incoming_stage_changed(stage: int, posture: int, commit_dist: float, ball2ghost: float, ttc: float)


signal grade_flashed(grade: String)


const PaddleScene = preload("res://scenes/paddle.tscn")
const _PC: = preload("res://scripts/posture_constants.gd")


const PADDLE_SIDE_OFFSET: = _PC.PADDLE_SIDE_OFFSET
const PADDLE_FORWARD_OFFSET: = _PC.PADDLE_FORWARD_OFFSET
const PADDLE_CENTER_OFFSET: = _PC.PADDLE_CENTER_OFFSET
const PADDLE_BACKHAND_OFFSET: = _PC.PADDLE_BACKHAND_OFFSET
const PADDLE_MEDIUM_OVERHEAD_HEIGHT: = _PC.PADDLE_MEDIUM_OVERHEAD_HEIGHT
const PADDLE_MEDIUM_OVERHEAD_FORWARD: = _PC.PADDLE_MEDIUM_OVERHEAD_FORWARD
const PADDLE_HIGH_OVERHEAD_HEIGHT: = _PC.PADDLE_HIGH_OVERHEAD_HEIGHT
const PADDLE_HIGH_OVERHEAD_FORWARD: = _PC.PADDLE_HIGH_OVERHEAD_FORWARD
const PADDLE_OVERHEAD_SIDE_OFFSET: = _PC.PADDLE_OVERHEAD_SIDE_OFFSET
const PADDLE_LOW_HEIGHT: = _PC.PADDLE_LOW_HEIGHT
const PADDLE_LOW_FORWARD_OFFSET: = _PC.PADDLE_LOW_FORWARD_OFFSET
const PADDLE_BACKSWING_DEGREES: = _PC.PADDLE_BACKSWING_DEGREES
const PADDLE_FOLLOW_THROUGH_DEGREES: = _PC.PADDLE_FOLLOW_THROUGH_DEGREES
const PADDLE_CHARGE_PULLBACK: = _PC.PADDLE_CHARGE_PULLBACK
const PADDLE_CHARGE_LIFT: = _PC.PADDLE_CHARGE_LIFT
const PADDLE_CHARGE_BEHIND_OFFSET: = _PC.PADDLE_CHARGE_BEHIND_OFFSET
const PADDLE_CHARGE_FOREHAND_BEHIND: = _PC.PADDLE_CHARGE_FOREHAND_BEHIND
const PADDLE_CHARGE_FOREHAND_HEIGHT: = _PC.PADDLE_CHARGE_FOREHAND_HEIGHT
const PADDLE_CHARGE_BACKHAND_BEHIND: = _PC.PADDLE_CHARGE_BACKHAND_BEHIND
const PADDLE_CHARGE_BACKHAND_HEIGHT: = _PC.PADDLE_CHARGE_BACKHAND_HEIGHT
const PADDLE_POSTURE_SWITCH_DEADZONE: = _PC.PADDLE_POSTURE_SWITCH_DEADZONE
const PADDLE_WIDE_LATERAL_THRESHOLD: = _PC.PADDLE_WIDE_LATERAL_THRESHOLD


const GHOST_STRETCH_LATERAL_MAX: = _PC.GHOST_STRETCH_LATERAL_MAX
const GHOST_STRETCH_HEIGHT_MIN: = _PC.GHOST_STRETCH_HEIGHT_MIN
const GHOST_STRETCH_HEIGHT_MAX: = _PC.GHOST_STRETCH_HEIGHT_MAX
const GHOST_FORWARD_PLANE: = _PC.GHOST_FORWARD_PLANE
const GHOST_CONTACT_MAX_DIST: = _PC.GHOST_CONTACT_MAX_DIST
const ZONE_EXIT_MARGIN: = _PC.ZONE_EXIT_MARGIN



var POSTURE_ZONES: Dictionary = {}

func _init_posture_zones() -> void :
	POSTURE_ZONES.clear()
	if _posture_lib == null:
		return
	for def in _posture_lib.all_definitions():
		if def is PostureDefinition and def.has_zone:
			POSTURE_ZONES[def.posture_id] = {
				"x_min": def.zone_x_min, "x_max": def.zone_x_max, 
				"y_min": def.zone_y_min, "y_max": def.zone_y_max, 
			}

func refresh_posture_zones() -> void :
	_init_posture_zones()


const POSTURE_GHOST_ALPHA: = _PC.POSTURE_GHOST_ALPHA
const POSTURE_GHOST_ACTIVE_ALPHA: = _PC.POSTURE_GHOST_ACTIVE_ALPHA
const POSTURE_GHOST_NEAR_ALPHA: = _PC.POSTURE_GHOST_NEAR_ALPHA
const POSTURE_GHOST_NEAR_EMISSION: = _PC.POSTURE_GHOST_NEAR_EMISSION
const POSTURE_GHOST_NEAR_RADIUS: = _PC.POSTURE_GHOST_NEAR_RADIUS
const POSTURE_GHOST_SCALE: = _PC.POSTURE_GHOST_SCALE


const DEBUG_POSTURE_NAMES: Array[String] = [
	"FH", "FW", "BH", "MO", "HO", "LF", "LC", "LB", "CF", "CB", "WF", "WB", "VR", 
	"MLF", "MLB", "MLC", "MWF", "MWB", "LWF", "LWB", 
]


var paddle_posture: int = 0
var _posture_lerp_pos: Vector3 = Vector3.ZERO
var _posture_lerp_rot: Vector3 = Vector3.ZERO
var _posture_lerp_basis: Basis = Basis.IDENTITY
var _posture_lerp_initialized: bool = false
var _low_look_blend: float = 0.0
var posture_ghosts: Dictionary = {}
var posture_ghost_root: Node3D = null
var _ball_incoming: bool = false
var _incoming_timer: float = 0.0
var _incoming_expired: bool = false
var _ghost_base_color: Color = Color(1, 0.85, 0.2)
var _green_lit_postures: Dictionary = {}
var _zone_exit_cooldown: float = 0.0
var _green_fade_t: float = 0.0
var _trajectory_points: Array[Vector3] = []
var _committed_incoming_posture: int = -1
var _contact_point_local: Vector3 = Vector3.ZERO
var _last_commit_stage: int = -1
var _commit_count: int = 0
var _pose_change_count: int = 0
var _last_counted_posture: int = -1
var _green_trigger_count: int = 0
var _closest_ball2ghost: float = INF
var _scored_this_ball: bool = false
var _last_move_log_pos: Vector3 = Vector3.ZERO
var _commit_locked: bool = false
var _last_commit_ref_y: float = 0.0
var _last_commit_player_pos: Vector3 = Vector3.ZERO
var _blue_hold_timer: float = 0.0
var _blue_latched: bool = false
var _ghost_frozen_at: Vector3 = Vector3.ZERO
const BLUE_HOLD_DURATION: = _PC.BLUE_HOLD_DURATION
const TTC_BLUE: = _PC.TTC_BLUE
const TTC_PURPLE: = _PC.TTC_PURPLE
const BLUE_DIST_FALLBACK: = _PC.BLUE_DIST_FALLBACK
const POSTURE_HOLD_MIN: = _PC.POSTURE_HOLD_MIN
const INCOMING_GLOW_DURATION: = _PC.INCOMING_GLOW_DURATION
const INCOMING_FADE_DURATION: = _PC.INCOMING_FADE_DURATION
const GHOST_MIN_DISTANCE: = _PC.GHOST_MIN_DISTANCE
const GHOST_LERP_SPEED: = _PC.GHOST_LERP_SPEED
const GHOST_TIGHTEN_RATIO: = _PC.GHOST_TIGHTEN_RATIO



var transition_pose_blend = null
var _presented_body_pose: PostureDefinition


var solo_mode: bool = true
var selected_posture_id: int = -1


var _editor_solo_posture_id: int = -1


var editor_preview_mode: bool = false

func set_editor_solo_posture_id(id: int) -> void :
	_editor_solo_posture_id = id

var _paddle_head_marker: MeshInstance3D = null
var _hit_posture: int = -1
var _hit_flash_t: float = 0.0
const POSTURE_GHOST_HIT_FLASH_DURATION: = 0.6
var _first_green_posture: int = -1
var _last_lit_postures: Array = []


const FT_FOREHAND: = -1
const FT_BACKHAND: = -2
const FT_CENTER: = -3
const FT_OVERHEAD: = -4
const FT_KEYS: = [FT_FOREHAND, FT_BACKHAND, FT_CENTER, FT_OVERHEAD]
var ft_ghosts: Dictionary = {}


var _posture_ghosts_visible: bool = false
var _charge_ghosts_visible: bool = false
var _follow_through_visible: bool = false
var _charge_highlight_active: bool = false


var _posture_zone_bounds: Dictionary = {}

var _player

func _ready() -> void :
	_player = get_parent() as CharacterBody3D
	_posture_lib = PostureLibrary.instance()
	_skeleton_applier = load("res://scripts/posture_skeleton_applier.gd").new(_player)
	_offset_resolver = load("res://scripts/posture_offset_resolver.gd").new(_player)
	_commit_selector = load("res://scripts/posture_commit_selector.gd").new()
	_init_posture_zones()




func _emit_stage_cleared() -> void :
	if _player and _player.player_num == 0:
		incoming_stage_changed.emit(-1, -1, 0.0, 0.0, 0.0)



func update_paddle_tracking(force: bool = false) -> void :
	if editor_preview_mode:
		return
	if not _player._ensure_paddle_ready():
		return
	if _player is CharacterBody3D and not _player.is_ai:
		if human_contact == null: human_contact = HumanContact.new(_player, self)
		human_contact.update(0.0 if force else get_physics_process_delta_time())
		return


	if _player.hitting.serving_visual_active:
		return
	if _player.hitting.charge_visual_active and not force:
		return

	if _player.hitting.is_in_follow_through:
		if (_player.hitting.paddle_swing_tween == null or not _player.hitting.paddle_swing_tween.is_valid()) and _player.hitting._live_swing_presentation.is_empty():
			_player.hitting.is_in_follow_through = false
		elif not force:
			return
	if _player.hitting.paddle_swing_tween != null and _player.hitting.paddle_swing_tween.is_valid() and not force:
		return

	var ball: RigidBody3D = _player._get_ball_ref()

	var ball_is_near: bool = false
	if ball != null:
		var to_ball: Vector3 = ball.global_position - _player.global_position
		var ball_dist: float = Vector2(to_ball.x, to_ball.z).length()
		ball_is_near = ball_dist <= 5.0

		if _committed_incoming_posture >= 0 and ball_dist <= 10.0:
			ball_is_near = true

	if ball != null and ball_is_near:
		if _player.is_ai and _player.ai_state == _player.AIState.CHARGING:

			pass
		elif _player.is_ai:

			paddle_posture = _player.ai_desired_posture

	else:
		if not ball_is_near:
			paddle_posture = _player.PaddlePosture.READY
			_committed_incoming_posture = -1
			_last_commit_stage = -1
			_contact_point_local = Vector3.ZERO
			_blue_hold_timer = 0.0
			_blue_latched = false
			_ghost_frozen_at = Vector3.ZERO
			_commit_locked = false
			_last_commit_ref_y = 0.0
			_last_commit_player_pos = Vector3.ZERO
			_emit_stage_cleared()
			if _player.awareness_grid:
				_player.awareness_grid.reset()
		elif _committed_incoming_posture >= 0:
			paddle_posture = _committed_incoming_posture




	if paddle_posture != _last_counted_posture:
		if _last_counted_posture >= 0:
			_pose_change_count += 1
		_last_counted_posture = paddle_posture


	if _ball_incoming and ball != null:
		var move_d: float = Vector2(_player.global_position.x - _last_move_log_pos.x, _player.global_position.z - _last_move_log_pos.z).length()
		if move_d > 0.5 or _last_move_log_pos == Vector3.ZERO:
			_last_move_log_pos = _player.global_position
			var ball_d: float = Vector2(ball.global_position.x - _player.global_position.x, ball.global_position.z - _player.global_position.z).length()
			var paddle_d: float = INF
			if _player.has_method("get_paddle_position"):
				paddle_d = _player.get_paddle_position().distance_to(ball.global_position)
			var pname: String = _player.DEBUG_POSTURE_NAMES[paddle_posture] if paddle_posture < _player.DEBUG_POSTURE_NAMES.size() else "?"
			if RuntimePolicy.developer_tools: print("[MOVE P%d] pos=(%.1f,%.1f) ball_d=%.1f paddle_d=%.1f spd=%.1f pose=%s" % [_player.player_num, _player.global_position.x, _player.global_position.z, ball_d, paddle_d, _player.current_velocity.length(), pname])




	var target_pos: Vector3 = _get_posture_offset()


	var active_def = _posture_lib.get_def(paddle_posture) if _posture_lib else null
	var clearance: float = active_def.paddle_floor_clearance if active_def else 0.06
	var floor_local_y: float = _player.COURT_FLOOR_Y - _player.global_position.y + clearance
	target_pos.y = maxf(target_pos.y, floor_local_y)
	var rot_offset: Vector3 = _offset_resolver.get_posture_rotation_offset_for(paddle_posture)
	var target_basis: Basis = SwingPath.unspun_paddle_basis(_player, active_def) if active_def else Basis.IDENTITY
	if force or not _posture_lerp_initialized:
		_posture_lerp_pos = target_pos
		_posture_lerp_rot = rot_offset
		_posture_lerp_basis = target_basis
		_posture_lerp_initialized = true
	else:
		var is_wide: bool = paddle_posture in [_player.PaddlePosture.WIDE_FOREHAND, _player.PaddlePosture.WIDE_BACKHAND]
		var is_low: bool = paddle_posture in [
			_player.PaddlePosture.LOW_FOREHAND, _player.PaddlePosture.LOW_BACKHAND, 
			_player.PaddlePosture.LOW_FORWARD, _player.PaddlePosture.LOW_WIDE_FOREHAND, 
			_player.PaddlePosture.LOW_WIDE_BACKHAND]

		var lerp_spd: float = 22.0 if is_wide else (12.0 if is_low else 16.0)
		var dt: float = get_physics_process_delta_time()
		_posture_lerp_pos = _posture_lerp_pos.lerp(target_pos, minf(dt * lerp_spd, 1.0))
		_posture_lerp_rot = _posture_lerp_rot.lerp(rot_offset, minf(dt * lerp_spd, 1.0))
		_posture_lerp_basis = _posture_lerp_basis.slerp(target_basis, 1.0 - exp( - dt * lerp_spd))


	_posture_lerp_pos.y = maxf(_posture_lerp_pos.y, floor_local_y)

	if _committed_incoming_posture < 0 or _last_commit_stage < 0:
		var head: Vector3 = _player.global_position + _posture_lerp_pos
		head = PaddleReach.clamp_head_with_floor(head, PaddleReach.target_shoulder_world(_player), _player.COURT_FLOOR_Y + clearance)


		_player.paddle_node.global_transform = SwingPath.apply_in_hand_transform(Transform3D(_posture_lerp_basis, head - _posture_lerp_basis.y * PaddleSize.HEAD_CENTER_Y), active_def) if active_def else Transform3D(_posture_lerp_basis, head - _posture_lerp_basis.y * PaddleSize.HEAD_CENTER_Y)

	_player._cache_paddle_rest_transform()



	if _paddle_head_marker and posture_ghost_root and posture_ghost_root.visible:
		_paddle_head_marker.visible = true
		_paddle_head_marker.global_position = _player.paddle_node.global_position + _player.paddle_node.global_transform.basis.y * PaddleSize.HEAD_CENTER_Y
	elif _paddle_head_marker:
		_paddle_head_marker.visible = false

var full_solve_stamp: Array = []   # [physics tick, def, paddle transform] of the last full solve
var arm_pending_def = null         # pose whose arm IK is deferred until ensure_arm_pose()

## Arms are deferred only in live rallies, where the lag is. Serves, between-point
## cut-scenes, dives/special reaches and the pose editor read hand transforms
## directly and keep immediate solves.
func _defer_arms_allowed() -> bool:
	if editor_preview_mode or not _player: return false
	var game = _player.get_parent()
	if game == null or not "game_state" in game or game.game_state != game.GameState.PLAYING: return false
	if _player.has_method("_between_point_owner") and _player._between_point_owner() != null: return false
	if "special_reach_driver" in _player and _player.special_reach_driver != null and _player.special_reach_driver.owns_presentation(): return false
	return true

## Solve the deferred arm IK now, against the paddle's current transform. Called
## before anything reads arm/hand transforms, and at the end of each tick/frame.
func ensure_arm_pose() -> void:
	if arm_pending_def == null or not _player or not _player.arm_ik: return
	var def = arm_pending_def
	arm_pending_def = null
	_player.arm_ik.update_arm_ik(0.0, def)

func force_posture_update(def, solve_ik_now: bool = true) -> void :
	if not _player or not _player._ensure_paddle_ready():
		return

	paddle_posture = def.posture_id

	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	var swing_sign: float = _player._get_swing_sign()
	var fwd_sign: float = forward_axis.z

	_posture_lerp_pos = def.resolve_paddle_offset(forehand_axis, forward_axis)
	_posture_lerp_rot = def.resolve_paddle_rotation_deg(swing_sign, fwd_sign)
	_posture_lerp_initialized = true

	_apply_full_body_posture(def)


	if _player.paddle_node:
		_player.paddle_node.global_transform = SwingPath.world_transform(_player, def)
		_posture_lerp_basis = SwingPath.unspun_paddle_basis(_player, def)
		_player._cache_paddle_rest_transform()


	if not solve_ik_now: return



	if _player.leg_ik:
		var feet = _player.leg_ik
		var base: = Vector3(_player.global_position.x, feet.ANKLE_HEIGHT, _player.global_position.z)
		if editor_preview_mode or not feet.feet_initialized or base.distance_to(feet._last_body_position) > feet.TELEPORT_DISTANCE:
			feet.update_leg_ik(0.0, def)
		else:



			var support_delta: float = _player._consume_support_delta()
			if support_delta > 0.0: feet.update_leg_ik(support_delta, def)
			else: feet._solve_legs(0.0, def)
	if _player.arm_ik:
		# Perf: arms are solved once per tick (ensure_arm_pose) instead of on every
		# owner call; body/legs above stay immediate for mid-tick readers.
		if _defer_arms_allowed(): arm_pending_def = def
		else: _player.arm_ik.update_arm_ik(0.0, def)
	# Perf: lets refresh_contact_support skip re-solving the same pose this tick.
	if _player.paddle_node: full_solve_stamp = [Engine.get_physics_frames(), def, _player.paddle_node.global_transform]



func capture_displayed_pose() -> PostureDefinition:
	ensure_arm_pose()   # reads elbow/wrist off the rig
	var source = _presented_body_pose if _presented_body_pose != null else _player.get_runtime_posture_def()
	var pose: PostureDefinition = source.lerp_with(source, 0.0)
	var fh: Vector3 = _player._get_forehand_axis()
	var fwd: Vector3 = _player._get_forward_axis()
	var stance: = Basis(fh, Vector3.UP, - fwd)
	var raw_paddle: Transform3D = SwingPath.remove_in_hand_transform(_player.paddle_node.global_transform, pose)
	var basis: Basis = stance.inverse() * raw_paddle.basis
	pose.paddle_pitch_base_deg = rad_to_deg(atan2( - basis.z.y, basis.z.z))
	pose.paddle_yaw_base_deg = rad_to_deg(asin(clampf(basis.z.x, -1.0, 1.0)))
	pose.paddle_roll_base_deg = rad_to_deg(atan2(basis.y.x, basis.x.x))
	if absf(basis.z.x) > 0.999999:
		pose.paddle_pitch_base_deg = rad_to_deg(signf(basis.z.x) * atan2(basis.x.y, basis.y.y))
		pose.paddle_roll_base_deg = 0.0
	pose.paddle_pitch_signed_deg = 0.0
	pose.paddle_yaw_signed_deg = 0.0
	pose.paddle_roll_signed_deg = 0.0
	var head: Vector3 = raw_paddle * PaddleSize.HEAD_OFFSET - _player.global_position
	pose.paddle_forehand_mul = head.dot(fh)
	pose.paddle_forward_mul = head.dot(fwd)
	pose.paddle_y_offset = head.y
	var body: Node3D = _player.body_pivot
	var body_angles: Vector3 = (stance.inverse() * body.basis * stance).get_euler() * (180.0 / PI)
	pose.body_pitch_deg = - body_angles.x
	pose.body_yaw_deg = - body_angles.y
	pose.body_roll_deg = body_angles.z
	# The explicit pose translation is already retained by lerp_with above.
	# Recover only the remaining crouch/load so capture cannot double it.
	var untranslated_body: Vector3 = body.position - VisibleBody.position_offset(_player, pose)
	pose.crouch_amount = 0.3 - untranslated_body.y
	pose.weight_shift = untranslated_body.dot(fwd) / 0.1


	var pelvis_angles: Vector3 = (stance.inverse() * body.get_node("HipsMesh").basis * stance).get_euler()
	pose.hip_yaw_deg = - rad_to_deg(pelvis_angles.y)
	pose.set_meta("visual_locomotion_weight", 0.0)


	var waist_prefix: Basis = VisibleBody.waist_transform(_player, pose).basis
	var chest_residual: Basis = waist_prefix.inverse() * body.get_node("TorsoMesh").basis
	var torso_angles: Vector3 = (stance.inverse() * chest_residual * stance).get_euler() * (180.0 / PI)
	pose.torso_pitch_deg = - torso_angles.x - 28.0
	pose.torso_yaw_deg = - torso_angles.y
	pose.torso_roll_deg = torso_angles.z

	for right in [true, false]:
		var arm = _player.right_arm_node if right else _player.left_arm_node
		var angles: Vector3 = pose.right_shoulder_rotation_deg if right else pose.left_shoulder_rotation_deg
		var rotation: Basis = stance * Basis.from_euler(angles * (PI / 180.0)) * stance.inverse()
		var shoulder: Vector3 = arm.upper_pivot.global_position
		var pole: Vector3 = shoulder + rotation.inverse() * (arm.forearm_pivot.global_position - shoulder) - _player.global_position
		var local: = Vector3(pole.dot(fh), pole.y, pole.dot(fwd))
		if right: pose.right_elbow_pole = local
		else: pose.left_elbow_pole = local
	var support_arm = _player.right_arm_node if pose.paddle_hand == 1 else _player.left_arm_node


	var wrist: Vector3 = support_arm.hand_mesh.global_transform * support_arm.articulated_hand.wrist_socket - _player.global_position
	var side: float = 1.0 if pose.paddle_hand == 1 else -1.0
	pose.set_meta("support_grip_weight", SwingPath.support_grip_weight(source))
	pose.left_hand_mode = 4
	var support_offset: = Vector3(wrist.dot(fh) - 0.15 * side, wrist.y - 0.15, wrist.dot(fwd) - 0.55)
	if pose.paddle_hand == 1: pose.right_hand_offset = support_offset
	else: pose.left_hand_offset = support_offset
	return pose

func place_paddle_at_side() -> void :
	if _player.paddle_node == null:
		return

	force_posture_update(_posture_lib.get_def(_player.PaddlePosture.FOREHAND))

func set_trajectory_points(points: Array[Vector3]) -> void :
	_trajectory_points = points
	_commit_selector.set_trajectory_points(points)

func _get_contact_point_local() -> Vector3:


	if _trajectory_points.is_empty():
		return _contact_point_local
	var fwd: Vector3 = _player._get_forward_axis()
	var fh: Vector3 = _player._get_forehand_axis()
	var player_pos: Vector3 = _player.global_position



	var best_dist: float = INF
	var best_world: Vector3 = Vector3.ZERO
	for pt in _trajectory_points:
		var offset: Vector3 = pt - player_pos
		var forward_dist: float = offset.dot(fwd)
		if forward_dist < 0.0:
			continue
		var plane_dist: float = abs(forward_dist - GHOST_FORWARD_PLANE)
		if plane_dist < best_dist:
			best_dist = plane_dist
			best_world = pt
	if best_world != Vector3.ZERO and best_dist < GHOST_CONTACT_MAX_DIST:
		var off: Vector3 = best_world - player_pos
		var lx: float = clampf(off.dot(fh), - GHOST_STRETCH_LATERAL_MAX, GHOST_STRETCH_LATERAL_MAX)


		var min_off_y: float = _player.COURT_FLOOR_Y - player_pos.y
		var ly: float = clampf(off.y, min_off_y, GHOST_STRETCH_HEIGHT_MAX)
		_contact_point_local = fh * lx + Vector3.UP * ly + fwd * GHOST_FORWARD_PLANE

	return _contact_point_local

func _find_closest_ghost_to_point(ref: Vector3) -> int:


	var awareness_grid = _player.awareness_grid if _player.has_method("awareness_grid") else null
	return _commit_selector.find_best_green_posture(
		ref, 
		posture_ghosts, 
		POSTURE_ZONES, 
		_player.PaddlePosture.CHARGE_FOREHAND, 
		_player.PaddlePosture.CHARGE_BACKHAND, 
		_player.global_position, 
		_player._get_forehand_axis(), 
		_player.COURT_FLOOR_Y, 
		awareness_grid
	)

func force_paddle_head_to_ghost() -> void :
	if editor_preview_mode:
		return
	if human_contact != null:
		human_contact._apply_visual()
		return
	if _player.hitting and (_player.hitting.charge_visual_active or _player.hitting.is_in_follow_through or _player.hitting.serving_visual_active):
		return




	if _committed_incoming_posture < 0 or _last_commit_stage < 0:
		return
	var ghost: Node3D = posture_ghosts.get(_committed_incoming_posture)
	if not ghost or not _player.paddle_node:
		return
	var ghost_world: Vector3 = ghost.global_position



	var ghost_head: Vector3 = ghost_world + ghost.global_transform.basis.y.normalized() * PaddleSize.HEAD_CENTER_Y * POSTURE_GHOST_SCALE.y
	var target: Vector3 = ghost_head - _player.paddle_node.global_transform.basis.y * PaddleSize.HEAD_CENTER_Y



	var reach_D: float = _player.paddle_node.global_position.distance_to(target)
	var fitts_W: float = 0.08
	var fitts_ID: float = log(reach_D / fitts_W + 1.0) / log(2.0)
	var fitts_MT: float = 0.05 + 0.12 * fitts_ID




	var stage_compression: float
	match _last_commit_stage:
		2: stage_compression = 0.3
		1: stage_compression = 0.55
		_: stage_compression = 0.8
	var halflife: float = maxf(fitts_MT * 0.35 * stage_compression, 0.02)

	var dt: float = get_process_delta_time()
	_player.paddle_node.global_position = _player._damp_v3(
		_player.paddle_node.global_position, target, halflife, dt
	)

func reset_incoming_highlight() -> void :
	if human_contact:
		human_contact.contact = {}



	if not _scored_this_ball and _closest_ball2ghost < INF and _committed_incoming_posture >= 0:
		var grade: String = _commit_selector.grade_ball_to_ghost(_closest_ball2ghost)
		var pname: String = _player.DEBUG_POSTURE_NAMES[_committed_incoming_posture] if _committed_incoming_posture < _player.DEBUG_POSTURE_NAMES.size() else "?"
		if RuntimePolicy.developer_tools: print("[SCORE P%d] %s %s closest=%.2f commits=%d poses=%d greens=%d (reset)" % [_player.player_num, grade, pname, _closest_ball2ghost, _commit_count, _pose_change_count, _green_trigger_count])
		if _player.player_num == 0:
			grade_flashed.emit(grade)
		_scored_this_ball = true
	_ball_incoming = false
	_incoming_timer = 0.0
	_incoming_expired = false
	_green_lit_postures.clear()
	_first_green_posture = -1
	_committed_incoming_posture = -1
	_last_commit_stage = -1
	_blue_hold_timer = 0.0
	_blue_latched = false
	_ghost_frozen_at = Vector3.ZERO
	_commit_locked = false
	_emit_stage_cleared()
	_last_commit_ref_y = 0.0
	_last_commit_player_pos = Vector3.ZERO
	_commit_count = 0
	_pose_change_count = 0
	_last_counted_posture = -1
	_green_trigger_count = 0
	_closest_ball2ghost = INF
	_scored_this_ball = false
	_last_move_log_pos = Vector3.ZERO

func notify_ball_hit() -> void :
	_hit_posture = paddle_posture
	_hit_flash_t = POSTURE_GHOST_HIT_FLASH_DURATION


func _create_paddle_ghost(material: StandardMaterial3D, label_text: String = "") -> Node3D:
	var ghost: = PaddleScene.instantiate() as StaticBody3D
	ghost.scale = POSTURE_GHOST_SCALE
	ghost.collision_layer = 0
	ghost.collision_mask = 0
	for shape_name in ["CollisionShape3D", "HandleCollision"]:
		var collision: = ghost.get_node_or_null(shape_name)
		if collision:
			collision.queue_free()
	var hitbox: = ghost.get_node_or_null("PaddleHitbox")
	if hitbox:
		hitbox.queue_free()

	for mesh_name in ["Handle", "Head", "Head/HeadTopCurve", "Head/HeadBottomCurve"]:
		var mesh: = ghost.get_node_or_null(mesh_name) as MeshInstance3D
		if mesh:
			mesh.material_override = material

	if label_text != "":
		var label: = Label3D.new()
		label.text = label_text
		label.font_size = 48
		label.pixel_size = 0.002
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = Vector3(0.0, 0.16, 0.0)
		label.modulate = Color(1.0, 1.0, 1.0, 0.9)
		ghost.add_child(label)

	return ghost


func _get_ghost_material(ghost: Node3D) -> StandardMaterial3D:
	if ghost == null:
		return null
	var head: = ghost.get_node_or_null("Head") as MeshInstance3D
	return head.material_override as StandardMaterial3D if head else null


func _apply_ghost_material(ghost: Node3D, material: StandardMaterial3D) -> void :
	if ghost == null or material == null:
		return
	for mesh_name in ["Handle", "Head", "Head/HeadTopCurve", "Head/HeadBottomCurve"]:
		var mesh: = ghost.get_node_or_null(mesh_name) as MeshInstance3D
		if mesh:
			mesh.material_override = material

func create_posture_ghosts(paddle_color: Color) -> void :
	_ghost_base_color = paddle_color
	posture_ghost_root = Node3D.new()
	posture_ghost_root.name = "PostureGhosts"
	posture_ghost_root.visible = false
	_player.add_child(posture_ghost_root)
	posture_ghosts.clear()


	_paddle_head_marker = MeshInstance3D.new()
	var head_mesh: = SphereMesh.new()
	head_mesh.radius = 0.04
	head_mesh.height = 0.08
	head_mesh.radial_segments = 8
	head_mesh.rings = 4
	_paddle_head_marker.mesh = head_mesh
	var head_mat: = StandardMaterial3D.new()
	head_mat.albedo_color = Color(1.0, 0.5, 0.0, 1.0)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.6, 0.0, 1.0)
	head_mat.emission_energy_multiplier = 3.0
	head_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	head_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_paddle_head_marker.material_override = head_mat
	_paddle_head_marker.top_level = true
	posture_ghost_root.add_child(_paddle_head_marker)

	for posture in [
		_player.PaddlePosture.FOREHAND, 
		_player.PaddlePosture.FORWARD, 
		_player.PaddlePosture.BACKHAND, 
		_player.PaddlePosture.MEDIUM_OVERHEAD, 
		_player.PaddlePosture.HIGH_OVERHEAD, 
		_player.PaddlePosture.LOW_FOREHAND, 
		_player.PaddlePosture.LOW_FORWARD, 
		_player.PaddlePosture.LOW_BACKHAND, 
		_player.PaddlePosture.CHARGE_FOREHAND, 
		_player.PaddlePosture.CHARGE_BACKHAND, 
		_player.PaddlePosture.WIDE_FOREHAND, 
		_player.PaddlePosture.WIDE_BACKHAND, 
		_player.PaddlePosture.VOLLEY_READY, 
		_player.PaddlePosture.MID_LOW_FOREHAND, 
		_player.PaddlePosture.MID_LOW_BACKHAND, 
		_player.PaddlePosture.MID_LOW_FORWARD, 
		_player.PaddlePosture.MID_LOW_WIDE_FOREHAND, 
		_player.PaddlePosture.MID_LOW_WIDE_BACKHAND, 
		_player.PaddlePosture.LOW_WIDE_FOREHAND, 
		_player.PaddlePosture.LOW_WIDE_BACKHAND, 
	]:
		var ghost_material: StandardMaterial3D = StandardMaterial3D.new()


		if posture == _player.PaddlePosture.CHARGE_FOREHAND or posture == _player.PaddlePosture.CHARGE_BACKHAND:
			ghost_material.albedo_color = Color(paddle_color.r * 0.5, paddle_color.g * 0.5, paddle_color.b * 0.5, POSTURE_GHOST_ALPHA * 1.5)
			ghost_material.emission = Color(paddle_color.r * 0.4 + 0.1, paddle_color.g * 0.4 + 0.1, paddle_color.b * 0.4 + 0.1, 1.0)
			ghost_material.emission_energy_multiplier = 0.08
		else:
			ghost_material.albedo_color = Color(paddle_color.r, paddle_color.g, paddle_color.b, POSTURE_GHOST_ALPHA)
			ghost_material.emission = Color(paddle_color.r * 0.7 + 0.2, paddle_color.g * 0.7 + 0.2, paddle_color.b * 0.7 + 0.2, 1.0)
			ghost_material.emission_energy_multiplier = 0.12

		ghost_material.emission_enabled = true
		ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		var ghost: = _create_paddle_ghost(
			ghost_material, 
			_player.DEBUG_POSTURE_NAMES[posture] if posture < _player.DEBUG_POSTURE_NAMES.size() else "?"
		)
		posture_ghost_root.add_child(ghost)
		posture_ghosts[posture] = ghost

	update_posture_ghosts()
	_create_follow_through_ghosts()
	_create_posture_zone_bounds()

func _create_posture_zone_bounds() -> void :
	if _player == null or _posture_lib == null:
		return
	_posture_zone_bounds.clear()
	for def in _posture_lib.all_definitions():
		if not def.has_zone:
			continue
		var w: float = def.zone_x_max - def.zone_x_min
		var h: float = def.zone_y_max - def.zone_y_min
		var bounds_mesh: = BoxMesh.new()
		bounds_mesh.size = Vector3(w, h, 0.15)
		var mi: = MeshInstance3D.new()
		mi.mesh = bounds_mesh
		mi.name = "ZoneBounds_" + str(def.posture_id)
		var mat: = StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.1, 1.0, 0.15)
		mat.emission = Color(0.5, 0.05, 0.95, 1.0)
		mat.emission_energy_multiplier = 0.3
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
		mi.visible = false

		var face_configs: = [
			{"name": "FaceLeft", "color": Color(1.0, 0.2, 0.2, 0.3)}, 
			{"name": "FaceRight", "color": Color(1.0, 0.2, 0.2, 0.3)}, 
			{"name": "FaceBottom", "color": Color(0.2, 1.0, 0.2, 0.3)}, 
			{"name": "FaceTop", "color": Color(0.2, 1.0, 0.2, 0.3)}, 
			{"name": "FaceFront", "color": Color(0.2, 0.2, 1.0, 0.3)}, 
			{"name": "FaceBack", "color": Color(0.2, 0.2, 1.0, 0.3)}, 
		]
		for cfg in face_configs:
			var face_mi: = MeshInstance3D.new()
			face_mi.name = cfg["name"]
			var fmat: = StandardMaterial3D.new()
			fmat.albedo_color = cfg["color"]
			fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
			face_mi.material_override = fmat
			face_mi.visible = false
			mi.add_child(face_mi)
		_update_zone_face_planes(mi)
		_player.add_child(mi)
		_posture_zone_bounds[def.posture_id] = mi

func _update_zone_face_planes(zone_mi: MeshInstance3D) -> void :
	var mesh: BoxMesh = zone_mi.mesh as BoxMesh
	if mesh == null:
		return
	var half_size: = mesh.size / 2.0
	var thin: = 0.001
	var configs: = [
		{"name": "FaceLeft", "size": Vector3(thin, mesh.size.y, mesh.size.z), "pos": Vector3( - half_size.x, 0, 0)}, 
		{"name": "FaceRight", "size": Vector3(thin, mesh.size.y, mesh.size.z), "pos": Vector3(half_size.x, 0, 0)}, 
		{"name": "FaceBottom", "size": Vector3(mesh.size.x, thin, mesh.size.z), "pos": Vector3(0, - half_size.y, 0)}, 
		{"name": "FaceTop", "size": Vector3(mesh.size.x, thin, mesh.size.z), "pos": Vector3(0, half_size.y, 0)}, 
		{"name": "FaceFront", "size": Vector3(mesh.size.x, mesh.size.y, thin), "pos": Vector3(0, 0, - half_size.z)}, 
		{"name": "FaceBack", "size": Vector3(mesh.size.x, mesh.size.y, thin), "pos": Vector3(0, 0, half_size.z)}, 
	]
	for cfg in configs:
		var face_mi = zone_mi.get_node_or_null(cfg["name"])
		if face_mi == null:
			continue
		var fm: = BoxMesh.new()
		fm.size = cfg["size"]
		face_mi.mesh = fm
		face_mi.position = cfg["pos"]

func _set_zone_visibility(zone_mi: MeshInstance3D, visible: bool) -> void :



	var allowed: bool = editor_preview_mode or (posture_ghost_root != null and posture_ghost_root.visible)
	var show_zone: bool = visible and allowed
	zone_mi.visible = show_zone
	for face_name in ["FaceLeft", "FaceRight", "FaceBottom", "FaceTop", "FaceFront", "FaceBack"]:
		var face_mi = zone_mi.get_node_or_null(face_name)
		if face_mi:
			face_mi.visible = show_zone

func _create_follow_through_ghosts() -> void :
	if posture_ghost_root == null or not _player.hitting:
		return
	var ft_family_postures: Dictionary = {
		FT_FOREHAND: _player.PaddlePosture.FOREHAND, 
		FT_BACKHAND: _player.PaddlePosture.BACKHAND, 
		FT_CENTER: _player.PaddlePosture.FORWARD, 
		FT_OVERHEAD: _player.PaddlePosture.HIGH_OVERHEAD, 
	}
	for ft_key in FT_KEYS:
		var base_posture: int = ft_family_postures[ft_key]

		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.1, 0.9, 0.95, 0.35)
		mat.emission_enabled = true
		mat.emission = Color(0.0, 0.8, 0.9, 1.0)
		mat.emission_energy_multiplier = 0.25
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var ghost: = _create_paddle_ghost(mat)
		posture_ghost_root.add_child(ghost)
		_place_ghost_pose(ghost, SwingPath.endpoint(_posture_lib.get_def(base_posture), 2))
		ft_ghosts[ft_key] = ghost

func set_ghosts_visible(v: bool) -> void :

	set_posture_ghosts_visible(v)
	set_charge_ghosts_visible(v)
	set_follow_through_visible(v)


func set_posture_ghosts_visible(v: bool) -> void :
	_posture_ghosts_visible = v
	if posture_ghost_root:
		posture_ghost_root.visible = _any_ghosts_visible()


func set_charge_ghosts_visible(v: bool) -> void :
	_charge_ghosts_visible = v
	if posture_ghost_root:
		posture_ghost_root.visible = _any_ghosts_visible()


func set_follow_through_visible(v: bool) -> void :
	_follow_through_visible = v
	if posture_ghost_root:
		posture_ghost_root.visible = _any_ghosts_visible()
	for ft_key in FT_KEYS:
		var ghost = ft_ghosts.get(ft_key)
		if ghost:
			ghost.visible = v


func set_charge_highlight_active(v: bool) -> void :
	_charge_highlight_active = v


func _any_ghosts_visible() -> bool:
	return _posture_ghosts_visible or _charge_ghosts_visible or _follow_through_visible

func _apply_ghost_separation() -> void :
	var keys: = posture_ghosts.keys()
	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			var a: Node3D = posture_ghosts[keys[i]]
			var b: Node3D = posture_ghosts[keys[j]]
			if a == null or b == null:
				continue
			var diff: Vector3 = a.position - b.position
			var dist: float = diff.length()
			if dist < GHOST_MIN_DISTANCE and dist > 0.001:
				var push: Vector3 = diff.normalized() * (GHOST_MIN_DISTANCE - dist) * 0.5
				a.position += push
				b.position -= push

func update_posture_ghosts() -> void :
	if posture_ghost_root == null:
		return
	if human_contact != null and not editor_preview_mode:
		human_contact.draw_ghosts()
		return
	var ball: RigidBody3D = _player._get_ball_ref()


	var delta: float = get_process_delta_time()
	if _hit_flash_t > 0.0:
		_hit_flash_t = maxf(_hit_flash_t - delta, 0.0)







	if _player.player_num == 0 and ball != null and not _scored_this_ball:
		var toward: float = ball.linear_velocity.dot( - _player._get_forward_axis())
		if toward > 0.5 and _committed_incoming_posture < 0:
			var pre_ttc: float = _commit_selector.compute_ttc(ball.global_position, ball.linear_velocity, _player.global_position)
			var pre_stage: int = 0
			if pre_ttc < TTC_BLUE:
				pre_stage = 2
			elif pre_ttc < TTC_PURPLE:
				pre_stage = 1
			var pre_commit_dist: float = Vector2(ball.global_position.x - _player.global_position.x, ball.global_position.z - _player.global_position.z).length()
			incoming_stage_changed.emit(pre_stage, -1, pre_commit_dist, 999.0, pre_ttc)


	if _trajectory_points.is_empty() and ball != null and ball is RigidBody3D and ball.linear_velocity.length() > 0.5:
		var traj: Array[Vector3] = _commit_selector.compute_simple_trajectory(ball.global_position, ball.linear_velocity, _BallInfo.get_effective_gravity(), _player.COURT_FLOOR_Y)
		if not traj.is_empty():
			set_trajectory_points(traj)
			if _player.awareness_grid:
				_player.awareness_grid.set_trajectory_points(traj)


	if ball != null and ball is RigidBody3D:
		var toward_player: float = ball.linear_velocity.dot( - _player._get_forward_axis())
		var ball_d_ghost: float = Vector2(ball.global_position.x - _player.global_position.x, ball.global_position.z - _player.global_position.z).length()
		var to_ball_fwd: float = (ball.global_position - _player.global_position).dot(_player._get_forward_axis())
		var ball_behind: bool = to_ball_fwd < 0.0

		if toward_player > 1.0 and not ball_behind:

			if _incoming_expired:
				_incoming_expired = false
				_ball_incoming = false
				_committed_incoming_posture = -1
				_last_commit_stage = -1
				_contact_point_local = Vector3.ZERO
				_emit_stage_cleared()
				if _player.awareness_grid:
					_player.awareness_grid.reset()



			if _committed_incoming_posture >= 0 and not _ball_incoming and ball_d_ghost > 5.0:
				_committed_incoming_posture = -1
				_last_commit_stage = -1
				_contact_point_local = Vector3.ZERO
				_emit_stage_cleared()

			if not _ball_incoming and not _incoming_expired:
				_incoming_timer = 0.0
				_ball_incoming = true
				var ppos: Vector3 = _player.global_position
				var pvel: Vector3 = _player.current_velocity
				var fwd_dir: Vector3 = _player._get_forward_axis()
				if RuntimePolicy.developer_tools: print("[TRACK P%d] incoming=true toward=%.1f traj_pts=%d pos=(%.1f,%.1f,%.1f) spd=%.1f dir=(%.2f,%.2f)" % [
					_player.player_num, toward_player, _trajectory_points.size(), 
					ppos.x, ppos.y, ppos.z, 
					pvel.length(), 
					fwd_dir.x, fwd_dir.z])
		else:
			_incoming_expired = false


			if _blue_latched and toward_player <= -0.5:
				_blue_latched = false
				_ghost_frozen_at = Vector3.ZERO
				_blue_hold_timer = 0.0


			if _committed_incoming_posture >= 0 and not _ball_incoming:
				_committed_incoming_posture = -1
				_last_commit_stage = -1
				_contact_point_local = Vector3.ZERO
				_emit_stage_cleared()
				if _player.awareness_grid:
					_player.awareness_grid.reset()


			if _committed_incoming_posture >= 0 and to_ball_fwd < -3.0:
				_committed_incoming_posture = -1
				_last_commit_stage = -1
				_contact_point_local = Vector3.ZERO
				_emit_stage_cleared()
				if _player.awareness_grid:
					_player.awareness_grid.reset()


	if _ball_incoming:
		_incoming_timer += delta
		if _incoming_timer >= INCOMING_GLOW_DURATION:
			_ball_incoming = false
			_incoming_expired = true
			_green_fade_t = 0.0


			_committed_incoming_posture = -1
			_last_commit_stage = -1
			_contact_point_local = Vector3.ZERO
			_emit_stage_cleared()
			if _player.awareness_grid:
				_player.awareness_grid.reset()


	if not _ball_incoming and not _green_lit_postures.is_empty():
		_green_fade_t += delta
		if _green_fade_t >= INCOMING_FADE_DURATION * 2.0:
			_green_lit_postures.clear()
	_first_green_posture = -1

	var _frame_lit_postures: Array = []

	var contact_local: Vector3 = Vector3.ZERO
	if _ball_incoming and _committed_incoming_posture >= 0:
		contact_local = _get_contact_point_local()
	for posture in posture_ghosts.keys():
		var ghost: Node3D = posture_ghosts[posture]
		if ghost == null:
			continue


		if not editor_preview_mode:
			var pose: PostureDefinition = _posture_lib.get_def(posture)
			var head_world: = Vector3.INF
			if _ball_incoming and posture == _committed_incoming_posture and contact_local != Vector3.ZERO:
				var relative_head: Vector3 = _compute_committed_ghost_target(contact_local, pose, Vector3.ZERO, 
					_player._get_forehand_axis(), _player._get_forward_axis(), _player.COURT_FLOOR_Y, _player.global_position.y)
				head_world = PaddleReach.clamp_for_player(_player, _player.global_position + relative_head)
				var old_head: Vector3 = ghost.global_transform * PaddleSize.HEAD_OFFSET
				head_world = old_head.lerp(head_world, 1.0 - exp( - get_process_delta_time() * 10.0))
			_place_ghost_pose(ghost, pose, head_world)


		var is_charge: bool = posture in [_player.PaddlePosture.CHARGE_FOREHAND, _player.PaddlePosture.CHARGE_BACKHAND]
		var debug_overrides_solo: bool = _any_ghosts_visible()
		if _editor_solo_posture_id >= 0:
			ghost.visible = _ghost_matches_editor_solo(posture, _editor_solo_posture_id)
		elif solo_mode and not debug_overrides_solo:
			ghost.visible = (posture == selected_posture_id)
		else:
			if is_charge:
				ghost.visible = _charge_ghosts_visible
			else:
				ghost.visible = _posture_ghosts_visible

		var ghost_material: StandardMaterial3D = _get_ghost_material(ghost)


		if is_charge and _charge_highlight_active and ghost_material != null:
			var pulse: float = (sin(Time.get_ticks_msec() * 0.004) + 1.0) * 0.5
			ghost_material.emission_energy_multiplier = 0.08 + pulse * 0.5

		if ghost_material != null:
			var is_active: bool = posture == paddle_posture
			var ball_dist: float = INF
			if ball != null:
				ball_dist = ghost.global_position.distance_to(ball.global_position)
			var is_near: bool = ball_dist < POSTURE_GHOST_NEAR_RADIUS
			var near_t: float = clampf(1.0 - ball_dist / POSTURE_GHOST_NEAR_RADIUS, 0.0, 1.0)

			var is_hit_flash: bool = posture == _hit_posture and _hit_flash_t > 0.0
			var hit_t: float = _hit_flash_t / POSTURE_GHOST_HIT_FLASH_DURATION

			if is_hit_flash:
				var hf: Dictionary = _PostureColors.hit_flash(hit_t)
				ghost_material.albedo_color = hf.albedo
				ghost_material.emission = hf.emission
				ghost_material.emission_energy_multiplier = hf.em_mult
			elif posture == _committed_incoming_posture and _ball_incoming:

				var ghost_world: Vector3 = ghost.global_position
				var ball_to_ghost: float = ghost_world.distance_to(ball.global_position)
				if ball_to_ghost < _closest_ball2ghost:
					_closest_ball2ghost = ball_to_ghost
				var commit_dist: float = Vector2(ball.global_position.x - _player.global_position.x, ball.global_position.z - _player.global_position.z).length()
				var ttc: float = _commit_selector.compute_ttc(ball.global_position, ball.linear_velocity, ghost_world)


				if _blue_hold_timer > 0.0:
					_blue_hold_timer -= get_physics_process_delta_time()
				var stage: int = _PostureColors.compute_stage(ttc, ball_to_ghost, _blue_hold_timer, _blue_latched)
				if stage == 2 and not _blue_latched:
					_blue_latched = true
					_blue_hold_timer = BLUE_HOLD_DURATION
					_ghost_frozen_at = ghost_world

				var sc: Dictionary = _PostureColors.stage_colors(stage)
				ghost_material.albedo_color = Color(sc.albedo.r, sc.albedo.g, sc.albedo.b, sc.alpha)
				ghost_material.emission = sc.emission
				ghost_material.emission_energy_multiplier = sc.em_mult


				var pname: String = _player.DEBUG_POSTURE_NAMES[posture] if posture < _player.DEBUG_POSTURE_NAMES.size() else "?"
				if _player.player_num == 0:
					incoming_stage_changed.emit(stage, _committed_incoming_posture, commit_dist, ball_to_ghost, ttc)
				if stage != _last_commit_stage:
					var stage_names: Array[String] = ["PINK", "PURPLE", "BLUE"]
					if RuntimePolicy.developer_tools: print("[COLOR P%d] %s %s ttc=%.2f d=%.1f ball2ghost=%.2f traj_pts=%d pos=(%.1f,%.1f)" % [_player.player_num, stage_names[stage], pname, ttc, commit_dist, ball_to_ghost, _trajectory_points.size(), _player.global_position.x, _player.global_position.z])
					_last_commit_stage = stage


					if stage == 2 and not _scored_this_ball:
						_scored_this_ball = true
						var grade: String = _commit_selector.grade_ball_to_ghost(_closest_ball2ghost)
						if RuntimePolicy.developer_tools: print("[SCORE P%d] %s %s closest=%.2f commits=%d poses=%d greens=%d" % [_player.player_num, grade, pname, _closest_ball2ghost, _commit_count, _pose_change_count, _green_trigger_count])
						if _player.player_num == 0:
							grade_flashed.emit(grade)


				if _zone_exit_cooldown > 0.0:
					_zone_exit_cooldown -= get_physics_process_delta_time()
				var ball_in_front: bool = false
				if ball != null:
					var to_ball_fwd: float = (ball.global_position - _player.global_position).dot(_player._get_forward_axis())
					ball_in_front = to_ball_fwd > 0.0
				if stage < 2 and _zone_exit_cooldown <= 0.0 and ball_in_front:
					var traj_pt: Vector3 = _commit_selector.find_closest_trajectory_point(_player.global_position, _player.COURT_FLOOR_Y)
					var fh_r: Vector3 = _player._get_forehand_axis()
					var contact_lat: float = (traj_pt - _player.global_position).dot(fh_r)
					var contact_ht: float = traj_pt.y - _player.COURT_FLOOR_Y
					if _player.awareness_grid:
						var ri: Dictionary = _player.awareness_grid.get_approach_info()
						if ri.confidence > 5:
							contact_lat = ri.lateral
							contact_ht = ri.height
					var zone: Dictionary = POSTURE_ZONES.get(_committed_incoming_posture, {})
					if not zone.is_empty():
						var outside: bool = contact_lat < zone.x_min - ZONE_EXIT_MARGIN or contact_lat > zone.x_max + ZONE_EXIT_MARGIN or contact_ht < zone.y_min - ZONE_EXIT_MARGIN or contact_ht > zone.y_max + ZONE_EXIT_MARGIN
						if outside:
							var better_z: int = _find_closest_ghost_to_point(traj_pt)
							if better_z >= 0 and better_z != _committed_incoming_posture:
								var old_n: String = _player.DEBUG_POSTURE_NAMES[_committed_incoming_posture] if _committed_incoming_posture < _player.DEBUG_POSTURE_NAMES.size() else "?"
								var new_n: String = _player.DEBUG_POSTURE_NAMES[better_z] if better_z < _player.DEBUG_POSTURE_NAMES.size() else "?"
								_committed_incoming_posture = better_z
								paddle_posture = better_z
								_zone_exit_cooldown = 0.2
								if RuntimePolicy.developer_tools: print("[ZONE_EXIT P%d] %s -> %s (lat=%.2f ht=%.2f)" % [_player.player_num, old_n, new_n, contact_lat, contact_ht])
			elif _commit_selector.is_ghost_near_trajectory(posture, posture_ghosts, _player.PaddlePosture.CHARGE_FOREHAND, _player.PaddlePosture.CHARGE_BACKHAND) and _ball_incoming:
				if posture not in _green_lit_postures:
					_green_trigger_count += 1

					var is_primary_green: bool = posture in [
						_player.PaddlePosture.FOREHAND, _player.PaddlePosture.BACKHAND, 
						_player.PaddlePosture.WIDE_FOREHAND, _player.PaddlePosture.WIDE_BACKHAND, 
						_player.PaddlePosture.FORWARD, _player.PaddlePosture.MEDIUM_OVERHEAD, 
						_player.PaddlePosture.HIGH_OVERHEAD, _player.PaddlePosture.VOLLEY_READY]
					if _first_green_posture < 0 and is_primary_green:
						_first_green_posture = posture
					var gname: String = _player.DEBUG_POSTURE_NAMES[posture] if posture < _player.DEBUG_POSTURE_NAMES.size() else "?"
					var gw: Vector3 = _player.global_position + _offset_resolver.get_posture_offset_for(posture)
					var first_tag: String = " ★FIRST" if posture == _first_green_posture else ""
					if RuntimePolicy.developer_tools: print("[GREEN P%d] +%s (#%d) ghost2traj=%.2f pos=(%.1f,%.1f)%s" % [_player.player_num, gname, _green_trigger_count, gw.distance_to(ball.global_position), _player.global_position.x, _player.global_position.z, first_tag])
				_green_lit_postures[posture] = Engine.get_physics_frames()
				var pname: String = _player.DEBUG_POSTURE_NAMES[posture] if posture < _player.DEBUG_POSTURE_NAMES.size() else str(posture)
				_frame_lit_postures.append(pname)
				ghost_material.albedo_color = Color(0.1, 1.0, 0.2, POSTURE_GHOST_NEAR_ALPHA)
				ghost_material.emission = Color(0.0, 1.0, 0.1, 1.0)
				ghost_material.emission_energy_multiplier = POSTURE_GHOST_NEAR_EMISSION
			elif posture in _green_lit_postures:

				var frames_since_lit: int = Engine.get_physics_frames() - int(_green_lit_postures[posture])
				var secs_since: float = frames_since_lit * get_physics_process_delta_time()
				var fade_t: float = clampf(secs_since / INCOMING_FADE_DURATION, 0.0, 1.0)
				var fade_result: Dictionary = _PostureColors.green_fading(fade_t, _ghost_base_color)
				if fade_t >= 1.0:
					_green_lit_postures.erase(posture)
				ghost_material.albedo_color = fade_result.albedo
				ghost_material.emission = fade_result.emission
				ghost_material.emission_energy_multiplier = fade_result.em_mult
			elif is_near:
				var pc: Dictionary = _PostureColors.proximity_color(near_t, false, _ghost_base_color)
				ghost_material.albedo_color = pc.albedo
				ghost_material.emission_energy_multiplier = pc.em_mult
			elif is_active:
				var pc: Dictionary = _PostureColors.proximity_color(0.0, true, _ghost_base_color)
				ghost_material.albedo_color = pc.albedo
				ghost_material.emission_energy_multiplier = pc.em_mult
			else:
				var pc: Dictionary = _PostureColors.proximity_color(0.0, false, _ghost_base_color)
				ghost_material.albedo_color = pc.albedo
				ghost_material.emission_energy_multiplier = pc.em_mult
			var is_purple: bool = posture == _committed_incoming_posture and _ball_incoming
			if not is_purple and not (_commit_selector.is_ghost_near_trajectory(posture, posture_ghosts, _player.PaddlePosture.CHARGE_FOREHAND, _player.PaddlePosture.CHARGE_BACKHAND) and _ball_incoming) and not (posture in _green_lit_postures) and not is_hit_flash:
				ghost_material.emission = Color(_ghost_base_color.r * 0.7 + 0.2, _ghost_base_color.g * 0.7 + 0.2, _ghost_base_color.b * 0.7 + 0.2, 1.0)






			if _player.awareness_grid and _ball_incoming and not is_purple and not is_hit_flash:
				var g_ttc: float = _player.awareness_grid.get_ttc_at_world_point(ghost.global_position, 0.45)
				if g_ttc < 1.5:
					var tier: Color = _player.awareness_grid._get_time_color(g_ttc)
					var ov: Dictionary = _PostureColors.grid_override(g_ttc, tier)
					ghost_material.albedo_color = ov.albedo
					ghost_material.emission = ov.emission
					ghost_material.emission_energy_multiplier = ov.em_mult


			if _editor_solo_posture_id >= 0:
				ghost_material.albedo_color.a = minf(ghost_material.albedo_color.a + 0.18, 0.55)
				ghost_material.emission_energy_multiplier = minf(ghost_material.emission_energy_multiplier * 2.2, 2.0)

			_apply_ghost_material(ghost, ghost_material)

	_update_ft_ghosts()

	if _ball_incoming and _frame_lit_postures != _last_lit_postures:
		_last_lit_postures = _frame_lit_postures.duplicate()
	elif not _ball_incoming:
		_last_lit_postures.clear()


	var fh: Vector3 = _player._get_forehand_axis()
	var fwd: Vector3 = _player._get_forward_axis()
	var player_y: float = _player.global_position.y
	for posture in _posture_zone_bounds.keys():
		var mi: MeshInstance3D = _posture_zone_bounds[posture]
		var zone_def = _posture_lib.get_def(posture) if _posture_lib else null
		if zone_def == null or not zone_def.has_zone:
			continue
		var ghost: Node3D = posture_ghosts.get(posture)


		var ghost_pos: Vector3 = ghost.position if ghost else Vector3.ZERO
		var ghost_x: float = ghost_pos.dot(fh)
		var ghost_z: float = ghost_pos.dot(fwd)


		var zone_y_min_rel: float = _player.COURT_FLOOR_Y + zone_def.zone_y_min - player_y
		var zone_y_max_rel: float = _player.COURT_FLOOR_Y + zone_def.zone_y_max - player_y
		var zone_cx: float = (zone_def.zone_x_min + zone_def.zone_x_max) * 0.5
		var zone_cy: float = (zone_y_min_rel + zone_y_max_rel) * 0.5
		var zone_cz: float = zone_def.zone_forward_offset


		if not editor_preview_mode:
			var is_committed: bool = (posture == _committed_incoming_posture)
			var cx: float = _compute_zone_center(ghost_x, zone_cx, _ball_incoming, is_committed)
			var cy: float = zone_cy
			var cz: float = _compute_zone_center(ghost_z, zone_cz, _ball_incoming, is_committed)
			mi.position = fh * cx + Vector3.UP * cy + fwd * cz
			var mesh: BoxMesh = mi.mesh as BoxMesh
			if mesh:
				mesh.size = Vector3(zone_def.zone_x_max - zone_def.zone_x_min, zone_y_max_rel - zone_y_min_rel, 0.15)
			mi.look_at(mi.global_position + fwd, Vector3.UP, true)
		var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D

		if _editor_solo_posture_id >= 0:
			_set_zone_visibility(mi, posture == _editor_solo_posture_id)
			mat.emission_energy_multiplier = 0.65
			mat.albedo_color.a = 0.28
		else:

			var is_imminent: bool = (posture == _committed_incoming_posture
									 or posture in _green_lit_postures
									 or (posture == paddle_posture and _ball_incoming))
			if is_imminent and _ball_incoming:
				_set_zone_visibility(mi, true)
				if posture == _committed_incoming_posture:
					mat.emission_energy_multiplier = 0.65
					mat.albedo_color.a = 0.28
				else:
					mat.emission_energy_multiplier = 0.35
					mat.albedo_color.a = 0.18
			else:
				_set_zone_visibility(mi, false)
				mat.emission_energy_multiplier = 0.3
				mat.albedo_color.a = 0.15

	_apply_ghost_separation()





static func _compute_zone_center(ghost_coord: float, zone_coord: float, ball_incoming: bool, is_committed: bool) -> float:
	if ball_incoming and is_committed:
		return ghost_coord
	return zone_coord if absf(zone_coord - ghost_coord) < 0.3 else ghost_coord




static func _compute_committed_ghost_target(
	contact_local: Vector3, 
	zone_def, 
	head_offset: Vector3, 
	fh_axis: Vector3, 
	fwd_axis: Vector3, 
	court_floor_y: float, 
	player_y: float
) -> Vector3:
	if zone_def != null and zone_def.has_zone:
		var contact_lat: float = contact_local.dot(fh_axis)
		var contact_ht_rel: float = contact_local.y
		var zone_y_min_rel: float = court_floor_y + zone_def.zone_y_min - player_y
		var zone_y_max_rel: float = court_floor_y + zone_def.zone_y_max - player_y
		var clamped_lat: float = clampf(contact_lat, zone_def.zone_x_min, zone_def.zone_x_max)
		var clamped_ht: float = clampf(contact_ht_rel, zone_y_min_rel, zone_y_max_rel)
		var zone_fwd: float = zone_def.zone_forward_offset
		var clamped_head_pos: Vector3 = fh_axis * clamped_lat + Vector3.UP * clamped_ht + fwd_axis * zone_fwd
		return clamped_head_pos - head_offset
	return contact_local - head_offset


func _ghost_matches_editor_solo(ghost_posture: int, solo_posture: int) -> bool:
	if ghost_posture == solo_posture:
		return true

	if solo_posture in _player.FOREHAND_POSTURES and ghost_posture == _player.PaddlePosture.CHARGE_FOREHAND:
		return true
	if solo_posture in _player.BACKHAND_POSTURES and ghost_posture == _player.PaddlePosture.CHARGE_BACKHAND:
		return true
	return false

func _ft_matches_editor_solo(ft_key: int, solo_posture: int) -> bool:
	match ft_key:
		FT_FOREHAND:
			return solo_posture in _player.FOREHAND_POSTURES
		FT_BACKHAND:
			return solo_posture in _player.BACKHAND_POSTURES
		FT_CENTER:
			return solo_posture in _player.CENTER_POSTURES and not (solo_posture in [_player.PaddlePosture.MEDIUM_OVERHEAD, _player.PaddlePosture.HIGH_OVERHEAD])
		FT_OVERHEAD:
			return solo_posture in [_player.PaddlePosture.MEDIUM_OVERHEAD, _player.PaddlePosture.HIGH_OVERHEAD]
	return false

func _place_ghost_pose(ghost: Node3D, pose: PostureDefinition, head_override: Vector3 = Vector3.INF) -> void :
	if pose == null: return
	var transform: Transform3D = SwingPath.world_transform(_player, pose)
	var head: Vector3 = transform * PaddleSize.HEAD_OFFSET if head_override == Vector3.INF else head_override
	var basis: Basis = transform.basis.scaled(POSTURE_GHOST_SCALE)
	ghost.global_transform = Transform3D(basis, head - basis.y * PaddleSize.HEAD_CENTER_Y)

func _update_ft_ghosts() -> void :

	var is_charging: bool = _player.hitting != null and _player.hitting.charge_visual_active
	for ft_key in ft_ghosts.keys():
		var ft_ghost: Node3D = ft_ghosts[ft_key]
		if ft_ghost == null:
			continue
		var families: Dictionary = {FT_FOREHAND: 0, FT_BACKHAND: 2, FT_CENTER: 1, FT_OVERHEAD: 4}
		_place_ghost_pose(ft_ghost, SwingPath.endpoint(_posture_lib.get_def(families[ft_key]), 2))
		var ft_mat: StandardMaterial3D = _get_ghost_material(ft_ghost)
		if ft_mat == null:
			continue
		var matching: bool = false
		if is_charging:
			var cur: int = paddle_posture
			match ft_key:
				FT_FOREHAND: matching = cur in _player.FOREHAND_POSTURES
				FT_BACKHAND: matching = cur in _player.BACKHAND_POSTURES
				FT_CENTER: matching = cur in _player.CENTER_POSTURES
				FT_OVERHEAD: matching = cur in [_player.PaddlePosture.MEDIUM_OVERHEAD, _player.PaddlePosture.HIGH_OVERHEAD]
		if matching:
			ft_mat.albedo_color = Color(0.2, 1.0, 0.95, 0.65)
			ft_mat.emission = Color(0.1, 1.0, 0.9, 1.0)
			ft_mat.emission_energy_multiplier = 1.2
		else:
			ft_mat.albedo_color = Color(0.1, 0.9, 0.95, 0.35)
			ft_mat.emission = Color(0.0, 0.8, 0.9, 1.0)
			ft_mat.emission_energy_multiplier = 0.25
		_apply_ghost_material(ft_ghost, ft_mat)

		if _editor_solo_posture_id >= 0:
			ft_ghost.visible = _ft_matches_editor_solo(ft_key, _editor_solo_posture_id)
		elif not is_charging:
			ft_ghost.visible = _follow_through_visible





func get_posture_charge_sign() -> float:
	match paddle_posture:
		_player.PaddlePosture.BACKHAND, _player.PaddlePosture.LOW_BACKHAND, _player.PaddlePosture.CHARGE_BACKHAND, \
		_player.PaddlePosture.WIDE_BACKHAND, _player.PaddlePosture.MID_LOW_BACKHAND, \
		_player.PaddlePosture.MID_LOW_WIDE_BACKHAND, _player.PaddlePosture.LOW_WIDE_BACKHAND:
			return - _player._get_swing_sign()
		_player.PaddlePosture.FORWARD, _player.PaddlePosture.LOW_FORWARD, _player.PaddlePosture.MID_LOW_FORWARD, \
		_player.PaddlePosture.MEDIUM_OVERHEAD, _player.PaddlePosture.HIGH_OVERHEAD, _player.PaddlePosture.VOLLEY_READY:
			return 0.0
	return _player._get_swing_sign()



func get_posture_offset_for(p: int) -> Vector3:
	return _offset_resolver.get_posture_offset_for(p)

func _get_posture_offset() -> Vector3:


	return _offset_resolver.get_posture_offset_for(paddle_posture)




func _apply_full_body_posture(def_override = null) -> void :
	if _skeleton_applier == null or _posture_lib == null:
		return


	var def = def_override if def_override != null else _player.get_runtime_posture_def()
	if def:
		_presented_body_pose = def
		_skeleton_applier.apply(def)

func _get_basis_from_rotation(rot_deg: Vector3) -> Basis:
	var b: = Basis()
	b = b * Basis(Vector3.RIGHT, deg_to_rad(rot_deg.x))
	b = b * Basis(Vector3.UP, deg_to_rad(rot_deg.y))
	b = b * Basis(Vector3.FORWARD, deg_to_rad(rot_deg.z))
	return b
