extends SceneTree
## Run separately: Godot --headless --path . --script res://scripts/tests/test_normal_serve_flow.gd
const Flight = preload("res://scripts/ball_flight_predictor.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	seed(77811)
	var failures: Array[String] = []
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	var legal_serves: int = 0
	for side in range(2):
		for parity in range(2):
			game.score_left = parity
			game.score_right = 0
			for charge in [0.15, 0.35, 0.65, 1.0]:
				var start: Vector3 = game.game_serve.get_serve_launch_position(side == 1)
				var velocity: Vector3 = game.game_serve.get_predicted_serve_velocity(charge, side == 1)
				var preview: Vector3 = game.game_trajectory._get_predicted_serve_velocity(charge, side == 1)
				if velocity.distance_to(preview) > 0.001:
					failures.append("serve preview velocity diverged")
				var flight: Dictionary = Flight.trace(start, velocity, Vector3.ZERO, 3.0, 1, false)
				var landing: Vector3 = flight["first_bounce"]
				var legal_z: bool = landing.z > 2.134 and landing.z < 6.7 if side == 1 \
					else landing.z < -2.134 and landing.z > -6.7
				var expected_x: float = 1.0 if side == 1 else -1.0
				if parity == 1:
					expected_x *= -1.0
				if legal_z and signf(landing.x) == expected_x and absf(landing.x) < 3.05 and not flight["net_hit"]:
					legal_serves += 1
				else:
					failures.append("side%d parity%d charge%.2f landed at %s" % [side, parity, charge, landing])
	game.queue_free()
	await physics_frame
	print("SERVE FLIGHT: %d/16 legal diagonal landings" % legal_serves)

	var live_returns: int = 0
	for charge in [0.2, 0.4, 0.65, 0.9]:
		var rally: Node = load("res://scenes/game.tscn").instantiate()
		root.add_child(rally)
		await physics_frame
		await physics_frame
		rally.serving_team = 0
		rally._on_player_swing_press()
		for frame in range(6):
			await physics_frame
		if rally.serve_charge_time <= 0.0 or not rally.game_trajectory.trajectory_mesh_instance.visible:
			failures.append("charge %.2f did not show a serve preview" % charge)
		rally._on_player_swing_release(charge)
		if rally.game_state != rally.GameState.PLAYING or not rally.player_right.ai_movement_enabled or not rally.ball.is_in_play:
			failures.append("charge %.2f did not start a live rally" % charge)
		var moved: bool = false
		var returned: bool = false
		var initial_ai_pos: Vector3 = rally.player_right.global_position
		for frame in range(180):
			await physics_frame
			if rally.player_right.global_position.distance_to(initial_ai_pos) > 0.1:
				moved = true
			if rally.ball.last_hit_by == 1:
				returned = true
				break
			if rally.game_state != rally.GameState.PLAYING:
				break
		if moved and returned and rally.game_state == rally.GameState.PLAYING:
			live_returns += 1
		else:
			failures.append("charge %.2f serve: moved=%s returned=%s state=%d" % [charge, moved, returned, rally.game_state])
		rally.queue_free()
		await physics_frame
	print("NORMAL SERVE RALLIES: %d/4 AI returns" % live_returns)

	var ai_serves: int = 0
	for parity in range(2):
		var ai_game: Node = load("res://scenes/game.tscn").instantiate()
		root.add_child(ai_game)
		await physics_frame
		ai_game.score_left = parity
		ai_game.score_right = 0
		ai_game.serving_team = 1
		ai_game._reset_ball()
		var launched: Array[int] = []
		var first_bounce: Array[Vector3] = []
		ai_game.game_serve.serve_launched.connect(func(team: int) -> void: launched.append(team))
		ai_game.ball.bounced.connect(func(pos: Vector3) -> void: first_bounce.append(pos))
		for frame in range(210):
			await physics_frame
			if not first_bounce.is_empty():
				break
		if launched.size() != 1 or launched[0] != 1:
			failures.append("Red auto-serve parity%d did not launch" % parity)
		elif first_bounce.is_empty():
			failures.append("Red auto-serve parity%d did not bounce" % parity)
		else:
			var landing: Vector3 = first_bounce[0]
			var expected_x: float = 1.0 if parity == 0 else -1.0
			if signf(landing.x) != expected_x or landing.z <= 2.134 or landing.z >= 6.7:
				failures.append("Red auto-serve parity%d landed outside diagonal at %s" % [parity, landing])
			elif ai_game.game_state != ai_game.GameState.PLAYING:
				failures.append("Red auto-serve parity%d was faulted on landing" % parity)
			else:
				ai_serves += 1
		ai_game.queue_free()
		await physics_frame
	print("AI AUTO-SERVE: %d/2 live diagonal serves" % ai_serves)
	if failures.is_empty():
		print("NORMAL SERVE FLOW PASS")
	else:
		for failure in failures:
			push_error(failure)
		print("NORMAL SERVE FLOW FAIL: ", failures)
	quit(0 if failures.is_empty() else 1)
