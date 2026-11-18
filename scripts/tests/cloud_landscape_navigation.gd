extends SceneTree
## Real stretched-window geometry and event-dispatch checks. No gameplay tuning.
const SIZES := [Vector2i(390,844), Vector2i(430,932), Vector2i(540,960), Vector2i(960,540), Vector2i(1178,814)]
var checks := 0
var failures: Array[String] = []
var records: Array = []
var scope := ""
var output := ""
var variant := "production"
var capture := false
var geometry_only := false
var toggle_probe := false
var settings_events := 0
var baseline_scripts := {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant=arg.trim_prefix("--variant=")
	capture=OS.get_cmdline_user_args().has("--capture")
	geometry_only=OS.get_cmdline_user_args().has("--geometry-only")
	toggle_probe=OS.get_cmdline_user_args().has("--toggle-probe")
	output=OS.get_environment("LANDSCAPE_NAVIGATION_REPORT")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(scope+": "+label)

func frames(count: int=8) -> void:
	for index in range(count): await process_frame

func physical_rect(control: Control) -> Rect2:
	return root.get_final_transform()*control.get_global_rect()

func rect_list(rect: Rect2) -> Array:
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]

func button_named(parent: Node, text: String) -> Button:
	for child in parent.get_children():
		if child is Button and child.text==text: return child
		var found=button_named(child,text)
		if found: return found
	return null

func baseline_script(name: String) -> GDScript:
	if not baseline_scripts.has(name):
		var script:=GDScript.new()
		script.source_code=FileAccess.get_file_as_string("res://tools/cloud_qa/landscape_navigation_before/"+name+".gd.txt")
		check(script.reload()==OK,"baseline source parses: "+name)
		baseline_scripts[name]=script
	return baseline_scripts[name]

func make_title() -> Node:
	var title=load("res://scenes/title.tscn").instantiate()
	if variant=="before": title.set_script(baseline_script("title_screen"))
	root.add_child(title);current_scene=title
	await frames()
	return title

func replace_practice(game: Node) -> void:
	if variant!="before": return
	game.practice_panel.queue_free();await frames()
	game.practice_panel=baseline_script("practice_panel").new()
	game.add_child(game.practice_panel);game.practice_panel.setup(game)
	await frames()

func screenshot(name: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	var path:=output.get_base_dir()+"/"+name+".png"
	check(root.get_texture().get_image().save_png(path)==OK,"screenshot saved")

func record_control(control: Control, label: String) -> void:
	var record:={"case":scope,"kind":control.get_class(),"label":label,"physical_rect":rect_list(physical_rect(control))}
	if control is Label or control is Button or control is ProgressBar:
		record.font_physical=control.get_theme_font_size("font_size")*root.get_final_transform().get_scale().y
	records.append(record)

func inspect_menu(panel: Control, content: Control, landscape: bool, scroller: ScrollContainer=null) -> void:
	record_control(panel,"panel")
	check(root.get_visible_rect().grow(0.1).encloses(panel.get_global_rect()),"panel stays inside viewport")
	for child in content.get_children():
		if not child is Control or not child.is_visible_in_tree(): continue
		var text_value: String=child.text if child is Label or child is Button else child.get_class()
		record_control(child,text_value)
		if variant=="before" or not landscape: continue
		var pixels:=physical_rect(child)
		check(pixels.position.x>=physical_rect(panel).position.x-0.2 and pixels.end.x<=physical_rect(panel).end.x+0.2,"content stays inside panel width: "+text_value)
		if child is Label or child is Button:
			var font_pixels:float=child.get_theme_font_size("font_size")*root.get_final_transform().get_scale().y
			check(font_pixels>=15.99,"16px minimum readable text: "+text_value)
		if child is Button:
			check(pixels.size.x>=43.99 and pixels.size.y>=43.99,"44px target: "+text_value)
			var text_width:float=child.get_theme_font("font").get_string_size(child.text,HORIZONTAL_ALIGNMENT_LEFT,-1,child.get_theme_font_size("font_size")).x
			var style:StyleBox=child.get_theme_stylebox("normal")
			check(text_width+style.get_minimum_size().x<=child.size.x+0.1,"button caption does not clip: "+text_value)
	if scroller and landscape and variant!="before":
		check(panel.get_global_rect().encloses(scroller.get_global_rect()),"scroll viewport stays inside panel")
		check(scroller.horizontal_scroll_mode==ScrollContainer.SCROLL_MODE_DISABLED,"no horizontal scrolling")

func reveal(control: Control) -> void:
	var parent=control.get_parent()
	while parent:
		if parent is ScrollContainer and parent.is_visible_in_tree():
			parent.ensure_control_visible(control)
		parent=parent.get_parent()
	await frames()

func click(control: Control) -> void:
	check(control!=null,"pointer target exists")
	if control==null: return
	await reveal(control)
	for down in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=root.get_final_transform()*control.get_global_rect().get_center()
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
		Input.parse_input_event(event);await process_frame
	await frames()

func touch(control: Control) -> void:
	check(control!=null,"touch target exists")
	if control==null: return
	await reveal(control)
	for down in [true,false]:
		var event:=InputEventScreenTouch.new()
		event.index=0;event.position=root.get_final_transform()*control.get_global_rect().get_center();event.pressed=down
		Input.parse_input_event(event);await process_frame
	await frames()

func key(code: Key) -> void:
	for down in [true,false]:
		var event:=InputEventKey.new()
		event.keycode=code;event.physical_keycode=code;event.pressed=down
		Input.parse_input_event(event);await process_frame
	await frames()

func native_back() -> void:
	# The actual native notification routes through the same production handler.
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames()

func wait_match(title) -> Node:
	var limit:=Time.get_ticks_msec()+20000
	while is_instance_valid(title) and current_scene==title and Time.get_ticks_msec()<limit:
		OS.delay_msec(1);await process_frame
	check(current_scene!=title and current_scene!=null,"real threaded scene transition completes")
	await frames()
	return current_scene

func run() -> void:
	if not OS.get_user_data_dir().contains("landscape-navigation-"):
		push_error("Use isolated landscape-navigation-* HOME/XDG");quit(2);return
	create_timer(170.0,true).timeout.connect(func():quit(2))
	var controller=root.get_node("PauseController")
	if root.focus_exited.is_connected(controller._on_window_focus_exited):root.focus_exited.disconnect(controller._on_window_focus_exited)
	if root.focus_entered.is_connected(controller._on_window_focus_entered):root.focus_entered.disconnect(controller._on_window_focus_entered)
	root.content_scale_size=Vector2i(720,1280)
	Input.set_emulate_mouse_from_touch(true)
	var settings=root.get_node("Settings")
	# Seed a non-default, existing config only inside this isolated test HOME.
	settings._config.set_value("video","focus_dim",0.21)
	settings._config.set_value("audio","master",0.63)
	check(settings._config.save("user://settings.cfg")==OK,"isolated settings fixture saved")
	var settings_before: String=settings._config.encode_to_text()
	var settings_file_before:=FileAccess.get_sha256("user://settings.cfg")
	settings.settings_changed.connect(func(_key,_value):settings_events+=1)
	if toggle_probe:
		await probe_attack_toggle()
		return
	for size in SIZES:
		root.size=size;await frames()
		var title=await make_title()
		scope="%dx%d/title" % [size.x,size.y]
		await inspect_menu(title._panel,title._content,size.x>size.y,title.get("_scroll"))
		await screenshot(scope.replace("/","-"))
		if variant!="before" and size.x>size.y:
			for button in title._buttons:
				check(title._scroll.get_global_rect().grow(0.1).encloses(button.get_global_rect()),"default action visible without scroll: "+button.text)
		title._toggle_controls();await frames()
		scope="%dx%d/title-controls" % [size.x,size.y]
		await inspect_menu(title._panel,title._content,size.x>size.y,title.get("_scroll"))
		await screenshot(scope.replace("/","-"))
		title.queue_free();await frames()
	var rotated_title=await make_title()
	rotated_title._toggle_controls();await frames()
	for size in [SIZES[0],SIZES[3],SIZES[4],SIZES[1],SIZES[2]]:
		root.size=size;await frames()
		scope="%dx%d/title-controls-rotated" % [size.x,size.y]
		await inspect_menu(rotated_title._panel,rotated_title._content,size.x>size.y,rotated_title.get("_scroll"))
	rotated_title.queue_free();await frames()
	var game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game;await frames()
	await replace_practice(game)
	for size in SIZES:
		root.size=size;await frames()
		game.practice_panel.open_practice();await frames()
		scope="%dx%d/practice" % [size.x,size.y]
		await inspect_menu(game.practice_panel._panel,game.practice_panel._content,size.x>size.y,game.practice_panel._content.get_parent())
		await screenshot(scope.replace("/","-"))
		game.practice_panel.close_picker();controller.close();await frames()
	game.practice_launcher.start_drill("DINK")
	for size in SIZES:
		root.size=size;await frames()
		game.practice_panel.open_practice();await frames()
		scope="%dx%d/practice-active" % [size.x,size.y]
		await inspect_menu(game.practice_panel._panel,game.practice_panel._content,size.x>size.y,game.practice_panel._content.get_parent())
		await screenshot(scope.replace("/","-"))
		game.practice_panel.close_picker();controller.close();await frames()
	game.practice_panel.open_practice();await frames()
	for size in [SIZES[0],SIZES[3],SIZES[4],SIZES[1],SIZES[2]]:
		root.size=size;await frames()
		scope="%dx%d/practice-active-rotated" % [size.x,size.y]
		await inspect_menu(game.practice_panel._panel,game.practice_panel._content,size.x>size.y,game.practice_panel._content.get_parent())
	game.practice_panel.close_picker();controller.close();await frames()
	game.practice_launcher.stop_practice()
	game.match_over=true;game.match_winner=0;game.score_left=11;game.score_right=7
	for size in SIZES:
		root.size=size;await frames()
		game.practice_panel._fit();await frames()
		scope="%dx%d/match-result" % [size.x,size.y]
		await inspect_menu(game.practice_panel._panel,game.practice_panel._content,size.x>size.y,game.practice_panel._content.get_parent())
		await screenshot(scope.replace("/","-"))
	game.queue_free();await frames()
	if variant!="before" and not geometry_only:
		print("Navigation phase: title event dispatch")
		await test_title_inputs(controller)
		print("Navigation phase: practice event dispatch")
		await test_practice_inputs(controller)
	check(settings_events==0,"navigation emitted no settings writes")
	check(settings._config.encode_to_text()==settings_before,"settings values unchanged")
	check(FileAccess.get_sha256("user://settings.cfg")==settings_file_before,"existing settings file stays byte-identical")
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"variant":variant,"scope":"Archived build28 cloud Title/Practice candidate, not unavailable Mac30/31 or device acceptance","checks":checks,"failures":failures,"settings_events":settings_events,"records":records},"\t"))
	for failure in failures:print("FAIL: ",failure)
	print("CLOUD LANDSCAPE NAVIGATION %s: %d checks, %d failures" % [variant,checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_title_inputs(controller: Node) -> void:
	for size in [SIZES[3],SIZES[4]]:
		root.size=size;await frames()
		var title=await make_title()
		scope="%dx%d/title-input" % [size.x,size.y]
		await touch(title._settings)
		check(is_instance_valid(title._overlay),"touch Settings opens overlay")
		var overlay=title._overlay
		title._open_settings()
		check(title._overlay==overlay,"repeated Settings keeps one overlay")
		if is_instance_valid(overlay):
			root.size=SIZES[0];await frames()
			check(is_instance_valid(title._overlay),"Settings remains open through portrait rotation")
			root.size=size;await frames()
			check(is_instance_valid(title._overlay),"Settings remains open through landscape rotation")
			await touch(button_named(overlay,"Back"))
			check(not is_instance_valid(title._overlay),"touch Back closes Settings")
			check(root.gui_get_focus_owner()==title._settings,"Settings close restores focus")
		await click(title._controls)
		check(title._hint.text.begins_with("MOVE"),"pointer Controls expands")
		check(title._scroll.get_global_rect().grow(0.1).encloses(title._status.get_global_rect()),"expanded Controls fully fits at target resolution")
		await screenshot(scope.replace("/","-")+"-expanded")
		# Requested sizes fit completely; a shorter window exercises overflow.
		root.size=Vector2i(640,360);await frames()
		title._scroll.scroll_vertical=0;await frames()
		await swipe_up(title._scroll)
		check(title._scroll.scroll_vertical>0,"touch swipe scrolls Controls when short window overflows")
		check(root.get_visible_rect().grow(0.1).encloses(title._panel.get_global_rect()),"short-window panel remains bounded")
		check(title._hint.text.begins_with("MOVE") and not title._loading,"swiping Controls does not activate navigation")
		await screenshot(scope.replace("/","-")+"-short-overflow")
		root.size=size;await frames()
		title._controls.grab_focus();await frames()
		for rotated in [SIZES[0],SIZES[4],SIZES[1],SIZES[3],SIZES[2],size]:
			root.size=rotated;await frames()
			check(root.get_visible_rect().grow(0.1).encloses(title._panel.get_global_rect()),"open Controls fits after rotation "+str(rotated))
			check(root.gui_get_focus_owner()==title._controls,"rotation preserves focused Controls button")
		await native_back()
		check(not title._hint.text.begins_with("MOVE"),"native Back collapses Controls")
		title._settings.grab_focus();await key(KEY_SPACE)
		check(is_instance_valid(title._overlay),"keyboard opens Settings")
		await key(KEY_ESCAPE)
		check(not is_instance_valid(title._overlay),"Escape closes Settings")
		await touch(title._settings);await native_back()
		check(not is_instance_valid(title._overlay),"native Back closes Settings")
		await touch(title._play)
		var game=await wait_match(title)
		check(game!=null and game.get("ball")!=null,"touch Play loads actual game")
		check(not has_meta("open_practice") and not game.practice_panel._picker_open,"Play does not enter Practice")
		game.queue_free();await frames()
		var next_title=await make_title()
		await touch(button_named(next_title,"PRACTICE"))
		game=await wait_match(next_title)
		check(game.practice_panel._picker_open and paused,"touch Practice loads paused picker")
		await touch(button_named(game.practice_panel,"Back"))
		check(not game.practice_panel._picker_open and paused,"picker Back preserves Pause")
		controller.close();game.queue_free();await frames()

func test_practice_inputs(controller: Node) -> void:
	var game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game;await frames()
	for size in [SIZES[3],SIZES[4]]:
		root.size=size;await frames()
		scope="%dx%d/practice-input" % [size.x,size.y]
		game.score_left=4;game.score_right=7
		game.practice_panel.open_practice();await frames()
		var scroll:ScrollContainer=game.practice_panel._content.get_parent()
		scroll.scroll_vertical=0;await frames()
		await swipe_up(scroll)
		check(scroll.scroll_vertical>0,"touch swipe scrolls existing picker")
		check(game.practice_panel._picker_open and paused and not game.practice_launcher.is_active,"swiping does not launch a drill")
		await touch(button_named(game.practice_panel,"Back"))
		for mode in [["Wall Practice · solo rebound court","WALL"],["Serve placement","SERVE"],["Baseline drive","DRIVE"],["Serve return","RETURN"],["Live crosscourt dinking","DINK"],["Kitchen-line fast hands","HANDS"]]:
			game.practice_panel.open_practice();await frames()
			var count:int=game.practice_panel._content.get_child_count()
			game.practice_panel.open_practice()
			check(count==game.practice_panel._content.get_child_count(),"repeated open does not duplicate controls")
			await touch(button_named(game.practice_panel,mode[0]))
			check(game.practice_launcher.is_active and game.practice_launcher.drill_mode==mode[1],"touch starts mode "+mode[1])
			check(not paused and not game.practice_panel._picker_open,"mode resumes game "+mode[1])
			game.practice_panel.open_practice();await frames()
			await touch(button_named(game.practice_panel,"Reset wall ball" if mode[1]=="WALL" else "Repeat current drill"))
			check(game.practice_launcher.drill_mode==mode[1] and not paused,"repeat keeps mode "+mode[1])
			game.practice_panel.open_practice();await frames()
			await touch(button_named(game.practice_panel,"Return to match"))
			check(not game.practice_launcher.is_active and not paused,"Return exits mode "+mode[1])
			check(game.score_left==4 and game.score_right==7,"practice preserves match score")
		for entry in [["Watch crosscourt dink demo","DINK"],["Watch fast-hands demo","HANDS"],["Watch wide-dink recovery demo","DINK"],["Watch pop-up attack and reset demo","DINK"]]:
			game.practice_panel.open_practice();await frames()
			await click(button_named(game.practice_panel,entry[0]))
			check(game.practice_launcher.drill_mode==entry[1] and not paused,"pointer starts demo: "+entry[0])
		game.practice_panel.open_practice();await frames()
		print("Navigation phase: attack toggle ",size)
		var before:bool=game.practice_launcher.allow_attacks
		await touch(button_named(game.practice_panel,"Allow pop-up attacks: "+("ON" if before else "OFF")))
		check(game.practice_launcher.allow_attacks!=before and game.practice_panel._picker_open and paused,"toggle attacks preserves picker and pause")
		print("Navigation phase: reverse diagonal ",size)
		var diagonal:int=game.practice_launcher.diagonal
		await touch(button_named(game.practice_panel,"Reverse diagonal and repeat"))
		check(game.practice_launcher.diagonal==-diagonal and not paused,"reverse diagonal repeats and resumes")
		game.practice_panel.open_practice();await frames()
		var back=button_named(game.practice_panel,"Back")
		back.grab_focus();await frames()
		check(game.practice_panel._scroll.get_global_rect().grow(1).encloses(back.get_global_rect()),"keyboard focus scrolls Back into view")
		await screenshot(scope.replace("/","-")+"-back-focused")
		await key(KEY_SPACE)
		check(not game.practice_panel._picker_open and paused,"keyboard Back returns to Pause")
		game.practice_panel.open_practice();await frames()
		await key(KEY_ESCAPE)
		check(not game.practice_panel._picker_open and paused,"Escape closes only picker")
		game.practice_panel.open_practice();await frames()
		await native_back()
		check(not game.practice_panel._picker_open and paused,"native Back closes only picker")
		game.practice_panel.open_practice();await frames()
		for rotated in [SIZES[0],SIZES[4],SIZES[1],SIZES[3],SIZES[2],size]:
			root.size=rotated;await frames()
			check(root.get_visible_rect().grow(0.1).encloses(game.practice_panel._panel.get_global_rect()),"picker fits after rotation "+str(rotated))
			check(game.practice_panel._picker_open and paused,"rotation preserves modal state")
		await touch(button_named(game.practice_panel,"Return to match"))
		check(not game.practice_launcher.is_active and not paused,"rotated picker Return works")
	game.match_over=true;game.match_winner=0;game.score_left=11;game.score_right=7
	await frames()
	await touch(button_named(game.practice_panel,"Rematch"))
	check(not game.match_over and game.score_left==0 and game.score_right==0,"result Rematch starts fresh match")
	game.match_over=true;game.match_winner=0;await frames()
	await click(button_named(game.practice_panel,"Practice drills"))
	check(game.practice_panel._picker_open and paused,"result Practice drills opens paused picker")
	await touch(button_named(game.practice_panel,"Back"))
	check(not game.practice_panel._picker_open and paused,"result Practice Back preserves Pause")
	controller.close()
	game.queue_free();await frames()

func swipe_up(scroll: ScrollContainer) -> void:
	# Godot gates native ScrollContainer dragging on touchscreen availability.
	# Enable its supported runtime emulation only for this simulated gesture.
	var was_emulated:=Input.is_emulating_touch_from_mouse()
	Input.set_emulate_touch_from_mouse(true)
	check(DisplayServer.is_touchscreen_available(),"simulated touchscreen hint is active")
	var before_scroll:=scroll.scroll_vertical
	var rect:=physical_rect(scroll)
	var begin:=rect.position+Vector2(rect.size.x*0.5,rect.size.y-28)
	var end:=rect.position+Vector2(rect.size.x*0.5,28)
	var press:=InputEventScreenTouch.new()
	press.index=0;press.position=begin;press.pressed=true
	Input.parse_input_event(press);await process_frame
	var last:=begin
	for step in range(1,13):
		var drag:=InputEventScreenDrag.new()
		drag.index=0;drag.position=begin.lerp(end,step/12.0);drag.relative=drag.position-last
		drag.velocity=drag.relative*60;last=drag.position
		Input.parse_input_event(drag);await process_frame
	var release:=InputEventScreenTouch.new()
	release.index=0;release.position=end;release.pressed=false
	Input.parse_input_event(release);await frames()
	check(scroll.scroll_vertical>before_scroll,"drag advances scroll beyond starting offset")
	Input.set_emulate_touch_from_mouse(was_emulated)

func probe_attack_toggle() -> void:
	var game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game;await frames()
	await replace_practice(game)
	game.practice_launcher.start_drill("DINK")
	for size in [SIZES[3],SIZES[4]]:
		root.size=size;await frames()
		game.practice_panel.open_practice();await frames()
		var before:bool=game.practice_launcher.allow_attacks
		print("Attack toggle probe: ",variant," ",size)
		await touch(button_named(game.practice_panel,"Allow pop-up attacks: "+("ON" if before else "OFF")))
		check(game.practice_launcher.allow_attacks!=before,"attack toggle still works")
		check(game.practice_panel._picker_open and paused,"attack toggle preserves picker and pause")
		game.practice_panel.close_picker();root.get_node("PauseController").close();await frames()
	game.queue_free();await frames()
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"variant":variant,"probe":"existing attack-toggle rebuild during input dispatch","checks":checks,"failures":failures},"\t"))
	quit(0 if failures.is_empty() else 1)
