extends SceneTree

var game
const OUT: = "/workspace/shared/mobileqa/camera-player35"
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
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game);current_scene = game
	game.camera_rig.portrait_elevation_degrees = 35.0
	game.camera_rig.portrait_anchor_z = 6.8
	game.camera_rig.portrait_anchor_height = 1.0
	game.camera_rig.portrait_max_baseline_view_angle = 40.0
	for i in range(12): await physics_frame
	await capture("serve_player35")
	var eye: Vector3 = game.main_camera.get_camera_transform().origin
	print("PLAYER CAMERA actual=", eye, " rotation=", game.main_camera.rotation_degrees, " baseline_ray=", rad_to_deg(atan2(eye.y - 1.0, eye.z - 6.8)))
	game.game_serve.perform_serve(0.65)
	var returned: = false
	for i in range(360):
		await physics_frame
		if game.game_state == 2 and game.ball.last_hit_by == 1:
			returned = true
			break
	print("CAMERA42 AI RETURN=", returned, " state=", game.game_state)
	await capture("rally_ready_player35")
	Input.action_press("ui_accept")
	for i in range(8): await physics_frame
	await capture("rally_charge_player35")
	Input.action_release("ui_accept")
	print("CAMERA42 REVIEW DONE")
	quit()
