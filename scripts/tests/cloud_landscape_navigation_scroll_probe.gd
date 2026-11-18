extends "res://scripts/tests/cloud_landscape_navigation.gd"
func run() -> void:
	var controller=root.get_node("PauseController")
	if root.focus_exited.is_connected(controller._on_window_focus_exited):root.focus_exited.disconnect(controller._on_window_focus_exited)
	if root.focus_entered.is_connected(controller._on_window_focus_entered):root.focus_entered.disconnect(controller._on_window_focus_entered)
	root.content_scale_size=Vector2i(720,1280);root.size=Vector2i(640,360)
	Input.set_emulate_mouse_from_touch(true)
	var title=await make_title();title._toggle_controls();await frames()
	print("PROBE viewport ",root.get_visible_rect()," size ",root.size)
	print("PROBE scroll ",physical_rect(title._scroll)," content ",physical_rect(title._content)," max ",title._scroll.get_v_scroll_bar().max_value," page ",title._scroll.get_v_scroll_bar().page," pos ",title._scroll.scroll_vertical)
	Input.set_emulate_touch_from_mouse(true)
	print("PROBE touchscreen hint ",DisplayServer.is_touchscreen_available())
	for button in title._buttons: button.mouse_filter=Control.MOUSE_FILTER_PASS
	print("PROBE filters ",title._scroll.mouse_filter," ",title._content.mouse_filter," ",title._play.mouse_filter)
	title._scroll.gui_input.connect(func(e): print("SCROLL EVENT ",e.as_text()))
	title._play.gui_input.connect(func(e): print("PLAY EVENT ",e.as_text()))
	await swipe_up(title._scroll)
	print("PROBE after swipe ",title._scroll.scroll_vertical," focus ",root.gui_get_focus_owner())
	var event:=InputEventMouseButton.new();event.position=physical_rect(title._scroll).get_center();event.button_index=MOUSE_BUTTON_WHEEL_DOWN;event.pressed=true
	Input.parse_input_event(event);await frames()
	print("PROBE after wheel ",title._scroll.scroll_vertical)
	title.queue_free();await frames();quit()
