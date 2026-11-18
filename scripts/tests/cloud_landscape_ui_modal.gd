extends "res://scripts/tests/cloud_landscape_ui.gd"
## Reset modal exclusion / single Back dismissal, plus long-text wrap bounds.
var completed := false

func _initialize() -> void:
	capture=OS.get_cmdline_user_args().has("--capture")
	output=OS.get_environment("LANDSCAPE_UI_REPORT")
	call_deferred("run")

func save_report() -> void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"scope":"Final Reset modal and landscape description QA; archived build28 cloud source","variant":"production","completed":completed,"checks":checks,"failures":failures,"records":records},"\t"))

func run() -> void:
	if not OS.get_user_data_dir().contains("landscape-ui-"):quit(2);return
	create_timer(120.0,true).timeout.connect(func():quit(2))
	var controller=root.get_node("PauseController")
	if root.focus_exited.is_connected(controller._on_window_focus_exited):root.focus_exited.disconnect(controller._on_window_focus_exited)
	if root.focus_entered.is_connected(controller._on_window_focus_entered):root.focus_entered.disconnect(controller._on_window_focus_entered)
	# Leave the real PauseController Escape listener enabled to catch bubbling.
	root.content_scale_size=Vector2i(720,1280)
	var game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game;await frames(8)
	for size in SIZES:
		root.size=size;await frames()
		game.score_left=4;game.score_right=7;game.scoreboard_ui.update_score(4,7)
		controller.open();await frames()
		var menu=controller._menu
		var underlying_events:Array=[]
		menu._resume_button.pressed.connect(func():underlying_events.append("resume"))
		var quit_button:Button=null
		for child in menu._content.get_children():
			if child is Button and child.text=="Quit game":quit_button=child
		quit_button.pressed.connect(func():underlying_events.append("quit"))
		menu._on_reset_requested();await frames()
		var dialog:ConfirmationDialog=menu._reset_dialog
		scope="%dx%d/modal" % [size.x,size.y]
		check(dialog.get_cancel_button().text=="Cancel","cancel label describes dismissal")
		check(dialog.exclusive,"Reset is exclusive/modal")
		menu._on_reset_requested();await frames()
		check(menu._reset_dialog==dialog and dialog.visible,"repeated Reset request keeps one dialog")
		await screenshot("reset-final-%dx%d" % [size.x,size.y])
		# Save an incomplete checkpoint first: accidental underlying Quit must not
		# masquerade as success just because the process exits with code0.
		save_report()
		await click(menu._resume_button)
		check(underlying_events.is_empty() and paused and is_instance_valid(menu) and dialog.visible,"modal blocks underlying Resume")
		await click(quit_button)
		check(underlying_events.is_empty() and paused and dialog.visible,"modal blocks underlying Quit")
		check(game.score_left==4 and game.score_right==7,"blocked clicks preserve score")
		await click(dialog.get_cancel_button())
		check(not dialog.visible and paused and is_instance_valid(menu),"Cancel dismisses exactly one layer")
		check(game.score_left==4 and game.score_right==7 and menu._panel.visible,"Cancel preserves score and Pause")
		menu._on_reset_requested();await frames()
		await key(KEY_ESCAPE,dialog)
		check(not dialog.visible and paused and is_instance_valid(controller._menu),"Escape dismisses Reset once; no Pause bubbling")
		check(game.score_left==4 and game.score_right==7,"Escape preserves score")
		menu._on_reset_requested();await frames()
		# An Android/native Back notification follows the actual controller path.
		controller._last_back_msec=-1000
		controller.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST);await frames()
		check(not dialog.visible and paused and is_instance_valid(controller._menu),"native Back dismisses Reset once")
		check(game.score_left==4 and game.score_right==7,"native Back preserves score")
		menu._on_reset_requested();await frames()
		await click(dialog.get_ok_button())
		check(not paused and not is_instance_valid(menu) and not is_instance_valid(dialog),"confirmed Reset removes Pause and dialog")
		check(game.score_left==0 and game.score_right==0,"confirmed Reset resets scores")
		var overlay_count:=0
		for node in root.find_children("*","CanvasLayer",true,false):
			if node.get_script()!=null and node.get_script().resource_path in ["res://scripts/ui/pause_menu.gd","res://scripts/ui/settings_panel.gd"]:overlay_count+=1
		check(overlay_count==0,"confirmed Reset leaves no stacked dim overlays")
		var exclusive_windows:=0
		for node in root.find_children("*","Window",true,false):
			if node.visible and node.exclusive:exclusive_windows+=1
		check(exclusive_windows==0,"confirmed Reset leaves no visible modal Window")
		records.append({"case":scope,"underlying_signals":underlying_events,"remaining_overlays":overlay_count,"remaining_modal_windows":exclusive_windows})
	for size in [SIZES[3],SIZES[4]]:
		root.size=size;await frames();controller.open();await frames()
		var menu=controller._menu;menu._on_settings();await frames()
		var panel=menu._settings_overlay
		var tabs:TabContainer=panel._vbox.get_child(1)
		for tab_index in tabs.get_tab_count():
			tabs.current_tab=tab_index;await frames()
			var scroll:ScrollContainer=tabs.get_tab_control(tab_index)
			scope="%dx%d/wrapped-%s" % [size.x,size.y,scroll.name]
			for label in scroll.find_children("*","Label",true,false):
				if label.text.length()<160:continue
				var bar:VScrollBar=scroll.get_v_scroll_bar()
				var content_right:=scroll.get_global_rect().end.x-(bar.size.x if bar.visible else 0.0)
				check(label.autowrap_mode==TextServer.AUTOWRAP_WORD_SMART,"long description uses word wrapping")
				check(label.get_global_rect().end.x<=content_right+1.0/root.get_final_transform().get_scale().x,"long description clears scrollbar")
				check(label.get_line_count()>1,"long description wraps to multiple lines")
				check(label.get_visible_line_count()==label.get_line_count(),"allocated label shows every wrapped line")
				check(label.visible_characters==-1 and label.lines_skipped==0,"no truncated characters or skipped lines")
				scroll.ensure_control_visible(label);await frames()
				records.append({"case":scope,"text_start":label.text.left(60),"characters":label.text.length(),"lines":label.get_line_count(),"visible_lines":label.get_visible_line_count(),"label_right":label.get_global_rect().end.x,"scrollbar_left":content_right})
			if tab_index==0:
				scroll.scroll_vertical=0;await frames();await screenshot("description-%dx%d" % [size.x,size.y])
		panel._on_close();await frames();controller.close();await frames()
	game.queue_free();await frames();await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	completed=true;save_report()
	for failure in failures:print("FAIL: ",failure)
	print("CLOUD LANDSCAPE MODAL: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
