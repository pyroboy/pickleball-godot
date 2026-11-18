extends SceneTree



const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Styles = preload("res://scripts/serve_style.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
var records: Array = []
var output: = "/workspace/shared/pickleball-hands/chain-before.json"
func _initialize() -> void : call_deferred("run")
func v(p: Vector3) -> Array: return [p.x, p.y, p.z]
func tx(t: Transform3D) -> Array: return [v(t.basis.x), v(t.basis.y), v(t.basis.z), v(t.origin)]
func trial_frames(shoulder: Vector3, elbow: Vector3, grip: Vector3, paddle_basis: Basis, arm) -> Array:
	if arm.get("articulated_hand") == null: return []
	var model = arm.articulated_hand
	var out: Array = []
	for yaw in [0.0, 45.0, 90.0, 135.0, 180.0, -135.0, -90.0, -45.0]:
		var basis: Basis = paddle_basis * Basis(Vector3.UP, deg_to_rad(yaw))
		var wrist: Vector3 = grip + basis * model.wrist_socket
		var distal: Vector3 = basis * model.anatomical_basis.x
		var fore: Vector3 = (wrist - elbow).normalized()
		var reach: float = shoulder.distance_to(wrist)

		var axis: Vector3 = (wrist - shoulder).normalized()
		var along: float = (arm.upper_arm_length * arm.upper_arm_length - arm.forearm_length * arm.forearm_length + reach * reach) / (2.0 * maxf(reach, 1e-05))
		var center: Vector3 = shoulder + axis * along
		var radius: float = sqrt(maxf(0.0, arm.upper_arm_length * arm.upper_arm_length - along * along))
		var u: Vector3 = axis.cross(Vector3.UP).normalized()
		if u.length_squared() < 0.01: u = axis.cross(Vector3.RIGHT).normalized()
		var vv: Vector3 = axis.cross(u).normalized()
		var min_bend: = 180.0
		for step in range(72):
			var e: Vector3 = center + (u * cos(TAU * step / 72.0) + vv * sin(TAU * step / 72.0)) * radius
			min_bend = minf(min_bend, rad_to_deg(distal.angle_to((wrist - e).normalized())))
		out.append({"yaw_deg": yaw, "wrist": v(wrist), "actual_pole_net_bend_deg": rad_to_deg(distal.angle_to(fore)), "minimum_swivel_net_bend_deg": min_bend, "wrist_reach_m": reach, "reachable": reach <= arm.upper_arm_length + arm.forearm_length + 0.0001})
	return out
func capture(p, pose: PostureDefinition, label: String) -> void :
	p.posture.editor_preview_mode = true
	p.posture.transition_pose_blend = pose
	p.posture.force_posture_update(pose)
	var arm = p.left_arm_node if pose.paddle_hand == 1 else p.right_arm_node
	var torso = p.body_pivot.get_node("TorsoMesh")
	var hips = p.body_pivot.get_node("HipsMesh")
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var elbow: Vector3 = arm.forearm_pivot.global_position
	var anchor: Vector3 = arm.hand_pivot.global_position
	var paddle: Transform3D = p.paddle_node.global_transform
	var hand_offset: Vector3 = pose.left_hand_offset if pose.paddle_hand == 1 else pose.right_hand_offset
	var grip: Vector3 = paddle * (PaddleSize.MAIN_GRIP_OFFSET + hand_offset)
	var record: = {"label": label, "side": p.player_num, "dominant": pose.paddle_hand, 
		"pose": pose.posture_id, "paddle": tx(paddle), "torso": tx(torso.global_transform), "hips": tx(hips.global_transform), 
		"body": tx(p.body_pivot.global_transform), "shoulder": v(shoulder), "elbow": v(elbow), "virtual_grip_anchor": v(anchor), 
		"computed_shoulder_error_m": shoulder.distance_to(Body.shoulder_world(p, pose)), "grip_error_m": anchor.distance_to(grip), 
		"elbow_flexion_deg": rad_to_deg(PI - (shoulder - elbow).angle_to(anchor - elbow)), 
		"arm_reach_m": shoulder.distance_to(anchor), "hand_basis": tx(arm.hand_pivot.global_transform), 
		"raw_body_yaw_deg": pose.body_yaw_deg, "raw_hip_yaw_deg": pose.hip_yaw_deg, "raw_torso_yaw_deg": pose.torso_yaw_deg, 
		"left_hand_mode": pose.left_hand_mode, "support_wrist": v((p.right_arm_node if pose.paddle_hand == 1 else p.left_arm_node).hand_pivot.global_position)}
	if arm.get("articulated_hand") != null:
		var model = arm.articulated_hand
		record["hand_model"] = model.debug_metadata()
		record["visual_wrist"] = v(model.hand_mesh.global_transform * model.wrist_socket)
		record["hand_mesh_transform"] = tx(model.hand_mesh.global_transform)
		record["hand_anatomical_basis"] = tx(Transform3D(model.hand_mesh.global_basis * model.anatomical_basis, Vector3.ZERO))
		record["visible_arm_scale"] = arm.visual_stretch
		if FileAccess.file_exists("res://scripts/arm_anatomy.gd"):
			var anatomy = load("res://scripts/arm_anatomy.gd")
			var wrist: Vector3 = model.hand_mesh.global_transform * model.wrist_socket
			var forearm_frame: Basis = anatomy.forearm_reference(shoulder, elbow, wrist, Vector3.UP, arm == p.left_arm_node)
			record["anatomical_channels"] = anatomy.decompose(forearm_frame, model.hand_mesh.global_basis * model.anatomical_basis, model.radial_sign)
			record["forearm_reference"] = tx(Transform3D(forearm_frame, wrist))
			record["visual_wrist_lag_deg"] = arm.visual_wrist_lag_deg
	record["hypothetical_grip_trials"] = trial_frames(shoulder, elbow, grip, paddle.basis, arm)
	records.append(record)
func run() -> void :
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.game_serve.cleanup()
	for p in [game.player_left, game.player_right]:
		p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false
		p.current_velocity = Vector3.ZERO
		for id in [20, 0, 2, 5, 7, 10, 11, 13, 14, 3, 4]:
			var base: PostureDefinition = PostureLibrary.instance().get_def(id)
			capture(p, base, "authored_%02d" % id)
			if id == 20: continue
			for charge in [0.35, 1.0]:
				capture(p, Motion.held_drive_pose(base, charge), "held_%02d_q%.2f" % [id, charge])
				for progress in [0.0, 0.2, 0.4, 0.49, 0.5, 0.65, 1.0]:
					capture(p, Motion.sample_drive(base, progress, charge), "swing_%02d_q%.2f_t%.2f" % [id, charge, progress])
		for style in range(7):
			for charge in [0.0, 0.5, 1.0]:
				capture(p, Motion.serve_style_preparation(style, charge, Styles.hold_offset(style)), "serve_%d_q%.1f" % [style, charge])
	var summary: = {"engine": Engine.get_version_info().string, "project": ProjectSettings.globalize_path("res://"), "records": records, 
		"notes": "Source-profile audit of final visible rig via production force_posture_update; this is not a real-flight gameplay test. Compare world torso bases, not sums of Euler fields. Virtual grip is not anatomical wrist."}
	var f: = FileAccess.open(output, FileAccess.WRITE);f.store_string(JSON.stringify(summary, "\t"));f.close()
	print("HAND CHAIN AUDIT ", records.size(), " samples -> ", output)
	game.queue_free(); await process_frame;quit()
