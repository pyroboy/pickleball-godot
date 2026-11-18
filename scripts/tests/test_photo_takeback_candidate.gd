extends "res://scripts/tests/test_serve_phase_geometry.gd"


const Candidate = preload("res://scripts/tests/photo_takeback_candidate.gd")
var active_charge: = 0.0
func adjusted_pose(pose: PostureDefinition, _elapsed: float) -> PostureDefinition:
	return Candidate.apply(pose, active_charge)
func run():
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
	surface = G.sample_head_surface()
	for p in [game.player_left, game.player_right]:
		p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
		p.current_velocity = Vector3.ZERO;p.posture._committed_incoming_posture = -1
		var plan: Dictionary = Styles.release_plan(p.global_position, p.player_num == 1, 0)
		var previous: = Basis.IDENTITY
		for step in range(41):
			active_charge = step / 40.0
			export_frames = step == 40
			sample(p, 0, active_charge, 0.0, plan)
			var pose: PostureDefinition = p.posture.transition_pose_blend
			var tag: = "court%d q%.3f" % [p.player_num, active_charge]
			check(records[-1].face >= 0.04, tag + " conservative face spacing")
			if step == 0:
				var original: PostureDefinition = Motion.serve_style_preparation(0, 0.0, Styles.hold_offset(0))
				check(p.paddle_node.global_transform.is_equal_approx(Path.world_transform(p, original)), tag + " exact q0 paddle")
			else:
				var angle: float = rad_to_deg(previous.get_rotation_quaternion().angle_to(p.paddle_node.global_basis.get_rotation_quaternion()))
				records[-1]["half_key_rotation_deg"] = angle
				check(angle < 10.0, tag + " continuous half-key rotation")
			previous = p.paddle_node.global_basis
			if step == 40:
				var body_transform: Array = _basis_data(p.body_pivot.global_basis)
				body_transform.append(_vector_data(p.body_pivot.global_position))
				records[-1]["body_transform"] = body_transform
				records[-1]["player_origin"] = _vector_data(p.global_position)
				records[-1]["body_fields"] = {}
				for field in Candidate.BODY_FIELDS: records[-1].body_fields[field] = pose.get(field)
				records[-1].body_fields["shoulder_protraction_m"] = pose.shoulder_protraction_m
				var arm = p.right_arm_node
				var wrist: Vector3 = arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket
				var expected_w: Vector3 = p.global_position + p._get_forehand_axis() * 0.45 + Vector3.UP * ( - 0.2) + p._get_forward_axis() * ( - 0.25)
				var expected_e: Vector3 = p.global_position + p._get_forehand_axis() * 0.444148261 + Vector3.UP * 0.044544835 + p._get_forward_axis() * 0.000327854
				check(wrist.distance_to(expected_w) < 1e-05, tag + " accepted q1 wrist")
				check(arm.forearm_pivot.global_position.distance_to(expected_e) < 1e-05, tag + " accepted q1 elbow")
			var hand: Transform3D = p.left_arm_node.hand_mesh.global_transform
			check((hand * p.left_arm_node.articulated_hand.cup_ball_center).distance_to(plan.release_position) < 1e-05, tag + " exact held sphere seat")
	var file: = FileAccess.open("/workspace/shared/pickleball-hands/vendor-photo-takeback-baked.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failure_count": failure_count, "failures": failures, "records": records}, "\t"));file.close()
	for failure in failures: push_error(failure)
	print("PHOTO TAKEBACK BAKED ", checks, " checks; ", failure_count, " failures; ", records.size(), " actual poses")
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game)
	quit(0 if failure_count == 0 else 1)
