extends CanvasLayer








const Layout = preload("res://scripts/ui/mobile_layout.gd")
const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
var _vbox: VBoxContainer
var _portrait_note: Label
var _panel: Panel
var _closing: = false
var _focus_controls: Dictionary = {}
var _focus_value_labels: Dictionary = {}

func _ready() -> void :
	layer = 101
	# The same overlay opens from the unpaused title and paused gameplay.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	Settings.settings_changed.connect(_on_setting_changed)

func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "video.camera_mode":
		_fit_panel()
	if not _focus_controls.has(key):
		return
	var control: Control = _focus_controls[key]
	if control is HSlider:
		control.set_value_no_signal(float(value))
		_focus_value_labels[key].text = _format_slider_value(control.value, control.step, key)
	elif control is CheckButton:
		control.set_pressed_no_signal(bool(value))
	elif control is OptionButton:
		control.select(clampi(int(value), 0, control.item_count - 1))

func _build() -> void :

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)


	var panel: Panel = Panel.new()
	_panel = panel
	panel.theme = UiTheme.create()
	UiTheme.crisp(panel)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	get_viewport().size_changed.connect(_fit_panel)
	_fit_panel()
	panel.add_theme_stylebox_override("panel", _panel_stylebox())
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	_vbox = vbox
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 32
	vbox.offset_top = 32
	vbox.offset_right = -32
	vbox.offset_bottom = -32
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)


	var header: HBoxContainer = HBoxContainer.new()
	vbox.add_child(header)

	var title: Label = Label.new()
	title.text = "Settings"
	UiTheme.use_pixel(title, 27)
	title.add_theme_color_override("font_color", UiTheme.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn: Button = Button.new()
	close_btn.text = "Back"
	close_btn.custom_minimum_size = Vector2(88, 44)
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.pressed.connect(_on_close)
	header.add_child(close_btn)
	close_btn.grab_focus()


	var tabs: TabContainer = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 22)
	vbox.add_child(tabs)

	tabs.add_child(_build_video_tab())
	tabs.add_child(_build_gameplay_tab())
	tabs.add_child(_build_audio_tab())
	tabs.add_child(_build_beta_debug_tab())
	_portrait_note = Label.new()
	_portrait_note.text = "Camera framing adapts to keep the ball visible. POV locks the ball at screen center."
	_portrait_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_portrait_note.add_theme_font_size_override("font_size", 16)
	_portrait_note.add_theme_color_override("font_color", UiTheme.MUTED)
	vbox.add_child(_portrait_note)
	var footnote: = Label.new()
	footnote.name = "SettingsFootnote"
	footnote.text = "Changes save automatically · Back returns to the previous screen"
	footnote.add_theme_font_size_override("font_size", 14)
	footnote.add_theme_color_override("font_color", UiTheme.MUTED)
	footnote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(footnote)
	_fit_panel()



func _build_video_tab() -> ScrollContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Video"
	scroll.follow_focus = true
	var v: VBoxContainer = _inner_vbox()
	scroll.add_child(v)

	_option_row(v, "Camera perspective", "video.camera_mode", ["Center + serve", "Third person", "POV: ball lock"])
	var camera_note: = Label.new()
	camera_note.text = "Center + serve: behind Blue for your serve until contact, then back to center. Stays centered on Blue’s side when Red serves. Third person follows Blue throughout play. POV uses Blue’s eyes and keeps the ball centered; the local body is hidden for a clear view. Shake applies to the center view only."
	camera_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	camera_note.add_theme_font_size_override("font_size", 16)
	camera_note.add_theme_color_override("font_color", UiTheme.MUTED)
	v.add_child(camera_note)
	_slider_row(v, "Center Field of View", "video.fov", 50.0, 90.0, 1.0)
	_slider_row(v, "Camera Shake", "video.shake", 0.0, 1.5, 0.05)
	_build_focus_visuals(v)
	_checkbox_row(v, "Hitstop on strong hits", "video.hitstop")
	_option_row(v, "Particle Density", "video.particle_density", 
		["Off", "Low", "Medium", "High"])
	_option_row(v, "Shadow Quality", "video.shadow_quality", 
		["Off", "Low", "High"])
	return scroll

func _build_focus_visuals(parent: VBoxContainer) -> void:
	var group: = VBoxContainer.new()
	group.name = "SlowMotionVisuals"
	group.add_theme_constant_override("separation", 12)
	parent.add_child(group)
	var title: = Label.new()
	title.text = "Slow-motion visuals"
	UiTheme.use_pixel(title, 18)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	group.add_child(title)
	_slider_row(group, "Screen dimming", "video.focus_dim", 0.0, 0.35, 0.01)
	_slider_row(group, "Blur strength", "video.focus_blur", 0.0, 1.5, 0.05)
	_checkbox_row(group, "Show shot preview", "video.focus_preview")
	_option_row(group, "Arc style", "video.focus_arc_style", ["Steady dashed", "Solid"])
	var note: = Label.new()
	note.text = "Dimming and blur apply during solo aim slow motion. Set either to 0 to turn it off. The shot preview shows an estimated arc and landing area."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", UiTheme.MUTED)
	group.add_child(note)
	var reset: = Button.new()
	reset.name = "ResetFocusVisuals"
	reset.text = "Reset slow-motion visuals"
	reset.add_theme_font_size_override("font_size", 18)
	reset.custom_minimum_size.y = 44
	reset.tooltip_text = "Restore dimming, blur, shot preview and arc style only"
	reset.pressed.connect(Settings.reset_focus_visuals)
	group.add_child(reset)



func _build_gameplay_tab() -> ScrollContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Gameplay"
	scroll.follow_focus = true
	var v: VBoxContainer = _inner_vbox()
	scroll.add_child(v)

	var stamina_note := Label.new()
	stamina_note.text = "Stamina · Standard gameplay\nBoth players: 100 stamina. Drives and fast travel cost more; soft resets create time to recover. Rest recovers 7/s after a short breathing delay (0.8 s hard shots, 0.2 s soft shots). Below 25, running gradually slows by up to 15%. Contact timing, aim accuracy and shot power stay unchanged. Prototype tuning."
	stamina_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stamina_note.add_theme_font_size_override("font_size", 16)
	v.add_child(stamina_note)
	_option_row(v, "AI Difficulty", "gameplay.difficulty", 
		["Easy", "Medium", "Hard"])
	var style_options: Array = preload("res://scripts/ai_playing_styles.gd").NAMES
	_option_row(v, "Partner style (doubles)", "gameplay.ai_style_partner", style_options)
	_option_row(v, "Opponent 1 style", "gameplay.ai_style_opponent_one", style_options)
	_option_row(v, "Opponent 2 style (doubles)", "gameplay.ai_style_opponent_two", style_options)
	var style_note := Label.new()
	style_note.text = "Style changes shot preferences and court positioning. Difficulty separately controls skill and reaction. Styles choose only situationally suitable shots; committed shots finish with their original plan. Each player keeps an independent style."
	style_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	style_note.add_theme_font_size_override("font_size", 16)
	style_note.add_theme_color_override("font_color", UiTheme.MUTED)
	v.add_child(style_note)
	_option_row(v, "Shot accuracy", "gameplay.execution_accuracy", ["Perfect training", "Realistic execution"])
	var accuracy_note := Label.new()
	accuracy_note.text = "Realistic execution adds a small one-time shot variation. Late, off-center, moving and stretched contacts are less precise. The same model applies to AI: Easy has more variation, Hard less. Perfect training removes random execution error; contact, reach, rules and physical edge effects still apply. The aiming area is an estimate, not a guaranteed landing."
	accuracy_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	accuracy_note.add_theme_font_size_override("font_size", 16)
	accuracy_note.add_theme_color_override("font_color", UiTheme.MUTED)
	v.add_child(accuracy_note)
	_slider_row(v, "Extra AI reaction delay (s)", "gameplay.reaction_delay", 0.0, 0.5, 0.02)
	_checkbox_row(v, "Reaction Hit Button (Easy mode)", "gameplay.reaction_button")
	_checkbox_row(v, "Vibrate when release is ready", "gameplay.timing_vibration")
	_slider_row(v, "Rally aim window (real seconds)", "gameplay.aim_focus_seconds", 1.0, 5.0, 0.5)
	_checkbox_row(v, "Incoming movement guide", "gameplay.movement_guide")
	_option_row(v, "Between points (next finalized point)", "gameplay.point_transition", ["Physical pickup", "Quick reset"])
	var movement_note := Label.new()
	movement_note.text = "MOVE marks a legal target with time to move. TIGHT means little or uncertain time. NO TIME means the predicted legal flight cannot be reached in time. The guide never moves your player."
	movement_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	movement_note.add_theme_font_size_override("font_size", 16)
	movement_note.add_theme_color_override("font_color", UiTheme.MUTED)
	v.add_child(movement_note)
	var note: = Label.new()
	note.text = "Solo aim slow motion starts when reachable aiming locks in. The real-time countdown keeps running if you leave reach, and a new incoming shot gets a fresh window. Hit ring closes as contact approaches. Green RELEASE and one short vibration mark a reachable release window, not a guaranteed hit. Amber MOVE CLOSER means the ball is still out of reach. Vibration requires a supported phone."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", UiTheme.MUTED)
	v.add_child(note)
	return scroll



func _build_audio_tab() -> ScrollContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Audio"
	scroll.follow_focus = true
	var v: VBoxContainer = _inner_vbox()
	scroll.add_child(v)

	_slider_row(v, "Master Volume", "audio.master", 0.0, 1.0, 0.01)
	_slider_row(v, "Ball & Point Cues", "audio.sfx", 0.0, 1.0, 0.01)
	_slider_row(v, "Court Ambience", "audio.ambience", 0.0, 1.0, 0.01)
	_slider_row(v, "Footsteps & Squeaks", "audio.footsteps", 0.0, 1.0, 0.01)
	var note: = Label.new()
	note.text = "Set a level to 0 to mute it. Court audio pauses with the game."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", UiTheme.MUTED)
	v.add_child(note)
	return scroll


func _build_beta_debug_tab() -> ScrollContainer:
	var scroll: = ScrollContainer.new()
	scroll.name = "Beta debug"
	scroll.follow_focus = true
	var v: = _inner_vbox()
	scroll.add_child(v)
	_checkbox_row(v, "Show reach rings", "beta_debug.reach_rings")
	_checkbox_row(v, "Show preparation blocks", "beta_debug.preparation_blocks")
	var note: = Label.new()
	note.text = "BLUE PLAYER REACH\n\nInner cyan ring: normal reach guide.\nOuter ring: wider and extended reach guide.\n\nThe outer ring glows amber when a valid longer contact is planned. A bright arc points toward that contact.\n\nThese are ground guides. Ball height, angle, bounce rules and swing timing still determine the hit.\n\nPREPARATION BLOCKS\n\nEight colored outer blocks suggest low, mid, high or overhead preparation while Hit is held. Gray zones show the existing preparation areas.\n\nThe low display reaches the floor, but actual paddle/floor clearance is unchanged. These blocks never grant extra reach or hit permission."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 18)
	note.add_theme_color_override("font_color", UiTheme.MUTED)
	v.add_child(note)
	return scroll



func _inner_vbox() -> VBoxContainer:
	var v: VBoxContainer = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 22)
	v.offset_left = 12
	v.offset_top = 16
	v.offset_right = -12
	v.offset_bottom = -12
	return v

func _slider_row(parent: Node, label_text: String, key: String, vmin: float, vmax: float, step: float, on_change: Callable = Callable()) -> void :
	var row: VBoxContainer = VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var header: HBoxContainer = HBoxContainer.new()
	row.add_child(header)

	var lbl: Label = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_bold(lbl, 600)
	header.add_child(lbl)

	var value_lbl: Label = Label.new()
	value_lbl.add_theme_font_size_override("font_size", 20)
	value_lbl.add_theme_color_override("font_color", UiTheme.ACCENT)
	_apply_bold(value_lbl, 700)
	header.add_child(value_lbl)

	var slider: HSlider = HSlider.new()
	# Wheel/trackpad scrolling should navigate the panel, never save a value.
	# Native pointer/touch dragging and focused keyboard arrows remain enabled.
	slider.scrollable = false
	slider.min_value = vmin
	slider.max_value = vmax
	slider.step = step
	slider.name = key.replace(".", "_")
	slider.value = Settings.get_value(key)
	slider.custom_minimum_size = Vector2(0, 52)
	row.add_child(slider)

	value_lbl.text = _format_slider_value(slider.value, step, key)
	if key in Settings.FOCUS_VISUAL_KEYS:
		_focus_controls[key] = slider
		_focus_value_labels[key] = value_lbl
	slider.value_changed.connect( func(v: float) -> void :
		Settings.set_value(key, v)
		value_lbl.text = _format_slider_value(v, step, key)
		if on_change.is_valid():
			on_change.call(key, v)
	)

func _format_slider_value(v: float, step: float, key: String = "") -> String:
	if key == "video.focus_dim":
		return "%d%%" % roundi(v * 100.0)
	if step >= 1.0:
		return str(int(round(v)))
	if step >= 0.1:
		return "%.1f" % v
	return "%.2f" % v

func _checkbox_row(parent: Node, label_text: String, key: String) -> void :
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)

	var lbl: Label = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_bold(lbl, 600)
	row.add_child(lbl)

	var cb: CheckButton = CheckButton.new()
	cb.name = key.replace(".", "_")
	cb.button_pressed = bool(Settings.get_value(key))
	if key in Settings.FOCUS_VISUAL_KEYS or key == "gameplay.movement_guide":
		_focus_controls[key] = cb
	cb.add_theme_font_size_override("font_size", 24)
	cb.toggled.connect( func(on: bool) -> void :
		Settings.set_value(key, on)
	)
	row.add_child(cb)

func _option_row(parent: Node, label_text: String, key: String, options: Array) -> void :
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)

	var lbl: Label = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_bold(lbl, 600)
	row.add_child(lbl)

	var opt: OptionButton = OptionButton.new()
	opt.add_theme_font_size_override("font_size", 20)
	opt.custom_minimum_size = Vector2(190, 44)
	for i in range(options.size()):
		opt.add_item(str(options[i]), i)
	opt.name = key.replace(".", "_")
	opt.select(clampi(int(Settings.get_value(key)), 0, options.size() - 1))
	opt.item_selected.connect( func(i: int) -> void :
		Settings.set_value(key, i)
	)
	row.add_child(opt)
	_style_option_popup(opt.get_popup())
	if key == "video.focus_arc_style": _focus_controls[key] = opt



func _style_option_popup(popup: PopupMenu) -> void:
	# Local PopupMenu colors; preserve its padding, row sizing and input behavior.
	var popup_panel: StyleBoxFlat = popup.get_theme_stylebox("panel").duplicate()
	popup_panel.bg_color = UiTheme.PANEL
	popup_panel.border_color = UiTheme.BORDER
	popup.add_theme_stylebox_override("panel", popup_panel)
	var highlight: StyleBoxFlat = popup.get_theme_stylebox("hover").duplicate()
	highlight.bg_color = UiTheme.SURFACE
	highlight.border_color = UiTheme.ACCENT
	popup.add_theme_stylebox_override("hover", highlight)
	popup.add_theme_color_override("font_color", UiTheme.INK)
	popup.add_theme_color_override("font_hover_color", UiTheme.ACCENT)
	popup.add_theme_color_override("font_disabled_color", UiTheme.MUTED)

func _panel_stylebox() -> StyleBoxFlat:
	return UiTheme.panel_style()

func _apply_bold(ctrl: Control, weight: int = 700) -> void :
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray([
		"SF Pro Display", "Helvetica Neue", "Inter", "Roboto", "Segoe UI", "Arial", "sans-serif", 
	])
	font.font_weight = weight
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	ctrl.add_theme_font_override("font", font)

func _on_dim_input(event: InputEvent) -> void :
	if event is InputEventMouseButton and event.pressed:

		_on_close()

func _unhandled_input(event: InputEvent) -> void :
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close()
		get_viewport().set_input_as_handled()

func _on_close() -> void :
	if _closing: return
	_closing = true
	if has_meta("on_close"):
		var cb: Callable = get_meta("on_close")
		if cb.is_valid():
			cb.call()
	queue_free()

func _fit_panel() -> void :
	if _panel == null:
		return
	var viewport_size: = get_viewport().get_visible_rect().size
	var portrait: = Layout.is_portrait(viewport_size)
	# Convert the physical 44-pixel target into the stretched canvas coordinates.
	var window_size := Vector2(get_window().size).max(Vector2.ONE)
	var minimum_touch := (Vector2(44, 44) * viewport_size / window_size).ceil()
	# Landscape uses physical-pixel sizing; the authored portrait canvas may be
	# scaled down substantially in a wide window. Preserve portrait typography.
	var s: = Layout.scale_for(viewport_size) if portrait else viewport_size.y / window_size.y
	var safe: = Layout.safe_rect(get_viewport())
	var half_size: = Vector2(minf(760 * s, safe.size.x - 48 * s), minf((1120 if portrait else 700) * s, safe.size.y - 48 * s)) * 0.5
	var center: = safe.get_center() - viewport_size * 0.5
	_panel.offset_left = center.x - half_size.x
	_panel.offset_right = center.x + half_size.x
	_panel.offset_top = center.y - half_size.y
	_panel.offset_bottom = center.y + half_size.y
	if _vbox == null: return
	_vbox.offset_left = 28 * s
	_vbox.offset_right = -28 * s
	_vbox.offset_top = 28 * s
	_vbox.offset_bottom = -28 * s
	if _portrait_note: _portrait_note.visible = portrait
	for control in _panel.find_children("*", "Control", true, false):
		if not control.has_meta("base_font_size"):
			control.set_meta("base_font_size", control.get_theme_font_size("font_size"))
		var base: int = control.get_meta("base_font_size", 20)
		control.add_theme_font_size_override("font_size", maxi(12, roundi(base * (1.25 if portrait else 1.0) * s)))
		if control is HSlider:
			control.custom_minimum_size.y = maxf((96 if portrait else 52) * s, minimum_touch.y)
			if control.name == "video_fov":
				control.editable = not portrait and int(Settings.get_value("video.camera_mode", 0)) == 0
				control.modulate.a = 1.0 if control.editable else 0.4
				control.tooltip_text = "Centered landscape field of view; close and portrait views frame automatically"
		elif control is Button:
			control.custom_minimum_size.y = maxf((96 if portrait else 44) * s, minimum_touch.y)
			if control is CheckButton:
				control.custom_minimum_size.x = minimum_touch.x
			else:
				if not control.has_meta("base_minimum_width"):
					control.set_meta("base_minimum_width", control.custom_minimum_size.x)
				control.custom_minimum_size.x = maxf(float(control.get_meta("base_minimum_width")), minimum_touch.x)
			if control is OptionButton:
				control.custom_minimum_size.x = 190 * s
				var popup: PopupMenu = control.get_popup()
				# Popups are separate windows: match readable text and touch rows
				# without changing the closed control or portrait panel geometry.
				var popup_font_size: int = maxi(control.get_theme_font_size("font_size"), ceili(16 * viewport_size.y / window_size.y))
				popup.add_theme_font_size_override("font_size", popup_font_size)
				var line_height: float = popup.get_theme_font("font").get_height(popup_font_size)
				popup.add_theme_constant_override("v_separation", maxi(4, ceili(minimum_touch.y - line_height)))
		elif control is TabContainer:
			for key in ["tab_selected", "tab_unselected", "tab_hovered"]:
				var style: = UiTheme.button_style(UiTheme.SURFACE if key == "tab_selected" else UiTheme.PANEL)
				style.content_margin_top = (32 if portrait else 10) * s
				style.content_margin_bottom = (32 if portrait else 10) * s
				control.add_theme_stylebox_override(key, style)
