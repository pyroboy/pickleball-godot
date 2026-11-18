extends SceneTree


const Calls = preload("res://scripts/court_callouts.gd")
const Size = preload("res://scripts/paddle_dimensions.gd")
var game
var checks: = 0
var failures: Array[String] = []
var output: = ""
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(message);print("FAIL: ", message)
func frames(count: int) -> void :
	for i in count: await process_frame; await physics_frame
func capture(name: String) -> void :
	if output.is_empty(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
func run() -> void :
	create_timer(75, true).timeout.connect( func(): quit(2))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): output = arg.trim_prefix("--capture-dir=")
	if not output.is_empty():
		if DisplayServer.get_name() == "headless": quit(2);return
		DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(540, 960);root.content_scale_size = Vector2i(720, 1280)
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game);current_scene = game
	await frames(5)
	var calls = game.court_callouts
	check(Calls.score_text(7, 4, 0) == "7 – 4", "Human server score order")
	check(Calls.score_text(7, 4, 1) == "4 – 7", "AI server score order")
	check(Calls.score_text(0, 0, 1).count("–") == 1, "Doubles digit leaked into singles")
	for team in [0, 1]:
		game.score_left = 7;game.score_right = 4;game.serving_team = team
		game.scoreboard_ui.update_score(7, 4)
		game._reset_ball(); await frames(4)
		check(calls.kind == "SCORE" and calls.speaker == team and calls.bubble.visible, "Server call bubble missing")
		check(calls.label.text == ("7 – 4" if team == 0 else "4 – 7"), "Live score not used")
		check( not game.ball.is_in_play and game.game_state == 0, "Score call started serve")
		await capture("score-blue" if team == 0 else "score-red")
		game._set_game_state(game.GameState.SERVING); await frames(1)
		check( not calls.bubble.visible and calls.kind.is_empty(), "Score bubble survived serve start")
	for hitter in [0, 1]:
		game._reset_match()
		game.serving_team = hitter
		game._set_game_state(game.GameState.PLAYING)
		game.rally_scorer._serve_was_hit = true
		game.player_right.set_ai_movement_enabled(false)
		game.ball.global_position = Vector3(3.9, 0.35, -4.3 if hitter == 0 else 4.3)
		game.ball.linear_velocity = Vector3(1.0, -0.7, 0)
		game.ball.last_hit_by = hitter
		game.ball.bounces_since_last_hit = 0
		game.ball.is_in_play = true
		game.ball.both_bounces_complete = true
		# A shot stays live until its first ground contact establishes Out.
		for frame in range(60):
			await frames(1)
			if game.game_state == game.GameState.POINT_SCORED: break
		check(calls.kind == "OUT" and calls.speaker == 1 - hitter and calls.label.text == "Out!", "Receiving player Out call missing")
		check(game.game_state == 3 and not game.ball.is_in_play, "Call preceded authoritative dead ball")
		check( not game.hud.fault.visible and not game.hud.out_text.visible, "Large Out banners obscure the receiver")
		await frames(10)
		var caller = game.player_right if hitter == 0 else game.player_left
		var weight: float = calls.gesture_weight(caller)
		check(weight > 0.5, "Free-hand signal not active")
		var arm = caller.left_arm_node
		var wrist: Vector3 = arm.hand_pivot.global_position
		var shoulder: Vector3 = arm.upper_pivot.global_position
		check(wrist.y > shoulder.y + 0.15, "Free hand was not raised beside head")
		check(wrist.distance_to(shoulder) <= arm.upper_arm_length + arm.forearm_length + 0.002, "Call gesture stretched support arm")
		check(caller.arm_ik._hands.mode == "CALLOUT", "Callout hand did not use owned mount")
		check(caller.right_arm_node.articulated_hand._mode == "GRIP", "Dominant paddle grip changed")
		await capture("out-red" if hitter == 0 else "out-blue")
		game.between_point_controller.skip(); await frames(3)
		check(calls.gesture_weight(caller) == 0 and game.game_state == 0, "Gesture leaked into next serve")
		check( not calls.kind == "OUT", "Old Out bubble survived reset")

	game._reset_match(); await frames(2);calls.clear()
	game.scoreboard_ui.show_out("OUT RISK")
	await frames(2)
	check(calls.kind.is_empty(), "Prediction marker produced a line call")
	calls._on_rally_ended(1, RallyScorer.FAULT_KITCHEN_VOLLEY, "Kitchen")
	check(calls.kind.is_empty(), "Other fault produced Out")
	game.ball.last_hit_by = 0;game.ball.bounces_since_last_hit = 1
	calls._on_rally_ended(0, RallyScorer.FAULT_OUT_OF_BOUNDS, "missed return")
	check(calls.kind.is_empty(), "Legal bounce then roll-out produced Out")
	game.practice_launcher.start_drill("WALL"); await frames(3)
	check( not calls.bubble.visible and calls.kind.is_empty(), "Competitive score leaked into Wall Practice")
	game.practice_launcher.stop_practice(); await frames(2)
	check(calls.kind == "SCORE", "Match score call did not restore")
	pause.open(); await frames(2)
	var remaining: float = calls.remaining
	await frames(10)
	check(is_equal_approx(calls.remaining, remaining), "Pause advanced callout timer")
	pause.close(); await frames(2)
	game.queue_free(); await frames(3)
	print("COURT CALLOUTS ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
