extends SceneTree

var failures: Array[String] = []
var hits: = 0
func _initialize() -> void : call_deferred("run")
func run() -> void :
	create_timer(25).timeout.connect( func(): quit(2))
	for trajectory in [Vector3(1.65, 4.0, 5.0), Vector3(1.85, 3.0, 5.0), Vector3(1.9, 2.5, 6.0)]:
		var game = load("res://scenes/game.tscn").instantiate()
		root.add_child(game);current_scene = game
		await physics_frame; await physics_frame
		game.input_handler.set_process(false)
		game.reaction_button.auto_fire_on_perfect = false
		game._set_game_state(game.GameState.PLAYING)
		game.rally_scorer._serve_was_hit = true
		var p = game.player_left
		p.global_position = Vector3(0, p.ground_y, 3.5)


		p.leg_ik.feet_initialized = false
		p._process(0.0)
		if not p.can_volley_from_feet(): failures.append("Fixture did not establish both shoes outside")
		game.player_right.set_ai_movement_enabled(false)
		var b = game.ball
		b.reset_rally_state();b.both_bounces_complete = true
		b.bounces_since_last_hit = 0;b.last_hit_by = 1;b.is_in_play = true
		b.global_position = Vector3(0, trajectory.x, 1.0)
		b.linear_velocity = Vector3(0, trajectory.y, trajectory.z)
		b.angular_velocity = Vector3.ZERO;b.flight_id += 1
		await physics_frame; await physics_frame
		var h = p.posture.human_contact
		if h.contact.is_empty():
			if trajectory != Vector3(1.65, 4.0, 5.0): failures.append("No contact prediction for %s" % trajectory)
			game._perform_player_swing(0.95)
			if not p._contextual_jump.is_empty(): failures.append("Unreachable trajectory incorrectly queued jump")
		else:
			print("[JUMP CONTACT] fixture=", trajectory, " posture=", h.contact.posture, " point=", h.contact.point, " time=", h.contact.time)
			h.set_charge(0.95)
			game._perform_player_swing(0.95)
			if p._contextual_jump.is_empty(): failures.append("No contextual jump queued for %s" % trajectory)
		var observation: = {"error": -1.0, "air": false}
		b.hit_by_paddle.connect( func(side):
			if side == 0:
				observation.error = PaddleReach.head_world(p).distance_to(b.global_position)
				observation.air = p.is_jumping
		)
		var peak: = 0.0
		for frame in range(90):
			await physics_frame
			peak = maxf(peak, p.global_position.y - p.ground_y)
			if b.last_hit_by == 0 and p.global_position.y == p.ground_y and not p.is_jumping: break
		print("[JUMP CONTACT] result fixture=", trajectory, " peak=", peak, " error=", observation.error, " air=", observation.air, " hitter=", b.last_hit_by)
		if trajectory == Vector3(1.65, 4.0, 5.0):
			if peak > 0.001 or b.last_hit_by == 0: failures.append("Unreachable flight fabricated jump/contact")
			game.queue_free(); await process_frame
			continue
		if b.last_hit_by != 0: failures.append("No real hit for %s" % trajectory)
		elif observation.error > 0.10001: failures.append("Hit outside unchanged 10cm actual radius")
		else: hits += 1
		if not observation.air: failures.append("Contact was not airborne for %s" % trajectory)
		if p.is_jumping or absf(p.global_position.y - p.ground_y) > 0.001: failures.append("Did not finish landing")
		game.queue_free(); await process_frame
	print("[JUMP CONTACT] %d real airborne hits, %d failures" % [hits, failures.size()])
	for failure in failures: print("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
