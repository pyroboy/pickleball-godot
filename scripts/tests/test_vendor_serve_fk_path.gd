extends "res://scripts/tests/test_serve_phase_geometry.gd"
const Size = preload("res://scripts/paddle_dimensions.gd")
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
		check(preload("res://scripts/serve_joint_motion.gd")._anatomical.is_equal_approx(p.right_arm_node.articulated_hand.anatomical_basis), "pure FK anatomy matches the actual hand landmarks")
		p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
		p.current_velocity = Vector3.ZERO;p.posture._committed_incoming_posture = -1
		for style in [0, 4]:
			var plan: Dictionary = Styles.release_plan(p.global_position, p.player_num == 1, style)
			for charge in [0.0, 1.0]:
				var impact: float = plan.contact_time
				var sweep: float = Styles.sweep_duration(style)
				var strike: float = Styles.stroke_duration(style)
				var times: Array[float] = [0.0, 0.03, 0.06, 0.12]
				for t in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]: times.append(impact - strike + strike * t)
				for t in [1.0 / 120.0, 1.0 / 60.0, 1.0 / 30.0]: times.append(impact + t)
				for t in [0.1, 0.25, 0.5, 0.75, 1.0]: times.append(impact + sweep * t)
				for t in [0.25, 0.5, 0.75, 1.0]: times.append(impact + sweep + Motion.SERVE_HOLD_TIME + Motion.SERVE_RECOVERY_TIME * t)
				for elapsed in times:
					sample(p, style, charge, maxf(0, elapsed), plan)
					var arm = p.right_arm_node; var model = arm.articulated_hand
					var center: Vector3 = ball_at(plan, elapsed)
					if elapsed < 0.18:
						var support = p.left_arm_node
						var gap: float = support.articulated_hand.ball_surface_gap(support.hand_mesh.to_local(center))
						records[-1]["release_skin_gap_m"] = gap
						check(gap >= - 0.0002, records[-1].tag + " real release skin clearance")
					if is_equal_approx(elapsed, impact):
						var tx: Transform3D = p.paddle_node.global_transform
						var ball_local: Vector3 = tx.affine_inverse() * center
						var normal: Vector3 = tx.basis.z * signf(ball_local.z)
						var dorsal: Vector3 = arm.hand_mesh.global_basis * model.anatomical_basis.z
						var wrist: Vector3 = arm.hand_mesh.global_transform * model.wrist_socket
						check(ball_local.z > 0 and dorsal.dot(normal) < - 0.5, records[-1].tag + " actual palmar striking side")
						check(absf(G.distance_to_head_shape(ball_local) - 0.0375) < 1e-05, records[-1].tag + " finite contact sphere")
						check(arm.upper_pivot.global_position.y - arm.forearm_pivot.global_position.y > 0.12, records[-1].tag + " low main elbow")
						var before: PostureDefinition = Preview.sample_serve_elapsed(style, impact - 0.0001, charge, p.global_position.y)
						var velocity: Vector3 = ((tx * Size.HEAD_OFFSET) - (Path.world_transform(p, before) * Size.HEAD_OFFSET)) / 0.0001
						records[-1]["contact_head_velocity"] = _vector_data(velocity)
						if not Styles.is_drop(style):
							check(velocity.y > 0, records[-1].tag + " upward volley strike")
							for point in Size.head_hull_points(): check((tx * point).y < wrist.y, records[-1].tag + " whole head below wrist")
			print("VENDOR FK PATH side", p.player_num, " style", style, " complete")
	var file: = FileAccess.open("/workspace/shared/pickleball-hands/vendor-serve-fk-path.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failure_count": failure_count, "failures": failures, "records": records}, "\t"));file.close()
	for failure in failures: push_error(failure)
	print("VENDOR SERVE FK PATH ", checks, " checks; ", failure_count, " failures; ", records.size(), " actual poses")
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game)
	quit(0 if failure_count == 0 else 1)
