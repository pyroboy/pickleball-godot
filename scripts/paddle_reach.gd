class_name PaddleReach extends RefCounted
const FloorGeometry = preload("res://scripts/paddle_floor_geometry.gd")
const PaddleDimensions = preload("res://scripts/paddle_dimensions.gd")



const MAX_HEAD_DISTANCE: = 1.35

static func head_world(player) -> Vector3:
	if player == null or player.paddle_node == null:
		return Vector3.ZERO
	return player.paddle_node.global_position + player.paddle_node.global_transform.basis.y * PaddleDimensions.HEAD_CENTER_Y

static func shoulder_world(player) -> Vector3:
	var arm = player.right_arm_node if player != null and "right_arm_node" in player else null
	if player != null and "paddle_posture" in player:
		var def = PostureLibrary.instance().get_def(player.paddle_posture)
		if "posture" in player and player.posture and player.posture.transition_pose_blend:
			def = player.posture.transition_pose_blend
		if def and def.paddle_hand == 1 and "left_arm_node" in player:
			arm = player.left_arm_node
	if arm != null:
		var pivot: Node3D = arm.get_node_or_null("UpperArmPivot")
		if pivot != null:
			return pivot.global_position
	return player.global_position + player._get_forehand_axis() * 0.18 + Vector3.UP * 0.15

static func clamp_head_world(head: Vector3, shoulder: Vector3) -> Vector3:
	var delta: = head - shoulder
	if delta.length_squared() <= MAX_HEAD_DISTANCE * MAX_HEAD_DISTANCE:
		return head
	return shoulder + delta.normalized() * MAX_HEAD_DISTANCE

static func clamp_head_with_floor(head: Vector3, shoulder: Vector3, floor_y: float) -> Vector3:
	var limited: Vector3 = clamp_head_world(head, shoulder)
	if limited.y >= floor_y:
		return limited
	limited.y = floor_y
	var vertical: float = floor_y - shoulder.y
	var horizontal_radius: float = sqrt(maxf(0.0, MAX_HEAD_DISTANCE * MAX_HEAD_DISTANCE - vertical * vertical))
	var horizontal: = Vector2(limited.x - shoulder.x, limited.z - shoulder.z)
	if horizontal.length() > horizontal_radius:
		horizontal = horizontal.normalized() * horizontal_radius
		limited.x = shoulder.x + horizontal.x
		limited.z = shoulder.z + horizontal.y
	return limited

static func clamp_for_player(player, head: Vector3) -> Vector3:
	return clamp_head_world(head, target_shoulder_world(player))

## Translation caps the body against a fixed paddle target, so later runtime
## reach refreshes must use that target's original shoulder reference as well.
static func target_shoulder_world(player) -> Vector3:
	if player != null and "posture" in player and player.posture != null:
		var pose = player.posture.transition_pose_blend
		if pose == null and "paddle_posture" in player: pose = PostureLibrary.instance().get_def(player.paddle_posture)
		if pose != null and pose.body_position_offset != Vector3.ZERO:
			return load("res://scripts/stroke_body_pose.gd").shoulder_world(player, pose, null, false)
	return shoulder_world(player)

static func clamp_paddle_for_player(player) -> bool:
	if player == null or player.paddle_node == null:
		return false
	var head_offset: Vector3 = player.paddle_node.global_transform.basis.y * PaddleDimensions.HEAD_CENTER_Y
	var head: Vector3 = player.paddle_node.global_position + head_offset
	var clearance: float = 0.06
	var def = PostureLibrary.instance().get_def(player.paddle_posture)
	if "posture" in player and player.posture != null and player.posture.transition_pose_blend != null:
		var runtime: PostureDefinition = player.posture.transition_pose_blend
		if runtime.height_tier == 0 and runtime.paddle_floor_clearance < 0.3: def = runtime
	if def != null:
		clearance = FloorGeometry.clearance(def, player.paddle_node.global_transform.basis)
	var limited: Vector3 = clamp_head_with_floor(head, target_shoulder_world(player), player.COURT_FLOOR_Y + clearance)
	if head.distance_squared_to(limited) < 1e-06:
		return false
	player.paddle_node.global_position = limited - head_offset
	return true
