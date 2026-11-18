extends SceneTree

const Scorer = preload("res://scripts/rally_scorer.gd")
const FakeBall = preload("res://scripts/tests/fakes/fake_ball.gd")
const FakePlayer = preload("res://scripts/tests/fakes/fake_player.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		print("FAIL: ", message)

func fixture(hitter: int) -> Dictionary:
	var scorer = Scorer.new()
	var ball = FakeBall.new()
	var blue = FakePlayer.new(0, Vector3(0, 1, 6.8))
	var red = FakePlayer.new(1, Vector3(0, 1, -6.8))
	ball.last_hit_by = hitter
	ball.both_bounces_complete = true
	scorer.bind(ball, blue, red)
	scorer.start_rally(hitter, true)
	scorer._serve_was_hit = true
	var events: Array = []
	scorer.rally_ended.connect(func(winner, reason, detail): events.append({"winner":winner, "reason":reason, "detail":detail}))
	return {"scorer":scorer, "ball":ball, "blue":blue, "red":red, "events":events}

func bounce(f: Dictionary, pos: Vector3) -> void:
	f.ball.global_position = pos
	f.ball.bounces_since_last_hit += 1
	f.ball.ball_bounced_since_last_hit = true
	f.scorer._on_ball_bounced(pos)

func cleanup(f: Dictionary) -> void:
	f.scorer.free(); f.blue.free(); f.red.free()

func run() -> void:
	for hitter in [0, 1]:
		var side := -1.0 if hitter == 0 else 1.0
		var f := fixture(hitter)
		f.ball.global_position = Vector3(3.2, 0.3, side * 4.0)
		f.ball.linear_velocity = Vector3(-2.0, -1.0, 0.0)
		f.scorer._physics_process(1.0 / 60.0)
		check(f.events.is_empty(), "Airborne inbound shot called out before landing (hitter %d)" % hitter)
		cleanup(f)

		f = fixture(hitter)
		bounce(f, Vector3(0, 0.082, side * 5.8))
		f.ball.global_position = Vector3(0, 0.3, side * 7.1)
		f.scorer._physics_process(1.0 / 60.0)
		check(f.events.is_empty(), "Legal first bounce then airborne exit ended a still-returnable rally (hitter %d)" % hitter)
		bounce(f, Vector3(0, 0.082, side * 7.5))
		check(f.events.size() == 1 and f.events[0].winner == hitter, "Second bounce outside changed rally winner (hitter %d)" % hitter)
		check(f.events.size() == 1 and f.events[0].reason == Scorer.FAULT_DOUBLE_BOUNCE, "Missed return mislabeled as shot out (hitter %d)" % hitter)
		f.scorer._physics_process(1.0 / 60.0)
		bounce(f, Vector3(0, 0.082, side * 8.0))
		check(f.events.size() == 1, "Duplicate point after rally end (hitter %d)" % hitter)
		cleanup(f)

		f = fixture(hitter)
		bounce(f, Vector3(3.2, 0.082, side * 4.0))
		check(f.events.size() == 1 and f.events[0].winner == 1 - hitter and f.events[0].reason == Scorer.FAULT_OUT_OF_BOUNDS, "First outside bounce did not fault shooter (hitter %d)" % hitter)
		cleanup(f)

		for edge in ["sideline", "baseline"]:
			for offset in [0.023, 0.025, 0.027]:
				f = fixture(hitter)
				var pos := Vector3(PickleballConstants.COURT_WIDTH * 0.5 + offset, 0.082, side * 4.0) if edge == "sideline" else Vector3(0, 0.082, side * (PickleballConstants.BASELINE_Z + offset))
				bounce(f, pos)
				if offset <= PickleballConstants.LINE_WIDTH * 0.5:
					check(f.events.is_empty(), "Visible white %s called out (hitter %d)" % [edge, hitter])
				else:
					check(f.events.size() == 1 and f.events[0].winner == 1 - hitter, "Outside white %s not called out (hitter %d)" % [edge, hitter])
				cleanup(f)

	for server in [0, 1]:
		var side := -1.0 if server == 0 else 1.0
		var f := fixture(server)
		f.scorer._serve_was_hit = false
		f.ball.both_bounces_complete = false
		bounce(f, Vector3(side, 0.082, side * 4.0))
		check(f.events.is_empty() and f.scorer._serve_was_hit, "Legal serve first bounce was rejected")
		bounce(f, Vector3(side, 0.082, side * 7.5))
		check(f.events.size() == 1 and f.events[0].winner == server and f.events[0].reason == Scorer.FAULT_DOUBLE_BOUNCE, "Legal serve then outside second bounce was incorrectly faulted")
		cleanup(f)
		for kind in ["outside", "short", "wrong_diagonal"]:
			f = fixture(server)
			f.scorer._serve_was_hit = false
			f.ball.both_bounces_complete = false
			var pos := Vector3(side * 3.3, 0.082, side * 4.0)
			var reason := Scorer.FAULT_OUT_OF_BOUNDS
			if kind == "short": pos = Vector3(side, 0.082, side); reason = Scorer.FAULT_SHORT_SERVE
			if kind == "wrong_diagonal": pos = Vector3(-side, 0.082, side * 4); reason = Scorer.FAULT_WRONG_SERVICE_COURT
			bounce(f, pos)
			check(f.events.size() == 1 and f.events[0].winner == 1 - server and f.events[0].reason == reason, "Service " + kind + " fault precedence changed")
			cleanup(f)

	for sign_value in [-1.0, 1.0]:
		check(not Scorer.is_outside_painted_court(Vector3(sign_value * 3.075, 0.082, 0)), "Exact outer sideline must be in despite Vector3 float precision")
		check(not Scorer.is_outside_painted_court(Vector3(0, 0.082, sign_value * 6.725)), "Exact outer baseline must be in despite Vector3 float precision")
		check(Scorer.is_outside_painted_court(Vector3(sign_value * 3.076, 0.082, 0)), "Sphere radius must not extend legal court beyond contact point")

	await test_physical_landings()

	# Production bounce signal ordering and side-out scoring, without relying on
	# manually changing the score or bypassing Game._on_rally_ended.
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame
	for serving_team in [0, 1]:
		game._reset_match()
		game.score_left = 4; game.score_right = 3; game.serving_team = serving_team
		game._reset_ball()
		game._set_game_state(game.GameState.PLAYING)
		game.rally_scorer._serve_was_hit = true
		game.player_right.set_ai_movement_enabled(false)
		game.ball.freeze = true
		game.ball.last_hit_by = 0
		game.ball.both_bounces_complete = true
		game.ball.bounces_since_last_hit = 0
		game.ball.global_position = Vector3(3.2, 0.3, -4.0)
		game.game_shots._update_out_indicator()
		check(not game.hud.out_text.visible, "Airborne boundary crossing displayed an unconfirmed OUT banner")
		game.ball.global_position = Vector3(0, 0.1125, -5.8)
		game.ball.bounced.emit(Vector3(0, 0.082, -5.8))
		game.ball.global_position = Vector3(0, 0.3, -7.5)
		game.game_shots._update_out_indicator()
		game.rally_scorer._physics_process(1.0 / 60.0)
		check(not game.hud.out_text.visible and game.game_state == game.GameState.PLAYING, "Legal first bounce then airborne exit displayed OUT or ended rally")
		game.ball.global_position = Vector3(0, 0.1125, -7.5)
		game.ball.bounced.emit(Vector3(0, 0.082, -7.5))
		check(game.game_state == game.GameState.POINT_SCORED and not game.ball.is_in_play, "Production bounce signals did not end the rally")
		check(game.score_left == (5 if serving_team == 0 else 4) and game.score_right == 3, "Incorrect serving/receiving score for blue winning rally")
		check(game.serving_team == 0, "Blue did not retain/win the serve")
		game.ball.bounced.emit(Vector3(0, 0.082, -8.0))
		check(game.score_left == (5 if serving_team == 0 else 4), "Duplicate signal scored twice")
	game.queue_free()
	await process_frame
	await process_frame
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	print("LANDING SCORING REGRESSION ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func test_physical_landings() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var court = preload("res://scripts/court.gd").new()
	court.create_court(world); court.free()
	var ball = preload("res://scripts/ball.gd").new()
	world.add_child(ball)
	var scorer = Scorer.new()
	world.add_child(scorer)
	var blue = FakePlayer.new(0, Vector3(0, 1, 6.8))
	var red = FakePlayer.new(1, Vector3(0, 1, -6.8))
	world.add_child(blue); world.add_child(red)
	var bounces: Array = []
	var events: Array = []
	# Match Game's production signal ordering: record before scorer sees bounce.
	ball.bounced.connect(func(pos): bounces.append(pos); ball.record_bounce_side(pos.z))
	scorer.bind(ball, blue, red)
	scorer.rally_ended.connect(func(winner, reason, detail): events.append({"winner":winner,"reason":reason,"detail":detail}))
	await physics_frame
	var cases: Array[Dictionary] = [
		{"name":"blue legal bounce then outside miss", "hitter":0, "pos":Vector3(0, 1, -4.5), "vel":Vector3(0, -1, -4), "winner":0, "reason":Scorer.FAULT_DOUBLE_BOUNCE},
		{"name":"red legal bounce then outside miss", "hitter":1, "pos":Vector3(0, 1, 4.5), "vel":Vector3(0, -1, 4), "winner":1, "reason":Scorer.FAULT_DOUBLE_BOUNCE},
		{"name":"airborne outside curves inward", "hitter":0, "pos":Vector3(3.2, 0.3, -4), "vel":Vector3(-2, -1, 0), "winner":0, "reason":Scorer.FAULT_DOUBLE_BOUNCE},
		{"name":"first bounce outside", "hitter":0, "pos":Vector3(3.3, 0.3, -4), "vel":Vector3(0, -1, 0), "winner":1, "reason":Scorer.FAULT_OUT_OF_BOUNDS},
		{"name":"painted outer sideline", "hitter":0, "pos":Vector3(3.075, 0.3, -4), "vel":Vector3(0, -1, 0), "winner":0, "reason":Scorer.FAULT_DOUBLE_BOUNCE},
	]
	for item in cases:
		scorer.set_active(false)
		ball.freeze = true
		ball.global_position = item.pos
		ball.linear_velocity = item.vel
		ball.angular_velocity = Vector3.ZERO
		ball.reset_rally_state()
		ball.can_register_floor_bounce = true
		ball.last_hit_by = item.hitter
		ball.both_bounces_complete = true
		ball.is_in_play = true
		bounces.clear(); events.clear()
		await physics_frame
		scorer.start_rally(item.hitter, true)
		scorer._serve_was_hit = true
		ball.freeze = false
		for frame in range(180):
			await physics_frame
			if not events.is_empty(): break
		check(events.size() == 1, item.name + ": actual floor physics did not end rally exactly once")
		if not events.is_empty():
			check(events[0].winner == item.winner and events[0].reason == item.reason, item.name + ": incorrect live ruling " + str(events[0]))
		check(bounces.size() == (1 if item.reason == Scorer.FAULT_OUT_OF_BOUNDS else 2), item.name + ": rally ended before authoritative ground contact")
		print("PHYSICAL LANDING ", item.name, " bounces=", bounces, " events=", events)
	world.queue_free()
	await process_frame
	await process_frame
