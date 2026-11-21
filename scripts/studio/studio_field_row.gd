extends HBoxContainer
## Desktop Pose Studio: one numeric inspector row (a float field, or one axis of a vector field).
## [lock][label | indent + axis][slider with stage ticks][value][reset][A/B] (+ foot-plant stop).
## Slider + typed value + arrow-key nudge (Shift = 0.1x) + track ticks (wind-up / contact /
## finish / last saved / foot-plant stop) + per-field reset + hold-to-compare + gameplay lock.
## Reset and A/B are small icon buttons shown while the row is hovered or focused (their
## space is kept, so nothing moves). Every write goes through studio.set_field; a slider drag
## is one undo step (begin/end_edit).

const Theme_ = preload("res://scripts/studio/studio_theme.gd")
const STAGE_COLORS := [Color("bd80ff"), Color("ffdc62"), Color("58dfdb")]
const SAVED_COLOR := Color("eef5fa")
const STOP_COLOR := Color("ff6b5e")
const LABEL_W := 140.0     # label column (points); longer labels go on a line above (inspector)
const INDENT := 14.0       # vector axis rows
const LOCK_W := 12.0
const SPIN_W := 88.0
const ICON_W := 24.0
const SEP := 4
const LOCK_TIP := "Gameplay field: changes how shots play, not only the look."

var studio
var field := ""
var axis := -1
var desc: Dictionary = {}
var gameplay := false
var wrapped := false
var has_value := true
var slider: HSlider
var spin: SpinBox
var label: Label
var reset_button: Button
var compare_button: Button
var stop_label: Label
var _ticks: Control
var _keys: Array = [null, null, null]
var _saved = null
var _stop = null
var _sync := false
var _hovered := false
var locked := false        # Gameplay edit lock (studio.gameplay_locked): slider and value disabled
var _tip := ""
var _focused := false

func setup(owner_studio, d: Dictionary, component: int, caption: String, is_gameplay: bool, is_wrapped: bool, indent := false) -> void:
	studio = owner_studio; desc = d; field = d.field; axis = component; gameplay = is_gameplay; wrapped = is_wrapped
	var id := field + ("" if axis < 0 else "_%d" % axis)
	name = "Row_" + id
	add_theme_constant_override("separation", SEP)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var lock := Lock.new(); lock.name = "Lock_" + id; lock.visible_lock = gameplay
	lock.custom_minimum_size = Vector2(LOCK_W, 0)
	lock.tooltip_text = LOCK_TIP if gameplay else ""
	lock.mouse_filter = Control.MOUSE_FILTER_PASS if gameplay else Control.MOUSE_FILTER_IGNORE
	add_child(lock)
	label = Label.new(); label.name = "Label_" + id; label.text = caption
	label.custom_minimum_size.x = LABEL_W; label.mouse_filter = Control.MOUSE_FILTER_PASS
	if indent:
		label.custom_minimum_size.x = LABEL_W - INDENT
		var sp := Control.new(); sp.name = "Indent_" + id; sp.custom_minimum_size.x = INDENT - SEP
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(sp)
		label.theme_type_variation = &"SmallLabel"
	label.visible = caption != ""
	add_child(label)
	var track := Control.new(); track.name = "Track_" + id
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL; track.custom_minimum_size = Vector2(80, Theme_.TARGET)
	track.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(track)
	slider = HSlider.new(); slider.name = "Slider_" + id
	slider.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slider.min_value = float(d.min); slider.max_value = float(d.max); slider.step = 0.0001
	slider.scrollable = false; slider.focus_mode = Control.FOCUS_CLICK
	slider.tooltip_text = "Drag (one undo step) · Up/Down or Left/Right nudge %s · Shift = 0.1x" % str(d.step)
	track.add_child(slider)
	_ticks = Control.new(); _ticks.name = "Ticks_" + id; _ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _ticks.draw.connect(_draw_ticks)
	track.add_child(_ticks)
	spin = SpinBox.new(); spin.name = "Spin_" + id
	spin.min_value = float(d.min); spin.max_value = float(d.max); spin.step = 0.0001
	spin.allow_greater = wrapped; spin.allow_lesser = wrapped  # wrapped angles: typed 190 wraps to -170
	spin.custom_arrow_step = float(d.step); spin.select_all_on_focus = true
	spin.custom_minimum_size.x = SPIN_W; spin.update_on_text_changed = false
	spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(spin)
	reset_button = _small("Reset_" + id, "reset", "Reset to the last saved value (undoable)")
	compare_button = _small("Compare_" + id, "compare", "A/B: hold to show the saved value; release to go back")
	stop_label = Label.new(); stop_label.name = "Stop_" + id; stop_label.theme_type_variation = &"SmallLabel"
	stop_label.add_theme_color_override("font_color", STOP_COLOR)
	stop_label.visible = false
	add_child(stop_label)
	slider.drag_started.connect(func(): studio.begin_edit("drag " + field))
	slider.drag_ended.connect(func(_changed): studio.end_edit())
	slider.value_changed.connect(_on_value)
	spin.value_changed.connect(_on_value)
	spin.get_line_edit().text_submitted.connect(func(_t): spin.get_line_edit().release_focus())
	slider.gui_input.connect(_nudge_input)
	spin.get_line_edit().gui_input.connect(_nudge_input)
	reset_button.pressed.connect(reset)
	compare_button.button_down.connect(func(): studio.compare_begin(field, axis))
	compare_button.button_up.connect(func(): studio.compare_end())
	# Hover / focus reveal of the reset and A/B buttons.
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_on_exit)
	for c in [slider, spin.get_line_edit(), reset_button, compare_button, label, track]:
		c.mouse_entered.connect(_set_hover.bind(true))
	for c in [slider, spin.get_line_edit()]:
		c.focus_entered.connect(_set_focus.bind(true))
		c.focus_exited.connect(_set_focus.bind(false))
	_update_reveal()

func set_tip(t: String) -> void:
	_tip = t
	label.tooltip_text = t
	spin.tooltip_text = t

const LOCKED_TIP := "Locked: gameplay field (changes how shots play). Turn on Gameplay edit in the top bar to change it."

## Gameplay edit lock: the row shows its value but takes no input.
func set_locked(on: bool) -> void:
	if on == locked: return
	locked = on
	slider.editable = not on
	spin.editable = not on
	reset_button.disabled = on or reset_button.disabled
	label.tooltip_text = LOCKED_TIP if on else _tip
	spin.tooltip_text = LOCKED_TIP if on else _tip
	modulate.a = 0.55 if on else 1.0

func _small(n: String, icon_name: String, tip: String) -> Button:
	var b := Theme_.tool_button(n, "", icon_name, tip)
	b.custom_minimum_size = Vector2(ICON_W, Theme_.TARGET)
	add_child(b); return b

func _set_hover(on: bool) -> void:
	if _hovered == on: return
	_hovered = on; _update_reveal()

func _on_exit() -> void:
	# Leaving into a child keeps the row hovered.
	if get_global_rect().has_point(get_global_mouse_position()): return
	_set_hover(false)

func _set_focus(on: bool) -> void:
	_focused = on; _update_reveal()

func _update_reveal() -> void:
	var a := 1.0 if (_hovered or _focused) else 0.0
	reset_button.modulate.a = a
	compare_button.modulate.a = a

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hovered: _on_exit()

func _on_value(v: float) -> void:
	if not _sync: _write(v)

func _write(v: float) -> void:
	var r: Dictionary = studio.set_field(field, axis, v)
	if r.get("stopped") != null: show_stop(r.stopped)
	else: show_stop(null)

func nudge(direction: int, fine: bool) -> void:
	var step := float(desc.step) * (0.1 if fine else 1.0)
	var r: Dictionary = studio.set_field(field, axis, value() + step * direction)
	show_stop(r.get("stopped"))

func reset() -> void:
	if _saved == null: return
	show_stop(studio.set_field(field, axis, float(_saved)).get("stopped"))

func value() -> float: return spin.value

func _nudge_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed: return
	var dir := 0
	if event.keycode in [KEY_UP, KEY_RIGHT]: dir = 1
	elif event.keycode in [KEY_DOWN, KEY_LEFT]: dir = -1
	if dir == 0: return
	nudge(dir, event.shift_pressed)
	get_viewport().set_input_as_handled()

## keys: [windup, contact, finish] values (null when that stage does not exist); saved: file value.
func sync(current: float, keys: Array, saved) -> void:
	_sync = true
	slider.set_value_no_signal(current)
	spin.set_value_no_signal(current)
	_sync = false
	_keys = keys; _saved = saved
	reset_button.disabled = locked or saved == null or is_equal_approx(float(saved), current)
	compare_button.disabled = reset_button.disabled
	_ticks.queue_redraw()

func show_stop(stop) -> void:
	_stop = stop
	stop_label.visible = stop != null
	if stop != null: stop_label.text = "stop %.3f" % float(stop.get("at", 0.0)); stop_label.tooltip_text = str(stop.get("reason", ""))
	_ticks.queue_redraw()

func state() -> Dictionary:
	return {"field": field, "axis": axis, "value": value(), "keys": _keys, "saved": _saved,
		"gameplay": gameplay, "locked": locked, "wrapped": wrapped, "stopped": _stop, "tools_shown": _hovered or _focused}

func _x(v: float) -> float:
	var span := slider.max_value - slider.min_value
	var grab := 8.0  # keep ticks inside the grabber travel
	return grab + (_ticks.size.x - grab * 2.0) * clampf((v - slider.min_value) / maxf(span, 0.000001), 0.0, 1.0)

func _draw_ticks() -> void:
	var h := _ticks.size.y
	for st in 3:
		if _keys.size() > st and _keys[st] != null:
			var x := _x(float(_keys[st]))
			_ticks.draw_line(Vector2(x, 2), Vector2(x, 8), STAGE_COLORS[st], 2.0)
	if _saved != null:
		var xs := _x(float(_saved))
		_ticks.draw_line(Vector2(xs, h - 8), Vector2(xs, h - 2), SAVED_COLOR, 2.0)
	if _stop != null:
		var xt := _x(float(_stop.get("at", 0.0)))
		_ticks.draw_rect(Rect2(xt - 3, h * 0.5 - 3, 6, 6), STOP_COLOR)

class Lock extends Control:
	var visible_lock := false
	func _draw() -> void:
		if not visible_lock: return
		var c := size * 0.5
		var col := Color("ffdc62")
		draw_arc(c + Vector2(0, -2), 3.0, PI, TAU, 10, col, 1.5)
		draw_rect(Rect2(c.x - 4, c.y - 1, 8, 6), col)
