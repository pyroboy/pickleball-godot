class_name PostureSkeletonApplier extends RefCounted

## World-space offset from forehand (X), up (Y), forward (Z) components — matches editor / foot metadata.
static func stance_offset(v: Vector3, forehand_axis: Vector3, forward_axis: Vector3) -> Vector3:
	return forehand_axis * v.x + Vector3.UP * v.y + forward_axis * v.z


## Applies PostureDefinition full-body fields to the player skeleton.
##
## Phase 3 wiring: connects feet, knees, elbows, head, torso fields from
## PostureDefinition to actual Skeleton3D bone poses.
##
## Usage:
##   var applier := PostureSkeletonApplier.new(player)
##   applier.apply(posture_definition)

var _player: PlayerController

func _init(player: PlayerController) -> void:
	_player = player


## Apply full-body posture fields to the skeleton.
func apply(def: PostureDefinition) -> void:
	if not _player.skeleton:
		return
	if _player.skeleton_bones.is_empty():
		return

	_apply_head(def)
	_apply_torso(def)
	_apply_arms(def)
	_apply_legs(def)


func _apply_head(def: PostureDefinition) -> void:
	var head_idx: int = _player.skeleton_bones.get("head", -1)
	var _neck_idx: int = _player.skeleton_bones.get("neck", -1)
	if head_idx < 0:
		return

	# Head yaw/pitch from posture definition
	var yaw: float = def.head_yaw_deg
	var pitch: float = def.head_pitch_deg

	var rot := Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)
	_set_bone_rotation("head", rot)


func _apply_torso(def: PostureDefinition) -> void:
	# Hip yaw (coil/uncoil)
	var hip_yaw: float = def.hip_yaw_deg
	_set_bone_rotation("hips", Vector3(0.0, deg_to_rad(hip_yaw), 0.0))

	# Spine curve
	var spine_pitch: float = def.spine_curve_deg
	_set_bone_rotation("spine", Vector3(deg_to_rad(spine_pitch), 0.0, 0.0))

	# Chest/torso orientation
	var torso_yaw: float = def.torso_yaw_deg
	var torso_pitch: float = def.torso_pitch_deg
	var torso_roll: float = def.torso_roll_deg
	_set_bone_rotation("chest", Vector3(
		deg_to_rad(torso_pitch),
		deg_to_rad(torso_yaw),
		deg_to_rad(torso_roll)
	))


func _apply_arms(def: PostureDefinition) -> void:
	# Right arm pole target (for IK)
	# Note: Actual IK solving happens in PlayerArmIK, this just sets bone hints
	var r_pole := def.right_elbow_pole
	if r_pole != Vector3.ZERO:
		# Store as metadata for IK to read
		_player.set_meta("right_elbow_pole", r_pole)

	# Right shoulder rotation offset
	var r_shoulder_rot := def.right_shoulder_rotation_deg
	if r_shoulder_rot != Vector3.ZERO:
		_set_bone_rotation("right_shoulder", Vector3(
			deg_to_rad(r_shoulder_rot.x),
			deg_to_rad(r_shoulder_rot.y),
			deg_to_rad(r_shoulder_rot.z)
		))

	# Left arm
	var l_pole := def.left_elbow_pole
	if l_pole != Vector3.ZERO:
		_player.set_meta("left_elbow_pole", l_pole)

	var l_shoulder_rot := def.left_shoulder_rotation_deg
	if l_shoulder_rot != Vector3.ZERO:
		_set_bone_rotation("left_shoulder", Vector3(
			deg_to_rad(l_shoulder_rot.x),
			deg_to_rad(l_shoulder_rot.y),
			deg_to_rad(l_shoulder_rot.z)
		))


func _apply_legs(def: PostureDefinition) -> void:
	# Stance width affects foot positions (handled by leg IK target positions)
	# We store the target foot offsets for the leg IK system to read
	var stance: float = def.stance_width
	var r_foot_offset: Vector3 = def.right_foot_offset
	var l_foot_offset: Vector3 = def.left_foot_offset

	if r_foot_offset != Vector3.ZERO or stance > 0.0:
		var r_target := _compute_foot_target(true, stance, r_foot_offset)
		_player.set_meta("right_foot_target", r_target)

	if l_foot_offset != Vector3.ZERO or stance > 0.0:
		var l_target := _compute_foot_target(false, stance, l_foot_offset)
		_player.set_meta("left_foot_target", l_target)

	# Knee pole targets
	var r_knee_pole := def.right_knee_pole
	if r_knee_pole != Vector3.ZERO:
		_player.set_meta("right_knee_pole", r_knee_pole)

	var l_knee_pole := def.left_knee_pole
	if l_knee_pole != Vector3.ZERO:
		_player.set_meta("left_knee_pole", l_knee_pole)


func _compute_foot_target(is_right: bool, stance_width: float, offset: Vector3) -> Vector3:
	var side := 1.0 if is_right else -1.0
	var forehand_axis := _player._get_forehand_axis()
	var forward_axis := _player._get_forward_axis()

	# Base stance position
	var base_pos := forehand_axis * side * stance_width * 0.5
	return base_pos + stance_offset(offset, forehand_axis, forward_axis)


func _set_bone_rotation(bone_name: String, euler_rad: Vector3) -> void:
	var idx: int = _player.skeleton_bones.get(bone_name, -1)
	if idx < 0 or not _player.skeleton:
		return

	var basis := Basis.from_euler(euler_rad)
	var rest: Transform3D = _player.skeleton.get_bone_rest(idx)
	var pose := Transform3D(basis, rest.origin)
	_player.skeleton.set_bone_pose(idx, pose)
