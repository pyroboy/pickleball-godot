extends "res://scripts/tests/test_held_hit_windup.gd"
## Actual input-owner press/cancel/repress from an intentionally turned Ready.
func run() -> void:
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false); node.set_physics_process(false)
	game.pvp_mode = true; game.aim_focus._sync_realtime_mode()
	var p = game.player_left
	var records: Array = []
	for yaw in [-65.0, 65.0]:
		for hz in [30, 60, 120]:
			rally_fixture(10)
			var h = p.posture.human_contact
			p.hitting.serving_visual_active = false; p.hitting.charge_visual_active = false; p.hitting.is_in_follow_through = false
			p.posture._committed_incoming_posture = -1
			p._head_gaze._rest_body_angle = yaw
			game.ball.global_position = p.global_position + p._get_forward_axis().rotated(Vector3.UP, -deg_to_rad(yaw)) * 3.0
			game.ball.linear_velocity = Vector3.ZERO
			h.contact.time = 2.0
			h.visual_pose = h._ready_pose(0.0)
			p.leg_ik.feet_initialized = false; h._apply_visual()
			for frame in range(hz / 2): p.leg_ik.update_leg_ik(1.0 / hz, h.visual_pose)
			var ik = p.leg_ik
			var feet: Array[Vector3] = [ik.right_foot_smooth, ik.left_foot_smooth]
			var turns: Array[float] = [ik._right_yaw, ik._left_yaw]
			var serials: Array[int] = [ik.right_contact_serial, ik.left_contact_serial]
			var prior_heading: float = ik._heading_angle
			var maximum_drift := 0.0; var maximum_locked_yaw := 0.0; var maximum_body_step := 0.0; var maximum_foot_step := 0.0
			for frame in range(hz * 3):
				var t: float = float(frame) / float(hz)
				if frame == 0 or frame == hz:
					Input.action_press("ui_accept"); game.input_handler._handle_swing_charge(0.0)
				if frame == int(hz * 0.45) or frame == int(hz * 1.45):
					game.input_handler.cancel_charge_input(); Input.action_release("ui_accept")
				if t < 0.45 or t >= 1.0 and t < 1.45: game.input_handler._handle_swing_charge(1.0 / hz)
				else: h.update(1.0 / hz)
				h._apply_visual(); ik.update_leg_ik(1.0 / hz, h.visual_pose)
				var now: Array[Vector3] = [ik.right_foot_smooth, ik.left_foot_smooth]
				var now_yaws: Array[float] = [ik._right_yaw, ik._left_yaw]
				var now_serials: Array[int] = [ik.right_contact_serial, ik.left_contact_serial]
				for side in [0, 1]:
					if (ik.right_foot_locked if side == 0 else ik.left_foot_locked) and now_serials[side] == serials[side]:
						maximum_drift = maxf(maximum_drift, feet[side].distance_to(now[side]))
						maximum_locked_yaw = maxf(maximum_locked_yaw, absf(angle_difference(turns[side], now_yaws[side])))
					maximum_foot_step = maxf(maximum_foot_step, absf(angle_difference(turns[side], now_yaws[side])))
				maximum_body_step = maxf(maximum_body_step, absf(angle_difference(prior_heading, ik._heading_angle)))
				prior_heading = ik._heading_angle; feet = now; turns = now_yaws; serials = now_serials
			var tag := "%dHz Ready %.0f" % [hz, yaw]
			check(maximum_drift < 0.00001 and maximum_locked_yaw < 0.00001, tag + " held/cancel/repress moved a planted contact")
			check(maximum_body_step <= deg_to_rad(ik.TURN_RATE / hz + 0.1), tag + " held/cancel/repress snapped the footwork heading")
			check(maximum_foot_step < deg_to_rad(35.0), tag + " held/cancel/repress flipped an airborne shoe")
			check(not p.hitting.charge_visual_active and h.held_hit_seconds == 0.0, tag + " cancel retained hold ownership")
			records.append({"case": tag, "locked_drift_m": maximum_drift, "locked_yaw_deg": rad_to_deg(maximum_locked_yaw), "heading_step_deg": rad_to_deg(maximum_body_step), "shoe_step_deg": rad_to_deg(maximum_foot_step)})
	stop_input()
	print("ROTATED READY HELD FOOTWORK: %d checks, %d failures; %s" % [checks, failures.size(), JSON.stringify(records)])
	game.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
