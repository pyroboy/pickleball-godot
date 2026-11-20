extends RefCounted
## Preview path only. Feasible fixed Contact frames are returned unchanged.
## Where a world-frame blend leaves the wrist cone, keep real link geometry,
## project its anatomical channels, and derive the seated paddle from the hand.
const Path = preload("res://scripts/stroke_swing_path.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Reach = preload("res://scripts/paddle_wrist_reach.gd")
const Grip = preload("res://scripts/paddle_grip_frame.gd")
const Budget = preload("res://scripts/live_arm_budget.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const Rotation = preload("res://scripts/paddle_rotation.gd")
const D = preload("res://scripts/paddle_dimensions.gd")
## Binary search steps for the admissible blend (each runs a full arm condition).
## 10 steps cost up to ~45 ms per call on iPhone 15 Pro; 6 resolve the blend to
## 1/64, a few degrees of paddle turn at most.
const SEARCH_STEPS := 6
const WRIST_CORRECTION := false

static func sample(player, desired: PostureDefinition, previous: PostureDefinition, delta: float) -> PostureDefinition:
	if desired == null: return desired
	if not load("res://scripts/live_transition_arm_reach.gd").enabled(player, desired): return desired
	if previous != null and previous.has_meta("live_joint_presented_basis"):
		var rebased: Transform3D = Path.world_transform(player, previous)
		var head: Vector3 = rebased * D.HEAD_OFFSET
		rebased.basis = previous.get_meta("live_joint_presented_basis")
		rebased.origin = head - rebased.basis * D.HEAD_OFFSET
		previous = _encode(player, previous, rebased)
	var result: PostureDefinition = _condition(player, desired)
	if previous == null or delta < 0.0: return _presented(player, result)
	var arm = player.left_arm_node if desired.paddle_hand == 1 else player.right_arm_node
	var before_paddle: Transform3D = Path.world_transform(player, previous)
	var old: Quaternion = Grip.basis(before_paddle.basis, previous.paddle_hand == 1, previous.main_grip_rotation_deg - previous.paddle_in_hand_rotation_deg).orthonormalized().get_rotation_quaternion()
	var allowance: float = deg_to_rad(719.9) * maxf(delta, 0.0) + .00001
	if _hand_angle(player, result, old, previous) <= allowance: return _presented(player, result)
	var low := 0.0; var high := 1.0
	var admitted: PostureDefinition = previous
	for unused in range(SEARCH_STEPS):
		var middle := (low + high) * .5
		var candidate: PostureDefinition = _condition(player, Path.blend_pose(desired, previous, 1.0 - middle))
		if _hand_angle(player, candidate, old, previous) <= allowance:
			low = middle; admitted = candidate
		else: high = middle
	return _presented(player, admitted)

static func _hand_angle(player, pose: PostureDefinition, old: Quaternion, previous: PostureDefinition) -> float:
	var paddle: Transform3D = Path.world_transform(player, pose)
	var basis: Basis = Grip.basis(paddle.basis, pose.paddle_hand == 1, pose.main_grip_rotation_deg - pose.paddle_in_hand_rotation_deg)
	var angle: float = old.angle_to(basis.orthonormalized().get_rotation_quaternion())
	angle = maxf(angle, Path.world_transform(player, previous).basis.orthonormalized().get_rotation_quaternion().angle_to(paddle.basis.orthonormalized().get_rotation_quaternion()))
	if Path._support_mode(pose) == 1:
		var support = player.right_arm_node if pose.paddle_hand == 1 else player.left_arm_node
		var support_basis: Basis = Grip.basis(paddle.basis, pose.paddle_hand == 0, pose.support_grip_rotation_deg - pose.paddle_in_hand_rotation_deg)
		var prior_support: Basis = Grip.basis(Path.world_transform(player, previous).basis, previous.paddle_hand == 0, previous.support_grip_rotation_deg - previous.paddle_in_hand_rotation_deg) if Path._support_mode(previous) == 1 else support.hand_mesh.global_basis.orthonormalized()
		var support_clock: Dictionary = support.get_meta("live_support_frame", {})
		if not support_clock.is_empty():
			prior_support = support_clock.start if is_equal_approx(float(support_clock.time), player._support_sim_time) else support_clock.last
		angle = maxf(angle, prior_support.orthonormalized().get_rotation_quaternion().angle_to(support_basis.orthonormalized().get_rotation_quaternion()))
	return angle

static func _condition(player, desired: PostureDefinition) -> PostureDefinition:
	# Wrist-limit correction is off (user's call): projecting a pose past the wrist
	# limit flipped the AI blade every tick and re-ran the arm solve. The pose is used
	# as authored; the contact rule tolerates the arm (match_contact_authority).
	if not WRIST_CORRECTION: return desired
	var pose: PostureDefinition = desired
	var left: bool = pose.paddle_hand == 1
	var arm = player.left_arm_node if left else player.right_arm_node
	for unused in range(6):
		var paddle: Transform3D = Path.world_transform(player, pose)
		var shoulder: Vector3 = Body.shoulder_world(player, pose)
		if player.leg_ik != null and player.leg_ik.feet_initialized:
			shoulder = Body._position_candidate(player, pose, Body.pivot_transform(player, pose), Vector3.ZERO,
				[player.leg_ik.right_foot_smooth, player.leg_ik.left_foot_smooth]).shoulder
		var wrist: Vector3 = Reach.wrist_world(paddle, pose)
		var hand: Basis = Grip.basis(paddle.basis, left, pose.main_grip_rotation_deg - pose.paddle_in_hand_rotation_deg)
		var prior_body: Dictionary = player.body_pivot.get_meta("live_transition_arm_reach", {})
		var prior_shift: Vector3 = prior_body.get("world_offset", Vector3.ZERO)
		if prior_shift.length() <= .12: shoulder += prior_shift
		var fixed: Dictionary = Budget.solve(shoulder, wrist, arm.forearm_pivot.global_position,
			hand * arm.articulated_hand.anatomical_basis, arm.upper_arm_length, arm.forearm_length, left)
		if fixed.feasible and fixed.cost <= .98: return pose
		var span: Vector3 = wrist - shoulder
		var distance: float = clampf(span.length(), .01, arm.upper_arm_length + arm.forearm_length - .002)
		var axis: Vector3 = span.normalized()
		wrist = shoulder + axis * distance
		var along: float = (arm.upper_arm_length * arm.upper_arm_length - arm.forearm_length * arm.forearm_length + distance * distance) / (2.0 * distance)
		var center: Vector3 = shoulder + axis * along
		var radial: Vector3 = arm.forearm_pivot.global_position - center
		radial -= axis * radial.dot(axis)
		if radial.length_squared() < .000001: radial = Vector3.DOWN - axis * axis.dot(Vector3.DOWN)
		if radial.length_squared() < .000001: radial = player._get_forehand_axis() - axis * axis.dot(player._get_forehand_axis())
		var elbow: Vector3 = fixed.get("nearest_elbow", center + radial.normalized() * sqrt(maxf(0.0, arm.upper_arm_length * arm.upper_arm_length - along * along)))
		var reference: Basis = Anatomy.forearm_reference(shoulder, elbow, wrist, Vector3.UP, left)
		var channels: Dictionary = Anatomy.decompose(reference, hand * arm.articulated_hand.anatomical_basis, -1.0 if left else 1.0)
		var flex: float = channels.flexion_deg
		var deviation: float = channels.radial_deviation_deg
		var reserve: float = minf(lerpf(.998, .75, smoothstep(1.0, 1.4, float(channels.coupled_budget_ratio))), .998 / pow(maxf(1.0, float(fixed.cost)), 2.0))
		reserve = minf(reserve, .978)
		var ratio: float = maxf(1.0, sqrt(float(channels.coupled_budget_ratio) / reserve))
		flex /= ratio; deviation /= ratio
		var axial_limit: float = lerpf(89.9, 75.0, smoothstep(90.0, 110.0, absf(channels.forearm_axial_deg)))
		axial_limit = minf(axial_limit, 88.0)
		var axial: float = clampf(channels.forearm_axial_deg, -axial_limit, axial_limit)
		var sign_side: float = -1.0 if left else 1.0
		var anatomical: Basis = reference * Basis(Vector3.RIGHT, deg_to_rad(axial / sign_side)) * Basis(Vector3.UP, deg_to_rad(flex)) * Basis(Vector3.BACK, deg_to_rad(deviation / sign_side))
		hand = anatomical * arm.articulated_hand.anatomical_basis.inverse()
		var anchor: Vector3 = wrist - hand * arm.articulated_hand.wrist_socket
		var grip: Basis = Grip.basis(Basis.IDENTITY, left, pose.main_grip_rotation_deg - pose.paddle_in_hand_rotation_deg)
		var basis: Basis = hand * grip.inverse()
		var head: Vector3 = paddle * D.HEAD_OFFSET
		pose = _encode(player, pose, Transform3D(basis, head - basis * D.HEAD_OFFSET))
		pose.set_meta("live_joint_preparation", true)
	return pose

static func _encode(player, pose: PostureDefinition, desired: Transform3D) -> PostureDefinition:
	return preload("res://scripts/paddle_pose_encoding.gd").encode(player, pose, desired)

static func _presented(player, pose: PostureDefinition) -> PostureDefinition:
	var result: PostureDefinition = pose.duplicate(false)
	result.set_meta("live_joint_presented_basis", Path.world_transform(player, pose).basis.orthonormalized())
	return result
