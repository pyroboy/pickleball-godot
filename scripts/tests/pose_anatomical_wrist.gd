extends RefCounted
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")


const Path = preload("res://scripts/stroke_swing_path.gd")
const GripFrame = preload("res://scripts/paddle_grip_frame.gd")
const HandModel = preload("res://scripts/articulated_hand.gd")

static func main_world(player, pose: PostureDefinition) -> Vector3:
	var tx: Transform3D = Path.world_transform(player, pose)
	var is_left: bool = pose.paddle_hand == 1
	var socket: Vector3 = HandModel.WRIST_SOCKET
	if is_left: socket.x = - socket.x
	var offset: Vector3 = pose.left_hand_offset if is_left else pose.right_hand_offset
	return tx * (PaddleSize.MAIN_GRIP_OFFSET + offset) + GripFrame.basis(tx.basis, is_left, pose.main_grip_rotation_deg) * socket

static func support_world(player, pose: PostureDefinition) -> Vector3:
	var point: Vector3 = Path.support_wrist_offset(pose)
	return player.global_position + player._get_forehand_axis() * point.x + Vector3.UP * point.y - player._get_forward_axis() * point.z
