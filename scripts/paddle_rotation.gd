extends RefCounted
## Paddle-only angle representation and shortest physical-orientation blending.
## Never edits position, body, elbow, timing or grip-seat channels.
const BASE := ["paddle_pitch_base_deg", "paddle_yaw_base_deg", "paddle_roll_base_deg"]
const SIGNED := ["paddle_pitch_signed_deg", "paddle_yaw_signed_deg", "paddle_roll_signed_deg"]
const GRIP := ["main_grip_rotation_deg", "paddle_in_hand_rotation_deg", "support_grip_rotation_deg"]
const DELTAS := ["charge_paddle_rotation_deg", "ft_paddle_rotation_deg"]

static func degrees(value: float) -> float:
	# Avoid perturbing already normalized authored decimals.
	if not is_finite(value) or (value >= -180.0 and value < 180.0): return value
	return wrapf(value, -180.0, 180.0)

static func vector(value: Vector3) -> Vector3:
	return Vector3(degrees(value.x), degrees(value.y), degrees(value.z))

static func field_value(field: String, value):
	if (field in BASE or field in SIGNED or field in GRIP) and (value is float or value is int): return degrees(float(value))
	if field in DELTAS and value is Vector3: return vector(value)
	return value

static func normalize_channels(pose: Resource) -> bool:
	var changed := false
	for field in BASE + SIGNED + GRIP + DELTAS:
		if pose.get(field) == null: continue
		var before = pose.get(field)
		var after = field_value(field, before)
		if before != after: pose.set(field, after); changed = true
	return changed

static func normalize_pose(pose: Resource) -> bool:
	var changed := normalize_channels(pose)
	for field in ["windup_body", "follow_through_body"]:
		var body = pose.get(field)
		if body == null: continue
		# Partial keyframes remain partial; inherited fields are never materialized.
		for key in body.values:
			var before = body.values[key]
			var after = field_value(key, before)
			if before != after: body.values[key] = after; changed = true
	return changed

static func angle_lerp(a: float, b: float, t: float) -> float:
	return degrees(degrees(a) + degrees(degrees(b) - degrees(a)) * t)

static func vector_lerp(a: Vector3, b: Vector3, t: float) -> Vector3:
	return Vector3(angle_lerp(a.x,b.x,t), angle_lerp(a.y,b.y,t), angle_lerp(a.z,b.z,t))

static func basis(angles: Vector3) -> Basis:
	var a := vector(angles) * (PI / 180.0)
	return Basis(Vector3.RIGHT,a.x) * Basis(Vector3.UP,a.y) * Basis(Vector3.FORWARD,a.z)

static func euler(frame: Basis) -> Vector3:
	# XYZ about Right, Up, Forward (-Z), matching the authored paddle convention.
	var b := frame.orthonormalized()
	var cos_y := Vector2(b.z.y,b.z.z).length()
	var result := Vector3(atan2(-b.z.y,b.z.z), atan2(b.z.x,cos_y), atan2(b.y.x,b.x.x))
	if cos_y < .000001:
		result.x = signf(b.z.x) * atan2(b.x.y,b.y.y)
		result.z = 0.0
	return vector(result * (180.0 / PI))

static func set_basis(pose, frame: Basis) -> void:
	var angles := euler(frame)
	for axis in range(3):
		pose.set(BASE[axis], angles[axis])
		pose.set(SIGNED[axis], 0.0)

static func unspun_basis(pose, swing_sign: float = -1.0, fwd_sign: float = -1.0) -> Basis:
	return basis(pose.resolve_paddle_rotation_deg(swing_sign,fwd_sign))

static func displayed_basis(pose, swing_sign: float = -1.0, fwd_sign: float = -1.0) -> Basis:
	return unspun_basis(pose,swing_sign,fwd_sign) * Basis(Vector3.UP,deg_to_rad(degrees(pose.paddle_in_hand_rotation_deg)))

static func shortest(a: Basis, b: Basis, t: float) -> Basis:
	if t <= 0.0: return a
	if t >= 1.0: return b
	return Basis(a.orthonormalized().get_rotation_quaternion().slerp(b.orthonormalized().get_rotation_quaternion(),t))

static func blend_into(pose, a, b, t: float, swing_sign: float = -1.0, fwd_sign: float = -1.0) -> void:
	# Endpoints retain original sign-source fields. Intermediate poses are baked
	# in the canonical stance used by preview/gameplay, after resolving signs.
	if t <= 0.0 or t >= 1.0: return
	var display := shortest(displayed_basis(a,swing_sign,fwd_sign),displayed_basis(b,swing_sign,fwd_sign),t)
	set_basis(pose,display * Basis(Vector3.UP,deg_to_rad(-pose.paddle_in_hand_rotation_deg)))
