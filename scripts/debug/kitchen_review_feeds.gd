extends RefCounted

static func popup(game, seed_value: int = 112) -> void :
	var practice = game.practice_launcher
	practice.start_drill("DINK")
	practice.loop_enabled = false
	var player = game.player_right
	player.global_position = Vector3(0, player.ground_y, -2.72)
	player.leg_ik.feet_initialized = false
	player.ai_brain.ai_difficulty = 2
	player.ai_brain.set_tactic_seed(seed_value)
	var origin: = Vector3(-0.42, 1.2, 2.0)
	var target: = Vector3(-0.42, 1.35, -2.0)


	var duration: = 1.1
	var velocity: Vector3 = (target - origin) / duration
	velocity.y += 0.5 * preload("res://scripts/ball.gd").get_effective_gravity() * duration
	for step in range(12):
		velocity += (target - game.shot_physics._spin_position_after(origin, velocity, Vector3.ZERO, duration)) / duration * 0.86
	game.ball.global_position = origin
	game.ball.linear_velocity = velocity
	game.ball.angular_velocity = Vector3.ZERO
	game.ball.last_hit_by = 0
	game.ball.flight_id += 1
	practice._set_status("POP-UP REVIEW FEED · watch the red player's legal choice")

static func scenario(game, kind: String, receiver: int = 1, diagonal: int = 1, seed_value: int = 112, difficulty: int = 2) -> Dictionary:
	var data: Dictionary = preload("res://scripts/kitchen_exchange_scenarios.gd").review_case(kind, receiver, diagonal)
	var practice = game.practice_launcher
	var popup_case: bool = kind in ["NET_POPUP", "HIGH_POPUP", "UNREACHABLE"]
	practice.start_drill("DINK", receiver == 0, diagonal, "ATTACK" if popup_case else "WIDE")
	practice.loop_enabled = false
	practice.allow_attacks = popup_case
	var player = game.player_left if receiver == 0 else game.player_right
	player.global_position = Vector3(data.player.x, player.ground_y, data.player.z)
	player.velocity = Vector3.ZERO
	player.current_velocity = Vector3.ZERO
	player.leg_ik.feet_initialized = false
	game.player_right.ai_brain.ai_difficulty = difficulty
	game.player_right.ai_brain.set_tactic_seed(seed_value)
	practice._demo_rng.seed = seed_value
	var sender: int = 1 - receiver
	var launch: Dictionary
	if data.duration > 0.0:
		launch = practice.solve_airborne_feed(data.origin, data.target, data.duration)
	else:
		launch = game.shot_physics.solve_drop_launch(data.origin, 0.25, sender, 0, data.target)
	practice._remember_launch(launch, sender)
	game.ball.global_position = data.origin
	game.ball.linear_velocity = launch.velocity
	game.ball.angular_velocity = launch.omega
	game.ball.last_hit_by = sender
	game.ball.ball_bounced_since_last_hit = false
	game.ball.bounces_since_last_hit = 0
	game.ball.flight_id += 1
	practice._set_status("%s REVIEW · %s receiver · actual contact and rules" % [kind.replace("_", " "), "blue" if receiver == 0 else "red"])
	return data
