extends SceneTree

const OUT: = "/workspace/shared/pickleball-visuals/screens"
var game
func _initialize() -> void : call_deferred("run")
func frames(count: int) -> void :
	for i in range(count): await physics_frame
func capture(label: String) -> void :
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(label + ".png"))
func run() -> void :
	create_timer(50).timeout.connect( func(): quit(2))
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	root.get_node("Settings")._config.set_value("video", "shadow_quality", 0)
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(720, 1560);root.content_scale_size = Vector2i(720, 1560)
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	game.input_handler.set_process(false)
	await frames(12)
	game.input_handler._process(0)
	await capture("01_actual_portrait_hold")
	game.game_serve.start_charge()
	game.game_serve.tick_charge(0.14 * PickleballConstants.MAX_SERVE_CHARGE_TIME)
	await frames(2); await capture("02_partial_charge")
	game.game_serve.tick_charge(0.86 * PickleballConstants.MAX_SERVE_CHARGE_TIME)
	await frames(2); await capture("03_full_charge")
	game.game_serve.cleanup();game._reset_ball(); await frames(2)
	game.hud._toggle_guide(); await capture("04_guide");game.hud._toggle_guide()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.hud.set_gameplay_elements_visible(false)
	game.mobile_controls.hide()
	game.main_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	game.main_camera.fov = 42
	var player = game.player_left
	game.main_camera.global_position = player.global_position + Vector3(2.25, 1.15, 3.55)
	game.main_camera.look_at(player.global_position + Vector3(0, 0.05, 0), Vector3.UP)
	await frames(2); await capture("05_model_close_review")
	print("REFERENCE VISUAL CAPTURES DONE")
	quit()
