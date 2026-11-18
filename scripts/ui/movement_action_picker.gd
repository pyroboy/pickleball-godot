extends Control
## One discoverable movement selector. Selection never awards a shot; HIT still
## commits a physically eligible incoming-ball action through the match driver.
const Layout = preload("res://scripts/ui/mobile_layout.gd")
const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
var game
var action_button: Button
var overlay: ColorRect
var panel: PanelContainer
var explanation: Label
var choices: Dictionary = {}
var _open := false
var _pause_owned := false
var _last_focus: Control

func setup(owner) -> void:
	game = owner
	name = "MovementActions"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.create()
	action_button = Button.new()
	action_button.name = "MovementAction"
	action_button.text = "Move: Auto"
	action_button.tooltip_text = "Choose a reach, Erne or dive for your next HIT · V"
	action_button.pressed.connect(open_picker)
	add_child(action_button)
	overlay = ColorRect.new()
	overlay.color = Color(0.015, 0.03, 0.045, 0.52)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style())
	overlay.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	panel.add_child(column)
	var title := Label.new()
	title.text = "Next movement"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	explanation = Label.new()
	explanation.text = "Choose, then hold and release HIT. Reach and Dive need a bounced ball; Erne needs a legal sideline volley. A reachable window is still required. Play is paused here."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(explanation)
	for row in [["AUTO", "Auto footwork"], ["REACH", "Grounded reach"], ["ERNE", "Erne attack"], ["DIVE", "Emergency dive"]]:
		var button := Button.new()
		button.name = row[0]
		button.text = row[1]
		button.custom_minimum_size.y = 48
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_choose.bind(str(row[0])))
		column.add_child(button)
		choices[row[0]] = button
	var cancel := Button.new()
	cancel.name = "Cancel"
	cancel.text = "Cancel"
	cancel.custom_minimum_size.y = 48
	cancel.pressed.connect(close_picker)
	column.add_child(cancel)
	overlay.hide()
	get_viewport().size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	if action_button == null: return
	var size := get_viewport().get_visible_rect().size
	var safe := Layout.safe_rect(get_viewport())
	var portrait := Layout.is_portrait(size)
	var scale := Layout.scale_for(size)
	if portrait:
		var deck := Layout.deck_rect(size, safe)
		var button_width := maxf(110.0, 132 * scale)
		action_button.position = Vector2(safe.get_center().x - button_width * 0.5, deck.end.y - 47 * scale)
		action_button.size = Vector2(button_width, maxf(44.0, 54 * scale))
		action_button.add_theme_font_size_override("font_size", maxi(14, roundi(20 * scale)))
	else:
		action_button.position = Vector2(safe.get_center().x - 75, safe.position.y + 20)
		action_button.size = Vector2(150, 44)
		action_button.add_theme_font_size_override("font_size", 16)
	var width := minf(440.0, safe.size.x - 24)
	panel.position = Vector2(safe.get_center().x - width * 0.5, maxf(safe.position.y + 12, safe.get_center().y - 230))
	panel.size = Vector2(width, 0)
	explanation.custom_minimum_size.x = width - 44

func _process(_delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_process(_delta)
	PerfMonitor.record("proc.movement_action_picker", Time.get_ticks_usec() - _pt)

func _perf_process(_delta: float) -> void:
	if game == null: return
	var driver = game.player_left.special_reach_driver
	var busy: bool = driver != null and driver.owns_presentation() or _committed_move_busy()
	var blocked: bool = game._tool_state_active() or not game.hud._gameplay_visible or game.hud._between_point_active or game.hud._guide.visible or game.match_over
	action_button.visible = not blocked and not _open and not get_tree().paused and game.game_state == game.GameState.PLAYING
	action_button.disabled = busy
	action_button.text = "Move: " + str(game.selected_movement_intent).capitalize()
	choices.DIVE.disabled = not game.dive_actions_enabled
	if _open and blocked: close_picker()

func _committed_move_busy() -> bool:
	# The scene creates its Human controller after the first UI process frame.
	# Treat that incomplete state as unavailable, never as a cancellable stroke.
	if game == null or not is_instance_valid(game.player_left): return true
	var actor = game.player_left
	if actor.posture == null or actor.posture.human_contact == null: return true
	return actor.posture.human_contact.phase >= 0 or actor.erne_action != null and actor.erne_action.active

func is_open() -> bool: return _open

func open_picker() -> void:
	if game != null and game._point_transition_blocks_attempt(): return
	if _open or get_tree().paused or game == null or game._tool_state_active() or game.game_state != game.GameState.PLAYING: return
	var driver = game.player_left.special_reach_driver
	if driver != null and driver.owns_presentation(): return
	# Admission must be checked before input cancellation clears the stroke.
	if _committed_move_busy(): return
	_last_focus = get_viewport().gui_get_focus_owner()
	if game.mobile_controls: game.mobile_controls.cancel_all()
	if game.input_handler: game.input_handler.cancel_charge_input()
	_open = true
	_pause_owned = true
	get_node("/root/PauseController").hold_overlay(self)
	overlay.show()
	action_button.hide()
	_layout()
	choices.AUTO.grab_focus()

func _choose(kind: String) -> void:
	if game != null and game._point_transition_blocks_attempt(): return
	if not _open or not choices.has(kind) or choices[kind].disabled: return
	game.selected_movement_intent = kind
	close_picker()

func close_picker() -> void:
	if not _open: return
	_open = false
	overlay.hide()
	if _pause_owned: get_node("/root/PauseController").release_overlay(self)
	_pause_owned = false
	if is_instance_valid(_last_focus): _last_focus.grab_focus()
	else: action_button.grab_focus()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _open and event.keycode in [KEY_ESCAPE, KEY_BACK]:
			close_picker()
			get_viewport().set_input_as_handled()
		elif not _open and event.keycode == KEY_V and not event.ctrl_pressed and not event.meta_pressed and not event.alt_pressed:
			open_picker()
			get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if _pause_owned and is_inside_tree(): get_node("/root/PauseController").release_overlay(self)
