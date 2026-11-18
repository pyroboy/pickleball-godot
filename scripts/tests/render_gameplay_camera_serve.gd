extends SceneTree
var game
var output: = "user://camera-serve"
var serving_team: = 0
func _initialize() -> void: call_deferred("run")
func capture(label: String) -> void:
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): output = arg.trim_prefix("--capture-dir=")
		if arg.begins_with("--server="): serving_team = int(arg.trim_prefix("--server="))
	DirAccess.make_dir_recursive_absolute(output)
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	root.size = Vector2i(432, 936); root.content_scale_size = Vector2i(720, 1560)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	root.get_node("Settings").set_value("video.camera_mode", 0)
	game.serving_team = serving_team
	game._reset_ball()
	paused = false
	var contact_seen: = false
	var return_seen: = false
	var receiving_view_correct: = true
	for frame in 210:
		if serving_team == 0 and frame == 25: Input.action_press("ui_accept")
		if serving_team == 0 and frame == 65: Input.action_release("ui_accept")
		await physics_frame
		await capture("frame-%04d" % frame)
		if serving_team == 1 and int(game.game_state) in [0,1,2]:
			receiving_view_correct = receiving_view_correct and game.camera_rig.gameplay_camera.active_kind == "center" and game.main_camera.global_position.z > 0.0
		if game.game_state == game.GameState.PLAYING: contact_seen = true
		if contact_seen and game.camera_rig.gameplay_camera.active_kind == "center" and game.camera_rig.gameplay_camera._transition_elapsed >= 0.65: return_seen = true
	print("CAMERA LIVE CLIP contact=%s centered_return=%s" % [contact_seen, return_seen])
	game.queue_free(); await process_frame
	print("BLUE RECEIVING VIEW: ", receiving_view_correct)
	quit(0 if contact_seen and return_seen and receiving_view_correct else 1)
