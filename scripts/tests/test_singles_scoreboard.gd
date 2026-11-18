extends SceneTree

var game
var checks := 0
var failures: Array[String] = []
var output := ""
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); print("FAIL: ", message)
func frames(count := 2) -> void:
	for i in count: await process_frame
func capture(label: String) -> void:
	if output.is_empty(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
func setup_rally(server: int, blue := 4, red := 3) -> void:
	game.between_point_controller.cancel()
	game.match_over = false; game.match_winner = -1
	game.serving_team = server; game.score_left = blue; game.score_right = red
	game._reset_ball()
	game.scoreboard_ui.update_score(blue, red)
	game._set_game_state(game.GameState.PLAYING)
	game.rally_scorer._serve_was_hit = true
	game.ball.freeze = true
	game.ball.is_in_play = true
	game.ball.both_bounces_complete = true
	game.player_right.set_ai_movement_enabled(false)
func finish_with_missed_return(winner: int) -> void:
	game.ball.last_hit_by = winner
	game.ball.bounces_since_last_hit = 2
	game.rally_scorer._on_ball_bounced(Vector3(0, 0.082, -4 if winner == 0 else 4))
func marker_on(server: int) -> void:
	var hud = game.hud
	check(hud._serve_ball.visible and hud._server == server, "Serving-ball visibility/owner disagrees")
	var center: Vector2 = hud._score_panel.get_global_rect().get_center()
	check((hud._serve_ball.get_global_rect().get_center().x < center.x) == (server == 0), "Ball appears on wrong fixed team side")
	check(hud._score_panel.get_global_rect().encloses(hud._serve_ball.get_global_rect()), "Ball escapes scoreboard")
func run() -> void:
	create_timer(120, true).timeout.connect(func(): quit(2))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): output = arg.trim_prefix("--capture-dir=")
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(540, 960); root.content_scale_size = Vector2i(720, 1280)
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	await frames(3)
	game.set_process(false); game.input_handler.set_process(false)
	var hud = game.hud
	var ui = game.scoreboard_ui
	game._reset_match(); marker_on(0)
	check(hud.score.text == "0   :   0" and not hud._rally_banner.visible, "New game should be 0-0 without Sideout")
	await capture("singles-initial-blue")
	# Official example, through the authoritative scorer and game's real result path.
	setup_rally(0, 0, 0); finish_with_missed_return(1)
	check(game.score_left == 0 and game.score_right == 0 and game.serving_team == 1, "Receiver won a point rather than just service")
	marker_on(1)
	check(hud._rally_headline.text == "Sideout" and hud._rally_banner.visible, "Exact Sideout announcement missing")
	check(hud._rally_detail.text.contains("score unchanged"), "Sideout presented as a point")
	check(not hud.state.text.begins_with("Sideout"), "Fixture did not exercise independent retrieval status")
	await capture("singles-sideout-red")
	var timer: float = ui._rally_visible_timer
	finish_with_missed_return(0); game._on_rally_ended(0, "DOUBLE_BOUNCE", "duplicate")
	check(game.serving_team == 1 and game.score_left == 0 and game.score_right == 0 and ui._rally_visible_timer == timer, "Duplicate event repeated scoring or announcement")
	game.between_point_controller.skip()
	check(not hud._rally_banner.visible, "Skip carries Sideout into next serve")
	marker_on(1)
	setup_rally(1, 0, 0); finish_with_missed_return(1)
	check(game.score_left == 0 and game.score_right == 1 and game.serving_team == 1, "Server winning rally failed to earn exactly one")
	check(hud._rally_headline.text == "Point!" and hud._rally_detail.text.contains("AI +1"), "Point not distinguished from Sideout")
	marker_on(1); await capture("singles-point-red")
	setup_rally(1, 0, 1); finish_with_missed_return(0)
	check(game.score_left == 0 and game.score_right == 1 and game.serving_team == 0, "Second Sideout changed the score")
	marker_on(0); await capture("singles-sideout-blue")
	for pvp in [false, true]:
		game.pvp_mode = pvp
		for server in [0, 1]:
			for winner in [0, 1]:
				setup_rally(server)
				finish_with_missed_return(winner)
				check(game.serving_team == winner, "Result lost correct server")
				check(game.score_left == 4 + (1 if winner == server and server == 0 else 0), "Blue wrong side-out score")
				check(game.score_right == 3 + (1 if winner == server and server == 1 else 0), "Red wrong side-out score")
				check(hud._rally_headline.text == ("Sideout" if winner != server else "Point!"), "Wrong result type")
				marker_on(winner)
				if pvp: check(not hud._rally_detail.text.contains("AI") and hud._serve_label.text.begins_with("BLUE" if winner == 0 else "RED"), "PvP mislabeled as AI")
			# The actual serve-position fault path must produce one sideout.
			setup_rally(server)
			game.game_serve.trigger_server_position_fault("FOOT_FAULT")
			check(game.serving_team == 1-server and game.score_left == 4 and game.score_right == 3, "Serve foot fault added point")
			check(hud._rally_headline.text == "Sideout" and hud.fault.visible, "Serve fault lost independent Sideout/reason")
			marker_on(1-server)
			game.game_serve.trigger_server_position_fault("FOOT_FAULT")
			check(game.serving_team == 1-server and game.score_left == 4 and game.score_right == 3, "Serve fault emitted twice")
			# Game end must never advertise a next serve or sole scoring eligibility.
			setup_rally(server, 10 if server == 0 else 8, 10 if server == 1 else 8)
			finish_with_missed_return(server)
			check(game.match_over and game.match_winner == server, "Game-winning point missed")
			check(not hud._serve_ball.visible and hud._serve_label.text == "MATCH OVER", "Game over advertises a next server")
			check(hud._rally_headline.text.contains("win") and not hud._rally_headline.text.contains("Sideout"), "Game winner is a misleading sideout")
			game.request_rematch(); marker_on(0)
			check(not hud._rally_banner.visible and game.score_left == 0 and game.score_right == 0, "Rematch retains previous result")
	game.pvp_mode = false
	# Service parity uses the new server's own score, never combined score.
	for server in [0, 1]:
		for own_score in [0, 1, 2, 9]:
			setup_rally(server, own_score if server == 0 else 6, own_score if server == 1 else 6)
			check(game.get_server_score() == own_score, "Wrong own-score parity source")
			var player = game.player_left if server == 0 else game.player_right
			var right_x: float = 1.0 if server == 0 else -1.0
			check(signf(player.global_position.x) == (right_x if own_score % 2 == 0 else -right_x), "Server not on correct odd/even service side")
			for camera_mode in range(3):
				game.camera_rig.cycle_third_person()
				ui._sync_match_context(); marker_on(server)
		# First-bounce out and wrong service court must announce only once.
		for reason in ["OUT", "SHORT", "DIAGONAL"]:
			setup_rally(server)
			game.rally_scorer._serve_was_hit = false
			game.ball.both_bounces_complete = false
			game.ball.last_hit_by = server; game.ball.bounces_since_last_hit = 1
			var sign_side: float = -1.0 if server == 0 else 1.0
			var landing := Vector3(sign_side * 3.4, 0.082, sign_side * 4.0)
			if reason == "SHORT": landing = Vector3(sign_side, 0.082, sign_side)
			if reason == "DIAGONAL": landing = Vector3(-sign_side if game.get_server_score() % 2 == 0 else sign_side, 0.082, sign_side * 4.0)
			game.rally_scorer._on_ball_bounced(landing)
			check(game.serving_team == 1-server and game.score_left == 4 and game.score_right == 3, "Service landing fault changes wrong score/server")
			check(hud._rally_headline.text == "Sideout", "Landing fault lost Sideout")
			marker_on(1-server)
	setup_rally(0, 10, 10); finish_with_missed_return(0)
	check(not game.match_over and game.score_left == 11, "11-10 must continue until win-by-two")
	marker_on(0)
	setup_rally(0); finish_with_missed_return(1)
	pause.open(); var before: float = ui._rally_visible_timer
	await frames(6)
	check(is_equal_approx(ui._rally_visible_timer, before), "Pause consumes result timer")
	pause.close()
	ui._update_timers(3.0)
	check(not hud._rally_banner.visible, "Sideout does not expire")
	marker_on(1)
	setup_rally(0); finish_with_missed_return(1)
	ui.hide_all_hud()
	check(not hud._rally_banner.visible and not hud._serve_ball.visible, "Editor hide leaks singles UI")
	ui.show_all_hud(); marker_on(1)
	check(not hud._rally_banner.visible, "Editor reopen resurrects old Sideout")
	for mode in ["WALL", "DINK"]:
		game.practice_launcher.start_drill(mode); ui._sync_match_context(); ui._update_timers(0.0)
		check(not hud._serve_ball.visible and not hud._rally_banner.visible, "Competitive scoring shown in practice " + mode)
		game.practice_launcher.stop_practice(); ui._sync_match_context(); marker_on(game.serving_team)
	# Repeat layouts, both ownership states; screen rotation cannot move identity.
	for resolution in [Vector2i(720, 1280), Vector2i(540, 960), Vector2i(600, 960), Vector2i(1440, 900), Vector2i(800, 600)]:
		root.content_scale_size = resolution; root.size = resolution
		await frames(2); hud._layout_desktop()
		for server in [0, 1]:
			setup_rally(1-server); finish_with_missed_return(server)
			marker_on(server)
			var screen := Rect2(Vector2.ZERO, root.get_visible_rect().size)
			check(screen.encloses(hud._rally_banner.get_global_rect()), "Result offscreen at " + str(resolution))
			check(not hud._rally_banner.get_global_rect().intersects(hud._score_panel.get_global_rect()), "Result overlaps scoreboard")
			check(not hud._rally_banner.get_global_rect().intersects(hud._toolbar.get_global_rect()), "Result overlaps controls")
			check(not hud._rally_banner.get_global_rect().intersects(hud.fault.get_global_rect()), "Result overlaps fault explanation at " + str(resolution))
			if server == 1: await capture("singles-layout-%dx%d" % [resolution.x, resolution.y])
	game.queue_free(); await frames(3)
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	print("SINGLES SCOREBOARD: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
