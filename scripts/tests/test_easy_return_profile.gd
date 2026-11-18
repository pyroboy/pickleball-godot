extends SceneTree
const Flight = preload("res://scripts/ball_flight_predictor.gd")
var out: = "/tmp/easy-returns.json"
var failures: Array[String] = []
var checks: = 0
var baseline: = OS.get_cmdline_user_args().has("--baseline")
func _initialize() -> void : call_deferred("run")
func run() -> void :
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): out = arg.trim_prefix("--output=")
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game);current_scene = game
	await process_frame; await physics_frame; await physics_frame
	game.set_process(false);game.set_physics_process(false)
	var rows: Array = []
	for difficulty in [0, 1, 2]:
		for receiver_x in [-2.1, 0.0, 2.1]:
			for receiver_z in [2.8, 4.6, 6.5]:
				for origin_z in [-5.2, -2.7]:
					for height in [0.55, 1.1, 1.8]:
						for sequence in range(3):
							var seed_value: int = 9101 + rows.size()
							seed(seed_value)
							game.ai_difficulty = difficulty
							game.player_right.ai_brain.ai_difficulty = difficulty
							game.player_right.ai_brain.set_tactic_seed(seed_value)
							game.player_left.global_position = Vector3(receiver_x, game.player_left.ground_y, receiver_z)
							game.player_right.ai_brain._observed_opponent = game.player_left.global_position
							game.player_left.leg_ik.feet_initialized = false
							game.player_left._process(0.0)
							game.player_right.global_position = Vector3( - receiver_x * 0.4, game.player_right.ground_y, origin_z)
							game.ball.both_bounces_complete = sequence != 0
							game.player_right.ai_brain._perception_ready = true
							game.player_right.ai_brain.ai_selected_contact_reachable = true
							var origin: = Vector3( - receiver_x * 0.4, height, origin_z)
							var launch: Dictionary = game.solve_ai_launch(origin, 0.35 + sequence * 0.2, 0, origin, Vector3.ZERO, 0.0)
							var flight: = Flight.trace(origin, launch.velocity, launch.omega, 4.0, 2, false)
							var receive: Dictionary = {}
							var peak: float = height
							var contact_z: float = receiver_z - 0.65
							for sample in flight.samples:
								peak = maxf(peak, sample.pos.y)
								if receive.is_empty() and sample.pos.z >= contact_z: receive = sample
							var crossing: Dictionary = flight.net_crossing
							rows.append({"tactic": launch.get("tactic", ""), "difficulty": difficulty, "seed": seed_value, "receiver": [receiver_x, receiver_z], "origin": [origin.x, origin.y, origin.z], "both_bounces": game.ball.both_bounces_complete, "target": str(launch.get("target")), "speed": launch.velocity.length(), "bounce_x": flight.first_bounce.x, "bounce_z": flight.first_bounce.z, "bounce_time": flight.first_bounce_time, "net_hit": flight.net_hit, "net_margin": crossing.pos.y - Flight.net_clear_y_at(crossing.pos.x) if not crossing.is_empty() else - INF, "peak": peak, "receive_time": receive.get("time", -1), "receive_height": receive.pos.y if not receive.is_empty() else -1, "receive_lateral": absf(receive.pos.x - receiver_x) if not receive.is_empty() else -1, "receive_speed": receive.vel.length() if not receive.is_empty() else -1, "receive_bounces": receive.get("bounces", -1), "velocity": str(launch.velocity), "omega": str(launch.omega)})
	if not baseline:
		# Easy now plays contextual pickleball. Its previous unconditional
		# receiver-height feed was the cause of the missing drops/resets.
		var easy_kinds: Dictionary = {}
		for row in rows:
			verify(not row.net_hit and row.net_margin >= 0.075, row, "net clearance")
			verify(absf(row.bounce_x) < 3.05 and row.bounce_z > 0.0 and row.bounce_z < 6.7, row, "legal landing")
			verify(row.speed <= Ball.MAX_SPEED + 0.001, row, "physical speed limit")
			verify(row.both_bounces or row.tactic == "RETURN", row, "deep opening return preserved")
			if row.tactic in ["DROP", "RESET", "DINK"]:
				verify(row.bounce_z < PickleballConstants.NON_VOLLEY_ZONE, row, "soft shot lands in kitchen")
			if row.difficulty == 0: easy_kinds[row.tactic] = true
		checks += 1
		if easy_kinds.size() < 3 or not easy_kinds.has("DROP") or not easy_kinds.has("DINK"):
			failures.append("Easy lost contextual variety: %s" % easy_kinds.keys())

	var f = FileAccess.open(out, FileAccess.WRITE);f.store_string(JSON.stringify(rows, "\t"));f.close()
	print("EASY RETURN MEASUREMENT: ", rows.size(), " trajectories -> ", out)
	game.queue_free(); await process_frame; await process_frame
	for failure in failures: push_error(failure)
	print("EASY PROFILE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
func verify(ok: bool, row: Dictionary, message: String) -> void :
	checks += 1
	if not ok: failures.append("seed %d: %s" % [row.seed, message])
