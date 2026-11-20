extends VBoxContainer
## Desktop Pose Studio: timeline under the preview. Stage keys (wind-up / contact / finish),
## real-time scrub track over the engine's sequence (ed._timeline) with coloured stage markers
## and a playhead, play / pause, loop, speed (1x, 1/2, 1/4), strong / weak backswing, step one
## 30 Hz game tick. Drives the engine only. refresh() runs every frame but only writes a
## control when its value changed (no per-frame allocations while idle).

const Ui = preload("res://scripts/ui/game_ui_theme.gd")
const Theme_ = preload("res://scripts/studio/studio_theme.gd")
const STAGE_COLORS := [Color("bd80ff"), Color("ffdc62"), Color("58dfdb")]
const STAGE_NAMES := ["Wind-up", "Contact", "Finish"]
const TICK := 1.0 / 30.0
const SPEEDS := [1.0, 0.5, 0.25]
const SPEED_TEXT := ["1x", "½x", "¼x"]

var studio
var stage_buttons: Array[Button] = []
var play_button: Button
var loop_toggle: Button
var speed_buttons: Array[Button] = []
var speed_index := 0
var strong_button: Button
var weak_button: Button
var step_back: Button
var step_fwd: Button
var scrubber: ScrubTrack
var time_label: Label
var loop := false
var _sync := false
var _transport: Array[Button] = []
var _was_playing := -1
var _last_t := -1.0
var _last_code := -2   # -1 playing / scrubbed, else stage*4 + has*2 + base

func build(owner_studio) -> void:
	studio = owner_studio
	name = "Timeline"
	add_theme_constant_override("separation", Theme_.SP1)
	var row := HFlowContainer.new(); row.name = "TimelineControls"; add_child(row)
	row.add_theme_constant_override("h_separation", Theme_.SP2); row.add_theme_constant_override("v_separation", Theme_.SP1)
	var stages := Theme_.segment(row, "StageSeg")
	for i in 3:
		var b := Theme_.tool_button(["StageWindup", "StageContact", "StageFinish"][i], STAGE_NAMES[i], "",
			"Edit the %s key (Alt+%d · Tab / Shift+Tab cycles)" % [["wind-up", "contact", "finish"][i], i + 1], true)
		b.add_theme_color_override("font_color", STAGE_COLORS[i]); b.add_theme_color_override("font_hover_color", STAGE_COLORS[i])
		b.add_theme_color_override("font_pressed_color", Ui.PANEL); b.add_theme_color_override("font_hover_pressed_color", Ui.PANEL)
		var sel := Theme_._box(STAGE_COLORS[i], STAGE_COLORS[i].darkened(0.3), 1, 4, Theme_.TOOL_MX, Theme_.margin_y)
		b.add_theme_stylebox_override("pressed", sel); b.add_theme_stylebox_override("hover_pressed", sel)
		b.pressed.connect(studio.set_stage.bind(i))
		stages.add_child(b)
		stage_buttons.append(b)
	var tr := Theme_.segment(row, "TransportSeg")
	step_back = _tool(tr, "StepBack", "step_back", "Back one game tick (comma)")
	step_back.pressed.connect(step.bind(-1))
	play_button = _tool(tr, "PlayButton", "play", "Play / pause (Space)")
	play_button.pressed.connect(toggle_play)
	step_fwd = _tool(tr, "StepForward", "step_forward", "Forward one game tick (period)")
	step_fwd.pressed.connect(step.bind(1))
	loop_toggle = _tool(tr, "LoopToggle", "loop", "Loop playback (L)")
	loop_toggle.toggle_mode = true
	loop_toggle.toggled.connect(func(on): loop = on)
	var sp := Theme_.segment(row, "SpeedPicker")
	sp.get_parent().tooltip_text = "Playback speed"
	var group := ButtonGroup.new()
	for i in 3:
		var b := Theme_.tool_button("Speed%d" % i, SPEED_TEXT[i], "", "Playback speed %s" % SPEED_TEXT[i], true)
		b.button_group = group
		b.set_pressed_no_signal(i == 0)
		b.pressed.connect(set_speed_index.bind(i))
		sp.add_child(b)
		speed_buttons.append(b)
	var vr := Theme_.segment(row, "VariantSeg")
	strong_button = Theme_.tool_button("StrongButton", "Strong", "", "Play a generated longer backswing (saved poses unchanged)", true)
	strong_button.pressed.connect(play_variant.bind(1))
	vr.add_child(strong_button)
	weak_button = Theme_.tool_button("WeakButton", "Weak", "", "Play a generated shorter backswing (saved poses unchanged)", true)
	weak_button.pressed.connect(play_variant.bind(2))
	vr.add_child(weak_button)
	_transport = [play_button, step_back, step_fwd, loop_toggle, strong_button, weak_button]
	var srow := HBoxContainer.new(); srow.name = "ScrubRow"; srow.add_theme_constant_override("separation", Theme_.SP2)
	add_child(srow)
	scrubber = ScrubTrack.new(); scrubber.name = "Scrubber"
	scrubber.tooltip_text = "Real-time sequence (charge -> release), drag to scrub. Marks: purple wind-up, gold contact, cyan finish. Scrubbing previews only; it does not change the edited key."
	scrubber.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrubber.value_changed.connect(seek)
	srow.add_child(scrubber)
	time_label = Theme_.small_label("TimeLabel", "")
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	srow.add_child(time_label)
	_size_time_label.call_deferred()
	for sg in ["pose_selected", "stage_changed", "pose_edited", "pose_reloaded"]:
		studio.connect(sg, update_marks.unbind(1))

## Fixed width: the longest text it shows, so the track does not jump while playing.
func _size_time_label() -> void:
	var font := time_label.get_theme_font("font")
	var fs := time_label.get_theme_font_size("font_size")
	var w := 0.0
	for t in ["00.000 / 00.000 s · tick 000", "Body stance (one key)", "Key: Wind-up", "Static pose"]:
		w = maxf(w, font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	time_label.custom_minimum_size.x = ceilf(w) + 2

func _tool(parent: Node, n: String, icon_name: String, tip: String) -> Button:
	var b := Theme_.tool_button(n, "", icon_name, tip)
	parent.add_child(b); return b

func _ed(): return studio.engine if studio and is_instance_valid(studio.engine) else null

func motion() -> bool:
	var ed = _ed()
	return ed != null and studio.key != "" and ed._has_motion()

func toggle_play() -> void:
	var ed = _ed()
	if not motion(): return
	studio.stop_drag()
	if ed._variant_mode != 0: ed._play_variant(ed._variant_mode)
	else: ed._toggle_play()
	update_marks()
	refresh()

func stop() -> void:
	var ed = _ed()
	if ed == null: return
	loop = false; loop_toggle.set_pressed_no_signal(false)
	ed._stop(); refresh()

func set_speed_index(i: int) -> void:
	var ed = _ed()
	speed_index = clampi(i, 0, 2)
	for j in 3: speed_buttons[j].set_pressed_no_signal(j == speed_index)
	if ed: ed._timeline.speed = SPEEDS[speed_index]
	_last_code = -2

func play_variant(mode: int) -> void:
	var ed = _ed()
	if not motion(): refresh(); return
	studio.stop_drag()
	if ed._variant_mode == mode and not ed._playing:
		# Second press on an idle variant: back to the authored swing.
		ed._clear_variant(); ed._stop(); ed._refresh_preview()
	else:
		ed._play_variant(mode)
	update_marks()
	refresh()

func seek(t: float) -> void:
	if _sync: return
	var ed = _ed()
	if not motion() or not ed._timeline._configure(): return
	studio.stop_drag()
	ed._timeline._seek(clampf(t, 0.0, 1.0))
	studio.stage_preview_changed()
	update_marks()
	refresh()

## One 30 Hz game tick along the real-time sequence.
func step(dir: int) -> void:
	var ed = _ed()
	if not motion() or not ed._timeline._configure(): return
	studio.stop_drag()
	var tl = ed._timeline
	var dur: float = maxf(tl.sequence.duration, 0.001)
	var from: float = tl.elapsed if tl.active else 0.0
	# Next / previous point on the 1/30 s grid (from an off-grid time: the nearest one that way).
	var tick_i := (floori(from / TICK + 0.001) + 1) if dir >= 0 else (ceili(from / TICK - 0.001) - 1)
	tl._seek(clampf(tick_i * TICK, 0.0, dur) / dur)
	studio.stage_preview_changed()
	update_marks()
	refresh()

## Stage markers on the scrub track (fractions of the sequence). Called on pose / stage /
## edit / variant changes, never per frame.
func update_marks() -> void:
	var ed = _ed()
	if not motion() or not ed._timeline._configure():
		scrubber.set_marks([], 0.0); return
	var s = ed._timeline.sequence
	var dur: float = maxf(s.duration, 0.001)
	scrubber.set_marks([s.prefix_seconds / dur, (s.prefix_seconds + s.release_seconds) / dur,
		(s.prefix_seconds + s.stroke_seconds) / dur], s.duration)

## Called every frame by the studio: only writes what changed.
func refresh() -> void:
	var ed = _ed()
	var has := motion()
	var active: bool = ed != null and ed._timeline.active
	var playing: bool = ed != null and ed._playing
	for i in 3:
		var dis := not has and i != 1
		if stage_buttons[i].disabled != dis: stage_buttons[i].disabled = dis
		var on: bool = ed != null and studio.key != "" and ed._stage == i and not active and not playing
		if stage_buttons[i].button_pressed != on: stage_buttons[i].set_pressed_no_signal(on)
	for b in _transport:
		if b.disabled == has: b.disabled = not has
	for b in speed_buttons:
		if b.disabled == has: b.disabled = not has
	if scrubber.editable != has: scrubber.editable = has
	if ed == null: return
	if _was_playing != int(playing):
		_was_playing = int(playing)
		play_button.icon = Theme_.icon("pause" if playing else "play")
		play_button.tooltip_text = ("Pause" if playing else "Play") + " (Space)"
	if strong_button.button_pressed != (ed._variant_mode == 1): strong_button.set_pressed_no_signal(ed._variant_mode == 1)
	if weak_button.button_pressed != (ed._variant_mode == 2): weak_button.set_pressed_no_signal(ed._variant_mode == 2)
	var tl = ed._timeline
	if active and tl.sequence.duration > 0.0:
		var t: float = tl.elapsed / tl.sequence.duration
		if t != _last_t or _last_code != -1:
			_last_t = t; _last_code = -1
			_sync = true
			scrubber.set_value_no_signal(t); scrubber.queue_redraw()
			_sync = false
			scrubber.phase = String(tl.sample.get("phase", ""))
			time_label.text = "%.3f / %.3f s · tick %d" % [tl.elapsed, tl.sequence.duration, roundi(tl.elapsed / TICK)]
	else:
		var code: int = int(ed._stage) * 4 + int(has) * 2 + int(ed._base)
		if code != _last_code:
			_last_code = code; _last_t = -1.0
			_sync = true
			scrubber.set_value_no_signal(0.0); scrubber.phase = ""; scrubber.queue_redraw()
			_sync = false
			time_label.text = ("Key: " + STAGE_NAMES[ed._stage]) if has else ("Body stance (one key)" if ed._base else "Static pose")

## Studio _process hook: keep looping.
func tick() -> void:
	var ed = _ed()
	if ed == null: return
	if loop and motion() and not ed._playing:
		if ed._variant_mode != 0: ed._play_variant(ed._variant_mode)
		else: ed._toggle_play()
	refresh()

func state() -> Dictionary:
	var ed = _ed()
	var tl = ed._timeline if ed else null
	return {"playing": ed != null and ed._playing, "loop": loop, "speed": SPEEDS[speed_index],
		"variant": ed._variant_mode if ed else 0, "active": tl != null and tl.active,
		"t": (tl.elapsed / maxf(tl.sequence.duration, 0.001)) if tl and tl.active else 0.0,
		"seconds": tl.elapsed if tl and tl.active else 0.0, "marks": scrubber.marks}

## Scrub track: a Range (0..1) drawn as a rail with stage markers, progress and a playhead.
## Click or drag anywhere on it to scrub. 28 pt tall.
class ScrubTrack extends Range:
	const H := 28.0
	var editable := true
	var marks: Array = []          # [windup, contact, finish] fractions
	var duration := 0.0
	var phase := ""
	var _drag := false

	func _init() -> void:
		min_value = 0.0; max_value = 1.0; step = 0.0001
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(160, H)

	func set_marks(m: Array, dur: float) -> void:
		marks = m; duration = dur; queue_redraw()

	func _x(f: float) -> float:
		return 8.0 + (size.x - 16.0) * clampf(f, 0.0, 1.0)

	func _gui_input(e: InputEvent) -> void:
		if not editable: return
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			_drag = e.pressed
			if e.pressed: _set_from(e.position.x)
			accept_event()
		elif e is InputEventMouseMotion and _drag:
			_set_from(e.position.x)
			accept_event()

	func _set_from(px: float) -> void:
		value = clampf((px - 8.0) / maxf(size.x - 16.0, 1.0), 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		var y := size.y * 0.5
		var rail := Rect2(8.0, y - 3.0, size.x - 16.0, 6.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color("0d1f2b"))
		draw_rect(rail, Color("23404f"))
		var dim := 1.0 if editable else 0.35
		if editable and value > 0.0:
			draw_rect(Rect2(rail.position, Vector2(_x(value) - 8.0, rail.size.y)), Color(0.52, 0.81, 1.0, 0.45))
		var cols := [Color("bd80ff"), Color("ffdc62"), Color("58dfdb")]
		for i in mini(3, marks.size()):
			var x := _x(float(marks[i]))
			var c: Color = cols[i]; c.a = dim
			draw_line(Vector2(x, 4.0), Vector2(x, size.y - 4.0), c, 2.0)
			draw_colored_polygon(PackedVector2Array([Vector2(x - 4.0, 2.0), Vector2(x + 4.0, 2.0), Vector2(x, 7.0)]), c)
		if editable and (value > 0.0 or not phase.is_empty()):
			var px := _x(value)
			draw_line(Vector2(px, 2.0), Vector2(px, size.y - 2.0), Color("eef5fa"), 2.0)
			draw_circle(Vector2(px, y), 5.0, Color("eef5fa"))
		if phase != "":
			var font := get_theme_font("font")
			var fs := 13
			var w := font.get_string_size(phase, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if w + 24.0 < size.x:
				var tx := clampf(_x(value) + 10.0, 10.0, size.x - w - 10.0)
				if tx < _x(value) and tx + w > _x(value) - 10.0: tx = _x(value) - w - 10.0
				draw_string(font, Vector2(tx, size.y - 4.0), phase, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("a9becb"))
