extends RefCounted
const BodyPose = preload("res://scripts/stroke_body_pose.gd")
## One authored path for the editor, paddle ghosts and procedural release animation.

static func endpoint(def: PostureDefinition, stage: int) -> PostureDefinition:
	var pose: PostureDefinition = def.lerp_with(def, 0.0)
	if stage == 1:
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
	pose.weight_shift = -def.charge_back_foot_load if stage == 0 else def.ft_front_foot_load
	if stage == 0:
		pose.body_yaw_deg += def.charge_body_rotation_deg
	var body: Resource = def.windup_body if stage == 0 else def.follow_through_body
	if body and body.has_method("apply_to"):
		body.apply_to(pose)
	return pose

static func sample(def: PostureDefinition, progress: float) -> PostureDefinition:
	var t: float = clampf(progress, 0.0, 1.0)
	var windup: PostureDefinition = endpoint(def, 0)
	var finish: PostureDefinition = endpoint(def, 2)
	var a: PostureDefinition = windup if t <= 0.5 else def
	var b: PostureDefinition = def if t <= 0.5 else finish
	var u: float = t * 2.0 if t <= 0.5 else (t - 0.5) * 2.0
	var pose: PostureDefinition = a.lerp_with(b, u)
	var p0 := Vector3(windup.paddle_forehand_mul, windup.paddle_y_offset, windup.paddle_forward_mul)
	var p1 := Vector3(def.paddle_forehand_mul, def.paddle_y_offset, def.paddle_forward_mul)
	var p2 := Vector3(finish.paddle_forehand_mul, finish.paddle_y_offset, finish.paddle_forward_mul)
	var start: Vector3 = p0 if t <= 0.5 else p1
	var end: Vector3 = p1 if t <= 0.5 else p2
	# Shared contact tangent merges both segments without missing the contact keyframe.
	var tangent := (p2 - p0) * 0.5
	var m0: Vector3 = p1 - p0 if t <= 0.5 else tangent
	var m1: Vector3 = tangent if t <= 0.5 else p2 - p1
	var curved := (2*u*u*u - 3*u*u + 1)*start + (u*u*u - 2*u*u + u)*m0 + (-2*u*u*u + 3*u*u)*end + (u*u*u - u*u)*m1
	var position: Vector3 = start.lerp(end, u).lerp(curved, def.swing_path_blend)
	pose.paddle_forehand_mul = position.x
	pose.paddle_y_offset = position.y
	pose.paddle_forward_mul = position.z
	# Interpolate angles across the shortest wrap instead of spinning through 360 degrees.
	pose.paddle_pitch_base_deg = rad_to_deg(lerp_angle(deg_to_rad(a.paddle_pitch_base_deg), deg_to_rad(b.paddle_pitch_base_deg), u))
	pose.paddle_yaw_base_deg = rad_to_deg(lerp_angle(deg_to_rad(a.paddle_yaw_base_deg), deg_to_rad(b.paddle_yaw_base_deg), u))
	pose.paddle_roll_base_deg = rad_to_deg(lerp_angle(deg_to_rad(a.paddle_roll_base_deg), deg_to_rad(b.paddle_roll_base_deg), u))
	return pose

static func world_transform(player, pose: PostureDefinition) -> Transform3D:
	var rotation: Vector3 = pose.resolve_paddle_rotation_deg(player._get_swing_sign(), player._get_forward_axis().z)
	var basis := Basis(Vector3.RIGHT, deg_to_rad(rotation.x)) * Basis(Vector3.UP, deg_to_rad(rotation.y)) * Basis(Vector3.FORWARD, deg_to_rad(rotation.z))
	var head: Vector3 = player.global_position + pose.resolve_paddle_offset(player._get_forehand_axis(), player._get_forward_axis())
	head = PaddleReach.clamp_head_with_floor(head, BodyPose.shoulder_world(player, pose), player.COURT_FLOOR_Y + pose.paddle_floor_clearance)
	return Transform3D(basis, head - basis.y * 0.4)
static func release_progress(def: PostureDefinition, phase: int, factor: float) -> float:
	var transition: Tween.TransitionType = Tween.TRANS_EXPO
	if def.ft_ease_curve == 1: transition = Tween.TRANS_QUAD
	elif def.ft_ease_curve == 2: transition = Tween.TRANS_SINE
	var easing: Tween.EaseType = Tween.EASE_IN_OUT if def.ft_ease_curve == 2 else Tween.EASE_OUT
	var eased: float = Tween.interpolate_value(0.0, 1.0, clampf(factor, 0.0, 1.0), 1.0, transition, easing)
	return eased * 0.5 + (0.5 if phase == 1 else 0.0)
