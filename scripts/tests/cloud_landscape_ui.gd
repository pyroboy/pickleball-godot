extends SceneTree
## Readability and reset-confirmation QA using actual authored canvas transforms.
const SIZES := [Vector2i(390,844), Vector2i(430,932), Vector2i(540,960), Vector2i(960,540), Vector2i(1178,814)]
const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
var checks := 0
var failures: Array[String] = []
var records: Array = []
var scope := ""
var variant := "candidate"
var capture := false
var settings_path := "res://tools/cloud_qa/landscape_ui_candidate_settings_panel.gd"
var pause_path := "res://tools/cloud_qa/landscape_ui_candidate_pause_menu.gd"
var output := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=")
	capture = OS.get_cmdline_user_args().has("--capture")
	if variant == "before":
		settings_path = "res://tools/cloud_qa/landscape_ui_before_settings_panel.gd"
		pause_path = "res://tools/cloud_qa/landscape_ui_before_pause_menu.gd"
	elif variant == "production":
		settings_path = "res://scripts/ui/settings_panel.gd"
		pause_path = "res://scripts/ui/pause_menu.gd"
	output = OS.get_environment("LANDSCAPE_UI_REPORT")
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(scope + ": " + message)

func frames(count := 5) -> void:
	for i in count: await process_frame

func point_list(v: Vector2) -> Array:
	return [v.x,v.y]

func rect_list(r: Rect2) -> Array:
	return [r.position.x,r.position.y,r.size.x,r.size.y]

func pixel_scale(control: Control) -> Vector2:
	# Embedded subwindows have their own identity final transform, then receive
	# the root window's canvas stretch when composited. Include both transforms.
	var scale: Vector2 = control.get_global_transform_with_canvas().get_scale()
	var viewport: Viewport = control.get_viewport()
	scale *= viewport.get_final_transform().get_scale()
	if viewport is Window and viewport != root and viewport.is_embedded():
		scale *= root.get_final_transform().get_scale()
	return scale

func physical_rect(control: Control) -> Rect2:
	var logical: Rect2 = control.get_global_rect()
	if control.get_viewport() != root and control.get_viewport() is Window:
		logical.position += Vector2(control.get_viewport().position)
	return Rect2(logical.position * root.get_final_transform().get_scale(), control.size * pixel_scale(control))

func inspect_control(control: Control, interactive := false) -> void:
	var scale := pixel_scale(control)
	var physical_font := control.get_theme_font_size("font_size") * scale.y
	var rect := physical_rect(control)
	var label := str(control.name)
	if control is Label or control is Button: label = control.text.left(60)
	records.append({"case":scope,"kind":"control","name":control.name,"label":label,"font_logical":control.get_theme_font_size("font_size"),"font_physical":physical_font,"physical_rect":rect_list(rect),"pixel_scale":point_list(scale)})
	if interactive: check(rect.size.x >= 43.8 and rect.size.y >= 43.8,"44px target: " + label + " " + str(rect.size))
	if root.size.x > root.size.y:
		var minimum := 13.5 if control.name == "SettingsFootnote" else 15.5
		if control is Label or control is Button or control is TabBar:
			check(physical_font >= minimum,"readable landscape font: " + label + " " + str(physical_font))

func key(code: Key, viewport: Viewport = root) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
		Input.parse_input_event(event) if viewport != root else viewport.push_input(event,true);await process_frame
	await frames()

func click(control: Control) -> void:
	var viewport := root
	var point := control.get_global_rect().get_center()
	if control.get_viewport()!=root:point+=Vector2(control.get_viewport().position)
	var move := InputEventMouseMotion.new();move.position=point;move.global_position=point
	viewport.push_input(move,true);await process_frame
	for pressed in [true,false]:
		var event := InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;event.global_position=point
		viewport.push_input(event,true);await process_frame
	await frames()

func screenshot(name: String) -> void:
	if not capture:return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.get_base_dir().path_join(name+".png"))==OK,"saved native capture")

func run() -> void:
	if not OS.get_user_data_dir().contains("landscape-ui-"):
		push_error("Use isolated landscape-ui-* HOME/XDG");quit(2);return
	create_timer(120.0,true).timeout.connect(func():quit(2))
	var controller=root.get_node("PauseController")
	if root.focus_exited.is_connected(controller._on_window_focus_exited):root.focus_exited.disconnect(controller._on_window_focus_exited)
	if root.focus_entered.is_connected(controller._on_window_focus_entered):root.focus_entered.disconnect(controller._on_window_focus_entered)
	controller.set_process_unhandled_input(false)
	root.content_scale_size=Vector2i(720,1280)
	for size in SIZES:
		root.size=size;await frames()
		paused=true
		var panel=load(settings_path).new();root.add_child(panel);await frames()
		await inspect_settings(panel,size)
		await key(KEY_ESCAPE)
		check(not is_instance_valid(panel),"Escape closes settings")
		if is_instance_valid(panel):panel.queue_free();await frames()
	paused=false
	var game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game;await frames(8)
	for size in SIZES:
		root.size=size;await frames()
		game.score_left=4;game.score_right=7;game.scoreboard_ui.update_score(4,7)
		controller.open();await frames()
		controller._menu.queue_free();await frames()
		var menu=load(pause_path).new();menu.set_meta("controller",controller);controller._menu=menu;game.add_child(menu);await frames()
		scope="%dx%d/reset" % [size.x,size.y]
		menu._on_reset_requested();await frames(8)
		var dialog:ConfirmationDialog=menu._reset_dialog
		check(dialog.visible,"confirmation opens")
		inspect_control(dialog.get_label())
		inspect_control(dialog.get_ok_button(),true)
		inspect_control(dialog.get_cancel_button(),true)
		var decoration_rect:=Rect2(Vector2(dialog.get_position_with_decorations()),Vector2(dialog.get_size_with_decorations()))
		check(root.get_visible_rect().encloses(decoration_rect),"decorated dialog fits safe viewport")
		check(dialog.get_theme_stylebox("panel") is StyleBoxFlat,"dialog panel is flat")
		check(dialog.get_theme_stylebox("panel").bg_color.is_equal_approx(UiTheme.PANEL),"dialog panel matches game theme")
		check(dialog.get_theme_stylebox("embedded_border").bg_color.is_equal_approx(UiTheme.PANEL),"dialog frame matches game theme")
		records.append({"case":scope,"kind":"dialog","logical_size":point_list(dialog.size),"physical_decorated_rect":rect_list(Rect2(decoration_rect.position*root.get_final_transform().get_scale(),decoration_rect.size*root.get_final_transform().get_scale())),"title_font_physical":dialog.get_theme_font_size("title_font_size")*root.get_final_transform().get_scale().y,"panel_color":str(dialog.get_theme_stylebox("panel").bg_color)})
		var close_size:=dialog.get_theme_icon("close").get_size()*root.get_final_transform().get_scale()
		check(close_size.x>=43.8 and close_size.y>=43.8,"title close target is 44px")
		records.append({"case":scope,"kind":"close_target","physical_size":point_list(close_size)})
		await screenshot("reset-%dx%d" % [size.x,size.y])
		if size == SIZES[0]:
			for rotated in [SIZES[3],SIZES[1],SIZES[4],SIZES[2],SIZES[0]]:
				root.size=rotated;await frames(8)
				var rotated_rect:=Rect2(Vector2(dialog.get_position_with_decorations()),Vector2(dialog.get_size_with_decorations()))
				check(root.get_visible_rect().grow(1.0).encloses(rotated_rect),"open reset remains within safe viewport after "+str(rotated))
				check(physical_rect(dialog.get_cancel_button()).size.y>=43.8,"open reset keeps44px cancel after "+str(rotated))
				check(dialog.get_label().get_theme_font_size("font_size")*pixel_scale(dialog.get_label()).y>=17.5,"open reset readable after "+str(rotated))
				check(dialog.visible and paused and game.score_left==4 and game.score_right==7,"rotation neither resets nor unpauses")
		check(dialog.gui_get_focus_owner()==dialog.get_cancel_button(),"Keep playing receives initial focus")
		await click(dialog.get_cancel_button())
		check(not dialog.visible and paused,"Keep playing returns to paused menu")
		check(game.score_left==4 and game.score_right==7,"cancel preserves score")
		check(root.gui_get_focus_owner()==menu._reset_button,"cancel restores Reset focus")
		menu._on_reset_requested();await frames()
		controller._handle_back_request();await frames()
		check(not dialog.visible and paused,"native Back dismisses reset only")
		check(game.score_left==4 and game.score_right==7,"Back preserves score")
		menu._on_reset_requested();await frames()
		await key(KEY_ESCAPE,dialog)
		check(not dialog.visible and paused,"Escape dismisses reset only")
		check(game.score_left==4 and game.score_right==7,"Escape preserves score")
		menu._on_reset_requested();await frames()
		await key(KEY_SPACE,dialog)
		check(is_instance_valid(dialog) and not dialog.visible and paused and game.score_left==4 and game.score_right==7,"initial keyboard activation safely keeps playing")
		if not is_instance_valid(menu):
			# The baseline focuses Reset by default. Recover after recording its
			# destructive Space outcome so every other case still runs.
			game.score_left=4;game.score_right=7;game.scoreboard_ui.update_score(4,7)
			controller.open();await frames()
			controller._menu.queue_free();await frames()
			menu=load(pause_path).new();menu.set_meta("controller",controller);controller._menu=menu;game.add_child(menu);await frames()
			dialog=menu._reset_dialog


		menu._on_reset_requested();await frames()
		var close_origin:=Vector2(dialog.position)+Vector2(dialog.size.x-dialog.get_theme_constant("close_h_offset"),-dialog.get_theme_constant("close_v_offset"))
		for pressed in [true,false]:
			var close_event:=InputEventMouseButton.new();close_event.pressed=pressed;close_event.button_index=MOUSE_BUTTON_LEFT;close_event.position=close_origin+Vector2(2,2);close_event.global_position=close_event.position
			root.push_input(close_event,true);await process_frame
		await frames()
		check(not dialog.visible and paused,"title close corner cancels without resuming")
		check(game.score_left==4 and game.score_right==7,"title close preserves score")
		menu._on_reset_requested();await frames()
		await click(dialog.get_ok_button())
		check(not paused and not is_instance_valid(controller._menu),"Reset returns to game")
		check(game.score_left==0 and game.score_right==0,"Reset starts score at 0-0")
		check(not game.ball.is_in_play,"Reset waits for fresh serve")
		controller.close();await frames()
	game.queue_free();await frames()
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	var data={"scope":"Archived build28 cloud source only; not Mac build30, APK or physical phone acceptance","variant":variant,"checks":checks,"failures":failures,"records":records}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
	for failure in failures:print("FAIL: ",failure)
	print("CLOUD LANDSCAPE UI %s: %d checks, %d failures" % [variant,checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func inspect_settings(panel:Node,size:Vector2i) -> void:
	scope="%dx%d/settings" % [size.x,size.y]
	check(root.get_visible_rect().encloses(panel._panel.get_global_rect()),"settings panel fits viewport")
	records.append({"case":scope,"kind":"panel","physical_rect":rect_list(physical_rect(panel._panel)),"canvas_size":point_list(root.get_visible_rect().size)})
	var tabs:TabContainer=panel._vbox.get_child(1)
	var back:Button=panel._vbox.get_child(0).get_child(1)
	inspect_control(back,true)
	inspect_control(panel._vbox.get_child(0).get_child(0))
	inspect_control(panel.find_child("SettingsFootnote",true,false))
	inspect_control(tabs.get_tab_bar())
	for tab_index in tabs.get_tab_count():
		var tab_rect:Rect2=tabs.get_tab_bar().get_tab_rect(tab_index)
		var target_size:=tab_rect.size*pixel_scale(tabs.get_tab_bar())
		check(target_size.x>=43.8 and target_size.y>=43.8,"tab has44px target: "+tabs.get_tab_title(tab_index))

	check(root.gui_get_focus_owner()==back,"Back receives initial focus")
	for index in tabs.get_tab_count():
		tabs.current_tab=index;await frames()
		var scroll:ScrollContainer=tabs.get_tab_control(index)
		scope="%dx%d/settings/%s" % [size.x,size.y,scroll.name]
		check(scroll.follow_focus,"scroll follows keyboard focus")
		check(scroll.get_h_scroll_bar().max_value<=scroll.get_h_scroll_bar().page+0.5,"no horizontal overflow")
		check(physical_rect(scroll).size.y>=100,"scroll viewport keeps usable height")
		for control in scroll.find_children("*","Control",true,false):
			if control is Label or control is Button or control is HSlider:
				inspect_control(control,control is Button or control is HSlider)
			if control is OptionButton:
				var popup:PopupMenu=control.get_popup()
				var popup_font:=popup.get_theme_font_size("font_size")*root.get_final_transform().get_scale().y
				records.append({"case":scope,"kind":"option_popup","name":control.name,"font_physical":popup_font})
				if size.x>size.y:check(popup_font>=15.5,"readable popup font: "+str(control.name)+" "+str(popup_font))
			if control is HSlider:check(not control.scrollable,"wheel over slider never changes value")
			if control is Button or control is HSlider:
				control.grab_focus();await frames(5)
				check(scroll.get_global_rect().grow(1.0 / root.get_final_transform().get_scale().y).encloses(control.get_global_rect()),"focused control reachable: "+str(control.name)+" control="+str(control.get_global_rect())+" scroll="+str(scroll.get_global_rect()))
		scroll.scroll_vertical=0;await frames()
		await screenshot("settings-%dx%d-%s" % [size.x,size.y,scroll.name])
		if index == 0:
			for option_name in ["video_camera_mode", "video_focus_arc_style"]:
				var option:OptionButton=panel.find_child(option_name,true,false)
				scroll.ensure_control_visible(option);await frames()
				await click(option)
				var popup:=option.get_popup()
				check(popup.visible,"option opens by pointer: "+option_name)
				var font_size:=popup.get_theme_font_size("font_size")
				var item_height:float=(popup.get_theme_font("font").get_height(font_size)+popup.get_theme_constant("v_separation"))*root.get_final_transform().get_scale().y
				if size.x>size.y:check(item_height>=43.8,"landscape popup rows have 44px targets: "+option_name)
				records.append({"case":scope,"kind":"popup_open","name":option_name,"physical_size":point_list(Vector2(popup.size)*root.get_final_transform().get_scale()),"item_height_physical":item_height})
				await screenshot("options-%dx%d-%s" % [size.x,size.y,option_name])
				await key(KEY_ESCAPE,popup)
				check(not popup.visible and is_instance_valid(panel),"Escape closes option only: "+option_name)

