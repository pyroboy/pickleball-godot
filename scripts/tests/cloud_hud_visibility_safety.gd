extends SceneTree
## Cloud build28 candidate only. Exercises real display methods and projection.
const Display = preload("res://scripts/ui/stamina_display.gd")
const Layout = preload("res://scripts/ui/mobile_layout.gd")
const Fixture = preload("res://scripts/tests/fixtures/charged_footwork_fixture.gd")
const WARNING_COLOR := Color(1.0, 0.68, 0.2)
var game
var display
var rate := 60
var output := "/tmp/cloud_hud_visibility_safety.json"
var checks := 0
var failures: Array[String] = []
var records: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rate="): rate = int(arg.trim_prefix("--rate="))
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	Engine.physics_ticks_per_second = rate
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func record(name: String, data: Dictionary) -> void:
	data["scenario"] = name
	records.append(data)
	print("HUD VISIBILITY ", JSON.stringify(data))

func freeze(node: Node) -> void:
	node.set_process(false); node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func tick(count := 1) -> void:
	for frame in count: display._process(1.0 / rate)

func remote_ball() -> void:
	game.ball.global_position = game.camera_rig.camera.project_position(Vector2(-500,-500),10)

func ball_at(point: Vector2) -> void:
	game.ball.global_position = game.camera_rig.camera.project_position(point,10)

func prepare() -> void:
	paused = false
	game.hud._guide.hide()
	game.mobile_controls.cancel_all()
	game.input_handler.cancel_charge_input()
	game.between_point_controller.cancel()
	game.game_state = game.GameState.PLAYING
	game.match_over = false
	game.hud.set_gameplay_elements_visible(true)
	game.hud.set_between_point_active(false)
	game.mobile_controls._layout()
	game.mobile_controls.enabled = false
	game.ball.freeze = true
	game.ball.is_in_play = true
	game.player_left.stamina.value = 100.0
	game.player_right.stamina.value = 100.0
	remote_ball()
	tick(rate)

func run() -> void:
	root.content_scale_size = Vector2i(720,1280); root.size = Vector2i(720,1280)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game); current_scene = game
	for frame in 12: await process_frame
	Fixture.configure(game)
	freeze(game)
	for child in game.get_children():
		if child.get_script() == Display: display = child
	check(display != null, "production display available")
	if display == null: quit(1); return
	for size in [Vector2i(720,1280),Vector2i(1280,720),Vector2i(390,844),Vector2i(288,512),Vector2i(1920,1080)]:
		root.content_scale_size = size; root.size = size
		await process_frame; await process_frame
		game.hud._layout_desktop()
		prepare()
		transients(str(size))
		for mode in [0,1,2]:
			game.camera_rig.gameplay_camera.mode = mode
			prepare()
			ball_clearance("%s_mode%d" % [size,mode])
		controls_clearance(str(size), false)
		controls_clearance(str(size), true)
		warnings(str(size))
		context_resets(str(size))
	await pointer_repetition()
	var report := {"scope":"Archived build28 cloud candidate only, not Mac build30/31, raster or physical-device acceptance", "rate":rate,"checks":checks,"failures":failures,"records":records}
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for failure in failures: push_error(failure)
	print("CLOUD HUD VISIBILITY SAFETY %d Hz: %d checks, %d failures" % [rate,checks,failures.size()])
	paused = false; current_scene = null; game.queue_free()
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	quit(0 if failures.is_empty() else 1)

func transients(tag: String) -> void:
	var ui = game.scoreboard_ui
	var hud = game.hud
	var stale := 0
	for direct in [false,true]:
		for delta in [0.0,1.0/rate,0.55,8.0]:
			for cycle in 4:
				ui.show_speed(21.3); ui.show_shot_type("DROP")
				ui.show_fault("FAULT","fixture"); ui.show_zone("ZONE"); ui.show_out()
				ui.show_rally_result(0,false)
				if direct: ui._hide_temporary_ui()
				else: ui.hide_all_hud()
				check(ui._shot_type_timer == 0 and ui._speed_visible_timer == 0 and ui._fault_visible_timer == 0 and ui._zone_visible_timer == 0 and ui._rally_visible_timer == 0,"all dismissed timers reset " + tag)
				ui._process(delta); ui.show_all_hud(); ui._process(delta)
				if hud.shot_type.modulate.a > 0 or hud.speed.modulate.a > 0: stale += 1
				check(hud.shot_type.modulate.a == 0 and hud.speed.modulate.a == 0,"dismissed feedback resurrects " + tag)
				check(not hud.fault.visible and not hud.out_text.visible and not hud.zone.visible and not hud._rally_banner.visible,"dismissed banner resurrects " + tag)
	ui.show_shot_type("DROP"); ui.show_shot_type("VOLLEY")
	ui.show_speed(12.3); ui.show_speed(18.7)
	check(hud.shot_type.text=="VOLLEY" and hud.speed.text=="18.7 mph" and hud.shot_type.modulate.a==1 and hud.speed.modulate.a==1,"new repeated event replaces old feedback " + tag)
	var previous_shot := 1.0; var previous_speed := 1.0
	for frame in rate*4:
		ui._update_shot_type_fade(1.0/rate); ui._update_timers(1.0/rate)
		check(hud.shot_type.modulate.a <= previous_shot + 0.000001 and hud.speed.modulate.a <= previous_speed + 0.000001,"natural fades remain monotone " + tag)
		previous_shot= hud.shot_type.modulate.a; previous_speed= hud.speed.modulate.a
	check(previous_shot==0 and previous_speed==0,"natural feedback expiry " + tag)
	record("transients_"+tag,{"stale_reentries":stale,"hide_cancel_cycles":32})

func recover(tag: String) -> int:
	var frame_count := 0
	while not display.bars[0].visible and frame_count <= rate:
		tick(); frame_count += 1
	check(display.bars[0].visible,"bounded clear recovery " + tag)
	check(frame_count == ceili(0.10 * rate),"clearance waits exactly100ms within frame precision " + tag + " frames=" + str(frame_count))
	return frame_count

func ball_clearance(tag: String) -> void:
	var bar: ProgressBar = display.bars[0]
	var s := Layout.scale_for(root.get_visible_rect().size)
	var rect := Rect2(bar.position,bar.size)
	check(bar.visible,"clear fixture starts visible " + tag)
	check(bar.mouse_filter == Control.MOUSE_FILTER_IGNORE,"stamina remains noninteractive " + tag)
	var edge := Vector2(rect.end.x+20*s,rect.get_center().y)
	var previous := bar.visible; var toggles := 0; var obstructive := 0
	for frame in 2*rate:
		ball_at(edge + Vector2(0.25*cos(float(frame)/rate*TAU*4.0),0)); tick()
		if frame > 0 and bar.visible != previous: toggles += 1
		previous = bar.visible
		var point: Vector2 = game.camera_rig.camera.unproject_position(game.ball.global_position)
		if rect.grow(20*s).has_point(point) and bar.visible: obstructive += 1
	check(toggles<=1 and obstructive==0,"ball boundary hides immediately without chatter " + tag)
	# The exit margin must be wider than the entry margin, indefinitely.
	ball_at(edge+Vector2(2*s,0)); tick(rate)
	check(not bar.visible,"hysteresis band cannot re-show an occluded bar " + tag)
	remote_ball()
	for delta in [0.0,-1.0,0.0]: display._process(delta)
	check(not bar.visible,"nonpositive delta must not satisfy reentry " + tag)
	var recovery := recover(tag)
	# Check entry from every edge and corner; no delayed hiding is allowed.
	for relative in [Vector2(-19*s,5*s),Vector2(44*s,-19*s),Vector2(107*s,5*s),Vector2(44*s,29*s),Vector2(-19*s,-19*s),Vector2(107*s,29*s)]:
		ball_at(rect.position+relative); tick()
		check(not bar.visible,"edge/corner immediately hides " + tag)
		remote_ball(); recover(tag+" edge")
	# A brief clear sample followed by an obstruction restarts the full hold.
	ball_at(rect.get_center()); tick(); remote_ball(); tick()
	ball_at(rect.get_center()); tick(); remote_ball()
	var restarted := recover(tag+" restarted")
	# Hidden display still reads exact current stamina without touching its source.
	ball_at(rect.get_center()); game.player_left.stamina.value=17.25; tick()
	check(not bar.visible and bar.value==17.25 and game.player_left.stamina.value==17.25,"hidden stamina updates without source mutation " + tag)
	remote_ball(); recover(tag+" hidden value")
	var camera: Camera3D = game.camera_rig.camera
	var original := camera.global_transform
	var camera_toggles := 0; previous = bar.visible
	for frame in rate:
		camera.global_transform = original
		camera.position.x += sin(float(frame)/rate*TAU)*0.02
		tick()
		if bar.visible!=previous: camera_toggles+=1
		previous=bar.visible
	check(camera_toggles==0,"smooth remote-ball camera remains stable " + tag)
	camera.global_transform = original
	record("ball_clearance_"+tag,{"boundary_toggles":toggles,"obstructive_frames":obstructive,"recovery_frames":recovery,"recovery_seconds":float(recovery)/rate,"reset_recovery_frames":restarted,"smooth_camera_toggles":camera_toggles})

func controls_clearance(tag: String, caption: bool) -> void:
	prepare()
	game.camera_rig.gameplay_camera.mode=2
	tick(rate)
	var controls = game.mobile_controls
	var bar: ProgressBar=display.bars[0]
	var s := Layout.scale_for(root.get_visible_rect().size)
	var rect := Rect2(bar.position,bar.size)
	controls.enabled=true
	controls._charge_radius=10*s
	controls._charge_center=Vector2(-500,-500)
	controls._timing_caption_rect=Rect2(-500,-500,10,10)
	tick(rate)
	var previous := bar.visible; var toggles := 0; var obstructive := 0
	for frame in 2*rate:
		var offset := 0.25*cos(float(frame)/rate*TAU*4.0)
		if caption:
			controls._timing_caption_rect=Rect2(Vector2(rect.end.x+6*s+offset,rect.position.y),Vector2(20,10)*s)
		else:
			controls._charge_center=Vector2(rect.end.x+6*s+controls._charge_radius*1.25+offset,rect.get_center().y)
		tick()
		if frame>0 and bar.visible!=previous: toggles+=1
		previous=bar.visible
		var radius: float=controls._charge_radius*1.25
		var obstacle: Rect2=controls._timing_caption_rect if caption else Rect2(controls._charge_center-Vector2.ONE*radius,Vector2.ONE*radius*2)
		if rect.grow(6*s).intersects(obstacle) and bar.visible: obstructive+=1
	check(toggles<=1 and obstructive==0,"control/caption boundary hides safely " + tag)
	controls._charge_center=Vector2(-500,-500); controls._timing_caption_rect=Rect2(-500,-500,10,10)
	var recovered := recover(tag+" controls")
	controls._charge_center=rect.get_center(); tick()
	check(not bar.visible,"direct control overlap suppresses immediately " + tag)
	controls.enabled=false
	recover(tag+" disabled controls")
	controls._layout()
	record("controls_clearance_"+tag+"_caption" if caption else "controls_clearance_"+tag+"_hit",{"toggles":toggles,"obstructive_frames":obstructive,"recovery_frames":recovered})

func warnings(tag: String) -> void:
	prepare()
	var state=game.player_left.stamina
	state.value=25.0; state.recovery_delay=0.0
	var previous:= Color.WHITE; var changes:=0; var minimum:=INF; var maximum:=-INF
	for frame in 2*rate:
		state.advance(1.0/rate,1.75+0.01*cos((float(frame)+0.5)/rate*TAU*4.0),true,false)
		var exact:float=state.value
		tick()
		var color:Color=display.fills[0].bg_color
		if frame>0 and color!=previous: changes+=1
		previous=color; minimum=minf(minimum,exact); maximum=maxf(maximum,exact)
		check(state.value==exact,"display cannot mutate actual stamina " + tag)
		if exact<25.0: check(color==WARNING_COLOR,"low stamina warning enters immediately " + tag)
	check(changes<=1,"warning boundary does not chatter " + tag)
	for value in [0.0,24.999,25.0,26.0,26.999]:
		state.value=value; tick()
		check(display.fills[0].bg_color==WARNING_COLOR and state.value==value,"warning remains conservative below27 " + tag)
	state.value=27.0; tick()
	check(display.fills[0].bg_color!=WARNING_COLOR,"comfortable recovery clears warning " + tag)
	state.value=25.5; tick()
	check(display.fills[0].bg_color!=WARNING_COLOR,"normal value never entered warning band " + tag)
	state.value=24.999; game.player_right.stamina.value=80; tick()
	check(display.fills[0].bg_color==WARNING_COLOR and display.fills[1].bg_color!=WARNING_COLOR,"independent player warning " + tag)
	state.value=80; game.player_right.stamina.value=24.99; tick()
	check(display.fills[0].bg_color!=WARNING_COLOR and display.fills[1].bg_color==WARNING_COLOR,"opposite player warning independent " + tag)
	record("warning_"+tag,{"changes":changes,"actual_stamina_range":[minimum,maximum],"entry":25,"exit":27})

func context_resets(tag: String) -> void:
	prepare()
	var bar:ProgressBar=display.bars[0]
	var tool:=Control.new(); game.add_child(tool); game.mobile_pose_editor=tool
	tick(); check(not bar.visible,"tool hide immediate " + tag)
	game.mobile_pose_editor=null; tool.queue_free(); recover(tag+" tool")
	var rig=game.camera_rig
	game.camera_rig=null; tick(); check(not bar.visible,"missing rig hides stale pixels " + tag)
	game.camera_rig=rig; recover(tag+" rig")
	var camera:Camera3D=rig.camera
	rig.camera=null; tick(); check(not bar.visible,"missing camera hides stale pixels " + tag)
	rig.camera=camera; recover(tag+" camera")
	display.game=null; tick(); check(not bar.visible,"missing game hides stale pixels " + tag)
	display.game=game; recover(tag+" game")
	var original:=camera.global_transform
	game.camera_rig.gameplay_camera.mode=0
	camera.rotate_y(PI); tick()
	check(not bar.visible,"behind-camera player hides immediately " + tag)
	camera.global_transform=original; remote_ball(); recover(tag+" behind-camera")
	# A replaced owner cannot inherit the previous player's warning hysteresis.
	game.player_left.stamina.value=20; tick()
	var original_player=game.player_left
	game.player_right.stamina.value=26
	game.player_left=game.player_right; tick()
	check(display.fills[0].bg_color!=WARNING_COLOR,"new player resets warning state " + tag)
	game.player_left=original_player
	prepare()

func pointer_repetition() -> void:
	root.content_scale_size=Vector2i(720,1280); root.size=Vector2i(720,1280)
	await process_frame; await process_frame
	prepare(); game.hud._layout_desktop(); game.mobile_controls._layout()
	game.mobile_controls.set_process_input(true)
	for cycle in 6:
		var hit:Vector2=game.mobile_controls._charge_center
		var down:=InputEventMouseButton.new()
		down.button_index=MOUSE_BUTTON_LEFT; down.position=hit; down.pressed=true
		root.push_input(down,true)
		check(Input.is_action_pressed("ui_accept"),"real pointer HIT remains reachable")
		game.mobile_controls.cancel_all()
		down.pressed=false; root.push_input(down,true)
		check(not Input.is_action_pressed("ui_accept"),"cancel/release cannot stick repeated HIT")
		game.scoreboard_ui.show_shot_type("VOLLEY"); game.scoreboard_ui.show_speed(18.7)
		game.scoreboard_ui.hide_all_hud(); game.scoreboard_ui.show_all_hud(); game.scoreboard_ui._process(1.0/rate)
		check(game.hud.shot_type.modulate.a==0 and game.hud.speed.modulate.a==0,"pointer cancel hide/show stale event")
	for bar in display.bars: check(bar.mouse_filter==Control.MOUSE_FILTER_IGNORE,"bars cannot steal pointer events")
	record("pointer_repetition",{"cancel_release_cycles":6})
