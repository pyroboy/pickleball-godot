extends RefCounted


const Footwork = preload("res://scripts/charged_footwork.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")

static func cases() -> Array[Dictionary]:
	return [
		{"name": "short_forehand", "root_z": 4.7, "lateral": 1.0, "height": 1.12, "forward": 0.7, "duration": 1.65, "family": 0}, 
		{"name": "wide_forehand", "root_z": 4.7, "lateral": 2.1, "height": 1.1, "forward": 0.7, "duration": 1.75, "family": 0}, 
		{"name": "wide_backhand", "root_z": 4.7, "lateral": -2.1, "height": 1.1, "forward": 0.7, "duration": 1.75, "family": 1}, 
		{"name": "forward_neutral", "root_z": 4.7, "lateral": 0.6, "height": 0.68, "forward": 1.62, "duration": 1.75, "family": 0}, 
		{"name": "impossible", "root_z": 4.7, "lateral": 4.8, "height": 1.1, "forward": 0.7, "duration": 0.65, "family": 0, "impossible": true}, 
	]

static func configure(game) -> void :
	game.input_handler.set_process(false)
	game.reaction_button.auto_fire_on_perfect = false
	game.ai_difficulty = 2
	game.pvp_mode = true
	game.aim_focus._sync_realtime_mode()
	game.player_right.set_ai_movement_enabled(false)

static func prepare(game, data: Dictionary) -> Dictionary:
	Input.action_release("ui_accept")
	for action in ["move_left", "move_right", "move_up", "move_down"]: Input.action_release(action)
	game.input_handler.cancel_charge_input()
	game.input_handler._handle_swing_charge(0.0)
	game._reset_ball()
	game.between_point_controller.cancel()
	game._set_game_state(game.GameState.PLAYING)
	game.rally_scorer._serve_was_hit = true
	game.player_right.set_ai_movement_enabled(false)
	var player = game.player_left
	player.global_position = Vector3(0, player.ground_y, float(data.root_z))
	player.current_velocity = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player.hitting.clear_charge_visual()
	player.hitting.serving_visual_active = false
	player.leg_ik.feet_initialized = false
	player._process(0.0)
	player.can_volley_from_feet()
	var target: Vector3 = player.global_position + player._get_forehand_axis() * float(data.lateral) + player._get_forward_axis() * float(data.forward)
	target.y = float(data.height)
	var origin: Vector3 = Vector3(target.x * 0.35, 1.1, -2.4)
	var launch: Dictionary = game.practice_launcher.solve_airborne_feed(origin, target, float(data.duration))
	var ball = game.ball
	ball.reset_rally_state()
	ball.both_bounces_complete = true
	ball.serving_side_bounced = true
	ball.receiving_side_bounced = true
	ball.bounces_since_last_hit = 0
	ball.is_in_play = true
	ball.last_hit_by = 1
	ball.global_position = origin
	ball.linear_velocity = launch.velocity
	ball.angular_velocity = launch.omega
	ball.flight_id += 1
	return {"origin": origin, "target": target, "velocity": launch.velocity, "flight": ball.flight_id, "root": player.global_position}

static func press(game) -> void :
	Input.action_press("ui_accept")
	game.input_handler._handle_swing_charge(1.0 / Engine.physics_ticks_per_second)

static func release(game) -> void :
	Input.action_release("ui_accept")
	game.input_handler._handle_swing_charge(0.0)

static func tick_input(game) -> void :
	game.input_handler._handle_swing_charge(1.0 / Engine.physics_ticks_per_second)
