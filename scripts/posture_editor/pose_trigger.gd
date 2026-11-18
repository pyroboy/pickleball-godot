class_name PoseTrigger extends RefCounted



const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
var _player
var _original_time_scale: float = 1.0
var _is_frozen: bool = false
var _target_posture_id: int = -1

var _is_blending: bool = false
var _blend_start_time: int = 0
var _blend_duration_ms: int = 300

var _start_bones: Dictionary = {}
var _target_bones: Dictionary = {}
var _start_paddle_pos: Vector3
var _start_paddle_rot: Vector3
var _target_paddle_pos: Vector3
var _target_paddle_rot: Vector3


var _start_body_pivot_rot: Vector3
var _target_body_pivot_rot: Vector3

signal pose_triggered(posture_id: int)
signal pose_released()

func _init(player) -> void :
	_player = player


func trigger_pose(posture_def) -> void :
	if not _player or not posture_def:
		return

	if not _is_frozen:
		_original_time_scale = Engine.time_scale
		Engine.time_scale = 0.0
		_is_frozen = true

	_is_blending = true
	_blend_start_time = Time.get_ticks_msec()


	_start_paddle_pos = _player.paddle_node.position
	_start_paddle_rot = _player.paddle_node.rotation_degrees
	_start_bones = _capture_current_bones()


	if _player.body_pivot:
		_start_body_pivot_rot = _player.body_pivot.rotation_degrees


	_player.paddle_posture = posture_def.posture_id
	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	var swing_sign: float = _player._get_swing_sign()
	var fwd_sign: float = forward_axis.z

	var head_pos = posture_def.resolve_paddle_offset(forehand_axis, forward_axis)
	var paddle_rot = posture_def.resolve_paddle_rotation_deg(swing_sign, fwd_sign)

	var b: = _get_basis_from_rotation(paddle_rot)

	_target_paddle_pos = head_pos - b.y * PaddleSize.HEAD_CENTER_Y
	_target_paddle_rot = paddle_rot
	_target_bones = _calculate_target_bones(posture_def)
	_target_posture_id = posture_def.posture_id


	_target_body_pivot_rot = Vector3(
		posture_def.body_pitch_deg, 
		posture_def.body_yaw_deg * swing_sign, 
		posture_def.body_roll_deg
	)

	pose_triggered.emit(posture_def.posture_id)



func refresh_from_definition(posture_def) -> void :
	if not _player or not posture_def:
		return



	if _player.posture:
		_player.posture.transition_pose_blend = null if not _is_frozen else posture_def
	var forward_axis: Vector3 = _player._get_forward_axis()
	var forehand_axis: Vector3 = _player._get_forehand_axis()
	var swing_sign: float = _player._get_swing_sign()
	var fwd_sign: float = forward_axis.z
	var head_pos = posture_def.resolve_paddle_offset(forehand_axis, forward_axis)
	var paddle_rot = posture_def.resolve_paddle_rotation_deg(swing_sign, fwd_sign)

	var b: = _get_basis_from_rotation(paddle_rot)

	_target_paddle_pos = head_pos - b.y * PaddleSize.HEAD_CENTER_Y
	_target_paddle_rot = paddle_rot
	_target_bones = _calculate_target_bones(posture_def)
	_target_body_pivot_rot = Vector3(
		posture_def.body_pitch_deg, 
		posture_def.body_yaw_deg * swing_sign, 
		posture_def.body_roll_deg
	)
	_target_posture_id = posture_def.posture_id
	_is_blending = false
	_player.posture.force_posture_update(posture_def)
	if _is_frozen:
		_apply_blended_state(1.0)

func update() -> void :
	if not _is_blending:
		return

	var now: = Time.get_ticks_msec()
	var elapsed: = now - _blend_start_time

	if elapsed >= _blend_duration_ms:
		_is_blending = false
		_apply_blended_state(1.0)
	else:
		var weight: = float(elapsed) / float(_blend_duration_ms)
		weight = sin(weight * PI * 0.5)
		_apply_blended_state(weight)

func _apply_blended_state(weight: float) -> void :
	if not _player or not _player.paddle_node:
		return


	_player.paddle_node.position = _start_paddle_pos.lerp(_target_paddle_pos, weight)
	_player.paddle_node.rotation_degrees = Vector3.ZERO
	var blended_rot: Vector3 = _start_paddle_rot.lerp(_target_paddle_rot, weight)
	_player.paddle_node.rotate_object_local(Vector3.RIGHT, deg_to_rad(blended_rot.x))
	_player.paddle_node.rotate_object_local(Vector3.UP, deg_to_rad(blended_rot.y))
	_player.paddle_node.rotate_object_local(Vector3.FORWARD, deg_to_rad(blended_rot.z))


	if _player.body_pivot:
		var blended_body_rot: Vector3 = _start_body_pivot_rot.lerp(_target_body_pivot_rot, weight)
		_player.body_pivot.rotation_degrees = blended_body_rot


	if not _player.skeleton: return
	for b_name in _start_bones:
		if _target_bones.has(b_name):
			var idx: int = _player.skeleton_bones.get(b_name, -1)
			if idx >= 0:
				var q_start: Quaternion = _start_bones[b_name].basis.get_rotation_quaternion()
				var q_target: Quaternion = _target_bones[b_name].basis.get_rotation_quaternion()
				var q_blend: Quaternion = q_start.slerp(q_target, weight)
				var blended_transform: = Transform3D(Basis(q_blend), _start_bones[b_name].origin)
				_player.skeleton.set_bone_pose(idx, blended_transform)


func release_pose() -> void :
	if not _is_frozen:
		return

	Engine.time_scale = _original_time_scale
	_is_frozen = false


	if _target_posture_id >= 0:
		_player.paddle_posture = _target_posture_id


	if _player.posture:
		_player.posture._posture_lerp_pos = _target_paddle_pos
		_player.posture._posture_lerp_rot = _target_paddle_rot



		_player.posture._posture_lerp_initialized = false


	if _player.body_pivot:
		_player.body_pivot.rotation_degrees = _target_body_pivot_rot


	if _player.skeleton:
		for b_name in ["hips", "spine", "chest", "head", "right_shoulder", "left_shoulder"]:
			var idx: int = _player.skeleton_bones.get(b_name, -1)
			if idx >= 0:
				_player.skeleton.set_bone_pose(idx, _player.skeleton.get_bone_rest(idx))

	pose_released.emit()


func toggle_pose(posture_def) -> void :
	if _is_frozen:
		release_pose()
	else:
		trigger_pose(posture_def)

func is_frozen() -> bool:
	return _is_frozen

func _capture_current_bones() -> Dictionary:
	var result: Dictionary = {}
	if not _player.skeleton: return result
	for b_name in ["hips", "spine", "chest", "head", "right_shoulder", "left_shoulder"]:
		var idx: int = _player.skeleton_bones.get(b_name, -1)
		if idx >= 0:
			result[b_name] = _player.skeleton.get_bone_pose(idx)
	return result

func _calculate_target_bones(def) -> Dictionary:
	var result: Dictionary = {}
	if not _player.skeleton or _player.skeleton_bones.is_empty():
		return result

	var hip_idx: int = _player.skeleton_bones.get("hips", -1)
	if hip_idx >= 0:
		var hip_basis: = Basis.from_euler(Vector3(0, deg_to_rad(def.hip_yaw_deg), 0))
		result["hips"] = Transform3D(hip_basis, _player.skeleton.get_bone_rest(hip_idx).origin)

	var spine_idx: int = _player.skeleton_bones.get("spine", -1)
	if spine_idx >= 0:
		var spine_basis: = Basis.from_euler(Vector3(deg_to_rad(def.spine_curve_deg), 0, 0))
		result["spine"] = Transform3D(spine_basis, _player.skeleton.get_bone_rest(spine_idx).origin)

	var chest_idx: int = _player.skeleton_bones.get("chest", -1)
	if chest_idx >= 0:
		var chest_basis: = Basis.from_euler(Vector3(deg_to_rad(def.torso_pitch_deg), deg_to_rad(def.torso_yaw_deg), deg_to_rad(def.torso_roll_deg)))
		result["chest"] = Transform3D(chest_basis, _player.skeleton.get_bone_rest(chest_idx).origin)

	var head_idx: int = _player.skeleton_bones.get("head", -1)
	if head_idx >= 0:
		var head_basis: = Basis.from_euler(Vector3(deg_to_rad(def.head_pitch_deg), deg_to_rad(def.head_yaw_deg), 0))
		result["head"] = Transform3D(head_basis, _player.skeleton.get_bone_rest(head_idx).origin)

	var r_shoulder_idx: int = _player.skeleton_bones.get("right_shoulder", -1)
	if r_shoulder_idx >= 0:
		var r_shoulder_basis: = Basis.from_euler(def.right_shoulder_rotation_deg * PI / 180.0)
		result["right_shoulder"] = Transform3D(r_shoulder_basis, _player.skeleton.get_bone_rest(r_shoulder_idx).origin)

	var l_shoulder_idx: int = _player.skeleton_bones.get("left_shoulder", -1)
	if l_shoulder_idx >= 0:
		var l_shoulder_basis: = Basis.from_euler(def.left_shoulder_rotation_deg * PI / 180.0)
		result["left_shoulder"] = Transform3D(l_shoulder_basis, _player.skeleton.get_bone_rest(l_shoulder_idx).origin)

	return result

func _get_basis_from_rotation(rot_deg: Vector3) -> Basis:

	var b: = Basis()
	b = b * Basis(Vector3.RIGHT, deg_to_rad(rot_deg.x))
	b = b * Basis(Vector3.UP, deg_to_rad(rot_deg.y))
	b = b * Basis(Vector3.FORWARD, deg_to_rad(rot_deg.z))
	return b
