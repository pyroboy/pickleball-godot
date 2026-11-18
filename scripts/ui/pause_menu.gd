extends CanvasLayer


const SettingsPanelScript = preload("res://scripts/ui/settings_panel.gd")
const Layout = preload("res://scripts/ui/mobile_layout.gd")
const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
var _hint: Label
var _content: VBoxContainer
var _panel: Panel
var _settings_overlay: Node = null
var _resume_button: Button
var _settings_button: Button
var _pose_button: Button
var _reset_button: Button
var _reset_dialog: ConfirmationDialog

func _ready() -> void :
	layer = 100
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_build()
	get_viewport().size_changed.connect(_fit_panel)
	_fit_panel()
	_resume_button.grab_focus()

func _contact_reset_required() -> bool:
	var controller = get_node_or_null("/root/PauseController")
	return controller != null and controller.contact_reset_required()

func _build() -> void :
	var dim: = ColorRect.new()
	dim.color = Color(0.015, 0.035, 0.05, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_panel = Panel.new()
	_panel.theme = UiTheme.create()
	_panel.add_theme_stylebox_override("panel", UiTheme.panel_style())
	add_child(_panel)
	var content: = VBoxContainer.new()
	_content = content
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 32
	content.offset_top = 28
	content.offset_right = -32
	content.offset_bottom = -28
	content.add_theme_constant_override("separation", 12)
	_panel.add_child(content)
	var eyebrow: = Label.new()
	eyebrow.text = "PRACTICE PAUSED" if _is_practice() else "MATCH PAUSED"
	eyebrow.set_meta("font_size", 13)
	eyebrow.add_theme_font_size_override("font_size", 13)
	eyebrow.add_theme_color_override("font_color", UiTheme.ACCENT)
	content.add_child(eyebrow)
	var title: = Label.new()
	title.text = "Contact check stopped" if _contact_reset_required() else "Take a breather"
	title.set_meta("font_size", 32)
	title.add_theme_font_size_override("font_size", 32)
	content.add_child(title)
	var subtitle: = Label.new()
	subtitle.text = "A collision could not be resolved safely. No point was awarded. Reset the ball or match to continue." if _contact_reset_required() else ("Your court is right where you left it." if _is_practice() else "Your match is right where you left it.")
	subtitle.set_meta("font_size", 16)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", UiTheme.MUTED)
	content.add_child(subtitle)
	var spacer: = Control.new()
	spacer.custom_minimum_size.y = 8
	content.add_child(spacer)
	_resume_button = _add_button(content, "Reset required" if _contact_reset_required() else ("Resume practice" if _is_practice() else "Resume match"), _on_resume)
	_resume_button.disabled = _contact_reset_required()
	for state in ["normal", "hover", "pressed"]:
		_resume_button.add_theme_stylebox_override(state, UiTheme.button_style(UiTheme.ACCENT if state == "normal" else Color("d2f59d")))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_resume_button.add_theme_color_override(state, UiTheme.PANEL)
	_add_button(content, "Practice drills", _on_practice)
	_settings_button = _add_button(content, "Settings", _on_settings)
	_pose_button = _add_button(content, "Pose Editor", _on_pose_editor)
	_reset_button = _add_button(content, "Reset ball" if _is_wall() else "Reset match", _on_reset_requested)
	_reset_dialog = ConfirmationDialog.new()
	_reset_dialog.title = "Reset match?"
	_reset_dialog.dialog_text = "Reset the score to 0–0 and start a fresh serve? Your current rally will end."
	_reset_dialog.ok_button_text = "Reset match"
	_reset_dialog.cancel_button_text = "Cancel"
	_reset_dialog.theme = UiTheme.create()
	_reset_dialog.confirmed.connect(_on_reset_confirmed)
	_reset_dialog.canceled.connect(_on_reset_canceled)
	add_child(_reset_dialog)
	var quit_button: = _add_button(content, "Quit game", _on_quit)
	quit_button.add_theme_color_override("font_color", UiTheme.MUTED)
	var hint: = Label.new()
	_hint = hint
	hint.text = "ESC  Resume     TAB / arrows  Navigate"
	hint.set_meta("font_size", 13)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", UiTheme.MUTED)
	content.add_child(hint)

func _add_button(parent: Node, text: String, callback: Callable) -> Button:
	var button: = Button.new()
	button.text = text
	button.custom_minimum_size.y = 52
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _fit_panel() -> void :
	if is_instance_valid(_reset_dialog) and _reset_dialog.visible:
		_fit_reset_dialog()
		_position_reset_dialog()
	var viewport_size: = get_viewport().get_visible_rect().size
	var portrait: bool = Layout.is_portrait(viewport_size)
	_hint.text = "Tap Resume to return to court" if portrait else "ESC  Resume     TAB / arrows  Navigate"
	var window_size: = Vector2(get_window().size).max(Vector2.ONE)
	var scale: float = Layout.scale_for(viewport_size) if portrait else viewport_size.y / window_size.y
	var safe: Rect2 = Layout.safe_rect(get_viewport())
	var panel_size: = Vector2(minf((660 if portrait else 470) * scale, safe.size.x - 32 * scale), minf((970 if portrait else 610) * scale, safe.size.y - 32 * scale))
	var compact: bool = not portrait and panel_size.y < 610 * scale - 0.5
	_panel.position = safe.position + (safe.size - panel_size) * 0.5
	_panel.size = panel_size
	_content.offset_left = 32 * scale
	_content.offset_right = -32 * scale
	_content.offset_top = (20 if compact else 28) * scale
	_content.offset_bottom = -(20 if compact else 28) * scale
	_content.add_theme_constant_override("separation", int((8 if compact else 12) * scale))
	for widget in _content.get_children():
		if widget is Button:
			widget.custom_minimum_size.y = 96.0 * scale if portrait else ceili((44.0 if compact else 52.0) * scale)
			widget.add_theme_font_size_override("font_size", int((26 if portrait else 18) * scale))
		elif widget is Label:
			widget.add_theme_font_size_override("font_size", int(widget.get_meta("font_size", 16) * (1.35 if portrait else 1.0) * scale))

func _on_resume() -> void :
	var controller = get_meta("controller") if has_meta("controller") else null
	if controller != null and controller.has_method("close"):
		controller.close()

func _on_settings() -> void :
	if is_instance_valid(_settings_overlay): return
	_panel.hide()
	_settings_overlay = SettingsPanelScript.new()
	_settings_overlay.set_meta("on_close", Callable(self, "_on_settings_closed"))
	add_child(_settings_overlay)

func _on_settings_closed() -> void :
	_settings_overlay = null
	_panel.show()
	_settings_button.grab_focus()

func _on_quit() -> void :
	get_tree().quit()

func close_settings() -> bool:
	if is_instance_valid(_reset_dialog) and _reset_dialog.visible:
		_on_reset_canceled()
		return true
	if is_instance_valid(_settings_overlay):
		_settings_overlay._on_close()
		return true
	return false

func _on_practice() -> void :
	var game = get_tree().current_scene
	if game and game.get("practice_panel"):
		game.practice_panel.open_practice()

func _on_reset_requested() -> void :
	if _is_wall():
		var game = get_tree().current_scene
		_on_resume()
		game.practice_launcher.repeat_drill()
		return
	if _reset_dialog.visible: return
	_fit_reset_dialog()
	_reset_dialog.popup_centered(_reset_dialog.size)
	_position_reset_dialog()
	_reset_dialog.get_cancel_button().grab_focus()

func _fit_reset_dialog() -> void:
	var viewport_size: = get_viewport().get_visible_rect().size
	var window_size: = Vector2(get_window().size).max(Vector2.ONE)
	var scale: float = viewport_size.y / window_size.y if _reset_dialog.is_embedded() else 1.0
	var safe: = Layout.safe_rect(get_viewport())
	if not _reset_dialog.is_embedded():
		safe = Rect2(safe.position * window_size / viewport_size, safe.size * window_size / viewport_size)
	var panel_style: = UiTheme.panel_style()
	panel_style.set_corner_radius_all(0)
	panel_style.set_border_width_all(0)
	panel_style.shadow_size = 0
	panel_style.content_margin_left = 20 * scale
	panel_style.content_margin_right = 20 * scale
	panel_style.content_margin_top = 20 * scale
	panel_style.content_margin_bottom = 20 * scale
	_reset_dialog.add_theme_stylebox_override("panel", panel_style)
	var border_style: = UiTheme.panel_style()
	border_style.set_corner_radius_all(roundi(12 * scale))
	border_style.set_border_width_all(maxi(1, roundi(scale)))
	border_style.content_margin_left = scale
	border_style.content_margin_right = scale
	border_style.content_margin_top = 44 * scale
	border_style.content_margin_bottom = scale
	border_style.expand_margin_left = scale
	border_style.expand_margin_right = scale
	border_style.expand_margin_top = 44 * scale
	border_style.expand_margin_bottom = scale
	border_style.shadow_size = roundi(10 * scale)
	border_style.shadow_offset = Vector2(0, 4 * scale)
	_reset_dialog.add_theme_stylebox_override("embedded_border", border_style)
	_reset_dialog.add_theme_stylebox_override("embedded_unfocused_border", border_style)
	_reset_dialog.add_theme_color_override("title_color", UiTheme.INK)
	_reset_dialog.add_theme_font_size_override("title_font_size", roundi(20 * scale))
	_reset_dialog.add_theme_constant_override("title_height", roundi(44 * scale))
	_reset_dialog.add_theme_constant_override("close_h_offset", roundi(48 * scale))
	_reset_dialog.add_theme_constant_override("close_v_offset", roundi(44 * scale))
	_reset_dialog.add_theme_constant_override("buttons_separation", roundi(20 * scale))
	_reset_dialog.add_theme_constant_override("buttons_min_height", ceili(44 * scale))
	_reset_dialog.add_theme_constant_override("buttons_min_width", ceili(112 * scale))
	# Godot uses the close texture bounds as its title-bar hit rectangle.
	# Keep a small cross centered inside a real 44-pixel transparent target.
	for icon_name in ["close", "close_pressed"]:
		var cache_key: String = "reset_base_" + icon_name
		if not _reset_dialog.has_meta(cache_key):
			_reset_dialog.set_meta(cache_key, _reset_dialog.get_theme_icon(icon_name))
		var icon: Image = _reset_dialog.get_meta(cache_key).get_image().duplicate()
		icon.convert(Image.FORMAT_RGBA8)
		icon.resize(maxi(1, roundi(16 * scale)), maxi(1, roundi(16 * scale)), Image.INTERPOLATE_LANCZOS)
		var target: = Image.create(ceili(44 * scale), ceili(44 * scale), false, Image.FORMAT_RGBA8)
		target.blit_rect(icon, Rect2i(Vector2i.ZERO, icon.get_size()), (target.get_size() - icon.get_size()) / 2)
		_reset_dialog.add_theme_icon_override(icon_name, ImageTexture.create_from_image(target))
	for button in [_reset_dialog.get_ok_button(), _reset_dialog.get_cancel_button()]:
		button.add_theme_font_size_override("font_size", roundi(18 * scale))
	_reset_dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reset_dialog.get_label().add_theme_font_size_override("font_size", roundi(18 * scale))
	_reset_dialog.min_size = Vector2i(minf(560 * scale, safe.size.x - 48 * scale), minf(240 * scale, safe.size.y - 88 * scale))
	_reset_dialog.size = _reset_dialog.min_size

func _position_reset_dialog() -> void:
	var safe: = Layout.safe_rect(get_viewport())
	if not _reset_dialog.is_embedded():
		var ratio: = Vector2(get_window().size) / get_viewport().get_visible_rect().size
		safe = Rect2(Vector2(get_window().position) + safe.position * ratio, safe.size * ratio)
	# Center the decorated window in the safe area, including its title bar.
	var decoration: = Vector2(_reset_dialog.get_size_with_decorations() - _reset_dialog.size)
	var inset: = Vector2(_reset_dialog.position - _reset_dialog.get_position_with_decorations())
	_reset_dialog.position = Vector2i(safe.position + (safe.size - Vector2(_reset_dialog.size) - decoration) * 0.5 + inset)

func _on_reset_canceled() -> void :
	_reset_dialog.hide()
	_reset_button.grab_focus()

func _on_reset_confirmed() -> void :
	_reset_dialog.hide()
	var game = get_tree().current_scene
	if game and game.has_method("request_match_reset"): game.request_match_reset()
	var controller = get_meta("controller") if has_meta("controller") else null
	if controller: controller.close()

func _is_practice() -> bool:
	var game = get_tree().current_scene
	return game != null and game.has_method("_is_practice") and game._is_practice()

func _is_wall() -> bool:
	var game = get_tree().current_scene
	return _is_practice() and game.practice_launcher.is_wall()

func _on_pose_editor() -> void:
	var game = get_tree().current_scene
	if game and game.has_method("open_mobile_pose_editor"):
		game.open_mobile_pose_editor()

func focus_pose_editor() -> void:
	_pose_button.grab_focus()
