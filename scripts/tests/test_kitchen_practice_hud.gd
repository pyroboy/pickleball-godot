extends SceneTree
const Layout = preload("res://scripts/ui/mobile_layout.gd")
var checks: = 0
var failures: Array[String] = []
var output: = ""
func _initialize(): call_deferred("run")
func check(ok: bool, detail: String) -> void :
	checks += 1
	if not ok: failures.append(detail)
func run() -> void :
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): output = arg.trim_prefix("--capture=")
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	var hud = game.hud
	var practice = game.practice_launcher
	for size in [Vector2i(1080, 2340), Vector2i(600, 960)]:
		root.content_scale_size = size
		root.size = size
		await process_frame
		await process_frame
		for pattern in ["WIDE", "ATTACK"]:
			practice.start_drill("DINK", true, 1, pattern)
			practice.loop_enabled = false
			game.ball.freeze = true
			game.ball.linear_velocity = Vector3.ZERO
			practice.exchange_count = 12
			practice.best_exchange_count = 18
			practice._show_exchange_status()
			hud._layout_desktop()
			hud.set_status_text(practice.status_text)
			game.scoreboard_ui._sync_match_context()
			await process_frame
			var tag: String = "%s %s" % [size, pattern]
			check( not hud.state.text.contains("\n") and hud.state.max_lines_visible == 1, tag + " multiline practice status")
			check(hud.state.text.contains("12 hits") and hud.state.text.contains("best 18"), tag + " hidden exchange state")
			check(hud.state.get_line_count() == 1, tag + " wrapped status")
			check( not hud._charge_label.text.contains("HOLD") and not hud._controls_hint.text.contains("MOVE"), tag + " manual input prompts during autonomous demo")
			check( not hud._charge_bar.visible, tag + " irrelevant charge meter visible")
			check(hud._serve_label.text == "OPENING BOUNCES COMPLETE", tag + " exchange presents a false serve instruction")
			check(hud.state.get_global_rect().end.y <= hud._charge_label.get_global_rect().position.y, tag + " status overlaps helper row")
			var safe: Rect2 = Layout.safe_rect(root)
			check(hud._guidance_chrome.get_global_rect().end.y < Layout.court_rect(safe.size, safe).position.y, tag + " HUD expanded into court")
			if not output.is_empty() and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join("practice_%dx%d_%s.png" % [size.x, size.y, pattern.to_lower()]))
			practice.stop_practice()
			game.scoreboard_ui._sync_match_context()
			hud.set_aim_state("MOVE")
			check(hud._charge_bar.visible and hud._charge_label.text.contains("HOLD"), tag + " manual charge helper not restored")
			check( not hud._serve_label.text.contains("BOUNCES COMPLETE"), tag + " warm-start label retained after exit")
	game.queue_free()
	await process_frame
	await process_frame
	for failure in failures: push_error(failure)
	print("KITCHEN PRACTICE HUD: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
