extends SceneTree
const Motion = preload("res://scripts/drive_serve_motion.gd")
var records: Array = []
var checks: = 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func v(a: Vector3) -> Array: return [a.x, a.y, a.z]
func b(a: Basis) -> Array: return [v(a.x), v(a.y), v(a.z)]
func snapshot(p) -> Dictionary:
	return {"body": p.body_pivot.global_transform, "pelvis": p.body_pivot.get_node("HipsMesh").global_transform, "chest": p.body_pivot.get_node("TorsoMesh").global_transform, 
		"paddle": p.paddle_node.global_transform, "right_shoulder": p.right_arm_node.upper_pivot.global_position, "left_shoulder": p.left_arm_node.upper_pivot.global_position, 
		"right_wrist": p.right_arm_node.hand_mesh.global_transform * p.right_arm_node.articulated_hand.wrist_socket, "left_wrist": p.left_arm_node.hand_mesh.global_transform * p.left_arm_node.articulated_hand.wrist_socket}
func compare(before: Dictionary, after: Dictionary, tag: String) -> Dictionary:
	var result: Dictionary = {}
	for key in before:
		checks += 1
		if before[key] is Transform3D:
			var origin: float = before[key].origin.distance_to(after[key].origin)
			var angle: float = rad_to_deg(before[key].basis.get_rotation_quaternion().angle_to(after[key].basis.get_rotation_quaternion()))
			var basis_error: float = maxf(before[key].basis.x.distance_to(after[key].basis.x), maxf(before[key].basis.y.distance_to(after[key].basis.y), before[key].basis.z.distance_to(after[key].basis.z)))
			result[key] = {"origin_error_m": origin, "angle_error_deg": angle, "basis_vector_error": basis_error, "before_basis": b(before[key].basis), "after_basis": b(after[key].basis)}
			if origin > 1e-05 or basis_error > 1e-05: failures.append(tag + " " + key + " moved %.6fm / %.5fdeg" % [origin, angle])
		else:
			var error: float = before[key].distance_to(after[key]);result[key] = error
			if error > 1e-05: failures.append(tag + " " + key + " moved %.6fm" % error)
	return result
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
	for p in [game.player_left, game.player_right]:
		p.posture.editor_preview_mode = false;p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false;p.current_velocity = Vector3.ZERO;p.posture._committed_incoming_posture = -1
		for index in range(5):
			var pose: PostureDefinition = Motion.serve_style_contact(0) if index < 3 else PostureLibrary.instance().get_def(20).duplicate(true)
			pose.spine_curve_deg = float(index % 3) * 10.0
			pose.body_yaw_deg = 17.0;pose.body_roll_deg = -6.0;pose.body_pitch_deg = 4.0
			pose.torso_yaw_deg = 12.0;pose.hip_yaw_deg = -9.0;pose.torso_roll_deg = 5.0
			p.leg_ik.locomotion_mode = "run" if index >= 3 else "stance"
			p.leg_ik.locomotion_hip_yaw_deg = (-55.0 if index == 3 else 55.0) if index >= 3 else 0.0
			p.leg_ik.feet_initialized = false;p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)


			if index >= 3:
				p.leg_ik.locomotion_mode = "run";p.leg_ik.locomotion_hip_yaw_deg = -55.0 if index == 3 else 55.0
				p.posture.force_posture_update(pose)
			var before: Dictionary = snapshot(p)
			var captured: PostureDefinition = p.posture.capture_displayed_pose()
			p.leg_ik.locomotion_mode = "stance";p.leg_ik.locomotion_hip_yaw_deg = 0.0
			p.posture.transition_pose_blend = captured;p.posture.force_posture_update(captured)
			var tag: String = "court%d case%d spine%.0f" % [p.player_num, index, pose.spine_curve_deg]
			var result: Dictionary = compare(before, snapshot(p), tag)
			result.merge({"tag": tag, "captured_body": [captured.body_pitch_deg, captured.body_yaw_deg, captured.body_roll_deg], "captured_hip": captured.hip_yaw_deg, "captured_torso": [captured.torso_pitch_deg, captured.torso_yaw_deg, captured.torso_roll_deg], "captured_spine": captured.spine_curve_deg})
			records.append(result)
	var file: = FileAccess.open("/workspace/shared/pickleball-hands/connected-capture-roundtrip.json", FileAccess.WRITE);file.store_string(JSON.stringify({"checks": checks, "failures": failures, "records": records}, "\t"));file.close()
	for failure in failures: push_error(failure)
	print("CONNECTED CAPTURE ROUNDTRIP ", checks, " checks; ", failures.size(), " failures")
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game)
	quit(0 if failures.is_empty() else 1)
