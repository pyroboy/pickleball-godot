extends SceneTree
const Accuracy = preload("res://scripts/shot_accuracy.gd")
const Aim = preload("res://scripts/aim_controller.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
var checks: = 0
var failures: Array[String] = []
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(message)
func run() -> void :
	create_timer(45).timeout.connect( func(): quit(2))
	var totals: = {"pass": 0, "fail": 0, "errors": []}
	load("res://scripts/tests/test_aim_controller.gd").new().run_all(totals)
	check(totals.fail == 0, "unit aim ranges/motion/lock/reset pass")
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await physics_frame
	await physics_frame
	game.input_handler.set_process(false)
	game.reaction_button.auto_fire_on_perfect = false
	game.ai_difficulty = 2
	game.shot_physics.accuracy.rng.seed = 912
	check(not game._apply_player_contact_hit(0.7, 0), "invalid contact rejected")
	check(game.shot_physics.accuracy.samples == 0, "invalid contact does not sample accuracy")
	var aim = game.aim_controller
	var input = game.input_handler
	var player = game.player_left
	aim.update(0.1, false, Vector2.ZERO)
	check(aim.mode == "SERVE" and not aim.cursor_visible, "serve target stays hidden before active aiming")
	check(aim.get_target().x < 0 and aim.get_target().z < -2.6, "serve default lands diagonal service box")
	var bracket: = InputEventKey.new()
	bracket.keycode = KEY_BRACKETLEFT
	bracket.pressed = true
	input._unhandled_key_input(bracket)
	input._update_aim_and_arc(0.1)
	check(aim.get_target().x < -1.5, "legacy left bracket moves same landing marker")
	bracket.pressed = false
	Input.parse_input_event(bracket)
	Input.action_press("move_right")
	check(player._get_human_input().x > 0, "directions move body before preparation")
	Input.action_press("ui_accept")
	input._process(0.12)
	var first_target: Vector3 = aim.get_target()
	check(aim.planted and aim.mode == "AIM", "serve Space explicitly plants and aims")
	check(player._get_human_input() == Vector3.ZERO, "arrows cannot walk while aiming")
	input._process(0.12)
	check(aim.get_target().x > first_target.x, "held right moves visible serve marker")
	Input.action_release("move_right")
	Input.action_press("move_up")
	input._process(0.1)
	Input.action_release("move_up")
	var requested: Vector3 = aim.get_target()
	game.game_trajectory._update_player_cursor()
	check(game.game_trajectory.landing_cursor.visible, "landing marker visible")
	check(absf(game.game_trajectory.landing_cursor.global_position.z - requested.z) < 0.001, "marker follows actual target")
	check(game.shot_physics.accuracy.samples == 0, "held aim and preview do not sample accuracy")
	Input.action_release("ui_accept")
	input._process(0.0)
	check(game.shot_physics.accuracy.samples == 0, "release commits intention without sampling before contact")
	check(game.game_state == 1 and aim.is_locked(), "release freezes target through serving animation")
	aim.nudge(Vector2.LEFT, 1)
	check(aim.get_target().is_equal_approx(requested), "target cannot drift after serve release")
	for i in range(120):
		await physics_frame
		if game.game_state == 2: break
	check(game.game_state == 2 and not aim.should_plant_player(), "serve contact restores movement")
	check(game.ball.get_meta("aim_target", Vector3.INF).is_equal_approx(requested), "serve executes exact locked cursor")
	check(game.shot_physics.accuracy.samples == 1, "accepted serve contact samples exactly once")
	if not game.ball.has_meta("shot_profile"):
		push_error("serve did not reach physical contact: %s" % failures)
		quit(1)
		return
	var serve_profile: Dictionary = game.ball.get_meta("shot_profile")
	var serve_axes: Vector2 = serve_profile.accuracy_radii
	serve_axes *= 1.0 + Accuracy.SOLVER_ALLOWANCE / minf(serve_axes.x, serve_axes.y)
	var predicted: Dictionary = Flight.trace(game.ball.global_position, game.ball.linear_velocity, game.ball.angular_velocity, 3, 1, false)
	print("AIM SERVE target=", requested, " actual_prediction=", predicted.first_bounce, " position=", game.ball.global_position, " velocity=", game.ball.linear_velocity)
	check(Vector2((predicted.first_bounce.x - requested.x) / serve_axes.x, (predicted.first_bounce.z - requested.z) / serve_axes.y).length() <= 1.0, "serve prediction lies inside estimated accuracy area")
	game.player_right.set_ai_movement_enabled(false)
	game.player_right.global_position.x = 2.8
	var serves_landed: Array[Vector3] = []
	game.ball.bounced.connect( func(point): serves_landed.append(point))
	for frame in range(160):
		await physics_frame
		if not serves_landed.is_empty(): break
	check( not serves_landed.is_empty(), "aimed serve bounces live")
	if not serves_landed.is_empty():
		print("AIM LIVE SERVE landing=", serves_landed[0], " target=", requested)
		check(Vector2((serves_landed[0].x - requested.x) / serve_axes.x, (serves_landed[0].z - requested.z) / serve_axes.y).length() <= 1.0, "live serve lands within shown accuracy area")

	game.set_physics_process(false)
	game.rally_scorer._serve_was_hit = true
	player.global_position = Vector3(0, player.ground_y, 3.2)
	player.current_velocity = Vector3.ZERO
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
	game._on_player_swing_press()
	check(is_equal_approx(Engine.time_scale, 1.0) and not game._in_slow_mo, "rally Space preparation does not activate slow motion")
	var human = player.posture.human_contact
	check( not human.contact.is_empty(), "test feed is in real paddle reach")
	aim.update(0.1, true, Vector2.RIGHT)
	check( not aim.planted and aim.mode == "PREPARE", "held chasing direction remains movement")
	aim.update(0.03, true, Vector2.ZERO)
	check( not aim.planted, "brief neutral does not unexpectedly plant")
	aim.update(0.04, true, Vector2.ZERO)
	check(aim.planted and aim.mode == "AIM", "deliberately settling plants for reachable ball")
	Input.action_press("move_left")
	var body_before: Vector3 = player.global_position
	player._physics_process(0.02)
	check(player.global_position.distance_to(body_before) < 0.001, "aiming has no body drift")
	var rally_before: Vector3 = aim.get_target()
	aim.update(0.12, true, Vector2(-1, 1))
	check(aim.get_target().x < rally_before.x and aim.get_target().z > rally_before.z, "rally marker moves left and shorter")
	var rally_target: Vector3 = aim.get_target()
	check(human.request_swing(0.7), "reachable rally shot commits")
	game.select_drop_shot()
	aim.update(0.2, false, Vector2.RIGHT)
	check(aim.get_target().is_equal_approx(rally_target), "next shot type cannot move locked current target")
	game.cycle_spin_mode()
	game.cycle_spin_mode()
	aim.update(0.1, false, Vector2.LEFT)
	check(aim.get_target().is_equal_approx(rally_target), "Q spin changes cannot move current frozen target")
	check(game.selected_spin_mode == 1 and game._frozen_spin_mode == 0, "current flat shot and next topspin remain distinct")
	Input.action_release("move_left")
	for i in range(70):
		await physics_frame
		if ball.last_hit_by == 0: break
	check(ball.last_hit_by == 0, "aimed rally hits real ball")
	if ball.last_hit_by == 0:
		check(game.shot_physics.accuracy.samples == 2, "accepted rally contact samples once")
		check(ball.get_meta("aim_target", Vector3.INF).is_equal_approx(rally_target), "real rally launch uses frozen cursor")
		check( not aim.should_plant_player(), "movement returns at contact before follow-through ends")
		Input.action_press("move_right")
		check(player._get_human_input().x > 0, "can recover position during follow-through")
		Input.action_release("move_right")
	human.cancel()
	game.select_drop_shot()
	aim.update(0.1, false, Vector2.ZERO)
	check(absf(aim.get_target().z) <= 1.55, "next Drop resets marker into kitchen")
	aim.capture()
	human.cancel()
	check( not aim.should_plant_player(), "cancel releases planted target")
	check(game.shot_physics.accuracy.samples == 2, "cancelling aim consumes no accuracy sample")
	game._reset_ball()
	aim.update(0.1, true, Vector2.ZERO)
	if preload("res://scripts/runtime_policy.gd").developer_tools:
		game._toggle_posture_editor_v2()
		input._process(0.1)
		check( not aim.should_plant_player() and not aim.cursor_visible, "editor clears aim and marker")
		game.posture_editor_v2.close()
	else:
		check(game.posture_editor_v2 == null, "mobile runtime excludes developer posture editor")
		game._toggle_posture_editor_v2()
		check(game.posture_editor_v2 == null and not game._tool_state_active(), "mobile runtime blocks editor toggle")
		input.cancel_charge_input()
		input._process(0.1)
		game.game_trajectory._update_player_cursor()
		check(not aim.should_plant_player() and not aim.cursor_visible and not game.game_trajectory.landing_cursor.visible, "mobile cancellation clears aim and world marker")
	check( not game._in_slow_mo, "tool interruption or cancellation does not leave aiming slow motion")
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("AIM GAMEPLAY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
