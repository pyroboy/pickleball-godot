extends RefCounted
## Presentation-only Ready tracking. Call after the recovery/preparation blend.
## The caller supplies a visible/permitted target; this never predicts or steers a shot.
const Path = preload("res://scripts/stroke_swing_path.gd")
const Orientation = preload("res://scripts/stroke_preparation_orientation.gd")
const Wrist = preload("res://scripts/paddle_wrist_reach.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const D = preload("res://scripts/paddle_dimensions.gd")
const Grip = preload("res://scripts/paddle_grip_frame.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const BASE_META: = "ready_tracking_base"
const TIP_LIMIT: = deg_to_rad(12.0)
const TIP_HALFLIFE: = 0.018
const TIP_SPEED: = deg_to_rad(1080.0)
const TORSO_LIMIT: = 8.0
const TORSO_HALFLIFE: = 0.085
const TORSO_SPEED: = 240.0
var _tip: = Quaternion.IDENTITY
var _torso: = 0.0

static func untracked(pose: PostureDefinition) -> PostureDefinition:
	return pose.get_meta(BASE_META, pose) if pose != null else null

static func response_weight(distance: float, delta: float, halflife: float, speed: float) -> float:
	if distance < 0.000001: return 1.0
	var k: float = log(2.0) / halflife
	var threshold: float = speed / k
	var linear_time: float = maxf(0.0, (distance - threshold) / speed)
	var remaining: float = distance - speed * maxf(delta, 0.0) if distance > threshold and delta <= linear_time else minf(distance, threshold) * exp(-k * maxf(0.0, delta - linear_time))
	return clampf(1.0 - remaining / distance, 0.0, 1.0)

func apply(source: PostureDefinition, player, target_world: Vector3, delta: float, amount: float = 1.0) -> PostureDefinition:
	if source == null: return source
	var base: PostureDefinition = untracked(source)
	var weight: float = clampf(amount, 0.0, 1.0)
	if weight <= 0.00001 or not target_world.is_finite(): return base
	var stance: = Basis(player._get_forehand_axis(), Vector3.UP, -player._get_forward_axis())
	var target: Vector3 = stance.inverse() * (target_world - player.global_position)
	var raw: Transform3D = Path.canonical_transform(base)
	var grip: Vector3 = Wrist.virtual_grip_world(raw, base)
	var direction: Vector3 = target - grip
	var tip_goal: = Quaternion.IDENTITY
	if direction.length_squared() > 0.000001:
		var from: Vector3 = raw.basis.y.normalized()
		var to: Vector3 = direction.normalized()
		var axis: Vector3 = from.cross(to)
		var angle: float = acos(clampf(from.dot(to), -1.0, 1.0))
		if axis.length_squared() < 0.000001: axis = raw.basis.x
		tip_goal = Quaternion(axis.normalized(), minf(angle, TIP_LIMIT))
	_tip = _tip.slerp(tip_goal, response_weight(_tip.angle_to(tip_goal), delta, TIP_HALFLIFE, TIP_SPEED)).normalized()
	var body_goal: float = clampf(rad_to_deg(atan2(target.x, -target.z)), -TORSO_LIMIT, TORSO_LIMIT) if Vector2(target.x, target.z).length_squared() > 0.01 else 0.0
	_torso = lerpf(_torso, body_goal, response_weight(absf(body_goal - _torso), delta, TORSO_HALFLIFE, TORSO_SPEED))
	var result: PostureDefinition = _sample(base, grip, weight)
	# Rotating the shaft must not buy extra arm length. If an authored/custom
	# guard is already at its limit, reduce the overlay rather than move its grip.
	var limits: Vector2 = _reach_limits(base, player)
	var wrist_limits: Vector4 = _wrist_limits(base, player)
	if not _within_reach(result, player, limits) or not _within_wrist(result, player, wrist_limits):
		var low: = 0.0
		var high: float = weight
		for attempt in range(9):
			var middle: float = (low + high) * 0.5
			var candidate: PostureDefinition = _sample(base, grip, middle)
			if _within_reach(candidate, player, limits) and _within_wrist(candidate, player, wrist_limits): low = middle
			else: high = middle
		weight = low
		result = _sample(base, grip, weight)
	result.set_meta(BASE_META, base)
	result.set_meta("ready_tracking_torso_yaw_deg", _torso * weight)
	result.set_meta("ready_tracking_tip_angle_deg", rad_to_deg(Quaternion.IDENTITY.angle_to(_tip)) * weight)
	return result

func _sample(base: PostureDefinition, grip: Vector3, weight: float) -> PostureDefinition:
	var result: PostureDefinition = base.lerp_with(base, 0.0)
	for key in base.get_meta_list():
		if key != BASE_META: result.set_meta(key, base.get_meta(key))
	# Body/hip/feet remain authored. Only the chest assists the fast tip.
	result.torso_yaw_deg += _torso * weight
	var turn: = Basis(Quaternion.IDENTITY.slerp(_tip, weight))
	var basis: Basis = turn * Orientation.canonical_basis(base)
	Orientation.set_canonical_basis(result, basis)
	var head: Vector3 = grip + basis * (D.HEAD_OFFSET - Wrist.grip_local(base))
	result.paddle_forehand_mul = head.x
	result.paddle_y_offset = head.y
	result.paddle_forward_mul = -head.z
	return result

static func _reach_distances(pose: PostureDefinition, player) -> Vector2:
	var paddle: Transform3D = Path.world_transform(player, pose)
	var main: float = Wrist.wrist_world(paddle, pose).distance_to(Body.shoulder_world(player, pose))
	var support: = 0.0
	if Path._support_mode(pose) == 1:
		var stance: = Basis(player._get_forehand_axis(), Vector3.UP, -player._get_forward_axis())
		var is_left: bool = pose.paddle_hand == 0
		var offset: Vector3 = pose.left_hand_offset if is_left else pose.right_hand_offset
		var support_wrist: Vector3 = paddle * (D.SUPPORT_GRIP_OFFSET + Vector3.UP * pose.support_grip_slide_m) + stance * Vector3(offset.x, offset.y, -offset.z)
		support_wrist += Grip.basis(paddle.basis, is_left, pose.support_grip_rotation_deg - pose.paddle_in_hand_rotation_deg) * Wrist.socket(is_left)
		var other: PostureDefinition = pose.lerp_with(pose, 0.0)
		for key in pose.get_meta_list(): other.set_meta(key, pose.get_meta(key))
		other.paddle_hand = 1 - pose.paddle_hand
		support = support_wrist.distance_to(Body.shoulder_world(player, other))
	return Vector2(main, support)

static func _reach_limits(base: PostureDefinition, player) -> Vector2:
	var distances: Vector2 = _reach_distances(base, player)
	var other: PostureDefinition = base.lerp_with(base, 0.0)
	other.paddle_hand = 1 - base.paddle_hand
	return Vector2(maxf(Wrist.link_budget(player, base), distances.x), maxf(Wrist.link_budget(player, other), distances.y)) + Vector2.ONE * 0.00001

static func _within_reach(pose: PostureDefinition, player, limits: Vector2) -> bool:
	var distances: Vector2 = _reach_distances(pose, player)
	return distances.x <= limits.x and distances.y <= limits.y

# Analytic copy of the existing two-link/mount geometry; no rig writes. Keep
# custom authored wrist envelopes, but never add a larger tracking excursion.
static func _wrist_channels(pose: PostureDefinition, player, left: bool) -> Vector2:
	var arm = player.left_arm_node if left else player.right_arm_node
	if arm == null or arm.articulated_hand == null: return Vector2.ZERO
	var dominant: bool = (pose.paddle_hand == 1) == left
	if not dominant and Path._support_mode(pose) != 1: return Vector2.ZERO
	var paddle: Transform3D = Path.world_transform(player, pose)
	var stance: = Basis(player._get_forehand_axis(), Vector3.UP, -player._get_forward_axis())
	var offset: Vector3 = pose.left_hand_offset if left else pose.right_hand_offset
	var anchor: Vector3 = paddle * (D.MAIN_GRIP_OFFSET + offset) if dominant else paddle * (D.SUPPORT_GRIP_OFFSET + Vector3.UP * pose.support_grip_slide_m) + stance * Vector3(offset.x, offset.y, -offset.z)
	var rotation: float = (pose.main_grip_rotation_deg if dominant else pose.support_grip_rotation_deg) - pose.paddle_in_hand_rotation_deg
	var hand: Basis = Grip.basis(paddle.basis, left, rotation)
	var wrist: Vector3 = anchor + hand * Wrist.socket(left)
	var sided: PostureDefinition = pose.lerp_with(pose, 0.0)
	for key in pose.get_meta_list(): sided.set_meta(key, pose.get_meta(key))
	sided.paddle_hand = 1 if left else 0
	var shoulder: Vector3 = Body.shoulder_world(player, sided)
	var guide: Vector3 = pose.left_elbow_pole if left else pose.right_elbow_pole
	if guide.length_squared() < 0.00000001: guide = Vector3(-0.5 if left else 0.5, -1.0, -0.5)
	var pole: Vector3 = player.global_position + stance * Vector3(guide.x, guide.y, -guide.z)
	var angles: Vector3 = pose.left_shoulder_rotation_deg if left else pose.right_shoulder_rotation_deg
	var shoulder_rotation: Basis = stance * Basis.from_euler(angles * (PI / 180.0)) * stance.inverse()
	pole = shoulder + shoulder_rotation * (pole - shoulder)
	pole = Anatomy.stabilized_pole(shoulder, wrist, pole, player._get_forehand_axis() * (1.0 if left else -1.0))
	var hand_frame: Basis = hand * arm.articulated_hand.anatomical_basis
	pole = Anatomy.conditioned_pole(shoulder, wrist, pole, hand_frame.x, arm.upper_arm_length, arm.forearm_length)
	var span: Vector3 = wrist - shoulder
	var distance: float = span.length()
	if distance < 0.00001: return Vector2.ZERO
	var axis: Vector3 = span / distance
	var along: float = (arm.upper_arm_length * arm.upper_arm_length - arm.forearm_length * arm.forearm_length + distance * distance) / (2.0 * distance)
	var radius: float = sqrt(maxf(0.0, arm.upper_arm_length * arm.upper_arm_length - along * along))
	var radial: Vector3 = pole - shoulder
	radial = (radial - axis * radial.dot(axis)).normalized()
	var elbow: Vector3 = shoulder + axis * along + radial * radius
	var channels: Dictionary = Anatomy.decompose(Anatomy.forearm_reference(shoulder, elbow, wrist, Vector3.UP, left), hand_frame, -1.0 if left else 1.0)
	return Vector2(channels.coupled_budget_ratio, absf(channels.forearm_axial_deg))

static func _wrist_limits(base: PostureDefinition, player) -> Vector4:
	var right: Vector2 = _wrist_channels(base, player, false)
	var left: Vector2 = _wrist_channels(base, player, true)
	return Vector4(maxf(1.0, right.x) + 0.0001, maxf(90.0, right.y) + 0.0001, maxf(1.0, left.x) + 0.0001, maxf(90.0, left.y) + 0.0001)

static func _within_wrist(pose: PostureDefinition, player, limits: Vector4) -> bool:
	var right: Vector2 = _wrist_channels(pose, player, false)
	var left: Vector2 = _wrist_channels(pose, player, true)
	return right.x <= limits.x and right.y <= limits.y and left.x <= limits.z and left.y <= limits.w
