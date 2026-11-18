extends RefCounted


const Body = preload("res://scripts/stroke_body_pose.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Orientation = preload("res://scripts/stroke_preparation_orientation.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const Hand = preload("res://scripts/articulated_hand.gd")
const Grip = preload("res://scripts/paddle_grip_frame.gd")
const Size = preload("res://scripts/paddle_dimensions.gd")
const LINK: = 0.35
const REFERENCE_BALL_Y: = - 0.275195205675167
const REFERENCE_CROUCH: = 0.11095504760742
const CONTACT_BASIS: = Basis(Vector3(0.621995834055, 0.782315873709, 0.033206545688), Vector3(0.419523359691, - 0.297142441249, - 0.857733304383), Vector3( - 0.661151304393, 0.547437551211, - 0.513021189554))
const CONTACT_POLE: = Vector3(0.376436627179, 0.035804918387, 0.079752657634)
class CanonicalAxes extends RefCounted:
	var global_transform: = Transform3D.IDENTITY
	func _get_forehand_axis() -> Vector3: return Vector3.RIGHT
	func _get_forward_axis() -> Vector3: return Vector3.FORWARD
static var _axes: = CanonicalAxes.new()
static var _anatomical: Basis = _landmark_frame()

static func _landmark_frame() -> Basis:

	var x: Vector3 = (Hand._mcp_point(1) - Hand.WRIST_SOCKET).normalized()
	var y: Vector3 = Hand._mcp_point(0) - Hand._mcp_point(3)
	y = (y - x * y.dot(x)).normalized()
	return Basis(x, y, x.cross(y).normalized())

static func contact(pose: PostureDefinition, ball: Vector3) -> PostureDefinition:
	var down: float = REFERENCE_BALL_Y - ball.y
	pose.crouch_amount = REFERENCE_CROUCH + down
	pose.right_elbow_pole = CONTACT_POLE - Vector3.UP * down
	Orientation.set_canonical_basis(pose, CONTACT_BASIS)

	var offset: Vector3 = CONTACT_BASIS.z * (Size.HEAD_HALF_THICKNESS + 0.0375)
	pose.paddle_forehand_mul = ball.x - offset.x
	pose.paddle_y_offset = ball.y - offset.y
	pose.paddle_forward_mul = ball.z + offset.z
	return pose

static func _state(pose: PostureDefinition) -> Dictionary:
	var s: Vector3 = Body.shoulder_world(_axes, pose)
	var b: Basis = Orientation.canonical_basis(pose)
	var head: = Vector3(pose.paddle_forehand_mul, pose.paddle_y_offset, - pose.paddle_forward_mul)
	var hand: Basis = Grip.basis(b, false, pose.main_grip_rotation_deg)
	var w: Vector3 = head + b * (Size.MAIN_GRIP_OFFSET + pose.right_hand_offset - Size.HEAD_OFFSET) + hand * Hand.WRIST_SOCKET
	var pole: = Vector3(pose.right_elbow_pole.x, pose.right_elbow_pole.y, - pose.right_elbow_pole.z)
	pole = s + Basis.from_euler(pose.right_shoulder_rotation_deg * (PI / 180.0)) * (pole - s)
	pole = Anatomy.conditioned_pole(s, w, pole, hand * _anatomical.x, LINK, LINK)
	var span: Vector3 = w - s
	var distance: float = maxf(span.length(), 1e-05)
	var axis: Vector3 = span / distance
	var radial: Vector3 = pole - s - axis * (pole - s).dot(axis)
	if radial.length_squared() < 1e-08: radial = Vector3.UP - axis * axis.y
	radial = radial.normalized()
	var e: Vector3 = s + axis * (distance * 0.5) + radial * sqrt(maxf(0.0, LINK * LINK - distance * distance * 0.25))
	var upper: Vector3 = (e - s).normalized()
	var fore: Vector3 = (w - e).normalized()
	var bend: float = acos(clampf(upper.dot(fore), -1.0, 1.0))
	var transverse: Vector3 = (fore - upper * fore.dot(upper)).normalized()
	if transverse.length_squared() < 1e-05: transverse = radial
	var frame: = Basis(upper, transverse, upper.cross(transverse).normalized()).orthonormalized()
	var channels: Dictionary = Anatomy.decompose(Anatomy.forearm_reference(s, e, w, Vector3.UP, false), hand * _anatomical)
	return {"frame": frame, "bend": bend, "flex": channels.flexion_deg, "deviation": channels.radial_deviation_deg, "axial": channels.forearm_axial_deg}

static func blend(start: PostureDefinition, end: PostureDefinition, progress: float, guide_pitch_deg: float = 0.0, guide_outward_deg: float = 0.0) -> PostureDefinition:
	var t: float = clampf(progress, 0.0, 1.0)
	if t <= 0.0: return start.lerp_with(start, 0.0)
	if t >= 1.0: return end.lerp_with(end, 0.0)
	var a: Dictionary = _state(start); var b: Dictionary = _state(end)
	var pose: PostureDefinition = Path.blend_pose(start, end, t)
	var s: Vector3 = Body.shoulder_world(_axes, pose)
	var frame: Basis = a.frame.slerp(b.frame, t).orthonormalized()


	frame = Basis(Vector3.BACK, deg_to_rad(guide_outward_deg)) * Basis(Vector3.RIGHT, deg_to_rad(guide_pitch_deg)) * frame
	var bend: float = lerpf(a.bend, b.bend, t)
	var e: Vector3 = s + frame.x * LINK
	var w: Vector3 = e + (frame.x * cos(bend) + frame.y * sin(bend)) * LINK
	var flex: float = deg_to_rad(lerpf(a.flex, b.flex, t))
	var deviation: float = deg_to_rad(lerpf(a.deviation, b.deviation, t))
	var axial: float = lerp_angle(deg_to_rad(a.axial), deg_to_rad(b.axial), t)
	var hand: Basis = Anatomy.forearm_reference(s, e, w, Vector3.UP, false) * Basis(Vector3.RIGHT, axial) * Basis(Vector3.UP, flex) * Basis(Vector3.BACK, deviation) * _anatomical.inverse()
	var paddle: Basis = hand * Grip.basis(Basis.IDENTITY, false, pose.main_grip_rotation_deg).inverse()
	var head: Vector3 = w - hand * Hand.WRIST_SOCKET + paddle * (Size.HEAD_OFFSET - Size.MAIN_GRIP_OFFSET - pose.right_hand_offset)
	Orientation.set_canonical_basis(pose, paddle)
	pose.paddle_forehand_mul = head.x;pose.paddle_y_offset = head.y;pose.paddle_forward_mul = - head.z
	var pole: Vector3 = s + Basis.from_euler(pose.right_shoulder_rotation_deg * (PI / 180.0)).inverse() * (e - s)
	pose.right_elbow_pole = Vector3(pole.x, pole.y, - pole.z)
	return pose



static func recover_to_ready(from: PostureDefinition, to: PostureDefinition, progress: float) -> PostureDefinition:
	var t: float = clampf(progress, 0.0, 1.0)
	if t >= 1.0: return to.lerp_with(to, 0.0)
	if from.paddle_hand != 0 or to.paddle_hand != 0: return Path.blend_pose(from, to, smoothstep(0.0, 1.0, t))
	var pose: PostureDefinition
	if t <= 0.5:
		var waiting: PostureDefinition = to.duplicate(true)
		waiting.left_hand_mode = 4;waiting.left_hand_offset = from.left_hand_offset;waiting.left_elbow_pole = from.left_elbow_pole;waiting.set_meta("support_grip_weight", 0.0)
		pose = blend(from, waiting, smoothstep(0.0, 0.5, t))
		pose.left_hand_mode = 4;pose.left_hand_offset = from.left_hand_offset;pose.left_elbow_pole = from.left_elbow_pole;pose.set_meta("support_grip_weight", 0.0)
		pose.set_meta("serve_recovery_open", 1.0);pose.set_meta("serve_recovery_relaxed", 1.0 - smoothstep(0.0, 0.5, t))
		return pose
	pose = to.duplicate(true)
	var final: Vector3 = Path.support_wrist_offset(to)
	var outside: Vector3 = final - Orientation.canonical_basis(to).z * 0.1
	var wrist: Vector3
	if t < 0.7:
		var u: float = smoothstep(0.5, 0.7, t)
		wrist = Path.support_wrist_offset(from).lerp(outside, u)
		pose.left_elbow_pole = from.left_elbow_pole.lerp(to.left_elbow_pole, u)
		pose.set_meta("support_grip_weight", u)
	elif t < 0.88:
		wrist = outside.lerp(final, smoothstep(0.7, 0.88, t))
		pose.set_meta("support_grip_weight", 1.0)
	else:
		pose.set_meta("support_grip_weight", 1.0)
		pose.set_meta("serve_recovery_open", 1.0 - smoothstep(0.88, 1.0, t));pose.set_meta("serve_recovery_relaxed", 0.0)
		return pose
	pose.left_hand_mode = 4
	var offset: Vector3 = wrist - Vector3( - 0.15, 0.15, - 0.55)
	pose.left_hand_offset = Vector3(offset.x, offset.y, - offset.z)
	pose.set_meta("serve_recovery_open", 1.0);pose.set_meta("serve_recovery_relaxed", 0.0)
	return pose
