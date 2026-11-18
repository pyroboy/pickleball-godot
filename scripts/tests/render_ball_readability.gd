extends SceneTree
const OUT: = "/workspace/shared/ballqa"
var game
func _initialize() -> void : call_deferred("run")
func capture(label: String) -> void :
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(label + ".png"))
func run() -> void :
	var pause = root.get_node("PauseController")
	root.focus_exited.disconnect(pause._on_window_focus_exited)
	root.focus_entered.disconnect(pause._on_window_focus_entered)
	paused = false
	root.size = Vector2i(432, 936);root.content_scale_size = Vector2i(720, 1560)
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	pause.close();paused = false
	for i in range(6): await physics_frame
	game.input_handler.set_process(false);game.process_mode = Node.PROCESS_MODE_DISABLED
	game.player_left.set_physics_process(false);game.player_right.set_physics_process(false)
	game.ball.freeze = true;game.ball.set_physics_process(false)
	game.get_node("Sun").shadow_enabled = false
	game.ball.show();game.ball.position = Vector3(0.8, 0.16, 2.0)
	game.get_node("GroundShadows").update_shadows()
	game.camera_rig.update(0.0)
	await capture("portrait_low_ball_mobile_shadows")
	game.ball.position.y = 2.1
	game.get_node("GroundShadows").update_shadows()
	await capture("portrait_high_ball_mobile_shadows")
	pause.open(); await capture("portrait_paused_net_shadows");pause.close()
	root.size = Vector2i(1180, 780);root.content_scale_size = Vector2i(1280, 800)
	await process_frame;game.hud._layout_desktop();game.camera_rig.update(0.0)
	await capture("desktop_net_and_shadows")
	game.hud.hide();game.mobile_controls.hide()
	game.main_camera.position = Vector3(4.2, 2.5, 5.6);game.main_camera.look_at(Vector3(0, 0.6, 0))
	game.main_camera.fov = 49.0
	game.player_left.hide();game.player_right.hide();game.ball.hide()
	game.get_node("GroundShadows").update_shadows()
	await capture("net_woven_tape_detail")
	var net = game.get_node("Net");net.set_physics_process(false)
	net.add_impact(Vector3(0, 0.5, 0), Vector3(0, 0, 20));net.advance_impacts(0.07)
	await capture("net_local_ripple")
	print("BALL READABILITY VISUAL DONE")
	quit()
