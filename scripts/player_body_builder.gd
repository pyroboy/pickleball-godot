class_name PlayerBodyBuilder extends Node

var _player

func build(paddle_color: Color) -> void:
	_player.name = "Player" + str(_player.player_num)

	for child_name in ["MeshInstance3D", "Paddle", "CollisionShape3D", "Skeleton3D"]:
		var existing = _player.get_node_or_null(child_name)
		if existing:
			existing.queue_free()

	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = 0.2
	shape.height = 1.0
	col.shape = shape
	col.position = Vector3(0, 0.5, 0)
	_player.add_child(col)
	_player.collision_layer = 2
	_player.collision_mask = 1

	_player.body_pivot = Node3D.new()
	_player.body_pivot.name = "BodyPivot"
	_player.add_child(_player.body_pivot)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = paddle_color

	var h: float = -0.15
	var hips_y: float = h - 0.04
	var chest_y: float = h + 0.20
	var shoulder_y: float = h + 0.30
	var head_y: float = h + 0.48
	var chest_forward_lean: float = 28.0

	# Chest
	var chest_inst: MeshInstance3D = MeshInstance3D.new()
	var chest_mesh: BoxMesh = BoxMesh.new()
	chest_mesh.size = Vector3(0.36, 0.32, 0.2)
	chest_inst.mesh = chest_mesh
	chest_inst.material_override = mat
	chest_inst.position = Vector3(0.0, chest_y, 0.0)
	chest_inst.rotation.x = deg_to_rad(chest_forward_lean) * _player._get_swing_sign()
	_player.body_pivot.add_child(chest_inst)

	# Head
	var head_inst: MeshInstance3D = MeshInstance3D.new()
	var head_mesh: SphereMesh = SphereMesh.new()
	head_mesh.radius = 0.12
	head_mesh.height = 0.24
	head_inst.mesh = head_mesh
	var skin_mat: StandardMaterial3D = StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.87, 0.72, 0.58)
	head_inst.material_override = skin_mat
	head_inst.position = Vector3(0.0, head_y - chest_y, 0.0)
	chest_inst.add_child(head_inst)

	# Paddle
	var paddle_scene = preload("res://scenes/paddle.tscn")
	var paddle: StaticBody3D = paddle_scene.instantiate()
	paddle.name = "Paddle"
	_player.body_pivot.add_child(paddle)
	_player.paddle_node = paddle

	var head_part := paddle.get_node_or_null("Head") as MeshInstance3D
	var top_curve := paddle.get_node_or_null("Head/HeadTopCurve") as MeshInstance3D
	var bottom_curve := paddle.get_node_or_null("Head/HeadBottomCurve") as MeshInstance3D
	var paddle_mat: StandardMaterial3D = StandardMaterial3D.new()
	paddle_mat.albedo_color = Color(1, 0.85, 0.2)
	paddle_mat.roughness = 0.4
	if head_part: head_part.material_override = paddle_mat
	if top_curve: top_curve.material_override = paddle_mat
	if bottom_curve: bottom_curve.material_override = paddle_mat

	_player.paddle_hitbox = paddle.get_node("PaddleHitbox")
	# Wire hitbox to ai_brain (deferred — ai_brain created after build())
	_player.call_deferred("_wire_hitbox")

	# Hips
	var hips_inst: MeshInstance3D = MeshInstance3D.new()
	var hips_mesh: BoxMesh = BoxMesh.new()
	hips_mesh.size = Vector3(0.30, 0.14, 0.18)
	hips_inst.mesh = hips_mesh
	hips_inst.material_override = mat
	hips_inst.position = Vector3(0.0, hips_y, 0.0)
	_player.body_pivot.add_child(hips_inst)

	var shoe_mat: StandardMaterial3D = StandardMaterial3D.new()
	shoe_mat.albedo_color = Color(0.2, 0.2, 0.25)

	# Right leg
	var right_leg_scene = preload("res://scenes/right_leg.tscn")
	var right_leg = right_leg_scene.instantiate()
	right_leg.name = "RightLeg"
	_player.body_pivot.add_child(right_leg)
	_player.right_leg_node = right_leg
	right_leg.set_materials(mat, shoe_mat)
	right_leg.set_lengths(0.52, 0.50)
	right_leg.position = _player._get_forehand_axis() * 0.12 + Vector3(0.0, h, 0.0)

	# Left leg
	var left_leg_scene = preload("res://scenes/left_leg.tscn")
	var left_leg = left_leg_scene.instantiate()
	left_leg.name = "LeftLeg"
	_player.body_pivot.add_child(left_leg)
	_player.left_leg_node = left_leg
	left_leg.set_materials(mat, shoe_mat)
	left_leg.set_lengths(0.52, 0.50)
	left_leg.position = _player._get_forehand_axis() * -0.12 + Vector3(0.0, h, 0.0)

	# Arms
	var arm_scene = preload("res://scenes/right_arm.tscn")
	var right_arm = arm_scene.instantiate()
	right_arm.name = "RightArm"
	_player.body_pivot.add_child(right_arm)
	_player.right_arm_node = right_arm
	right_arm.set_materials(mat)
	right_arm.position = Vector3(0.0, shoulder_y, 0.0) + _player._get_forehand_axis() * 0.18

	var left_arm_scene = preload("res://scenes/left_arm.tscn")
	var left_arm = left_arm_scene.instantiate()
	left_arm.name = "LeftArm"
	_player.body_pivot.add_child(left_arm)
	_player.left_arm_node = left_arm
	left_arm.set_materials(mat)
	left_arm.position = Vector3(0.0, shoulder_y, 0.0) + _player._get_forehand_axis() * -0.18

	# Skeleton3D for Phase 3 full-body posture wiring
	_create_skeleton(hips_y)

func _create_skeleton(hips_y: float) -> void:
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	_player.add_child(skel)
	_player.skeleton = skel

	# Bone hierarchy for full-body posture control
	# Root: hips
	var hips_idx := _add_bone(skel, "Hips", -1, Vector3(0, hips_y, 0))

	# Spine chain
	var spine_idx := _add_bone(skel, "Spine", hips_idx, Vector3(0, 0.15, 0))
	var chest_idx := _add_bone(skel, "Chest", spine_idx, Vector3(0, 0.20, 0))

	# Head
	var neck_idx := _add_bone(skel, "Neck", chest_idx, Vector3(0, 0.18, 0))
	var head_idx := _add_bone(skel, "Head", neck_idx, Vector3(0, 0.10, 0))

	# Right arm chain
	var r_shoulder_idx := _add_bone(skel, "RightShoulder", chest_idx, Vector3(0.18, 0.12, 0))
	var r_upper_idx := _add_bone(skel, "RightUpperArm", r_shoulder_idx, Vector3(0.22, 0, 0))
	var r_fore_idx := _add_bone(skel, "RightForearm", r_upper_idx, Vector3(0.24, 0, 0))
	var r_hand_idx := _add_bone(skel, "RightHand", r_fore_idx, Vector3(0.10, 0, 0))

	# Left arm chain
	var l_shoulder_idx := _add_bone(skel, "LeftShoulder", chest_idx, Vector3(-0.18, 0.12, 0))
	var l_upper_idx := _add_bone(skel, "LeftUpperArm", l_shoulder_idx, Vector3(-0.22, 0, 0))
	var l_fore_idx := _add_bone(skel, "LeftForearm", l_upper_idx, Vector3(-0.24, 0, 0))
	var l_hand_idx := _add_bone(skel, "LeftHand", l_fore_idx, Vector3(-0.10, 0, 0))

	# Right leg chain
	var r_thigh_idx := _add_bone(skel, "RightThigh", hips_idx, Vector3(0.12, -0.08, 0))
	var r_shin_idx := _add_bone(skel, "RightShin", r_thigh_idx, Vector3(0, -0.52, 0))
	var r_foot_idx := _add_bone(skel, "RightFoot", r_shin_idx, Vector3(0, -0.50, 0.08))

	# Left leg chain
	var l_thigh_idx := _add_bone(skel, "LeftThigh", hips_idx, Vector3(-0.12, -0.08, 0))
	var l_shin_idx := _add_bone(skel, "LeftShin", l_thigh_idx, Vector3(0, -0.52, 0))
	var l_foot_idx := _add_bone(skel, "LeftFoot", l_shin_idx, Vector3(0, -0.50, 0.08))

	# Store bone indices for posture wiring
	_player.skeleton_bones = {
		"hips": hips_idx,
		"spine": spine_idx,
		"chest": chest_idx,
		"neck": neck_idx,
		"head": head_idx,
		"right_shoulder": r_shoulder_idx,
		"right_upper_arm": r_upper_idx,
		"right_forearm": r_fore_idx,
		"right_hand": r_hand_idx,
		"left_shoulder": l_shoulder_idx,
		"left_upper_arm": l_upper_idx,
		"left_forearm": l_fore_idx,
		"left_hand": l_hand_idx,
		"right_thigh": r_thigh_idx,
		"right_shin": r_shin_idx,
		"right_foot": r_foot_idx,
		"left_thigh": l_thigh_idx,
		"left_shin": l_shin_idx,
		"left_foot": l_foot_idx
	}

	print("[PlayerBodyBuilder] Skeleton created with %d bones" % skel.get_bone_count())

func _add_bone(skel: Skeleton3D, _name: String, parent_idx: int, rel_pos: Vector3) -> int:
	var idx := skel.get_bone_count()
	skel.add_bone(_name)
	if parent_idx >= 0:
		skel.set_bone_parent(idx, parent_idx)
	skel.set_bone_rest(idx, Transform3D(Basis.IDENTITY, rel_pos))
	skel.set_bone_pose(idx, Transform3D.IDENTITY)
	return idx

func log_positions() -> void:
	var _foot_y: float = _player.ground_y + 0.04

	if _player.right_leg_node:
		var thigh_p = _player.right_leg_node.get_node_or_null("ThighPivot")
		if thigh_p:
			var shin_p = thigh_p.get_node_or_null("ShinPivot")
			if shin_p:
				var ankle_y = shin_p.global_position.y
				var foot_pos = shin_p.global_position
				var dist = _player.right_leg_node.global_position.distance_to(foot_pos)
				var ratio = dist / (_player.leg_ik.THIGH_LENGTH + _player.leg_ik.SHIN_LENGTH)
				print("[P%d] Leg: ankle=%.2f gap=%.2f hip2foot=%.2f (%.0f%%)" % [
					_player.player_num, ankle_y, ankle_y - _player.ground_y, dist, ratio * 100])

	# Vertical labels
	var head: Node3D = null
	if _player.body_pivot:
		for c in _player.body_pivot.get_children():
			if c is MeshInstance3D and c.mesh is SphereMesh:
				head = c
				break

	if head == null and _player.body_pivot:
		var chest_node: Node3D = null
		for c in _player.body_pivot.get_children():
			if c is MeshInstance3D and c.position.y > 0.3 and c.position.y < 0.6:
				chest_node = c
				break
		if chest_node:
			for cc in chest_node.get_children():
				if cc is MeshInstance3D:
					head = cc
					break

	if head:
		var h_top = head.global_position.y + 0.12
		var h_bot = head.global_position.y - 0.12
		print("[P%d] Head: top=%.2f bot=%.2f" % [_player.player_num, h_top, h_bot])

	var arm_summary: String = ""
	for arm_info in [["R", _player.right_arm_node], ["L", _player.left_arm_node]]:
		var arm_node = arm_info[1]
		if not arm_node:
			continue
		var upper = arm_node.get_node_or_null("UpperArmPivot")
		var elbow_pos = upper.get_node_or_null("ForearmPivot").global_position if upper and upper.get_node_or_null("ForearmPivot") else Vector3.ZERO
		var hand_pos = Vector3.ZERO
		if upper:
			var fa = upper.get_node_or_null("ForearmPivot")
			if fa:
				var hp = fa.get_node_or_null("HandPivot")
				if hp:
					hand_pos = hp.global_position
		arm_summary += " %s(s=%.2f e=%.2f h=%.2f)" % [arm_info[0], arm_node.global_position.y, elbow_pos.y, hand_pos.y]
	if arm_summary != "":
		print("[P%d] Arms:%s" % [_player.player_num, arm_summary])
