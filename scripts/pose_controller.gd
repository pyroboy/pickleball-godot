class_name PoseController extends Node

const LANDING_RECOVERY_FALLBACK = 0.16
const LUNGE_RECOVERY_FALLBACK = 0.18
const JUMP_TAKEOFF_FALLBACK = 0.18
const SPLIT_STEP_FALLBACK = 0.12
const DECEL_PLANT_FALLBACK = 0.14
const LUNGE_LATERAL_THRESHOLD = 0.72
const LOW_SCOOP_HEIGHT = 0.28
const RUN_SPEED_THRESHOLD = 3.0
const SHUFFLE_SPEED_THRESHOLD = 1.2
const DECEL_TRIGGER_SPEED_DELTA = 2.2

var _player
var _library

var base_pose_state: int = 0
var pose_intent: int = 0
var last_contact_context: Dictionary = {}

var landing_recovery_timer: float = 0.0
var lunge_recovery_timer: float = 0.0
var split_step_timer: float = 0.0
var jump_takeoff_timer: float = 0.0
var decel_timer: float = 0.0

var _prev_is_jumping: bool = false
var _prev_speed: float = 0.0
var _prev_commit_stage: int = -1

var _editor_base_pose_override
var _editor_state_override: int = -1
var _composed_pose_cache
var _cache_posture_id: int = -999
var _cache_state_id: int = -999
var _cache_override_ref


func _ready() -> void:
	_player = get_parent()
	_library = load("res://scripts/base_pose_library.gd").new()


func invalidate_cache() -> void:
	_composed_pose_cache = null
	_cache_posture_id = -999
	_cache_state_id = -999
	_cache_override_ref = null


func set_editor_base_pose_override(def) -> void:
	_editor_base_pose_override = def
	invalidate_cache()


func clear_editor_base_pose_override() -> void:
	_editor_base_pose_override = null
	invalidate_cache()


func set_editor_state_override(state_id: int) -> void:
	_editor_state_override = state_id
	invalidate_cache()


func clear_editor_state_override() -> void:
	_editor_state_override = -1
	invalidate_cache()


func get_base_pose_def():
	if _editor_base_pose_override != null:
		return _editor_base_pose_override
	var state_id: int = _editor_state_override if _editor_state_override >= 0 else base_pose_state
	return _library.get_def(state_id)


func compose_runtime_posture(def_override = null):
	if _player == null:
		return def_override

	var stroke_def = def_override
	if stroke_def == null:
		stroke_def = load("res://scripts/posture_library.gd").new().get_def(_player.paddle_posture)
	if stroke_def == null:
		return def_override

	var state_id: int = _editor_state_override if _editor_state_override >= 0 else base_pose_state
	if def_override == null and _composed_pose_cache != null \
		and _cache_posture_id == stroke_def.posture_id \
		and _cache_state_id == state_id:
		return _composed_pose_cache

	var base_def = get_base_pose_def()
	if base_def == null:
		return stroke_def

	var composed = base_def.blend_onto_stroke(stroke_def)
	if def_override == null:
		_composed_pose_cache = composed
		_cache_posture_id = stroke_def.posture_id
		_cache_state_id = state_id
		_cache_override_ref = null
	return composed


func compose_preview_posture(base_def, stroke_posture_id: int):
	var stroke_def = load("res://scripts/posture_library.gd").new().get_def(stroke_posture_id)
	if stroke_def == null:
		stroke_def = load("res://scripts/posture_library.gd").new().get_def(_player.PaddlePosture.READY)
	if stroke_def == null or base_def == null:
		return stroke_def
	return base_def.to_preview_posture(stroke_def)


func update_runtime_pose_state(delta: float) -> void:
	if _player == null:
		return

	var speed: float = Vector3(_player.current_velocity.x, 0.0, _player.current_velocity.z).length()
	var commit_stage: int = _player.posture._last_commit_stage if _player.posture else -1
	var ball = _player._get_ball_ref()

	if _prev_is_jumping and not _player.is_jumping:
		var landing_def = _library.get_def(_player.BasePoseState.LANDING_RECOVERY)
		landing_recovery_timer = maxf(
			landing_recovery_timer,
			landing_def.landing_lockout_time if landing_def else LANDING_RECOVERY_FALLBACK
		)
		decel_timer = maxf(decel_timer, DECEL_PLANT_FALLBACK)
	if not _prev_is_jumping and _player.is_jumping:
		var takeoff_def = _library.get_def(_player.BasePoseState.JUMP_TAKEOFF)
		jump_takeoff_timer = maxf(
			jump_takeoff_timer,
			takeoff_def.jump_window * 0.5 if takeoff_def else JUMP_TAKEOFF_FALLBACK
		)
	if commit_stage >= 1 and commit_stage != _prev_commit_stage and not _player.is_jumping:
		if ball == null or not ball.ball_bounced_since_last_hit:
			var split_def = _library.get_def(_player.BasePoseState.SPLIT_STEP)
			split_step_timer = maxf(
				split_step_timer,
				split_def.recovery_time if split_def else SPLIT_STEP_FALLBACK
			)
	if _prev_speed - speed > DECEL_TRIGGER_SPEED_DELTA:
		decel_timer = maxf(decel_timer, DECEL_PLANT_FALLBACK)

	landing_recovery_timer = maxf(landing_recovery_timer - delta, 0.0)
	lunge_recovery_timer = maxf(lunge_recovery_timer - delta, 0.0)
	split_step_timer = maxf(split_step_timer - delta, 0.0)
	jump_takeoff_timer = maxf(jump_takeoff_timer - delta, 0.0)
	decel_timer = maxf(decel_timer - delta, 0.0)

	var context = _resolve_live_context()
	last_contact_context = context
	var was_lunge: bool = base_pose_state in [
		_player.BasePoseState.FOREHAND_LUNGE,
		_player.BasePoseState.BACKHAND_LUNGE,
		_player.BasePoseState.LOW_SCOOP_LUNGE,
	]
	var new_intent: int = int(context.get("intent", _player.PoseIntent.NEUTRAL))
	var new_state: int = _resolve_base_pose_state(context, speed)
	if was_lunge and new_state not in [
		_player.BasePoseState.FOREHAND_LUNGE,
		_player.BasePoseState.BACKHAND_LUNGE,
		_player.BasePoseState.LOW_SCOOP_LUNGE,
	]:
		var recovery_def = _library.get_def(_player.BasePoseState.RECOVERY_READY)
		lunge_recovery_timer = maxf(
			lunge_recovery_timer,
			recovery_def.recovery_time if recovery_def else LUNGE_RECOVERY_FALLBACK
		)

	if base_pose_state != new_state or pose_intent != new_intent:
		base_pose_state = new_state
		pose_intent = new_intent
		invalidate_cache()

	_prev_is_jumping = _player.is_jumping
	_prev_speed = speed
	_prev_commit_stage = commit_stage


func describe_contact_intent(hit_h: float, player_z_abs: float, pre_bounce: bool) -> Dictionary:
	if pre_bounce:
		if hit_h >= PickleballConstants.HIGH_OVERHEAD_TRIGGER_HEIGHT:
			return {
				"intent": _player.PoseIntent.OVERHEAD_SMASH,
				"label": "SMASH",
				"dot_color": Color(1.0, 0.15, 0.10, 1.0),
				"label_color": Color(1.0, 0.22, 0.02, 1.0),
				"scale": 1.65,
				"energy": 1.6,
			}
		if hit_h >= PickleballConstants.MEDIUM_OVERHEAD_TRIGGER_HEIGHT:
			return {
				"intent": _player.PoseIntent.OVERHEAD_SMASH,
				"label": "SEMI-SMASH",
				"dot_color": Color(1.0, 0.55, 0.05, 1.0),
				"label_color": Color(1.0, 0.65, 0.10, 1.0),
				"scale": 1.25,
				"energy": 1.3,
			}
		var near_kitchen: bool = player_z_abs < PickleballConstants.NON_VOLLEY_ZONE + 0.6
		if hit_h < 0.45 and near_kitchen:
			return {
				"intent": _player.PoseIntent.DINK_VOLLEY,
				"label": "DINK VOLLEY",
				"dot_color": Color(0.95, 0.90, 0.20, 1.0),
				"label_color": Color(1.0, 1.0, 0.35, 1.0),
				"scale": 0.95,
				"energy": 1.0,
			}
		if near_kitchen:
			return {
				"intent": _player.PoseIntent.PUNCH_VOLLEY,
				"label": "PUNCH VOLLEY",
				"dot_color": Color(1.0, 0.78, 0.15, 1.0),
				"label_color": Color(1.0, 0.85, 0.22, 1.0),
				"scale": 1.05,
				"energy": 1.1,
			}
		return {
			"intent": _player.PoseIntent.DEEP_VOLLEY,
			"label": "DEEP VOLLEY",
			"dot_color": Color(1.0, 0.70, 0.15, 1.0),
			"label_color": Color(1.0, 0.78, 0.20, 1.0),
			"scale": 1.0,
			"energy": 1.0,
		}

	var near_kitchen_post: bool = player_z_abs < PickleballConstants.NON_VOLLEY_ZONE + 0.6
	var at_baseline: bool = player_z_abs > PickleballConstants.NON_VOLLEY_ZONE + 2.6
	if hit_h < 0.40 and near_kitchen_post:
		return {
			"intent": _player.PoseIntent.DINK,
			"label": "DINK",
			"dot_color": Color(0.30, 1.00, 0.85, 1.0),
			"label_color": Color(0.45, 1.00, 0.90, 1.0),
			"scale": 0.90,
			"energy": 1.0,
		}
	if hit_h < 0.45:
		return {
			"intent": _player.PoseIntent.DROP_RESET,
			"label": "DROP / RESET",
			"dot_color": Color(0.40, 0.95, 1.00, 1.0),
			"label_color": Color(0.55, 1.00, 1.00, 1.0),
			"scale": 0.95,
			"energy": 1.0,
		}
	if hit_h > 1.10:
		return {
			"intent": _player.PoseIntent.LOB_DEFENSE,
			"label": "LOB RETURN",
			"dot_color": Color(0.70, 0.55, 1.00, 1.0),
			"label_color": Color(0.80, 0.65, 1.00, 1.0),
			"scale": 1.10,
			"energy": 1.15,
		}
	if at_baseline or hit_h >= 0.70:
		return {
			"intent": _player.PoseIntent.GROUNDSTROKE,
			"label": "GROUNDSTROKE",
			"dot_color": Color(0.20, 0.90, 1.00, 1.0),
			"label_color": Color(0.35, 0.95, 1.00, 1.0),
			"scale": 1.10,
			"energy": 1.15,
		}
	return {
		"intent": _player.PoseIntent.DROP_RESET,
		"label": "RESET RETURN",
		"dot_color": Color(0.30, 0.85, 1.00, 1.0),
		"label_color": Color(0.45, 0.92, 1.00, 1.0),
		"scale": 1.0,
		"energy": 1.0,
	}


func _resolve_live_context() -> Dictionary:
	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	var vel_flat: Vector3 = Vector3(_player.current_velocity.x, 0.0, _player.current_velocity.z)
	var contact_point: Vector3 = _player.global_position + forward_axis * 0.8 + Vector3.UP * 0.6
	var pre_bounce: bool = true
	var has_contact_hint: bool = false

	var ball = _player._get_ball_ref()
	if ball != null:
		pre_bounce = not ball.ball_bounced_since_last_hit
		contact_point = ball.global_position
		has_contact_hint = true

	if _player.is_ai and _player.ai_brain and _player.ai_brain.ai_predicted_contact_position != Vector3.ZERO:
		contact_point = _player.ai_brain.ai_predicted_contact_position
		has_contact_hint = true
	elif _player.debug_visual:
		if not _player.debug_visual.human_committed_pre_intercepts.is_empty():
			contact_point = _player.debug_visual.human_committed_pre_intercepts.back()
			pre_bounce = true
			has_contact_hint = true
		elif not _player.debug_visual.human_committed_post_intercepts.is_empty():
			contact_point = _player.debug_visual.human_committed_post_intercepts[0]
			pre_bounce = false
			has_contact_hint = true

	if _player.posture and _player.posture._committed_incoming_posture >= 0 \
		and _player.posture._contact_point_local != Vector3.ZERO:
		contact_point = _player.global_position + _player.posture._contact_point_local
		has_contact_hint = true

	if not has_contact_hint:
		var player_z_abs_idle: float = absf(_player.global_position.z)
		return {
			"intent": _player.PoseIntent.NEUTRAL,
			"pre_bounce": true,
			"contact_point": contact_point,
			"hit_height": 0.0,
			"player_z_abs": player_z_abs_idle,
			"near_kitchen": player_z_abs_idle < PickleballConstants.NON_VOLLEY_ZONE + 0.6,
			"at_baseline": player_z_abs_idle > PickleballConstants.NON_VOLLEY_ZONE + 2.6,
			"lateral_reach": 0.0,
			"forward_reach": 0.0,
			"forward_dot": vel_flat.dot(forward_axis),
			"lateral_dot": vel_flat.dot(forehand_axis),
			"speed": vel_flat.length(),
			"is_lunge": false,
		}

	var player_z_abs: float = absf(_player.global_position.z)
	var hit_h: float = maxf(0.0, contact_point.y - _player.ground_y)
	var lateral_reach: float = (contact_point - _player.global_position).dot(forehand_axis)
	var forward_reach: float = (contact_point - _player.global_position).dot(forward_axis)
	var intent_desc = describe_contact_intent(hit_h, player_z_abs, pre_bounce)
	var speed: float = vel_flat.length()
	return {
		"intent": intent_desc["intent"],
		"pre_bounce": pre_bounce,
		"contact_point": contact_point,
		"hit_height": hit_h,
		"player_z_abs": player_z_abs,
		"near_kitchen": player_z_abs < PickleballConstants.NON_VOLLEY_ZONE + 0.6,
		"at_baseline": player_z_abs > PickleballConstants.NON_VOLLEY_ZONE + 2.6,
		"lateral_reach": lateral_reach,
		"forward_reach": forward_reach,
		"forward_dot": vel_flat.dot(forward_axis),
		"lateral_dot": vel_flat.dot(forehand_axis),
		"speed": speed,
		"is_lunge": absf(lateral_reach) >= LUNGE_LATERAL_THRESHOLD,
	}


func _resolve_base_pose_state(context: Dictionary, speed: float) -> int:
	var intent: int = int(context.get("intent", _player.PoseIntent.NEUTRAL))
	var hit_height: float = float(context.get("hit_height", 0.0))
	var lateral_reach: float = float(context.get("lateral_reach", 0.0))
	var forward_dot: float = float(context.get("forward_dot", 0.0))
	var lateral_dot: float = float(context.get("lateral_dot", 0.0))
	var near_kitchen: bool = bool(context.get("near_kitchen", false))
	var is_lunge: bool = bool(context.get("is_lunge", false))

	if landing_recovery_timer > 0.0:
		return _player.BasePoseState.LANDING_RECOVERY

	if _player.is_jumping:
		if jump_takeoff_timer > 0.0:
			return _player.BasePoseState.JUMP_TAKEOFF
		return _player.BasePoseState.AIR_SMASH if intent == _player.PoseIntent.OVERHEAD_SMASH else _player.BasePoseState.JUMP_TAKEOFF

	if intent == _player.PoseIntent.OVERHEAD_SMASH:
		return _player.BasePoseState.OVERHEAD_PREP

	if is_lunge:
		if hit_height <= LOW_SCOOP_HEIGHT:
			return _player.BasePoseState.LOW_SCOOP_LUNGE
		return _player.BasePoseState.FOREHAND_LUNGE if lateral_reach >= 0.0 else _player.BasePoseState.BACKHAND_LUNGE

	if split_step_timer > 0.0 and bool(context.get("pre_bounce", true)):
		return _player.BasePoseState.SPLIT_STEP

	if decel_timer > 0.0 and speed > 0.4:
		return _player.BasePoseState.DECEL_PLANT

	if speed >= RUN_SPEED_THRESHOLD:
		if forward_dot < -0.75:
			return _player.BasePoseState.BACKPEDAL
		if absf(lateral_dot) > absf(forward_dot) * 1.15:
			return _player.BasePoseState.LATERAL_SHUFFLE
		return _player.BasePoseState.CROSSOVER_RUN
	elif speed >= SHUFFLE_SPEED_THRESHOLD and absf(lateral_dot) > absf(forward_dot):
		return _player.BasePoseState.LATERAL_SHUFFLE

	if lunge_recovery_timer > 0.0:
		return _player.BasePoseState.RECOVERY_READY

	match intent:
		_player.PoseIntent.DINK:
			return _player.BasePoseState.DINK_BASE
		_player.PoseIntent.DROP_RESET:
			return _player.BasePoseState.DROP_RESET_BASE
		_player.PoseIntent.PUNCH_VOLLEY:
			return _player.BasePoseState.PUNCH_VOLLEY_READY
		_player.PoseIntent.DINK_VOLLEY:
			return _player.BasePoseState.DINK_VOLLEY_READY
		_player.PoseIntent.DEEP_VOLLEY:
			return _player.BasePoseState.DEEP_VOLLEY_READY
		_player.PoseIntent.GROUNDSTROKE:
			return _player.BasePoseState.GROUNDSTROKE_BASE
		_player.PoseIntent.LOB_DEFENSE:
			return _player.BasePoseState.LOB_DEFENSE_BASE
		_:
			return _player.BasePoseState.KITCHEN_NEUTRAL if near_kitchen else _player.BasePoseState.ATHLETIC_READY
