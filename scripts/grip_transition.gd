extends RefCounted


const Joint = preload("res://scripts/serve_joint_motion.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Orientation = preload("res://scripts/stroke_preparation_orientation.gd")
const VALIDATED: = false


const BETA_PREVIEW_ENABLED: = true
const OUTSIDE_DISTANCE: = 0.1
static func _profile(p: PostureDefinition) -> int:
	if p == null or p.paddle_hand != 0 or p.left_hand_mode != 1: return -1
	if not is_equal_approx(p.main_grip_rotation_deg, -30.0): return -1
	if not p.right_hand_offset.is_equal_approx(Vector3(0, - 0.05, 0)): return -1
	if not is_equal_approx(p.support_grip_slide_m, 0.00825) or not p.left_hand_offset.is_zero_approx(): return -1
	if not is_equal_approx(p.support_index_closure, 0.4): return -1
	var bevel: float = wrapf(p.support_grip_rotation_deg, -180.0, 180.0)
	if is_equal_approx(bevel, -120.0) and is_zero_approx(p.support_grip_style): return 195
	if is_zero_approx(bevel) and is_equal_approx(p.support_grip_style, 1.0): return 315
	return -1
static func supports(from: PostureDefinition, to: PostureDefinition) -> bool:
	return (VALIDATED or BETA_PREVIEW_ENABLED) and _profile(from) >= 0 and _profile(to) >= 0 and _profile(from) != _profile(to)
static func supports_both_joined(from: PostureDefinition, to: PostureDefinition) -> bool:
	return supports(from, to)
static func _outside(pose: PostureDefinition) -> Vector3:
	var sign: float = -1.0 if _profile(pose) == 195 else 1.0
	var distance: float = OUTSIDE_DISTANCE
	return Path.support_wrist_offset(pose) + Orientation.canonical_basis(pose).z * (sign * distance)
static func _free_wrist(pose: PostureDefinition, wrist: Vector3, weight: float) -> void :
	pose.left_hand_mode = 4
	var offset: Vector3 = wrist - Vector3( - 0.15, 0.15, - 0.55)
	pose.left_hand_offset = Vector3(offset.x, offset.y, - offset.z)
	pose.set_meta("support_grip_weight", weight)
static func sample(from: PostureDefinition, to: PostureDefinition, progress: float) -> PostureDefinition:
	var t: float = clampf(progress, 0.0, 1.0)
	if t <= 0.0: return from.lerp_with(from, 0.0)
	if t >= 1.0: return to.lerp_with(to, 0.0)
	var pose: PostureDefinition
	var open_weight: = 1.0
	if t < 0.1:
		pose = from.lerp_with(from, 0.0)
		open_weight = smoothstep(0.0, 0.1, t)
	elif t < 0.22:
		pose = from.lerp_with(from, 0.0)
		_free_wrist(pose, Path.support_wrist_offset(from).lerp(_outside(from), smoothstep(0.1, 0.22, t)), 1.0)
	elif t < 0.3:
		pose = from.lerp_with(from, 0.0)
		_free_wrist(pose, _outside(from), 1.0 - smoothstep(0.22, 0.3, t))
	elif t < 0.65:
		var u: float = smoothstep(0.3, 0.65, t)
		pose = Joint.blend(from, to, u)
		_free_wrist(pose, _outside(from).lerp(_outside(to), u), 0.0)
	elif t < 0.75:
		pose = to.lerp_with(to, 0.0)
		_free_wrist(pose, _outside(to), smoothstep(0.65, 0.75, t))
	elif t < 0.9:
		pose = to.lerp_with(to, 0.0)
		_free_wrist(pose, _outside(to).lerp(Path.support_wrist_offset(to), smoothstep(0.75, 0.9, t)), 1.0)
	else:
		pose = to.lerp_with(to, 0.0)
		open_weight = 1.0 - smoothstep(0.9, 1.0, t)


	if t > 0.22 and t < 0.75:
		var detour: float = pow(sin(PI * (t - 0.22) / (0.75 - 0.22)), 2.0)
		pose.left_hand_offset += Vector3(0, - 0.03, 0.18) * detour
	pose.set_meta("grip_transition_open", open_weight)
	return pose
