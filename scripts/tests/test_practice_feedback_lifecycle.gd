extends SceneTree
## Actual menu pointer events and naturally produced practice feedback.
## Supplemental match-end fixture is explicitly labeled; it does not create feedback.
var game
var rate := 60
var output := ""
var failures: Array = []
var records: Array = []
var checks := 0
var start_usec := 0
var natural_faults := 0
var phase := "startup"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rate="): rate = int(arg.trim_prefix("--rate="))
		if arg.begins_with("--output=" ): output = arg.trim_prefix("--output=" )
	Engine.physics_ticks_per_second = rate
	Engine.max_fps = rate
	seed(271828)
	call_deferred("run")

func frames(n: int) -> void:
	for i in n: await process_frame
func seconds(n: float) -> void:
	var end := Time.get_ticks_usec() + int(n * 1000000.0)
	while Time.get_ticks_usec() < end: await process_frame
func state() -> Dictionary:
	if not is_instance_valid(game): return {}
	return {"phase": phase, "time": float(Time.get_ticks_usec()-start_usec)/1e6, "physics_frame": Engine.get_physics_frames(), "practice": game.practice_launcher.drill_mode if game.practice_launcher.is_active else "", "attempt": game.practice_launcher.attempt_count, "fault": game.hud.fault.text, "visible": game.hud.fault.visible, "timer": game.scoreboard_ui._fault_visible_timer, "paused": paused, "state": game.game_state, "match_over": game.match_over, "score": [game.score_left, game.score_right], "flight": game.ball.flight_id}
func record(event: String, extra: Dictionary = {}) -> void:
	var row := state(); row["event"] = event; row["extra"] = extra
	records.append(row)
	print("FEEDBACK_EVENT ", JSON.stringify(row))
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		var row := state(); row["failure"] = label; failures.append(row)
		print("FEEDBACK_FAILURE ", JSON.stringify(row))
func find_button(node: Node, label: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == label: return child
		var found := find_button(child, label)
		if found != null: return found
	return null
func tap(button: Button) -> void:
	if button == null:
		check(false, "Required menu button missing"); return
	var parent := button.get_parent()
	while parent != null:
		if parent is ScrollContainer: parent.ensure_control_visible(button)
		parent = parent.get_parent()
	await frames(2)
	var point := button.get_global_rect().get_center()
	var viewport := button.get_viewport()
	record("pointer_button", {"text": button.text, "point": [point.x, point.y]})
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT; event.position = point; event.global_position = point; event.pressed = pressed
		viewport.push_input(event, true)
		await frames(1)
	await frames(2)
func dialog_button(button: Button) -> void:
	# Native child-window mouse dispatch is unavailable in the headless display.
	# Exercise its existing visible button callback, not game reset internals.
	record("dialog_button_callback_supplement", {"text": button.text})
	button.pressed.emit()
	await frames(3)
func capture(tag: String) -> void:
	if DisplayServer.get_name() == "headless" or output.is_empty(): return
	await RenderingServer.frame_post_draw
	var path := output.path_join(tag + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "Native screenshot " + tag)
func picker() -> void:
	if not paused: await tap(game.hud._pause_button)
	check(paused, "Pause pointer opens menu")
	await tap(find_button(root.get_node("PauseController")._menu, "Practice drills"))
	check(game.practice_panel._picker_open, "Practice picker pointer opens")
func choose(label: String) -> void:
	await picker()
	await tap(find_button(game.practice_panel, label))
func hands_fault() -> bool:
	await choose("Kitchen-line fast hands")
	check(not paused and game.practice_launcher.drill_mode == "HANDS", "Hands selected through menu")
	var deadline := Time.get_ticks_usec() + 12000000
	while Time.get_ticks_usec() < deadline:
		await process_frame
		if game.practice_launcher._attempt_finished and game.hud.fault.visible:
			natural_faults += 1
			record("natural_practice_fault")
			check(game.hud.fault.text.begins_with("MISSED VOLLEY"), "Natural untouched HANDS feed misses volley")
			return true
	check(false, "Natural HANDS fault failed to occur within 12 seconds")
	return false
func clear_check(label: String) -> void:
	record(label)
	check(not game.hud.fault.visible, label + " hides stale fault")
	check(is_zero_approx(game.scoreboard_ui._fault_visible_timer), label + " cancels fault timer")
func no_resurrection() -> void:
	await seconds(2.75)
	record("after old timer deadline")
	check(not game.hud.fault.visible and game.scoreboard_ui._fault_visible_timer <= 0.0, "Old timer deadline cannot restore feedback")
func spawn_game() -> void:
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game); current_scene = game
	await frames(8)
func run() -> void:
	start_usec = Time.get_ticks_usec()
	create_timer(180.0, true).timeout.connect(func(): quit(2))
	root.size = Vector2i(540, 960); root.content_scale_size = Vector2i(720, 1280)
	await spawn_game()
	phase = "return_match_pause_resume"
	if not await hands_fault(): await finish(); return
	await capture("01-natural-hands-fault")
	var timer_before: float = game.scoreboard_ui._fault_visible_timer
	await tap(game.hud._pause_button)
	var timer_paused: float = game.scoreboard_ui._fault_visible_timer
	await seconds(0.5)
	check(game.hud.fault.visible and is_equal_approx(timer_paused, game.scoreboard_ui._fault_visible_timer), "Pause preserves feedback and timer")
	await tap(root.get_node("PauseController")._menu._resume_button)
	check(game.hud.fault.visible and game.scoreboard_ui._fault_visible_timer < timer_before, "Resume retains current feedback with ordinary timer")
	await choose("Return to match")
	check(not game.practice_launcher.is_active and not paused and game.game_state == 0, "Returned to ordinary serve")
	clear_check("return to match")
	await capture("02-return-to-match")
	await no_resurrection()

	phase = "switch_drill"
	if not await hands_fault(): await finish(); return
	await choose("Serve placement")
	check(game.practice_launcher.is_active and game.practice_launcher.drill_mode == "SERVE", "Switched to serve practice")
	clear_check("switch to serve")
	await capture("03-switch-to-serve")
	await no_resurrection()

	phase = "automatic_repeat"
	if not await hands_fault(): await finish(); return
	var initial_attempt: int = game.practice_launcher.attempt_count
	var expiry := Time.get_ticks_usec() + 3000000
	while game.practice_launcher.attempt_count == initial_attempt and Time.get_ticks_usec() < expiry: await process_frame
	check(game.practice_launcher.attempt_count == initial_attempt+1, "Normal automatic repeat occurred")
	clear_check("automatic repeat")
	await capture("04-automatic-repeat")
	await choose("Return to match")

	phase = "manual_repeat"
	if not await hands_fault(): await finish(); return
	await choose("Repeat current drill")
	clear_check("manual repeat")
	await choose("Return to match")

	phase = "reset_cancel_confirm"
	if not await hands_fault(): await finish(); return
	await tap(game.hud._pause_button)
	var pause = root.get_node("PauseController")
	await tap(pause._menu._reset_button)
	check(pause._menu._reset_dialog.visible, "Reset confirmation visible")
	await dialog_button(pause._menu._reset_dialog.get_cancel_button())
	check(paused and game.hud.fault.visible, "Cancel reset preserves current paused feedback")
	await tap(pause._menu._reset_button)
	await dialog_button(pause._menu._reset_dialog.get_ok_button())
	check(not paused and not game.practice_launcher.is_active and game.score_left == 0 and game.score_right == 0, "Confirmed reset creates clean match")
	clear_check("confirmed reset")
	await no_resurrection()

	phase = "rapid_practice_changes"
	if not await hands_fault(): await finish(); return
	for caption in ["Baseline drive", "Live crosscourt dinking", "Serve return", "Wall Practice · solo rebound court", "Serve placement"]:
		await choose(caption)
		clear_check("rapid change " + caption)
	await choose("Return to match")
	clear_check("rapid changes return")
	await no_resurrection()

	phase = "same_context_expiry_supplement"
	# Freeze only automatic repeat via its ordinary loop-toggle method. Feedback
	# itself is still generated by an untouched, real HANDS feed.
	await choose("Kitchen-line fast hands")
	game.practice_launcher.toggle_loop()
	record("disable_repeat_for_duration_audit")
	var wait_end := Time.get_ticks_usec()+12000000
	while not game.practice_launcher._attempt_finished and Time.get_ticks_usec()<wait_end: await process_frame
	check(game.hud.fault.visible, "Natural fault visible with repeat disabled")
	var ttl: float = game.scoreboard_ui._fault_visible_timer
	check(ttl > 2.35 and ttl <= 2.5, "Unchanged initial 2.5-second lifetime")
	await seconds(0.6)
	check(game.hud.fault.visible and game.scoreboard_ui._fault_visible_timer > 1.5, "Current-context feedback remains after 0.6 seconds")
	await seconds(2.0)
	check(not game.hud.fault.visible and game.scoreboard_ui._fault_visible_timer <= 0.0, "Current-context feedback expires normally")
	await choose("Return to match")

	phase = "match_end_snapshot_supplement"
	# Explicit near-end score fixture invokes normal scoring; no feedback fabricated.
	game.score_left = 10; game.score_right = 0; game.serving_team = 0
	game._on_point_scored(0)
	await frames(4)
	check(game.match_over and game.practice_panel._shown_result, "Supplemental match-end result visible")
	record("seeded_match_end_fixture")
	await tap(find_button(game.practice_panel, "Practice drills"))
	await tap(find_button(game.practice_panel, "Kitchen-line fast hands"))
	wait_end = Time.get_ticks_usec()+12000000
	while not game.practice_launcher._attempt_finished and Time.get_ticks_usec()<wait_end: await process_frame
	check(game.hud.fault.visible, "Natural practice feedback from completed-match snapshot")
	await choose("Return to match")
	check(game.match_over and game.score_left == 11 and game.score_right == 0, "Restored completed match")
	clear_check("return to completed match")
	await tap(find_button(game.practice_panel, "Rematch"))
	check(not game.match_over and game.score_left == 0, "Result Rematch pointer resets match")
	clear_check("rematch")
	await no_resurrection()
	await finish()
func finish() -> void:
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"rate": rate, "checks": checks, "failures": failures, "natural_faults": natural_faults, "records": records, "scope": "Headless actual GUI pointer-input lifecycle regression. Real naturally produced HANDS faults; no fabricated feedback. Loop-toggle and seeded end-score fixture explicitly supplemental."}, "\t")); file.close()
	root.get_node("PauseController").close()
	if is_instance_valid(game): game.queue_free()
	await frames(3)
	print("FEEDBACK_RESULT ", JSON.stringify({"rate": rate, "checks": checks, "failures": failures.size(), "natural_faults": natural_faults}))
	quit(0 if failures.is_empty() else 1)
