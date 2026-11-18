## Test-only copy of test_match_practice_flow.gd, SHA256 54826a4b72f615782856a82a3945ae3cf5d503e6e04b0cb445a8b9a006c302b1.
## All108 original checks preserved;60Hz latency expectation and three frame budgets are wall-clock-scaled.
extends SceneTree

const Flight = preload("res://scripts/ball_flight_predictor.gd")
var failures: Array[String] = []
var checks: = 0
func _initialize() -> void :
	call_deferred("run")
func check(condition: bool, description: String) -> void :
	checks += 1
	if not condition: failures.append(description)
func run() -> void :
	create_timer(40.0).timeout.connect( func(): quit(2))
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	var practice = game.practice_launcher
	var pause = root.get_node("PauseController")

	for team in [0, 1]:
		for points in [[2, 3], [3, 2], [10, 9], [9, 10]]:
			game.score_left = points[0]
			game.score_right = points[1]
			game.serving_team = team
			game._reset_ball()
			var right: bool = points[team] %2 == 0
			check((game.player_left.global_position.x > 0) == right, "spawn uses wrong server parity")
			var server = game.player_left if team == 0 else game.player_right
			check(game.rally_scorer.check_server_position(server.global_position, team, int(right)).valid, "spawned server is foot-faulted")
			var launch: Dictionary = game.game_serve.get_predicted_serve_launch(0.55, team == 1, 0)
			var flight: Dictionary = Flight.trace(game.game_serve.get_serve_launch_position(team == 1), launch.velocity, launch.omega, 3.0, 1, false)
			var expected_x: float = (1.0 if team == 1 else -1.0) * (1.0 if right else -1.0)
			check(signf(flight.first_bounce.x) == expected_x and not flight.net_hit, "serve lands in wrong diagonal at unequal scores")
			game._set_game_state(game.GameState.PLAYING)
			check(game.rally_scorer._serving_from_right == right, "scorer uses wrong server parity")

	game.score_left = 4
	game.score_right = 3
	game.serving_team = 0
	game._reset_ball()
	game._on_point_scored(1)
	game._on_point_scored(1)
	check(game.score_left == 4 and game.score_right == 3 and game.serving_team == 1, "side-out or double-notification scoring incorrect")

	practice.start_drill("DRIVE")
	var drive_origin: Vector3 = game.ball.global_position
	var drive_velocity: Vector3 = game.ball.linear_velocity
	var drive_spin: Vector3 = game.ball.angular_velocity
	check(game.game_state == game.GameState.PLAYING and game.ball.is_in_play, "drive starts in SERVING instead of PLAYING")
	check(game.ball.both_bounces_complete and game.rally_scorer._serve_was_hit, "drive feed incorrectly treated as new serve")
	game.ball.bounces_since_last_hit = 3
	game.ball.was_volley = true
	game.ball.last_hit_by = 0
	game.ball.angular_velocity = Vector3(23, 41, 1)
	practice.repeat_drill()
	check(game.ball.global_position.is_equal_approx(drive_origin) and game.ball.linear_velocity.is_equal_approx(drive_velocity) and game.ball.angular_velocity.is_equal_approx(drive_spin), "repeat did not preserve exact feed")
	check(game.ball.bounces_since_last_hit == 0 and not game.ball.was_volley and game.ball.last_hit_by == 1, "repeat retained old rally state")
	practice.finish_attempt(0, "IN BOUNDS", "Good drive")
	practice.finish_attempt(0, "IN BOUNDS", "Duplicate")
	check(practice.success_count == 1 and game.score_left == 4 and game.score_right == 3, "practice success corrupted match score")
	practice.stop_practice()
	practice.stop_practice()
	check( not practice.is_active and game.serving_team == 1 and game.score_left == 4 and game.score_right == 3, "practice exit failed to restore match")
	game.serving_team = 0
	game._reset_ball()
	game.game_state = game.GameState.PLAYING
	await create_timer(1.7).timeout
	check(game.game_state == game.GameState.PLAYING, "old point timer reset a new rally")

	practice.start_drill("SERVE")
	practice.loop_enabled = false
	check(game.game_state == game.GameState.WAITING and game.serving_team == 0, "serve drill is not ready to serve")
	game._perform_serve(0.55)
	for frame in range(ceili(240.0 / 60.0 * Engine.physics_ticks_per_second)):
		await physics_frame
		if practice._attempt_finished: break
	check(practice._attempt_finished and practice.success_count == 1, "legal serve drill never records success")
	check(game.score_left == 4 and game.score_right == 3, "serve drill changed score")
	practice.repeat_drill()
	game.player_left.global_position.z = 3.0
	game._perform_serve(0.55)
	check(practice._attempt_finished and practice.status_text.to_lower().contains("foot fault"), "serve foot-fault feedback missing")
	practice.start_drill("RETURN")
	practice.loop_enabled = false
	for frame in range(ceili(30.0 / 60.0 * Engine.physics_ticks_per_second)):
		await physics_frame
		if game.game_state == game.GameState.PLAYING: break
	check(game.game_state == game.GameState.PLAYING and game.ball.last_hit_by == 1 and not game.ball.both_bounces_complete, "return drill is not a real two-bounce serve")
	check( not game.player_right.ai_movement_enabled, "drill opponent chases the feed")
	practice.finish_attempt(1, "MISSED RETURN", "Move behind the bounce")
	practice.loop_enabled = true
	var before_repeat: int = practice.attempt_count
	practice._process(practice.PRACTICE_LOOP_INTERVAL + 0.01)
	check(practice.attempt_count == before_repeat + 1 and not practice._attempt_finished, "finished drill does not automatically repeat")
	practice.finish_attempt(1, "MISSED RETURN", "Move behind the bounce")
	var attempt: int = practice.attempt_count
	pause.open()
	await create_timer(1.9, true).timeout
	check(practice.attempt_count == attempt, "practice repeats while paused")
	pause.close()
	practice.stop_practice()

	game.score_left = 10
	game.score_right = 10
	game.serving_team = 0
	game._reset_ball()
	game._on_point_scored(0)
	check( not game.match_over and game.score_left == 11, "win-by-two incorrectly ends an 11-10 match")
	pause.open()
	await create_timer(1.8, true).timeout
	check(game.game_state == game.GameState.POINT_SCORED, "point countdown advances under pause")
	pause.close()
	for frame in range(ceili(950.0 / 60.0 * Engine.physics_ticks_per_second)):
		await physics_frame
		if not game.between_point_controller.is_active(): break
	check(game.game_state == game.GameState.WAITING, "point retrieval does not resume after pause")
	game._on_point_scored(0)
	check(game.match_over and game.score_left == 12 and game.score_right == 10 and game.match_winner == 0, "12-10 win not retained")
	await create_timer(3.1).timeout
	check(game.match_over and game.score_left == 12 and game.practice_panel.visible, "final score silently reset or rematch missing")
	game.request_rematch()
	game.request_rematch()
	check( not game.match_over and game.score_left == 0 and game.score_right == 0 and game.game_state == game.GameState.WAITING, "repeated Rematch failed")

	game.game_serve.start_charge()
	game.game_serve.tick_charge(0.2)
	game._perform_serve(0.5)
	check(game.game_serve.is_release_pending(), "expected a pending serve")
	practice.start_drill("DRIVE")
	check( not game.game_serve.is_release_pending() and not game.ball.freeze and not game.game_serve.is_charging(), "practice retained pending serve/freeze")
	check( not game.aim_controller.is_locked() and game._frozen_spin_mode == -1 and game.player_left._contextual_jump.is_empty(), "practice retained aim/spin/jump state")
	practice.stop_practice()

	for resolution in [Vector2i(720, 1280), Vector2i(390, 844), Vector2i(1440, 900)]:
		root.content_scale_size = resolution
		root.size = resolution
		pause.open()
		game.practice_panel.open_practice()
		var count: int = game.practice_panel._content.get_child_count()
		game.practice_panel.open_practice()
		await process_frame
		await process_frame
		for widget in game.practice_panel._content.get_children():
			if widget is Button:
				check(widget.size.y >= (96.0 * resolution.x / 720.0 if resolution.y > resolution.x else 48.0) - 1.0, "practice touch target too small")
		check(count == game.practice_panel._content.get_child_count(), "reopening practice duplicates controls")
		check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(game.practice_panel._panel.get_global_rect()), "drill picker offscreen at %s" % resolution)
		game.practice_panel.close_picker()
		check( not game.practice_panel.visible and paused, "Back left gameplay running behind pause")
		pause.close()

	var brain = game.player_right.ai_brain
	for difficulty in [0, 1, 2]:
		brain.ai_difficulty = difficulty
		# Same wall-clock difficulty latency at the actual engine tick rate.
		var latency: int = roundi(float([18, 12, 8][difficulty]) / 60.0 * Engine.physics_ticks_per_second)
		check(brain._get_latency_frames() == latency, "difficulty reaction delay unchanged")
		game.ball.flight_id += 1
		brain._sample_ball_history(game.ball)
		check( not brain._perception_ready, "AI sees new flight instantly")
		for frame in range(latency): brain._sample_ball_history(game.ball)
		check(brain._perception_ready, "AI never becomes ready after difficulty delay")
	game.queue_free()
	await process_frame
	await process_frame
	for failure in failures: push_error(failure)
	print("MATCH PRACTICE FLOW: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
