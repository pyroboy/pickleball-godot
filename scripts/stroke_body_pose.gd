extends RefCounted
## Visible primitive rig transforms, also used to calculate the swing's shoulder reach.

static func pivot_transform(player, def) -> Transform3D:
	var sign: float = player._get_swing_sign()
	var basis := Basis.from_euler(Vector3(def.body_pitch_deg * sign, def.body_yaw_deg * sign, def.body_roll_deg) * (PI / 180.0))
	var origin: Vector3 = player._get_forward_axis() * def.weight_shift * 0.10 + Vector3.DOWN * def.crouch_amount
	return Transform3D(basis, origin)

static func torso_transform(player, def) -> Transform3D:
	var sign: float = player._get_swing_sign()
	var basis := Basis.from_euler(Vector3((28.0 + def.torso_pitch_deg + def.spine_curve_deg) * sign, (def.hip_yaw_deg + def.torso_yaw_deg) * sign, def.torso_roll_deg) * (PI / 180.0))
	return Transform3D(basis, Vector3(0, 0.05, 0))

static func shoulder_world(player, def) -> Vector3:
	var side: float = -1.0 if def.paddle_hand == 1 else 1.0
	var local: Vector3 = player._get_forehand_axis() * side * 0.18 + Vector3.UP * 0.10
	return player.global_transform * pivot_transform(player, def) * torso_transform(player, def) * local

static func apply(player, def) -> void:
	if player.body_pivot == null: return
	player.body_pivot.transform = pivot_transform(player, def)
	var torso: Node3D = player.body_pivot.get_node_or_null("TorsoMesh")
	if torso:
		torso.transform = torso_transform(player, def)
		var head: Node3D = torso.get_node_or_null("HeadMesh")
		if head:
			head.rotation_degrees = Vector3(def.head_pitch_deg * player._get_swing_sign(), def.head_yaw_deg * player._get_swing_sign(), 0)
	var hips: Node3D = player.body_pivot.get_node_or_null("HipsMesh")
	if hips: hips.rotation_degrees.y = def.hip_yaw_deg * player._get_swing_sign()
	for side in [1, -1]:
		var arm = player.right_arm_node if side == 1 else player.left_arm_node
		if arm:
			arm.position = torso_transform(player, def) * (player._get_forehand_axis() * side * 0.18 + Vector3.UP * 0.10)
			arm.rotation_degrees = def.right_shoulder_rotation_deg if side == 1 else def.left_shoulder_rotation_deg
		var leg = player.right_leg_node if side == 1 else player.left_leg_node
		if leg:
			leg.position = Vector3(0, -0.15, 0) + Basis(Vector3.UP, deg_to_rad(def.hip_yaw_deg * player._get_swing_sign())) * player._get_forehand_axis() * side * 0.12
