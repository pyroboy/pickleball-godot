extends CanvasLayer
## Pause menu overlay — dimmed background + centered panel with buttons.
## Lifecycle owned by PauseController autoload (which queue_frees this node).
##
## Buttons: Resume / Settings / Quit
## Settings opens SettingsPanel as a child overlay on top of this one.

const SettingsPanelScript = preload("res://scripts/ui/settings_panel.gd")

var _panel: Panel
var _settings_overlay: Node = null

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build()

func _build() -> void:
	# Full-screen dim
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# Centered panel
	_panel = Panel.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -280
	_panel.offset_top = -340
	_panel.offset_right = 280
	_panel.offset_bottom = 340
	_panel.add_theme_stylebox_override("panel", _panel_stylebox())
	add_child(_panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 36
	vbox.offset_top = 36
	vbox.offset_right = -36
	vbox.offset_bottom = -36
	vbox.add_theme_constant_override("separation", 24)
	_panel.add_child(vbox)

	var title: Label = Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	_apply_bold(title)
	vbox.add_child(title)

	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	_add_button(vbox, "Resume", Callable(self, "_on_resume"))
	_add_button(vbox, "Settings", Callable(self, "_on_settings"))
	_add_button(vbox, "Quit to Desktop", Callable(self, "_on_quit"))

func _panel_stylebox() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.14, 0.96)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 24
	sb.corner_radius_top_right = 24
	sb.corner_radius_bottom_left = 24
	sb.corner_radius_bottom_right = 24
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 18
	return sb

func _button_style(bg: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	return sb

func _add_button(parent: Node, text: String, cb: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 80)
	b.add_theme_font_size_override("font_size", 34)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.85, 0.92, 1.0, 1.0))
	b.add_theme_stylebox_override("normal", _button_style(Color(0.14, 0.18, 0.28, 1.0)))
	b.add_theme_stylebox_override("hover", _button_style(Color(0.22, 0.32, 0.52, 1.0)))
	b.add_theme_stylebox_override("pressed", _button_style(Color(0.10, 0.13, 0.20, 1.0)))
	b.add_theme_stylebox_override("focus", _button_style(Color(0.18, 0.24, 0.40, 1.0)))
	_apply_bold(b)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _apply_bold(ctrl: Control) -> void:
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray([
		"SF Pro Display", "Helvetica Neue", "Inter", "Roboto", "Segoe UI", "Arial", "sans-serif",
	])
	font.font_weight = 800
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	ctrl.add_theme_font_override("font", font)

func _on_resume() -> void:
	var ctrl = get_meta("controller") if has_meta("controller") else null
	if ctrl != null and ctrl.has_method("close"):
		ctrl.close()

func _on_settings() -> void:
	if _settings_overlay != null and is_instance_valid(_settings_overlay):
		return
	_settings_overlay = SettingsPanelScript.new()
	_settings_overlay.set_meta("on_close", Callable(self, "_on_settings_closed"))
	add_child(_settings_overlay)

func _on_settings_closed() -> void:
	_settings_overlay = null

func _on_quit() -> void:
	get_tree().quit()
