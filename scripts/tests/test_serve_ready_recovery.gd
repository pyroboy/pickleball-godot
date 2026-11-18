extends "res://scripts/tests/test_two_hand_backhand_grip.gd"
const Trial = preload("res://scripts/serve_joint_motion.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
func run() -> void :
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in 5: await process_frame
	game.game_serve.cleanup();game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_state = game.GameState.PLAYING
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	var rows: Array = []
	for p in [game.player_left, game.player_right]:
		p.hitting.serving_visual_active = true;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false;p.current_velocity = Vector3.ZERO;p.posture.editor_preview_mode = false
		for style in [0, 2, 3]:
			var local: = Vector3(0.417111, - 0.283223 if style == 2 else - 0.311699, 0.620205)
			var from: PostureDefinition = Motion.serve_style_follow_through(style, 0.7, 1.0, local)
			var to: PostureDefinition = PostureLibrary.instance().get_def(20).duplicate(true);to.front_foot_forward = - 0.12;to.back_foot_back = - 0.24
			for phase in [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.525, 0.55, 0.575, 0.6, 0.625, 0.65, 0.675, 0.7, 0.725, 0.75, 0.775, 0.8, 0.825, 0.85, 0.86, 0.87, 0.88, 0.9, 0.925, 0.95, 0.975, 1.0]:
				var t: float = smoothstep(0.0, 1.0, phase)
				var pose: PostureDefinition = Trial.recover_to_ready(from, to, phase)
				p.leg_ik.feet_initialized = false;p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
				var label: = "court%d style%d phase%.2f" % [p.player_num, style, phase]
				var arm_channels: Array = []
				for side in [0, 1]:
					var arm = p.right_arm_node if side == 0 else p.left_arm_node; var model = arm.articulated_hand
					var s: Vector3 = arm.upper_pivot.global_position; var e: Vector3 = arm.forearm_pivot.global_position; var w: Vector3 = arm.hand_mesh.global_transform * model.wrist_socket
					var channels: Dictionary = Anatomy.decompose(Anatomy.forearm_reference_for_arm(arm, w, side == 1), arm.hand_mesh.global_basis * model.anatomical_basis, model.radial_sign)
					arm_channels.append(channels)
					check(channels.within_animation_budget, label + " arm%d wrist budget" % side)
					check(absf(s.distance_to(e) - 0.35) < 1e-05 and absf(e.distance_to(w) - 0.35) < 1e-05, label + " fixed links")
					check(w.distance_to(arm.anatomical_wrist_world) < 1e-05, label + " visible/solved real wrist agrees")
				var into: Transform3D = p.paddle_node.global_transform.affine_inverse()
				var right: Dictionary = _geometry(p.right_arm_node.articulated_hand, into * p.right_arm_node.hand_mesh.global_transform)
				var left: Dictionary = _geometry(p.left_arm_node.articulated_hand, into * p.left_arm_node.hand_mesh.global_transform)
				var rb: Dictionary = _head_intersections(right.triangles, _head_planes()); var lb: Dictionary = _head_intersections(left.triangles, _head_planes())
				var ab: Dictionary = _hand_overlap(right, left); var ba: Dictionary = _hand_overlap(left, right)
				check(right.shaft_gap >= - 5e-05, label + " main stays seated on shaft")
				check(left.shaft_gap >= - 5e-05, label + " support clears shaft")
				check(rb.penetrating_triangles == 0 and lb.penetrating_triangles == 0, label + " both hands clear blade")
				check(ab.penetrating_vertices == 0 and ba.penetrating_vertices == 0 and ab.surface_crossings == 0 and ba.surface_crossings == 0, label + " hands clear each other")
				rows.append({"label": label, "channels": arm_channels, "main_shaft_gap": right.shaft_gap, "support_shaft_gap": left.shaft_gap, "main_blade": rb, "support_blade": lb, "main_inside_support": ab, "support_inside_main": ba})
	var f = FileAccess.open("/workspace/scratch/6b6e64f75bd2/verification/two-handed-backhand/grip/serve-ready-recovery-production.json", FileAccess.WRITE);f.store_string(JSON.stringify({"checks": checks, "failures": failures, "rows": rows}, "\t"));f.close()
	for failure in failures: push_error(failure)
	print("RECOVERY SKIN ", checks, " checks, ", failures.size(), " failures")
	game.queue_free(); await process_frame;quit(0 if failures.is_empty() else 1)
