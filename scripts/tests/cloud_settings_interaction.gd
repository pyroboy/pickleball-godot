extends SceneTree
## Engine-dispatched Settings interaction tests. Use disposable settings-interaction-* HOME/XDG.
const SIZES := [Vector2i(390, 844), Vector2i(430, 932), Vector2i(540, 960), Vector2i(960, 540)]
const POSE_PATHS := ["user://mobile_pose_overrides_v1.json", "user://mobile_serve_pose_overrides_v1.json"]
const POSE_BYTES := "{\"settings_interaction_fixture\":\"preserve bytes\"}\n"
var checks := 0
var failures: Array[String] = []
var records: Array = []
var current_case := ""
var settings
var events: Array = []
var capture := false
var mode := "sweep"
var panel_script := "res://scripts/ui/settings_panel.gd"

func _initialize() -> void:
	if not OS.get_environment("SETTINGS_INTERACTION_PANEL").is_empty(): panel_script = OS.get_environment("SETTINGS_INTERACTION_PANEL")
	capture = OS.get_cmdline_user_args().has("--capture")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(current_case + ": " + label)

func frames(count := 3) -> void:
	for frame in count: await process_frame

func run() -> void:
	if not OS.get_user_data_dir().contains("settings-interaction-"):
		push_error("Use isolated settings-interaction-* HOME/XDG"); quit(2); return
	create_timer(100.0, true).timeout.connect(func(): quit(2))
	settings = root.get_node("Settings")
	var pause = root.get_node("PauseController")
	pause.set_process_unhandled_input(false)
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	settings.settings_changed.connect(func(key, value): events.append([key, value]))
	if mode == "reload":
		check(settings.get_value("gameplay.aim_focus_seconds") == 3.0, "fresh-process wheel probe did not change aim window")
		check(settings.get_value("pose_editor.interaction_sentinel") == {"preserve": [1, 2, 3]}, "unknown persisted settings survive")
		for path in POSE_PATHS: check(FileAccess.get_file_as_string(path) == POSE_BYTES, "pose sentinel survives " + path)
		finish(); return
	settings.set_value("pose_editor.interaction_sentinel", {"preserve": [1, 2, 3]})
	for path in POSE_PATHS: FileAccess.open(path, FileAccess.WRITE).store_string(POSE_BYTES)
	root.content_scale_size = Vector2i(720, 1280)
	Input.set_emulate_mouse_from_touch(true)
	for size in SIZES:
		root.size = size; await frames(5)
		paused = size != SIZES[0]
		var panel = load(panel_script).new(); root.add_child(panel)
		await frames(5)
		var tabs: TabContainer = panel._vbox.get_child(1)
		current_case = str(size)
		check(root.get_visible_rect().grow(0.5).encloses(panel._panel.get_global_rect()), "panel fits viewport")
		var back: Button = panel._vbox.get_child(0).get_child(1)
		check(root.gui_get_focus_owner() == back, "Back receives initial keyboard focus")
		await check_target(back, size, false)
		for tab_index in tabs.get_tab_count():
			tabs.current_tab = tab_index; await frames(5)
			var scroll: ScrollContainer = tabs.get_tab_control(tab_index)
			current_case = "%s/%s" % [size, scroll.name]
			check(scroll.get_h_scroll_bar().max_value <= scroll.get_h_scroll_bar().page + 0.5, "no horizontal overflow")
			for label in scroll.find_children("*", "Label", true, false):
				check(label.get_global_rect().position.x >= scroll.get_global_rect().position.x - 0.5 and label.get_global_rect().end.x <= scroll.get_global_rect().end.x + 0.5, "label wraps inside panel: " + label.text.left(36))
			for control in scroll.find_children("*", "Control", true, false):
				if control is HSlider:
					await slider_cases(control, scroll, size)
				elif control is CheckButton:
					await check_target(control, size)
					await toggle_cases(control, scroll)
				elif control is Button:
					await check_target(control, size, false)
					if control is OptionButton: await option_cases(control, scroll)
			await keyboard_cases(scroll, tabs)
			if capture:
				scroll.scroll_vertical = 0; await frames(3); await RenderingServer.frame_post_draw
				var destination := OS.get_environment("SETTINGS_INTERACTION_REPORT").get_base_dir()
				check(root.get_texture().get_image().save_png(destination.path_join("settings-%dx%d-%s.png" % [size.x, size.y, scroll.name])) == OK, "native capture saved")
		current_case = str(size) + "/Back"
		back.grab_focus(); await key(KEY_SPACE)
		check(not is_instance_valid(panel), "keyboard Space activates Back")
		if is_instance_valid(panel): panel.queue_free(); await frames()
		panel = load(panel_script).new(); root.add_child(panel); await frames(5)
		await key(KEY_ESCAPE)
		check(not is_instance_valid(panel), "Escape closes settings")
		if is_instance_valid(panel): panel.queue_free(); await frames()
		panel = load(panel_script).new(); root.add_child(panel); await frames(5)
		back = panel._vbox.get_child(0).get_child(1)
		await touch_tap(back.get_global_rect().get_center())
		check(not is_instance_valid(panel), "touch Back closes settings")
		if is_instance_valid(panel): panel.queue_free(); await frames()
	paused = false
	# Last action is only a wheel over a known saved aim value. Reload in another process.
	settings.set_value("gameplay.aim_focus_seconds", 3.0); await frames()
	var last = load(panel_script).new(); root.add_child(last); await frames(5)
	var scroll: ScrollContainer = last.find_child("Gameplay", true, false)
	scroll.get_parent().current_tab = 1; await frames(3)
	var aim: HSlider = last.find_child("gameplay_aim_focus_seconds", true, false)
	scroll.ensure_control_visible(aim); await frames(3)
	current_case = "orientation-resize"
	for size in [SIZES[0], SIZES[3], SIZES[0], SIZES[2]]:
		root.size = size; await frames(5)
		check(root.get_visible_rect().grow(0.5).encloses(last._panel.get_global_rect()), "same panel fits after resize " + str(size))
		var resize_tabs: TabContainer = scroll.get_parent()
		for tab_index in resize_tabs.get_tab_count():
			resize_tabs.current_tab = tab_index; await frames(3)
			var tab_scroll: ScrollContainer = resize_tabs.get_tab_control(tab_index)
			for control in tab_scroll.find_children("*", "CheckButton", true, false): await check_target(control, size)
			check(tab_scroll.get_h_scroll_bar().max_value <= tab_scroll.get_h_scroll_bar().page + 0.5, "no horizontal overflow after resize " + str(size))
		resize_tabs.current_tab = 1; await frames(3)
	current_case = "saved-aim-final-wheel"
	await nonmutating_scroll(aim, scroll, false)
	last.queue_free(); await frames()
	for path in POSE_PATHS: check(FileAccess.get_file_as_string(path) == POSE_BYTES, "pose fixture remains byte-identical " + path)
	finish()

func check_target(control: Control, size: Vector2i, _toggle := true) -> void:
	var pixels := control.size * Vector2(size) / root.get_visible_rect().size
	check(pixels.x >= 43.9 and pixels.y >= 43.9, "%s target below44px: %s" % [control.name, pixels])
	records.append({"kind": "target", "case": current_case, "name": control.name, "physical_pixels": [pixels.x, pixels.y], "logical_size": str(control.size)})

func slider_cases(slider: HSlider, scroll: ScrollContainer, size: Vector2i) -> void:
	await check_target(slider, size, false)
	slider.value = (slider.min_value + slider.max_value) * 0.5; await frames()
	await nonmutating_scroll(slider, scroll, false)
	await nonmutating_scroll(slider, scroll, true)
	if not slider.editable: return
	scroll.ensure_control_visible(slider); await frames(3)
	var rect := slider.get_global_rect()
	await mouse_tap(rect.position + Vector2(rect.size.x * 0.25, 2))
	check(slider.value < (slider.min_value + slider.max_value) * 0.5, "pointer top edge adjusts " + slider.name)
	await mouse_tap(rect.position + Vector2(rect.size.x * 0.75, rect.size.y - 2))
	check(slider.value > (slider.min_value + slider.max_value) * 0.5, "pointer bottom edge adjusts " + slider.name)
	await mouse_drag(rect.position + Vector2(rect.size.x * 0.25, rect.size.y * 0.5), rect.position + Vector2(rect.size.x * 0.7, rect.size.y * 0.5))
	check(slider.value > (slider.min_value + slider.max_value) * 0.5, "mouse drag adjusts " + slider.name)
	await touch_drag(rect.position + Vector2(rect.size.x * 0.75, rect.size.y * 0.5), rect.position + Vector2(rect.size.x * 0.3, rect.size.y * 0.5))
	check(slider.value < (slider.min_value + slider.max_value) * 0.5, "touch drag adjusts " + slider.name)
	slider.grab_focus()
	var previous := slider.value
	await key(KEY_RIGHT)
	check(is_equal_approx(slider.value, previous + slider.step), "focused Right advances one step " + slider.name)
	await key(KEY_LEFT)
	check(is_equal_approx(slider.value, previous), "focused Left reverses one step " + slider.name)

func nonmutating_scroll(control: Control, scroll: ScrollContainer, pan: bool) -> void:
	scroll.ensure_control_visible(control); await frames(3)
	var before_scroll := scroll.scroll_vertical
	var maximum := scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page
	var direction := 1.0 if before_scroll < maximum - 1 else -1.0
	var before: String = settings._config.encode_to_text()
	var disk := FileAccess.get_file_as_string("user://settings.cfg")
	events.clear()
	await pointer_move(control.get_global_rect().get_center())
	if pan:
		var event := InputEventPanGesture.new(); event.position = control.get_global_rect().get_center(); event.delta = Vector2(0, direction * 2)
		root.push_input(event, true)
	else:
		var event := InputEventMouseButton.new(); event.position = control.get_global_rect().get_center(); event.global_position = event.position
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN if direction > 0 else MOUSE_BUTTON_WHEEL_UP; event.pressed = true
		root.push_input(event, true)
		# Native wheel packets include a release; omitting it leaves GUI capture held.
		event.pressed = false; root.push_input(event, true)
	await frames()
	var kind := "pan" if pan else "wheel"
	check(settings._config.encode_to_text() == before, "%s changes preference over %s" % [kind, control.name])
	check(FileAccess.get_file_as_string("user://settings.cfg") == disk, "%s rewrites saved file over %s" % [kind, control.name])
	check(events.is_empty(), "%s emits preference change over %s" % [kind, control.name])
	if maximum > 1:
		check((scroll.scroll_vertical - before_scroll) * direction > 0, "%s fails to scroll panel over %s (before=%s after=%s)" % [kind, control.name, before_scroll, scroll.scroll_vertical])
	records.append({"kind": kind, "case": current_case, "control": control.name, "scroll_before": before_scroll, "scroll_after": scroll.scroll_vertical, "preference_changes": events.duplicate(true)})

func toggle_cases(control: CheckButton, scroll: ScrollContainer) -> void:
	scroll.ensure_control_visible(control); await frames()
	check(scroll.get_global_rect().grow(0.5).encloses(control.get_global_rect()), "toggle entirely reachable " + control.name)
	await nonmutating_scroll(control, scroll, false)
	scroll.ensure_control_visible(control); await frames()
	var rect := control.get_global_rect()
	for point in [rect.get_center(), rect.position + Vector2(2, 2), rect.end - Vector2(2, 2)]:
		var previous := control.button_pressed
		await mouse_tap(point)
		check(control.button_pressed != previous, "mouse target accepts " + control.name + " " + str(point))
	var previous := control.button_pressed
	await touch_tap(rect.get_center())
	check(control.button_pressed != previous, "touch target accepts " + control.name)
	control.grab_focus(); previous = control.button_pressed
	await key(KEY_SPACE)
	check(control.button_pressed != previous, "keyboard Space toggles " + control.name)

func option_cases(control: OptionButton, scroll: ScrollContainer) -> void:
	scroll.ensure_control_visible(control); await frames()
	await mouse_tap(control.get_global_rect().get_center())
	var popup := control.get_popup()
	check(popup.visible, "pointer opens option selector " + control.name)
	if popup.visible:
		var previous := control.selected
		await key(KEY_ESCAPE)
		check(not popup.visible and control.is_inside_tree(), "Escape dismisses option only " + control.name)
		check(control.selected == previous, "option cancel preserves selection " + control.name)

func keyboard_cases(scroll: ScrollContainer, tabs: TabContainer) -> void:
	scroll.scroll_vertical = 0
	var controls: Array[Control] = []
	for control in scroll.find_children("*", "Control", true, false):
		if (control is Button or control is HSlider) and control.focus_mode != Control.FOCUS_NONE:
			controls.append(control)
	if controls.is_empty(): return
	controls[0].grab_focus(); await frames()
	for index in controls.size() + 2:
		var owner := root.gui_get_focus_owner()
		if owner != null and scroll.is_ancestor_of(owner) and not owner is ScrollBar:
			check(scroll.get_global_rect().grow(0.5).encloses(owner.get_global_rect()), "keyboard focused control is visible " + str(owner.name))
		await key(KEY_TAB)

func pointer_move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new(); event.position = point; event.global_position = point
	root.push_input(event, true); await process_frame

func mouse_button(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new(); event.position = point; event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT; event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0; event.pressed = down
	root.push_input(event, true); await process_frame

func mouse_tap(point: Vector2) -> void:
	await pointer_move(point)
	await mouse_button(point, true); await mouse_button(point, false); await frames()

func mouse_drag(start: Vector2, end: Vector2) -> void:
	await pointer_move(start)
	await mouse_button(start, true)
	var event := InputEventMouseMotion.new(); event.position = end; event.global_position = end; event.relative = end - start; event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true); await process_frame
	await mouse_button(end, false); await frames()

func touch_event(point: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new(); event.index = 0; event.position = root.get_final_transform() * point; event.pressed = down
	Input.parse_input_event(event); await process_frame

func touch_tap(point: Vector2) -> void:
	await touch_event(point, true); await touch_event(point, false); await frames()

func touch_drag(start: Vector2, end: Vector2) -> void:
	await touch_event(start, true)
	var event := InputEventScreenDrag.new(); event.index = 0
	event.position = root.get_final_transform() * end; event.relative = (end - start) * root.get_final_transform().get_scale()
	Input.parse_input_event(event); await process_frame
	await touch_event(end, false); await frames()

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = down
		root.push_input(event, true); await process_frame
	await frames()

func finish() -> void:
	var report := {"scope": "Archived build28 plus cloud candidates; not unavailable Mac30/31 or phone hardware", "mode": mode, "panel_script": panel_script, "checks": checks, "failures": failures, "records": records, "user_data_dir": OS.get_user_data_dir()}
	FileAccess.open(OS.get_environment("SETTINGS_INTERACTION_REPORT"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	for failure in failures: print("FAIL: ", failure)
	print("CLOUD SETTINGS INTERACTION %s: %d checks, %d failures" % [mode, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
