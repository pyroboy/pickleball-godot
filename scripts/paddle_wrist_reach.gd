extends RefCounted


const D = preload("res://scripts/paddle_dimensions.gd")
const Hand = preload("res://scripts/articulated_hand.gd")
const Grip = preload("res://scripts/paddle_grip_frame.gd")
const DEFAULT_LINK_BUDGET: = 0.7
const NUMERICAL_EPSILON: = 0.0001


static var _right_socket_in_grip: Vector3 = Grip.basis(Basis.IDENTITY, false) * Hand.WRIST_SOCKET
static var _left_socket_in_grip: Vector3 = Grip.basis(Basis.IDENTITY, true) * Vector3( - Hand.WRIST_SOCKET.x, Hand.WRIST_SOCKET.y, Hand.WRIST_SOCKET.z)

static func socket(is_left: bool) -> Vector3:
	var point: Vector3 = Hand.WRIST_SOCKET
	if is_left: point.x = - point.x
	return point

static func grip_local(pose: PostureDefinition) -> Vector3:
	return D.MAIN_GRIP_OFFSET + (pose.left_hand_offset if pose.paddle_hand == 1 else pose.right_hand_offset)

static func virtual_grip_world(paddle: Transform3D, pose: PostureDefinition) -> Vector3:
	return paddle * grip_local(pose)

static func wrist_world(paddle: Transform3D, pose: PostureDefinition) -> Vector3:
	var offset: Vector3 = socket_in_grip(pose)
	return paddle * (grip_local(pose) + offset)

static func socket_in_grip(pose: PostureDefinition) -> Vector3:
	var offset: Vector3 = _left_socket_in_grip if pose.paddle_hand == 1 else _right_socket_in_grip
	var angle: float = pose.main_grip_rotation_deg - pose.paddle_in_hand_rotation_deg
	return offset if is_zero_approx(angle) else offset.rotated(Vector3.UP, deg_to_rad(angle))

static func head_to_wrist_offset(basis: Basis, pose: PostureDefinition) -> Vector3:
	var offset: Vector3 = socket_in_grip(pose)
	return basis * (grip_local(pose) - D.HEAD_OFFSET + offset)

static func wrist_from_head(head: Vector3, basis: Basis, pose: PostureDefinition) -> Vector3:
	return head + head_to_wrist_offset(basis, pose)

static func link_budget(player, pose: PostureDefinition) -> float:
	var key: String = "left_arm_node" if pose.paddle_hand == 1 else "right_arm_node"
	if player != null and key in player:
		var arm = player.get(key)
		if arm != null: return arm.upper_arm_length + arm.forearm_length
	return DEFAULT_LINK_BUDGET

static func fits(paddle: Transform3D, pose: PostureDefinition, shoulder: Vector3, budget: float = DEFAULT_LINK_BUDGET) -> bool:
	return wrist_world(paddle, pose).distance_to(shoulder) <= budget + NUMERICAL_EPSILON



static func live_shoulder(player, pose: PostureDefinition) -> Vector3:
	var arm = player.left_arm_node if pose.paddle_hand == 1 else player.right_arm_node
	return arm.upper_pivot.global_position



static func displayed_wrist(player, pose: PostureDefinition) -> Vector3:
	var arm = player.left_arm_node if pose.paddle_hand == 1 else player.right_arm_node
	return arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket
