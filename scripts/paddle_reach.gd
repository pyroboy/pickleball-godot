class_name PaddleReach extends RefCounted

## The arm has 0.35 m upper and lower segments. Paddle length plus torso lean
## gives a practical maximum head reach of 1.35 m from the shoulder.
const MAX_HEAD_DISTANCE := 1.35

static func head_world(player) -> Vector3:
	if player == null or player.paddle_node == null:
		return Vector3.ZERO
	return player.paddle_node.global_position + player.paddle_node.global_transform.basis.y * 0.4

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
	var delta := head - shoulder
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
	var horizontal := Vector2(limited.x - shoulder.x, limited.z - shoulder.z)
	if horizontal.length() > horizontal_radius:
		horizontal = horizontal.normalized() * horizontal_radius
		limited.x = shoulder.x + horizontal.x
		limited.z = shoulder.z + horizontal.y
	return limited

static func clamp_for_player(player, head: Vector3) -> Vector3:
	return clamp_head_world(head, shoulder_world(player))

static func clamp_paddle_for_player(player) -> bool:
	if player == null or player.paddle_node == null:
		return false
	var head_offset: Vector3 = player.paddle_node.global_transform.basis.y * 0.4
	var head: Vector3 = player.paddle_node.global_position + head_offset
	var clearance: float = 0.06
	var def = PostureLibrary.instance().get_def(player.paddle_posture)
	if def != null:
		clearance = def.paddle_floor_clearance
	var limited: Vector3 = clamp_head_with_floor(head, shoulder_world(player), player.COURT_FLOOR_Y + clearance)
	if head.distance_squared_to(limited) < 0.000001:
		return false
	player.paddle_node.global_position = limited - head_offset
	return true
