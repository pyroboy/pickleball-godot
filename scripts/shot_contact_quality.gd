extends RefCounted
## Read-only actual contact inputs shared by human and AI execution tuning.
const D = preload("res://scripts/paddle_dimensions.gd")
const Surface = preload("res://scripts/paddle_clearance.gd")

static func capture(actor, ball, charge: float, timing_error_seconds: float = 0.0, serve: bool = false) -> Dictionary:
	var local: Vector3 = actor.paddle_node.to_local(ball.global_position)
	var incoming: Vector3 = actor.paddle_node.global_basis.inverse() * ball.linear_velocity
	var surface: Vector3 = Surface.closest_head_surface(local, incoming)
	var offset := surface - D.HEAD_OFFSET
	var face_offset: float = Vector2(offset.x / D.HEAD_RADIUS, offset.y / (D.HEAD_LENGTH * 0.5)).length()
	var pose = actor.posture.transition_pose_blend if actor.posture != null else null
	if pose == null: pose = actor.get_runtime_posture_def()
	var arm = actor.left_arm_node if pose != null and pose.paddle_hand == 1 else actor.right_arm_node
	var link_budget: float = arm.upper_arm_length + arm.forearm_length
	var actual_extension: float = arm.upper_pivot.global_position.distance_to(arm.anatomical_wrist_world) / maxf(link_budget, 0.001)
	var speed: float = Vector2(actor.current_velocity.x, actor.current_velocity.z).length()
	var support: Array[Dictionary] = actual_support(actor)
	var planted := 0
	for foot: Dictionary in support:
		if foot.locked and foot.grounded: planted += 1
	var support_load := 0.0 if planted == 2 else 0.20 if planted == 1 else 0.65
	var balance: float = clampf(speed / maxf(actor.move_speed, 0.1) * 0.7 + support_load, 0.0, 1.0)
	var pace: float = clampf((ball.linear_velocity.length() - 3.0) / 15.0, 0.0, 1.0) if not serve else 0.0
	return {"timing": clampf(absf(timing_error_seconds) / 0.10, 0.0, 1.0),
		"off_center": clampf(face_offset, 0.0, 1.0), "balance": balance,
		"extension": clampf((actual_extension - 0.78) / 0.22, 0.0, 1.0),
		"pace": pace, "power": clampf(charge, 0.0, 1.0),
		"timing_error_seconds": timing_error_seconds, "surface_point": actor.paddle_node.to_global(surface),
		"face_offset_normalized": face_offset, "arm_extension_ratio": actual_extension,
		"movement_speed": speed, "planted_feet": planted, "support_evidence": support, "incoming_speed": ball.linear_velocity.length(),
		"serve": serve, "player_num": actor.player_num}

static func actual_support(actor) -> Array[Dictionary]:
	# A cached IK lock is intent, not evidence of a foot on the court. Measure
	# the displayed shoe after the actual root/leg pose, including airborne saves.
	var result: Array[Dictionary] = []
	for side in range(2):
		var leg = actor.right_leg_node if side == 0 else actor.left_leg_node
		var locked: bool = actor.leg_ik != null and (actor.leg_ik.right_foot_locked if side == 0 else actor.leg_ik.left_foot_locked)
		var lowest := INF
		if leg != null and leg.foot_mesh != null and leg.foot_mesh.mesh != null:
			var shoe: MeshInstance3D = leg.foot_mesh
			var box: AABB = shoe.mesh.get_aabb()
			for corner in range(8): lowest = minf(lowest, (shoe.global_transform * box.get_endpoint(corner)).y)
		result.append({"locked": locked, "lowest_point": lowest, "grounded": is_finite(lowest) and lowest <= PickleballConstants.FLOOR_Y + 0.006})
	return result
