extends "res://scripts/tests/author_photo_serve_charge.gd"



const BODY_FIELDS: = ["stance_width", "crouch_amount", "weight_shift", "body_pitch_deg", "body_yaw_deg", "hip_yaw_deg", "torso_yaw_deg", "torso_pitch_deg"]
var active_charge: = 0.0
func adjusted_body_pose(pose: PostureDefinition, config: Dictionary) -> PostureDefinition:
	var start: PostureDefinition = Motion.serve_style_preparation(0, 0.0, Styles.hold_offset(0))
	var finish: PostureDefinition = super.adjusted_body_pose(pose.duplicate(true), config)
	var weight: float = smoothstep(0.0, 1.0, active_charge)
	for field in BODY_FIELDS: pose.set(field, lerpf(start.get(field), finish.get(field), weight))
	return pose
func qcheck(ok: bool, label: String, failures: Array):
	if not ok: failures.append(label)
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
	surface = Paddle.sample_head_surface()
	var failures: Array = []; var keys: Array = []
	for p in [game.player_left, game.player_right]:
		p.posture.editor_preview_mode = false;p.hitting.serving_visual_active = true;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
		p.current_velocity = Vector3.ZERO;p.posture._committed_incoming_posture = -1
		game.serving_team = p.player_num;game.game_state = game.GameState.WAITING;game.ball.is_in_play = false;game.ball.freeze = true
		var zero: PostureDefinition = Motion.serve_style_preparation(0, 0.0, Styles.hold_offset(0))
		p.leg_ik.feet_initialized = false;p.posture.transition_pose_blend = zero;p.posture.force_posture_update(zero)
		var original_zero: Transform3D = p.paddle_node.global_transform
		var main = p.right_arm_node; var model = main.articulated_hand
		var start_w: Vector3 = main.hand_mesh.global_transform * model.wrist_socket - p.global_position
		var start_e: Vector3 = main.forearm_pivot.global_position - p.global_position
		var start_s: Vector3 = main.upper_pivot.global_position - p.global_position
		start_w = Vector3(start_w.dot(p._get_forehand_axis()), start_w.y, start_w.dot(p._get_forward_axis()))
		start_e = Vector3(start_e.dot(p._get_forehand_axis()), start_e.y, start_e.dot(p._get_forward_axis()))
		start_s = Vector3(start_s.dot(p._get_forehand_axis()), start_s.y, start_s.dot(p._get_forward_axis()))
		var end_s: = Vector3(0.200323104858398, 0.293842434883118, - 0.0296721458435059)
		var end_e: = Vector3(0.444148261, 0.044544835, 0.000327854)
		var end_w: = Vector3(0.45, - 0.2, - 0.25)
		var start_radial: Vector3 = (start_e - (start_s + start_w) * 0.5).normalized()
		var end_radial: Vector3 = (end_e - (end_s + end_w) * 0.5).normalized()
		var start_frame: Basis = Anatomy.forearm_reference(main.upper_pivot.global_position, main.forearm_pivot.global_position, main.hand_mesh.global_transform * model.wrist_socket, Vector3.UP, false)
		var start_relative: Basis = start_frame.inverse() * main.hand_mesh.global_basis * model.anatomical_basis
		var previous: = original_zero.basis
		for step in range(21):
			var q: float = step / 20.0;active_charge = q
			var t: float = smoothstep(0, 1, q)
			var wrist: Vector3 = start_w.lerp(Vector3(0.45, - 0.2, - 0.25), t) + Vector3(0.09, - 0.03, 0) * sin(PI * q)
			var elbow: Vector3 = start_e.lerp(Vector3(0.444148261, 0.044544835, 0.000327854), t)
			var config: Dictionary = {"wrist_x": wrist.x, "wrist_y": wrist.y, "wrist_forward0": wrist.z, "load_backshift": 0.0, "axial": 60 * t, "pole_x": elbow.x, "pole_y": elbow.y, "pole_forward": elbow.z}
			config["pole_relative_to_shoulder"] = start_radial.slerp(end_radial, t).normalized()
			config["relative_hand_basis"] = Basis(start_relative.get_rotation_quaternion().slerp(Basis(Vector3.RIGHT, deg_to_rad(60)).get_rotation_quaternion(), t))
			sample(p, config, 0, q, 0.03 * (1 - q))
			var row: Dictionary = rows[-1];row["team"] = p.player_num
			var tag: String = "court%d q%.2f" % [p.player_num, q]
			qcheck(row.channels.within_animation_budget, tag + " main wrist", failures)
			qcheck(row.arm_surface >= - 3e-05 and row.support_arm_surface >= - 3e-05, tag + " actual body surfaces", failures)
			qcheck(row.maximum_link_scale <= 1.001 and row.wrist_error < 1e-05, tag + " wrist/reach", failures)
			qcheck(row.face > 0.04 and row.floor > 0 and row.held_ball_gap > 0, tag + " face/floor/ball", failures)
			for label in row.arm_paddle: qcheck(float(row.arm_paddle[label]) >= - 3e-05, tag + " paddle " + label, failures)
			for label in row.paddle_body: qcheck(float(row.paddle_body[label]) >= - 3e-05, tag + " paddle body " + label, failures)
			var pose: PostureDefinition = p.posture.transition_pose_blend
			if step == 0: qcheck(p.paddle_node.global_transform.is_equal_approx(original_zero), tag + " exact existing q0", failures)
			if step == 20:
				var expected_elbow: Vector3 = p.global_position + p._get_forehand_axis() * end_e.x + Vector3.UP * end_e.y + p._get_forward_axis() * end_e.z
				qcheck(main.forearm_pivot.global_position.distance_to(expected_elbow) < 1e-05, tag + " exact accepted q1 elbow", failures)
			var angle: float = rad_to_deg(previous.get_rotation_quaternion().angle_to(p.paddle_node.global_basis.get_rotation_quaternion()))
			row["five_percent_rotation_step_deg"] = angle;previous = p.paddle_node.global_basis
			qcheck(angle < 20, tag + " bounded charge rotation", failures)
			var support = p.left_arm_node; var sm = support.articulated_hand
			var hand: Transform3D = support.hand_mesh.global_transform
			var sw: Vector3 = hand * sm.wrist_socket
			row["support_channels"] = Anatomy.decompose(Anatomy.forearm_reference(support.upper_pivot.global_position, support.forearm_pivot.global_position, sw, Vector3.UP, true), hand.basis * sm.anatomical_basis, sm.radial_sign)
			qcheck(row.support_channels.within_animation_budget, tag + " support wrist", failures)
			qcheck((hand * sm.cup_ball_center).distance_to(game.game_serve.get_held_ball_position()) < 1e-05, tag + " exact held seat", failures)
			pose.set_meta("runtime_preview_serve", true);pose.set_meta("preview_serve_phase", "HELD");pose.set_meta("preview_serve_charge", q);pose.set_meta("preview_serve_held_offset", Styles.hold_offset(0));pose.set_meta("preview_serve_release_elapsed", 0.0)
			p.posture.editor_preview_mode = true;p.arm_ik.update_arm_ik(0, pose)
			qcheck(support.hand_mesh.global_transform.is_equal_approx(hand), tag + " runtime/editor cup parity", failures)
			p.posture.editor_preview_mode = false
			if p.player_num == 0 and step in [0, 10, 20]:
				var data: Dictionary = {"q": q, "head": row.head, "rotation": row.rotation, "pole": row.pole, "body": {}}
				for field in BODY_FIELDS: data.body[field] = pose.get(field)
				keys.append(data)
	var file: = FileAccess.open("/workspace/shared/pickleball-hands/vendor-photo-charge-path-radial.json", FileAccess.WRITE);file.store_string(JSON.stringify({"rows": rows, "keys": keys, "failures": failures}, "\t"));file.close()
	for failure in failures: push_error(failure)
	print("PHOTO CHARGE PATH ", rows.size(), " actual samples; ", failures.size(), " failures")
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game)
	quit(0 if failures.is_empty() else 1)
