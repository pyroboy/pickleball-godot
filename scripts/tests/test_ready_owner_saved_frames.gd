extends "res://scripts/tests/diagnose_receiving_face_candidate.gd"



var displayed_frames: Array[Transform3D] = []
func support_metrics(p, pose) -> Dictionary:
	var arm = p.left_arm_node
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var elbow: Vector3 = arm.forearm_pivot.global_position
	var wrist: Vector3 = arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket
	var geometry: Dictionary = C.volumes(p, pose, p.body_pivot.global_transform, displayed_frames)
	var upper: Dictionary = C.mesh_surface_margins(arm.upper_mesh, geometry, shoulder, elbow, 0.08)
	var fore: Dictionary = C.mesh_surface_margins(arm.fore_mesh, geometry)
	var body_gap: = INF
	for region in C.REGIONS: body_gap = minf(body_gap, minf(upper[region], fore[region]))
	var gap: = INF
	var inverse: Transform3D = p.paddle_node.global_transform.affine_inverse()
	for mesh in [arm.upper_mesh, arm.fore_mesh]:
		for point in C.mesh_surface_points(mesh): gap = minf(gap, P.distance_to_paddle_shape(inverse * (mesh.global_transform * point)))
	return {"shoulder": vd(shoulder), "elbow": vd(elbow), "wrist": vd(wrist), "body_gap": body_gap, "paddle_gap": gap, "scale": arm.visual_stretch}
func run() -> void :
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/tests/fixtures/ready_owner_stage2.json"))
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for entry in data.records:
		var sample: Dictionary = entry.sample
		var p = game.player_right
		p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
		p.current_velocity = Vector3.ZERO;p.posture.editor_preview_mode = true
		var pose = PostureLibrary.instance().get_def(20).duplicate(true)
		apply_fields(pose, sample.pose_fields)
		p.global_position = v(sample.body_root);p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
		p.body_pivot.global_transform = tt(sample.body_pivot_transform)
		displayed_frames.clear()
		for frame in sample.displayed_skin_frames: displayed_frames.append(tt(frame))
		p.body_pivot.get_node("HipsMesh").transform = displayed_frames[0]
		p.body_pivot.get_node("TorsoMesh").transform = displayed_frames[2]
		for side in [0, 1]:
			var arm = p.right_arm_node if side == 0 else p.left_arm_node
			arm.transform = tt(entry.arms[side].root_local_transform)
			arm.upper_pivot.transform = tt(entry.arms[side].upper_local_transform)
			arm.forearm_pivot.transform = tt(entry.arms[side].forearm_local_transform)
		p.paddle_node.global_transform = tt(sample.paddle_transform)
		p.arm_ik.update_arm_ik(0.0, pose)
		var baseline: Dictionary = support_metrics(p, pose)
		var error: = 0.0
		for key in ["shoulder", "elbow", "wrist"]:
			var stored: String = "visible_wrist" if key == "wrist" else key
			error = maxf(error, v(baseline[key]).distance_to(v(entry.arms[1][stored])))
		check(error < 1e-05, entry.case + " exact historical free support reconstruction")
		var guard = pose.duplicate(true)
		apply_fields(guard, sample.displayed_body_pose_fields)
		var paddle: Transform3D = p.paddle_node.global_transform
		p.posture.transition_pose_blend = guard;p.arm_ik.update_arm_ik(0.0, guard)
		var owned: Dictionary = support_metrics(p, guard)
		check(p.paddle_node.global_transform.is_equal_approx(paddle), entry.case + " ownership correction moves paddle")
		check(owned.scale <= 1.00001, entry.case + " full guard stretches support arm")
		check(owned.body_gap >= - 3e-05, entry.case + " full guard body intersection")
		check(owned.paddle_gap >= - 3e-05, entry.case + " full guard paddle intersection")
		records.append({"case": entry.case, "historical_minimum": entry.historical_minimum, "support_reconstruction_error": error, "current_geometry_mixed_owner": baseline, "current_geometry_full_guard": owned})
	var file = FileAccess.open("/tmp/ready-owner-saved-frames.json", FileAccess.WRITE);file.store_string(JSON.stringify({"records": records, "errors": errors}, "\t"));file.close()
	for error in errors: push_error(error)
	print("READY OWNER SAVED FRAMES: ", records.size(), " cases, ", errors.size(), " failures")
	game.queue_free(); await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	quit(0 if errors.is_empty() else 1)
