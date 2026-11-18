extends SceneTree

const Profile = preload("res://scripts/shot_profile.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const BallScript = preload("res://scripts/ball.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void : call_deferred("run")
func check(condition: bool, message: String) -> void :
	checks += 1
	if not condition: failures.append(message)

func key(game, code: Key, echo: bool = false, ctrl: bool = false) -> void :
	var event: = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo
	event.ctrl_pressed = ctrl
	game.input_handler._unhandled_key_input(event)

func run() -> void :
	create_timer(60).timeout.connect( func(): quit(2))
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await physics_frame
	await physics_frame
	game.input_handler.set_process(false)
	check(game.selected_spin_mode == 0, "new game defaults flat")
	key(game, KEY_Q)
	check(game.selected_spin_mode == 1 and not game.posture_editor_v2.visible, "Q picks topspin without opening editor")
	key(game, KEY_Q, true)
	key(game, KEY_Q, false, true)
	check(game.selected_spin_mode == 1, "repeat/modifier do not change choice")
	key(game, KEY_Q)
	check(game.selected_spin_mode == 2, "Q picks slice")
	key(game, KEY_Q)
	check(game.selected_spin_mode == 0, "Q wraps flat")
	key(game, KEY_E)
	check(game.selected_shot_intent == "DROP" and not game.posture_editor_v2.visible, "E selects a persistent drop")
	key(game, KEY_Q)
	check(game.selected_shot_intent == "AUTO" and game.selected_spin_mode == 0, "Q exits drop to flat")
	key(game, KEY_F2)
	check(game.posture_editor_v2.visible, "F2 opens pose editor")
	key(game, KEY_Q)
	key(game, KEY_E)
	check(game.selected_spin_mode == 0 and game.selected_shot_intent == "AUTO", "shot controls ignored inside editor")
	game.posture_editor_v2.close()
	key(game, KEY_Q)
	game._reset_ball()
	check(game.selected_spin_mode == 1, "choice persists across point reset")
	game.reaction_button.auto_fire_on_perfect = false
	game.ai_difficulty = 2
	game._set_game_state(game.GameState.PLAYING)
	game.rally_scorer._serve_was_hit = true
	game.player_left.global_position = Vector3(0, game.player_left.ground_y, 3.2)
	game.player_right.set_ai_movement_enabled(false)
	var ball = game.ball
	ball.reset_rally_state()
	ball.both_bounces_complete = true
	ball.global_position = Vector3(0.42, 1.12, 1.5)
	ball.linear_velocity = Vector3(0, 1.5, 8)
	ball.angular_velocity = Vector3.ZERO
	ball.last_hit_by = 1
	ball.is_in_play = true
	ball.flight_id += 1
	await physics_frame
	await physics_frame
	var human = game.player_left.posture.human_contact
	check(human.request_swing(0.7), "reachable contact commits")
	key(game, KEY_Q)
	check(game.selected_spin_mode == 2, "next choice may change during swing")
	check(game._frozen_spin_mode == 1, "current shot stays locked to topspin")
	Input.action_press("ui_accept")
	game.input_handler._handle_swing_charge(0.25)
	check(is_equal_approx(human.charge_ratio, 0.7), "repeated Space cannot change committed power")
	Input.action_release("ui_accept")
	game.input_handler._handle_swing_charge(0.0)
	var hits: Array[int] = []
	game.ball.hit_by_paddle.connect( func(id): hits.append(id))
	for frame in range(70):
		await physics_frame
		if ball.last_hit_by == 0: break
	check(ball.last_hit_by == 0, "committed contact hits")
	if ball.last_hit_by == 0:
		check(game.last_shot_profile.get("mode", -1) == 1, "impact uses frozen profile, not new selection")
		check(game.last_shot_profile.is_read_only(), "applied profile is immutable")
		var axis: Vector3 = Vector3.UP.cross(Vector3(ball.linear_velocity.x, 0, ball.linear_velocity.z).normalized())
		check(ball.angular_velocity.dot(axis) > 10.0, "contact has real topspin angular velocity")
		check(game._frozen_spin_mode == -1, "HUD lock clears at impact")
		check(hits.count(0) == 1, "spin change does not re-hit ball")
	game.queue_free()
	await process_frame
	await verify_live_drop_shots()


	var worst_error: float = 0.0
	for aimed in [false, true]:
		for side in [-1.0, 1.0]:
			for mode in range(3):
				var live: = BallScript.new()
				root.add_child(live)
				live.collision_mask = 0
				live.global_position = Vector3(0.4, 0.9, -3.2 * side)
				live.linear_velocity = Vector3(0.6, 5.0, 10.0 * side)
				live.angular_velocity = Profile.angular_velocity(Profile.create(mode, 0.7), live.linear_velocity)
				if aimed:
					var target: = Vector3(-0.5, Flight.FLOOR_REST_Y, 4.6 * side)
					var solver = preload("res://scripts/shot_physics.gd").new()
					var launch: Dictionary = solver.solve_aimed_launch(live.global_position, target, 0.8, 0 if side < 0 else 1, mode)
					live.linear_velocity = launch.velocity
					live.angular_velocity = launch.omega
				var predicted: Dictionary = Flight.trace(live.global_position, live.linear_velocity, live.angular_velocity, 3, 1, false)
				var bounces: Array[Vector3] = []
				live.bounced.connect( func(pos): bounces.append(pos))
				for frame in range(160):
					await physics_frame
					if not bounces.is_empty(): break
				check( not bounces.is_empty(), "mode%d side%.0f bounces live" % [mode, side])
				if not bounces.is_empty():
					var error: float = Vector2(bounces[0].x - predicted.first_bounce.x, bounces[0].z - predicted.first_bounce.z).length()
					worst_error = maxf(error, worst_error)
					check(error < 0.3, "mode%d side%.0f live landing misses prediction by %.3fm" % [mode, side, error])
				live.queue_free()
				await process_frame
	for failure in failures: push_error(failure)
	print("SPIN GAMEPLAY: %d checks, %d failures; max live prediction error %.3f m" % [checks, failures.size(), worst_error])
	quit(0 if failures.is_empty() else 1)

func verify_live_drop_shots() -> void :
	var speeds: Array[float] = []
	for charge in [0.0, 0.5, 1.0]:
		var game = load("res://scenes/game.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		await physics_frame
		await physics_frame
		game.input_handler.set_process(false)
		game.reaction_button.auto_fire_on_perfect = false
		game.ai_difficulty = 2
		game._set_game_state(game.GameState.PLAYING)
		game.rally_scorer._serve_was_hit = true
		game.player_left.global_position = Vector3(0, game.player_left.ground_y, 3.2)
		game.player_right.set_ai_movement_enabled(false)
		var ball = game.ball
		ball.reset_rally_state()
		ball.both_bounces_complete = true
		ball.global_position = Vector3(0.42, 1.12, 1.5)
		ball.linear_velocity = Vector3(0, 1.5, 8)
		ball.angular_velocity = Vector3.ZERO
		ball.last_hit_by = 1
		ball.is_in_play = true
		ball.flight_id += 1
		await physics_frame
		await physics_frame
		key(game, KEY_E)
		var human = game.player_left.posture.human_contact
		check(human.request_swing(charge), "drop commits reachable contact")
		key(game, KEY_Q)
		check(game.selected_shot_intent == "AUTO" and game._frozen_shot_intent == "DROP", "Q changes next shot without replacing committed drop")
		for frame in range(70):
			await physics_frame
			if ball.last_hit_by == 0: break
		check(ball.last_hit_by == 0, "drop reaches physical paddle contact")
		if ball.last_hit_by == 0:
			check(game.last_shot_profile.get("shot_type", "") == "DROP", "impact keeps frozen drop intent")
			speeds.append(ball.linear_velocity.length())
			var prediction: Dictionary = Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity, 3, 1, false)
			var target_depth: float = - float(ball.get_meta("aim_target", Vector3(0, 0, -1.15)).z)
			check(absf(prediction.first_bounce.z + target_depth) < 0.16, "drop preserves its frozen short cursor")
			var landings: Array[Vector3] = []
			ball.bounced.connect( func(pos): landings.append(pos))
			for frame in range(150):
				await physics_frame
				if not landings.is_empty(): break
			check( not landings.is_empty(), "drop bounces in real court")
			if not landings.is_empty():
				check(landings[0].z < -0.45 and landings[0].z > -1.8, "live drop lands safely short")
				check(absf(landings[0].z + target_depth) < 0.25, "live drop preserves frozen cursor depth")
		check( not ball.get_collision_exceptions().has(game.player_left.paddle_node), "paddle grace expires after egress")
		ball.suppress_paddle_collision(game.player_left.paddle_node)
		ball.reset()
		check( not ball.get_collision_exceptions().has(game.player_left.paddle_node), "reset immediately restores paddle collisions")
		check(ball.collision_mask == 7, "paddle grace preserves body, net and floor collision mask")
		game.queue_free()
		await process_frame
	if speeds.size() == 3:
		check(speeds[2] < speeds[0] + 1.0, "full drop charge does not become drive power")
