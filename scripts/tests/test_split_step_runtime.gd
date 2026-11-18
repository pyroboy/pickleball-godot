extends "res://scripts/tests/test_scaled_body_gait.gd"
const Split = preload("res://scripts/split_step_timing.gd")
const Observer = preload("res://scripts/split_step_observer.gd")
const Human = preload("res://scripts/human_contact_controller.gd")
func run() -> void:
	var pause = root.get_node_or_null("PauseController")
	if pause:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
		pause.close()
	paused = false
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	for i in 5: await process_frame
	game.game_serve.cleanup(); game.process_mode = Node.PROCESS_MODE_DISABLED
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false); node.set_physics_process(false)
	for hz in [30, 60, 120]:
		for p in [game.player_left, game.player_right]:
			for held in [false, true]: _receive(p, hz, held)
	var f := FileAccess.open("/tmp/split-step-runtime.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks": checks, "failures": failures, "records": records}, "\t")); f.close()
	for failure in failures: push_error(failure)
	print("SPLIT STEP RUNTIME: %d checks, %d failures" % [checks, failures.size()])
	game.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
func fixture(p) -> PostureDefinition:
	var ready: PostureDefinition = PostureLibrary.instance().get_def(20).duplicate(true)
	for person in [game.player_left, game.player_right]:
		person.hitting.is_in_follow_through = false; person.hitting.charge_visual_active = false; person.hitting.serving_visual_active = false
		if person.posture.human_contact != null: person.posture.human_contact.cancel(false)
		person.leg_ik.drive_preparation.reset()
		person.pose_controller.split_step = Split.new(); person.pose_controller.split_observer = Observer.new()
		reset(person, ready)
		person.global_position = Vector3(0, person.ground_y, 3.8 if person.player_num == 0 else -3.8)
		person.leg_ik.feet_initialized = false
		tick(person, ready, Vector3.ZERO, 1.0 / 60)
	game.ball.freeze = true; game.ball.is_in_play = true; game.ball.both_bounces_complete = true
	game.ball.flight_id += 10; game.ball.last_hit_by = p.player_num; game.ball.bounces_since_last_hit = 0
	game.ball.global_position = Vector3(0, 1, 0); game.ball.linear_velocity = Vector3.ZERO
	game.practice_launcher.is_active = false
	return ready
func _receive(p, hz: int, held: bool = false) -> void:
	var ready := fixture(p)
	p.hitting.charge_visual_active = held
	var opponent = game.player_right if p.player_num == 0 else game.player_left
	var original_human = opponent.posture.human_contact
	if original_human == null: opponent.posture.human_contact = Human.new(opponent, opponent.posture)
	var human = opponent.posture.human_contact
	human.phase = 1; human.strike_time = .15; human.elapsed = 0.0; human.hit = false
	var timing = p.pose_controller.split_step
	var peak := 0.0; var toe := 0.0; var minimum_sole := INF
	var lifted := false; var phases := {}; var root_start: Vector3 = p.global_position
	var feet: Array[Vector3] = [p.leg_ik.right_foot_smooth, p.leg_ik.left_foot_smooth]
	for frame in range(hz):
		var t: float = float(frame) / hz
		human.elapsed = minf(t, .15)
		if frame == ceili(.15 * hz):
			game.ball.hit_by_player(opponent.player_num)
			human.hit = true; human.phase = -1
		p.ai_brain._perception_ready = t >= .45
		p.ai_brain._observed_flight_id = game.ball.flight_id
		p.ai_brain.ai_selected_contact_reachable = false
		p.current_velocity = Vector3.ZERO
		p.pose_controller.update_runtime_pose_state(1.0 / hz)
		tick(p, ready, Vector3.ZERO, 1.0 / hz)
		var sample: Dictionary = timing.sample()
		phases[timing.phase] = true
		peak = maxf(peak, sample.foot_lift); toe = maxf(toe, sample.ankle_pitch_deg)
		if sample.foot_lift > .005:
			lifted = lifted or p.leg_ik.right_foot_smooth.y > p.leg_ik.ANKLE_HEIGHT + .004
			check(not p.leg_ik.right_foot_locked and not p.leg_ik.left_foot_locked, "Airborne soles unlock P%d %dHz" % [p.player_num, hz])
		minimum_sole = minf(minimum_sole, minf(sole_y(p.right_leg_node.foot_mesh), sole_y(p.left_leg_node.foot_mesh)))
		check(sample.ankle_pitch_deg >= 0 and sample.ankle_pitch_deg <= 12, "Toe-down bounded")
	check(timing.hop_count == 1 and timing.event_serial == 1 and timing.strike_count == 1, "Observed one strike/split P%d %dHz" % [p.player_num, hz])
	check(peak > .015 and lifted, "Runtime observer actually lifts both feet P%d %dHz" % [p.player_num, hz])
	check(toe > 1.0, "Runtime airborne toe-down sample P%d %dHz" % [p.player_num, hz])
	check(p.global_position == root_start, "No gameplay-root displacement")
	check(minimum_sole >= .075 - .002, "No sole penetrates court")
	check(p.leg_ik.right_foot_smooth.distance_to(feet[0]) < .001 and p.leg_ik.left_foot_smooth.distance_to(feet[1]) < .001, "Land on captured contacts")
	check(p.leg_ik.right_foot_locked and p.leg_ik.left_foot_locked, "Reacquire both contacts")
	# Repeated physics notifications of one flight do not manufacture another hop.
	for frame in hz: p.pose_controller.update_runtime_pose_state(1.0 / hz)
	check(timing.event_serial == 1, "Duplicate observed contact cannot retrigger")
	# New cue while traveling is consumed without hopping or slowing travel.
	game.ball.hit_by_player(p.player_num); human.phase = 1; human.hit = false; human.elapsed = 0
	p.current_velocity = Vector3(1, 0, 0); p.pose_controller.update_runtime_pose_state(1.0 / hz)
	check(timing.hop_count == 1 and timing.sample().foot_lift == 0.0 and p.current_velocity.x == 1.0, "Moving receive skips hop without movement delay")
	# Exact contact refresh interrupts any cosmetic hop, even with no time advance.
	timing.update(.01, {"cue_id": game.ball.flight_id + 20, "cue_lead": .15})
	timing.update(.07, {})
	p.hitting.is_in_follow_through = true
	p.leg_ik.update_leg_ik(0.0, ready)
	check(timing.sample().foot_lift == 0 and p.leg_ik.right_foot_locked and p.leg_ik.left_foot_locked, "Own contact zero-clock refresh cancels/grounds")
	p.hitting.is_in_follow_through = false
	for interrupted in ["editor", "deadball", "serve", "jump"]:
		timing = Split.new(); p.pose_controller.split_step = timing
		timing.update(.01, {"cue_id": 1, "cue_lead": .15}); timing.update(.07, {})
		match interrupted:
			"editor": p.posture.editor_preview_mode = true
			"deadball": game.ball.is_in_play = false
			"serve": p.hitting.serving_visual_active = true
			"jump": p.is_jumping = true
		p.pose_controller.update_runtime_pose_state(1.0 / hz)
		check(timing.phase == "ready" and timing.sample().foot_lift == 0.0, interrupted + " cancels runtime split")
		p.posture.editor_preview_mode = false; game.ball.is_in_play = true; p.hitting.serving_visual_active = false; p.is_jumping = false
	opponent.posture.human_contact = original_human
	records.append({"side": p.player_num, "hz": hz, "held_ready": held, "peak_lift": peak, "peak_toe_down_deg": toe, "minimum_sole_y": minimum_sole, "phases": phases.keys()})
