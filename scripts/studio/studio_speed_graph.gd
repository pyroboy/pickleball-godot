extends Control
## Desktop Pose Studio: speed ramp graph under the timeline scrubber (same time axis).
## Three parts, Ready -> Wind-up, Strike, Follow-through (stroke_speed_ramp.gd). Each part shows
## its relative speed (1 = the part's average speed, dashed line) as a coloured curve, with the
## real solved paddle-head speed (m/s, from the trajectory arc) faint behind it.
## Drag a part's start / end handle up or down to set the speed there. A hollow handle = the
## authored ease (untouched); the first drag switches the part to its own ramp. Double-click a
## handle: back to the authored ease. Durations and keys never move. One undo step per drag.
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

func _init() -> void:
	custom_minimum_size = Vector2(160, H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Speed ramp: drag a part's start / end handle up or down to set how fast the paddle moves there (1 = even speed). Hollow = authored ease; double-click a handle to go back to it. Grey: Ready → Wind-up · gold: Strike (Gameplay edit) · cyan: Follow-through. Faint line: real paddle speed (m/s)."

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

func tick() -> void:
	var pv = studio.preview if studio else null
	var rc: int = pv.momentum_rebuild_count if pv else -1
	if rc != _seen_rebuild or studio.key != _seen_key:
		_seen_rebuild = rc; _seen_key = studio.key
		update_spans()

func _x(f: float) -> float: return PAD + (size.x - 2.0 * PAD) * clampf(f, 0.0, 1.0)
func _y(speed: float) -> float: return size.y - BOTTOM - (size.y - TOP - BOTTOM) * clampf(speed / Ramp.MAX_SPEED, 0.0, 1.0)
func _speed_at(y: float) -> float: return clampf((size.y - BOTTOM - y) / maxf(size.y - TOP - BOTTOM, 1.0) * Ramp.MAX_SPEED, 0.0, Ramp.MAX_SPEED)

## Handle points of a part: [start, end] (inset so neighbouring parts' handles never overlap).
func _handles(part: int) -> Array:
	var d = _def()
	var e: Vector2 = Ramp.ends(d, part) if Ramp.custom(d, part) else Ramp.authored_ends(d, part)
	var x0 := _x(_spans[part][0]); var x1 := _x(_spans[part][1])
	var inset := minf(10.0, (x1 - x0) * 0.25)
	return [Vector2(x0 + inset, _y(e.x)), Vector2(x1 - inset, _y(e.y))]

func _locked(part: int) -> bool:
	return part == Ramp.STRIKE and studio.gameplay_locked("speed_strike_start")

func _pick(p: Vector2) -> Vector2i:
	if _def() == null or _spans.size() < 3: return Vector2i(-1, -1)
	var best := Vector2i(-1, -1); var bd := GRAB
	for part in 3:
		var hs := _handles(part)
		for e in 2:
			var d: float = hs[e].distance_to(p)
			if d < bd: bd = d; best = Vector2i(part, e)
	return best

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			var h := _pick(ev.position)
			if h.x < 0: return
			accept_event()
			if _locked(h.x):
				studio._set_status("Locked: the strike's speed is gameplay timing. Turn on Gameplay edit (top bar) to change it."); return
			if ev.double_click: reset_part(h.x); return
			_drag_part = h.x; _drag_end = h.y
			studio.begin_edit("speed ramp")
			_set_end(_drag_part, _drag_end, _speed_at(ev.position.y))
		elif _drag_part >= 0:
			_drag_part = -1; _drag_end = -1
			studio.end_edit(); accept_event(); queue_redraw()
	elif ev is InputEventMouseMotion:
		if _drag_part >= 0:
			_set_end(_drag_part, _drag_end, _speed_at(ev.position.y)); accept_event()
		else:
			var h := _pick(ev.position)
			if h != _hover: _hover = h; queue_redraw()
			mouse_default_cursor_shape = Control.CURSOR_VSIZE if h.x >= 0 else Control.CURSOR_ARROW

## Set one end's speed (an authored part first takes its authored ends, so the other end keeps
## roughly its look).
func _set_end(part: int, end: int, value: float) -> void:
	var d = _def()
	if d == null: return
	var e: Vector2 = Ramp.ends(d, part) if Ramp.custom(d, part) else Ramp.authored_ends(d, part)
	e[end] = value
	e = Vector2(snappedf(e.x, 0.05), snappedf(e.y, 0.05))
	var f: Array = Ramp.FIELDS[part]
	studio.set_field(f[0], null, e.x, false, false)
	studio.set_field(f[1], null, e.y)
	queue_redraw()

func reset_part(part: int) -> void:
	var f: Array = Ramp.FIELDS[part]
	studio.begin_edit("speed ramp reset")
	studio.set_field(f[0], null, -1.0, false, false)
	studio.set_field(f[1], null, -1.0)
	studio.end_edit()
	queue_redraw()

## Set a part's ramp directly (link / tests): -1, -1 = authored.
func set_part(part: int, start: float, end: float) -> Dictionary:
	if _def() == null: return {"ok": false, "error": "speed ramp: strokes only"}
	var f: Array = Ramp.FIELDS[part]
	studio.begin_edit("speed ramp")
	var a: Dictionary = studio.set_field(f[0], null, start, false, false)
	var b: Dictionary = studio.set_field(f[1], null, end)
	studio.end_edit()
	return {"ok": a.get("ok", false) and b.get("ok", false), "error": a.get("error", b.get("error", ""))}

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0d1f2b"))
	var font := get_theme_font("font"); var fs := 11
	var d = _def()
	if d == null or _spans.size() < 3:
		draw_string(font, Vector2(PAD, size.y * 0.5 + 4.0), "Speed ramp: strokes only", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("6f8796"))
		return
	# 1 = even speed.
	var y1 := _y(1.0)
	for i in int((size.x - 2.0 * PAD) / 8.0):
		draw_line(Vector2(PAD + i * 8.0, y1), Vector2(PAD + i * 8.0 + 4.0, y1), Color(1, 1, 1, 0.12), 1.0)
	# Real solved paddle-head speed (m/s) behind the parts.
	var pv = studio.preview
	var heads: PackedVector3Array = pv.momentum_heads if pv else PackedVector3Array()
	if heads.size() > 2 and _dur > 0.0:
		var sp := PackedFloat32Array(); var top := 0.001
		for i in heads.size() - 1:
			var v := heads[i].distance_to(heads[i + 1]) / TICK; sp.append(v); top = maxf(top, v)
		var pts := PackedVector2Array()
		for i in sp.size():
			pts.append(Vector2(_x((i + 0.5) * TICK / _dur), size.y - BOTTOM - (size.y - TOP - BOTTOM) * sp[i] / top))
		draw_polyline(pts, Color(0.75, 0.85, 0.95, 0.22), 1.5, true)
		draw_string(font, Vector2(size.x - PAD - 96.0, 11.0), "paddle peak %.1f m/s" % top, HORIZONTAL_ALIGNMENT_RIGHT, 96, fs, Color(0.75, 0.85, 0.95, 0.5))
	for part in 3:
		var x0 := _x(_spans[part][0]); var x1 := _x(_spans[part][1])
		if part > 0: draw_line(Vector2(x0, TOP - 4.0), Vector2(x0, size.y - BOTTOM), Color(COLORS[part], 0.35), 1.0)
		var pts := PackedVector2Array()
		for i in SAMPLES + 1:
			var u := float(i) / SAMPLES
			pts.append(Vector2(lerpf(x0, x1, u), _y(Ramp.speed(d, part, u))))
		var custom := Ramp.custom(d, part)
		var col: Color = COLORS[part]; col.a = 1.0 if custom else 0.6
		draw_polyline(pts, col, 2.0 if custom else 1.5, true)
		if x1 - x0 > 60.0:
			draw_string(font, Vector2(x0 + 4.0, 11.0), Ramp.NAMES[part] + ("" if custom else " · authored"), HORIZONTAL_ALIGNMENT_LEFT, x1 - x0 - 8.0, fs, Color(COLORS[part], 0.8))
		var hs := _handles(part)
		var locked := _locked(part)
		for e in 2:
			var p: Vector2 = hs[e]
			var hot := (_drag_part == part and _drag_end == e) or _hover == Vector2i(part, e)
			var r := 5.0 + (1.5 if hot else 0.0)
			var dia := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
			draw_colored_polygon(dia, Color("122630"))
			var c: Color = Color("eef5fa") if hot else Color(COLORS[part], 0.45 if locked else 1.0)
			if custom: draw_colored_polygon(dia, c)
			else: draw_polyline(dia + PackedVector2Array([dia[0]]), c, 1.5, true)
			if hot: draw_string(font, p + Vector2(8.0, -6.0), "×%.2f" % _speed_at(p.y), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("eef5fa"))

## For the link / tests: spans, handle points (graph pixels) and each part's ramp.
func state() -> Dictionary:
	var d = _def()
	var parts: Array = []
	if d != null and _spans.size() == 3:
		for part in 3:
			var hs := _handles(part)
			parts.append({"name": Ramp.NAMES[part], "span": _spans[part], "custom": Ramp.custom(d, part),
				"ends": [Ramp.ends(d, part).x, Ramp.ends(d, part).y] if Ramp.custom(d, part) else [Ramp.authored_ends(d, part).x, Ramp.authored_ends(d, part).y],
				"handles": [[hs[0].x, hs[0].y], [hs[1].x, hs[1].y]], "locked": _locked(part)})
	return {"shown": d != null, "size": [size.x, size.y], "parts": parts}
