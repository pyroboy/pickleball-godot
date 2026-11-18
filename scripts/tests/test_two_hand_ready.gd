extends "res://scripts/tests/test_two_hand_backhand_grip.gd"




const Motion = preload("res://scripts/drive_serve_motion.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const BodyClearance = preload("res://scripts/body_clearance.gd")
const PaddleClearance = preload("res://scripts/paddle_clearance.gd")
func run() -> void :
	var source: PostureDefinition = PostureLibrary.instance().get_def(20)
	var kitchen_enabled: = true
	var authored_default: = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pose="):
			source = load(arg.trim_prefix("--pose="));authored_default = false
		if arg == "--base-only": kitchen_enabled = false
	var serialized: = source.duplicate(true)
	var temp: = "user://two-hand-ready-roundtrip.tres"
	check(ResourceSaver.save(serialized, temp) == OK, "ready resource serialization saves")
	var restored: PostureDefinition = load(temp)
	for field in ["main_grip_rotation_deg", "support_grip_rotation_deg", "support_grip_slide_m", "support_index_closure", "support_grip_style"]:
		check(is_equal_approx(float(source.get(field)), float(restored.get(field))), "serialization preserves " + field)
	check(restored.left_hand_mode == 1, "serialized Ready remains two-handed")
	check( not restored.has_zone, "neutral Ready has no contact zone")
	var sources: Array = [source]
	if authored_default:
		var volley: PostureDefinition = PostureLibrary.instance().get_def(12)
		check(volley.has_zone and is_equal_approx(volley.zone_x_min, - 0.2) and is_equal_approx(volley.zone_x_max, 0.2) and is_equal_approx(volley.zone_y_min, 0.845) and is_equal_approx(volley.zone_y_max, 1.245), "Volley Ready preserves original contact zone")
		check(is_equal_approx(volley.charge_duration, 0.32) and is_equal_approx(volley.ft_duration_strike, 0.1) and is_equal_approx(volley.ft_duration_sweep, 0.2), "Volley Ready retains contact timing")
		check(is_equal_approx(volley.paddle_forehand_mul, 0.0) and is_equal_approx(volley.paddle_y_offset, 0.12) and is_equal_approx(volley.paddle_forward_mul, 0.5), "active Volley Ready preserves its original contact head point")
		for authored in sources:
			for frame in [authored.windup_body, authored.follow_through_body]:
				check(frame != null, "authored Ready has complete body keyframes")
				if frame == null: continue
				for field in ["left_hand_mode", "right_hand_offset", "left_hand_offset", "main_grip_rotation_deg", "support_grip_rotation_deg", "support_grip_slide_m", "support_index_closure"]:
					check(frame.values.has(field) and frame.values[field] == authored.get(field), "Ready body keyframe preserves " + field)
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in 5: await process_frame
	game.game_serve.cleanup();game.process_mode = Node.PROCESS_MODE_DISABLED
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	var rows: Array = []
	for p in [game.player_left, game.player_right]:
		p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false;p.current_velocity = Vector3.ZERO;p.posture.editor_preview_mode = false
		for authored in sources:
			for blend in ([0.0, 0.25, 0.5, 0.75, 1.0] if kitchen_enabled else [0.0]):
				for yaw in [-60.0, 0.0, 60.0]:
					var pose: PostureDefinition = authored.lerp_with(Motion.kitchen_ready(authored), blend) if blend > 0 else authored.duplicate(true)
					for field in ["main_grip_rotation_deg", "support_grip_rotation_deg", "support_grip_slide_m", "support_index_closure", "support_grip_style"]:
						check(is_equal_approx(float(authored.get(field)), float(pose.get(field))), "kitchen preserves " + field)
					pose = SwingPath.rotate_guard(pose, yaw)
					p.leg_ik.feet_initialized = false;p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
					var label: = "pose%d court%d compact%.2f yaw%.0f" % [authored.posture_id, p.player_num, blend, yaw]
					check(pose.left_hand_mode == 1, label + " both hands selected")
					var geometry: Dictionary = BodyClearance.volumes(p, pose, p.body_pivot.global_transform)
					var body: Dictionary = BodyClearance.sample_paddle(p.paddle_node.global_transform, PaddleClearance.sample_head_surface(), geometry)
					for region in BodyClearance.REGIONS: check(body[region] >= 0, label + " blade clears " + region)
					var arms: Array = []
					for side in [0, 1]:
						var arm = p.right_arm_node if side == 0 else p.left_arm_node; var model = arm.articulated_hand
						var shoulder: Vector3 = arm.upper_pivot.global_position; var elbow: Vector3 = arm.forearm_pivot.global_position; var wrist: Vector3 = arm.hand_mesh.global_transform * model.wrist_socket
						var channels: Dictionary = Anatomy.decompose(Anatomy.forearm_reference_for_arm(arm, wrist, side == 1), arm.hand_mesh.global_basis * model.anatomical_basis, model.radial_sign)
						check(absf(shoulder.distance_to(elbow) - 0.35) < 1e-05 and absf(elbow.distance_to(wrist) - 0.35) < 1e-05, label + " fixed arm links")
						check(channels.within_animation_budget, label + " wrist budget arm%d %s" % [side, channels])
						check(elbow.y < shoulder.y - 0.15, label + " elbow remains below shoulder")
						var upper: Dictionary = BodyClearance.mesh_surface_margins(arm.upper_mesh, geometry, shoulder, elbow, 0.08)
						var fore: Dictionary = BodyClearance.mesh_surface_margins(arm.fore_mesh, geometry)
						for region in BodyClearance.REGIONS: check(upper[region] >= - 3e-05 and fore[region] >= - 3e-05, label + " arm clears " + region)
						arms.append({"channels": channels, "upper": upper, "fore": fore})
					var into_paddle: Transform3D = p.paddle_node.global_transform.affine_inverse()
					var right: Dictionary = _geometry(p.right_arm_node.articulated_hand, into_paddle * p.right_arm_node.hand_mesh.global_transform)
					var left: Dictionary = _geometry(p.left_arm_node.articulated_hand, into_paddle * p.left_arm_node.hand_mesh.global_transform)
					for hand in [right, left]:
						check(hand.shaft_gap >= - 5e-05, label + " actual cuff/hand clears shaft")
						check(_head_intersections(hand.triangles, _head_planes()).penetrating_triangles == 0, label + " actual skin clears blade")
					var ab: Dictionary = _hand_overlap(right, left); var ba: Dictionary = _hand_overlap(left, right)
					check(ab.penetrating_vertices == 0 and ba.penetrating_vertices == 0, label + " actual hands do not contain each other")
					check(ab.surface_crossings == 0 and ba.surface_crossings == 0, label + " actual hands have no surface crossings")
					rows.append({"label": label, "arms": arms, "paddle": body})
	var file = FileAccess.open("/workspace/scratch/6b6e64f75bd2/verification/two-handed-backhand/grip/ready-tracking-test.json", FileAccess.WRITE);file.store_string(JSON.stringify({"checks": checks, "failures": failures, "rows": rows}, "\t"));file.close()
	for failure in failures: push_error(failure)
	print("TWO-HAND READY: ", checks, " checks, ", failures.size(), " failures")
	game.queue_free(); await process_frame;quit(0 if failures.is_empty() else 1)
