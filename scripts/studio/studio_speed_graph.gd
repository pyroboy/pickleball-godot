extends Control
## Pose Studio easing curve (desktop: under the timeline scrubber, same time axis; phone: the
## Easing sheet). One curve for the whole motion, as in an animation graph editor:
##   across  time (the keys stay where they are in time: Wind-up, Contact and Finish never move)
##   up      how far along the motion the paddle is (by path distance: Ready at the bottom, then
##           Wind-up, Contact, Finish at the top), so steep = fast and flat = slow
## Handles
##   keys         Ready, Wind-up, Contact, Finish: fixed points of the curve
##   ease handles a short bar through each key: its right end is the ease OUT of that key (how
##                fast the paddle leaves it), its left end the ease IN (how fast it arrives).
##                Drag an end: level = soft (at rest at the key), raised (out) / lowered (in) =
##                snappy. The two are independent.
##   easing keys  press the curve to add a point it passes through (up to 4 per part): drag it
##                anywhere between its neighbours, for a hesitation or a burst. Right-click
##                (desktop) or Delete point removes it.
## Presets (apply_preset) shape the WHOLE motion, Ready to Finish, as one ease: Original, Linear,
## Ease in, Ease out, Ease in-out, Whip. Hollow handles = the original ease, untouched.
## The Strike follows the Gameplay edit lock (its ease handles at Wind-up and Contact too).
## Data: stroke_speed_ramp.gd (speed_<part>_start / _end = the slopes, speed_<part>_points with
## z = 1 = the easing keys). One undo step per drag.

const Ramp = preload("res://scripts/stroke_speed_ramp.gd")
const H := 150.0
const PAD := 8.0               # same horizontal inset as the scrub track
const TOP := 16.0
const BOTTOM := 8.0
const GRAB := 10.0
const SAMPLES := 28
const HANDLE := 30.0           # ease handle reach to the side (points)
const RISE := 1.1              # ... and how far up / down its end travels for the steepest ease, as a share of that
const NEAR_CURVE := 16.0       # a press this close to the curve adds an easing key (else it only selects the part)
const COLORS := [Color("9aa3b5"), Color("ffdc62"), Color("58dfdb")]                       # the three parts
const KEY_COLORS := [Color("c9d2e0"), Color("bd80ff"), Color("ffdc62"), Color("58dfdb")]   # Ready, W, C, F
const KEY_NAMES := ["Ready", "Wind-up", "Contact", "Finish"]
const TITLES := [["Ready → Wind-up", "Wind-up", "Prep"], ["Strike", "Hit"], ["Follow-through", "Finish", "End"]]
const SETTLE_FRAMES := 12      # idle frames after the last edit before the exact arc rebuild

signal locked_pressed          # a press on a locked handle: the phone shows a toast
signal selection_changed

var studio
var k := 1.0                   # size scale: 1 desktop, larger on the phone (finger-sized handles)
var lock_note := "locked · Gameplay edit"   # under the Strike title while it is locked
var selected := Vector2i(-1, -1)   # (part, key index) of the last pressed easing key
var sel_part := -1             # the part last touched (its column is tinted)
var write_usec := 0            # cost of the last edit applied to the pose (preview update included)
var write_count := 0

var _stale := false
var _spans: Array = []         # [[t0, t1] fractions of the sequence] per part
var _dur := 0.0
var _cum: Array = [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]   # height (0..1) of Ready, Wind-up, Contact, Finish
var _c: Array = [1.0, 1.0, 1.0]   # real speed (m/s) of slope 1, per part: path length / duration
var _real := false
## Dragged thing: (-2, -2) none; (-3, key * 2 + side) an ease handle (side 0 = in / left, 1 = out /
## right); (part, index) an easing key.
var _drag := Vector2i(-2, -2)
var _hover := Vector2i(-2, -2)
var _pending := Vector2.ZERO
var _has_pending := false
var _seen_rebuild := -1
var _seen_key := ""

func _init() -> void:
	custom_minimum_size = Vector2(160, H)
	set_process(true)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Easing curve of the whole motion: time across, how far along the swing up. Steep = fast, flat = slow. The keys stay put in time. Drag the end of a key's handle bar to ease out of / into that key; click the curve to add an easing key and drag it; right-click deletes one. Hollow = original ease. Strike: Gameplay edit."

## Phone: handles and text scale by `scale_k`; `height` (canvas units) when the sheet has less
## room than H * scale_k.
func set_scale_k(scale_k: float, height := 0.0) -> void:
	k = scale_k
	custom_minimum_size = Vector2(160, height if height > 0.0 else H * scale_k)
	queue_redraw()

func _def():
	if studio == null or not studio._ok() or studio.key == "" or studio.engine._base or studio.engine._serve or studio.engine.get("_action"): return null
	return studio.engine._current if studio.engine._has_motion() else null

## Part spans from the engine's sequence (prefix = Ready -> Wind-up) and the height of each key.
## The spans are owed: they are worked out when the graph is next drawn, pressed or asked for.
## Measuring the path solves about a hundred poses, so it is not done on every edit while the
## graph is hidden, and several edits in one frame cost one measurement.
func update_spans() -> void:
	_stale = true
	queue_redraw()

func _ensure_spans() -> void:
	if not _stale: return
	_stale = false
	_compute_spans()

func _compute_spans() -> void:
	_spans.clear(); _dur = 0.0
	if _def() == null or not studio.engine._timeline._configure(): queue_redraw(); return
	var s = studio.engine._timeline.sequence
	_dur = maxf(s.duration, 0.001)
	var w: float = s.prefix_seconds / _dur; var c: float = (s.prefix_seconds + s.release_seconds) / _dur
	var f: float = (s.prefix_seconds + s.stroke_seconds) / _dur
	_spans = [[0.0, w], [w, c], [c, f]]
	_real = false; _c = [1.0, 1.0, 1.0]; _cum = [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]
	var pl: Dictionary = studio.preview.part_lengths() if studio.preview else {}
	var ok := not pl.is_empty()
	if ok:
		for i in 3: if float(pl.seconds[i]) <= 0.0 or float(pl.lengths[i]) <= 0.0005: ok = false
	if ok:   # heights by path distance: the slope is then the real speed
		var total: float = float(pl.lengths[0]) + float(pl.lengths[1]) + float(pl.lengths[2])
		_cum = [0.0, float(pl.lengths[0]) / total, (float(pl.lengths[0]) + float(pl.lengths[1])) / total, 1.0]
		for i in 3: _c[i] = float(pl.lengths[i]) / float(pl.seconds[i])
		_real = true
	queue_redraw()

func _flush_drag() -> void:
	if _has_pending and _drag.x != -2: _drag_to(_pending)
	_has_pending = false

func _process(_d: float) -> void:
	if not is_visible_in_tree(): return
	_ensure_spans()
	_flush_drag()
	tick()

func tick() -> void:
	var pv = studio.preview if studio else null
	if pv and pv.momentum_retime_dirty and _drag.x == -2 and Engine.get_process_frames() - pv.momentum_retime_frame >= SETTLE_FRAMES:
		pv.settle_motion()
	var rc: int = pv.momentum_rebuild_count if pv else -1
	if rc != _seen_rebuild or studio.key != _seen_key:
		_seen_rebuild = rc; _seen_key = studio.key
		update_spans()

# ---------------------------------------------------------------- geometry

func _x(f: float) -> float: return PAD + (size.x - 2.0 * PAD) * clampf(f, 0.0, 1.0)
func _gy(g: float) -> float: return size.y - BOTTOM * k - (size.y - (TOP + BOTTOM) * k) * clampf(g, 0.0, 1.0)
## Screen point of progress n (0..1) of `part` at time fraction x of the part.
func _pt(part: int, x: float, n: float) -> Vector2:
	return Vector2(_x(lerpf(_spans[part][0], _spans[part][1], x)), _gy(lerpf(_cum[part], _cum[part + 1], n)))
func _key_pt(key: int) -> Vector2:
	return Vector2(_x(_spans[mini(key, 2)][0] if key < 3 else _spans[2][1]), _gy(_cum[key]))
## Pixels of a part: (width, height).
func _box(part: int) -> Vector2:
	return Vector2(maxf(_x(_spans[part][1]) - _x(_spans[part][0]), 1.0), maxf(_gy(_cum[part]) - _gy(_cum[part + 1]), 1.0))

func _part_locked(part: int) -> bool:
	return part == Ramp.STRIKE and studio.gameplay_locked("speed_strike_start")

## A part as it is edited: {e: Vector2 slopes (start, end), keys: [[x, progress]] inner keys, custom}.
## Older speed points become easing keys on the same curve the first time the part is edited.
func _part(part: int) -> Dictionary:
	var d = _def()
	var custom: bool = Ramp.custom(d, part)
	var e: Vector2 = Ramp.ends(d, part) if custom else Ramp.authored_ends(d, part)
	var keys: Array = []
	if Ramp.has_ease_keys(d, part):
		var kk: Array = Ramp.ease_keys(d, part)
		for i in range(1, kk.size() - 1): keys.append([kk[i][0], kk[i][1]])
	elif Ramp.has_points(d, part):
		var xs: Array = []
		for p in Ramp.points(d, part): xs.append(clampf(p.x, 0.03, 0.97))
		xs.sort()
		for x in xs: keys.append([x, Ramp.normalized(d, part, x)])
		e = Vector2(clampf(Ramp.speed(d, part, 0.0), 0.0, Ramp.MAX_SPEED), clampf(Ramp.speed(d, part, 1.0), 0.0, Ramp.MAX_SPEED))
	return {"e": e, "keys": keys, "custom": custom}

## The ease handle end of `key` on `side` (0 = in / left, 1 = out / right): its part, and where
## it is drawn. Empty when the key has no part on that side.
func _handle(key: int, side: int) -> Dictionary:
	var part: int = key - 1 if side == 0 else key
	if part < 0 or part > 2: return {}
	var w := _part(part)
	var slope: float = w.e.y if side == 0 else w.e.x
	var kp := _key_pt(key)
	# The same travel for every handle (level = soft, fully raised = as snappy as it goes): a
	# true-to-slope bar would hardly move on a long, low part.
	var reach := Vector2(HANDLE * k, -HANDLE * k * RISE * slope / Ramp.MAX_SPEED)
	return {"part": part, "slope": slope, "pt": kp + reach * (1.0 if side == 1 else -1.0), "key_pt": kp}

## Everything that can be pressed: [[id, point]].
func _targets() -> Array:
	_ensure_spans()
	var out: Array = []
	if _def() == null or _spans.size() < 3: return out
	for key in 4:
		for side in 2:
			var h := _handle(key, side)
			if not h.is_empty(): out.append([Vector2i(-3, key * 2 + side), h.pt])
	for part in 3:
		var w := _part(part)
		for i in w.keys.size(): out.append([Vector2i(part, i), _pt(part, w.keys[i][0], w.keys[i][1])])
	return out

func _pick(p: Vector2) -> Vector2i:
	var best := Vector2i(-2, -2); var bd := GRAB * k
	for t in _targets():
		var d: float = (t[1] as Vector2).distance_to(p)
		if d < bd: bd = d; best = t[0]
	return best

func _part_at(px: float) -> int:
	if _spans.size() < 3: return -1
	for part in 3:
		if px >= _x(_spans[part][0]) and px <= _x(_spans[part][1]): return part
	return -1

# ---------------------------------------------------------------- editing

func _apply(writes: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var parts: Array = writes.keys()
	for i in parts.size():
		var part: int = parts[i]
		var w: Dictionary = writes[part]
		var f: Array = Ramp.FIELDS[part]
		var pts: Array = []
		for q in w.keys: pts.append([snappedf(q[0], 0.002), snappedf(q[1], 0.002), 1.0])
		studio.set_field(f[0], null, snappedf(clampf(w.e.x, 0.0, Ramp.MAX_SPEED), 0.01), false, false)
		studio.set_field(f[1], null, snappedf(clampf(w.e.y, 0.0, Ramp.MAX_SPEED), 0.01), false, false)
		studio.set_speed_points(part, pts, i == parts.size() - 1)
	write_usec = Time.get_ticks_usec() - t0; write_count += 1
	queue_redraw()

## The ease handle of `key` on `side` to `slope` (progress per time: 0 = at rest there, 1 = the
## part's even speed, 3 = as snappy as it goes). Ease in and ease out of a key are independent.
func set_ease(key: int, side: int, slope: float) -> bool:
	_ensure_spans()
	var h := _handle(key, side)
	if h.is_empty() or _part_locked(h.part): return false
	var w := _part(h.part)
	var s: float = snappedf(clampf(slope, 0.0, Ramp.MAX_SPEED), 0.05)
	if side == 0: w.e.y = s
	else: w.e.x = s
	_apply({h.part: w})
	return true

## Easing key `idx` of `part` to time fraction x and progress n, kept between its neighbours.
## Returns false when the part is locked.
func set_key(part: int, idx: int, x: float, n: float) -> bool:
	_ensure_spans()
	if _part_locked(part): return false
	var w := _part(part)
	if idx < 0 or idx >= w.keys.size(): return false
	var x0: float = w.keys[idx - 1][0] if idx > 0 else 0.0
	var x1: float = w.keys[idx + 1][0] if idx < w.keys.size() - 1 else 1.0
	var n0: float = w.keys[idx - 1][1] if idx > 0 else 0.0
	var n1: float = w.keys[idx + 1][1] if idx < w.keys.size() - 1 else 1.0
	w.keys[idx] = [clampf(x, x0 + 0.03, x1 - 0.03), clampf(n, n0 + 0.01, n1 - 0.01)]
	_apply({part: w})
	return true

## A new easing key on the curve at time fraction x. Its index, -1 when full / locked / no room.
func add_key(part: int, x: float) -> int:
	_ensure_spans()
	if _part_locked(part): return -1
	var d = _def()
	var w := _part(part)
	if w.keys.size() >= Ramp.MAX_POINTS:
		studio._set_status("A part holds at most %d easing keys" % Ramp.MAX_POINTS); return -1
	var xx: float = clampf(x, 0.04, 0.96)
	for q in w.keys: if absf(q[0] - xx) < 0.04: return -1
	var added: Array = [xx, clampf(Ramp.normalized(d, part, xx), 0.01, 0.99)]
	w.keys.append(added)
	w.keys.sort_custom(func(a, b): return a[0] < b[0])
	_apply({part: w})
	return w.keys.find(added)

func delete_key(part: int, idx: int) -> bool:
	_ensure_spans()
	if _part_locked(part): return false
	var w := _part(part)
	if idx < 0 or idx >= w.keys.size(): return false
	w.keys.remove_at(idx)
	studio.begin_edit("easing key delete"); _apply({part: w}); studio.end_edit()
	_select(Vector2i(-1, -1))
	return true

## Delete the selected easing key (phone button).
func delete_selected() -> bool:
	return selected.x >= 0 and delete_key(selected.x, selected.y)

func reset_part(part: int) -> void:
	_ensure_spans()
	if _part_locked(part): return
	var f: Array = Ramp.FIELDS[part]
	studio.set_speed_points(part, [], false)
	studio.set_field(f[0], null, -1.0, false, false)
	studio.set_field(f[1], null, -1.0)

## Every free part back to the original ease (one undo step).
func reset_all() -> void:
	_ensure_spans()
	studio.begin_edit("easing reset")
	for part in 3: reset_part(part)
	studio.end_edit()
	_select(Vector2i(-1, -1))
	queue_redraw()

## A named ease over the WHOLE motion, Ready to Finish, as one curve: "original" (every part back
## to its own ease), "linear", "in" (slow start, building to the end), "out" (fast start, settling),
## "inout" (slow, fast through the middle, slow), "whip" (slow for long, then a burst to the end).
## The keys stay where they are in time, so the preset gives each key the slope its whole-motion
## curve has at that key's moment; the parts' easing keys are cleared. Locked parts are skipped:
## returns how many were (0 = the whole curve took it), -1 for an unknown name.
func apply_preset(name: String) -> int:
	_ensure_spans()
	if name != "original" and not WHOLE.has(name): return -1
	if _spans.size() < 3: return -1
	var skipped := 0
	var total: float = maxf(_spans[2][1], 0.001)
	studio.begin_edit("easing preset")
	for part in 3:
		if _part_locked(part): skipped += 1; continue
		if name == "original": reset_part(part); continue
		var t0: float = _spans[part][0] / total; var t1: float = _spans[part][1] / total
		# whole-motion slope (level per time) -> this part's own slope (its progress per its time)
		var scale: float = (t1 - t0) / maxf(_cum[part + 1] - _cum[part], 0.001)
		_apply({part: {"e": Vector2(clampf(_whole_slope(name, t0) * scale, 0.0, Ramp.MAX_SPEED), clampf(_whole_slope(name, t1) * scale, 0.0, Ramp.MAX_SPEED)), "keys": []}})
	studio.end_edit()
	_select(Vector2i(-1, -1))
	queue_redraw()
	return skipped

## Slope at time t (0..1 of the whole motion) of the named whole-motion ease.
const WHOLE := ["linear", "in", "out", "inout", "whip"]
static func _whole_slope(name: String, t: float) -> float:
	match name:
		"in": return 2.0 * t                      # t^2
		"out": return 2.0 * (1.0 - t)             # 1 - (1 - t)^2
		"inout": return 6.0 * t * (1.0 - t)       # smoothstep
		"whip": return 3.0 * t * t                # t^3
	return 1.0                                    # linear

func _select(v: Vector2i) -> void:
	if v == selected: return
	selected = v; selection_changed.emit(); queue_redraw()

func _set_part(part: int) -> void:
	if part == sel_part: return
	sel_part = part; selection_changed.emit(); queue_redraw()

func _target_part(id: Vector2i) -> int:
	if id.x >= 0: return id.x
	if id.x == -3: return (id.y / 2) - 1 if id.y % 2 == 0 else id.y / 2
	return -1

func _gui_input(ev: InputEvent) -> void:
	_ensure_spans()
	if _def() == null or _spans.size() < 3: return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		var h := _pick(ev.position)
		if h.x >= 0:
			accept_event()
			if not delete_key(h.x, h.y): _refuse()
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			var h := _pick(ev.position)
			var part: int = _target_part(h) if h.x != -2 else _part_at(ev.position.x)
			if part < 0: return
			accept_event()
			_set_part(part)
			if _part_locked(part): _refuse(); return
			studio.begin_edit("easing")
			if h.x == -2:   # on the curve: a new easing key there; elsewhere in the part: only select it
				var x0 := _x(_spans[part][0]); var x1 := _x(_spans[part][1])
				var fx: float = clampf((ev.position.x - x0) / maxf(x1 - x0, 1.0), 0.0, 1.0)
				if absf(_pt(part, fx, Ramp.normalized(_def(), part, fx)).y - ev.position.y) > NEAR_CURVE * k: studio.end_edit(); return
				var idx := add_key(part, fx)
				if idx < 0: studio.end_edit(); return
				h = Vector2i(part, idx)
			_drag = h
			_select(h if h.x >= 0 else Vector2i(-1, -1))
		elif _drag.x != -2:
			_flush_drag()
			_drag = Vector2i(-2, -2)
			if k > 1.5: _hover = Vector2i(-2, -2)   # touch has no hover: no label left behind
			studio.end_edit(); accept_event(); queue_redraw()
	elif ev is InputEventMouseMotion:
		if _drag.x != -2:   # applied once per frame (_process): several moves can arrive in one
			_pending = ev.position; _has_pending = true; accept_event()
		elif k <= 1.5:   # hover labels are for a mouse; a finger only has presses and drags
			var h := _pick(ev.position)
			if h != _hover: _hover = h; queue_redraw()
			mouse_default_cursor_shape = Control.CURSOR_MOVE if h.x >= 0 else Control.CURSOR_POINTING_HAND if h.x == -3 else Control.CURSOR_CROSS if _part_at(ev.position.x) >= 0 else Control.CURSOR_ARROW

func _refuse() -> void:
	locked_pressed.emit()
	studio._set_status("Locked: the strike's easing is gameplay timing. Turn on Gameplay edit (top bar) to change it.")

func _drag_to(p: Vector2) -> void:
	if _drag.x == -3:
		var key: int = _drag.y / 2; var side: int = _drag.y % 2
		var h := _handle(key, side)
		if h.is_empty(): return
		var rise: float = (h.key_pt.y - p.y) if side == 1 else (p.y - h.key_pt.y)   # out: end up; in: end down
		set_ease(key, side, clampf(rise / (HANDLE * k * RISE), 0.0, 1.0) * Ramp.MAX_SPEED)
	else:
		var part := _drag.x
		var x0 := _x(_spans[part][0]); var x1 := _x(_spans[part][1])
		var y0 := _gy(_cum[part]); var y1 := _gy(_cum[part + 1])
		set_key(part, _drag.y, (p.x - x0) / maxf(x1 - x0, 1.0), (p.y - y0) / minf(y1 - y0, -1.0))

# ---------------------------------------------------------------- drawing

func _speed_text(part: int, slope: float) -> String:
	return ("%.1f m/s" % (slope * _c[part])) if _real else ("×%.2f" % slope)

func _tag(font: Font, fs: int, at_pt: Vector2, txt: String) -> void:
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := Vector2(clampf(at_pt.x + 10.0 * k, PAD, size.x - PAD - tw), clampf(at_pt.y - 9.0 * k, TOP * k + fs, size.y - 4.0 * k))
	draw_rect(Rect2(at + Vector2(-3.0 * k, -fs), Vector2(tw + 6.0 * k, fs + 4.0 * k)), Color(0.05, 0.12, 0.17, 0.92))
	draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("eef5fa"))

func _draw() -> void:
	_ensure_spans()
	draw_rect(Rect2(Vector2.ZERO, size), Color("0d1f2b"))
	var font := get_theme_font("font"); var fs := int(round(11 * k))
	var d = _def()
	if d == null or _spans.size() < 3:
		draw_string(font, Vector2(PAD, size.y * 0.5 + 4.0), "Easing: pick a stroke (stances and serves have no easing curve)", HORIZONTAL_ALIGNMENT_LEFT, size.x - 2.0 * PAD, fs, Color("6f8796"))
		return
	var top := TOP * k; var bottom := size.y - BOTTOM * k
	# Part columns: tint (brighter when it is the part presets apply to), title, hatching when locked.
	for part in 3:
		var x0 := _x(_spans[part][0]); var x1 := _x(_spans[part][1])
		var locked := _part_locked(part)
		draw_rect(Rect2(x0, top, x1 - x0, bottom - top), Color(COLORS[part], 0.03 if locked else 0.13 if part == sel_part else 0.06))
		for name in TITLES[part]:
			var label: String = name
			if font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= x1 - x0 - 8.0 * k:
				draw_string(font, Vector2(x0 + 4.0 * k, 11.0 * k), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(COLORS[part], 0.5 if locked else 0.95))
				break
		if locked:
			for n in int((x1 - x0) / (9.0 * k)) + 1:
				var hx := x0 + n * 9.0 * k
				draw_line(Vector2(hx, bottom), Vector2(minf(hx + (bottom - top) * 0.5, x1), bottom - minf((bottom - top), (x1 - hx) * 2.0)), Color(1, 1, 1, 0.045), k)
	# The keys' levels (how far along the swing) and their times.
	for key in 4:
		var kp := _key_pt(key)
		for i in int((size.x - 2.0 * PAD) / (8.0 * k)):
			draw_line(Vector2(PAD + i * 8.0 * k, kp.y), Vector2(PAD + i * 8.0 * k + 3.0 * k, kp.y), Color(KEY_COLORS[key], 0.14), k)
		if key == 1 or key == 2: draw_line(Vector2(kp.x, 2.0 * k), Vector2(kp.x, bottom), Color(KEY_COLORS[key], 0.3), k)
	# Key names beside their levels, where the curve is not (left of Contact / Finish, right of Ready / Wind-up).
	for key in 4:
		var kp := _key_pt(key)
		var name: String = KEY_NAMES[key]
		var tw := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := Vector2(size.x - PAD - tw, kp.y - 3.0 * k) if key < 2 else Vector2(PAD + 2.0 * k, kp.y + fs)
		draw_string(font, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(KEY_COLORS[key], 0.5))
	# The curve: one line through the keys, coloured by part.
	for part in 3:
		var pts := PackedVector2Array()
		for i in SAMPLES + 1:
			var u := float(i) / SAMPLES
			pts.append(_pt(part, u, Ramp.normalized(d, part, u)))
		var col: Color = COLORS[part]; col.a = 0.45 if _part_locked(part) else 1.0 if Ramp.custom(d, part) else 0.75
		draw_polyline(pts, col, 2.5 * k, true)
	# Ease handles: a bar through each key, a dot at each end.
	for key in 4:
		for side in 2:
			var h := _handle(key, side)
			if h.is_empty(): continue
			var id := Vector2i(-3, key * 2 + side)
			var hot: bool = _drag == id or _hover == id
			var locked := _part_locked(h.part)
			var custom: bool = Ramp.custom(d, h.part)
			var c: Color = Color("eef5fa") if hot else Color(KEY_COLORS[key], 0.35 if locked else 0.95)
			draw_line(h.key_pt, h.pt, Color(c, 0.3 if locked else 0.7), 1.5 * k, true)
			var r := (4.5 + (1.5 if hot else 0.0)) * k
			draw_circle(h.pt, r + 1.5 * k, Color("0d1f2b"), true, -1.0, true)
			if custom: draw_circle(h.pt, r, c, true, -1.0, true)
			else: draw_circle(h.pt, r, c, false, 1.5 * k, true)   # hollow: the original ease
			if hot: _tag(font, fs, h.pt, "%s %s  %s" % [KEY_NAMES[key], "ease in" if side == 0 else "ease out", _speed_text(h.part, h.slope)])
	# Keys: fixed diamonds.
	for key in 4:
		var kp := _key_pt(key)
		var r := 6.0 * k
		draw_colored_polygon(PackedVector2Array([kp + Vector2(0, -r - 2.0), kp + Vector2(r + 2.0, 0), kp + Vector2(0, r + 2.0), kp + Vector2(-r - 2.0, 0)]), Color("0d1f2b"))
		draw_colored_polygon(PackedVector2Array([kp + Vector2(0, -r), kp + Vector2(r, 0), kp + Vector2(0, r), kp + Vector2(-r, 0)]), KEY_COLORS[key])
	# Easing keys.
	for part in 3:
		var w := _part(part)
		for i in w.keys.size():
			var id := Vector2i(part, i)
			var p := _pt(part, w.keys[i][0], w.keys[i][1])
			var hot: bool = _drag == id or _hover == id
			var r := (5.0 + (1.5 if hot else 0.0)) * k
			draw_circle(p, r + 1.5 * k, Color("0d1f2b"), true, -1.0, true)
			draw_circle(p, r, Color("eef5fa") if hot else Color(COLORS[part], 0.4 if _part_locked(part) else 1.0), true, -1.0, true)
			if selected == id: draw_circle(p, r + 3.5 * k, Color("eef5fa"), false, 1.5 * k, true)
			if hot or selected == id:
				var t: float = (lerpf(_spans[part][0], _spans[part][1], w.keys[i][0]) - _spans[part][0]) * _dur
				_tag(font, fs, p, "%d%% of the way at %.2f s" % [roundi(w.keys[i][1] * 100.0), t])

## For the link / tests: the curve as data.
func state() -> Dictionary:
	_ensure_spans()
	var d = _def()
	var parts: Array = []; var keys: Array = []; var handles: Array = []
	if d != null and _spans.size() == 3:
		for key in 4:
			var kp := _key_pt(key)
			keys.append({"name": KEY_NAMES[key], "x": kp.x, "y": kp.y, "level": _cum[key]})
			for side in 2:
				var h := _handle(key, side)
				if not h.is_empty(): handles.append({"key": key, "side": side, "part": h.part, "slope": h.slope, "speed": h.slope * _c[h.part], "x": h.pt.x, "y": h.pt.y, "locked": _part_locked(h.part)})
		for part in 3:
			var w := _part(part)
			var ks: Array = []
			for q in w.keys:
				var p := _pt(part, q[0], q[1])
				ks.append({"t": q[0], "n": q[1], "x": p.x, "y": p.y})
			var curve: Array = []
			for i in 11: curve.append(snappedf(Ramp.normalized(d, part, i / 10.0), 0.001))
			parts.append({"name": Ramp.NAMES[part], "span": _spans[part], "custom": w.custom, "ends": [w.e.x, w.e.y], "keys": ks, "curve": curve, "locked": _part_locked(part)})
	var pv = studio.preview if studio else null
	return {"shown": d != null, "size": [size.x, size.y], "real": _real, "keys": keys, "handles": handles, "parts": parts,
		"selected": [selected.x, selected.y], "sel_part": sel_part, "write_usec": write_usec, "write_count": write_count,
		"retimes": pv.momentum_retime_count if pv else 0, "retime_usec": pv.momentum_retime_usec if pv else 0, "rebuilds": pv.motion_rebuild_count if pv else 0}
