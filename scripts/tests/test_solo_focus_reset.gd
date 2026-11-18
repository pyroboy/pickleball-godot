extends SceneTree
var checks: = 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func run() -> void :
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	var time_scale = root.get_node("TimeScale")
	var f = game.aim_focus
	var pause = root.get_node("PauseController")
	Input.action_press("ui_accept")
	game._on_player_swing_press()
	check(f.active and is_equal_approx(Engine.time_scale, f.START_FOCUS_SCALE), "solo hold does not slow world")
	var start: int = f.started_usec
	f.tick(start + f.MAX_REAL_USEC - 1, true)
	check(f.active, "focus ended before4 real seconds")
	f.tick(start + f.MAX_REAL_USEC, true)
	check( not f.active and f.holding and f.exhausted and is_equal_approx(Engine.time_scale, 1.0), "4-real-second cap did not restore normal time")
	check( not f.begin_hold(), "same held input restarted focus after cap")
	Input.action_release("ui_accept");f.end_hold();game.input_handler.cancel_charge_input()

	Input.action_press("ui_accept");game._on_player_swing_press()
	var real_deadline: int = f.deadline_usec
	while Time.get_ticks_usec() < real_deadline + 20000: await process_frame
	check( not f.active and f.holding and f.exhausted and is_equal_approx(Engine.time_scale, 1.0), "live held input exceeded the real-time cap")
	game.scoreboard_ui._sync_match_context()
	check(game.hud._charge_label.text.contains("REAL TIME"), "cap has no clear control feedback")
	Input.action_release("ui_accept");f.end_hold();game.input_handler.cancel_charge_input()
	Input.action_press("ui_accept");game._on_player_swing_press()
	game.aim_controller.update(0.1, true, Vector2.ZERO)
	f._update_presentation(Time.get_ticks_usec())
	check(f._presentation and f._dim.visible, "aim dim/target effect missing")
	check( not f._world_path.is_empty() and f._world_path.size() <= f.MAX_PREVIEW_POINTS and f.preview_solves > 0, "bounded outgoing preview missing")
	for warning in ["NET RISK", "OUT RISK", "ARC UNCERTAIN", "UPDATING ARC"]:
		f.preview_hint = warning
		game.hud.set_aim_state("AIM")
		check(game.hud._controls_hint.text.contains(warning), "uncertain estimate lacks visible " + warning + " cue")
	f.preview_hint = "ESTIMATED ARC";game.hud.set_aim_state("AIM")
	var solves: int = f.preview_solves
	f._refresh_preview(f._last_preview_usec + 1000, game.aim_controller.get_target() + Vector3(0.1, 0, 0))
	check(f.preview_solves == solves, "preview solved inside throttled interval")
	var old_target: Vector3 = game.aim_controller.target
	game.aim_controller.target += Vector3(0.25, 0, 0)
	f._update_presentation(f._last_preview_usec + 1001)
	check(f.preview_hint == "UPDATING ARC" and f.preview_solves == solves, "stale cached arc looks confident or triggered per-frame solve")
	game.aim_controller.target = old_target
	game._on_player_swing_release(0.3)
	check( not f.active and not f._dim.visible and is_equal_approx(Engine.time_scale, 1.0), "release retained focus")
	Input.action_release("ui_accept");game._reset_ball()
	game.pvp_mode = true
	Input.action_press("ui_accept")
	check( not f.begin_hold(), "PvP permitted solo focus")
	time_scale.request_hitstop(0.2, 0.1)
	check(is_equal_approx(Engine.time_scale, 1.0), "PvP did not stay real time")
	game.pvp_mode = false;f._sync_realtime_mode();Input.action_release("ui_accept")
	check(is_equal_approx(Engine.time_scale, 1.0), "leaving PvP revived a stale time effect")
	for reason in ["pause", "background", "fault", "reset", "guide", "cancel"]:
		game._reset_ball();Input.action_press("ui_accept");game._on_player_swing_press()
		check(f.active, "fixture focus inactive for " + reason)
		match reason:
			"pause": pause.open();pause.close()
			"background": pause._notification(Node.NOTIFICATION_APPLICATION_PAUSED);pause._notification(Node.NOTIFICATION_APPLICATION_RESUMED);pause.close()
			"fault": game._set_game_state(game.GameState.POINT_SCORED)
			"reset": game.request_match_reset()
			"guide": game.hud._guide.show();f.tick(Time.get_ticks_usec(), true);game.hud._guide.hide()
			"cancel": game.input_handler.cancel_charge_input()
		check( not f.active and not f._dim.visible and is_equal_approx(Engine.time_scale, 1.0), reason + " retained time/dim effect")
		Input.action_release("ui_accept");f.end_hold()
	game._reset_match();game.score_left = 4;game.score_right = 7;game.serving_team = 1
	var old_position: Vector3 = game.ball.global_position
	pause.open()
	var menu = pause._menu
	menu._reset_button.pressed.emit()
	check(menu._reset_dialog.visible, "actual Reset Match button did not open confirmation")
	menu._reset_dialog.get_cancel_button().pressed.emit()
	check(game.score_left == 4 and game.score_right == 7 and game.serving_team == 1 and game.ball.global_position.is_equal_approx(old_position), "Cancel reset changed match")
	menu._reset_button.pressed.emit()
	menu._reset_dialog.get_ok_button().pressed.emit()
	check(game.score_left == 0 and game.score_right == 0 and game.serving_team == 0 and game.game_state == 0 and not paused, "confirmed reset did not restore clean match")
	check( not f.active and not f._presentation and is_equal_approx(Engine.time_scale, 1.0), "reset retained effects")
	game._set_game_state(game.GameState.PLAYING)
	var cues: int = game.court_audio.cues_played
	game._on_point_scored(0)
	check(game.court_audio.cues_played == cues + 1, "point audio game hook missing")
	game._on_point_scored(0)
	check(game.court_audio.cues_played == cues + 1, "duplicate point played duplicate audio")
	game.queue_free(); await process_frame; await process_frame


	var audio_deadline: int = Time.get_ticks_usec() + 150000
	while Time.get_ticks_usec() < audio_deadline:
		OS.delay_msec(5)
		await process_frame
	await process_frame; await process_frame
	check(is_equal_approx(Engine.time_scale, 1.0), "scene exit leaked time scale")
	for failure in failures: push_error(failure)
	print("SOLO FOCUS RESET: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
