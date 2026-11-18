extends SceneTree
## Test-only production-caption wrapper, geometry audit, and owner-invoked native captures.
const SIZES = [Vector2i(390,844),Vector2i(1170,2532),Vector2i(430,932),Vector2i(1290,2796),Vector2i(540,960),Vector2i(1620,2880),Vector2i(1536,2048),Vector2i(960,540),Vector2i(1178,814)]
var game: Node
var report: Dictionary = {"cases":[],"checks":0,"failures":[]}
var current: Dictionary = {}
var output: String = ""
var capture_dir: String = ""
var wanted_width: int = 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	report.checks+=1
	if not ok: report.failures.append(label)
func frames(count: int = 3) -> void:
	for i in count: await process_frame
func v(value: Vector2) -> Array: return [value.x,value.y]
func r(value: Rect2) -> Array: return [value.position.x,value.position.y,value.size.x,value.size.y]
func control_info(node: Control) -> Dictionary:
	var font: Font = node.get_theme_font("font")
	var fs: int = node.get_theme_font_size("font_size")
	return {"rect":r(node.get_global_rect()),"font":fs,"font_height":font.get_height(fs),"minimum_size":v(node.get_combined_minimum_size()),"mouse_filter":node.mouse_filter,"visible":node.is_visible_in_tree(),"text":node.text if node is Label or node is Button else ""}
func geometry() -> Dictionary:
	var ui=game.mobile_controls
	var out: Dictionary={"centers":{"stick":v(ui._stick_center),"charge":v(ui._charge_center),"cancel":v(ui._cancel_center),"serve":v(ui._serve_selector_center),"timing":v(ui._timing_caption_center)},"radii":{"stick":ui._stick_radius,"charge":ui._charge_radius,"cancel":ui._cancel_radius,"serve":ui._serve_selector_radius,"shot":ui._shot_button_radius,"timing":ui._timing_ring_max},"shots":[],"deck":r(ui._deck_rect),"timing_safe":r(ui._timing_safe),"controls":{}}
	for center in ui._guide_nodes:out.shots.append(v(center))
	for key in ["score","state","_toolbar","_guide_button","_pause_button","_skip_button","_charge_label","_controls_hint","_charge_bar","_guide"]:
		out.controls[key]=control_info(game.hud.get(key))
	for i in game.hud._toolbar_captions.size():out.controls["caption_"+str(i)]=control_info(game.hud._toolbar_captions[i])
	return out
func reset_ui() -> void:
	var ui=game.mobile_controls
	ui.cancel_all();ui._hit_timing.clear();ui._serve_timing={};ui._serve_contact_flash=0
	game.game_state=0;game.serving_team=0;game.match_over=false
	game.hud._guide.hide();game.hud.set_between_point_active(false)
	game.hud.set_gameplay_elements_visible(true)
	ui.visible=ui.enabled;ui._was_blocked=false
	game.hud._charge_bar.value=0.5
func snap(label: String, selected_style: String = "") -> void:
	var ui=game.mobile_controls
	ui.queue_redraw();await frames()
	var row: Dictionary={"name":label,"captions":ui.drawn_captions.duplicate(true) if ui.is_visible_in_tree() and ui.enabled else [],"mobile_visible":ui.is_visible_in_tree(),"geometry":geometry(),"timing_backing":r(ui._timing_caption_rect),"selected_style":selected_style,"wheel_visible":ui._show_serve_selector(),"gesture_is_serve":ui._gesture_is_serve,"charge_owns_action":ui._charge_owns_action}
	if not selected_style.is_empty():
		var found: bool = false
		for caption in row.captions:
			if caption.text.to_upper()==selected_style.to_upper():found=true
		row.selected_style_visible=found
		check(found,"selected style visible at "+label+" "+str(root.size))
	if not capture_dir.is_empty():
		await RenderingServer.frame_post_draw
		var path: String=capture_dir.path_join("%dx%d_%s.png" % [root.size.x,root.size.y,label])
		var result: int = root.get_texture().get_image().save_png(path)
		check(result==OK,"capture saved "+path);row.capture=path
	current.states.append(row)
func run() -> void:
	output=OS.get_environment("PORTRAIT_TYPOGRAPHY_OUTPUT")
	capture_dir=OS.get_environment("PORTRAIT_TYPOGRAPHY_CAPTURE_DIR")
	wanted_width=int(OS.get_environment("PORTRAIT_TYPOGRAPHY_WIDTH"))
	if output.is_empty() or not OS.get_user_data_dir().contains("portrait-typography-"):
		push_error("Use the isolated portrait-typography runner with explicit output");quit(2);return
	if not capture_dir.is_empty():DirAccess.make_dir_recursive_absolute(capture_dir)
	create_timer(240,true).timeout.connect(func():push_error("Portrait typography suite timeout");quit(2))
	var controller=root.get_node("PauseController")
	if root.focus_exited.is_connected(controller._on_window_focus_exited):root.focus_exited.disconnect(controller._on_window_focus_exited)
	if root.focus_entered.is_connected(controller._on_window_focus_entered):root.focus_entered.disconnect(controller._on_window_focus_entered)
	root.content_scale_size=Vector2i(720,1280)
	game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game;await frames(8)
	var original=game.mobile_controls
	var probe=load("res://tools/cloud_qa/movement_f_typography_probe.gd").new()
	game.add_child(probe);game.mobile_controls=probe;probe.setup(game)
	original.queue_free();await frames()
	game.set_process(false);game.set_physics_process(false)
	for node in game.find_children("*","Node",true,false):node.set_process(false);node.set_physics_process(false)
	game.ball.freeze=true
	var settings=root.get_node("Settings")
	var settings_before: String=settings._config.encode_to_text()
	report.scope="Old build28-derived checkpoint D isolated typography candidate. Native captures only when owner explicitly invokes --native; no Mac30/31, APK, or device acceptance."
	report.policy={"orientation":ProjectSettings.get_setting("display/window/handheld/orientation"),"scale":v(root.content_scale_size),"display_server":DisplayServer.get_name(),"mobile_runtime":OS.get_cmdline_user_args().has("--mobile-runtime")}
	for size in SIZES:
		if wanted_width>0 and size.x!=wanted_width:continue
		root.size=size;await frames(5)
		# Layout must follow the real viewport size_changed signal, without a manual refresh.
		await frames()
		current={"window":v(root.size),"viewport":v(root.get_visible_rect().size),"scale":v(root.get_final_transform().get_scale()),"portrait":game.mobile_controls.enabled,"states":[]}
		check(root.size==size,"actual window "+str(size))
		reset_ui();await frames()
		current.initial_geometry=geometry()
		if not game.mobile_controls.enabled:
			await snap("desktop_idle")
			game.hud.set_between_point_active(true);await snap("desktop_skip")
			report.cases.append(current);continue
		var ui=game.mobile_controls
		for option in ui._serve_options():
			var id: int=int(option.id)
			var label: String=str(option.label)
			for state in ["idle","hold","cancel","release","drop","bounce","commit","contact","recovery"]:
				reset_ui();game.game_serve.selected_serve_style=id
				ui._serve_timing={"style":id,"phase":"HELD","locked":false}
				if state in ["hold","cancel"]:
					ui._press(71,ui._charge_center)
					if state=="cancel":ui._drag(71,ui._cancel_center)
				elif state in ["release","drop","bounce","commit","contact","recovery"]:
					ui._press(71,ui._charge_center);ui._release(71)
					game.game_state=1
					ui._serve_timing={"style":id,"phase":{"release":"RELEASE","drop":"DROP","bounce":"BOUNCE","commit":"SWING","contact":"CONTACT","recovery":"RECOVERY"}[state],"progress":0.6,"locked":true}
					if state=="contact":ui._serve_contact_flash=0.25
				await snap("serve_%d_%s" % [id,state],label)
		reset_ui();game.game_serve.selected_serve_style=6
		ui._press(74,ui._charge_center);Input.action_release("ui_accept");ui._charge_owns_action=false
		await snap("serve_locked_held", "Screwball")
		for shot in ["FLAT","TOPSPIN","SLICE","DROP"]:
			reset_ui();game.game_state=2
			ui._begin_shot(72,ui._charge_center,shot);await snap("shot_"+shot.to_lower())
			ui._drag(72,ui._cancel_center);await snap("shot_"+shot.to_lower()+"_cancel")
		for text in ["","NO CONTACT","RELEASE","MOVE CLOSER","HOLD","HOLD HIT"]:
			reset_ui();game.game_state=2
			if text!="HOLD HIT":ui._begin_shot(72,ui._charge_center,"FLAT")
			ui._hit_timing.caption=text;ui._hit_timing.active=text not in ["","NO CONTACT"];ui._hit_timing.ready=text=="RELEASE"
			await snap("timing_"+text.to_lower().replace(" ","_") if not text.is_empty() else "timing_empty")
		for owns_action in [true,false]:
			reset_ui();game.game_state=2;ui._begin_shot(73,ui._charge_center,"FLAT")
			if not owns_action:Input.action_release("ui_accept")
			ui._charge_owns_action=owns_action
			for ratio in [0.0,0.01,0.5,0.99,1.0]:
				game.hud._charge_bar.value=ratio;await snap("hold_%s_%d" % [str(owns_action),roundi(ratio*100)])
		reset_ui();game.hud._toggle_guide();ui.visible=false;await snap("guide")
		reset_ui();game.hud.set_between_point_active(true);ui.visible=false;await snap("skip")
		var panel=load("res://scripts/ui/settings_panel.gd").new();root.add_child(panel);await frames()
		current.settings_geometry=[]
		for control in panel._panel.find_children("*","Control",true,false):
			if control is Label or control is BaseButton or control is Range:
				current.settings_geometry.append({"class":control.get_class(),"info":control_info(control)})
		panel.queue_free();await frames()
		report.cases.append(current)
	check(settings_before==settings._config.encode_to_text(),"settings not changed")
	game.mobile_controls.cancel_all()
	check(not Input.is_action_pressed("ui_accept"),"no retained HIT action")
	for action in game.mobile_controls.MOVE_ACTIONS:check(not Input.is_action_pressed(action),"no retained movement "+str(action))
	game.queue_free();await frames()
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("PORTRAIT TYPOGRAPHY: %d checks, %d failures, %d cases" % [report.checks,report.failures.size(),report.cases.size()])
	for failure in report.failures:push_error(failure)
	quit(0 if report.failures.is_empty() else 1)
