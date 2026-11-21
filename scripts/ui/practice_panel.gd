extends CanvasLayer

const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
const Layout = preload("res://scripts/ui/mobile_layout.gd")
var _game: Node
var _panel: PanelContainer
var _margin: MarginContainer
var _content: VBoxContainer
var _scroll: ScrollContainer
var _picker_open: = false
var _picker_generation: = 0
var _shown_result: = false
var _first_button: Button

func setup(game: Node) -> void :
	_game = game
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim: = ColorRect.new()
	dim.color = Color(0.015, 0.035, 0.05, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.theme = UiTheme.create()
	UiTheme.crisp(_panel)
	var style: = UiTheme.panel_style()
	for side in ["left", "top", "right", "bottom"]: style.set("content_margin_" + side, 0.0)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var margin: = MarginContainer.new()
	_margin = margin
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	_panel.add_child(margin)
	var scroll: = ScrollContainer.new()
	_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	scroll.add_child(_content)
	get_viewport().size_changed.connect(_fit)
	hide()

func _clear() -> void :
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_first_button = null

func _label(text: String, size: int, color: Color = UiTheme.INK, pixel: bool = false) -> void :
	var label: = Label.new()
	label.text = text
	label.set_meta("font_size", size)
	label.set_meta("pixel", pixel)
	if pixel: label.add_theme_font_override("font", UiTheme.pixel_font())
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	_content.add_child(label)

func _button(text: String, action: Callable) -> Button:
	var button: = Button.new()
	button.text = text
	button.clip_text = true
	button.custom_minimum_size.y = 48
	button.pressed.connect(action)
	_content.add_child(button)
	if _first_button == null: _first_button = button
	return button

func open_practice() -> void :
	if _picker_open or _game._tool_state_active(): return
	_game.mobile_controls.cancel_all()
	_game.input_handler.cancel_charge_input()
	var pause = get_node("/root/PauseController")
	pause.open()
	_picker_open = true
	_picker_generation += 1
	_shown_result = false
	_clear()
	_label("PRACTICE · NO SCORE", 15, UiTheme.ACCENT, true)
	_label("Find your rhythm", 27, UiTheme.INK, true)
	_label("Unscored practice. Exchange drills begin after the opening bounces. Your match score is kept. Pause to repeat, switch or return.", 16, UiTheme.MUTED)
	if _game.practice_launcher.is_wall():
		_button("Reset wall ball", _repeat)
		_button("Return to match", _return_to_match)
	_button("Wall Practice · solo rebound court", _start.bind("WALL"))
	for mode in ["SERVE", "DRIVE", "RETURN", "DINK", "HANDS"]:
		var caption: String = {"SERVE": "Serve placement", "DRIVE": "Baseline drive", "RETURN": "Serve return", "DINK": "Live crosscourt dinking", "HANDS": "Kitchen-line fast hands"}[mode]
		_button(caption, _start.bind(mode))
	_button("Watch crosscourt dink demo", _start_demo.bind("DINK"))
	_button("Watch fast-hands demo", _start_demo.bind("HANDS"))
	_button("Watch wide-dink recovery demo", _start_wide_demo)
	_button("Watch pop-up attack and reset demo", _start_attack_demo)
	if _game.practice_launcher.is_active:
		if _game.practice_launcher.drill_mode == "DINK":
			_button("Allow pop-up attacks: " + ("ON" if _game.practice_launcher.allow_attacks else "OFF"), _toggle_attacks)
			_button("Reverse diagonal and repeat", _reverse_diagonal)
		if not _game.practice_launcher.is_wall():
			_button("Repeat current drill", _repeat)
			_button("Return to match", _return_to_match)
	_button("Back", close_picker)
	show()
	_fit()
	_first_button.grab_focus()

func close_picker() -> void :
	if not _picker_open: return
	_picker_open = false
	_picker_generation += 1
	hide()
	var pause = get_node("/root/PauseController")
	if is_instance_valid(pause._menu): pause._menu._resume_button.grab_focus()

func _start(mode: String) -> void :
	if not _picker_open: return
	close_picker()
	_game.practice_launcher.start_drill(mode)
	get_node("/root/PauseController").close()

func _repeat() -> void :
	if not _picker_open: return
	close_picker()
	_game.practice_launcher.repeat_drill()
	get_node("/root/PauseController").close()

func _return_to_match() -> void :
	if not _picker_open: return
	close_picker()
	_game.practice_launcher.stop_practice()
	get_node("/root/PauseController").close()

func _rematch() -> void :
	if not _game.match_over: return
	_game.request_rematch()
	_shown_result = false
	hide()

func _process(_delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_process(_delta)
	PerfMonitor.record("proc.practice_panel", Time.get_ticks_usec() - _pt)

func _perf_process(_delta: float) -> void:
	if _game == null or _picker_open: return
	var show_result: bool = _game.match_over and not get_tree().paused and not _game._tool_state_active()
	if show_result and not _shown_result:
		_clear()
		_label("MATCH COMPLETE", 15, UiTheme.ACCENT, true)
		var doubles: bool = _game.get("doubles_mode") == true
		_label(("Your team wins!" if doubles else "You win!") if _game.match_winner == 0 else ("The other team wins this one" if doubles else "AI wins this one"), 30, UiTheme.INK, true)
		_label("%d – %d" % [_game.score_left, _game.score_right], 40, UiTheme.GOLD, true)
		var target: int = int(_game.doubles_state.target_score) if doubles and _game.get("doubles_state") != null else 11
		_label("%s · first to %d, win by 2" % ["Doubles" if doubles else "Singles", target], 16, UiTheme.MUTED)
		_button("Rematch", _rematch)
		_button("Practice drills", open_practice)
		_shown_result = true
		show()
		_fit()
		_first_button.grab_focus()
	elif not show_result:
		_shown_result = false
		hide()

func _fit() -> void :
	if _panel == null: return
	var size: Vector2 = get_viewport().get_visible_rect().size
	var safe: Rect2 = Layout.safe_rect(get_viewport())
	var portrait: bool = Layout.is_portrait(size)
	# Landscape must size against window pixels, not the stretched portrait canvas.
	var scale: float = Layout.scale_for(size) if portrait else size.y / maxf(1.0, get_window().size.y)
	_scroll.follow_focus = not portrait
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS if portrait else Control.MOUSE_FILTER_STOP
	var desired_height: float = (1020.0 if _game.practice_launcher.is_active else 800.0) if _picker_open else 640.0
	if not portrait: desired_height = (640.0 if _game.practice_launcher.is_active else 500.0) if _picker_open else 360.0
	_panel.size = Vector2(minf((660.0 if portrait else 460.0) * scale, safe.size.x - 24.0 * scale), minf(desired_height * scale, safe.size.y - 32.0 * scale))
	_panel.position = safe.position + (safe.size - _panel.size) * 0.5
	for side in ["left", "top", "right", "bottom"]: _margin.add_theme_constant_override("margin_" + side, int(24 * scale))
	_content.add_theme_constant_override("separation", int(16 * scale))
	for widget in _content.get_children():
		if widget is Button:
			# Landscape drags bubble to the scroll viewport, which consumes them.
			widget.mouse_filter = Control.MOUSE_FILTER_STOP if portrait else Control.MOUSE_FILTER_PASS
			widget.custom_minimum_size.y = (96.0 if portrait else 48.0) * scale
			widget.add_theme_font_size_override("font_size", UiTheme.pixel_size(27 * scale) if portrait else UiTheme.pixel_size(18 * scale))
		elif widget is Label:
			var font_size: float = widget.get_meta("font_size", 16)
			var px: float = font_size * 1.35 * scale if portrait else maxf(16.0, font_size) * scale
			widget.add_theme_font_size_override("font_size", UiTheme.pixel_size(px) if widget.get_meta("pixel", false) else int(px))

func _input(event: InputEvent) -> void :
	if _picker_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_picker()
		get_viewport().set_input_as_handled()

func _start_demo(mode: String) -> void :
	if not _picker_open: return
	close_picker()
	_game.practice_launcher.start_drill(mode, true, 1, "WIDE" if mode == "DINK" else "STANDARD")
	get_node("/root/PauseController").close()

func _start_wide_demo() -> void :
	if not _picker_open: return
	close_picker()
	_game.practice_launcher.start_drill("DINK", true, 1, "WIDE")
	get_node("/root/PauseController").close()

func _toggle_attacks() -> void :
	if not _picker_open: return
	_game.practice_launcher.set_allow_attacks( not _game.practice_launcher.allow_attacks)
	# The pressed control must stay alive until its input dispatch completes.
	_refresh_attack_picker.call_deferred(_picker_generation)

func _refresh_attack_picker(generation: int) -> void:
	# A newer open/close session owns its own controls and focus. Rapid toggles
	# update the value immediately; only the first valid refresh rebuilds the UI.
	if not is_inside_tree() or is_queued_for_deletion() or not _picker_open or generation != _picker_generation: return
	close_picker()
	open_practice()

func _reverse_diagonal() -> void :
	if not _picker_open: return
	close_picker()
	_game.practice_launcher.diagonal *= -1
	_game.practice_launcher.repeat_drill()
	get_node("/root/PauseController").close()

func _start_attack_demo() -> void :
	if not _picker_open: return
	close_picker()
	_game.practice_launcher.start_drill("DINK", true, 1, "ATTACK")
	get_node("/root/PauseController").close()
