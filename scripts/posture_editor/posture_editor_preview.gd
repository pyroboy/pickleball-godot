## Manages pose trigger, transition player, and preview definition building.

var _pose_trigger = null
var _transition_player = null

## Injected
var _player: Node3D
var _library
var _base_pose_library
var _state  # PostureEditorState ref

const READY_POSTURE_ID := 20
const CHARGE_FOREHAND_POSTURE_ID := 8
const CHARGE_BACKHAND_POSTURE_ID := 9

func init(player: Node3D, library, base_pose_library, state) -> void:
	_player = player
	_library = library
	_base_pose_library = base_pose_library
	_state = state

func setup_transition_player() -> void:
	if not _player or not _state.get_current_def() or _state.is_base_pose_mode():
		return
	
	if not _transition_player:
		_transition_player = load("res://scripts/posture_editor/transition_player.gd").new()
		# Parent will add as child
	
	var ready_def = _contextualize_posture_for_preview(_library.get_def(READY_POSTURE_ID))
	var charge_def = _contextualize_posture_for_preview(_build_charge_preview_def(_state.get_current_def()))
	var contact_def = _contextualize_posture_for_preview(_state.get_current_def())
	var ft_defs = _build_follow_through_preview_defs(_state.get_current_def())
	var preview_ft_defs = []
	for ft_def in ft_defs:
		preview_ft_defs.append(_contextualize_posture_for_preview(ft_def))
	_transition_player.setup(_player, ready_def, charge_def, contact_def, preview_ft_defs)

func get_transition_player():
	return _transition_player

func set_transition_player(player) -> void:
	_transition_player = player

func on_play_transition() -> void:
	if _state.is_base_pose_mode():
		return
	if not _transition_player:
		setup_transition_player()
	elif _state.get_current_def():
		setup_transition_player()
	
	if not _transition_player:
		return
	
	if _transition_player.is_playing():
		_transition_player.pause()
	else:
		if not _state.get_current_def():
			return
		_capture_live_restore_posture()
		if _pose_trigger and _pose_trigger.is_frozen():
			_pose_trigger.release_pose()
		_transition_player.play()

func build_preview_posture_for_editor():
	if not _player:
		return null
	if _state.is_base_pose_mode():
		if _state.get_current_base_def() == null or not _player.pose_controller:
			return null
		return _player.pose_controller.compose_preview_posture(_state.get_current_base_def(), _preview_context_stroke_posture_id())
	if _state.get_current_def() == null:
		return null
	return _contextualize_posture_for_preview(_state.get_current_def())

func _contextualize_posture_for_preview(def):
	if def == null:
		return null
	var base_def = _preview_context_base_pose_def()
	if base_def == null:
		return def
	return base_def.to_preview_posture(def)

func _preview_context_base_pose_id() -> int:
	if not _player:
		return -1
	var preview_idx: int = 0
	# preview context option is managed by shell
	match preview_idx:
		1: return _player.BasePoseState.ATHLETIC_READY
		2: return _player.BasePoseState.SPLIT_STEP
		3: return _player.BasePoseState.PUNCH_VOLLEY_READY
		4: return _player.BasePoseState.GROUNDSTROKE_BASE
		5:
			var def = _state.get_current_def()
			if def and def.height_tier == 0:
				return _player.BasePoseState.LOW_SCOOP_LUNGE
			if def and def.family == 1:
				return _player.BasePoseState.BACKHAND_LUNGE
			return _player.BasePoseState.FOREHAND_LUNGE
		6: return _player.BasePoseState.JUMP_TAKEOFF
		7: return _player.BasePoseState.LANDING_RECOVERY
		_: return -1

func _preview_context_stroke_posture_id() -> int:
	if not _player:
		return READY_POSTURE_ID
	var preview_idx: int = 0  # managed by shell
	match preview_idx:
		1: return READY_POSTURE_ID
		2: return READY_POSTURE_ID
		3: return _player.PaddlePosture.VOLLEY_READY
		4: return _player.PaddlePosture.FORWARD
		5:
			var def = _state.get_current_def()
			if def and def.family == 1:
				return _player.PaddlePosture.WIDE_BACKHAND
			if def and def.height_tier == 0:
				return _player.PaddlePosture.LOW_WIDE_FOREHAND
			return _player.PaddlePosture.WIDE_FOREHAND
		6: return _player.PaddlePosture.HIGH_OVERHEAD
		7: return READY_POSTURE_ID
		_: return _state.get_current_def().posture_id if _state.get_current_def() else READY_POSTURE_ID

func _preview_context_base_pose_def():
	if not _player:
		return null
	var base_pose_id := _preview_context_base_pose_id()
	if base_pose_id < 0:
		return null
	return _base_pose_library.get_def(base_pose_id)

func _build_charge_preview_def(def):
	if def == null:
		return null
	if def.family == 0:
		var fh_charge = _library.get_def(CHARGE_FOREHAND_POSTURE_ID)
		if fh_charge != null:
			return fh_charge
	elif def.family == 1:
		var bh_charge = _library.get_def(CHARGE_BACKHAND_POSTURE_ID)
		if bh_charge != null:
			return bh_charge

	var preview = _copy_definition(def)
	if preview == null:
		return null
	preview.display_name = "%s Charge Preview" % def.display_name
	preview.paddle_forehand_mul += def.charge_paddle_offset.x
	preview.paddle_y_offset += def.charge_paddle_offset.y
	preview.paddle_forward_mul += def.charge_paddle_offset.z
	preview.paddle_pitch_base_deg += def.charge_paddle_rotation_deg.x
	preview.paddle_yaw_base_deg += def.charge_paddle_rotation_deg.y
	preview.paddle_roll_base_deg += def.charge_paddle_rotation_deg.z
	preview.body_yaw_deg += def.charge_body_rotation_deg
	preview.hip_yaw_deg += def.charge_hip_coil_deg
	return preview

func _build_follow_through_preview_defs(def):
	var results = []
	if def == null:
		return results

	var follow = _copy_definition(def)
	if follow == null:
		return results

	follow.display_name = "%s Follow-Through" % def.display_name
	follow.paddle_forehand_mul += def.ft_paddle_offset.x
	follow.paddle_y_offset += def.ft_paddle_offset.y
	follow.paddle_forward_mul += def.ft_paddle_offset.z
	follow.paddle_pitch_base_deg += def.ft_paddle_rotation_deg.x
	follow.paddle_yaw_base_deg += def.ft_paddle_rotation_deg.y
	follow.paddle_roll_base_deg += def.ft_paddle_rotation_deg.z
	follow.hip_yaw_deg += def.ft_hip_uncoil_deg
	results.append(follow)
	return results

func _copy_definition(def):
	if def == null:
		return null
	return def.lerp_with(def, 0.0)

func _capture_live_restore_posture() -> void:
	if _state == null or _state.get_editor_restore_posture_id() >= 0:
		return
	if _player and _player.posture:
		_state.set_editor_restore_posture_id(_player.posture.paddle_posture)

func restore_live_posture_from_editor() -> void:
	if _state == null or _state.get_editor_restore_posture_id() < 0 or not _player:
		return
	_player.paddle_posture = _state.get_editor_restore_posture_id()

func get_pose_trigger():
	return _pose_trigger

func set_preview_context_option_idx(_idx: int) -> void:
	# Stored in shell but needed here for context computation
	pass

func refresh_pose_trigger(preview_def) -> void:
	if _pose_trigger and _pose_trigger.is_frozen():
		_pose_trigger.refresh_from_definition(preview_def)
