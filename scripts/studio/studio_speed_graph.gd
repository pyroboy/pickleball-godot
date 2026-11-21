extends Control
## Desktop Pose Studio: speed ramp graph under the timeline scrubber (same time axis).
## Three parts, Ready -> Wind-up, Strike, Follow-through (stroke_speed_ramp.gd). Each part shows
## its relative speed (1 = the part's average speed, dashed line) as a coloured curve, with the
## real solved paddle-head speed (m/s, from the trajectory arc) faint behind it.
## Drag a part's start / end handle up or down to set the speed there. A hollow handle = the
## authored ease (untouched); the first drag switches the part to its own ramp. Double-click a
## handle: back to the authored ease. Press empty graph inside a part: a speed point there (up
## to 4 per part, round handles: drag up / down and sideways in time; right-click or the phone's
## Delete point removes it). Durations and keys never move. One undo step per drag.
## Strike handles follow the Gameplay edit lock (the strike is gameplay timing).

const Ramp = preload("res://scripts/stroke_speed_ramp.gd")
const H := 92.0
const PAD := 8.0               # same horizontal inset as the scrub track
const TOP := 14.0
const BOTTOM := 6.0
const GRAB := 9.0
const SAMPLES := 32
const COLORS := [Color("9aa3b5"), Color("ffdc62"), Color("58dfdb")]
const TICK := 1.0 / 30.0

var studio
var _spans: Array = []        # [[t0, t1] fractions of the sequence] per part
var _dur := 0.0
var _drag_part := -1
var _drag_end := -1           # 0 start, 1 end
var _hover := Vector2i(-1, -1)
var _seen_rebuild := -1
var _seen_key := ""
var k := 1.0                  # size scale: 1 desktop, larger on the phone (finger-sized handles)
signal locked_pressed         # a press on a locked (strike) handle: the phone shows a toast

func _init() -> void:
	custom_minimum_size = Vector2(160, H)
	set_process(true)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Speed ramp: drag a part's start / end handle up or down to set how fast the paddle moves there (1 = even speed). Hollow = authored ease; double-click a handle to go back to it. Click empty graph inside a part to add a speed point (drag it; right-click deletes). Grey: Ready → Wind-up · gold: Strike (Gameplay edit) · cyan: Follow-through. Faint line: real paddle speed (m/s)."

func _def():
	if studio == null or not studio._ok() or studio.key == "" or studio.engine._base or studio.engine._serve or studio.engine.get("_action"): return null
	return studio.engine._current if studio.engine._has_motion() else null

## Part spans from the engine's sequence (prefix = Ready -> Wind-up).
func update_spans() -> void:
	_spans.clear(); _dur = 0.0
	if _def() == null or not studio.engine._timeline._configure(): queue_redraw(); return
	var s = studio.engine._timeline.sequence
	_dur = maxf(s.duration, 0.001)
	var w: float = s.prefix_seconds / _dur; var c: float = (s.prefix_seconds + s.release_seconds) / _dur
	var f: float = (s.prefix_seconds + s.stroke_seconds) / _dur
	_spans = [[0.0, w], [w, c], [c, f]]
	queue_redraw()

## Phone size: handles, text and height scale by `scale_k`.
func set_scale_k(scale_k: float) -> void:
	k = scale_k
	custom_minimum_size = Vector2(160, H * scale_k)
	queue_redraw()

func _process(_d: float) -> void:
	if is_visible_in_tree(): tick()

func tick() -> void:
	var pv = studio.preview if studio else null
	var rc: int = pv.momentum_rebuild_count if pv else -1
	if rc != _seen_rebuild or studio.key != _seen_key:
		_seen_rebuild = rc; _seen_key = studio.key
		update_spans()

func _x(f: float) -> float: return PAD + (size.x - 2.0 * PAD) * clampf(f, 0.0, 1.0)
func _y(speed: float) -> float: return size.y - BOTTOM * k - (size.y - (TOP + BOTTOM) * k) * clampf(speed / Ramp.MAX_SPEED, 0.0, 1.0)
func _speed_at(y: float) -> float: return clampf((size.y - BOTTOM * k - y) / maxf(size.y - (TOP + BOTTOM) * k, 1.0) * Ramp.MAX_SPEED, 0.0, Ramp.MAX_SPEED)

## Handle points of a part: [start, end, point 0, point 1, ...] (ends inset so neighbouring
## parts' handles never overlap). With speed points every handle sits on the real speed.
func _handles(part: int) -> Array:
	var d = _def()
	var x0f: float = _spans[part][0]; var x1f: float = _spans[part][1]
	var x0 := _x(x0f); var x1 := _x(x1f)
	var inset := minf(10.0 * k, (x1 - x0) * 0.25)
	if Ramp.has_points(d, part):
		var out: Array = [Vector2(x0 + inset, _y(Ramp.speed(d, part, 0.0))), Vector2(x1 - inset, _y(Ramp.speed(d, part, 1.0)))]
		for q in _sorted_points(d, part): out.append(Vector2(_x(lerpf(x0f, x1f, q[0])), _y(Ramp.speed(d, part, q[0]))))
		return out
	var e: Vector2 = Ramp.ends(d, part) if Ramp.custom(d, part) else Ramp.authored_ends(d, part)
	return [Vector2(x0 + inset, _y(e.x)), Vector2(x1 - inset, _y(e.y))]

func _sorted_points(d, part: int) -> Array:
	var out: Array = []
	for q in Ramp.points(d, part): out.append([q.x, q.y])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out

func _locked(part: int) -> bool:
	return part == Ramp.STRIKE and studio.gameplay_locked("speed_strike_start")

## Handle under p: (part, index) with index 0 start, 1 end, 2 + i speed point i; (-1, -1) none.
func _pick(p: Vector2) -> Vector2i:
	if _def() == null or _spans.size() < 3: return Vector2i(-1, -1)
	var best := Vector2i(-1, -1); var bd := GRAB * k
	for part in 3:
		var hs := _handles(part)
		for e in hs.size():
			var d: float = hs[e].distance_to(p)
			if d < bd: bd = d; best = Vector2i(part, e)
	return best

## Part whose time span holds x (-1 = none).
func _part_at(px: float) -> int:
	if _spans.size() < 3: return -1
	for part in 3:
		if px >= _x(_spans[part][0]) and px <= _x(_spans[part][1]): return part
	return -1

func _frac_in(part: int, px: float) -> float:
	var x0 := _x(_spans[part][0]); var x1 := _x(_spans[part][1])
	return clampf((px - x0) / maxf(x1 - x0, 1.0), 0.03, 0.97)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		var h := _pick(ev.position)
		if h.x >= 0 and h.y >= 2 and not _locked(h.x):
			accept_event(); _delete_point(h.x, h.y - 2)
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			var h := _pick(ev.position)
			var part: int = h.x if h.x >= 0 else _part_at(ev.position.x)
			if part < 0: return
			accept_event()
			if _locked(part):
				locked_pressed.emit()
				studio._set_status("Locked: the strike's speed is gameplay timing. Turn on Gameplay edit (top bar) to change it."); return
			if h.x >= 0 and ev.double_click and h.y < 2: reset_part(h.x); return
			studio.begin_edit("speed ramp")
			if h.x < 0:   # empty graph inside a part: a new speed point there
				var idx := _add_point(part, _frac_in(part, ev.position.x))
				if idx < 0: studio.end_edit(); return
				h = Vector2i(part, 2 + idx)
			_drag_part = h.x; _drag_end = h.y
			_moved = false
			_select(Vector2i(h.x, h.y - 2) if h.y >= 2 else Vector2i(-1, -1))
		elif _drag_part >= 0:
			_drag_part = -1; _drag_end = -1
			studio.end_edit(); accept_event(); queue_redraw()
	elif ev is InputEventMouseMotion:
		if _drag_part >= 0:
			_moved = true
			_drag_to(_drag_part, _drag_end, ev.position); accept_event()
		else:
			var h := _pick(ev.position)
			if h != _hover: _hover = h; queue_redraw()
			mouse_default_cursor_shape = Control.CURSOR_MOVE if h.y >= 2 else Control.CURSOR_VSIZE if h.x >= 0 else Control.CURSOR_CROSS if _part_at(ev.position.x) >= 0 else Control.CURSOR_ARROW

var _moved := false
var selected := Vector2i(-1, -1)   # (part, point index) of the last pressed speed point
signal selection_changed

func _select(v: Vector2i) -> void:
	if v == selected: return
	selected = v; selection_changed.emit(); queue_redraw()

## Working copy of a part's raw keys: {e: Vector2 ends, pts: [[x, v]] sorted}.
func _work(part: int) -> Dictionary:
	var d = _def()
	if Ramp.has_points(d, part): return {"e": Ramp.ends(d, part), "pts": _sorted_points(d, part)}
	var e: Vector2 = Ramp.ends(d, part) if Ramp.custom(d, part) else Ramp.authored_ends(d, part)
	return {"e": e, "pts": []}

func _write(part: int, w: Dictionary) -> void:
	var f: Array = Ramp.FIELDS[part]
	var pts := PackedVector3Array()
	for q in w.pts: pts.append(Vector3(snappedf(q[0], 0.005), snappedf(q[1], 0.01), 0.0))
	studio.set_field(f[0], null, snappedf(w.e.x, 0.01), false, false)
	studio.set_field(f[1], null, snappedf(w.e.y, 0.01), false, false)
	studio.set_speed_points(part, pts)
	queue_redraw()

func _keys_of(w: Dictionary) -> Array:
	var out: Array = [[0.0, w.e.x]]; out.append_array(w.pts); out.append([1.0, w.e.y]); return out

## Insert a speed point at time fraction x on the current curve (the shape barely changes).
## Returns its index among the sorted points, -1 when the part is full.
func _add_point(part: int, x: float) -> int:
	var d = _def()
	var w := _work(part)
	if w.pts.size() >= Ramp.MAX_POINTS:
		studio._set_status("A part holds at most %d speed points" % Ramp.MAX_POINTS); return -1
	var v: float = Ramp.spline(_keys_of(w), x) if w.pts.size() > 0 else Ramp.speed(d, part, x)
	w.pts.append([x, clampf(v, 0.0, Ramp.MAX_SPEED)])
	w.pts.sort_custom(func(a, b): return a[0] < b[0])
	_write(part, w)
	for i in w.pts.size(): if is_equal_approx(w.pts[i][0], x): return i
	return 0

func _delete_point(part: int, idx: int) -> void:
	var w := _work(part)
	if idx < 0 or idx >= w.pts.size(): return
	w.pts.remove_at(idx)
	studio.begin_edit("speed point delete"); _write(part, w); studio.end_edit()
	_select(Vector2i(-1, -1))

## Delete the selected speed point (phone button).
func delete_selected() -> bool:
	if selected.x < 0 or _locked(selected.x): return false
	_delete_point(selected.x, selected.y); return true

## Drag handle `idx` of `part` toward pointer p. Ends move up / down; points also slide in time.
## With points the target is the real speed: raw keys are rescaled until the shown speed matches.
func _drag_to(part: int, idx: int, p: Vector2) -> void:
	var target := _speed_at(p.y)
	var w := _work(part)
	if w.pts.is_empty() and idx < 2:
		w.e[idx] = snappedf(target, 0.05); _write(part, w); return
	var x_new := -1.0
	if idx >= 2:
		var i := idx - 2
		if i >= w.pts.size(): return
		x_new = _frac_in(part, p.x)
		w.pts[i][0] = x_new
	for _it in 6:
		var kk := _keys_of(w)
		var m := Ramp.mean_of(kk)
		var raw: float = w.e[idx] if idx < 2 else w.pts[idx - 2][1]
		var shown := raw / m
		var nraw: float = target * m if shown < 0.0001 else raw * target / shown
		nraw = clampf(nraw, 0.0, Ramp.MAX_SPEED)
		if idx < 2: w.e[idx] = nraw
		else: w.pts[idx - 2][1] = nraw
	if idx >= 2:
		var moved: Array = w.pts[idx - 2]
		w.pts.sort_custom(func(a, b): return a[0] < b[0])
		_drag_end = 2 + w.pts.find(moved)
		_select(Vector2i(part, _drag_end - 2))
	_write(part, w)

func reset_part(part: int) -> void:
	var f: Array = Ramp.FIELDS[part]
	studio.begin_edit("speed ramp reset")
	studio.set_speed_points(part, PackedVector3Array(), false)
	studio.set_field(f[0], null, -1.0, false, false)
	studio.set_field(f[1], null, -1.0)
	studio.end_edit()
	_select(Vector2i(-1, -1))
	queue_redraw()

## Set a part's ramp directly (link / tests): -1, -1 = authored; points [[x, speed], ...] raw.
func set_part(part: int, start: float, end: float, pts: Array = []) -> Dictionary:
	if _def() == null: return {"ok": false, "error": "speed ramp: strokes only"}
	var f: Array = Ramp.FIELDS[part]
	studio.begin_edit("speed ramp")
	var a: Dictionary = studio.set_field(f[0], null, start, false, false)
	var b: Dictionary = studio.set_field(f[1], null, end, false, false)
	var c: Dictionary = studio.set_speed_points(part, pts)
	studio.end_edit()
	return {"ok": a.get("ok", false) and b.get("ok", false) and c.get("ok", false), "error": a.get("error", b.get("error", c.get("error", "")))}

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0d1f2b"))
	var font := get_theme_font("font"); var fs := int(round(11 * k))
	var d = _def()
	if d == null or _spans.size() < 3:
		draw_string(font, Vector2(PAD, size.y * 0.5 + 4.0), "Speed ramp: strokes only", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("6f8796"))
		return
	# 1 = even speed.
	var y1 := _y(1.0)
	for i in int((size.x - 2.0 * PAD) / 8.0):
		draw_line(Vector2(PAD + i * 8.0, y1), Vector2(PAD + i * 8.0 + 4.0, y1), Color(1, 1, 1, 0.12), k)
	# Real solved paddle-head speed (m/s) behind the parts.
	var pv = studio.preview
	var heads: PackedVector3Array = pv.momentum_heads if pv else PackedVector3Array()
	if heads.size() > 2 and _dur > 0.0:
		var sp := PackedFloat32Array(); var top := 0.001
		for i in heads.size() - 1:
			var v := heads[i].distance_to(heads[i + 1]) / TICK; sp.append(v); top = maxf(top, v)
		var pts := PackedVector2Array()
		for i in sp.size():
			pts.append(Vector2(_x((i + 0.5) * TICK / _dur), size.y - BOTTOM * k - (size.y - (TOP + BOTTOM) * k) * sp[i] / top))
		draw_polyline(pts, Color(0.75, 0.85, 0.95, 0.22), 1.5 * k, true)
		draw_string(font, Vector2(size.x - PAD - 96.0 * k, 11.0 * k), "paddle peak %.1f m/s" % top, HORIZONTAL_ALIGNMENT_RIGHT, 96 * k, fs, Color(0.75, 0.85, 0.95, 0.5))
	for part in 3:
		var x0 := _x(_spans[part][0]); var x1 := _x(_spans[part][1])
		if part > 0: draw_line(Vector2(x0, (TOP - 4.0) * k), Vector2(x0, size.y - BOTTOM * k), Color(COLORS[part], 0.35), k)
		var pts := PackedVector2Array()
		for i in SAMPLES + 1:
			var u := float(i) / SAMPLES
			pts.append(Vector2(lerpf(x0, x1, u), _y(Ramp.speed(d, part, u))))
		var custom := Ramp.custom(d, part)
		var col: Color = COLORS[part]; col.a = 1.0 if custom else 0.6
		draw_polyline(pts, col, (2.0 if custom else 1.5) * k, true)
		if x1 - x0 > 60.0 * k:
			draw_string(font, Vector2(x0 + 4.0 * k, 11.0 * k), Ramp.NAMES[part] + ("" if custom else " · authored"), HORIZONTAL_ALIGNMENT_LEFT, x1 - x0 - 8.0 * k, fs, Color(COLORS[part], 0.8))
		var hs := _handles(part)
		var locked := _locked(part)
		for e in hs.size():
			var p: Vector2 = hs[e]
			var hot := (_drag_part == part and _drag_end == e) or _hover == Vector2i(part, e)
			var r := (5.0 + (1.5 if hot else 0.0)) * k
			if e >= 2:   # a speed point: a round handle, ringed while selected
				draw_circle(p, r + 1.5 * k, Color("122630"), true, -1.0, true)
				draw_circle(p, r, Color("eef5fa") if hot else Color(COLORS[part], 0.45 if locked else 1.0), true, -1.0, true)
				if selected == Vector2i(part, e - 2): draw_circle(p, r + 3.0 * k, Color("eef5fa"), false, 1.5 * k, true)
				if hot: draw_string(font, p + Vector2(8.0, -6.0) * k, "×%.2f" % _speed_at(p.y), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("eef5fa"))
				continue
			var dia := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
			draw_colored_polygon(dia, Color("122630"))
			var c: Color = Color("eef5fa") if hot else Color(COLORS[part], 0.45 if locked else 1.0)
			if custom: draw_colored_polygon(dia, c)
			else: draw_polyline(dia + PackedVector2Array([dia[0]]), c, 1.5 * k, true)
			if hot: draw_string(font, p + Vector2(8.0, -6.0) * k, "×%.2f" % _speed_at(p.y), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("eef5fa"))

## Every part back to the authored ease (one undo step).
func reset_all() -> void:
	studio.begin_edit("speed ramp reset")
	for part in 3:
		if _locked(part): continue
		var f: Array = Ramp.FIELDS[part]
		studio.set_speed_points(part, PackedVector3Array(), false)
		studio.set_field(f[0], null, -1.0, false, false)
		studio.set_field(f[1], null, -1.0)
	studio.end_edit()
	_select(Vector2i(-1, -1))
	queue_redraw()

## For the link / tests: spans, handle points (graph pixels) and each part's ramp.
func state() -> Dictionary:
	var d = _def()
	var parts: Array = []
	if d != null and _spans.size() == 3:
		for part in 3:
			var hs := _handles(part)
			parts.append({"name": Ramp.NAMES[part], "span": _spans[part], "custom": Ramp.custom(d, part),
				"ends": [Ramp.ends(d, part).x, Ramp.ends(d, part).y] if Ramp.custom(d, part) else [Ramp.authored_ends(d, part).x, Ramp.authored_ends(d, part).y],
				"handles": hs.map(func(h: Vector2): return [h.x, h.y]), "locked": _locked(part),
				"points": _sorted_points(d, part)})
	return {"shown": d != null, "size": [size.x, size.y], "parts": parts, "selected": [selected.x, selected.y]}
