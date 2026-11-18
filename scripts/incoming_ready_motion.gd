extends RefCounted


const Rotation = preload("res://scripts/paddle_rotation.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Support = preload("res://scripts/groundstroke_support_motion.gd")
const GripTransition = preload("res://scripts/grip_transition.gd")
const GRIP_TRANSITION_TIME: = 0.32
const GRIP_TRANSITION_STATE: = "joined_grip_transition"
const PREP_START_TIME: = 1.15
const PREP_FULL_TIME: = 0.24
const TRACK_HALFLIFE: = 0.065
const RECOVER_HALFLIFE: = 0.1
const SPLIT_DURATION: = 0.22
const MAX_PREPARATION_ANGULAR_SPEED_DEG: = 720.0

static func ready_pose(source: PostureDefinition) -> PostureDefinition:

	return source.lerp_with(source, 0.0)

static func prepare(contact: PostureDefinition, ready: PostureDefinition, 
		time_to_contact: float, pre_bounce: bool, near_kitchen: bool = false) -> PostureDefinition:

	var amount: float = 0.18 if pre_bounce else 0.46
	if contact.height_tier <= 1: amount = 0.24
	if contact.family == 3: amount = 0.52
	var prepared: PostureDefinition = contact.lerp_with(Path.endpoint(contact, 0), amount)


	if contact.family == 1 and contact.left_hand_mode == 1:
		prepared = Path.sample(contact, 0.5 * (1.0 - amount))
	var urgency: float = smoothstep(PREP_START_TIME, PREP_FULL_TIME, maxf(time_to_contact, 0.0))

	var pose: PostureDefinition = Path.blend_pose(prepared, ready, 1.0 - urgency)
	if GripTransition.supports_both_joined(ready, prepared):



		pose = prepared if urgency > 0.0001 else Path.blend_pose(prepared, ready, 1.0)
	pose.paddle_hand = contact.paddle_hand
	pose.lead_foot = contact.lead_foot
	Support.prepare(pose, contact, time_to_contact, urgency, pre_bounce or near_kitchen)
	return pose

static func blend_pose(current: PostureDefinition, target: PostureDefinition, 
		delta: float, halflife: float = TRACK_HALFLIFE) -> PostureDefinition:
	if current == null: return target
	if grip_transition_active(current) or GripTransition.supports_both_joined(current, target):
		return _blend_joined_grip(current, target, delta)
	var weight: float = 1.0 - pow(0.5, maxf(delta, 0.0) / maxf(halflife, 0.001))



	# Rate-limit the same complete basis that Path.blend_pose interpolates.
	# Measuring unspun Euler channels makes the clock depend on frame splitting
	# when the selected grip spin changes during preparation/recovery.
	var qa:Quaternion=Rotation.displayed_basis(current).get_rotation_quaternion()
	var qb:Quaternion=Rotation.displayed_basis(target).get_rotation_quaternion()
	var angle: float = qa.angle_to(qb)
	# A seated hand also rolls around the shaft. Its composed path has constant
	# angular speed: paddle slerp's world rotation vector plus shaft-axis roll.
	# Use that exact arc length, not the sum of magnitudes: opposing rotations
	# can cancel, and an over-conservative sum delayed short legal receptions.
	var main_twist: float = angle_difference(deg_to_rad(current.main_grip_rotation_deg), deg_to_rad(target.main_grip_rotation_deg)) - angle_difference(deg_to_rad(current.paddle_in_hand_rotation_deg), deg_to_rad(target.paddle_in_hand_rotation_deg))
	angle = maxf(angle, _hand_path_angle(qa, qb, main_twist))
	if Path.support_grip_weight(current) > 0.00001 or Path.support_grip_weight(target) > 0.00001:
		var support_twist: float = angle_difference(deg_to_rad(current.support_grip_rotation_deg), deg_to_rad(target.support_grip_rotation_deg)) - angle_difference(deg_to_rad(current.paddle_in_hand_rotation_deg), deg_to_rad(target.paddle_in_hand_rotation_deg))
		angle = maxf(angle, _hand_path_angle(qa, qb, support_twist))
	if angle > 1e-05:


		var speed: float = deg_to_rad(MAX_PREPARATION_ANGULAR_SPEED_DEG)
		var k: float = log(2.0) / maxf(halflife, 0.001)
		var threshold: float = speed / k
		var linear_time: float = maxf(0.0, (angle - threshold) / speed)
		var remaining: float
		if angle > threshold and delta <= linear_time:
			remaining = angle - speed * maxf(delta, 0.0)
		else:
			remaining = minf(angle, threshold) * exp( - k * maxf(0.0, delta - linear_time))
		weight = 1.0 - remaining / angle

	var pose: PostureDefinition = Path.blend_pose(target, current, 1.0 - weight)
	pose.paddle_hand = target.paddle_hand
	pose.lead_foot = target.lead_foot
	if Path.support_wrist_offset(pose).distance_to(Path.support_wrist_offset(target)) < 0.002 and absf(Path.support_grip_weight(pose) - Path.support_grip_weight(target)) < 0.001:
		pose.left_hand_mode = target.left_hand_mode
		pose.set_meta("support_grip_weight", Path.support_grip_weight(target))
		if target.paddle_hand == 1: pose.right_hand_offset = target.right_hand_offset
		else: pose.left_hand_offset = target.left_hand_offset
	return pose

static func _hand_path_angle(from: Quaternion, to: Quaternion, twist: float) -> float:
	var relative: Quaternion = (to * from.inverse()).normalized()
	if relative.w < 0.0: relative = Quaternion(-relative.x, -relative.y, -relative.z, -relative.w)
	var paddle_angle: float = relative.get_angle()
	var angular: Vector3 = Vector3.ZERO if paddle_angle < .000001 else relative.get_axis() * paddle_angle
	return (angular + (Basis(from) * Vector3.UP) * twist).length()

static func grip_transition_active(pose: PostureDefinition) -> bool:
	return pose != null and pose.has_meta(GRIP_TRANSITION_STATE)

static func _blend_joined_grip(current: PostureDefinition, target: PostureDefinition, delta: float) -> PostureDefinition:
	var state: Dictionary
	if grip_transition_active(current):
		state = current.get_meta(GRIP_TRANSITION_STATE).duplicate()
	else:
		state = {"from": current.lerp_with(current, 0.0), "to": target.lerp_with(target, 0.0), "progress": 0.0}
	var start: PostureDefinition = state["from"]
	var finish: PostureDefinition = state["to"]


	var wanted_profile: float = target.support_grip_style if target.left_hand_mode == 1 else 0.0
	var forward: bool = absf(wanted_profile - finish.support_grip_style) <= absf(wanted_profile - start.support_grip_style)
	var progress: float = clampf(float(state.progress) + (1.0 if forward else -1.0) * maxf(delta, 0.0) / GRIP_TRANSITION_TIME, 0.0, 1.0)
	var pose: PostureDefinition = GripTransition.sample(start, finish, progress)


	pose.set_meta("visual_locomotion_weight", Path.locomotion_weight(pose))
	pose.posture_id = target.posture_id
	pose.display_name = target.display_name
	pose.family = target.family
	pose.height_tier = target.height_tier
	if progress > 0.0 and progress < 1.0:
		state.progress = progress
		pose.set_meta(GRIP_TRANSITION_STATE, state)
	else:
		pose.set_meta("joined_grip_transition_finished", true)
	return pose

static func split_load(remaining: float) -> float:
	return sin(PI * clampf(remaining / SPLIT_DURATION, 0.0, 1.0)) * 0.035
