extends SceneTree

var game
const OUT: = "/workspace/shared/mobileqa/final-camera"
func _initialize() -> void : call_deferred("run")
func frames(count: int) -> void :
	for i in range(count): await physics_frame
func capture(label: String) -> void :
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(label + ".png"))
func run() -> void :
	create_timer(45).timeout.connect( func(): quit(2))
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	DirAccess.make_dir_recursive_absolute(OUT)
	paused = false
	root.size = Vector2i(432, 936);root.content_scale_size = Vector2i(720, 1560)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await frames(12)
	await capture("01_current_serve")
	game.camera_rig.portrait_elevation_degrees = 40.0
	game.camera_rig.portrait_max_baseline_view_angle = 42.0
	await frames(6)
	await capture("02_raised_serve")
	var eye: Vector3 = game.main_camera.get_camera_transform().origin
	print("FINAL CAMERA eye=", eye, " baseline_body_ray=", rad_to_deg(atan2(eye.y - 1, eye.z - 6.8)))
	Input.action_press("ui_accept"); await frames(18);Input.action_release("ui_accept")
	for i in range(420):
		await frames(1)
		if game.game_state == 2 and game.ball.last_hit_by == 1: break
	await capture("03_raised_rally")
	print("FINAL CAMERA real AI return=", game.ball.last_hit_by == 1, " state=", game.game_state)
	game._reset_ball();game.ball.global_position = Vector3(0.7, Ball.FLOOR_Y + Ball.BALL_RADIUS, -3.6)
	game.ball.linear_velocity = Vector3.ZERO;game._on_point_scored(0)
	await frames(70); await capture("04_retrieval_angle_a")
	await frames(100); await capture("05_retrieval_angle_b")
	await frames(80); await capture("06_retrieval_restored")
	print("FINAL CAMERA montage ended=", not game.camera_rig.is_between_point_cinematic_active(), " retrieval still active=", game.between_point_controller.is_active())
	game.hud.skip_retrieval_requested.emit(); await frames(3)
	await capture("07_raised_ready_after_skip")
	print("FINAL CAMERA REVIEW DONE")
	game.queue_free(); await process_frame;quit()
