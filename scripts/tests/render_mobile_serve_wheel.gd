extends SceneTree

var game
const OUT: = "/workspace/shared/mobileqa/final-mobile"
func _initialize() -> void : call_deferred("run")
func capture(label: String) -> void :
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(label + ".png"))
	print("MOBILE CAPTURE ", label)
func run() -> void :
	var pause = root.get_node("PauseController")
	root.focus_exited.disconnect(pause._on_window_focus_exited)
	root.focus_entered.disconnect(pause._on_window_focus_entered)
	DirAccess.make_dir_recursive_absolute(OUT)
	paused = false
	root.size = Vector2i(432, 936);root.content_scale_size = Vector2i(720, 1560)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game);current_scene = game
	game.input_handler.set_process(false)
	for frame in range(8): await physics_frame
	game.input_handler._process(0)
	await capture("01_serve_rotary_flat")
	var ui = game.mobile_controls
	var wheel: Vector2 = ui._serve_selector_center
	var radius: float = ui._serve_selector_radius * 0.9
	ui._press(3, wheel + Vector2.RIGHT * radius)
	ui._press(1, ui._charge_center)
	ui._drag(3, wheel + Vector2.from_angle(TAU / 7.0) * radius)
	ui._press(2, ui._stick_center + Vector2(0, -60))
	for frame in range(20):
		game.input_handler._process(1.0 / 60.0)
		await physics_frame
	await capture("02_serve_aim_topspin")
	ui._release(2);ui._release(3);ui._release(1)
	game.input_handler._process(0)
	var swing: = false
	var contact: = false
	for frame in range(120):
		await physics_frame
		var phase: String = game.game_serve.get_serve_timing_state().phase
		if phase == "SWING" and not swing:
			swing = true
			await capture("03_serve_contact_countdown")
		if phase == "CONTACT":
			contact = true
			await capture("04_actual_serve_contact")
			break
	print("MOBILE REAL SERVE CONTACT ", contact)
	var returned: = false
	for frame in range(360):
		await physics_frame
		if game.game_state == 2 and game.ball.last_hit_by == 1:
			returned = true
			break
	print("MOBILE REAL AI RETURN ", returned)
	if returned:
		ui._press(5, ui._charge_center)
		for frame in range(6):
			game.input_handler._process(1.0 / 60.0)
			await physics_frame
		for choice in [["05_rally_topspin", Vector2(-1, -1).normalized()], ["06_rally_slice", Vector2(1, -1).normalized()], ["07_rally_drop", Vector2.DOWN], ["08_rally_flat", Vector2.ZERO]]:
			ui._drag(5, ui._charge_center + choice[1] * ui._charge_radius)
			game.input_handler._process(1.0 / 60.0)
			await capture(choice[0])
	ui.cancel_all()
	var retrieval: = false
	for frame in range(300):
		await physics_frame
		if game.between_point_controller.is_active():
			retrieval = true
			await capture("09_skip_retrieval")
			game.between_point_controller.skip()
			break
	print("MOBILE RETRIEVAL ", retrieval)
	game.hud._toggle_guide()
	await capture("10_mobile_guide")
	game.hud._toggle_guide()
	print("MOBILE FINAL VISUAL DONE")
	quit()
