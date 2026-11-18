extends SceneTree

const Planner = preload("res://scripts/incoming_contact_planner.gd")
var game
var checks: = 0
var failures: Array[String] = []
var hits: = 0
var output: = ""
func _initialize() -> void : call_deferred("run")
func check(ok: bool, text: String) -> void :
	checks += 1
	if not ok: failures.append(text);print("FAIL: ", text)
func frames(count: int) -> void :
	for i in count: await process_frame; await physics_frame
func touch(id: int, point: Vector2, pressed: bool) -> void :
	var event: = InputEventScreenTouch.new()
	event.index = id;event.position = point;event.pressed = pressed
	root.push_input(event, true)
func drag(id: int, point: Vector2) -> void :
	var event: = InputEventScreenDrag.new()
	event.index = id;event.position = point
	root.push_input(event, true)
func capture(name: String) -> void :
	if output.is_empty(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
func run() -> void :
	create_timer(100, true).timeout.connect( func(): push_error("Wall test timeout");quit(2))
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
	check(game.practice_launcher.wall_practice._wall == null, "Inactive mode eagerly built wall geometry")
	game.score_left = 7;game.score_right = 4;game.serving_team = 1
	game.scoreboard_ui.update_score(7, 4)
	game.practice_panel.open_practice()
	await frames(2)
	await capture("practice-picker")
	game.practice_panel._start("WALL")
	await frames(5)
	var wall = game.practice_launcher.wall_practice
	check(wall.active and game.ball.wall_practice_active, "Wall did not enter")
	check( not game.player_right.visible and not game.player_right.ai_movement_enabled, "AI stayed active/visible")
	check( not game.rally_scorer._active, "Match scorer active in wall mode")
	check(game.game_shots._classify_intended_shot(game.ball, game.player_left) == "VOLLEY", "Wall feed mislabeled by match kitchen heuristic")
	check( not game.get_node("Net").visible and game.get_node("Net").collision_layer == 0, "Match net still active")
	check(absf(wall.get_node("CenterNetReference").position.y - 0.075 - 0.8636) < 1e-05, "Reference line wrong height")
	await capture("wall-ready")
	game.ball.hit_by_paddle.connect( func(team): if team == 0: hits += 1)

	var ui = game.mobile_controls
	for tick in 150:
		await frames(1)
		if game.ball.is_in_play: break
	touch(1, ui._charge_center, true)
	var released: = false
	var aimed: = false
	for tick in 240:
		await frames(1)
		if tick % 12 == 0:
			print("WALL INPUT ", tick, " ball=", game.ball.global_position, " p=", game.player_left.global_position, " mode=", game.hud._aim_mode, " contact=", game.player_left.posture.human_contact.contact.get("time", -1), " cue=", game.hud.state.text)
		if game.hud._aim_mode == "AIM" and not released and not aimed:

			aimed = true
			touch(2, ui._stick_center, true)
			drag(2, ui._stick_center + Vector2(0.08, -0.06) * ui._stick_radius)
			await frames(2)
			drag(2, ui._stick_center)
			await capture("wall-aim")
			touch(2, ui._stick_center, false)
		if not released and ui._hit_timing.ready:
			touch(1, ui._charge_center, false)
			released = true
		if hits > 0 or game.practice_launcher._attempt_finished: break
	touch(1, ui._charge_center, false)
	check(released, "Reachable feed never showed release cue")
	check(hits > 0, "Touch release never produced a finite paddle hit")
	print("WALL INPUT RESULT hits=", hits, " released=", released)
	for tick in 180:
		await frames(1)
		if wall.rebounds > 0: break
	check(wall.rebounds > 0, "Player return did not physically rebound")
	check(game.ball.wall_return_ready and game.ball.last_hit_by == -1, "Rebound did not return ownership")
	await capture("wall-rebound")
	for rally_index in 2:
		var before_hits: int = hits
		var receive_z: float = 3.4 if game.ball.linear_velocity.z > 7.2 else 2.7
		var did_press: = false
		var did_release: = false
		touch(3, ui._stick_center, true)
		for tick in 240:
			await frames(1)
			if not did_press and ui._hit_timing.active:
				touch(1, ui._charge_center, true)
				did_press = true
			if game.hud._aim_mode == "AIM" and not did_release:
				drag(3, ui._stick_center)
			if tick % 6 == 0 and not did_release:
				var player: Vector3 = game.player_left.global_position
				var ball: Vector3 = game.ball.global_position
				var v: Vector3 = game.ball.linear_velocity


				var desired_z: float = receive_z
				var lead: float = clampf((desired_z - ball.z) / maxf(v.z, 1.0), 0.0, 0.7)
				var direction: = Vector2(clampf(ball.x + v.x * lead, -2.8, 2.8) - player.x, desired_z - player.z)
				if game.hud._aim_mode == "AIM" or direction.length() < 0.12: direction = Vector2.ZERO
				else: direction = direction.normalized() * clampf(direction.length() * 1.8, 0.25, 0.85)
				drag(3, ui._stick_center + direction * ui._stick_radius)
				print("WALL LOOP ", rally_index, " tick=", tick, " b=", ball, " v=", v, " p=", player, " cue=", ui._hit_timing.caption, " f=", game.player_left.posture.human_contact.footwork.state)
			if not did_release and ui._hit_timing.ready:
				touch(1, ui._charge_center, false)
				did_release = true
			if hits > before_hits or game.practice_launcher._attempt_finished: break
		touch(1, ui._charge_center, false)
		touch(3, ui._stick_center, false)
		check(hits > before_hits, "Continuous wall return failed %d" % rally_index)
		var before_rebounds: int = wall.rebounds
		for tick in 150:
			await frames(1)
			if wall.rebounds > before_rebounds or game.practice_launcher._attempt_finished: break
		await capture("wall-return-%d" % rally_index)

	for speed in [7.0, 20.0]:
		game.practice_launcher.repeat_drill(); await frames(3)
		wall._pending_feed = 0.0
		game.ball.freeze = false;game.ball.is_in_play = true
		game.ball.global_position = Vector3(0, 1.5, 1.2)
		game.ball.linear_velocity = Vector3(0, 0, - speed)
		game.ball.last_hit_by = 0;game.ball.wall_return_ready = false
		game.ball.flight_id += 1
		var before: int = wall.rebounds
		for tick in 60:
			await frames(1)
			if wall.rebounds > before: break
		check(wall.rebounds == before + 1 and game.ball.linear_velocity.z > 0, "Physical wall rebound failed speed=%s" % speed)
		check(game.ball.linear_velocity.z < speed, "Rebound gained energy")
		check(wall.targets > 0, "Target feedback missing")

	game.player_left.global_position.z = 1.2
	game.ball.bounces_since_last_hit = 0
	check(Planner.legal_ball(game.player_left, game.ball), "Wall volley incorrectly uses NVZ rule")
	game.ball.wall_return_ready = false
	check( not Planner.legal_ball(game.player_left, game.ball), "Outgoing ball accepted before wall contact")
	game.ball.wall_return_ready = true
	game.ball.bounces_since_last_hit = 2
	check( not Planner.legal_ball(game.player_left, game.ball), "Double-bounced wall ball accepted")

	touch(7, ui._charge_center, true); await frames(2)
	pause.open(); await frames(2)
	check(paused and not Input.is_action_pressed("ui_accept"), "Pause retained held input")
	await capture("wall-pause")
	pause.close(); await frames(3)
	game.practice_launcher.repeat_drill(); await frames(3)
	var attempt: int = game.practice_launcher.attempt_count
	for tick in 500:
		await frames(1)
		if game.practice_launcher.attempt_count > attempt: break
	check(game.practice_launcher.attempt_count > attempt, "Miss did not automatically reset")
	for repeat_index in 3:
		game.practice_launcher.stop_practice(); await frames(3)
		check( not wall.active and not game.ball.wall_practice_active and not game.ball.wall_return_ready, "Wall state leaked on exit")
		check(game.score_left == 7 and game.score_right == 4 and game.serving_team == 1, "Saved match score/server lost")
		check(game.player_right.visible and game.player_right.process_mode != Node.PROCESS_MODE_DISABLED, "Opponent not restored")
		check(game.get_node("Net").visible and game.get_node("Net").collision_layer != 0, "Net not restored")
		if repeat_index < 2: game.practice_launcher.start_drill("WALL"); await frames(3)
	check(game.ball._net_contact_guard == game.get_node("Net"), "Net sweep owner not restored")
	print("WALL PRACTICE CHECKS ", checks, " failures=", failures.size(), " real_touch_hits=", hits)
	game.queue_free(); await frames(2)
	quit(0 if failures.is_empty() else 1)
