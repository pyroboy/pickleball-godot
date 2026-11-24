extends Control


const Layout = preload("res://scripts/ui/mobile_layout.gd")
const UiTheme = preload("res://scripts/ui/game_ui_theme.gd")
const HitTiming = preload("res://scripts/ui/hit_timing_feedback.gd")
const PixelDraw = preload("res://scripts/ui/pixel_draw.gd")
const PixelStyle = preload("res://scripts/ui/pixel_style_box.gd")
const HumanShots = preload("res://scripts/human_shot_choice.gd")
const TIMING_RING_WIDTH_FRACTION: = 0.54
const TIMING_RING_MIN_GAP_FRACTION: = 0.16
const TIMING_RING_SMOOTH_SECONDS: = 0.045
var _hit_timing = HitTiming.new()
var _move_closer_dir := 0   # screen side (-1 left, +1 right) of the lit side band, 0 for none
var _timing_caption_center: = Vector2.ZERO
var _timing_caption_rect: = Rect2()
var _timing_ring_max: = 194.4
var _timing_safe: = Rect2()
var _timing_draw_fraction: = 1.0
var _timing_draw_flight: = -1
const MOVE_ACTIONS: = [&"move_left", &"move_right", &"move_up", &"move_down"]
const DEADZONE: = 0.13
const DEADZONE_STOP: = 0.1
const MOUSE_POINTER: = -100
var game: Node
var enabled: = false
var _owners: Dictionary = {}
var _toolbar_touches: Dictionary = {}
var _toolbar_positions: Dictionary = {}
var _stick_id: = -1
var _charge_id: = -1
var _charge_owns_action: = false
var _gesture_is_serve: = false
var _serve_selector_id: = -1
var _serve_selector_center: = Vector2.ZERO
var _serve_selector_radius: = 56.0
var _serve_selector_last_angle: = 0.0
var _serve_selector_has_angle: = false
var _serve_selector_accumulator: = 0.0
var _serve_selector_rotation: = 0.0
var _serve_timing: Dictionary = {}
var _last_serve_phase: = ""
var _serve_contact_flash: = 0.0
var _stick_vector: = Vector2.ZERO
var _stick_active: = false
var _stick_center: = Vector2.ZERO
var _charge_center: = Vector2.ZERO
var _stick_radius: = 78.0
var _charge_radius: = 78.0
var _charge_origin: = Vector2.ZERO
var _charge_vector: = Vector2.ZERO
var _gesture_sector: = ""
var _cancel_center: = Vector2.ZERO
var _cancel_radius: = 40.0
var _shot_button_radius: = 46.0
var _cancel_armed: = false
var _deck_rect: = Rect2()
var _s: = 1.0
var _was_blocked: = false
const GUIDE_LABELS: = ["TOPSPIN", "SLICE", "DROP"]
var _guide_nodes: = PackedVector2Array()
var _guide_labels: = PackedVector2Array()
var _guide_flat: = Vector2.ZERO
var _guide_show: = 0.0
var _guide_phase: = 0.0
var _guide_caption_rects: Array[Rect2] = []
var _guide_caption_backing: StyleBox

func setup(p_game: Node) -> void :
	game = p_game
	if OS.has_feature("mobile"): Engine.max_fps = 60
	name = "MobileControls"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # pixel discs and font (pixel_draw.gd)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _layout() -> void :
	cancel_all()
	var viewport_size: = get_viewport().get_visible_rect().size
	enabled = Layout.is_portrait(viewport_size)
	visible = enabled
	_s = Layout.scale_for(viewport_size)
	_deck_rect = Layout.deck_rect(viewport_size, Layout.safe_rect(get_viewport()))
	_stick_radius = 96.0 * _s   # was 78: bigger move stick (user's call)
	_charge_radius = 78.0 * _s
	_stick_center = Vector2(_deck_rect.position.x + 122 * _s, _deck_rect.end.y - 124 * _s)
	_charge_center = Vector2(_deck_rect.end.x - 136 * _s, _stick_center.y)


	var safe: Rect2 = Layout.safe_rect(get_viewport())
	_timing_safe = safe.grow(-7.0 * _s)
	_timing_ring_max = maxf(_charge_radius, safe.size.x * TIMING_RING_WIDTH_FRACTION * 0.5)
	_timing_caption_center = _charge_center + Vector2(-100, -246) * _s
	_serve_selector_center = Vector2((_stick_center.x + _charge_center.x) * 0.5, _stick_center.y)
	_serve_selector_radius = 56 * _s
	# Drawn areas of the move stick (with its MOVE caption) and the HIT pad (with its footer):
	# other HUD (the PARTNER / YOU name tags) keeps out of these. Layout-time only.
	stick_zone = Rect2(_stick_center - Vector2.ONE * _stick_radius, Vector2(_stick_radius * 2.0, _stick_radius + 128 * _s)).grow(6 * _s)
	hit_zone = Rect2(_charge_center - Vector2.ONE * _charge_radius, Vector2(_charge_radius * 2.0, _charge_radius + 112 * _s)).grow(6 * _s)
	_cache_hit_guide()
	queue_redraw()

var stick_zone: = Rect2()
var hit_zone: = Rect2()

func _blocked() -> bool:
	if game != null and game._point_transition_blocks_attempt(): return true
	return game == null or get_tree().paused or game._tool_state_active() or game.hud._between_point_active or not game.hud._gameplay_visible or game.hud._guide.visible or bool(game.get("match_over")) or game.get("practice_panel") != null and game.practice_panel.visible

func _process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_process(delta)
	PerfMonitor.record("proc.mobile_controls", Time.get_ticks_usec() - _pt)

func _perf_process(delta: float) -> void:
	if game == null: return
	if _shot_fb_age < SHOT_FB_SECONDS:
		_shot_fb_age += delta
		queue_redraw()
	_serve_contact_flash = maxf(0, _serve_contact_flash - delta)
	_serve_timing = {}
	if game.game_serve and game.game_serve.has_method("get_serve_timing_state"):
		_serve_timing = game.game_serve.get_serve_timing_state()
		var phase: String = str(_serve_timing.get("phase", ""))
		if phase == "CONTACT" and phase != _last_serve_phase: _serve_contact_flash = 0.25
		_last_serve_phase = phase
	if _serve_selector_id != -1 and not _show_serve_selector(): _release(_serve_selector_id, true)
	var blocked: = _blocked()
	if blocked and not _was_blocked: cancel_all()
	_was_blocked = blocked
	visible = enabled and not blocked
	var real_delta: float = delta / maxf(Engine.time_scale, 0.05)
	_update_hit_timing(blocked, real_delta)
	var show_guide: bool = enabled and not blocked and _charge_id != -1 and not _gesture_is_serve
	_guide_show = move_toward(_guide_show, 1.0 if show_guide else 0.0, real_delta * 7.5)
	_guide_phase = fmod(float(Time.get_ticks_msec()) * 0.0016, 1.0)
	if blocked: _guide_show = 0.0
	if enabled and not blocked:
		game.hud.state.text = game.hud.state.text.replace("SPACE", "HIT").replace("Space", "Hit")
		game.hud.difficulty.text = game.hud.difficulty.text.replace("  [X]", "").replace(" [X]", "")
		game.hud._spin_label.text = game.hud._spin_label.text.replace("  [Q]", "").replace("  [E]", "")
		if game.game_state == 0 and game.serving_team == 0:
			if not game._is_practice():
				game.hud.state.text = "Aim the target · release HIT to serve" if game.hud._charging else "Your serve · hold HIT to charge"
			if not game.hud._charging:
				game.hud._charge_label.text = "ROTATE SERVE WHEEL · HOLD HIT" if _show_serve_selector() else "HOLD HIT TO CHARGE"
	if enabled and game.reaction_button:

		game.reaction_button.visible = false
	queue_redraw()

func _notification(what: int) -> void :
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		cancel_all()

func _exit_tree() -> void :
	cancel_all()

func _input(event: InputEvent) -> void :
	if not enabled: return
	if event is InputEventMouse and event.device != InputEvent.DEVICE_ID_EMULATION and not OS.has_feature("mobile") and not Input.emulate_touch_from_mouse:
		if _handle_desktop_pointer(event):
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION and _toolbar_input_available() and _toolbar_at_point(event.position) != null:


		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if not event.pressed or event.canceled:
			if _owners.has(event.index):
				if _toolbar_touches.has(event.index): _toolbar_positions[event.index] = event.position
				if event.index == _charge_id and not event.canceled and not _blocked():
					_update_shot_drag(event.position)
				_release(event.index, event.canceled or (_blocked() and not _toolbar_touches.has(event.index)))
				get_viewport().set_input_as_handled()
			return
		if _press_toolbar(event.index, event.position):
			get_viewport().set_input_as_handled()
			return
		if _blocked(): return
		if _press(event.index, event.position): get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _owners.has(event.index):
		if _toolbar_touches.has(event.index): _toolbar_positions[event.index] = event.position
		elif _blocked(): cancel_all()
		else: _drag(event.index, event.position)
		get_viewport().set_input_as_handled()

func _handle_desktop_pointer(event: InputEventMouse) -> bool:


	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			return false if _blocked() else _press(MOUSE_POINTER, event.position)
		if _owners.has(MOUSE_POINTER):
			if _charge_id == MOUSE_POINTER and not _blocked(): _update_shot_drag(event.position)
			_release(MOUSE_POINTER, _blocked())
			return true
	elif event is InputEventMouseMotion and _owners.has(MOUSE_POINTER):
		if _blocked(): cancel_all()
		else: _drag(MOUSE_POINTER, event.position)
		return true
	return false

func _toolbar_input_available() -> bool:
	if game != null and game._point_transition_blocks_attempt(): return false
	return game != null and not get_tree().paused and not game._tool_state_active() and game.hud._gameplay_visible

func _toolbar_at_point(point: Vector2) -> Button:
	if game == null: return null
	if game.movement_actions != null:
		var movement: Button = game.movement_actions.action_button
		if movement.is_visible_in_tree() and not movement.disabled and movement.get_global_rect().has_point(point): return movement
	for child in game.hud._toolbar.get_children():
		if child is Button and child.is_visible_in_tree() and not child.disabled and child.get_global_rect().has_point(point):
			return child
	for extra in game.get("extra_touch_buttons") if game.get("extra_touch_buttons") != null else []:
		if is_instance_valid(extra) and extra is Button and extra.is_visible_in_tree() and not extra.disabled and extra.get_global_rect().has_point(point):
			return extra
	return null

func _press_toolbar(id: int, point: Vector2) -> bool:
	if not _toolbar_input_available(): return false
	var button: = _toolbar_at_point(point)
	if button == null: return false
	if not _toolbar_touches.is_empty(): return true
	cancel_all()
	_owners[id] = "toolbar"
	_toolbar_touches[id] = button
	_toolbar_positions[id] = point
	button.set_pressed_no_signal(true)
	return true

func _press(id: int, point: Vector2) -> bool:
	if _owners.has(id): return true
	var shot_index: int = _shot_button_at(point)
	if shot_index >= 0 and _charge_id == -1:
		_begin_shot(id, point, GUIDE_LABELS[shot_index])
	elif point.distance_to(_stick_center) <= _stick_radius * 1.35 and _stick_id == -1:
		_stick_id = id
		_owners[id] = "stick"
		_update_stick(point)
	elif point.distance_to(_charge_center) <= _charge_radius * 1.22 and _charge_id == -1:
		_begin_shot(id, point, "FLAT")
	elif _show_serve_selector() and point.distance_to(_serve_selector_center) <= _serve_selector_radius * 1.25 and _serve_selector_id == -1:
		_serve_selector_id = id
		_owners[id] = "serve_selector"
		_serve_selector_accumulator = 0.0
		_serve_selector_has_angle = false
		_update_serve_rotation(point)
	else:
		return false
	queue_redraw()
	return true

## Flick aiming (docs/PLAYER_FEEL_PLAN.md): the swipe of a short press, read by the game
## at release. dir: drag from the press point in hit-circle radii (y down), seconds: press time.
var last_flick: Dictionary = {}
var _press_usec := 0

func _begin_shot(id: int, point: Vector2, shot: String) -> void:
	_press_usec = Time.get_ticks_usec()
	_charge_id = id
	_owners[id] = "charge"
	_charge_origin = point
	_charge_vector = Vector2.ZERO
	_cancel_armed = false
	_gesture_is_serve = _is_serve_context()
	_gesture_sector = shot
	if not _gesture_is_serve: _select_shot(shot)
	var human = game.player_left.posture.human_contact
	_charge_owns_action = game.game_state != 1 and (human == null or human.phase < 0)
	if _charge_owns_action:
		Input.action_press("ui_accept")
		# Admit an urgent, already legal rally press before the next render
		# callback. At30fps two physics ticks can otherwise spend the entire
		# reachable window. Zero delta starts the existing path once without
		# adding charge time or changing the per-flight slow-motion budget.
		if not _gesture_is_serve and human != null and human.phase < 0 and not human.contact.is_empty() and float(human.contact.time) <= game.aim_controller.URGENT_PLANT_LEAD and bool(human.release_timing_state().get("current_reachable", false)):
			game.aim_controller.update(0.0, true, Vector2.ZERO, true)
			game.input_handler._handle_swing_charge(0.0)

func _drag(id: int, point: Vector2) -> void :
	if id == _stick_id:
		_update_stick(point)
	elif id == _charge_id:
		_update_shot_drag(point)
	elif id == _serve_selector_id:
		_update_serve_rotation(point)
	queue_redraw()

func _release(id: int, canceled: bool = false) -> void :
	if _toolbar_touches.has(id):
		var button: Button = _toolbar_touches[id]
		var point: Vector2 = _toolbar_positions.get(id, Vector2.INF)
		_toolbar_touches.erase(id)
		_toolbar_positions.erase(id)
		_owners.erase(id)
		if is_instance_valid(button):
			button.set_pressed_no_signal(false)
			if not canceled and _toolbar_input_available() and button.is_visible_in_tree() and button.get_global_rect().has_point(point):
				button.pressed.emit()
		return
	if id == _stick_id:
		_stick_id = -1
		_stick_active = false
		_stick_vector = Vector2.ZERO
		for action in MOVE_ACTIONS: Input.action_release(action)
	elif id == _charge_id:
		_hit_timing.clear()
		if is_instance_valid(game) and game.aim_focus: game.aim_focus.end_hold()
		_charge_id = -1
		_guide_show = 0.0
		if _charge_owns_action and (canceled or _cancel_armed) and is_instance_valid(game) and game.input_handler:
			game.input_handler.cancel_charge_input()
		last_flick = {"dir": _charge_vector, "seconds": float(Time.get_ticks_usec() - _press_usec) / 1000000.0} if not canceled and not _cancel_armed else {}
		if _charge_owns_action:
			Input.action_release("ui_accept")
			# Queue a normal rally release in this input event. Restoring real
			# time above must not let catch-up physics run before the render
			# callback has admitted the user's already-held swing.
			if not canceled and not _cancel_armed and not _gesture_is_serve and is_instance_valid(game) and game.game_state == 2 and game.input_handler and game.input_handler.serve_is_charging:
				game.input_handler._handle_swing_charge(0.0)
		if is_instance_valid(game) and game.aim_controller:
			game.aim_controller.cursor_visible = false
			if game.game_trajectory: game.game_trajectory._update_player_cursor()
		_charge_owns_action = false
		_charge_vector = Vector2.ZERO
		_gesture_sector = ""
		_cancel_armed = false
		_gesture_is_serve = false
	elif id == _serve_selector_id:
		_serve_selector_id = -1
		_serve_selector_has_angle = false
		_serve_selector_accumulator = 0.0
	_owners.erase(id)
	queue_redraw()

func cancel_all() -> void :
	_hit_timing.clear()

	for id in _owners.keys(): _release(int(id), true)

func _update_stick(point: Vector2) -> void :
	var raw: = ((point - _stick_center) / _stick_radius).limit_length(1.0)
	var travel: = raw.length()
	if _stick_active and travel <= DEADZONE_STOP: _stick_active = false
	elif not _stick_active and travel >= DEADZONE: _stick_active = true


	_stick_vector = raw.normalized() * ((travel - DEADZONE_STOP) / (1.0 - DEADZONE_STOP)) if _stick_active else Vector2.ZERO
	var strengths: = [maxf(0, - _stick_vector.x), maxf(0, _stick_vector.x), maxf(0, - _stick_vector.y), maxf(0, _stick_vector.y)]
	for i in range(4):
		if strengths[i] > 0: Input.action_press(MOVE_ACTIONS[i], strengths[i])
		else: Input.action_release(MOVE_ACTIONS[i])

func _update_shot_drag(point: Vector2) -> void :
	var displacement: = (point - _charge_origin) / _charge_radius
	_charge_vector = displacement.limit_length(1.0)


	_cancel_armed = point.distance_to(_cancel_center) <= _cancel_radius

func uses_touch_aim() -> bool:
	return enabled and (OS.has_feature("mobile") or _charge_id != -1 or _stick_id != -1)

func aim_direction() -> Vector2:
	if _charge_id == -1 or not _charge_owns_action or _cancel_armed: return Vector2.ZERO
	var travel: float = _charge_vector.length()
	return _charge_vector.normalized() * ((travel - DEADZONE) / (1.0 - DEADZONE)) if travel > DEADZONE else Vector2.ZERO

func _shot_button_at(point: Vector2) -> int:
	if _is_serve_context() or HumanShots.ENABLED: return -1   # tap/hold replaces the shot buttons
	for index in _guide_nodes.size():
		if point.distance_to(_guide_nodes[index]) <= _shot_button_radius: return index
	return -1

func _is_serve_context() -> bool:
	return game != null and game.serving_team == 0 and game.game_state in [0, 1]

func _serve_options() -> Array:
	if game and game.game_serve and game.game_serve.has_method("get_serve_style_options"):
		return game.game_serve.get_serve_style_options()
	return []

func _show_serve_selector() -> bool:
	return game != null and game.game_state == 0 and game.serving_team == 0 and _serve_options().size() > 1 and not _blocked()

func _selected_serve_option(use_locked_style: bool = false) -> Dictionary:
	var options: = _serve_options()
	var selected_value: Variant = game.game_serve.get("selected_serve_style") if game and game.game_serve else null
	var selected: int = int(selected_value) if selected_value != null else 0
	if use_locked_style and bool(_serve_timing.get("locked", false)):
		selected = int(_serve_timing.get("style", selected))
	for option in options:
		if int(option.get("id", -1)) == selected: return option
	return options[0] if not options.is_empty() else {"id": 0, "label": "Flat", "delivery": "Volley"}

func _update_serve_rotation(point: Vector2) -> void :
	if not _show_serve_selector(): return
	var offset: = point - _serve_selector_center
	if offset.length() < _serve_selector_radius * 0.45:
		_serve_selector_has_angle = false
		return
	var angle: = offset.angle()
	if not _serve_selector_has_angle:
		_serve_selector_has_angle = true
		_serve_selector_last_angle = angle
		return
	var delta_angle: = wrapf(angle - _serve_selector_last_angle, - PI, PI)
	_serve_selector_last_angle = angle
	_serve_selector_rotation += delta_angle
	_serve_selector_accumulator += delta_angle
	var options: = _serve_options()
	var step: = TAU / float(options.size())
	var index: = 0
	var selected_id: int = int(_selected_serve_option().get("id", 0))
	for i in range(options.size()):
		if int(options[i].get("id", -1)) == selected_id: index = i;break

	while absf(_serve_selector_accumulator) >= step * 0.6:
		var direction: = 1 if _serve_selector_accumulator > 0 else -1
		index = posmod(index + direction, options.size())
		_serve_selector_accumulator -= direction * step
		game.game_serve.select_serve_style(int(options[index].id))

func _hit_label() -> String:
	if _gesture_is_serve or _is_serve_context(): return str(_selected_serve_option(true).get("label", "Flat")).to_upper()
	var preview: Dictionary = _shot_preview()
	if not preview.is_empty(): return "TAP " + _shot_word(preview.tap)
	if _smash_state() > 0: return "SMASH"
	return "FLAT"

## What a tap and a hold will play on the incoming ball (empty when not in a rally
## or nothing is coming). Same rule as the shot itself (human_shot_choice.gd).
func _shot_preview() -> Dictionary:
	if not HumanShots.ENABLED or game == null or game.game_state != 2 or game._is_practice(): return {}
	var actor = game.get_human_actor()
	var human = actor.posture.human_contact if actor != null and actor.posture != null else null
	if human == null: return {}
	var preparation: Dictionary = human.preparation_contact()
	if preparation.is_empty(): return {}
	var root: Vector3 = preparation.get("target_root", actor.global_position)
	return HumanShots.names_for(absf(root.z), Vector3(preparation.point).y, _smash_state() == 2, preload("res://scripts/shot_names.gd").swing_room(preparation.get("def")))

static func _shot_word(key: String) -> String:
	return {"SPEED_UP": "SPEED-UP"}.get(key, key)

## 0 none, 1 smash spot reachable (hold HIT steps under the ball), 2 smash from here.
func _smash_state() -> int:
	if game == null or game.game_state != 2 or game.selected_shot_intent == "DROP": return 0
	var actor = game.get_human_actor()
	var human = actor.posture.human_contact if actor != null and actor.posture != null else null
	return human.smash_state() if human != null else 0

func _select_shot(shot: String) -> void :
	if shot == "DROP":
		game.select_drop_shot()
		return
	var mode: int = {"FLAT": 0, "TOPSPIN": 1, "SLICE": 2}.get(shot, 0)


	if game.selected_shot_intent == "DROP": game.cycle_spin_mode()
	for _i in range(3):
		if game.selected_spin_mode == mode: break
		game.cycle_spin_mode()

# Captions use the 5x7 pixel font at whole-pixel sizes (18 at 720 wide; 27 for >= 27
# authored). Minimum sizes are authored 720-wide portrait units, as before.
func _caption_size(font_size: int, minimum_design_size: int = 0) -> int:
	var want: float = float(maxi(font_size, minimum_design_size if enabled else 0)) * _s
	return maxi(UiTheme.PIXEL_UNIT, floori(want / UiTheme.PIXEL_UNIT) * UiTheme.PIXEL_UNIT)

# Keep a second caption line's ascent below the first line's shadow.
func _second_caption_baseline(first_size: int, second_size: int, authored_y: float, second_minimum: int) -> float:
	var font: Font = PixelDraw.font()
	return maxf(authored_y * _s, font.get_descent(_caption_size(first_size, 19)) + PixelDraw.unit(_s) * 2.0 + font.get_ascent(_caption_size(second_size, second_minimum)))

func _caption(text: String, center: Vector2, font_size: int, color: Color, minimum_design_size: int = 0) -> void :
	PixelDraw.text(self, text, center, _caption_size(font_size, minimum_design_size), color, PixelDraw.unit(_s))

## Base of a round control: translucent navy disc, bevel, coloured pixel rim.
func _pad(center: Vector2, radius: float, rim: Color, fill_alpha: float = 0.55, rim_width: int = 1) -> void:
	PixelDraw.disc(self, center, radius, PixelDraw.unit(_s), Color(UiTheme.PANEL, fill_alpha), rim, rim_width)

func _draw() -> void :
	if game == null or not enabled: return
	var u: float = PixelDraw.unit(_s)
	var stick_color: Color = UiTheme.BLUE
	_pad(_stick_center, _stick_radius, Color(stick_color, 0.8))
	for axis in [Vector2.RIGHT, Vector2.DOWN]:
		var half: Vector2 = axis * _stick_radius * 0.6
		var thick: Vector2 = Vector2(axis.y, axis.x) * u
		draw_rect(Rect2((_stick_center - half - thick * 0.5).round(), (half * 2.0 + thick).round()), Color(stick_color, 0.22))
	PixelDraw.disc(self, _stick_center + _stick_vector * _stick_radius * 0.64, 36 * _s, u, Color(stick_color, 0.85 if _stick_id != -1 else 0.45))
	_caption("MOVE", _stick_center + Vector2(0, 120 * _s), 22, stick_color)
	var held: = _charge_id != -1
	var perfect: bool = _hit_timing.ready
	var hit_color: Color = UiTheme.RED if _cancel_armed else UiTheme.ACCENT if perfect or held and _gesture_is_serve else UiTheme.BLUE
	var smash: int = 0 if _cancel_armed or _is_serve_context() else _smash_state()
	if smash > 0 and not perfect: hit_color = Color("ff9a3c")
	_pad(_charge_center, _charge_radius, Color(hit_color, 0.9), 0.55, 2 if perfect else 1)
	var ratio: float = game.hud._charge_bar.value
	if held and ratio > 0:
		PixelDraw.arc(self, _charge_center, _charge_radius - 4 * u, u, - PI * 0.5, - PI * 0.5 + TAU * ratio, hit_color, 2)
	# Tired: the most power this hold can give (stamina_display / STAMINA_UX_PLAN).
	if held and not _gesture_is_serve and game.game_state == 2:
		var tuning = preload("res://scripts/gameplay_tuning.gd")
		var cap: float = 1.0 - tuning.TIRED_CHARGE_CAP * game.player_left.stamina.tiredness()
		if cap < 0.98:
			var ang: float = - PI * 0.5 + TAU * cap
			var dir := Vector2(cos(ang), sin(ang))
			draw_line(_charge_center + dir * (_charge_radius - 14 * u), _charge_center + dir * (_charge_radius + 4 * u), Color(1.0, 0.45, 0.2), 4.0 * _s)
	_draw_stamina_cost(held)
	_draw_shot_feedback()
	var knob: = _charge_center + _charge_vector * _charge_radius * 0.6
	PixelDraw.disc(self, knob, 28 * _s, u, Color(hit_color, 0.22), Color(0, 0, 0, 0), 1, false)
	_caption("CANCEL" if _cancel_armed else _hit_label(), _charge_center + Vector2(0, -2 * _s), 19, hit_color, 19)
	var serve_locked: bool = _is_serve_context() and bool(_serve_timing.get("locked", false))
	var subcaption: String = "HOLD + AIM"
	var preview: Dictionary = {} if _is_serve_context() else _shot_preview()
	if not preview.is_empty(): subcaption = "HOLD " + _shot_word(preview.hold)
	var footer: = "HIT"
	if smash == 2: footer = "SMASH"
	elif smash == 1: subcaption = "HOLD: STEP IN"
	if serve_locked:
		subcaption = "COMMITTED"
		footer = "CONTACT"
	elif held:
		subcaption = "LOCKED" if not _charge_owns_action and _gesture_is_serve else "NEXT SHOT" if not _charge_owns_action else "%d%%" % roundi(ratio * 100)
		footer = "CONTACT" if not _charge_owns_action and _gesture_is_serve else "NEXT SHOT" if not _charge_owns_action else "RELEASE TO HIT"
	if _cancel_armed: subcaption = "RELEASE"
	_caption(subcaption, _charge_center + Vector2(0, _second_caption_baseline(19, 15, 23, 19)), 15, UiTheme.INK, 19)
	if not _cancel_armed:
		_caption(footer, _charge_center + Vector2(0, 106 * _s), 20, hit_color, 23)

	if held:
		var cancel_color: Color = UiTheme.RED if _cancel_armed else UiTheme.MUTED
		_pad(_cancel_center, _cancel_radius, cancel_color, 0.94)
		_caption("CANCEL", _cancel_center + Vector2(0, 6 * _s), 15, cancel_color, 19)

	_draw_hit_timing()
	if _is_serve_context() or _serve_contact_flash > 0:
		_draw_serve_timing()
	if _show_serve_selector(): _draw_serve_selector()
	if not _is_serve_context():
		_draw_hit_guide()
	elif game.reaction_button and game.reaction_button._grade_flash_t > 0:
		_caption(game.reaction_button._grade_label, _charge_center + Vector2(0, -110 * _s), 22, UiTheme.ACCENT)


func _update_hit_timing(blocked: bool, real_delta: float = 0.0) -> void :
	if not enabled or blocked or _is_serve_context() or _cancel_armed:
		_hit_timing.clear()
		_timing_draw_flight = -1
		return
	var human = game.player_left.posture.human_contact
	if human == null or human.phase >= 0 or not human.has_method("release_timing_state"):
		_hit_timing.clear()
		_timing_draw_flight = -1
		return
	var held: bool = _charge_id != -1 and _charge_owns_action and not _gesture_is_serve
	_hit_timing.update(human.release_timing_state(), held, bool(Settings.get_value("gameplay.timing_vibration", true)))
	_move_closer_dir = _band_screen_side(human) if held else 0
	if not _hit_timing.active:
		_timing_draw_flight = -1
		return


	var target: float = maxf(TIMING_RING_MIN_GAP_FRACTION, sqrt(_hit_timing.ring_fraction))
	if _hit_timing.ready:
		_timing_draw_fraction = 0.0
	elif _timing_draw_flight != _hit_timing.flight_id or real_delta <= 0.0:
		_timing_draw_fraction = target
	else:
		_timing_draw_fraction = lerpf(_timing_draw_fraction, target, 1.0 - exp( - real_delta / TIMING_RING_SMOOTH_SECONDS))
	_timing_draw_flight = _hit_timing.flight_id


func _timing_radius() -> float:
	if not _hit_timing.active or _hit_timing.ready: return _charge_radius
	return lerpf(_charge_radius, _timing_ring_max, _timing_draw_fraction)

func _timing_arc_angles(radius: float) -> Vector2:


	var right: float = _timing_safe.end.x - _charge_center.x
	var bottom: float = _timing_safe.end.y - _charge_center.y
	var clips_right: bool = radius > right
	var clips_bottom: bool = radius > bottom
	if not clips_right and not clips_bottom: return Vector2(0.0, TAU)
	var right_angle: float = acos(clampf(right / radius, 0.0, 1.0))
	var bottom_angle: float = asin(clampf(bottom / radius, 0.0, 1.0))
	return Vector2(PI - bottom_angle if clips_bottom else right_angle, 
		TAU - right_angle if clips_right else TAU + bottom_angle)

func _timing_corner_arc_angles(radius: float) -> Vector2:


	var right: float = _timing_safe.end.x - _charge_center.x
	var bottom: float = _timing_safe.end.y - _charge_center.y
	if radius <= right or radius <= bottom: return Vector2.ZERO
	var start: float = acos(clampf(right / radius, 0.0, 1.0))
	var end: float = asin(clampf(bottom / radius, 0.0, 1.0))
	return Vector2(start, end) if end > start else Vector2.ZERO

func _draw_timing_arc(radius: float, angles: Vector2, color: Color, flash: float) -> void :
	if angles.y <= angles.x: return
	var u: float = PixelDraw.unit(_s)
	PixelDraw.arc(self, _charge_center, radius, u, angles.x, angles.y, Color(UiTheme.PANEL, 0.9), 4 + roundi(flash))
	PixelDraw.arc(self, _charge_center, radius, u, angles.x, angles.y, color.lerp(Color.WHITE, flash), 2 + roundi(flash))

## Which way on screen the lit side band is (-1 left, +1 right, 0 none): the MOVE CLOSER arrow.
func _band_screen_side(human) -> int:
	var hint: Dictionary = human.superblock_hint
	var camera: Camera3D = get_viewport().get_camera_3d()
	if hint.is_empty() or not hint.has("side") or camera == null: return 0
	var me = game.player_left
	var at: Vector3 = me.global_position
	var toward: Vector3 = at + me._get_forehand_axis() * float(hint.side)
	if camera.is_position_behind(at) or camera.is_position_behind(toward): return 0
	return 1 if camera.unproject_position(toward).x > camera.unproject_position(at).x else -1

## MOVE CLOSER: larger, pulsing, with an arrow to the side the ball is passing.
func _draw_move_closer(color: Color) -> void:
	var text: String = "MOVE CLOSER"
	if _move_closer_dir < 0: text = "<< " + text
	elif _move_closer_dir > 0: text = text + " >>"
	var size: int = _caption_size(22, 24)
	var font: Font = PixelDraw.font()
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.0126)   # about 2 per second
	var center: Vector2 = _timing_caption_center + Vector2(0, -10 * _s)
	var rect := Rect2(center - Vector2(width * 0.5 + 8 * _s, font.get_ascent(size) + 4 * _s), Vector2(width + 16 * _s, font.get_height(size) + 8 * _s))
	draw_style_box(_guide_caption_backing, rect)
	draw_rect(rect, Color(UiTheme.RED, 0.35 + 0.45 * pulse), false, maxf(2.0, PixelDraw.unit(_s) * 2.0))
	_caption(text, center, 22, color.lerp(Color.WHITE, 0.6 * pulse), 24)

## Risk (0..1) of the rally hold in progress; 0 when nothing is held.
func _hold_risk() -> float:
	if _charge_id == -1 or not _charge_owns_action or _gesture_is_serve or game == null or game.game_state != 2: return 0.0
	var handler = game.input_handler
	var me = game.player_left
	if handler == null or me == null or me.posture == null or not handler.serve_is_charging: return 0.0
	var human = me.posture.human_contact
	if human == null or not human.has_method("hold_risk"): return 0.0
	return human.hold_risk(float(handler.serve_charge_time))

func _draw_hit_timing() -> void :
	if _is_serve_context() or _cancel_armed: return
	var color: Color = UiTheme.ACCENT if _hit_timing.ready else Color("ffe5a3")
	# Risk of the hold in progress: yellow, then red when this much power on this low a ball
	# is likely to go into the net (the rule itself: human_contact_controller.hold_risk).
	var risk: float = _hold_risk()
	var Tune = preload("res://scripts/gameplay_tuning.gd")
	if risk >= Tune.RISK_RED: color = UiTheme.RED
	elif risk >= Tune.RISK_YELLOW: color = Color("ffb23c")
	if _hit_timing.active:
		var radius: float = _timing_radius()
		var angles: Vector2 = _timing_arc_angles(radius)
		var flash: float = _hit_timing.flash_strength()


		_draw_timing_arc(radius, angles, color, flash)
		_draw_timing_arc(radius, _timing_corner_arc_angles(radius), color, flash)
	if _hit_timing.caption == "MOVE CLOSER" and risk < Tune.RISK_RED:
		_draw_move_closer(Color("ffb23c"))
	elif not _hit_timing.caption.is_empty():

		draw_style_box(_guide_caption_backing, _timing_caption_rect)
		_caption("TOO LOW" if risk >= Tune.RISK_RED else _hit_timing.caption, _timing_caption_center, 16, color if _hit_timing.active else UiTheme.RED, 19)

## Shot feedback at the HIT ring (STAMINA_UX / player feel): when a rally shot is released,
## its name pops above the ring (DINK, RESET, FAST DINK, DRIVE ...), and a flick shows
## chevrons running out of the ring in the swipe direction.
const SHOT_FB_SECONDS := 0.7
var _shot_fb_age := 99.0
var _shot_fb_name := ""
var _shot_fb_dir := Vector2.ZERO
var _shot_fb_color := Color.WHITE

func show_shot_feedback(shot_name: String, flick_dir: Vector2, touch: bool) -> void:
	_shot_fb_name = shot_name.replace("_", " ")
	_shot_fb_dir = flick_dir if flick_dir.length() >= 0.25 else Vector2.ZERO
	_shot_fb_color = Color("7dff9a") if touch else Color("ff9a3c")
	_shot_fb_age = 0.0
	_timing_word = ""
	queue_redraw()

## The release timing word (PERFECT / GOOD / EARLY / LATE), above the shot name.
var _timing_word := ""
const TIMING_WORD_COLORS := {"PERFECT": Color("7dff9a"), "GOOD": Color("ffe5a3"), "EARLY": Color("ff6b5e"), "LATE": Color("ff6b5e")}
func show_timing_word(word: String) -> void:
	_timing_word = word
	queue_redraw()

func _draw_shot_feedback() -> void:
	if _shot_fb_age >= SHOT_FB_SECONDS or _shot_fb_name.is_empty(): return
	if _timing_word != "":
		var tw: float = _shot_fb_age / SHOT_FB_SECONDS
		_caption(_timing_word, _charge_center + Vector2(0, -_charge_radius * (1.6 + 0.35 * tw)), 18, Color(TIMING_WORD_COLORS.get(_timing_word, Color.WHITE), 1.0 - tw * tw))
	var t: float = _shot_fb_age / SHOT_FB_SECONDS
	var fade: float = 1.0 - t * t
	# Word: pops up out of the ring and fades.
	var pop: float = 1.0 + 0.35 * maxf(0.0, 1.0 - _shot_fb_age / 0.12)
	_caption(_shot_fb_name, _charge_center + Vector2(0, -_charge_radius * (1.25 + 0.35 * t)), int(22 * pop), Color(_shot_fb_color, fade))
	# Chevrons along the flick, running outward.
	if _shot_fb_dir == Vector2.ZERO: return
	var dir: Vector2 = _shot_fb_dir.normalized()
	var side: Vector2 = Vector2(-dir.y, dir.x)
	var w: float = 14.0 * _s
	for k in 3:
		var d: float = _charge_radius * (0.55 + 0.32 * float(k) + 0.6 * t)
		var tip: Vector2 = _charge_center + dir * d
		var a: float = fade * (1.0 - 0.25 * float(k))
		draw_polyline(PackedVector2Array([tip - dir * w + side * w, tip, tip - dir * w - side * w]), Color(_shot_fb_color, a), 5.0 * _s)

## Stamina cost chip beside the HIT ring while a rally shot is held (STAMINA_UX_PLAN.md):
## "-1" for a tap (rest), the drive cost growing with your drive streak, amber when the
## shot would take you under the penalty line, red under 25.
func _draw_stamina_cost(held: bool) -> void:
	if not bool(Settings.get_value("gameplay.stamina_bars", false)): return   # stamina numbers are off with the bars
	if not held or _gesture_is_serve or _cancel_armed or game.game_state != 2: return
	var handler = game.input_handler
	var me = game.player_left
	if handler == null or me == null or not handler.serve_is_charging: return
	var tuning = preload("res://scripts/gameplay_tuning.gd")
	if not tuning.STAMINA_ON: return
	var touch: bool = float(handler.serve_charge_time) < preload("res://scripts/human_shot_choice.gd").TAP_SECONDS
	var cost: float = 1.0 if touch else me.stamina.contact_cost("DRIVE", 12.0) + tuning.STREAK_COST * float(me.stamina.power_streak)
	var after: float = float(me.stamina.value) - cost
	var color: Color = Color(1, 1, 1) if after >= tuning.STAMINA_PENALTY_AT else (Color(1.0, 0.68, 0.2) if after >= 25.0 else Color(1.0, 0.3, 0.25))
	_caption("-%d" % int(round(cost)), _charge_center + Vector2(_charge_radius * 0.95, -_charge_radius * 0.95), 20, color)

func _draw_serve_selector() -> void :
	var active: = _serve_selector_id != -1
	var color: Color = UiTheme.ACCENT if active else UiTheme.MUTED
	_pad(_serve_selector_center, _serve_selector_radius, Color(color, 0.75), 0.4)
	var options: = _serve_options()
	for i in range(options.size()):
		var angle: float = - PI * 0.5 + TAU * i / options.size() + _serve_selector_rotation
		var axis: = Vector2.from_angle(angle)
		draw_line((_serve_selector_center + axis * (_serve_selector_radius - 5 * _s)).round(), (_serve_selector_center + axis * (_serve_selector_radius + 5 * _s)).round(), color, PixelDraw.unit(_s), false)
	var option: = _selected_serve_option()
	var delivery: String = str(option.get("delivery", "Volley")).to_upper()
	if delivery == "EXPERIMENTAL DROP":
		# Preserve the selected style above the wheel, including during Cancel.
		# Full delivery names/descriptions remain unchanged in option metadata.
		_caption(str(option.get("label", "Flat")), _serve_selector_center + Vector2(0, -79 * _s), 18, UiTheme.MUTED, 19)
		_caption("EXPER.", _serve_selector_center + Vector2(0, -8 * _s), 13, UiTheme.INK, 19)
		_caption("DROP", _serve_selector_center + Vector2(0, 23 * _s), 13, UiTheme.MUTED, 19)
	else:
		_caption("SERVE", _serve_selector_center + Vector2(0, -79 * _s), 17, UiTheme.MUTED, 19)
		_caption(str(option.get("label", "Flat")), _serve_selector_center + Vector2(0, -2 * _s), 18, UiTheme.INK, 19)
		_caption(delivery, _serve_selector_center + Vector2(0, _second_caption_baseline(18, 13, 21, 19)), 13, UiTheme.MUTED, 19)
	_caption("ROTATE", _serve_selector_center + Vector2(0, 84 * _s), 16, color, 19)
	var pointer: = PackedVector2Array([_serve_selector_center + Vector2(-5, -65) * _s, _serve_selector_center + Vector2(5, -65) * _s, _serve_selector_center + Vector2(0, -58) * _s])
	draw_colored_polygon(pointer, color)

func _draw_serve_timing() -> void :
	var phase: String = str(_serve_timing.get("phase", "HELD"))
	if _serve_contact_flash > 0:
		PixelDraw.ring(self, _charge_center, _charge_radius + 12 * _s, PixelDraw.unit(_s), UiTheme.ACCENT, 2)
		_caption("CONTACT", _charge_center + Vector2(0, -111 * _s), 20, UiTheme.ACCENT, 19)
	elif phase not in ["", "IDLE", "HELD"]:
		var progress: float = clampf(float(_serve_timing.get("progress", 0.0)), 0, 1)
		var radius: = lerpf(_charge_radius + 25 * _s, _charge_radius * 0.58, progress)
		PixelDraw.ring(self, _charge_center, radius, PixelDraw.unit(_s), UiTheme.ACCENT, 1)
		_caption(phase.replace("_", " "), _charge_center + Vector2(0, -111 * _s), 18, UiTheme.MUTED, 19)

func _cache_hit_guide() -> void :

	_shot_button_radius = 46.0 * _s
	_cancel_center = _charge_center + Vector2(64, -294) * _s
	_cancel_radius = 40.0 * _s
	_guide_nodes = PackedVector2Array()
	_guide_labels = PackedVector2Array()
	for degrees in [-170.0, -130.0, -90.0]:
		var center: Vector2 = _charge_center + Vector2.from_angle(deg_to_rad(degrees)) * 174.0 * _s
		_guide_nodes.append(center)
		_guide_labels.append(center + Vector2(0, 6 * _s))
	var safe: Rect2 = Layout.safe_rect(get_viewport())


	# Same stair-cornered pixel plate as the HUD pills (no margins: drawn into a given rect).
	_guide_caption_backing = PixelStyle.plate(Color(UiTheme.PANEL, 0.93), _s, 1)
	_guide_caption_backing.set_content_margin_all(0)
	var status_font: Font = PixelDraw.font()
	var status_size: int = _caption_size(16, 19)
	var status_width: float = status_font.get_string_size("MOVE CLOSER", HORIZONTAL_ALIGNMENT_LEFT, -1, status_size).x
	_timing_caption_rect = Rect2(_timing_caption_center - Vector2(status_width * 0.5 + 4 * _s, status_font.get_ascent(status_size) + 2 * _s), Vector2(status_width + 8 * _s, status_font.get_height(status_size) + 4 * _s))

	_guide_caption_rects.clear()
	for index in 4:
		var text: String = GUIDE_LABELS[index] if index < 3 else "CENTER · FLAT"
		var center: Vector2 = _guide_labels[index] if index < 3 else _guide_flat
		var font_size: int = _caption_size(18 if index < 3 else 14, 19)
		var font: Font = PixelDraw.font()
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var rect: = Rect2(center - Vector2(width * 0.5 + 4 * _s, font.get_ascent(font_size) + 2 * _s), Vector2(width + 8 * _s, font.get_height(font_size) + 4 * _s))
		rect.position.y = minf(rect.position.y, safe.end.y - rect.size.y)
		_guide_caption_rects.append(rect)

func _draw_hit_guide() -> void :
	if HumanShots.ENABLED: return
	for index in 3:
		var chosen: bool = _charge_id != -1 and _gesture_sector == GUIDE_LABELS[index]
		var color: Color = UiTheme.ACCENT if chosen else UiTheme.MUTED
		var center: Vector2 = _guide_nodes[index]
		_pad(center, _shot_button_radius, color, 0.96, 2 if chosen else 1)
		if chosen:
			var tip: Vector2 = center + _charge_vector * _shot_button_radius * 0.65
			draw_line(center.round(), tip.round(), Color(color, 0.6), PixelDraw.unit(_s), false)
			PixelDraw.disc(self, tip, 12 * _s, PixelDraw.unit(_s), Color(color, 0.3), Color(0, 0, 0, 0), 1, false)
		_caption(GUIDE_LABELS[index], _guide_labels[index], 16, color, 19)
	if _cancel_armed:
		_caption("CANCEL ON RELEASE", _charge_center + Vector2(0, 106 * _s), 16, UiTheme.RED, 19)

func camera_occlusion_regions() -> Array[Rect2]:
	var regions: Array[Rect2] = []
	if not enabled or not visible or _blocked(): return regions
	var padding: float = 8.0 * _s
	if not _is_serve_context():
		for center in _guide_nodes:
			regions.append(Rect2(center - Vector2.ONE * _shot_button_radius, Vector2.ONE * _shot_button_radius * 2).grow(padding))
	if _charge_id != -1:
		regions.append(Rect2(_cancel_center - Vector2.ONE * _cancel_radius, Vector2.ONE * _cancel_radius * 2).grow(padding))
	if not _hit_timing.caption.is_empty(): regions.append(_timing_caption_rect.grow(padding))
	return regions
