extends SceneTree
## Integration check: Godot --headless --path . --script res://scripts/tests/test_ai_live_rally.gd
## Uses real physics frames and the real game AI hit method.
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const BallScript = preload("res://scripts/ball.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var live_ball: Ball = BallScript.new()
	root.add_child(live_ball)
	live_ball.collision_mask = 0
	await physics_frame
	var cases: Array[Dictionary] = [
		{"name": "flat", "pos": Vector3(0, 1.3, 4.5), "vel": Vector3(0.4, 2, -11), "spin": Vector3.ZERO},
		{"name": "topspin", "pos": Vector3(0, 1.3, 4.5), "vel": Vector3(0.4, 2, -11), "spin": Vector3(-35, 0, 0)},
		{"name": "backspin", "pos": Vector3(0, 1.3, 4.5), "vel": Vector3(0.4, 2, -11), "spin": Vector3(35, 0, 0)},
		{"name": "sidespin", "pos": Vector3(0, 1.3, 4.5), "vel": Vector3(0.4, 2, -11), "spin": Vector3(0, 35, 0)},
		{"name": "soft", "pos": Vector3(0, 1.0, 2.5), "vel": Vector3(0.2, 2, -6), "spin": Vector3(-12, 0, 0)},
		{"name": "fast", "pos": Vector3(0, 1.2, 5.0), "vel": Vector3(0.4, 1, -18), "spin": Vector3(-42, 0, 0)},
	]
	var failures: Array[String] = []
	for scenario in cases:
		live_ball.reset()
		live_ball.global_position = scenario.pos
		live_ball.linear_velocity = scenario.vel
		live_ball.angular_velocity = scenario.spin
		var predicted: Dictionary = Flight.trace(scenario.pos, scenario.vel, scenario.spin, 2.0, 1, false)
		var actual := [Vector3.INF]
		var callback := func(hit: Vector3) -> void: actual[0] = hit
		live_ball.bounced.connect(callback)
		var contact_error: float = 0.0
		for frame in range(120):
			await physics_frame
			if frame == 14:
				contact_error = live_ball.global_position.distance_to(predicted["samples"][15]["pos"])
			if actual[0] != Vector3.INF:
				break
		live_ball.bounced.disconnect(callback)
		var bounce_error: float = Vector2(actual[0].x - predicted["first_bounce"].x,
			actual[0].z - predicted["first_bounce"].z).length()
		print("AI LIVE %s: bounce=%.3f m contact=%.3f m" % [scenario.name, bounce_error, contact_error])
		if bounce_error > 0.20 or contact_error > 0.25:
			failures.append("%s bounce %.3f contact %.3f" % [scenario.name, bounce_error, contact_error])

	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	await physics_frame
	var game_ball: Ball = game.ball
	var brain: PlayerAIBrain = game.player_right.ai_brain
	for difficulty in range(3):
		brain.ai_difficulty = difficulty
		game_ball.flight_id += 1
		var expected_frames: int = brain._get_latency_frames() + 1
		for sample_index in range(expected_frames - 1):
			brain._sample_ball_history(game_ball)
			if brain._perception_ready:
				failures.append("difficulty %d reacted before its delay" % difficulty)
		brain._sample_ball_history(game_ball)
		if not brain._perception_ready:
			failures.append("difficulty %d did not react after its delay" % difficulty)
	print("AI REACTION: Easy, Medium, Hard delays preserved")
	game.player_right.global_position.z = -3.0
	game_ball.global_position = Vector3(-1.5, 1.2, 3.5)
	game_ball.linear_velocity = Vector3(0, 4, -10)
	game_ball.angular_velocity = Vector3.ZERO
	game_ball.both_bounces_complete = true
	brain._perceived_state = {"pos": game_ball.global_position, "vel": game_ball.linear_velocity,
		"omega": game_ball.angular_velocity}
	brain._predicted_flight_frame = -1
	var reachable: Dictionary = brain._get_ai_intercept_solution(game_ball.global_position)
	if not reachable["reachable"] or reachable["time"] <= 0.0:
		failures.append("legal interception was not selected")
	game_ball.global_position = Vector3(3.0, 0.5, -0.5)
	game_ball.linear_velocity = Vector3(0, -1, -17)
	brain._perceived_state = {"pos": game_ball.global_position, "vel": game_ball.linear_velocity,
		"omega": game_ball.angular_velocity}
	brain._predicted_flight_frame = -1
	var impossible: Dictionary = brain._get_ai_intercept_solution(game_ball.global_position)
	if impossible["reachable"]:
		failures.append("impossible interception was marked reachable")
	print("AI INTERCEPT: reachable=%s impossible=%s" % [reachable["reachable"], impossible["reachable"]])
	if reachable["reachable"]:
		live_ball.reset()
		live_ball.global_position = Vector3(-1.5, 1.2, 3.5)
		live_ball.linear_velocity = Vector3(0, 4, -10)
		live_ball.angular_velocity = Vector3.ZERO
		for frame in range(roundi(reachable["time"] * Engine.physics_ticks_per_second)):
			await physics_frame
		var selected_error: float = live_ball.global_position.distance_to(reachable["contact"])
		print("AI SELECTED CONTACT: %.3f m error" % selected_error)
		if selected_error > 0.25:
			failures.append("selected AI contact diverged by %.3f m" % selected_error)

	game.player_right.global_position.z = -6.8
	seed(33)
	var successful_hits: int = 0
	for difficulty in range(3):
		game.ai_difficulty = difficulty
		brain.ai_difficulty = difficulty
		for court_z in [-5.0, -3.0, -1.0]:
			for height in [0.5, 0.9, 1.4]:
				for charge in [0.35, 0.6, 0.9]:
					game_ball.global_position = Vector3(-0.5, height, court_z)
					game_ball.linear_velocity = Vector3.ZERO
					game_ball.angular_velocity = Vector3.ZERO
					game_ball.last_hit_by = 0
					brain.ai_hit_cooldown = 0.0
					brain.ai_charge_time = brain.AI_CHARGE_DURATION * charge
					brain._apply_ai_hit(game_ball, charge)
					var shot: Dictionary = Flight.trace(game_ball.global_position,
						game_ball.linear_velocity, game_ball.angular_velocity, 3.0, 1, false)
					var landing: Vector3 = shot["first_bounce"]
					if not shot["net_hit"] and not shot["net_crossing"].is_empty() \
							and absf(landing.x) < 3.05 and landing.z > 0.0 and landing.z < 6.7:
						successful_hits += 1
	print("AI GAMEPLAY HITS: %d/81 legal launches" % successful_hits)
	if successful_hits < 77:
		failures.append("AI gameplay hit path cleared net and landed in bounds only %d/81 times" % successful_hits)
	var return_pos: Vector3 = game_ball.global_position
	var return_vel: Vector3 = game_ball.linear_velocity
	var return_spin: Vector3 = game_ball.angular_velocity
	var return_prediction: Dictionary = Flight.trace(return_pos, return_vel, return_spin, 3.0, 1, false)
	live_ball.reset()
	live_ball.global_position = return_pos
	live_ball.linear_velocity = return_vel
	live_ball.angular_velocity = return_spin
	var return_actual := [Vector3.INF]
	var return_callback := func(hit: Vector3) -> void: return_actual[0] = hit
	live_ball.bounced.connect(return_callback)
	for frame in range(150):
		await physics_frame
		if return_actual[0] != Vector3.INF:
			break
	live_ball.bounced.disconnect(return_callback)
	var return_error: float = Vector2(return_actual[0].x - return_prediction["first_bounce"].x,
		return_actual[0].z - return_prediction["first_bounce"].z).length()
	print("AI LIVE RETURN: %.3f m bounce error" % return_error)
	if return_error > 0.20:
		failures.append("AI return bounce diverged by %.3f m" % return_error)

	game.player_right.global_position = Vector3(-1.5, game.player_right.ground_y, -3.0)
	game._set_game_state(game.GameState.PLAYING)
	game.rally_scorer._serve_was_hit = true
	game_ball.reset_rally_state()
	game_ball.both_bounces_complete = true
	game_ball.global_position = Vector3(-1.5, 1.2, 3.5)
	game_ball.linear_velocity = Vector3(0, 4, -10)
	game_ball.angular_velocity = Vector3.ZERO
	game_ball.last_hit_by = 0
	game_ball.is_in_play = true
	game_ball.flight_id += 1
	brain.ai_hit_cooldown = 0.0
	var live_return: bool = false
	for frame in range(180):
		await physics_frame
		if game_ball.last_hit_by == 1:
			live_return = true
			break
	print("AI CONTINUOUS RALLY: returned=%s" % live_return)
	if not live_return:
		failures.append("AI missed the reachable live rally shot")

	live_ball.queue_free()
	game.queue_free()
	if failures.is_empty():
		print("AI LIVE PASS")
	else:
		for failure in failures:
			push_error(failure)
		print("AI LIVE FAIL: ", failures)
	quit(0 if failures.is_empty() else 1)
