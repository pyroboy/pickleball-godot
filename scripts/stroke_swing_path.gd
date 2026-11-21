extends RefCounted
const AroundBody = preload("res://scripts/around_body.gd")
const Rotation = preload("res://scripts/paddle_rotation.gd")
const FloorGeometry = preload("res://scripts/paddle_floor_geometry.gd")
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const GripFrame = preload("res://scripts/paddle_grip_frame.gd")
const HandModel = preload("res://scripts/articulated_hand.gd")
const BodyPose = preload("res://scripts/stroke_body_pose.gd")
const Orientation = preload("res://scripts/stroke_preparation_orientation.gd")
const ContactCurve = preload("res://scripts/contact_paddle_curve.gd")
const ElbowPreset = preload("res://scripts/elbow_preset_runtime.gd")
const Ramp = preload("res://scripts/stroke_speed_ramp.gd")


static func endpoint(def: PostureDefinition, stage: int) -> PostureDefinition:
	var pose: PostureDefinition = def.lerp_with(def, 0.0)
	if stage == 1:
		Rotation.normalize_channels(pose)
		return pose
	var offset: Vector3 = def.charge_paddle_offset if stage == 0 else def.ft_paddle_offset
	var rotation: Vector3 = def.charge_paddle_rotation_deg if stage == 0 else def.ft_paddle_rotation_deg
	pose.paddle_forehand_mul += offset.x
	pose.paddle_y_offset += offset.y
	pose.paddle_forward_mul += offset.z
	pose.paddle_pitch_base_deg += rotation.x
	pose.paddle_yaw_base_deg += rotation.y
	pose.paddle_roll_base_deg += rotation.z
	pose.hip_yaw_deg += def.charge_hip_coil_deg if stage == 0 else def.ft_hip_uncoil_deg
	pose.weight_shift = - def.charge_back_foot_load if stage == 0 else def.ft_front_foot_load
	if stage == 0:
		pose.body_yaw_deg += def.charge_body_rotation_deg
	var body: Resource = def.windup_body if stage == 0 else def.follow_through_body
	if body and body.has_method("apply_to"):
		body.apply_to(pose)
	Rotation.normalize_channels(pose)
	return pose

static func sample(def: PostureDefinition, progress: float) -> PostureDefinition:
	# Ready is a static stance. Its retained historical body keys are not motion
	# phases and must never override the authored top-level pose while sampling.
	if def.posture_id == 20:
		return def.duplicate(true)
	return sample_with_endpoints(def, progress, endpoint(def, 0), endpoint(def, 2))

# Callers may reuse endpoint construction only for an unchanged source during
# one synchronous operation. The normal API above always observes fresh edits.
static func sample_with_endpoints(def: PostureDefinition, progress: float, windup: PostureDefinition, finish: PostureDefinition) -> PostureDefinition:
	if def.posture_id == 20: return def.duplicate(true)
	var t: float = clampf(progress, 0.0, 1.0)
	var a: PostureDefinition = windup if t <= 0.5 else def
	var b: PostureDefinition = def if t <= 0.5 else finish
	var u: float = t * 2.0 if t <= 0.5 else (t - 0.5) * 2.0
	var pose: PostureDefinition = a.lerp_with(b, u)
	var p0: = Vector3(windup.paddle_forehand_mul, windup.paddle_y_offset, windup.paddle_forward_mul)
	var p1: = Vector3(def.paddle_forehand_mul, def.paddle_y_offset, def.paddle_forward_mul)
	var p2: = Vector3(finish.paddle_forehand_mul, finish.paddle_y_offset, finish.paddle_forward_mul)
	var start: Vector3 = p0 if t <= 0.5 else p1
	var end: Vector3 = p1 if t <= 0.5 else p2

	var tangent: = (p2 - p0) * 0.5
	var m0: Vector3 = p1 - p0 if t <= 0.5 else tangent
	var m1: Vector3 = tangent if t <= 0.5 else p2 - p1
	var curved: = (2 * u * u * u - 3 * u * u + 1) * start + (u * u * u - 2 * u * u + u) * m0 + (-2 * u * u * u + 3 * u * u) * end + (u * u * u - u * u) * m1
	var position: Vector3 = start.lerp(end, u).lerp(curved, def.swing_path_blend) + path_offset(def, t)
	if t > 0.5:
		# Follow-through (the ball has left): the paddle sweeps around the body, not through it.
		# Canonical frame is (x, y, -forward); Contact and Finish themselves never move.
		var head_c := Vector3(position.x, position.y, -position.z)
		var grip: Vector3 = head_c + Rotation.unspun_basis(pose) * ((PaddleSize.MAIN_GRIP_OFFSET - PaddleSize.HEAD_OFFSET) + _main_offset(pose))
		var shift: Vector3 = AroundBody.shift(pose, grip, head_c, paddle_hand(def), paddle_head(def), paddle_hand(finish), paddle_head(finish), u)
		position += Vector3(shift.x, shift.y, -shift.z)
	pose.paddle_forehand_mul = position.x
	pose.paddle_y_offset = position.y
	pose.paddle_forward_mul = position.z

	# lerp_with blends the complete resolved paddle basis, including shaft spin.
	if def.family == 1 and a.left_hand_mode == 1 and b.left_hand_mode == 1:




		var frame_a: = Basis(Vector3.UP, deg_to_rad( - (a.body_yaw_deg + a.hip_yaw_deg + a.torso_yaw_deg)))
		var frame_b: = Basis(Vector3.UP, deg_to_rad( - (b.body_yaw_deg + b.hip_yaw_deg + b.torso_yaw_deg)))
		var frame_now: = Basis(Vector3.UP, deg_to_rad( - (pose.body_yaw_deg + pose.hip_yaw_deg + pose.torso_yaw_deg)))
		var local_a: Vector3 = frame_a.inverse() * Vector3(start.x, start.y, - start.z)
		var local_b: Vector3 = frame_b.inverse() * Vector3(end.x, end.y, - end.z)
		var head: Vector3 = frame_now * local_a.lerp(local_b, u)
		pose.paddle_forehand_mul = head.x;pose.paddle_y_offset = head.y;pose.paddle_forward_mul = - head.z

	# Apply after the linked two-hand path so every stroke uses the same control.
	ContactCurve.apply(pose, ContactCurve.bend(p0, p1, p2), t, def.contact_curve)
	if def.right_elbow_path.size() >= 2: pose.right_elbow_pole = _sample_elbow_path(def.right_elbow_path, t)
	if def.left_elbow_path.size() >= 2: pose.left_elbow_pole = _sample_elbow_path(def.left_elbow_path, t)
	ElbowPreset.tag(pose,def,t,"stroke_authored")
	return pose



## Paddle path keys (PostureDefinition.paddle_path_times / _offsets): the offset off the normal
## curve at progress t. Cubic Hermite through (0, 0), the keys, (0.5, 0), (1, 0); the slope is
## zero at Wind-up, Contact and Finish (the paddle meets the ball on the same line).
static func path_offset(def: PostureDefinition, t: float) -> Vector3:
	var n: int = mini(def.paddle_path_times.size(), def.paddle_path_offsets.size())
	if n == 0: return Vector3.ZERO
	var ts: Array = [0.0, 0.5, 1.0]
	var os: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	for i in n:
		var k: float = def.paddle_path_times[i]
		if k <= 0.0 or k >= 1.0 or is_equal_approx(k, 0.5): continue
		var j := ts.size()
		for m in ts.size(): if ts[m] > k: j = m; break
		ts.insert(j, k); os.insert(j, def.paddle_path_offsets[i])
	var i := 0
	while i < ts.size() - 2 and t > ts[i + 1]: i += 1
	var h: float = ts[i + 1] - ts[i]
	if h <= 0.0: return Vector3.ZERO
	var s: float = clampf((t - ts[i]) / h, 0.0, 1.0)
	var slope := func(m: int) -> Vector3:
		if is_equal_approx(ts[m], 0.0) or is_equal_approx(ts[m], 0.5) or is_equal_approx(ts[m], 1.0): return Vector3.ZERO
		return (os[m + 1] - os[m - 1]) / (ts[m + 1] - ts[m - 1])
	var m0: Vector3 = slope.call(i); var m1: Vector3 = slope.call(i + 1)
	return (2*s*s*s - 3*s*s + 1) * os[i] + (s*s*s - 2*s*s + s) * h * m0 + (-2*s*s*s + 3*s*s) * os[i + 1] + (s*s*s - s*s) * h * m1

static func _sample_elbow_path(points: PackedVector3Array, t: float) -> Vector3:
	var position: float = clampf(t, 0.0, 1.0) * float(points.size() - 1)
	var first: int = mini(int(floor(position)), points.size() - 2)
	return points[first].lerp(points[first + 1], position - float(first))





static func unspun_paddle_basis(player, pose: PostureDefinition) -> Basis:
	var rotation: Vector3 = pose.resolve_paddle_rotation_deg(-1.0, -1.0)
	var authored: Basis = Rotation.basis(rotation)
	var stance: = Basis(player._get_forehand_axis(), Vector3.UP, - player._get_forward_axis())
	return stance * authored

static func paddle_basis(player, pose: PostureDefinition) -> Basis:
	return unspun_paddle_basis(player, pose) * Basis(Vector3.UP, deg_to_rad(pose.paddle_in_hand_rotation_deg))

## Spin around the seated dominant-hand grip, not around the paddle head.
## Inverse grip-frame rotation at the hand mount keeps the actual wrist fixed.
static func apply_in_hand_transform(raw: Transform3D, pose: PostureDefinition) -> Transform3D:
	if is_zero_approx(pose.paddle_in_hand_rotation_deg): return raw
	var offset: Vector3 = PaddleSize.MAIN_GRIP_OFFSET + (pose.left_hand_offset if pose.paddle_hand == 1 else pose.right_hand_offset)
	var basis: Basis = raw.basis * Basis(Vector3.UP, deg_to_rad(pose.paddle_in_hand_rotation_deg))
	return Transform3D(basis, raw * offset - basis * offset)

static func remove_in_hand_transform(displayed: Transform3D, pose: PostureDefinition) -> Transform3D:
	if is_zero_approx(pose.paddle_in_hand_rotation_deg): return displayed
	var offset: Vector3 = PaddleSize.MAIN_GRIP_OFFSET + (pose.left_hand_offset if pose.paddle_hand == 1 else pose.right_hand_offset)
	var basis: Basis = displayed.basis * Basis(Vector3.UP, deg_to_rad(-pose.paddle_in_hand_rotation_deg))
	return Transform3D(basis, displayed * offset - basis * offset)

static func canonical_transform(pose: PostureDefinition) -> Transform3D:
	var basis: Basis = Orientation.canonical_basis(pose)
	var head := Vector3(pose.paddle_forehand_mul, pose.paddle_y_offset, -pose.paddle_forward_mul)
	return apply_in_hand_transform(Transform3D(basis, head - basis * PaddleSize.HEAD_OFFSET), pose)

static func world_transform(player, pose: PostureDefinition) -> Transform3D:
	var basis: = unspun_paddle_basis(player, pose)
	var head: Vector3 = player.global_position + pose.resolve_paddle_offset(player._get_forehand_axis(), player._get_forward_axis())
	if bool(pose.get_meta("travel_paddle_follow",false)) and BodyPose.locomotion_weight(player,pose) > .00001:
		var pivot:Transform3D=BodyPose.untranslated_pivot_transform(player,pose)
		var authored:Transform3D=pivot*BodyPose.torso_transform(player,pose,false)
		var displayed:Transform3D=pivot*BodyPose.torso_transform(player,pose,true)
		var travel:Transform3D=displayed*authored.affine_inverse()
		head=player.global_position+travel*(head-player.global_position)
		basis=travel.basis*basis
	# Body positioning must never drag Contact. Preserve the pre-offset solved
	# paddle target; BodyPose caps the body against this fixed grip instead.
	if pose.has_zone and pose.height_tier == 0 and pose.paddle_floor_clearance < 0.3:
		var displayed := apply_in_hand_transform(Transform3D(basis, head - basis * PaddleSize.HEAD_OFFSET), pose)
		var displayed_head: Vector3 = displayed * PaddleSize.HEAD_OFFSET
		var limited: Vector3 = PaddleReach.clamp_head_with_floor(displayed_head, BodyPose.shoulder_world(player, pose, null, false), player.COURT_FLOOR_Y + FloorGeometry.clearance(pose, displayed.basis))
		displayed.origin += limited - displayed_head
		return displayed
	head = PaddleReach.clamp_head_with_floor(head, BodyPose.shoulder_world(player, pose, null, false), player.COURT_FLOOR_Y + pose.paddle_floor_clearance)
	return apply_in_hand_transform(Transform3D(basis, head - basis.y * PaddleSize.HEAD_CENTER_Y), pose)
static func release_progress(def: PostureDefinition, phase: int, factor: float) -> float:
	var part: int = Ramp.FINISH if phase == 1 else Ramp.STRIKE
	if Ramp.custom(def, part): return Ramp.normalized(def, part, factor) * 0.5 + (0.5 if phase == 1 else 0.0)
	var transition: Tween.TransitionType = Tween.TRANS_EXPO
	if def.ft_ease_curve == 1: transition = Tween.TRANS_QUAD
	elif def.ft_ease_curve == 2: transition = Tween.TRANS_SINE
	var easing: Tween.EaseType = Tween.EASE_IN_OUT if def.ft_ease_curve == 2 else Tween.EASE_OUT
	var eased: float = Tween.interpolate_value(0.0, 1.0, clampf(factor, 0.0, 1.0), 1.0, transition, easing)
	return eased * 0.5 + (0.5 if phase == 1 else 0.0)




static func blend_pose(from_pose: PostureDefinition, to_pose: PostureDefinition, weight: float) -> PostureDefinition:
	var t: float = clampf(weight, 0.0, 1.0)
	var pose: PostureDefinition = from_pose.lerp_with(to_pose, t)
	ElbowPreset.clear_tag(pose)
	pose.body_yaw_deg = rad_to_deg(lerp_angle(deg_to_rad(from_pose.body_yaw_deg), deg_to_rad(to_pose.body_yaw_deg), t))
	var from_basis: Basis = Rotation.unspun_basis(from_pose)
	var to_basis: Basis = Rotation.unspun_basis(to_pose)
	var basis: Basis = Rotation.unspun_basis(pose)
	var from_offset: Vector3 = from_pose.left_hand_offset if from_pose.paddle_hand == 1 else from_pose.right_hand_offset
	var to_offset: Vector3 = to_pose.left_hand_offset if to_pose.paddle_hand == 1 else to_pose.right_hand_offset
	var offset: Vector3 = pose.left_hand_offset if pose.paddle_hand == 1 else pose.right_hand_offset
	var hand_a: = Vector3(from_pose.paddle_forehand_mul, from_pose.paddle_y_offset, - from_pose.paddle_forward_mul) + from_basis * ((PaddleSize.MAIN_GRIP_OFFSET - PaddleSize.HEAD_OFFSET) + from_offset)
	var hand_b: = Vector3(to_pose.paddle_forehand_mul, to_pose.paddle_y_offset, - to_pose.paddle_forward_mul) + to_basis * ((PaddleSize.MAIN_GRIP_OFFSET - PaddleSize.HEAD_OFFSET) + to_offset)
	var hand: Vector3 = hand_a.lerp(hand_b, t)
	var head: Vector3 = hand - basis * ((PaddleSize.MAIN_GRIP_OFFSET - PaddleSize.HEAD_OFFSET) + offset)
	# The paddle goes around the body, never through it (around_body.gd; the keys never move).
	head += AroundBody.shift(pose, hand, head, hand_a, paddle_head(from_pose), hand_b, paddle_head(to_pose), t)
	pose.paddle_forehand_mul = head.x
	pose.paddle_y_offset = head.y
	pose.paddle_forward_mul = - head.z
	if _support_mode(from_pose) != _support_mode(to_pose):



		if t <= 0.0:
			pose.left_hand_mode = _support_mode(from_pose)
		elif t >= 1.0:
			pose.left_hand_mode = _support_mode(to_pose)
		else:
			var support: Vector3 = support_wrist_offset(from_pose).lerp(support_wrist_offset(to_pose), t)
			var support_side: float = 1.0 if pose.paddle_hand == 1 else -1.0
			var free_origin: = Vector3(0.15 * support_side, 0.15, -0.55)
			var free_offset: Vector3 = support - free_origin
			pose.left_hand_mode = 4
			if pose.paddle_hand == 1: pose.right_hand_offset = Vector3(free_offset.x, free_offset.y, - free_offset.z)
			else: pose.left_hand_offset = Vector3(free_offset.x, free_offset.y, - free_offset.z)



	pose.set_meta("support_grip_weight", lerpf(support_grip_weight(from_pose), support_grip_weight(to_pose), t))
	pose.set_meta("visual_locomotion_weight", lerpf(locomotion_weight(from_pose), locomotion_weight(to_pose), t))
	pose.set_meta("travel_locomotion_weight",lerpf(float(from_pose.get_meta("travel_locomotion_weight",0.0)),float(to_pose.get_meta("travel_locomotion_weight",0.0)),t))
	if bool(from_pose.get_meta("travel_paddle_follow",false)) or bool(to_pose.get_meta("travel_paddle_follow",false)):
		pose.set_meta("travel_paddle_follow",true)



	if from_pose.has_meta("visual_wrist_lag_deg") or to_pose.has_meta("visual_wrist_lag_deg"):
		var lag: float = lerpf(float(from_pose.get_meta("visual_wrist_lag_deg", 0.0)), float(to_pose.get_meta("visual_wrist_lag_deg", 0.0)), t)
		if lag > 1e-05: pose.set_meta("visual_wrist_lag_deg", clampf(lag, 0.0, 6.0))
	return pose

## Paddle head and grip of a pose in the canonical blend frame (x forehand, y up from the root,
## +z away from the net), as blend_pose computes them.
static func paddle_head(pose: PostureDefinition) -> Vector3:
	return Vector3(pose.paddle_forehand_mul, pose.paddle_y_offset, - pose.paddle_forward_mul)

static func paddle_hand(pose: PostureDefinition) -> Vector3:
	return paddle_head(pose) + Rotation.unspun_basis(pose) * ((PaddleSize.MAIN_GRIP_OFFSET - PaddleSize.HEAD_OFFSET) + _main_offset(pose))

static func _main_offset(pose: PostureDefinition) -> Vector3:
	return pose.left_hand_offset if pose.paddle_hand == 1 else pose.right_hand_offset

static func _support_mode(pose: PostureDefinition) -> int:
	if pose.left_hand_mode != 0: return pose.left_hand_mode
	return 1 if pose.posture_id in [2, 7, 9, 11, 14, 17, 19, 3, 4, 12, 20] else 4

static func support_grip_weight(pose: PostureDefinition) -> float:
	return clampf(float(pose.get_meta("support_grip_weight", 1.0 if _support_mode(pose) == 1 else 0.0)), 0.0, 1.0)

static func locomotion_weight(pose: PostureDefinition) -> float:
	return clampf(float(pose.get_meta("visual_locomotion_weight", 1.0 if pose.posture_id in [12, 20] else 0.0)), 0.0, 1.0)

static func support_hand_offset(pose: PostureDefinition) -> Vector3:
	var offset: Vector3 = pose.right_hand_offset if pose.paddle_hand == 1 else pose.left_hand_offset
	var side: float = 1.0 if pose.paddle_hand == 1 else -1.0
	var point: = Vector3(0.15 * side, 0.15, -0.55)
	match _support_mode(pose):
		1:
			point = canonical_transform(pose) * (PaddleSize.SUPPORT_GRIP_OFFSET + Vector3.UP * pose.support_grip_slide_m)
		2: point = Vector3(0.2 * side, 0.45, -0.2)
		3: point = Vector3(0, 1.05, -0.15)
	return point + Vector3(offset.x, offset.y, - offset.z)



static func support_wrist_offset(pose: PostureDefinition) -> Vector3:
	var point: Vector3 = support_hand_offset(pose)
	if _support_mode(pose) != 1: return point
	var is_left: bool = pose.paddle_hand == 0
	var socket: Vector3 = HandModel.WRIST_SOCKET
	if is_left: socket.x = - socket.x
	var paddle: Basis = canonical_transform(pose).basis
	return point + GripFrame.basis(paddle, is_left, pose.support_grip_rotation_deg - pose.paddle_in_hand_rotation_deg) * socket

static func rotate_guard(pose: PostureDefinition, body_yaw: float) -> PostureDefinition:
	var result: PostureDefinition = pose.lerp_with(pose, 0.0)
	var turn: = Basis(Vector3.UP, deg_to_rad( - body_yaw))
	var angles: Vector3 = pose.resolve_paddle_rotation_deg(-1.0, -1.0) * (PI / 180.0)
	var basis: Basis = turn * Basis(Vector3.RIGHT, angles.x) * Basis(Vector3.UP, angles.y) * Basis(Vector3.FORWARD, angles.z)
	result.paddle_pitch_base_deg = rad_to_deg(atan2( - basis.z.y, basis.z.z))
	result.paddle_yaw_base_deg = rad_to_deg(asin(clampf(basis.z.x, -1.0, 1.0)))
	result.paddle_roll_base_deg = rad_to_deg(atan2(basis.y.x, basis.x.x))
	if absf(basis.z.x) > 0.999999:
		result.paddle_pitch_base_deg = rad_to_deg(signf(basis.z.x) * atan2(basis.x.y, basis.y.y))
		result.paddle_roll_base_deg = 0.0
	result.paddle_pitch_signed_deg = 0.0
	result.paddle_yaw_signed_deg = 0.0
	result.paddle_roll_signed_deg = 0.0
	var head: Vector3 = turn * Vector3(pose.paddle_forehand_mul, pose.paddle_y_offset, - pose.paddle_forward_mul)
	result.paddle_forehand_mul = head.x
	result.paddle_y_offset = head.y
	result.paddle_forward_mul = - head.z



	if _support_mode(pose) != 1:
		var support: Vector3 = turn * support_wrist_offset(pose)
		var side: float = 1.0 if pose.paddle_hand == 1 else -1.0
		var offset: Vector3 = support - Vector3(0.15 * side, 0.15, - 0.55)
		result.left_hand_mode = 4
		if pose.paddle_hand == 1: result.right_hand_offset = Vector3(offset.x, offset.y, - offset.z)
		else: result.left_hand_offset = Vector3(offset.x, offset.y, - offset.z)
		result.set_meta("support_grip_weight", support_grip_weight(pose))



	for right in [true, false]:
		var pole: Vector3 = pose.right_elbow_pole if right else pose.left_elbow_pole
		if pole.length_squared() <= 1e-08: continue
		var rotated: Vector3 = turn * Vector3(pole.x, pole.y, - pole.z)
		if right: result.right_elbow_pole = Vector3(rotated.x, rotated.y, - rotated.z)
		else: result.left_elbow_pole = Vector3(rotated.x, rotated.y, - rotated.z)
	result.body_yaw_deg = body_yaw
	# Explicit guard frame, independent of paddle face/grip orientation.
	result.set_meta("ready_facing_yaw_deg", body_yaw)
	result.right_foot_yaw_deg += body_yaw
	result.left_foot_yaw_deg += body_yaw
	return result
