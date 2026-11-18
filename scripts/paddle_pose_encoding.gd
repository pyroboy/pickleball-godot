extends RefCounted
## Encode an already observed finite paddle transform in the pose's own frame.
## Invert optional travel and in-hand overlays exactly once. Reach/floor limits
## remain authoritative: callers must verify the resulting world round trip.
const Path = preload("res://scripts/stroke_swing_path.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Rotation = preload("res://scripts/paddle_rotation.gd")
const Dimensions = preload("res://scripts/paddle_dimensions.gd")

static func encode(player, source: PostureDefinition, displayed: Transform3D) -> PostureDefinition:
	var pose: PostureDefinition = source.duplicate(false)
	var raw := displayed
	if bool(pose.get_meta("travel_paddle_follow", false)) and Body.locomotion_weight(player, pose) > 0.00001:
		var pivot: Transform3D = Body.untranslated_pivot_transform(player, pose)
		var travel: Transform3D = (pivot * Body.torso_transform(player, pose, true)) * (pivot * Body.torso_transform(player, pose, false)).affine_inverse()
		raw.origin = player.global_position + travel.affine_inverse() * (raw.origin - player.global_position)
		raw.basis = travel.basis.inverse() * raw.basis
	raw = Path.remove_in_hand_transform(raw, pose)
	var stance := Basis(player._get_forehand_axis(), Vector3.UP, -player._get_forward_axis())
	Rotation.set_basis(pose, stance.inverse() * raw.basis)
	var head: Vector3 = stance.inverse() * (raw * Dimensions.HEAD_OFFSET - player.global_position)
	pose.paddle_forehand_mul = head.x
	pose.paddle_y_offset = head.y
	pose.paddle_forward_mul = -head.z
	return pose
