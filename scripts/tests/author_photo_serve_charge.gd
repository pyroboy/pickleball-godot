extends "res://scripts/tests/author_serve_neutral_endpoints.gd"


const CONFIG: = {"wrist_x": 0.45, "wrist_y": - 0.2, "wrist_forward0": - 0.25, "load_backshift": 0.0, "axial": 60.0, "pole_x": 0.444148261, "pole_y": 0.044544835, "pole_forward": 0.000327854}
func adjusted_body_pose(pose: PostureDefinition, _config: Dictionary) -> PostureDefinition:
	pose.stance_width = 0.56;pose.crouch_amount = 0.14;pose.weight_shift = - 0.35
	pose.body_pitch_deg = 4.0;pose.body_yaw_deg = 12.0;pose.hip_yaw_deg = 6.0;pose.torso_yaw_deg = 8.0;pose.torso_pitch_deg = -10.0
	return pose
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
	var p = game.player_left;p.posture.editor_preview_mode = false
	p.hitting.serving_visual_active = true;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
	p.current_velocity = Vector3.ZERO;p.posture._committed_incoming_posture = -1
	game.serving_team = 0;game.game_state = game.GameState.WAITING;game.ball.is_in_play = false;game.ball.freeze = true
	surface = Paddle.sample_head_surface();sample(p, CONFIG, 0, 1.0, 0.0)
	var row: Dictionary = rows[0]
	var arm = p.right_arm_node; var support = p.left_arm_node
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var elbow: Vector3 = arm.forearm_pivot.global_position
	var wrist: Vector3 = arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket
	for key in ["shoulder", "elbow", "wrist"]:
		var point: Vector3 = (shoulder if key == "shoulder" else (elbow if key == "elbow" else wrist)) - p.global_position
		row["main_" + key + "_stance"] = vec(Vector3(point.dot(p._get_forehand_axis()), point.y, point.dot(p._get_forward_axis())))
	row["elbow_forward_of_shoulder_m"] = (elbow - shoulder).dot(p._get_forward_axis())
	row["elbow_flex_deg"] = rad_to_deg((elbow - shoulder).angle_to(wrist - elbow))
	row["main_elbow_drop_m"] = arm.upper_pivot.global_position.y - arm.forearm_pivot.global_position.y
	row["head_behind_hip_m"] = - float(row.head[2]);row["head_below_grip_m"] = - p.paddle_node.global_basis.y.y * (PaddleSize.HEAD_CENTER_Y - PaddleSize.MAIN_GRIP_Y)
	row["support_channels"] = Anatomy.decompose(Anatomy.forearm_reference(support.upper_pivot.global_position, support.forearm_pivot.global_position, support.hand_mesh.global_transform * support.articulated_hand.wrist_socket, Vector3.UP, true), support.hand_mesh.global_basis * support.articulated_hand.anatomical_basis, support.articulated_hand.radial_sign)
	var center: Vector3 = game.game_serve.get_held_ball_position()
	row["held_seat_error_m"] = (support.hand_mesh.global_transform * support.articulated_hand.cup_ball_center).distance_to(center)
	var valid: bool = row.channels.within_animation_budget and row.support_channels.within_animation_budget and row.arm_surface >= 0 and row.support_arm_surface >= 0 and row.maximum_link_scale <= 1.001 and row.held_seat_error_m < 1e-05 and row.wrist_error < 1e-05 and row.held_ball_gap > 0 and row.face > 0.04 and row.floor > 0 and row.main_elbow_drop_m > 0.12 and row.head_behind_hip_m > 0 and row.head_below_grip_m > 0
	valid = valid and row.elbow_forward_of_shoulder_m <= 0.04 and row.elbow_flex_deg >= 20 and row.elbow_flex_deg <= 75
	for gap in row.arm_paddle.values(): valid = valid and float(gap) >= 0
	for gap in row.paddle_body.values(): valid = valid and float(gap) >= 0
	row["valid"] = valid
	var file: = FileAccess.open("/workspace/shared/pickleball-hands/vendor-photo-serve-charge-candidate.json", FileAccess.WRITE);file.store_string(JSON.stringify(rows, "\t"));file.close()
	print("PHOTO SERVE CHARGE: ", valid, " ", row)
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game)
	quit(0 if valid else 1)
