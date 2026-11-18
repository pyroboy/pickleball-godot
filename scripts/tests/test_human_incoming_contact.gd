extends SceneTree
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Planner = preload("res://scripts/incoming_contact_planner.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
var failures: Array[String] = []
var checks: int = 0
var returns: int = 0
var maximum_error: float = 0

func _initialize() -> void: call_deferred("run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func setup_game():
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
	return game

func incoming(game, lateral: float, height: float, speed: float, spin: Vector3 = Vector3.ZERO) -> void:
	var ball = game.ball
	ball.reset_rally_state()
	ball.both_bounces_complete = true
	ball.bounces_since_last_hit = 0
	ball.global_position = Vector3(lateral, height, 1.5)
	ball.linear_velocity = Vector3(0, 1.5, speed)
	ball.angular_velocity = spin
	ball.last_hit_by = 1
	ball.is_in_play = true
	ball.flight_id += 1

func run() -> void:
	create_timer(50.0).timeout.connect(func(): quit(2))
	# Incoming side, height and spin sweep through the real human charge/release path.
	var cases: Array[Dictionary] = []
	for lane in [-0.65, -0.43, 0.0, 0.42, 0.82]:
		for height in [0.60, 1.12, 1.23]:
			cases.append({"lane": lane, "height": height, "speed": 8.0})
	cases.append_array([
		{"name": "high", "lane": 0.0, "height": 2.0, "speed": 8.0},
		{"name": "topspin", "lane": 0.42, "height": 1.12, "speed": 10.0, "spin": Vector3(-30, 0, 0)},
		{"name": "backspin", "lane": -0.43, "height": 1.12, "speed": 8.0, "spin": Vector3(30, 0, 0)},
		{"name": "sidespin", "lane": 0.0, "height": 1.12, "speed": 8.0, "spin": Vector3(0, 30, 0)},
		{"name": "fast", "lane": 0.42, "height": 1.12, "speed": 14.0},
		{"name": "soft", "lane": -0.43, "height": 1.12, "speed": 6.0},
		{"name": "after bounce", "lane": 0.42, "height": 0.8, "speed": 6.0, "bounce": true},
	])
	for shot in cases:
		var lane: float = shot.lane
		var height: float = shot.height
		var game = await setup_game()
		incoming(game, lane, height, shot.speed, shot.get("spin", Vector3.ZERO))
		if shot.get("bounce", false):
			game.ball.global_position.z = 0.3
			game.ball.linear_velocity.y = -4.0
			game.ball.both_bounces_complete = false
		await physics_frame
		await physics_frame
		var human = game.player_left.posture.human_contact
		var tag: String = "%s lane%.2f h%.2f" % [shot.get("name", "flat"), lane, height]
		check(not human.contact.is_empty(), tag + " no legal contact chosen")
		if human.contact.is_empty():
			game.queue_free()
			await process_frame
			continue
		var prediction: Vector3 = human.contact.point
		check(Planner.point_fits(game.player_left, human.contact.def, prediction), tag + " contact outside saved pose area")
		if lane > 0.25: check(human.contact.def.family == 0, tag + " right incoming ball does not choose forehand")
		if lane < -0.25: check(human.contact.def.family == 1, tag + " left incoming ball does not choose backhand")
		check(game.player_left.debug_visual.human_committed_contact_position.distance_to(prediction) < 0.001, tag + " indicator uses another contact")
		var hit_samples: Array[float] = []
		var hit_points: Array[Vector3] = []
		game.ball.hit_by_paddle.connect(func(id):
			if id == 0:
				hit_samples.append(PaddleReach.head_world(game.player_left).distance_to(game.ball.global_position))
				hit_points.append(game.ball.global_position)
		)
		# Exercise the actual Space input path rather than calling the shot solver.
		Input.action_press("ui_accept")
		game.input_handler._handle_swing_charge(0.08)
		check(game.player_left.hitting.charge_visual_active, tag + " holding Space does not wind up")
		check(game.scoreboard_ui._hud.state.text.contains("Release SPACE") and not game.scoreboard_ui._hud.state.text.contains("serve"), tag + " rally charge shows serve instructions")
		var expected: PostureDefinition = human.contact.def.lerp_with(Path.endpoint(human.contact.def, 0), 0.08 / PickleballConstants.MAX_SERVE_CHARGE_TIME)
		check(is_equal_approx(game.player_left.posture.transition_pose_blend.paddle_forward_mul, expected.paddle_forward_mul), tag + " held charge ignores selected contact pose")
		Input.action_release("ui_accept")
		game.input_handler._handle_swing_charge(0.0)
		check(game.ball.last_hit_by == 1, tag + " release applies a distant instant hit")
		for frame in range(70):
			await physics_frame
			if game.ball.last_hit_by == 0: break
			if game.game_state != game.GameState.PLAYING: break
		if game.ball.last_hit_by == 0:
			returns += 1
			check(hit_samples.size() == 1, tag + " hit fired more than once")
			if not hit_samples.is_empty():
				maximum_error = maxf(maximum_error, hit_samples[0])
				check(hit_samples[0] <= Planner.IMPACT_DISTANCE, tag + " impact misses actual paddle")
			check(not hit_points.is_empty() and hit_points[0].distance_to(prediction) < 0.25, tag + " prediction misses live impact")
		else:
			check(false, tag + " release misses legal timed contact")
		if shot.get("name", "") == "high":
			for frame in range(50): await physics_frame
			check(human.phase == -1 and not game.player_left.hitting.is_in_follow_through, "full swing never recovers to ready")
			check(hit_samples.size() == 1, "follow-through hits same ball twice")
		game.queue_free()
		await process_frame
	# Holding charge must reselect after movement/flight changes, then reject impossible balls.
	var game = await setup_game()
	incoming(game, 0.42, 1.12, 4.0)
	await physics_frame
	await physics_frame
	var human = game.player_left.posture.human_contact
	game.player_left.hitting.set_serve_charge_visual(0.8)
	check(human.contact.def.family == 0, "charge starts without forehand")
	game.player_left.global_position.x += 0.85
	await physics_frame
	check(not human.contact.is_empty() and human.contact.def.family == 1, "held charge freezes pose after player crosses ball path")
	if not human.contact.is_empty():
		check(game.player_left.posture.transition_pose_blend.posture_id == human.contact.posture, "charged body and incoming pose disagree")
		check(game.player_left.posture.transition_pose_blend.paddle_hand == human.contact.def.paddle_hand, "charged grip ignores selected pose")
	incoming(game, 3.0, 1.12, 8.0)
	await physics_frame
	check(human.contact.is_empty(), "unreachable ball still gets a contact")
	game._perform_player_swing(0.8)
	check(game.ball.last_hit_by == 1, "unreachable swing returns ball")
	# Queued swings are tied to a flight; a changed flight cannot inherit the release.
	incoming(game, 0.42, 1.12, 4.0)
	game.player_left.global_position.x = 0
	await physics_frame
	check(human.request_swing(0.8), "cannot queue a reachable incoming swing")
	incoming(game, -0.43, 1.12, 4.0)
	await physics_frame
	check(human.phase == -1 and not game.player_left.hitting.is_in_follow_through, "new flight inherits queued swing")
	# Opening the editor while charging cancels gameplay motion and preserves the editor preview.
	game.player_left.hitting.set_serve_charge_visual(0.8)
	game._toggle_posture_editor_v2()
	await process_frame
	check(game.posture_editor_v2.visible and game.player_left.posture.transition_pose_blend != null, "charge cancellation clears editor preview")
	check(not game.player_left.hitting.charge_visual_active and human.phase == -1, "charge continues inside editor")
	game.posture_editor_v2.close()
	# Tool panels must not release a stale Space charge when they close.
	Input.action_press("ui_accept")
	game.input_handler._handle_swing_charge(0.08)
	game._toggle_sound_panel()
	game.input_handler._process(0.0)
	check(not game.input_handler.serve_is_charging and human.phase == -1, "sound panel keeps a gameplay charge")
	Input.action_release("ui_accept")
	game.input_handler._process(0.0)
	game._toggle_sound_panel()
	game.input_handler._handle_swing_charge(0.0)
	check(human.phase == -1, "closing sound panel releases a stale swing")
	# Two-bounce rule and kitchen: no illegal airborne contact.
	incoming(game, 0.42, 1.12, 8.0)
	game.ball.both_bounces_complete = false
	var flight: Dictionary = Flight.trace(game.ball.global_position, game.ball.linear_velocity, game.ball.angular_velocity)
	var plan: Dictionary = Planner.select(game.player_left, game.ball, flight)
	check(plan.is_empty() or plan.bounces > 0, "serve return selects illegal pre-bounce contact")
	game.ball.both_bounces_complete = true
	game.player_left.global_position = Vector3(0, game.player_left.ground_y, 1.9)
	check(not Planner.legal_ball(game.player_left, game.ball), "kitchen volley accepted")
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("HUMAN INCOMING CONTACT: %d checks, %d failures; %d/%d returns; max impact error %.3f m" % [checks, failures.size(), returns, cases.size(), maximum_error])
	quit(0 if failures.is_empty() else 1)
