extends "res://scripts/tests/cloud_landscape_ui.gd"
## Read-only audit of adjacent menu typography. No production UI changes.
func _initialize() -> void:
	output=OS.get_environment("LANDSCAPE_UI_REPORT")
	call_deferred("run")
func run() -> void:
	if not OS.get_user_data_dir().contains("landscape-ui-"):quit(2);return
	var controller=root.get_node("PauseController")
	if root.focus_exited.is_connected(controller._on_window_focus_exited):root.focus_exited.disconnect(controller._on_window_focus_exited)
	if root.focus_entered.is_connected(controller._on_window_focus_entered):root.focus_entered.disconnect(controller._on_window_focus_entered)
	root.content_scale_size=Vector2i(720,1280)
	var title=load("res://scenes/title.tscn").instantiate();root.add_child(title);current_scene=title;await frames()
	for size in [SIZES[3],SIZES[4]]:
		root.size=size;await frames()
		for control in [title._play,title._settings,title._hint,title._status]:
			records.append({"menu":"title","window_size":point_list(size),"label":control.text,"font_physical":control.get_theme_font_size("font_size")*pixel_scale(control).y,"target_physical":point_list(physical_rect(control).size)})
	title.queue_free();await frames()
	var game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game;await frames(8)
	for size in [SIZES[3],SIZES[4]]:
		root.size=size;await frames()
		game.practice_panel.open_practice();await frames()
		for control in game.practice_panel._content.get_children():
			if control is Label or control is Button:
				records.append({"menu":"practice","window_size":point_list(size),"label":control.text,"font_physical":control.get_theme_font_size("font_size")*pixel_scale(control).y,"target_physical":point_list(physical_rect(control).size)})
		game.practice_panel.close_picker();controller.close();await frames()
	game.queue_free();await frames()
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"scope":"Read-only adjacent menu measurements; no changes made","records":records},"\t"));quit()
