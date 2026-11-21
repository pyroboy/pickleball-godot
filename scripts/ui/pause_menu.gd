extends CanvasLayer
## Pause menu: resume, restart (ball / drill / match), practice drills, settings, pose
## editor, main menu, quit. Destructive actions confirm inside the panel (no OS-style
## dialog), and the list scrolls when the screen is short, so every action stays reachable.

const SettingsPanelScript = preload("res://scripts/ui/settings_panel.gd")
const Layout = preload("res://scripts/ui/mobile_layout.gd")
const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")
const TITLE_SCENE: = "res://scenes/title.tscn"

var _hint: Label
var _content: VBoxContainer
var _panel: PanelContainer
var _margin: MarginContainer
var _scroll: ScrollContainer
var _main_list: VBoxContainer
var _confirm_box: VBoxContainer
var _confirm_title: Label
var _confirm_text: Label
var _confirm_ok: Button
var _confirm_cancel: Button
var _confirm_kind: = ""
var _settings_overlay: Node = null
var _resume_button: Button
var _settings_button: Button
var _pose_button: Button
var _reset_button: Button
var _menu_button: Button
var _eyebrow: Label
var _title: Label
var _subtitle: Label
var _score: Label

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
	dim.color = Color(UiTheme.BACKDROP, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.theme = UiTheme.create()
	UiTheme.crisp(_panel)
	var style: = UiTheme.panel_style()
	style.set_content_margin_all(0)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_margin = MarginContainer.new()
	_panel.add_child(_margin)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_margin.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	var reset_needed: = _contact_reset_required()
	_eyebrow = _label("PRACTICE PAUSED" if _is_practice() else "MATCH PAUSED", 18, UiTheme.ACCENT, true)
	_title = _label("Contact check" if reset_needed else "Take a breather", 36, UiTheme.INK, true)
	_subtitle = _label("A collision could not be resolved. No point was awarded. Reset to continue." if reset_needed else _subtitle_text(), 16, UiTheme.MUTED)
	_score = _label(_score_text(), 18, UiTheme.INK, true)
	_score.visible = not _score.text.is_empty()
	_main_list = VBoxContainer.new()
	_content.add_child(_main_list)
	_resume_button = _add_button(_main_list, "Reset required" if reset_needed else ("Resume practice" if _is_practice() else "Resume match"), _on_resume)
	_resume_button.disabled = reset_needed
	UiTheme.make_primary(_resume_button)
	_reset_button = _add_button(_main_list, _reset_caption(), _on_reset_requested)
	_add_button(_main_list, "Practice drills", _on_practice)
	_settings_button = _add_button(_main_list, "Settings", _on_settings)
	_pose_button = _add_button(_main_list, "Pose editor", _on_pose_editor)
	_menu_button = _add_button(_main_list, "Main menu", _confirm.bind("menu"))
	var quit_button: = _add_button(_main_list, "Quit game", _confirm.bind("quit"))
	UiTheme.make_quiet(quit_button)
	# In-panel confirmation (replaces the list while open).
	_confirm_box = VBoxContainer.new()
	_confirm_box.hide()
	_content.add_child(_confirm_box)
	_confirm_title = _label("", 27, UiTheme.GOLD, true, _confirm_box)
	_confirm_text = _label("", 16, UiTheme.MUTED, false, _confirm_box)
	_confirm_ok = _add_button(_confirm_box, "Confirm", _on_confirm_accepted)
	UiTheme.make_primary(_confirm_ok)
	_confirm_cancel = _add_button(_confirm_box, "Cancel", _close_confirm)
	_hint = _label("", 14, UiTheme.MUTED)

func _label(text: String, size: int, color: Color, pixel: bool = false, parent: Node = null) -> Label:
	var label: = Label.new()
	label.text = text
	label.set_meta("font_size", size)
	label.set_meta("pixel", pixel)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	if pixel: label.add_theme_font_override("font", UiTheme.pixel_font())
	(parent if parent != null else _content).add_child(label)
	return label

func _add_button(parent: Node, text: String, callback: Callable) -> Button:
	var button: = Button.new()
	button.text = text
	button.custom_minimum_size.y = 52
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _subtitle_text() -> String:
	if _is_wall(): return "Your wall court is right where you left it."
	return "Your court is right where you left it." if _is_practice() else "Your match is right where you left it."

func _score_text() -> String:
	var game = get_tree().current_scene
	if game == null or _is_practice() or not "score_left" in game: return ""
	return "SCORE  %d – %d" % [int(game.score_left), int(game.score_right)]

func _reset_caption() -> String:
	if _is_wall(): return "Reset ball"
	if _is_practice(): return "Restart drill"
	return "Restart match"

func _fit_panel() -> void :
	var viewport_size: = get_viewport().get_visible_rect().size
	var portrait: bool = Layout.is_portrait(viewport_size)
	_hint.text = "Tap Resume to return to court" if portrait else "ESC  Resume     TAB / arrows  Navigate"
	var window_size: = Vector2(get_window().size).max(Vector2.ONE)
	var scale: float = Layout.scale_for(viewport_size) if portrait else viewport_size.y / window_size.y
	var safe: Rect2 = Layout.safe_rect(get_viewport())
	var pad: = roundi((28 if portrait else 24) * scale)
	for side in ["left", "right", "top", "bottom"]: _margin.add_theme_constant_override("margin_" + side, pad)
	var gap: = roundi((12 if portrait else 8) * scale)
	_content.add_theme_constant_override("separation", gap)
	_main_list.add_theme_constant_override("separation", gap)
	_confirm_box.add_theme_constant_override("separation", gap)
	for box in [_main_list, _confirm_box]:
		for widget in box.get_children():
			if widget is Button:
				widget.custom_minimum_size.y = ceili((88.0 if portrait else 46.0) * scale)
				widget.add_theme_font_size_override("font_size", UiTheme.pixel_size((27 if portrait else 18) * scale))
	for label in _all_labels():
		var size: float = float(label.get_meta("font_size", 16)) * (1.35 if portrait else 1.0) * scale
		label.add_theme_font_size_override("font_size", UiTheme.pixel_size(size) if label.get_meta("pixel", false) else int(size))
	var width: float = minf((640 if portrait else 480) * scale, safe.size.x - 32 * scale)
	_panel.size = Vector2(width, 0)
	_panel.reset_size()
	var wanted: float = _content.get_combined_minimum_size().y + pad * 2 + _panel.get_theme_stylebox("panel").get_minimum_size().y
	var height: float = minf(wanted, safe.size.y - 32 * scale)
	_panel.size = Vector2(width, height)
	_panel.position = (safe.position + (safe.size - _panel.size) * 0.5).round()

func _all_labels() -> Array:
	var labels: Array = []
	for parent in [_content, _confirm_box]:
		for widget in parent.get_children():
			if widget is Label: labels.append(widget)
	return labels

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

## Back / ESC: closes the confirmation or settings first. Returns true when it did.
func close_settings() -> bool:
	if _confirm_box.visible:
		_close_confirm()
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
	var game = get_tree().current_scene
	if _is_practice():
		# Ball / drill restarts lose nothing worth confirming.
		var controller = get_meta("controller") if has_meta("controller") else null
		if controller: controller.close()
		if game and game.get("practice_launcher"):
			game.practice_launcher.repeat_drill()
		return
	_confirm("reset")

func _confirm(kind: String) -> void :
	_confirm_kind = kind
	match kind:
		"reset":
			_confirm_title.text = "Restart match?"
			_confirm_text.text = "The score goes back to 0–0 and a fresh serve starts. Your current rally ends."
			_confirm_ok.text = "Restart match"
		"menu":
			_confirm_title.text = "Back to main menu?"
			_confirm_text.text = "You leave the court. " + ("Practice progress is not saved." if _is_practice() else "This match will not be saved.")
			_confirm_ok.text = "Main menu"
		"quit":
			_confirm_title.text = "Quit the game?"
			_confirm_text.text = "The app closes. " + ("" if _is_practice() else "This match will not be saved.")
			_confirm_ok.text = "Quit"
	_main_list.hide()
	_confirm_box.show()
	_fit_panel()
	_confirm_cancel.grab_focus()

func _close_confirm() -> void :
	var kind: = _confirm_kind
	_confirm_kind = ""
	_confirm_box.hide()
	_main_list.show()
	_fit_panel()
	match kind:
		"reset": _reset_button.grab_focus()
		"menu": _menu_button.grab_focus()
		_:
			if _resume_button.disabled: _reset_button.grab_focus()
			else: _resume_button.grab_focus()

func _on_confirm_accepted() -> void :
	var kind: = _confirm_kind
	match kind:
		"reset":
			_close_confirm()
			var game = get_tree().current_scene
			if game and game.has_method("request_match_reset"): game.request_match_reset()
			var controller = get_meta("controller") if has_meta("controller") else null
			if controller: controller.close()
		"menu":
			var controller = get_meta("controller") if has_meta("controller") else null
			if controller and controller.has_method("return_to_title"): controller.return_to_title()
			else:
				get_tree().paused = false
				get_tree().change_scene_to_file(TITLE_SCENE)
		"quit":
			get_tree().quit()

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
