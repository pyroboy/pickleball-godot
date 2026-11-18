extends "res://scripts/tests/cloud_landscape_ui.gd"
## Popup-only follow-on: local colors, physical row geometry and actual selection.
const SettingsRef=preload("res://scripts/ui/settings.gd")
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="):variant=arg.trim_prefix("--variant=")
	capture=OS.get_cmdline_user_args().has("--capture")
	settings_path="res://tools/cloud_qa/landscape_ui_popup_theme_candidate.gd"
	if variant=="before":settings_path="res://tools/cloud_qa/landscape_ui_popup_theme_before.gd"
	elif variant=="production":settings_path="res://scripts/ui/settings_panel.gd"
	output=OS.get_environment("LANDSCAPE_UI_REPORT")
	call_deferred("run")

func tap_item(popup:PopupMenu,index:int,touch_input:bool) -> void:
	var font_size:=popup.get_theme_font_size("font_size")
	var row_height:=popup.get_theme_font("font").get_height(font_size)+popup.get_theme_constant("v_separation")
	var panel_style:=popup.get_theme_stylebox("panel")
	var point:=Vector2(popup.position)+Vector2(popup.size.x*0.5,panel_style.get_content_margin(SIDE_TOP)+(index+0.5)*row_height)
	if touch_input:
		for pressed in [true,false]:
			var event:=InputEventScreenTouch.new();event.index=0;event.pressed=pressed;event.position=root.get_final_transform()*point
			Input.parse_input_event(event);await process_frame
	else:
		var move:=InputEventMouseMotion.new();move.position=point;move.global_position=point;root.push_input(move,true);await process_frame
		for pressed in [true,false]:
			var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;event.global_position=point
			root.push_input(event,true);await process_frame
	await frames()

func run() -> void:
	if not OS.get_user_data_dir().contains("landscape-ui-"):quit(2);return
	create_timer(120.0,true).timeout.connect(func():quit(2))
	var controller=root.get_node("PauseController")
	if root.focus_exited.is_connected(controller._on_window_focus_exited):root.focus_exited.disconnect(controller._on_window_focus_exited)
	if root.focus_entered.is_connected(controller._on_window_focus_entered):root.focus_entered.disconnect(controller._on_window_focus_entered)
	controller.set_process_unhandled_input(false)
	Input.set_emulate_mouse_from_touch(true)
	var settings=root.get_node("Settings")
	root.content_scale_size=Vector2i(720,1280)
	paused=true
	for size in SIZES:
		root.size=size;await frames()
		settings.set_value("video.camera_mode",0);settings.set_value("video.focus_arc_style",0)
		var panel=load(settings_path).new();root.add_child(panel);await frames()
		var scroll:ScrollContainer=panel.find_child("Video",true,false)
		for setting in ["video.camera_mode","video.focus_arc_style"]:
			scope="%dx%d/%s" % [size.x,size.y,setting]
			var control:OptionButton=panel.find_child(setting.replace(".","_"),true,false)
			scroll.ensure_control_visible(control);await frames()
			check(scroll.get_global_rect().grow(1.0/root.get_final_transform().get_scale().y).encloses(control.get_global_rect()),"closed selector reachable by scroll")
			var before_geometry:=physical_rect(control)
			await click(control)
			var popup:=control.get_popup()
			check(popup.visible,"pointer opens popup")
			var font_size:=popup.get_theme_font_size("font_size")
			var font_pixels:=font_size*root.get_final_transform().get_scale().y
			var item_height:float=(popup.get_theme_font("font").get_height(font_size)+popup.get_theme_constant("v_separation"))*root.get_final_transform().get_scale().y
			var rect:=Rect2(Vector2(popup.position),Vector2(popup.size))
			check(font_pixels>=15.9,"popup text at least16px")
			check(item_height>=43.8,"popup rows at least44px")
			check(root.get_visible_rect().grow(1.0).encloses(rect),"popup fits viewport, including lower-edge Arc selector")
			check(popup.get_theme_stylebox("panel").bg_color.is_equal_approx(UiTheme.PANEL),"navy popup panel")
			check(popup.get_theme_stylebox("hover").bg_color.is_equal_approx(UiTheme.SURFACE),"navy popup highlight")
			check(popup.get_theme_color("font_color").is_equal_approx(UiTheme.INK),"readable text color")
			check(popup.get_theme_color("font_hover_color").is_equal_approx(UiTheme.ACCENT),"readable selected/focused color")
			check(physical_rect(control).is_equal_approx(before_geometry),"opening does not alter closed control geometry")
			records.append({"case":scope,"font_physical":font_pixels,"row_height_physical":item_height,"popup_physical_rect":rect_list(Rect2(rect.position*root.get_final_transform().get_scale(),rect.size*root.get_final_transform().get_scale())),"closed_control_physical_rect":rect_list(before_geometry),"scroll_vertical":scroll.scroll_vertical})
			# Move keyboard focus to another item so native capture shows highlight.
			await key(KEY_DOWN,popup)
			await screenshot("popup-%dx%d-%s" % [size.x,size.y,control.name])
			await tap_item(popup,control.item_count-1,false)
			check(not popup.visible and control.selected==control.item_count-1,"pointer selects last item and closes")
			check(int(settings.get_value(setting))==control.item_count-1,"pointer selection persists matching setting")
			var saved:=ConfigFile.new()
			check(saved.load(SettingsRef.CONFIG_PATH)==OK and int(saved.get_value(setting.get_slice(".",0),setting.get_slice(".",1),-1))==control.item_count-1,"pointer selection reaches saved config")
			scroll.ensure_control_visible(control);await frames();await click(control)
			await tap_item(popup,0,true)
			check(not popup.visible and control.selected==0,"touch selects first item and closes")
			check(int(settings.get_value(setting))==0,"touch selection persists matching setting")
			check(saved.load(SettingsRef.CONFIG_PATH)==OK and int(saved.get_value(setting.get_slice(".",0),setting.get_slice(".",1),-1))==0,"touch selection reaches saved config")
			await click(control);await key(KEY_ESCAPE,popup)
			check(not popup.visible and is_instance_valid(panel) and int(settings.get_value(setting))==0,"Escape cancels popup only")
		panel.queue_free();await frames()
	paused=false
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"variant":variant,"scope":"Popup-only local styling/touch follow-on; archived build28 cloud source","checks":checks,"failures":failures,"records":records},"\t"))
	for failure in failures:print("FAIL: ",failure)
	print("CLOUD LANDSCAPE POPUPS %s: %d checks, %d failures" % [variant,checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
