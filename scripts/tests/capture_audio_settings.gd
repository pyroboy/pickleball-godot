extends SceneTree

func _initialize() -> void : call_deferred("run")
func run() -> void :
	if DisplayServer.get_name() == "headless":
		push_error("Audio UI capture requires a rendered display")
		quit(2)
		return
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	var controller: = root.get_node("PauseController")
	controller.open()
	controller._menu._on_settings()
	var settings_panel = controller._menu._settings_overlay
	var tabs: TabContainer = settings_panel._panel.find_children("*", "TabContainer", true, false)[0]
	tabs.current_tab = 2
	for resolution in [Vector2i(720, 1280), Vector2i(1440, 900)]:
		root.content_scale_size = resolution
		root.size = resolution
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path: = "res://docs/audio-review/audio_settings_%dx%d.png" % [resolution.x, resolution.y]
		root.get_texture().get_image().save_png(path)
		print("AUDIO SETTINGS CAPTURE ", path)
	quit()
