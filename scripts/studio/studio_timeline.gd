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
const BallActions = preload("res://scripts/ball_actions.gd")
const SpeedGraph = preload("res://scripts/studio/studio_speed_graph.gd")
var speed_graph
var keys_toggle: Button
var ease_preset: OptionButton
var keys_bake: Button
var _speed_spacer: Control

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
var _names: Array = STAGE_NAMES
var _mark_txn := false
var _mark_duration := 0.0   # sequence length when a key-time drag began (keeps the drag mapping still)
var _mark_prefix := 0.0     # stroke wind-up hold (seconds before the strike) when a drag began

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
	var ks := Theme_.segment(row, "KeysSeg")
	keys_toggle = Theme_.tool_button("KeysPlayToggle", "My keys play", "", "On: the game and this timeline play the whole Wind-up and Finish pose you author. Off: the game builds those bodies and takes only the paddle position from your keys (posing joints there does not show in play).", true)
	keys_toggle.pressed.connect(func(): studio.set_keys_play("on" if keys_toggle.button_pressed else "off"))
	ks.add_child(keys_toggle)
	keys_bake = Theme_.tool_button("KeysBake", "Game pose → keys", "", "Copy the Wind-up and Finish the game builds now into this stroke's keys and switch My keys play on: play looks the same, and from then on your keys are what plays.")
	keys_bake.pressed.connect(func(): studio.set_keys_play("bake"))
	ks.add_child(keys_bake)
	var es := Theme_.segment(row, "EaseSeg")
	ease_preset = OptionButton.new(); ease_preset.name = "EasePreset"; ease_preset.focus_mode = Control.FOCUS_NONE
	ease_preset.tooltip_text = "Easing preset for the whole swing, Ready to Finish, as one curve (the keys stay put in time). The Strike is skipped unless Gameplay edit is on."
	for p in ["Ease preset…", "Original", "Linear", "Ease in", "Ease out", "Ease in-out", "Whip"]: ease_preset.add_item(p)
	ease_preset.item_selected.connect(func(i):
		if i > 0 and speed_graph: speed_graph.apply_preset(["original", "linear", "in", "out", "inout", "whip"][i - 1])
		ease_preset.select(0))
	es.add_child(ease_preset)
	_transport = [play_button, step_back, step_fwd, loop_toggle, strong_button, weak_button]
	var srow := HBoxContainer.new(); srow.name = "ScrubRow"; srow.add_theme_constant_override("separation", Theme_.SP2)
	add_child(srow)
	scrubber = ScrubTrack.new(); scrubber.name = "Scrubber"
	scrubber.tooltip_text = "Real-time sequence (charge -> release), drag to scrub. Marks: purple wind-up, gold contact, cyan finish. Scrubbing previews only. Drag a mark to change that key's time (strokes: contact and finish; needs Gameplay edit)."
	scrubber.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrubber.value_changed.connect(seek_from.bind(scrubber))
	scrubber.mark_moved.connect(_on_mark_moved)
	scrubber.key_mover = move_key
	scrubber.key_tapped.connect(go_to_key)
	srow.add_child(scrubber)
	time_label = Theme_.small_label("TimeLabel", "")
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	srow.add_child(time_label)
	_size_time_label.call_deferred()
	# Speed ramp graph: same time axis as the scrubber (a spacer matches the time label).
	var grow := HBoxContainer.new(); grow.name = "SpeedRow"; grow.add_theme_constant_override("separation", Theme_.SP2)
	add_child(grow)
	speed_graph = SpeedGraph.new(); speed_graph.name = "SpeedGraph"; speed_graph.studio = studio
	speed_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grow.add_child(speed_graph)
	_speed_spacer = Control.new(); _speed_spacer.name = "SpeedSpacer"; _speed_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grow.add_child(_speed_spacer)
	for sg in ["pose_selected", "stage_changed", "pose_edited", "pose_reloaded"]:
		studio.connect(sg, update_marks.unbind(1))

func _is_action() -> bool:
	var ed = _ed()
	return ed != null and bool(ed.get("_action"))

## Stage buttons and the key label follow the pose type (ball actions have their own keys).
func _relabel() -> void:
	var names: Array = studio.stage_names()
	if names == _names: return
	_names = names
	for i in 3:
		stage_buttons[i].text = names[i]
		stage_buttons[i].tooltip_text = "Edit the %s key (Alt+%d · Tab / Shift+Tab cycles)" % [String(names[i]).to_lower(), i + 1]
	_last_code = -2

## Strokes (not serves): contact and finish marks move; wind-up is the game's fixed hold.
func _stroke_marks_draggable() -> bool:
	var ed = _ed()
	if ed == null or _is_action() or not motion() or not ed._timeline._configure(): return false
	return int(ed._timeline.sequence.get("style")) < 0

## Dragging a key mark on the track changes that key's time (one undo step).
## Ball actions: their key-time fields. Strokes: contact = Strike time, finish = Sweep time
## (gameplay fields: locked unless Gameplay edit is on).
func _on_mark_moved(i: int, frac: float, done: bool) -> void:
	var ed = _ed()
	if ed == null: return
	var act := _is_action()
	if not act and (i == 0 or not _stroke_marks_draggable()): return
	if not _mark_txn:
		studio.stop_drag()
		_mark_txn = true
		var ok: bool = ed._timeline._configure()
		_mark_duration = ed._timeline.sequence.duration if ok else 1.0
		_mark_prefix = float(ed._timeline.sequence.prefix_seconds) if ok and not act else 0.0
		studio.begin_edit("key time")
	var t := frac * _mark_duration
	if act:
		var e: Array = BallActions.time_edit(ed._current, i, t)
		studio.set_field(e[0], null, snappedf(e[1], 0.01))
	elif i == 1:
		studio.set_field("ft_duration_strike", null, snappedf(clampf(t - _mark_prefix, 0.01, 0.5), 0.01))
	else:
		var strike := maxf(0.01, float(ed._current.ft_duration_strike))
		studio.set_field("ft_duration_sweep", null, snappedf(clampf(t - _mark_prefix - strike, 0.01, 0.5), 0.01))
	if done:
		_mark_txn = false
		studio.end_edit()
	update_marks()
	refresh()

## Fixed width: the longest text it shows, so the track does not jump while playing.
func _size_time_label() -> void:
	var font := time_label.get_theme_font("font")
	var fs := time_label.get_theme_font_size("font_size")
	var w := 0.0
	for t in ["00.000 / 00.000 s · tick 000", "Body stance (one key)", "Key: Wind-up", "Static pose"]:
		w = maxf(w, font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	time_label.custom_minimum_size.x = ceilf(w) + 2
	if _speed_spacer: _speed_spacer.custom_minimum_size.x = time_label.custom_minimum_size.x

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
	if not motion() or _is_action(): refresh(); return
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

## A scrub from a track (desktop scrubber or the phone's): a scrub that landed on Wind-up /
## Contact / Finish selects that key (posing edits it: what you see there is what you edit);
## on a path key it selects the key; anywhere else it previews that moment.
func seek_from(t: float, track) -> void:
	if _sync: return
	var hit: Array = track.snap_hit
	if hit.size() == 2 and String(hit[0]) == "stage":
		select_path_key(-1.0)
		if studio.stage != int(hit[1]) or not studio.at_key(): studio.set_stage(int(hit[1]))
		return
	seek(t)
	select_path_key(float(hit[1]) if hit.size() == 2 else -1.0)

## The selected path key (viewport tangent handles, the brighter timeline mark); -1 = none.
func select_path_key(id: float) -> void:
	var vi = studio.get("_view_input")
	if vi != null and not is_equal_approx(vi.sel_key_t, id):
		vi.sel_key_t = id; vi.queue_redraw()

func selected_path_key() -> float:
	var vi = studio.get("_view_input")
	return float(vi.sel_key_t) if vi != null else -1.0

## Fraction of the sequence at which path key `id` plays (through the speed ramp); -1 = unknown.
func key_frac(id: float) -> float:
	var ed = _ed()
	if not motion() or not ed._timeline._configure(): return -1.0
	var s = ed._timeline.sequence
	if s.style >= 0: return -1.0
	var dur: float = maxf(s.duration, 0.001)
	if studio.is_lead_in(id): return s.time_of_lead(id - studio.LEAD_IN) / dur
	return (s.prefix_seconds + s.time_of_progress(id)) / dur

## Preview the moment a path key plays, and select it.
func go_to_key(id: float) -> void:
	var f := key_frac(id)
	if f < 0.0: return
	seek(f)
	select_path_key(id)

## Move path key `id` to fraction `frac` of the sequence (its time, through the speed ramp). A
## lead-in key stays on the lead-in, a swing key on its side of Contact. One undo step per drag
## (`done` ends it). Returns the key's new id.
var _key_txn := false
func move_key(id: float, frac: float, done: bool) -> float:
	var ed = _ed()
	if not motion() or not ed._timeline._configure() or not studio.path_keys_supported(): return id
	var s = ed._timeline.sequence
	var t: float = clampf(frac, 0.0, 1.0) * maxf(s.duration, 0.001)
	var nid: float
	if studio.is_lead_in(id):
		nid = studio.LEAD_IN + clampf(s.lead_progress(clampf(t, 0.0, s.prefix_seconds)), 0.03, 0.97)
	else:
		var p: float = s.progress_at(t - s.prefix_seconds)
		nid = clampf(p, 0.02, 0.48) if id < 0.5 else clampf(p, 0.52, 0.98)
	if not _key_txn:
		studio.stop_drag()
		studio.begin_edit("key time"); _key_txn = true
	if absf(nid - id) > 0.0005:
		var keys: Array = studio.path_keys()
		for k in keys: if absf(float(k[0]) - id) < 0.001: k[0] = nid
		studio.set_path_keys(keys)
	else: nid = id
	if done:
		_key_txn = false
		studio.end_edit()
	select_path_key(nid)
	update_marks()
	return nid

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
	if studio: _relabel()
	var act := _is_action()
	scrubber.marks_draggable = act or _stroke_marks_draggable()
	scrubber.fixed_marks = _fixed_marks()
	if speed_graph: speed_graph.update_spans()
	if not motion() or not ed._timeline._configure():
		scrubber.key_marks = []
		scrubber.set_marks([], 0.0); return
	var s = ed._timeline.sequence
	var dur: float = maxf(s.duration, 0.001)
	var km: Array = []
	if studio.path_keys_supported() and s.style < 0:
		for k in studio.path_keys():
			var id := float(k[0])
			km.append([(s.time_of_lead(id - studio.LEAD_IN) if studio.is_lead_in(id) else s.prefix_seconds + s.time_of_progress(id)) / dur, id])
	scrubber.key_marks = km
	scrubber.set_marks([s.prefix_seconds / dur, (s.prefix_seconds + s.release_seconds) / dur,
		(s.prefix_seconds + s.stroke_seconds) / dur], s.duration)

## Marks a press cannot drag (it scrubs / snaps there instead): the stroke Wind-up always, and
## Contact / Finish while their times are locked (gameplay timing: Gameplay edit off, the phone).
func _fixed_marks() -> Array:
	if _is_action(): return []
	return [0, 1, 2] if studio.gameplay_locked("ft_duration_strike") else [0]

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
	var act := _is_action()
	for b in _transport:
		var dis: bool = not has or (act and (b == strong_button or b == weak_button))
		if b.disabled != dis: b.disabled = dis
	for b in speed_buttons:
		if b.disabled == has: b.disabled = not has
	if scrubber.editable != has: scrubber.editable = has
	if keys_toggle:
		var ks: String = studio.keys_play_state() if ed != null else ""
		var on: bool = ks == "on" or ks == "always"
		if keys_toggle.button_pressed != on: keys_toggle.set_pressed_no_signal(on)
		var dis: bool = ks == "" or ks == "always"
		if keys_toggle.disabled != dis: keys_toggle.disabled = dis; keys_bake.disabled = dis
	if ed == null: return
	var fm := _fixed_marks()
	if scrubber.fixed_marks != fm: scrubber.fixed_marks = fm
	var at: int = int(ed._stage) if has and studio.at_key() else -1
	var sk := selected_path_key()
	if scrubber.at_stage != at or not is_equal_approx(scrubber.sel_key, sk):
		scrubber.at_stage = at; scrubber.sel_key = sk; scrubber.queue_redraw()
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
			scrubber.set_value_no_signal(float(scrubber.marks[ed._stage]) if has and int(ed._stage) < scrubber.marks.size() else 0.0)
			scrubber.phase = ""; scrubber.queue_redraw()
			_sync = false
			time_label.text = ("Key: " + String(_names[ed._stage])) if has else ("Body stance (one key)" if ed._base else "Static pose")

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
		"seconds": tl.elapsed if tl and tl.active else 0.0, "marks": scrubber.marks, "key_marks": scrubber.key_marks, "at_stage": scrubber.at_stage, "sel_key": scrubber.sel_key, "scrub_size": [scrubber.size.x, scrubber.size.y], "keys_play": studio.keys_play_state() if studio else "",
		"speed_graph": speed_graph.state() if speed_graph else {}}

## Scrub track: a Range (0..1) drawn as a rail with stage markers, progress and a playhead.
## Click or drag anywhere on it to scrub. 28 pt tall.
class ScrubTrack extends Range:
	signal mark_moved(index: int, frac: float, done: bool)
	signal key_tapped(id: float)
	const H := 28.0
	const MARK_GRAB := 7.0        # points: a press this close to a mark drags the mark (ball actions)
	const SNAP := 9.0             # points: a scrub this close to a key lands on it (and selects it)
	const KEY_COLOR := Color("ff8fb1")
	var editable := true
	var marks_draggable := false
	var _mark := -1
	var fixed_marks: Array = []   # mark indices that never drag (stroke wind-up)
	var marks: Array = []          # [windup, contact, finish] fractions
	var duration := 0.0
	var phase := ""
	var _drag := false
	## Path keys (pink): [[fraction of the sequence, key id]] (id = the studio's key progress,
	## LEAD_IN + v on the Ready -> Wind-up lead-in). Drag one to move its key in time.
	var key_marks: Array = []
	var sel_key := -1.0           # the selected path key (drawn brighter)
	var at_stage := -1            # the key being edited (the playhead parks on its mark); -1 = scrubbing
	var touch_k := 1.0            # grab / snap distances scale (phone)
	var snap_hit: Array = []      # after a scrub: ["stage", i] / ["key", id] when it landed on a key, else []
	var key_mover: Callable       # (id, frac, done) -> new id: moves a path key in time
	var _kmark := -1.0
	var _kmoved := false

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
			if e.pressed and marks_draggable:
				_mark = _mark_at(e.position.x)
			if _mark >= 0:
				mark_moved.emit(_mark, _frac(e.position.x), not e.pressed)
				if not e.pressed: _mark = -1
				accept_event(); return
			if e.pressed:
				_kmark = _key_at(e.position.x); _kmoved = false
			if _kmark >= 0.0:   # a path key's mark: drag = move the key in time, tap = go to it
				if not e.pressed:
					if _kmoved and key_mover.is_valid(): key_mover.call(_kmark, _frac(e.position.x), true)
					else: key_tapped.emit(_kmark)
					_kmark = -1.0
				accept_event(); return
			_drag = e.pressed
			if e.pressed: _set_from(e.position.x)
			accept_event()
		elif e is InputEventMouseMotion and _mark >= 0:
			mark_moved.emit(_mark, _frac(e.position.x), false)
			accept_event()
		elif e is InputEventMouseMotion and _kmark >= 0.0:
			_kmoved = true
			if key_mover.is_valid(): _kmark = float(key_mover.call(_kmark, _frac(e.position.x), false))
			accept_event()
		elif e is InputEventMouseMotion and _drag:
			_set_from(e.position.x)
			accept_event()
		elif e is InputEventMouseMotion:
			mouse_default_cursor_shape = Control.CURSOR_HSIZE if (marks_draggable and _mark_at(e.position.x) >= 0) or _key_at(e.position.x) >= 0.0 else Control.CURSOR_POINTING_HAND

	func _frac(px: float) -> float:
		return clampf((px - 8.0) / maxf(size.x - 16.0, 1.0), 0.0, 1.0)

	func _mark_at(px: float) -> int:
		var best := -1
		var bd := MARK_GRAB * touch_k
		for i in mini(3, marks.size()):
			if i in fixed_marks: continue
			var d := absf(_x(float(marks[i])) - px)
			if d <= bd: bd = d; best = i
		return best

	## Path key mark under px: its id, -1 = none.
	func _key_at(px: float) -> float:
		var best := -1.0
		var bd := MARK_GRAB * touch_k
		for k in key_marks:
			var d := absf(_x(float(k[0])) - px)
			if d <= bd: bd = d; best = float(k[1])
		return best

	## Scrub to px, landing on a key when close (W / C / F first, then path keys).
	func _set_from(px: float) -> void:
		var v := clampf((px - 8.0) / maxf(size.x - 16.0, 1.0), 0.0, 1.0)
		snap_hit = []
		var bd := SNAP * touch_k
		for i in mini(3, marks.size()):
			var d := absf(_x(float(marks[i])) - px)
			if d <= bd: bd = d; v = float(marks[i]); snap_hit = ["stage", i]
		if snap_hit.is_empty():
			for k in key_marks:
				var d := absf(_x(float(k[0])) - px)
				if d <= bd: bd = d; v = float(k[0]); snap_hit = ["key", float(k[1])]
		if is_equal_approx(value, v): value_changed.emit(v)   # the same spot can still change what is selected
		else: value = v
		queue_redraw()

	func _draw() -> void:
		var y := size.y * 0.5
		var rail := Rect2(8.0, y - 3.0, size.x - 16.0, 6.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color("0d1f2b"))
		draw_rect(rail, Color("23404f"))
		var dim := 1.0 if editable else 0.35
		var head: float = float(marks[at_stage]) if at_stage >= 0 and at_stage < marks.size() else value
		if editable and head > 0.0:
			draw_rect(Rect2(rail.position, Vector2(_x(head) - 8.0, rail.size.y)), Color(0.52, 0.81, 1.0, 0.45))
		var cols := [Color("bd80ff"), Color("ffdc62"), Color("58dfdb")]
		for i in mini(3, marks.size()):
			var x := _x(float(marks[i]))
			var c: Color = cols[i]; c.a = dim
			draw_line(Vector2(x, 4.0), Vector2(x, size.y - 4.0), c, 4.0 if i == at_stage else 2.0)
			draw_colored_polygon(PackedVector2Array([Vector2(x - 4.0, 2.0), Vector2(x + 4.0, 2.0), Vector2(x, 7.0)]), c)
		for k in key_marks:   # path keys: small pink squares on the rail
			var x := _x(float(k[0]))
			var on: bool = absf(float(k[1]) - sel_key) < 0.001 or absf(float(k[1]) - _kmark) < 0.001
			var r := (5.0 if on else 3.5) * maxf(1.0, touch_k * 0.7)
			draw_rect(Rect2(x - r - 1.5, y - r - 1.5, (r + 1.5) * 2.0, (r + 1.5) * 2.0), Color("0d1f2b"))
			draw_rect(Rect2(x - r, y - r, r * 2.0, r * 2.0), Color("eef5fa") if on else Color(KEY_COLOR, dim))
		if editable and (at_stage >= 0 or value > 0.0 or not phase.is_empty()):
			var px := _x(head)
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
