extends SceneTree
## Actual key events with normal pause/menu/tool handlers; no injected game state.
var game
var rate:=60
var strict:=false
var output:="/tmp/reticle-keyboard.json"
var checks:=0
var failures:Array=[]
var rows:Array=[]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rate="):rate=int(arg.trim_prefix("--rate="))
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=" )
		if arg=="--strict-reticle":strict=true
	Engine.physics_ticks_per_second=rate;Engine.max_fps=rate
	call_deferred("run")

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL: ",label)

func frames(n:int)->void:
	for i in n:await process_frame

func key(down:bool)->void:
	var event:=InputEventKey.new()
	event.keycode=KEY_SPACE;event.physical_keycode=KEY_SPACE;event.pressed=down
	Input.parse_input_event(event)

func run()->void:
	root.size=Vector2i(720,1280);root.content_scale_size=Vector2i(720,1280)
	var pause=root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited):root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered):root.focus_entered.disconnect(pause._on_window_focus_entered)
	for reason in ["pause","guide","settings","practice","pose_tool","reset"]:
		game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game
		await frames(10)
		key(true);await frames(4)
		var before:Dictionary={"held":Input.is_action_pressed("ui_accept"),"visible":game.game_trajectory.landing_cursor.visible,"aim_mode":game.aim_controller.mode,"state":game.game_state}
		check(before.held and before.visible and before.aim_mode=="AIM","real keyboard fixture visibly aiming: "+reason)
		match reason:
			"pause":pause.open()
			"guide":game.hud._guide_button.pressed.emit()
			"settings":pause.open();pause._menu._settings_button.pressed.emit()
			"practice":game.practice_panel.open_practice()
			"pose_tool":game.open_mobile_pose_editor()
			"reset":pause.open();pause._menu._reset_button.pressed.emit();pause._menu._reset_dialog.get_ok_button().pressed.emit()
		var frames_visible:=0
		for i in 5:
			await process_frame
			# The signal resumes before late callbacks; the following deferred read
			# observes the previous completed process frame, not an internal flip.
			if game.game_trajectory.landing_cursor.visible:frames_visible+=1
		var after:Dictionary={"held":Input.is_action_pressed("ui_accept"),"visible":game.game_trajectory.landing_cursor.visible,"aim_mode":game.aim_controller.mode,"paused":paused,"state":game.game_state,"old_cursor_frames":frames_visible}
		rows.append({"reason":reason,"before":before,"after":after})
		if strict:check(not after.visible,"keyboard cursor cleared through "+reason)
		key(false)
		if reason=="pose_tool" and is_instance_valid(game.mobile_pose_editor):game.mobile_pose_editor.close();await frames(2)
		if reason=="practice":game.practice_panel.close_picker()
		if reason=="guide" and game.hud._guide.visible:game.hud._guide_button.pressed.emit()
		pause.close()
		game.queue_free();await frames(4)
	var report:Dictionary={"scope":"frozen-D actual keyboard/menu boundary test","rate":rate,"strict":strict,"checks":checks,"failures":failures,"cases":rows}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	print("RETICLE KEYBOARD ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
