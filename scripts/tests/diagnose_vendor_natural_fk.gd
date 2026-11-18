extends "res://scripts/tests/diagnose_vendor_serve_contact.gd"
var candidate_file: = "/workspace/shared/pickleball-hands/vendor-natural-fk-turn30-candidates.json"
var result_file: = "/workspace/shared/pickleball-hands/vendor-natural-fk-turn30-actual.json"
func prepare_candidates(candidates: Array, _original: Dictionary) -> Array: return candidates
func run():
	var candidates = JSON.parse_string(FileAccess.get_file_as_string(candidate_file))
	var original = JSON.parse_string(FileAccess.get_file_as_string("/workspace/shared/pickleball-hands/vendor-serve-contact-first.json"))
	candidates = prepare_candidates(candidates, original)
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
	for candidate in candidates:
		var p = game.player_left if int(candidate.team) == 0 else game.player_right
		p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
		p.current_velocity = Vector3.ZERO;p.posture._committed_incoming_posture = -1;p.posture.editor_preview_mode = false
		for source in original.records:
			if int(source.team) == int(candidate.team) and int(source.style) == int(candidate.style): p.global_position = v(source.player_origin);break
		var fixed_feet: Array[Vector3] = []
		if candidate.has("reference_pose_fields"):
			var reference: = PostureDefinition.new();apply_fields(reference, candidate.reference_pose_fields)
			p.leg_ik.feet_initialized = false;p.posture.transition_pose_blend = reference;p.posture.force_posture_update(reference)
			p.body_pivot.global_transform = tt(candidate.reference_body_transform)
			p.leg_ik._solve_legs(0.0, reference, false)
			fixed_feet = [p.right_leg_node.foot_pivot.global_position, p.left_leg_node.foot_pivot.global_position]
		var pose: = PostureDefinition.new();apply_fields(pose, candidate.pose_fields)
		var tx: = Transform3D(bt(candidate.paddle_basis), v(candidate.paddle_origin))
		var stance: = Basis(p._get_forehand_axis(), Vector3.UP, - p._get_forward_axis())
		var offset: Vector3 = tx * Size.HEAD_OFFSET - p.global_position
		O.set_canonical_basis(pose, stance.inverse() * tx.basis)
		pose.paddle_forehand_mul = offset.dot(p._get_forehand_axis());pose.paddle_y_offset = offset.y;pose.paddle_forward_mul = offset.dot(p._get_forward_axis())
		p.leg_ik.feet_initialized = false;p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
		p.body_pivot.global_transform = tt(candidate.body_transform)
		if not fixed_feet.is_empty():
			p.leg_ik._reset_feet(fixed_feet, false)
			p.leg_ik._solve_legs(0.0, pose, false)
		pose.right_elbow_pole = canonical_pole(p, pose, v(candidate.elbow))
		p.paddle_node.global_transform = tx;p.arm_ik.update_arm_ik(0.0, pose)
		var result: Dictionary = measured(p, pose)
		var actual: Transform3D = p.paddle_node.global_transform
		var ball: Vector3 = v(candidate.ball_target_world)
		var ball_local: Vector3 = actual.affine_inverse() * ball
		var face: Vector3 = actual.basis.z * signf(ball_local.z)
		var arm = p.right_arm_node; var model = arm.articulated_hand
		var leg_scale: = 1.0
		for leg in [p.right_leg_node, p.left_leg_node]: leg_scale = maxf(leg_scale, maxf(leg.thigh_pivot.global_position.distance_to(leg.shin_pivot.global_position) / leg.thigh_length, leg.shin_pivot.global_position.distance_to(leg.foot_pivot.global_position) / leg.shin_length))
		var foot_error: = 0.0
		if not fixed_feet.is_empty():
			foot_error = maxf(p.right_leg_node.foot_pivot.global_position.distance_to(fixed_feet[0]), p.left_leg_node.foot_pivot.global_position.distance_to(fixed_feet[1]))
			check(foot_error < 1e-05, candidate.case + " planted feet retained")
		var shape: Dictionary = C.volumes(p, pose, p.body_pivot.global_transform)
		var paddle_body: Dictionary = C.sample_paddle(actual, P.sample_head_surface(), shape)
		var limb: = INF
		for mesh in [p.left_arm_node.upper_mesh, p.left_arm_node.fore_mesh, p.right_leg_node.thigh_mesh, p.right_leg_node.shin_mesh, p.left_leg_node.thigh_mesh, p.left_leg_node.shin_mesh]:
			for point in C.mesh_surface_points(mesh): limb = minf(limb, P.distance_to_paddle_shape(actual.affine_inverse() * (mesh.global_transform * point)))
		result.merge({"case": candidate.case, "team": candidate.team, "style": candidate.style, "pose_fields": fields(pose), "canonical_pole": vd(pose.right_elbow_pole), "paddle_transform": transform_data(actual), "body_transform": transform_data(p.body_pivot.global_transform), "ball_position": vd(ball), "ball_local": vd(ball_local), "head": vd(actual * Size.HEAD_OFFSET), "paddle_body": paddle_body, "other_limb_gap_m": limb, "leg_max_scale": leg_scale, 
			"shoulder_error_m": v(result.shoulder).distance_to(v(candidate.expected_shoulder)), "elbow_error_m": v(result.elbow).distance_to(v(candidate.elbow)), "wrist_error_m": v(result.wrist).distance_to(v(candidate.wrist)), "ball_surface_gap_m": P.distance_to_head_shape(ball_local) - 0.0375, "dorsal_dot_ball_side": (arm.hand_mesh.global_basis * model.anatomical_basis.z).dot(face), "note": "Static direct-FK main-arm replay; held-seat reach/ball trajectory not established"})
		result["fixed_feet_error_m"] = foot_error
		if candidate.has("derived_delivery"): result["derived_delivery"] = candidate.derived_delivery
		check(result.shoulder_error_m < 1e-05 and result.elbow_error_m < 1e-05 and result.wrist_error_m < 1e-05, candidate.case + " exact FK endpoints")
		check(result.channels.within_animation_budget, candidate.case + " actual wrist budget")
		check(result.body_margin_m >= - 3e-05 and result.paddle_limb_margin_m >= - 3e-05, candidate.case + " main actual surfaces")
		check(result.other_limb_gap_m >= - 3e-05, candidate.case + " other arm/leg paddle clearance")
		for region in paddle_body: check(paddle_body[region] >= - 3e-05, candidate.case + " paddle body " + region)
		check(result.stretch <= 1.001 and leg_scale <= 1.001, candidate.case + " exact limb lengths")
		check(absf(result.ball_surface_gap_m) < 1e-05 and result.dorsal_dot_ball_side < - 0.5, candidate.case + " finite palmar contact")
		records.append(result)
	var file: = FileAccess.open(result_file, FileAccess.WRITE);file.store_string(JSON.stringify({"records": records, "errors": errors, "paddle_geometry": original.paddle_geometry, "geometry_source_sha256": original.geometry_source_sha256}, "\t"));file.close()
	for error in errors: push_error(error)
	print("VENDOR NATURAL FK ACTUAL ", records.size(), " cases; ", errors.size(), " failures")
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game)
	quit(0 if errors.is_empty() else 1)
