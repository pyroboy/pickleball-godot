extends SceneTree

func _initialize(): call_deferred("run")
func run():
	var output: = "/workspace/shared/pickleball-kitchen/pause-reset"
	DirAccess.make_dir_recursive_absolute(output)
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	game.score_left = 4;game.score_right = 7;game.scoreboard_ui.update_score(4, 7)
	for size in [Vector2i(1080, 2340), Vector2i(600, 960)]:
		root.content_scale_size = size;root.size = size; await process_frame; await process_frame
		pause.open(); await process_frame; await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("pause_%dx%d.png" % [size.x, size.y]))
		pause._menu._reset_button.pressed.emit(); await process_frame; await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("reset_%dx%d.png" % [size.x, size.y]))
		pause._menu._reset_dialog.get_cancel_button().pressed.emit();pause.close(); await process_frame
	game.queue_free(); await process_frame; await process_frame;quit()
