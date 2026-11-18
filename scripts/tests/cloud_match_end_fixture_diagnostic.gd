extends SceneTree
## Cloud diagnostic copy of the unchanged baseline match-end fixture.
## Only adds state evidence; assertions remain unchanged.
var game
var checks: = 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func held(mode: String, pressed: bool):
	if mode == "desktop":
		if pressed: Input.action_press("ui_accept")
		else: Input.action_release("ui_accept")
	else:
		var touch: = InputEventScreenTouch.new()
		touch.index = 44;touch.position = game.mobile_controls._charge_center;touch.pressed = pressed
		game.mobile_controls._input(touch)
	game.input_handler._handle_swing_charge(0.18 if pressed else 0.0)
func seed_rally():
	game._reset_match();game._set_game_state(game.GameState.PLAYING)
	game.rally_scorer._serve_was_hit = true
	var player = game.player_left
	player.global_position = Vector3(0, player.ground_y, 3.2)
	player.hitting.clear_charge_visual();player.hitting.serving_visual_active = false
	player.leg_ik.feet_initialized = false;player._process(0);player.can_volley_from_feet()
	game.player_right.set_ai_movement_enabled(false)
	game.ball.reset_rally_state();game.ball.both_bounces_complete = true;game.ball.is_in_play = true;game.ball.last_hit_by = 1
	game.ball.global_position = Vector3(0.42, 1.12, 1.5);game.ball.linear_velocity = Vector3(0, 1.5, 8);game.ball.angular_velocity = Vector3.ZERO;game.ball.flight_id += 1
func run():
	root.content_scale_size = Vector2i(600, 960);root.size = Vector2i(600, 960)
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	game.input_handler.set_process(false);game.reaction_button.auto_fire_on_perfect = false
	var time = root.get_node("TimeScale")
	var pause = root.get_node("PauseController")
	for mode in ["desktop", "touch"]:
		seed_rally(); await physics_frame; await physics_frame
		var winner: int = 0 if mode == "desktop" else 1
		game.serving_team = winner
		game.score_left = 10 if winner == 0 else 0;game.score_right = 10 if winner == 1 else 0
		held(mode, true)
		game.aim_controller.update(0.1, true, Vector2.ZERO)
		game.aim_focus._update_presentation(Time.get_ticks_usec())
		check(game.input_handler.serve_is_charging and game.player_left.hitting.charge_visual_active, mode + " fixture lacks held charge")
		print("MATCH-END FOCUS FIXTURE ", mode, " active=", game.aim_focus.active, " holding=", game.aim_focus.holding, " presentation=", game.aim_focus._presentation, " deadline=", game.aim_focus.deadline_usec, " mode=", game.aim_controller.mode, " planted=", game.aim_controller.planted, " contact_sample=", game.aim_focus._rally_contact_sample())
		check(game.aim_focus.active and game.aim_focus._presentation, mode + " fixture lacks focus/prediction")
		if mode == "desktop": game._enter_slow_mo()
		else:
			game.aim_focus.tick(game.aim_focus.deadline_usec, true)
			time.request_hitstop(0.3, 0.1)
			print("MATCH-END HITSTOP FIXTURE slowmo=", time._slowmo_sources, " realtime=", time._realtime_sources, " pause_forced=", time._pause_forced, " focus_deadline=", game.aim_focus.deadline_usec)
			check(time.is_hitstop_active(), "capped-hold fixture lacks pending hitstop")
		game._on_rally_ended(winner, "DOUBLE_BOUNCE", "Match-end lifecycle fixture")
		check(game.match_over and game.match_winner == winner, mode + " did not enter winning branch")
		check( not game.input_handler.serve_is_charging and is_zero_approx(game.input_handler.serve_charge_time), mode + " match win retains held input charge")
		check( not game.game_serve.is_charging() and not game.serve_is_charging and is_zero_approx(game.serve_charge_time), mode + " match win retains serve charge")
		for player in [game.player_left, game.player_right]:
			check( not player.hitting.charge_visual_active and not player.hitting.serving_visual_active and not player.hitting.is_in_follow_through, mode + " match win retains pose owner P%d" % player.player_num)
		var human = game.player_left.posture.human_contact
		check(human.phase < 0 and human._charge_target_pose == null, mode + " match win retains planned swing")
		check( not game.aim_focus.active and not game.aim_focus.holding and not game.aim_focus._presentation and not game.aim_focus._dim.visible and not game.aim_focus._drawing.visible, mode + " match win retains focus effects")
		check(is_equal_approx(Engine.time_scale, 1.0) and not time.is_hitstop_active() and not time.is_slowmo_active(), mode + " match win retains time effect")
		check(game.mobile_controls._charge_id == -1 and game.mobile_controls._guide_show == 0, mode + " match win retains touch ownership/guide")
		game.input_handler._handle_swing_charge(0.2)
		check( not game.input_handler.serve_is_charging and not game.aim_focus.active, mode + " still-held input rearmed at match end")
		held(mode, false)
		await physics_frame; await physics_frame
		check( not game.player_left.hitting.charge_visual_active and human.phase < 0, mode + " late release restarted a pose/swing")
		pause.open();pause._menu._reset_button.pressed.emit();pause._menu._reset_dialog.get_ok_button().pressed.emit()
		check( not game.match_over and game.score_left == 0 and game.score_right == 0 and game.serving_team == 0 and game.game_state == 0 and not paused, mode + " Reset match failed after win")
		held(mode, true)
		check(game.aim_focus.active and game.input_handler.serve_is_charging, mode + " fresh post-reset hold failed to arm")
		game.input_handler.cancel_charge_input();game.mobile_controls.cancel_all();held(mode, false)
	game.queue_free(); await process_frame; await process_frame
	var deadline: = Time.get_ticks_usec() + 150000
	while Time.get_ticks_usec() < deadline: OS.delay_msec(5); await process_frame
	for failure in failures: push_error(failure)
	print("MATCH END INPUT: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
