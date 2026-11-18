extends "res://scripts/tests/diagnose_vendor_serve_contact.gd"



func run():
	var source: Dictionary = {}
	for entry in JSON.parse_string(FileAccess.get_file_as_string("/workspace/shared/pickleball-hands/contact-body-variant-inputs.json")).snapshots:
		if entry.case == "pose_00": source = entry;break
	if source.is_empty(): push_error("Missing observed FH00 fixture");quit(2);return
	var pause = root.get_node_or_null("PauseController")
	if pause:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
		pause.close()
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	game.ball.is_in_play = true;game.ball.freeze = true;game.game_state = game.GameState.PLAYING
	var p = game.player_left
	p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
	p.current_velocity = Vector3.ZERO;p.posture._committed_incoming_posture = -1;p.posture.editor_preview_mode = true
	p.global_position = v(source.player_origin)
	var base: PostureDefinition = PostureLibrary.instance().get_def(0).duplicate(true)
	apply_fields(base, source.pose_fields);apply_fields(base, source.review_pose_fields)
	base.set_meta("visual_wrist_lag_deg", source.visual_wrist_lag_deg)
	var ball: Vector3 = v(source.ball_position)
	var original_observed_head: Vector3 = tt(source.paddle_transform) * Vector3(0, 0.4, 0)
	for correct_face in [false, true]:
		var pose: PostureDefinition = base.duplicate(true)
		if correct_face: O.set_canonical_basis(pose, O.canonical_basis(pose) * Basis(Vector3.UP, PI))
		var authored_head: Vector3 = Path.world_transform(p, pose) * Size.HEAD_OFFSET


		pose = P.contact_surface_pose(p, pose, ball, Vector3.ZERO)
		if pose == null: check(false, "new-size FH00 contact seating exceeds existing reach");continue
		p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
		p.body_pivot.global_transform = tt(source.body_transform)
		var feet: Array[Vector3] = [v(source.feet[0]), v(source.feet[1])]
		p.leg_ik._reset_feet(feet, false)
		p.leg_ik._right_yaw = source.foot_yaws[0];p.leg_ik._left_yaw = source.foot_yaws[1]
		p.leg_ik._solve_legs(0.0, pose, false)
		p.paddle_node.global_transform = Path.world_transform(p, pose);p.arm_ik.update_arm_ik(0.0, pose)
		var result: Dictionary = measured(p, pose)
		var arm = p.right_arm_node; var model = arm.articulated_hand
		var tx: Transform3D = p.paddle_node.global_transform
		var head: Vector3 = tx * Size.HEAD_OFFSET
		var ball_side: Vector3 = tx.basis.z * signf((ball - head).dot(tx.basis.z))
		var cells: Array = []
		for cell in C.volumes(p, pose, p.body_pivot.global_transform).cells:
			var planes: Array = []
			for plane in cell.planes: planes.append([plane.normal.x, plane.normal.y, plane.normal.z, plane.d])
			cells.append({"region": cell.region, "planes": planes})
		var meshes: Dictionary = {}
		for key in ["upper", "forearm"]:
			var mesh: MeshInstance3D = arm.upper_mesh if key == "upper" else arm.fore_mesh
			var triangles: Array = []
			for point in C.mesh_surface_triangles(mesh): triangles.append(vd(point))
			meshes[key] = {"transform": transform_data(mesh.global_transform), "triangles": triangles}
		var foot_error: = 0.0
		var leg_scale: = 1.0
		for side in [0, 1]:
			var leg = p.right_leg_node if side == 0 else p.left_leg_node
			foot_error = maxf(foot_error, leg.foot_pivot.global_position.distance_to(feet[side]))
			leg_scale = maxf(leg_scale, maxf(leg.thigh_pivot.global_position.distance_to(leg.shin_pivot.global_position) / leg.thigh_length, leg.shin_pivot.global_position.distance_to(leg.foot_pivot.global_position) / leg.shin_length))
		var pole: Vector3 = p.global_position + p._get_forehand_axis() * pose.right_elbow_pole.x + Vector3.UP * pose.right_elbow_pole.y + p._get_forward_axis() * pose.right_elbow_pole.z
		pole = p.arm_ik._rotate_shoulder_pole(arm, pole, pose.right_shoulder_rotation_deg)
		result.merge({"case": "pose_00_palmar" if correct_face else "pose_00_inherited", "correct_face_candidate": correct_face, 
			"scope": "Static old real-contact body/root/feet with current paddle; no new live acceptance", "pose_fields": fields(pose), "player_origin": vd(p.global_position), 
			"body_transform": transform_data(p.body_pivot.global_transform), "paddle_transform": transform_data(tx), "head": vd(head), "ball_position": vd(ball), 
			"original_observed_head": vd(original_observed_head), "authored_head_before_surface_seating": vd(authored_head), "surface_recenter_m": head.distance_to(authored_head), 
			"shoulder_error_from_recorded_m": arm.upper_pivot.global_position.distance_to(v(source.shoulder)), "feet_max_drift_m": foot_error, "leg_max_scale": leg_scale, 
			"dorsal_dot_ball_side": (arm.hand_mesh.global_basis * model.anatomical_basis.z).dot(ball_side), "ball_surface_gap_m": P.distance_to_head_shape(tx.affine_inverse() * ball) - 0.0375, 
			"hand_transform": transform_data(arm.hand_mesh.global_transform), "model_basis": bd(model.anatomical_basis), "radial_sign": model.radial_sign, "wrist_socket": vd(model.wrist_socket), 
			"upper_length": arm.upper_arm_length, "fore_length": arm.forearm_length, "authored_pole": vd(pole), "body_cells": cells, "arm_meshes": meshes})
		check(result.shoulder_error_from_recorded_m < 1e-05, result.case + " observed body/shoulder retained")
		check(foot_error < 1e-05 and leg_scale <= 1.001, result.case + " actual feet retained without stretch")
		check(absf(result.ball_surface_gap_m) < 1e-05, result.case + " same finite sphere seated")
		if correct_face: check(result.dorsal_dot_ball_side < - 0.5, result.case + " palmar striking side")
		records.append(result)
	var dimensions: Dictionary = {"length": Size.LENGTH, "width": Size.WIDTH, "thickness": Size.THICKNESS, "handle_length": Size.HANDLE_LENGTH, "handle_radius": Size.HANDLE_RADIUS, "head_center_y": Size.HEAD_CENTER_Y, "head_radius": Size.HEAD_RADIUS, "head_spine_half": Size.HEAD_SPINE_HALF, "head_half_thickness": Size.HEAD_HALF_THICKNESS, "main_grip_y": Size.MAIN_GRIP_Y, "head_outline": [], "head_hull_points": []}
	for point in Size.head_outline(): dimensions.head_outline.append([point.x, point.y])
	for point in Size.head_hull_points(): dimensions.head_hull_points.append(vd(point))
	var hashes: Dictionary = {}
	for path in ["res://scripts/paddle_dimensions.gd", "res://scripts/paddle_model.gd", "res://scripts/paddle_clearance.gd", "res://scenes/paddle.tscn"]: hashes[path] = FileAccess.get_sha256(path)
	var file: = FileAccess.open("/workspace/shared/pickleball-hands/vendor-forehand00-contact.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"records": records, "invariant_errors": errors, "paddle_geometry": dimensions, "geometry_source_sha256": hashes}, "\t"));file.close()
	for error in errors: push_error(error)
	print("VENDOR FH00 STATIC ", records.size(), " records; ", errors.size(), " invariant failures; anatomy recorded separately")
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game)
	quit(0 if errors.is_empty() else 1)
