extends SceneTree
const Flight = preload("res://scripts/ball_flight_predictor.gd")
var failures: Array[String] = []
var legal: int = 0
func _initialize() -> void : call_deferred("run")
func run() -> void :
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	for mode in range(3):
		game.selected_spin_mode = mode
		game.game_serve.select_serve_style(mode)
		for side in range(2):
			game.serving_team = side
			for parity in range(2):
				game.score_left = parity if side == 0 else 0
				game.score_right = parity if side == 1 else 0
				game._reset_ball()
				for charge in [0.15, 0.35, 0.65, 1.0]:
					var origin: Vector3 = game.game_serve.get_serve_launch_position(side == 1)
					var launch: Dictionary = game.game_serve.get_predicted_serve_launch(charge, side == 1)
					var flight: Dictionary = Flight.trace(origin, launch.velocity, launch.omega, 3.0, 1, false)
					var landing: Vector3 = flight.first_bounce
					var expected_x: float = (1.0 if side == 1 else -1.0) * (1.0 if parity == 0 else -1.0)
					var expected_z: float = 1.0 if side == 1 else -1.0
					if not flight.net_hit and signf(landing.x) == expected_x and absf(landing.x) < 3.05 and landing.z * expected_z > 2.134 and landing.z * expected_z < 6.7:
						legal += 1
					else: failures.append("mode%d side%d parity%d charge%.2f landing%s net%s" % [mode, side, parity, charge, landing, flight.net_hit])
					if launch.velocity.distance_to(game.game_trajectory._get_predicted_serve_velocity(charge, side == 1)) > 0.0001:
						failures.append("serve preview velocity differs from frozen launch")
					if mode == 0 and launch.omega.length() > 0.001: failures.append("flat serve unexpectedly spins")
					if mode != 0 and launch.omega.length() < 1.0: failures.append("selected serve spin has no angular velocity")
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("SERVE SPIN FLIGHT: %d/48 legal diagonal landings, %d failures" % [legal, failures.size()])
	quit(0 if failures.is_empty() else 1)
