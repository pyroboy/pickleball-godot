extends RefCounted




const Path = preload("res://scripts/stroke_swing_path.gd")

## Only for a left hand left on Auto: a hand set to Free in Pose Studio keeps its posed place,
## before and during the swing (the user's poses win over this reach-and-tuck).
static func eligible(contact: PostureDefinition, compact: bool) -> bool:
	return not compact and contact.family == 0 and contact.height_tier == 2 and contact.left_hand_mode == 0

static func tracking_target(contact: PostureDefinition) -> Vector3:

	return Vector3(clampf(contact.paddle_forehand_mul * 0.62, -0.28, 0.28), 
		clampf(contact.paddle_y_offset + 0.06, 0.1, 0.38), 
		clampf(contact.paddle_forward_mul * 0.78, 0.24, 0.38))

static func tuck_target(contact: PostureDefinition) -> Vector3:
	var side: float = 1.0 if contact.paddle_hand == 1 else -1.0
	return Vector3(side * 0.24, 0.18, 0.18)

static func _apply(pose: PostureDefinition, target: Vector3, weight: float) -> void :
	if weight <= 0.0: return
	var current: Vector3 = Path.support_wrist_offset(pose)
	current.z = - current.z
	var point: Vector3 = current.lerp(target, clampf(weight, 0.0, 1.0))
	var side: float = 1.0 if pose.paddle_hand == 1 else -1.0
	var offset: = point - Vector3(side * 0.15, 0.15, 0.55)
	pose.set_meta("support_grip_weight", Path.support_grip_weight(pose) * (1.0 - clampf(weight, 0.0, 1.0)))
	pose.left_hand_mode = 4
	if pose.paddle_hand == 1: pose.right_hand_offset = offset
	else: pose.left_hand_offset = offset

static func prepare(pose: PostureDefinition, contact: PostureDefinition, time_to_contact: float, urgency: float, compact: bool) -> void :
	if not eligible(contact, compact): return
	var clearing: float = 1.0 - smoothstep(0.06, 0.24, maxf(time_to_contact, 0.0))
	_apply(pose, tracking_target(contact).lerp(tuck_target(contact), clearing), urgency)

static func swing(pose: PostureDefinition, contact: PostureDefinition, progress: float, charge: float, compact: bool) -> void :
	if not eligible(contact, compact): return
	var amount: float = smoothstep(0.08, 0.38, clampf(charge, 0.0, 1.0))
	var t: float = clampf(progress, 0.0, 1.0)


	var clearing: float = smoothstep(0.0, 0.3, t)
	var release: float = 1.0 - smoothstep(0.6, 1.0, t)
	_apply(pose, tracking_target(contact).lerp(tuck_target(contact), clearing), amount * release)
