extends SceneTree

var game
const OUT: = "/workspace/shared/mobileqa/two-stick"
func _initialize() -> void : call_deferred("run")
func capture(label: String) -> void :
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(label + ".png"))
func run() -> void :
	var pause = root.get_node("PauseController")
	root.focus_exited.disconnect(pause._on_window_focus_exited)
	root.focus_entered.disconnect(pause._on_window_focus_entered)
	DirAccess.make_dir_recursive_absolute(OUT)
	paused = false
	root.size = Vector2i(432, 936);root.content_scale_size = Vector2i(720, 1560)
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	game.input_handler.set_process(false)
	for i in range(8): await physics_frame
	game.input_handler._process(0)
	await capture("portrait_01_ready")
	game.mobile_controls._press(1, game.mobile_controls._charge_center)
	for i in range(20):
		game.input_handler._process(1.0 / 60.0)
		await physics_frame
	game.mobile_controls._press(2, game.mobile_controls._stick_center + Vector2(0, -60))
	for i in range(8):
		game.input_handler._process(1.0 / 60.0)
		await physics_frame
	game.mobile_controls._drag(1, game.mobile_controls._charge_center + Vector2(-1, -1).normalized() * game.mobile_controls._charge_radius)
	await capture("portrait_02_aim")
	game.mobile_controls._drag(1, game.mobile_controls._charge_center + Vector2(1, -1).normalized() * game.mobile_controls._charge_radius)
	await capture("portrait_09_slice")
	game.mobile_controls._drag(1, game.mobile_controls._charge_center + Vector2(0, 1) * game.mobile_controls._charge_radius)
	await capture("portrait_10_drop")
	game.mobile_controls.cancel_all();game.hud.set_debug_mode(true)
	await capture("portrait_03_debug")
	game.hud.set_debug_mode(false);game.hud._toggle_guide()
	await capture("portrait_04_guide")
	game.hud._toggle_guide()
	pause.open()
	await capture("portrait_05_pause")
	pause._menu._on_settings()
	await capture("portrait_08_settings")
	pause._menu._settings_overlay._on_close()
	await process_frame
	game.practice_panel.open_practice()
	await capture("portrait_06_practice")
	game.practice_panel.close_picker();pause.close()
	game.score_left = 11;game.score_right = 7;game.scoreboard_ui.update_score(11, 7);game.match_over = true
	game.match_winner = 0
	await process_frame
	await capture("portrait_07_rematch")
	print("PORTRAIT VISUAL DONE")
	quit()
