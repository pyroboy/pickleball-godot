extends SceneTree
const Movement = preload("res://scripts/ai_match_movement.gd")
const Tactics = preload("res://scripts/ai_match_tactics.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const BallModel = preload("res://scripts/ball.gd")
var failures: Array[String] = []
var checks: int = 0
var rows: Array = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok: failures.append(detail)
func run() -> void:
	for difficulty in range(3):
		var fast: Vector3 = Vector3.ZERO
		for frame in range(60):
			var before: Vector3 = fast
			fast = Movement.velocity(fast, Vector3.RIGHT, Vector3(100, 0, 0), difficulty, 1.0 / 60.0)
			check(fast.length() <= Movement.speed(difficulty) + 0.0001, "speed cap d%d" % difficulty)
			check((fast - before).length() <= Movement.ACCELERATIONS[difficulty] / 60.0 + 0.0001, "acceleration d%d" % difficulty)
		var reverse: Vector3 = Movement.velocity(fast, Vector3.LEFT, Vector3(-100, 0, 0), difficulty, 1.0 / 60.0)
		check(reverse.x > 0.0, "instant reversal d%d" % difficulty)
		check(fast.length() <= PickleballConstants.PLAYER_SPEED + 0.0001, "faster than Blue d%d" % difficulty)
		var positions: Array[float] = []
		for scale in [1.0, 0.1, 0.025]:
			var velocity: Vector3 = Vector3.ZERO
			var position: Vector3 = Vector3.ZERO
			for frame in range(roundi(60.0 / scale)):
				velocity = Movement.velocity(velocity, Vector3.RIGHT, Vector3(100, 0, 0), difficulty, scale / 60.0)
				position += velocity * scale / 60.0
			positions.append(position.x)
		check(absf(positions[0] - positions[2]) < 0.055, "focus changes sim movement d%d" % difficulty)
		print("AI MOVEMENT d%d cap=%.2f distance/1simsec=%s reversal=%.2f" % [difficulty, Movement.speed(difficulty), positions, reverse.x])
		for sign_x in [-1.0, 1.0]:
			var arrival: Vector3 = Vector3.ZERO
			var velocity: Vector3 = Vector3.ZERO
			var target: Vector3 = Vector3(sign_x * 1.5, 0, 0.45)
			var past: float = 0.0
			for frame in range(120):
				var offset: Vector3 = target - arrival
				var input: Vector3 = offset.normalized() if offset.length() > 0.06 else Vector3.ZERO
				velocity = Movement.velocity(velocity, input, offset, difficulty, 1.0 / 60.0)
				arrival += velocity / 60.0
				past = maxf(past, arrival.z - target.z)
			check(past < 0.06 and arrival.distance_to(target) < 0.08, "overshot arrival target d%d" % difficulty)
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var brain = game.player_right.ai_brain
	var ball = game.ball
	ball.freeze = true
	ball.is_in_play = true
	ball.last_hit_by = 0
	for difficulty in range(3):
		brain.ai_difficulty = difficulty
		for scale in [1.0, 0.1, 0.025]:
			ball.flight_id += 1
			ball.global_position = Vector3(0, 2, 4.5)
			ball.linear_velocity = Vector3(0.3, 2.0, -9.0)
			ball.angular_velocity = Vector3.ZERO
			brain._sample_ball_history(ball, scale / 60.0)
			var latency: float = brain._get_latency_frames() / 60.0
			var elapsed: float = 0.0
			var max_error: float = 0.0
			for index in range(roundi((latency + 0.2) * 60.0 / scale)):
				var step: Array = BallModel.predict_aero_step(ball.global_position, ball.linear_velocity, ball.angular_velocity, BallModel.get_effective_gravity(), scale / 60.0)
				ball.global_position = step[0]; ball.linear_velocity = step[1]; ball.angular_velocity = step[2]
				elapsed += scale / 60.0
				brain._sample_ball_history(ball, scale / 60.0)
				if elapsed < latency - 0.00001:
					check(not brain._perception_ready, "early perception scale %.3f d%d t%.3f" % [scale, difficulty, elapsed])
				elif brain._perception_ready:
					max_error = maxf(max_error, brain._perceived_state.pos.distance_to(ball.global_position))
			check(brain._perception_ready, "never perceived scale %.3f d%d" % [scale, difficulty])
			check(max_error < 0.22, "focus predicts future scale %.3f d%d error%.3f" % [scale, difficulty, max_error])
			print("AI PERCEPTION d%d scale%.3f delay%.3fs max_error%.3f" % [difficulty, scale, latency, max_error])
	var previous_ticks: int = Engine.physics_ticks_per_second
	for rate in [30, 60, 120]:
		Engine.physics_ticks_per_second = rate
		for difficulty in range(3):
			brain.ai_difficulty = difficulty
			check(absf(float(brain._get_latency_frames()) / rate - [0.30, 0.20, 8.0 / 60.0][difficulty]) < 0.00001, "reaction changed with physics tick rate")
	Engine.physics_ticks_per_second = previous_ticks
	# Shot targeting uses the delayed opponent snapshot, never the current aim/move input.
	var observed: Vector3 = brain._observed_opponent
	game.player_left.global_position.x = -2.8 if observed.x >= 0.0 else 2.8
	check(brain.match_context(Vector3(0, 1, -4)).opponent == observed, "target reads current opponent")
	var scenarios: Array[Dictionary] = [
		{"kind":"RETURN", "depth":5.2, "height":0.8, "opponent_depth":6.0, "speed":8.0, "opening":true, "roll":0.3},
		{"kind":"DROP", "depth":5.2, "height":0.7, "opponent_depth":2.8, "speed":6.0, "roll":0.3},
		{"kind":"RESET", "depth":3.7, "height":0.75, "opponent_depth":2.8, "speed":13.0, "roll":0.3},
		{"kind":"DINK", "depth":2.4, "height":0.65, "opponent_depth":2.8, "speed":4.0, "roll":0.3},
		{"kind":"DRIVE", "depth":5.0, "height":1.25, "opponent_depth":5.6, "speed":6.0, "roll":0.4},
		{"kind":"LOB", "depth":2.8, "height":0.9, "opponent_depth":2.7, "speed":4.0, "roll":0.96},
		{"kind":"SMASH", "depth":2.8, "height":1.95, "opponent_depth":4.8, "speed":5.0, "roll":0.0},
		{"kind":"SPEED_UP", "depth":2.8, "height":1.4, "opponent_depth":2.8, "speed":5.0, "roll":0.0}]
	var kinds: Dictionary = {}
	for difficulty in range(3):
		for team in [0, 1]:
			var direction: float = -1.0 if team == 0 else 1.0
			for scenario in scenarios:
				for lane in [-1.8, 0.0, 1.8]:
					var origin: Vector3 = Vector3(lane, scenario.height, -direction * scenario.depth)
					var context: Dictionary = {"origin":origin,"player_num":team,"difficulty":difficulty,
						"opponent":Vector3(-lane,0,direction * scenario.opponent_depth),"ball_height":scenario.height,
						"net_height":Flight.net_clear_y_at(lane),"net_distance":scenario.depth,"incoming_speed":scenario.speed,
						"opening_return":scenario.get("opening",false),"balanced":true,"reachable":true,
						"legal_volley":true,"reaction_ready":true,"contact_distance":0.75}
					check(Tactics.choose(context, scenario.roll) == scenario.kind, "wrong tactical choice %s d%d side%d" % [scenario.kind,difficulty,team])
					var launch: Dictionary = Tactics.solve(game.shot_physics,origin,context,scenario.roll,0.58)
					check(not launch.is_empty(), "no physical launch %s d%d side%d" % [scenario.kind,difficulty,team])
					if launch.is_empty(): continue
					check(launch.tactic == scenario.kind, "unexpected fallback %s to %s" % [scenario.kind,launch.tactic])
					var flight: Dictionary = Flight.trace(origin,launch.velocity,launch.omega,3.0,1,false)
					var peak: float = origin.y
					for sample in flight.samples: peak = maxf(peak,sample.pos.y)
					check(Tactics.valid_launch(origin,launch,team), "net/out %s" % scenario.kind)
					check(launch.velocity.length() <= BallModel.MAX_SPEED + .001, "speed over physics limit")
					if scenario.kind in ["DINK","DROP","RESET"]:
						check(flight.first_bounce.z * direction < PickleballConstants.NON_VOLLEY_ZONE, "soft shot not in kitchen")
					if scenario.kind == "LOB": check(peak > 3.0, "lob has no high arc")
					kinds[launch.tactic] = int(kinds.get(launch.tactic,0)) + 1
					rows.append({"kind":launch.tactic,"difficulty":difficulty,"team":team,"origin":str(origin),"target":str(launch.target),"landing":str(flight.first_bounce),"net_margin":flight.net_crossing.pos.y - Flight.net_clear_y_at(flight.net_crossing.pos.x),"speed":launch.velocity.length(),"peak":peak})
	# Normal Easy route must now select a reset instead of unconditional comfortable return.
	brain.ai_difficulty = 0; game.ai_difficulty = 0
	game.player_right.global_position = Vector3(0,game.player_right.ground_y,-3.7)
	ball.both_bounces_complete = true; ball.linear_velocity = Vector3(0,0,-13)
	var integrated: Dictionary = game.solve_ai_launch(Vector3(0,0.75,-3.7),.7,0,Vector3.ZERO,Vector3.ZERO,0.0)
	check(integrated.get("tactic","") == "RESET", "Easy match bypassed reset")
	print("AI MATCH SHOTS: %s" % kinds)
	var out = FileAccess.open("/tmp/red-ai-match-behavior.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"checks":checks,"failures":failures,"shots":rows},"\t"));out.close()
	print("AI MATCH BEHAVIOR: %d checks, %d failures: %s" % [checks,failures.size(),failures])
	game.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
