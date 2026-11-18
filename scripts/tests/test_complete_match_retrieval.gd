extends SceneTree
var failures: Array[String] = []
var serves: Array[int] = [0, 0]
var points: = 0
var retrievals: = 0
var checks: = 0
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(message)
func run() -> void :
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.game_serve.serve_launched.connect( func(team): serves[team] += 1)
	game.rally_scorer.rally_ended.connect( func(_winner, _reason, _detail): points += 1)
	game.between_point_controller.finished.connect( func(skipped):
		retrievals += 1
		check( not skipped, "natural match retrieval required timeout/skip")
		check(game.game_serve._legal_service_feet(game.player_left if game.serving_team == 0 else game.player_right, game.serving_team), "next server's actual soles legal")
		check( not game.ball.is_in_play and game.game_state == game.GameState.WAITING, "dead-ball retrieval ends ready"))
	game._reset_match()
	await process_frame
	game._perform_serve(0.55)


	for frame in range(20000):
		await physics_frame
		if game.match_over: break
	check(game.match_over, "full physical match reaches match win")
	check(game.match_winner == 1 and game.score_right == 11 and game.score_left == 0, "sideout then eleven legal service points")
	check(serves[0] == 1 and serves[1] >= 11, "both real service paths executed")
	check(points == 12 and retrievals == 11, "one sideout, eleven points, no final retrieval")
	check( not game.between_point_controller.is_active(), "match win leaves retrieval inactive")
	game.request_rematch()
	check( not game.match_over and game.score_left == 0 and game.score_right == 0 and game.serving_team == 0 and game.game_state == game.GameState.WAITING, "rematch restores fresh match")
	await process_frame
	game._perform_serve(0.55)
	for frame in range(90):
		await physics_frame
		if serves[0] == 2: break
	check(serves[0] == 2 and game.ball.is_in_play, "rematch can serve again")
	print("COMPLETE MATCH RETRIEVAL: %d checks, %d failures; serves=%s points=%d retrievals=%d score=%d-%d; %s" % [checks, failures.size(), serves, points, retrievals, game.score_left, game.score_right, failures])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
