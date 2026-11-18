extends "res://scripts/tests/cloud_landscape_navigation.gd"
## Optional isolated cleanup. The readability production source stays frozen.
var cleanup_script: GDScript

func make_cleanup_game() -> Node:
	var game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game;await frames()
	check(game.practice_panel.get_script() == cleanup_script, "actual game-created production Practice panel is under test")
	game.practice_launcher.start_drill("DINK")
	game.score_left=4;game.score_right=7
	return game

func attack_button(panel: Node) -> Button:
	for child in panel._content.get_children():
		if child is Button and child.text.begins_with("Allow pop-up attacks:"):return child
	return null

func mouse_now(control: Control) -> void:
	for down in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=root.get_final_transform()*control.get_global_rect().get_center()
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func touch_now(control: Control) -> void:
	for down in [true,false]:
		var event:=InputEventScreenTouch.new()
		event.index=0;event.position=root.get_final_transform()*control.get_global_rect().get_center();event.pressed=down
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func key_now() -> void:
	for down in [true,false]:
		var event:=InputEventKey.new();event.keycode=KEY_SPACE;event.physical_keycode=KEY_SPACE;event.pressed=down
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func inspect_value(game: Node, expected: bool, count: int) -> void:
	check(game.practice_launcher.allow_attacks==expected,"attack value equals final input")
	check(game.practice_panel._picker_open and paused,"picker remains open and paused")
	check(game.practice_panel._content.get_child_count()==count,"one complete set of controls remains")
	var button=attack_button(game.practice_panel)
	check(button!=null and button.text=="Allow pop-up attacks: "+("ON" if expected else "OFF"),"caption reflects final value")
	check(root.gui_get_focus_owner()==game.practice_panel._first_button,"refresh preserves original first-button focus behavior")
	check(game.score_left==4 and game.score_right==7,"toggle preserves match score")
	check(not Input.is_action_pressed("ui_accept"),"toggle leaves no held gameplay accept action")

func run() -> void:
	if not OS.get_user_data_dir().contains("landscape-navigation-"):
		push_error("Use isolated landscape-navigation-* HOME/XDG");quit(2);return
	create_timer(130.0,true).timeout.connect(func():quit(2))
	var controller=root.get_node("PauseController")
	if root.focus_exited.is_connected(controller._on_window_focus_exited):root.focus_exited.disconnect(controller._on_window_focus_exited)
	if root.focus_entered.is_connected(controller._on_window_focus_entered):root.focus_entered.disconnect(controller._on_window_focus_entered)
	root.content_scale_size=Vector2i(720,1280);Input.set_emulate_mouse_from_touch(true)
	cleanup_script=load("res://scripts/ui/practice_panel.gd")
	check(cleanup_script != null,"actual production cleanup source loads")
	var settings=root.get_node("Settings")
	settings._config.set_value("video","focus_dim",0.23)
	check(settings._config.save("user://settings.cfg")==OK,"isolated settings fixture saved")
	var settings_file_before:=FileAccess.get_sha256("user://settings.cfg")
	settings.settings_changed.connect(func(_key,_value):settings_events+=1)
	var game=await make_cleanup_game()
	for size in SIZES:
		root.size=size;await frames()
		game.practice_panel.open_practice();await frames()
		scope="%dx%d/attack-cleanup" % [size.x,size.y]
		var panel=game.practice_panel
		var count:int=panel._content.get_child_count()
		for method in ["mouse","touch","keyboard"]:
			for direction in range(2):
				var before:bool=game.practice_launcher.allow_attacks
				var button=attack_button(panel);await reveal(button)
				var retired:WeakRef=weakref(button)
				if method=="mouse": await click(button)
				elif method=="touch":await touch(button)
				else:button.grab_focus();await key(KEY_SPACE)
				inspect_value(game,not before,count)
				check(retired.get_ref()==null,"dispatched button retires after "+method+" dispatch")
				if capture and size.x>size.y and method=="touch":
					await reveal(attack_button(panel))
					await screenshot("attack-%dx%d-%s" % [size.x,size.y,"on" if game.practice_launcher.allow_attacks else "off"])
		# Multiple complete actual input events before the deferred queue runs.
		for method in ["mouse","touch","keyboard"]:
			for presses in [2,3]:
				var button=attack_button(panel);await reveal(button)
				if method=="keyboard":button.grab_focus()
				var before:bool=game.practice_launcher.allow_attacks
				var generation:int=panel._picker_generation
				for press in range(presses):
					if method=="mouse":mouse_now(button)
					elif method=="touch":touch_now(button)
					else:key_now()
				var expected:bool=not before if presses%2==1 else before
				check(game.practice_launcher.allow_attacks==expected,"rapid "+method+" changes value immediately")
				check(panel._picker_generation==generation,"rapid dispatch has not rebuilt its live button")
				await frames()
				inspect_value(game,expected,count)
				check(panel._picker_generation==generation+2,"rapid "+method+" performs one valid refresh")
		# Native Back after the event, before its deferred refresh, must win.
		var button=attack_button(panel);await reveal(button)
		var before:bool=game.practice_launcher.allow_attacks
		mouse_now(button)
		check(game.practice_launcher.allow_attacks!=before,"close-race retains immediate value")
		root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		check(not panel._picker_open and paused,"native Back closes picker before deferred rebuild")
		await frames()
		check(not panel._picker_open and paused,"deferred refresh cannot reopen closed picker or resume gameplay")
		var closed_value:bool=game.practice_launcher.allow_attacks
		panel._toggle_attacks();await frames()
		check(game.practice_launcher.allow_attacks==closed_value,"stale closed-panel callback cannot change value")
		# Reopening creates a new generation, which an old queued refresh cannot replace.
		panel.open_practice();await frames()
		button=attack_button(panel);await reveal(button)
		touch_now(button)
		panel.close_picker();panel.open_practice()
		var current_first=panel._first_button
		var current_generation:int=panel._picker_generation
		await frames()
		check(panel._first_button==current_first and panel._picker_generation==current_generation,"old queued refresh leaves reopened controls intact")
		inspect_value(game,game.practice_launcher.allow_attacks,count)
		panel.close_picker();controller.close();await frames()
	# Queued deletion must not rebuild orphan controls or call back into gameplay.
	game.practice_panel.open_practice();await frames()
	var final_button=attack_button(game.practice_panel);await reveal(final_button)
	mouse_now(final_button)
	var retired_panel:WeakRef=weakref(game.practice_panel)
	game.practice_panel.queue_free();game.queue_free();await frames()
	check(retired_panel.get_ref()==null,"queued panel deletion leaves no orphan panel")
	check(settings_events==0,"attack UI never writes Settings")
	check(FileAccess.get_sha256("user://settings.cfg")==settings_file_before,"settings file remains byte-identical")
	controller.close();await frames()
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"scope":"Separate optional event-dispatch cleanup on frozen D + readability candidate","checks":checks,"failures":failures,"settings_events":settings_events,"production_applied":false},"\t"))
	for failure in failures:print("FAIL: ",failure)
	print("CLOUD LANDSCAPE ATTACK CLEANUP: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--rate="): Engine.physics_ticks_per_second = int(argument.trim_prefix("--rate="))
	super._initialize()
