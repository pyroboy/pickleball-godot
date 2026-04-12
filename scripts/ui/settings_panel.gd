extends CanvasLayer
## Settings panel overlay — tabbed UI (Video / Gameplay / Audio).
## Binds bidirectionally to the Settings autoload and fires settings_changed
## when values change. Consumers (CameraRig, HitFeedback, FXPool, AudioServer)
## read the current values on each event; no explicit plumbing needed here.
##
## Lifecycle: instantiated by pause_menu.gd. Closes itself on the X button
## (or on Esc handled here). Fires meta "on_close" callback when closing.

func _ready() -> void:
	layer = 101
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build()

func _build() -> void:
	# Dim background
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	# Panel
	var panel: Panel = Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -420
	panel.offset_top = -620
	panel.offset_right = 420
	panel.offset_bottom = 620
	panel.add_theme_stylebox_override("panel", _panel_stylebox())
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 32
	vbox.offset_top = 32
	vbox.offset_right = -32
	vbox.offset_bottom = -32
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)

	# Header row: title + close
	var header: HBoxContainer = HBoxContainer.new()
	vbox.add_child(header)

	var title: Label = Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color.WHITE)
	_apply_bold(title, 800)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn: Button = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(72, 72)
	close_btn.add_theme_font_size_override("font_size", 36)
	_apply_bold(close_btn, 700)
	close_btn.add_theme_stylebox_override("normal", _btn_style(Color(0.25, 0.10, 0.14, 1.0)))
	close_btn.add_theme_stylebox_override("hover", _btn_style(Color(0.45, 0.15, 0.20, 1.0)))
	close_btn.add_theme_stylebox_override("pressed", _btn_style(Color(0.18, 0.08, 0.10, 1.0)))
	close_btn.pressed.connect(_on_close)
	header.add_child(close_btn)

	# Tab container
	var tabs: TabContainer = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 28)
	vbox.add_child(tabs)

	tabs.add_child(_build_video_tab())
	tabs.add_child(_build_gameplay_tab())
	tabs.add_child(_build_audio_tab())

# ── Video tab ────────────────────────────────────────────────────────────────

func _build_video_tab() -> ScrollContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Video"
	var v: VBoxContainer = _inner_vbox()
	scroll.add_child(v)

	_slider_row(v, "Field of View", "video.fov", 50.0, 90.0, 1.0)
	_slider_row(v, "Camera Shake", "video.shake", 0.0, 1.5, 0.05)
	_checkbox_row(v, "Hitstop on strong hits", "video.hitstop")
	_option_row(v, "Particle Density", "video.particle_density",
		["Off", "Low", "Medium", "High"])
	_option_row(v, "Shadow Quality", "video.shadow_quality",
		["Off", "Low", "High"])
	return scroll

# ── Gameplay tab ─────────────────────────────────────────────────────────────

func _build_gameplay_tab() -> ScrollContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Gameplay"
	var v: VBoxContainer = _inner_vbox()
	scroll.add_child(v)

	_option_row(v, "AI Difficulty", "gameplay.difficulty",
		["Easy", "Medium", "Hard"])
	_slider_row(v, "AI Reaction Delay (s)", "gameplay.reaction_delay", 0.0, 0.5, 0.02)
	_checkbox_row(v, "Reaction Hit Button (Easy mode)", "gameplay.reaction_button")
	return scroll

# ── Audio tab ────────────────────────────────────────────────────────────────

func _build_audio_tab() -> ScrollContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Audio"
	var v: VBoxContainer = _inner_vbox()
	scroll.add_child(v)

	_slider_row(v, "Master Volume", "audio.master", 0.0, 1.0, 0.02,
		Callable(self, "_apply_audio_bus").bind("Master"))
	_slider_row(v, "SFX Volume", "audio.sfx", 0.0, 1.0, 0.02,
		Callable(self, "_apply_audio_bus").bind("SFX"))
	_slider_row(v, "Music Volume", "audio.music", 0.0, 1.0, 0.02,
		Callable(self, "_apply_audio_bus").bind("Music"))
	return scroll

func _apply_audio_bus(_key: String, value: float, bus_name: String) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var db: float = linear_to_db(maxf(value, 0.0001))
	AudioServer.set_bus_volume_db(idx, db)

# ── Row builders ─────────────────────────────────────────────────────────────

func _inner_vbox() -> VBoxContainer:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	v.offset_left = 12
	v.offset_top = 16
	v.offset_right = -12
	v.offset_bottom = -12
	return v

func _slider_row(parent: Node, label_text: String, key: String, vmin: float, vmax: float, step: float, on_change: Callable = Callable()) -> void:
	var row: VBoxContainer = VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var header: HBoxContainer = HBoxContainer.new()
	row.add_child(header)

	var lbl: Label = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_bold(lbl, 600)
	header.add_child(lbl)

	var value_lbl: Label = Label.new()
	value_lbl.add_theme_font_size_override("font_size", 26)
	value_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	_apply_bold(value_lbl, 700)
	header.add_child(value_lbl)

	var slider: HSlider = HSlider.new()
	slider.min_value = vmin
	slider.max_value = vmax
	slider.step = step
	slider.value = Settings.get_value(key, (vmin + vmax) * 0.5)
	slider.custom_minimum_size = Vector2(0, 52)
	row.add_child(slider)

	value_lbl.text = _format_slider_value(slider.value, step)
	slider.value_changed.connect(func(v: float) -> void:
		Settings.set_value(key, v)
		value_lbl.text = _format_slider_value(v, step)
		if on_change.is_valid():
			on_change.call(key, v)
	)

func _format_slider_value(v: float, step: float) -> String:
	if step >= 1.0:
		return str(int(round(v)))
	if step >= 0.1:
		return "%.1f" % v
	return "%.2f" % v

func _checkbox_row(parent: Node, label_text: String, key: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)

	var lbl: Label = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_bold(lbl, 600)
	row.add_child(lbl)

	var cb: CheckButton = CheckButton.new()
	cb.button_pressed = bool(Settings.get_value(key, true))
	cb.add_theme_font_size_override("font_size", 24)
	cb.toggled.connect(func(on: bool) -> void:
		Settings.set_value(key, on)
	)
	row.add_child(cb)

func _option_row(parent: Node, label_text: String, key: String, options: Array) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)

	var lbl: Label = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_bold(lbl, 600)
	row.add_child(lbl)

	var opt: OptionButton = OptionButton.new()
	opt.add_theme_font_size_override("font_size", 26)
	opt.custom_minimum_size = Vector2(220, 56)
	for i in range(options.size()):
		opt.add_item(str(options[i]), i)
	opt.select(clampi(int(Settings.get_value(key, 0)), 0, options.size() - 1))
	opt.item_selected.connect(func(i: int) -> void:
		Settings.set_value(key, i)
	)
	row.add_child(opt)

# ── Style + font helpers ─────────────────────────────────────────────────────

func _panel_stylebox() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.13, 0.98)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 22
	sb.corner_radius_top_right = 22
	sb.corner_radius_bottom_left = 22
	sb.corner_radius_bottom_right = 22
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 16
	return sb

func _btn_style(bg: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

func _apply_bold(ctrl: Control, weight: int = 700) -> void:
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray([
		"SF Pro Display", "Helvetica Neue", "Inter", "Roboto", "Segoe UI", "Arial", "sans-serif",
	])
	font.font_weight = weight
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	ctrl.add_theme_font_override("font", font)

func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# Clicking the dim background closes settings
		_on_close()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close()
		get_viewport().set_input_as_handled()

func _on_close() -> void:
	if has_meta("on_close"):
		var cb: Callable = get_meta("on_close")
		if cb.is_valid():
			cb.call()
	queue_free()
