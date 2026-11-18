extends SceneTree
var failures: Array[String] = []
var serves: Array[int] = [0, 0]
var points: = 0
var retrievals: = 0
var checks: = 0
var rally_hits: = 0
var max_rally_hits: = 0
var human_hits: = 0
var sustained_rallies: = 0
var assisted_points: = 0
var charge_frames: = 0
var last_charge_flight: = -1
const Flight = preload("res://scripts/ball_flight_predictor.gd")
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(message)
func run() -> void :
	seed(77811)
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.game_serve.serve_launched.connect( func(team): serves[team] += 1)
	game.rally_scorer.rally_ended.connect( func(_winner, _reason, _detail):
		points += 1
		max_rally_hits = maxi(max_rally_hits, rally_hits)
		if rally_hits >= 6: sustained_rallies += 1
		print("[MIXED POINT] hits=", rally_hits, " reason=", _reason)
		rally_hits = 0)
	game.ball.hit_by_paddle.connect( func(team):
		rally_hits += 1
		if team == 0: human_hits += 1)
	game.between_point_controller.finished.connect( func(skipped):
		retrievals += 1
		check( not skipped, "natural match retrieval required timeout/skip")
		check(game.game_serve._legal_service_feet(game.player_left if game.serving_team == 0 else game.player_right, game.serving_team), "next server's actual soles legal")
		check( not game.ball.is_in_play and game.game_state == game.GameState.WAITING, "dead-ball retrieval ends ready"))
	game.player_right.ai_brain.set_tactic_seed(411)
	game.player_right.ai_brain.ai_difficulty = 2
	game.ai_difficulty = 2
	game._reset_match()
	await process_frame
	game._perform_serve(0.55)


	for frame in range(20000):
		await physics_frame
		_drive_human(game, sustained_rallies < 2 and points < 8 and rally_hits < 8)
		if game.game_state == game.GameState.WAITING and game.serving_team == 0 and not game.game_serve.is_release_pending():
			game._perform_serve(0.55)
		if game.match_over: break
	check(game.match_over, "full physical match reaches match win")
	check(game.match_winner in [0, 1] and maxi(game.score_right, game.score_left) >= 11, "match reaches legal winning score")
	check(sustained_rallies >= 2 and human_hits >= 4, "two sustained six-contact rallies include actual human returns")
	check(serves[0] >= 1 and serves[1] >= 1, "both real service paths executed")
	check(points >= 11 and retrievals == points - 1, "each unfinished point has retrieval, final point does not")
	check( not game.between_point_controller.is_active(), "match win leaves retrieval inactive")
	var prior_blue_serves: int = serves[0]
	game.request_rematch()
	check( not game.match_over and game.score_left == 0 and game.score_right == 0 and game.serving_team == 0 and game.game_state == game.GameState.WAITING, "rematch restores fresh match")
	await process_frame
	game._perform_serve(0.55)
	for frame in range(90):
		await physics_frame
		if serves[0] > prior_blue_serves: break
	check(serves[0] > prior_blue_serves and game.ball.is_in_play, "rematch can serve again")
	print("[MIXED SUMMARY] max_rally_hits=", max_rally_hits, " human_hits=", human_hits, " sustained_rallies=", sustained_rallies)
	print("COMPLETE MIXED MATCH RETRIEVAL: %d checks, %d failures; serves=%s points=%d retrievals=%d score=%d-%d; %s" % [checks, failures.size(), serves, points, retrievals, game.score_left, game.score_right, failures])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _drive_human(game, enabled: bool) -> void :
	for action in ["move_left", "move_right", "move_up", "move_down"]: Input.action_release(action)
	if not enabled or game.game_state != game.GameState.PLAYING:
		Input.action_release("ui_accept")
		charge_frames = 0
		return
	var ball = game.ball
	var player = game.player_left
	if ball.last_hit_by == 0: return
	var human = player.posture.human_contact
	if human.contact.is_empty() and human.phase < 0:
		var prediction: Dictionary = Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity, 2.5, 2, false)
		var goal: = Vector3.INF
		for sample in prediction.samples:
			var point: Vector3 = sample.pos
			var time: float = sample.time
			if point.z < 0.5 or int(sample.bounces) + ball.bounces_since_last_hit >= 2: continue
			if not ball.both_bounces_complete and int(sample.bounces) + ball.bounces_since_last_hit == 0: continue
			if point.y < 0.5 or point.y > 1.5 or time < 0.15: continue
			var candidate: = Vector3(clampf(point.x - 0.4, player.min_x, player.max_x), player.ground_y, clampf(point.z + 0.45, 2.7, player.max_z))
			if player.global_position.distance_to(candidate) <= player.move_speed * maxf(0.0, time - 0.1):
				goal = candidate
				break
		if goal.is_finite():
			var delta: Vector3 = goal - player.global_position
			if absf(delta.x) > 0.06: Input.action_press("move_right" if delta.x > 0 else "move_left")
			if absf(delta.z) > 0.06: Input.action_press("move_down" if delta.z > 0 else "move_up")
	if charge_frames > 0:
		charge_frames -= 1
		if charge_frames == 0: Input.action_release("ui_accept")
	elif not human.contact.is_empty() and human.phase < 0 and ball.flight_id != last_charge_flight:
		last_charge_flight = ball.flight_id
		charge_frames = 8
		Input.action_press("ui_accept")
