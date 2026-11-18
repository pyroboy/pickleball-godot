extends "res://scripts/tests/test_scaled_body_gait.gd"
## Production rig, deterministic root trajectories at 30/60/120 Hz. Full wall
## input/rebound and natural dead-ball pickup flows run in companion suites.
const MotionState = preload("res://scripts/footwork_motion_state.gd")

func run() -> void:
	output = "/tmp/footwork-motion-states.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	var pause = root.get_node_or_null("PauseController")
	if pause:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
		pause.close()
	paused = false
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED; game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false); node.set_physics_process(false)
	_test_intent_states()
	for hz in [30, 60, 120]:
		for player in [game.player_left, game.player_right]:
			for name in ["wall_reversals", "backpedal", "backward_strafe", "fast_live_retreat", "chase_behind", "lateral_coverage", "offset_reversal", "rotated_ready_left", "rotated_ready_right"]:
				_motion_case(player, hz, name)
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "records": records,
		"coverage": "Actual game scene/IK at 30,60,120 Hz; deterministic movement trajectories. Separate wall/pickup/serve suites exercise live flows. No physical-device performance claim."}, "\t")); file.close()
	for failure in failures: push_error(failure)
	print("FOOTWORK MOTION STATES: %d checks, %d failures -> %s" % [checks, failures.size(), output])
	game.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)

func _test_intent_states() -> void:
	var motion := MotionState.new()
	var court := Vector3.FORWARD
	motion.update(0.1, Vector3.ZERO, 0.0, court, "rally", "idle", false, false)
	check(motion.state == "ready", "stationary ready")
	motion.update(0.1, Vector3.ZERO, 0.0, court, "rally", "split", false, false)
	check(motion.state == "split", "receive split")
	for phase in ["plant", "load", "swing"]:
		motion.update(0.1, Vector3.ZERO, 0.0, court, "rally", phase, false, false)
		check(motion.state == "planted_contact", "planted contact priority " + phase)
	motion.update(0.1, Vector3.ZERO, 0.0, court, "rally", "recover", false, true)
	check(motion.state == "recover", "unfinished step recovery")
	motion.update(0.1, Vector3.BACK, 0.1, court, "pickup", "idle", true, false)
	check(motion.state == "pickup_travel" and absf(motion.desired_heading) > 3.0, "pickup permits a whole-body turn away from court")
	motion.update(0.1, Vector3.ZERO, 0.0, court, "pickup", "idle", true, true)
	check(motion.state == "recover" and motion.desired_heading == 0.0, "pickup stop requests court-facing step recovery")
	motion.reset()
	for frame in range(60): motion.update(1.0 / 60.0, Vector3(2.4, 0, 3.2), 4.0 / 60.0, court, "wall", "idle", true, false)
	check(motion.state == "backward_strafe" and motion.desired_heading == 0.0, "wall retreat never opens into blind backward chase")
	var serial := motion.transition_serial
	for frame in range(20): motion.update(1.0 / 60.0, Vector3(2.4, 0, 3.2), 4.0 / 60.0, court, "wall", "idle", false, false)
	check(motion.transition_serial == serial, "stable route does not chatter states")
	motion.update(1.0 / 60.0, Vector3(-2.4, 0, -3.2), 4.0 / 60.0, court, "wall", "idle", false, false)
	check(motion.route_distance < 0.1, "reversal clears stale route commitment")

func _motion_case(player, hz: int, name: String) -> void:
	var pose: PostureDefinition = load("res://data/postures/20_ready.tres").duplicate(true)
	if name == "offset_reversal": pose.body_position_offset = Vector3(0.08, -0.04, 0.05)
	player.posture._committed_incoming_posture = -1
	player.hitting.is_in_follow_through = false
	if player.posture.human_contact != null: player.posture.human_contact.footwork.cancel()
	reset(player, pose)
	game.practice_launcher.is_active = name == "wall_reversals"
	game.practice_launcher.drill_mode = "WALL" if name == "wall_reversals" else "DINK"
	game.ball.is_in_play = true
	var ik = player.leg_ik
	var expected_heading := 0.0
	var maximum_ready_error := 0.0
	var maximum_hip_ready_error := 0.0
	var maximum_support_gap := 0.0
	var maximum_heading := 0.0
	var maximum_turn_rate := 0.0
	var maximum_drift := 0.0
	var maximum_yaw_drift := 0.0
	var maximum_ankle_error := 0.0
	var maximum_link_scale := 1.0
	var minimum_shoe_gap := INF
	var old_heading: float = ik._heading_angle
	var feet: Array[Vector3] = [ik.right_foot_smooth, ik.left_foot_smooth]
	var yaws: Array[float] = [ik._right_yaw, ik._left_yaw]
	var serials: Array[int] = [ik.right_contact_serial, ik.left_contact_serial]
	var states: Array[String] = []
	var tag := "P%d %dHz %s" % [player.player_num, hz, name]
	for frame in range(hz * 4):
		var elapsed := float(frame) / hz
		var fwd: Vector3 = player._get_forward_axis()
		var side: Vector3 = player._get_forehand_axis()
		var velocity := Vector3.ZERO
		if elapsed < 2.2:
			match name:
				"wall_reversals": velocity = (-fwd * 0.8 + side * (0.6 if int(elapsed / 0.18) % 2 == 0 else -0.6)) * 4.2
				"backpedal": velocity = -fwd * 1.2
				"backward_strafe": velocity = (-fwd + side).normalized() * 1.8
				"fast_live_retreat": velocity = -fwd * 4.2
				"chase_behind": velocity = -fwd * 3.5
				"lateral_coverage": velocity = side * 3.5
				"offset_reversal": velocity = side * (3.5 if elapsed < 1.0 else -3.5)
				"rotated_ready_left", "rotated_ready_right": velocity = (-fwd + side * 0.6).normalized().rotated(Vector3.UP, expected_heading) * 3.5
		game.ball.global_position = player.global_position + fwd * (-3.0 if name == "chase_behind" else 3.0)
		var shown := pose
		if name.begins_with("rotated_ready"):
			var gaze_angle: float = deg_to_rad(-65.0 if name.ends_with("left") else 65.0)
			shown = player._ready_tracking.apply(pose, player, player.global_position + fwd.rotated(Vector3.UP, gaze_angle) * 3.0, 1.0 / hz)
		tick(player, shown, velocity, 1.0 / hz)
		if not ik.locomotion_state in states: states.append(ik.locomotion_state)
		maximum_heading = maxf(maximum_heading, absf(ik._heading_angle))
		maximum_ready_error = maxf(maximum_ready_error, absf(angle_difference(expected_heading, ik._heading_angle)))
		var hips_forward: Vector3 = player.body_pivot.get_node("HipsMesh").global_basis * fwd
		hips_forward.y = 0.0
		maximum_hip_ready_error = maxf(maximum_hip_ready_error, absf(fwd.rotated(Vector3.UP, expected_heading).signed_angle_to(hips_forward.normalized(), Vector3.UP)))
		maximum_turn_rate = maxf(maximum_turn_rate, absf(angle_difference(old_heading, ik._heading_angle)) * hz)
		old_heading = ik._heading_angle
		var now: Array[Vector3] = [ik.right_foot_smooth, ik.left_foot_smooth]
		var now_yaws: Array[float] = [ik._right_yaw, ik._left_yaw]
		var now_serials: Array[int] = [ik.right_contact_serial, ik.left_contact_serial]
		minimum_shoe_gap = minf(minimum_shoe_gap, now[0].distance_to(now[1]))
		for foot_side in [0, 1]:
			var leg = player.right_leg_node if foot_side == 0 else player.left_leg_node
			var locked: bool = ik.right_foot_locked if foot_side == 0 else ik.left_foot_locked
			if locked:
				var knee: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, ik._knee_yaw[foot_side])
				maximum_support_gap = maxf(maximum_support_gap, absf(ik._heading_forward.signed_angle_to(knee, Vector3.UP)))
				if serials[foot_side] == now_serials[foot_side]:
					maximum_drift = maxf(maximum_drift, feet[foot_side].distance_to(now[foot_side]))
					maximum_yaw_drift = maxf(maximum_yaw_drift, absf(angle_difference(yaws[foot_side], now_yaws[foot_side])))
			maximum_ankle_error = maxf(maximum_ankle_error, leg.foot_pivot.global_position.distance_to(now[foot_side]))
			maximum_link_scale = maxf(maximum_link_scale, leg.thigh_pivot.global_position.distance_to(leg.shin_pivot.global_position) / leg.thigh_length)
			maximum_link_scale = maxf(maximum_link_scale, leg.shin_pivot.global_position.distance_to(leg.foot_pivot.global_position) / leg.shin_length)
		feet = now; yaws = now_yaws; serials = now_serials
	check(maximum_support_gap <= deg_to_rad(ik.MAX_SUPPORT_TURN_DEGREES + 0.1), tag + " hips outran planted knee %.3fdeg" % rad_to_deg(maximum_support_gap))
	check(maximum_turn_rate <= deg_to_rad(ik.TURN_RATE + 0.1), tag + " body turn rate")
	check(maximum_drift < 0.00001 and maximum_yaw_drift < 0.00001, tag + " planted shoe moved or spun")
	check(maximum_ankle_error < 0.005 and maximum_link_scale < 1.001, tag + " knee/ankle unreachable")
	check(minimum_shoe_gap >= 0.095, tag + " shoes crossed through one another")
	check(ik.is_support_ready(0) and ik.is_support_ready(1), tag + " failed court-facing recovery")
	check(maximum_ready_error < deg_to_rad(0.1), tag + " turned away from intended Ready frame")
	check(maximum_hip_ready_error < deg_to_rad(1.0), tag + " rendered hips oppose Ready %.4fdeg" % rad_to_deg(maximum_hip_ready_error))
	records.append({"case": tag, "states": states, "max_support_gap_deg": rad_to_deg(maximum_support_gap), "max_heading_deg": rad_to_deg(maximum_heading), "max_ready_error_deg": rad_to_deg(maximum_ready_error), "max_rendered_hip_ready_error_deg": rad_to_deg(maximum_hip_ready_error), "max_turn_rate_deg_s": rad_to_deg(maximum_turn_rate), "max_locked_drift_m": maximum_drift, "max_locked_yaw_drift_deg": rad_to_deg(maximum_yaw_drift), "max_ankle_error_m": maximum_ankle_error, "minimum_shoe_gap_m": minimum_shoe_gap})

	if name.begins_with("rotated_ready"):
		var serve_pose: PostureDefinition = load("res://data/postures/20_ready.tres").duplicate(true)
		ik.initialize_serve_stance(serve_pose)
		check(absf(ik._heading_angle) < 0.0001 and ik.is_support_ready(0) and ik.is_support_ready(1), tag + " serve reset retained tracking or stance ownership")
