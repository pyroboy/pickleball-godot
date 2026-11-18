extends "res://scripts/tests/cloud_landscape_ui.gd"
## Separate follow-on suite: Pause menu typography/layout, with original callbacks.
var quit_probe := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="):variant=arg.trim_prefix("--variant=")
	capture=OS.get_cmdline_user_args().has("--capture")
	quit_probe=OS.get_cmdline_user_args().has("--quit-probe")
	pause_path="res://tools/cloud_qa/landscape_ui_pause_candidate.gd"
	if variant=="before":pause_path="res://tools/cloud_qa/landscape_ui_pause_before.gd"
	elif variant=="production":pause_path="res://scripts/ui/pause_menu.gd"
	output=OS.get_environment("LANDSCAPE_UI_REPORT")
	call_deferred("run")

func open_menu(controller:Node,game:Node) -> Node:
	controller.open();await frames()
	controller._menu.queue_free();await frames()
	var menu=load(pause_path).new();menu.set_meta("controller",controller);controller._menu=menu;game.add_child(menu);await frames()
	return menu

func touch(control:Control) -> void:
	for pressed in [true,false]:
		var event:=InputEventScreenTouch.new();event.index=0;event.position=root.get_final_transform()*control.get_global_rect().get_center();event.pressed=pressed
		Input.parse_input_event(event);await process_frame
	await frames()

func save_report() -> void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"variant":variant,"scope":"Archived build28 cloud pause-only follow-on; not hardware/Mac/APK acceptance","quit_probe":quit_probe,"checks":checks,"failures":failures,"records":records},"\t"))

func run() -> void:
	if not OS.get_user_data_dir().contains("landscape-ui-"):
		push_error("Use isolated landscape-ui-* HOME/XDG");quit(2);return
	create_timer(120.0,true).timeout.connect(func():quit(2))
	var controller=root.get_node("PauseController")
	if root.focus_exited.is_connected(controller._on_window_focus_exited):root.focus_exited.disconnect(controller._on_window_focus_exited)
	if root.focus_entered.is_connected(controller._on_window_focus_entered):root.focus_entered.disconnect(controller._on_window_focus_entered)
	root.content_scale_size=Vector2i(720,1280)
	Input.set_emulate_mouse_from_touch(true)
	var game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game;await frames(8)
	if quit_probe:
		root.size=Vector2i(960,540);await frames()
		var menu=await open_menu(controller,game)
		var quit_button:Button=null
		for control in menu._content.get_children():
			if control is Button and control.text=="Quit game":quit_button=control
		check(quit_button!=null,"Quit control exists")
		check(paused,"Quit reachable from paused state")
		save_report()
		# A functioning quit handler terminates the isolated process before this returns.
		await click(quit_button)
		check(false,"Quit did not exit");save_report();quit(1);return
	for size in SIZES:
		root.size=size;await frames()
		game.score_left=4;game.score_right=7;game.scoreboard_ui.update_score(4,7)
		var menu=await open_menu(controller,game)
		scope="%dx%d/pause" % [size.x,size.y]
		await inspect_pause(menu,size)
		await screenshot("pause-%dx%d" % [size.x,size.y])
		check(paused and root.gui_get_focus_owner()==menu._resume_button,"pause starts focused on Resume")
		await touch(menu._settings_button)
		check(is_instance_valid(menu._settings_overlay),"touch opens Settings")
		if is_instance_valid(menu._settings_overlay):
			check(paused and not menu._panel.visible,"Settings preserves pause and hides menu")
			var back:Button=menu._settings_overlay._vbox.get_child(0).get_child(1)
			await touch(back)
			check(not is_instance_valid(menu._settings_overlay) and paused and menu._panel.visible,"touch Back returns to paused menu")
			check(root.gui_get_focus_owner()==menu._settings_button,"Back restores Settings focus")
		menu._reset_button.grab_focus();await key(KEY_SPACE)
		check(menu._reset_dialog.visible,"keyboard opens reset confirmation")
		await screenshot("pause-reset-%dx%d" % [size.x,size.y])
		await click(menu._reset_dialog.get_cancel_button())
		check(paused and game.score_left==4 and game.score_right==7,"cancel preserves pause and score")
		await touch(menu._resume_button)
		check(not paused and not is_instance_valid(controller._menu),"touch Resume returns to match")
		check(game.score_left==4 and game.score_right==7,"Resume preserves score")
		menu=await open_menu(controller,game)
		await key(KEY_ESCAPE)
		check(not paused and not is_instance_valid(controller._menu),"Escape resumes match")
		menu=await open_menu(controller,game)
		controller._handle_back_request();await frames()
		check(not paused and not is_instance_valid(controller._menu),"native Back resumes match")
	# Repeat portrait/landscape resizing on one live menu.
	var menu=await open_menu(controller,game)
	for size in [SIZES[0],SIZES[3],SIZES[4],SIZES[1],SIZES[2]]:
		root.size=size;await frames()
		scope="%dx%d/pause-rotated" % [size.x,size.y]
		await inspect_pause(menu,size)
	controller.close();await frames()
	game.queue_free();await frames()
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	save_report()
	for failure in failures:print("FAIL: ",failure)
	print("CLOUD LANDSCAPE PAUSE %s: %d checks, %d failures" % [variant,checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func inspect_pause(menu:Node,size:Vector2i) -> void:
	var panel_rect:Rect2=menu._panel.get_global_rect()
	check(root.get_visible_rect().grow(1.0).encloses(panel_rect),"pause fits viewport")
	records.append({"case":scope,"kind":"panel","physical_rect":rect_list(physical_rect(menu._panel))})
	for control in menu._content.get_children():
		if not control is Control:continue
		var pixels:=physical_rect(control)
		var text_value:String=control.text if control is Label or control is Button else "spacer"
		var font_pixels:float=control.get_theme_font_size("font_size")*pixel_scale(control).y
		records.append({"case":scope,"kind":control.get_class(),"label":text_value,"font_physical":font_pixels,"physical_rect":rect_list(pixels)})
		check(panel_rect.grow(1.0/root.get_final_transform().get_scale().y).encloses(control.get_global_rect()),"content stays inside Pause: "+text_value)
		if control is Button:
			check(pixels.size.x>=43.8 and pixels.size.y>=43.8,"44px target: "+text_value)
			if size.x>size.y:check(font_pixels>=17.5,"readable landscape button: "+text_value)
		elif control is Label and size.x>size.y:
			check(font_pixels>=12.5,"readable landscape label: "+text_value)
