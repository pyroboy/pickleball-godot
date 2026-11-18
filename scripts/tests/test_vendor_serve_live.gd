extends "res://scripts/tests/test_hand_runtime_states.gd"
const Surface = preload("res://scripts/paddle_clearance.gd")
const Styles = preload("res://scripts/serve_style.gd")
var live_contacts: Array = []
var observed_game
var owner_trace: Array = []
func sample(p, label: String) -> void :
	var game = p.get_parent()
	var pose = p.posture.transition_pose_blend if p.posture.transition_pose_blend != null else p.get_runtime_posture_def()
	var arm = p.right_arm_node if pose.paddle_hand == 0 else p.left_arm_node
	var offset: Vector3 = pose.right_hand_offset if pose.paddle_hand == 0 else pose.left_hand_offset
	var grip: Vector3 = p.paddle_node.to_global(PaddleSize.MAIN_GRIP_OFFSET + offset)
	var wrist: Vector3 = arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket
	var virtual_error: float = arm.hand_pivot.global_position.distance_to(grip)
	var socket_error: float = wrist.distance_to(arm.anatomical_wrist_world)
	if label in ["idle settle", "charged"] or virtual_error > 0.001 or socket_error > 0.0001:
		owner_trace.append({"label": label, "side": p.player_num, "style": game.game_serve.selected_serve_style, "physics_frame": Engine.get_physics_frames(), "process_frame": Engine.get_process_frames(), 
			"main_virtual_error_m": virtual_error, "main_socket_error_m": socket_error, "body": p.body_pivot.global_transform, "paddle": p.paddle_node.global_transform, "hand_pivot": arm.hand_pivot.global_transform, "hand": arm.hand_mesh.global_transform, "solved_wrist": arm.anatomical_wrist_world, 
			"game_state": game.game_state, "ball_in_play": game.ball.is_in_play, "charge_ratio": game.game_serve.get_charge_ratio(), "charging": game.game_serve.is_charging(), "release_pending": game.game_serve.is_release_pending(), "ai_serve_timer": game.ai_serve_timer, "serve_timing": game.game_serve.get_serve_timing_state(), 
			"transition_pose": p.posture.transition_pose_blend.posture_id if p.posture.transition_pose_blend else -1, "displayed_pose": p.posture._presented_body_pose.posture_id if p.posture._presented_body_pose else -1, 
			"serve_visual": p.hitting.serving_visual_active, "follow_through": p.hitting.is_in_follow_through, "swing_tween_valid": p.hitting.paddle_swing_tween != null and p.hitting.paddle_swing_tween.is_valid(), "support_mode": p.left_arm_node.articulated_hand._mode, "ball": game.ball.global_position})
		var report: = FileAccess.open("/workspace/shared/pickleball-hands/vendor-live-owner-trace.json", FileAccess.WRITE)
		report.store_string(JSON.stringify(owner_trace, "\t"));report.close()
	super.sample(p, label)
func tick(p, label: String) -> void :
	if observed_game == null:
		observed_game = p.get_parent()
		observed_game.game_serve.serve_launched.connect(on_real_contact)
	await super.tick(p, label)
func on_real_contact(side: int) -> void :
	var game = observed_game
	var p = game.player_left if side == 0 else game.player_right
	var style: int = game.game_serve.selected_serve_style
	var tx: Transform3D = p.paddle_node.global_transform
	var local_ball: Vector3 = tx.affine_inverse() * game.ball.global_position
	var arm = p.right_arm_node; var model = arm.articulated_hand
	var wrist: Vector3 = arm.hand_mesh.global_transform * model.wrist_socket
	var dorsal: Vector3 = arm.hand_mesh.global_basis * model.anatomical_basis.z
	var side_normal: Vector3 = tx.basis.z * signf(local_ball.z)
	var gap: float = Surface.distance_to_head_shape(local_ball) - Ball.BALL_RADIUS
	var drop: float = arm.upper_pivot.global_position.y - arm.forearm_pivot.global_position.y
	var top: float = - INF
	for point in PaddleSize.head_hull_points(): top = maxf(top, (tx * point).y)
	var tag: = "actual contact side%d style%d" % [side, style]
	check(local_ball.z > 0.0 and dorsal.dot(side_normal) < - 0.5, tag + " fixed-grip palmar striking side")
	check(absf(gap) < 0.0002, tag + " exact physical striking surface")
	check(drop > 0.12, tag + " lower main elbow")
	if not Styles.is_drop(style): check(top < wrist.y, tag + " full head below anatomical wrist")
	live_contacts.append({"side": side, "style": style, "ball_local": [local_ball.x, local_ball.y, local_ball.z], "dorsal_dot_ball_side": dorsal.dot(side_normal), "sphere_gap_m": gap, "elbow_drop_m": drop, "head_top_y": top, "wrist_y": wrist.y, "ball_position": game.ball.global_position, "launch_velocity": game.ball.linear_velocity, "normal_dot_launch": side_normal.dot(game.ball.linear_velocity)})
	var file: = FileAccess.open("/workspace/shared/pickleball-hands/vendor-live-serve-contacts.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"contacts": live_contacts, "failures": failures}, "\t"));file.close()
