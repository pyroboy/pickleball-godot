extends Control
## Pose Studio speed graph (desktop: under the timeline scrubber, same time axis; phone: the
## Speed sheet). ONE continuous curve of the paddle's real speed over the whole motion,
## Ready -> Wind-up -> Contact -> Finish (stroke_speed_ramp.gd holds the three parts' data).
##
## Handles
##   key points   one at Ready, Wind-up, Contact and Finish: the speed there, shared by the
##                parts on both sides (so the curve never jumps at a key)
##   speed points up to 4 inside each part (press empty graph to add): drag up / down for the
##                speed, sideways for when; right-click (desktop) or Delete point removes one
## Each part must still cover its distance in its time (durations and keys never move), so when
## one point goes up the other points of that part come down: with a single point in a part its
## height is given, and only its time can change. Add a second point to trade speed between them.
## Hollow handles = the original ease, untouched. Double-click a key point: its two parts back to
## the original. The Strike follows the Gameplay edit lock (and so do the Wind-up and Contact
## key points, which belong to it). One undo step per drag.
##
## Height is real speed (m/s) on a square-root scale, so the slow Ready -> Wind-up part stays
## readable next to the strike. Without a solved path (no arc yet) it falls back to relative
## speed (1 = the part's average).

const Ramp = preload("res://scripts/stroke_speed_ramp.gd")
const H := 104.0
const PAD := 8.0               # same horizontal inset as the scrub track
const TOP := 16.0
const BOTTOM := 6.0
const GRAB := 10.0
const SAMPLES := 28
const COLORS := [Color("9aa3b5"), Color("ffdc62"), Color("58dfdb")]                       # the three parts
const KEY_COLORS := [Color("c9d2e0"), Color("bd80ff"), Color("ffdc62"), Color("58dfdb")]   # Ready, W, C, F
const KEY_NAMES := ["Ready", "Wind-up", "Contact", "Finish"]
const TITLES := [["Ready → Wind-up", "Wind-up", "Prep"], ["Strike", "Hit"], ["Follow-through", "Finish", "End"]]
const SETTLE_FRAMES := 12      # idle frames after the last speed edit before the exact arc rebuild

signal locked_pressed          # a press on a locked handle: the phone shows a toast
signal selection_changed

var studio
var k := 1.0                   # size scale: 1 desktop, larger on the phone (finger-sized handles)
var lock_note := "locked · Gameplay edit"   # under the Strike title while it is locked
var selected := Vector2i(-1, -1)   # (part, point index) of the last pressed speed point
var write_usec := 0            # cost of the last edit applied to the pose (preview update included)
var write_count := 0

var _spans: Array = []         # [[t0, t1] fractions of the sequence] per part
var _dur := 0.0
var _c: Array = [1.0, 1.0, 1.0]   # real speed (m/s) of relative speed 1, per part: path length / duration
var _real := false             # _c holds real scales (else relative speed)
var _top := 3.0                # top of the height scale
var _drag := Vector2i(-2, -2)  # dragged handle: (-1, key) or (part, point); (-2, -2) = none
var _hover := Vector2i(-2, -2)
var _pending := Vector2.ZERO
var _has_pending := false
var _seen_rebuild := -1
var _seen_key := ""
var _pc: Array = [null, null, null]   # per-redraw cache: [keys, mean] of a part with points

func _init() -> void:
	custom_minimum_size = Vector2(160, H)
	set_process(true)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Paddle speed over the whole motion, one curve. Drag a key point (Ready, Wind-up, Contact, Finish) or a speed point up = faster there, down = slower; click empty graph to add a speed point, drag it sideways to move it in time, right-click deletes. Each part keeps its time and distance, so the part's other points give way. Hollow = original ease; double-click a key point to go back to it. Strike: Gameplay edit."

func set_scale_k(scale_k: float) -> void:
	k = scale_k
	custom_minimum_size = Vector2(160, H * scale_k)
	queue_redraw()

func _def():
	if studio == null or not studio._ok() or studio.key == "" or studio.engine._base or studio.engine._serve or studio.engine.get("_action"): return null
	return studio.engine._current if studio.engine._has_motion() else null

## Part spans from the engine's sequence (prefix = Ready -> Wind-up) and the real-speed scales.
func update_spans() -> void:
	_spans.clear(); _dur = 0.0
	if _def() == null or not studio.engine._timeline._configure(): queue_redraw(); return
	var s = studio.engine._timeline.sequence
	_dur = maxf(s.duration, 0.001)
	var w: float = s.prefix_seconds / _dur; var c: float = (s.prefix_seconds + s.release_seconds) / _dur
	var f: float = (s.prefix_seconds + s.stroke_seconds) / _dur
	_spans = [[0.0, w], [w, c], [c, f]]
	_update_scales()
	queue_redraw()

func _update_scales() -> void:
	_real = false; _c = [1.0, 1.0, 1.0]
	var pl: Dictionary = studio.preview.part_lengths() if studio.preview else {}
	if pl.is_empty(): return
	for i in 3:
		if float(pl.seconds[i]) <= 0.0 or float(pl.lengths[i]) <= 0.0005: return   # a part that does not move: stay relative
	for i in 3: _c[i] = float(pl.lengths[i]) / float(pl.seconds[i])
	_real = true

## The height scale follows the curve, but never while a handle is held (it would slide under it).
func _update_top() -> void:
	var d = _def()
	if d == null or _spans.size() < 3: return
	var top := 0.0
	for part in 3:
		for i in SAMPLES + 1: top = maxf(top, _spd(d, part, float(i) / SAMPLES) * _c[part])
	top = maxf(top * 1.2, 1.0 if _real else 1.5)
	if absf(top - _top) > _top * 0.02: _top = top; queue_redraw()

func _flush_drag() -> void:
	if _has_pending and _drag.x > -2: _drag_to(_pending)
	_has_pending = false

func _process(_d: float) -> void:
	if not is_visible_in_tree(): return
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
		if _drag.x == -2: _update_top()

# ---------------------------------------------------------------- geometry

func _x(f: float) -> float: return PAD + (size.x - 2.0 * PAD) * clampf(f, 0.0, 1.0)
func _y(speed: float) -> float:
	return size.y - BOTTOM * k - (size.y - (TOP + BOTTOM) * k) * sqrt(clampf(speed / _top, 0.0, 1.0))
func _speed_at(y: float) -> float:
	var f: float = clampf((size.y - BOTTOM * k - y) / maxf(size.y - (TOP + BOTTOM) * k, 1.0), 0.0, 1.0)
	return _top * f * f

## Relative speed of a part at x from this redraw's cache.
func _spd(d, part: int, x: float) -> float:
	if not Ramp.has_points(d, part): return Ramp.speed(d, part, x)
	if _pc[part] == null:
		var kk: Array = Ramp.keys(d, part)
		_pc[part] = [kk, Ramp.mean_of(kk)]
	return Ramp.spline(_pc[part][0], x) / _pc[part][1]

func _part_locked(part: int) -> bool:
	return part == Ramp.STRIKE and studio.gameplay_locked("speed_strike_start")

## A key point is locked when a part it belongs to is.
func _key_locked(key: int) -> bool:
	return (key > 0 and _part_locked(key - 1)) or (key < 3 and _part_locked(key))

## A part as it plays: {e: relative end speeds, pts: [[x, relative speed]] sorted, custom}.
func _part(part: int) -> Dictionary:
	var d = _def()
	if Ramp.has_points(d, part):
		var kk: Array = Ramp.keys(d, part)
		var m: float = Ramp.mean_of(kk)
		var pts: Array = []
		for i in range(1, kk.size() - 1): pts.append([kk[i][0], kk[i][1] / m])
		return {"e": Vector2(kk[0][1] / m, kk[kk.size() - 1][1] / m), "pts": pts, "custom": true}
	var custom: bool = Ramp.custom(d, part)
	return {"e": Ramp.ends(d, part) if custom else Ramp.authored_ends(d, part), "pts": [], "custom": custom}

func _keys_of(w: Dictionary) -> Array:
	var out: Array = [[0.0, w.e.x]]; out.append_array(w.pts); out.append([1.0, w.e.y]); return out

## Real speed at key point `key` (the mean of its two sides when they disagree).
func _key_value(key: int) -> float:
	var sum := 0.0; var n := 0
	if key > 0: sum += _part(key - 1).e.y * _c[key - 1]; n += 1
	if key < 3: sum += _part(key).e.x * _c[key]; n += 1
	return sum / maxf(n, 1)

func _key_x(key: int) -> float:
	var x := _x(_spans[mini(key, 2)][0] if key < 3 else _spans[2][1])
	if key == 0: return x + minf(9.0 * k, (_x(_spans[0][1]) - x) * 0.2)   # the outer two sit just inside
	if key == 3: return x - minf(9.0 * k, (x - _x(_spans[2][0])) * 0.2)
	return x

## Every handle: [[id, point]], id (-1, key) or (part, point index).
func _handles() -> Array:
	var d = _def()
	var out: Array = []
	if d == null or _spans.size() < 3: return out
	for key in 4: out.append([Vector2i(-1, key), Vector2(_key_x(key), _y(_key_value(key)))])
	for part in 3:
		if not Ramp.has_points(d, part): continue
		var w := _part(part)
		for i in w.pts.size():
			out.append([Vector2i(part, i), Vector2(_x(lerpf(_spans[part][0], _spans[part][1], w.pts[i][0])), _y(w.pts[i][1] * _c[part]))])
	return out

func _pick(p: Vector2) -> Vector2i:
	var best := Vector2i(-2, -2); var bd := GRAB * k
	for h in _handles():
		var d: float = (h[1] as Vector2).distance_to(p)
		if d < bd: bd = d; best = h[0]
	return best

func _part_at(px: float) -> int:
	if _spans.size() < 3: return -1
	for part in 3:
		if px >= _x(_spans[part][0]) and px <= _x(_spans[part][1]): return part
	return -1

func _frac_in(part: int, px: float) -> float:
	var x0 := _x(_spans[part][0]); var x1 := _x(_spans[part][1])
	return clampf((px - x0) / maxf(x1 - x0, 1.0), 0.04, 0.96)

# ---------------------------------------------------------------- editing

## Bring a part back to "its distance in its time": the entries marked free share one factor.
## A part without points is a Hermite ramp of its two ends and always fits.
func _settle(w: Dictionary, free_start: bool, free_end: bool, free_pts: Array) -> bool:
	w.e = Vector2(clampf(w.e.x, 0.0, Ramp.MAX_SPEED), clampf(w.e.y, 0.0, Ramp.MAX_SPEED))
	if w.pts.is_empty(): return true
	var free: Array = [free_start]; free.append_array(free_pts); free.append(free_end)
	var r: Array = Ramp.solve_mean(_keys_of(w), free)
	if r.is_empty(): return false
	w.e = Vector2(r[0][1], r[r.size() - 1][1])
	for i in w.pts.size(): w.pts[i][1] = r[i + 1][1]
	return true

func _all(n: int, v: bool) -> Array:
	var out: Array = []
	out.resize(n); out.fill(v)
	return out

## The neighbours of `part` take the new speeds at the key points they share with it. False when
## one cannot (locked, or out of range): the whole move is dropped.
func _follow(part: int, w: Dictionary, writes: Dictionary) -> bool:
	for nb in [[part - 1, 1, w.e.x], [part + 1, 0, w.e.y]]:
		var n: int = nb[0]
		if n < 0 or n > 2: continue
		var wn := _part(n)
		var v: float = float(nb[2]) * _c[part] / _c[n]
		if absf(wn.e[nb[1]] - v) < 0.003: continue
		if _part_locked(n) or v > Ramp.MAX_SPEED + 0.001: return false
		wn.e[nb[1]] = v
		if not _settle(wn, false, false, _all(wn.pts.size(), true)): return false
		writes[n] = wn
	return true

func _apply(writes: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	_pc = [null, null, null]
	var parts: Array = writes.keys()
	for i in parts.size():
		var part: int = parts[i]
		var w: Dictionary = writes[part]
		var f: Array = Ramp.FIELDS[part]
		var pts := PackedVector3Array()
		for q in w.pts: pts.append(Vector3(snappedf(q[0], 0.005), snappedf(q[1], 0.001), 0.0))
		studio.set_field(f[0], null, snappedf(w.e.x, 0.001), false, false)
		studio.set_field(f[1], null, snappedf(w.e.y, 0.001), false, false)
		studio.set_speed_points(part, pts, i == parts.size() - 1)
	write_usec = Time.get_ticks_usec() - t0; write_count += 1
	queue_redraw()

## Key point `key` to real speed `value`: both its parts take it, their speed points give way.
func set_key(key: int, value: float) -> bool:
	if _key_locked(key): return false
	var writes := {}
	for side in [[key - 1, 1], [key, 0]]:
		var part: int = side[0]
		if part < 0 or part > 2: continue
		var w := _part(part)
		w.e[side[1]] = clampf(value / _c[part], 0.0, Ramp.MAX_SPEED)
		if not _settle(w, false, false, _all(w.pts.size(), true)): return false
		writes[part] = w
	# both sides must really meet (a clamp on one side would open a step)
	if writes.size() == 2 and absf(writes[key - 1].e.y * _c[key - 1] - writes[key].e.x * _c[key]) > 0.02 * maxf(_top, 0.1): return false
	_apply(writes)
	return true

## Speed point `idx` of `part` to time fraction x and real speed `value`. The rest of the part
## gives way (its other points, and its key points when the part next door is free to follow);
## when nothing can, the point keeps the height the distance needs and only moves in time.
## Returns the point's index after the move (-1: not possible).
func set_point(part: int, idx: int, x: float, value: float) -> int:
	if _part_locked(part): return -1
	var w := _part(part)
	if idx < 0 or idx >= w.pts.size(): return -1
	var was: float = w.pts[idx][1]
	var want: float = clampf(value / _c[part], 0.0, Ramp.MAX_SPEED)
	var moved: Array = [clampf(x, 0.04, 0.96), want]
	w.pts[idx] = moved
	w.pts.sort_custom(func(a, b): return a[0] < b[0])
	var j: int = w.pts.find(moved)
	var writes := {}
	if not _try_point(part, w, j, want, writes):
		# Too far for the part's distance: as far toward it as fits (the point stops there).
		var lo := was; var hi := want
		var found := false
		for it in 7:
			var mid := (lo + hi) * 0.5
			var trial := {}
			if _try_point(part, w, j, mid, trial): lo = mid; writes = trial; found = true
			else: hi = mid
		if not found:
			writes.clear()   # nothing can give at all: the height the distance needs, only the time moves
			var only := _all(w.pts.size(), false); only[j] = true
			var forced: Dictionary = w.duplicate(true)
			if not _settle(forced, false, false, only): return -1
			writes[part] = forced
	_apply(writes)
	return j

## Speed point j of `w` at relative speed v, the rest of the part (and its neighbours) following.
func _try_point(part: int, w: Dictionary, j: int, v: float, writes: Dictionary) -> bool:
	var trial: Dictionary = w.duplicate(true)
	trial.pts[j][1] = v
	var others := _all(trial.pts.size(), true); others[j] = false
	var free_start: bool = part == 0 or not _part_locked(part - 1)
	var free_end: bool = part == 2 or not _part_locked(part + 1)
	writes.clear()
	if not _settle(trial, free_start, free_end, others) or not _follow(part, trial, writes): return false
	writes[part] = trial
	return true

## A new speed point at time fraction x, on the curve. Its index, -1 when the part is full / locked.
func add_point(part: int, x: float) -> int:
	if _part_locked(part): return -1
	var d = _def()
	var w := _part(part)
	if w.pts.size() >= Ramp.MAX_POINTS:
		studio._set_status("A part holds at most %d speed points" % Ramp.MAX_POINTS); return -1
	var added: Array = [clampf(x, 0.04, 0.96), clampf(_spd(d, part, x), 0.0, Ramp.MAX_SPEED)]
	w.pts.append(added)
	w.pts.sort_custom(func(a, b): return a[0] < b[0])
	var j: int = w.pts.find(added)
	var only := _all(w.pts.size(), false); only[j] = true
	if not _settle(w, false, false, only) and not _settle(w, false, false, _all(w.pts.size(), true)): return -1
	_apply({part: w})
	return j

func delete_point(part: int, idx: int) -> bool:
	if _part_locked(part): return false
	var w := _part(part)
	if idx < 0 or idx >= w.pts.size(): return false
	w.pts.remove_at(idx)
	if not _settle(w, false, false, _all(w.pts.size(), true)): return false
	studio.begin_edit("speed point delete"); _apply({part: w}); studio.end_edit()
	_select(Vector2i(-1, -1))
	return true

## Delete the selected speed point (phone button).
func delete_selected() -> bool:
	return selected.x >= 0 and delete_point(selected.x, selected.y)

func reset_part(part: int) -> void:
	if _part_locked(part): return
	var f: Array = Ramp.FIELDS[part]
	_pc = [null, null, null]
	studio.set_speed_points(part, PackedVector3Array(), false)
	studio.set_field(f[0], null, -1.0, false, false)
	studio.set_field(f[1], null, -1.0)

## Every free part back to the original ease (one undo step).
func reset_all() -> void:
	studio.begin_edit("speed reset")
	for part in 3: reset_part(part)
	studio.end_edit()
	_select(Vector2i(-1, -1))
	queue_redraw()

func _select(v: Vector2i) -> void:
	if v == selected: return
	selected = v; selection_changed.emit(); queue_redraw()

func _gui_input(ev: InputEvent) -> void:
	if _def() == null or _spans.size() < 3: return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		var h := _pick(ev.position)
		if h.x >= 0:
			accept_event()
			if not delete_point(h.x, h.y): _refuse()
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			var h := _pick(ev.position)
			var part: int = h.x if h.x >= 0 else _part_at(ev.position.x)
			if h.x == -2 and part < 0: return
			accept_event()
			if (h.x == -1 and _key_locked(h.y)) or (h.x != -1 and _part_locked(part)): _refuse(); return
			if h.x == -1 and ev.double_click:   # a key point: its parts back to the original
				studio.begin_edit("speed reset")
				for p in [h.y - 1, h.y]: if p >= 0 and p <= 2: reset_part(p)
				studio.end_edit(); _select(Vector2i(-1, -1)); queue_redraw(); return
			studio.begin_edit("speed")
			if h.x == -2:   # empty graph inside a part: a new speed point there
				var idx := add_point(part, _frac_in(part, ev.position.x))
				if idx < 0: studio.end_edit(); return
				h = Vector2i(part, idx)
			_drag = h
			_select(h if h.x >= 0 else Vector2i(-1, -1))
		elif _drag.x > -2:
			_flush_drag()
			_drag = Vector2i(-2, -2)
			studio.end_edit(); accept_event()
			_update_top(); queue_redraw()
	elif ev is InputEventMouseMotion:
		if _drag.x > -2:   # applied once per frame (_process): several moves can arrive in one
			_pending = ev.position; _has_pending = true; accept_event()
		else:
			var h := _pick(ev.position)
			if h != _hover: _hover = h; queue_redraw()
			mouse_default_cursor_shape = Control.CURSOR_MOVE if h.x >= 0 else Control.CURSOR_VSIZE if h.x == -1 else Control.CURSOR_CROSS if _part_at(ev.position.x) >= 0 else Control.CURSOR_ARROW

func _refuse() -> void:
	locked_pressed.emit()
	studio._set_status("Locked: the strike's speed is gameplay timing. Turn on Gameplay edit (top bar) to change it.")

func _drag_to(p: Vector2) -> void:
	var value := _speed_at(p.y)
	if _drag.x == -1: set_key(_drag.y, value)
	else:
		var j := set_point(_drag.x, _drag.y, _frac_in(_drag.x, p.x), value)
		if j >= 0 and j != _drag.y:
			_drag.y = j; _select(_drag)

# ---------------------------------------------------------------- drawing

func _fmt(v: float) -> String:
	return ("%.1f m/s" % v) if _real else ("×%.2f" % v)

func _draw() -> void:
	_pc = [null, null, null]
	draw_rect(Rect2(Vector2.ZERO, size), Color("0d1f2b"))
	var font := get_theme_font("font"); var fs := int(round(11 * k))
	var d = _def()
	if d == null or _spans.size() < 3:
		draw_string(font, Vector2(PAD, size.y * 0.5 + 4.0), "Speed: pick a stroke (stances and serves have no speed curve)", HORIZONTAL_ALIGNMENT_LEFT, size.x - 2.0 * PAD, fs, Color("6f8796"))
		return
	var top := TOP * k; var bottom := size.y - BOTTOM * k
	# Part columns: a tint, a title that fits (shorter names for narrow parts), hatching when locked.
	for part in 3:
		var x0 := _x(_spans[part][0]); var x1 := _x(_spans[part][1])
		var locked := _part_locked(part)
		draw_rect(Rect2(x0, top, x1 - x0, bottom - top), Color(COLORS[part], 0.03 if locked else 0.07))
		for name in TITLES[part]:
			var label: String = name
			if font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= x1 - x0 - 8.0 * k:
				draw_string(font, Vector2(x0 + 4.0 * k, 11.0 * k), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(COLORS[part], 0.5 if locked else 0.95))
				break
		if locked:
			for n in int((x1 - x0) / (9.0 * k)) + 1:
				var hx := x0 + n * 9.0 * k
				draw_line(Vector2(hx, bottom), Vector2(minf(hx + (bottom - top) * 0.5, x1), bottom - minf((bottom - top), (x1 - hx) * 2.0)), Color(1, 1, 1, 0.045), k)
			if font.get_string_size(lock_note, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= x1 - x0 - 8.0 * k:
				draw_string(font, Vector2(x0 + 4.0 * k, top + 12.0 * k), lock_note, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.45))
	# Height scale: a few speed lines, labelled on the right, never crowding each other or the floor.
	var last_y := bottom - 12.0 * k
	for tick in ([1.0, 5.0, 10.0, 20.0, 40.0] if _real else [1.0, 2.0, 3.0]):
		if tick > _top * 0.97: break
		var y := _y(tick)
		if y > last_y - 15.0 * k: continue
		last_y = y
		for i in int((size.x - 2.0 * PAD) / (8.0 * k)):
			draw_line(Vector2(PAD + i * 8.0 * k, y), Vector2(PAD + i * 8.0 * k + 3.0 * k, y), Color(1, 1, 1, 0.09), k)
		draw_string(font, Vector2(size.x - PAD - 70.0 * k, y - 2.0 * k), ("%d m/s" % int(tick)) if _real else ("×%d" % int(tick)), HORIZONTAL_ALIGNMENT_RIGHT, 70.0 * k, fs, Color(1, 1, 1, 0.3))
	# Key lines (Wind-up, Contact) through the graph.
	for key in [1, 2]:
		var x := _x(_spans[key][0])
		draw_line(Vector2(x, 2.0 * k), Vector2(x, bottom), Color(KEY_COLORS[key], 0.35), k)
	# The curve: one line, coloured by part.
	for part in 3:
		var x0 := _x(_spans[part][0]); var x1 := _x(_spans[part][1])
		var pts := PackedVector2Array()
		for i in SAMPLES + 1:
			var u := float(i) / SAMPLES
			pts.append(Vector2(lerpf(x0, x1, u), _y(_spd(d, part, u) * _c[part])))
		var col: Color = COLORS[part]; col.a = 0.45 if _part_locked(part) else 1.0 if Ramp.custom(d, part) else 0.75
		draw_polyline(pts, col, 2.5 * k, true)
	# Handles: key points (bigger, in the key's colour), then speed points.
	for h in _handles():
		var id: Vector2i = h[0]; var p: Vector2 = h[1]
		var hot: bool = _drag == id or _hover == id
		var is_key := id.x == -1
		var locked: bool = _key_locked(id.y) if is_key else _part_locked(id.x)
		var custom: bool = true
		if is_key: custom = (id.y > 0 and Ramp.custom(d, id.y - 1)) or (id.y < 3 and Ramp.custom(d, id.y))
		var r := ((6.5 if is_key else 5.0) + (1.5 if hot else 0.0)) * k
		var c: Color = Color("eef5fa") if hot else Color(KEY_COLORS[id.y] if is_key else COLORS[id.x], 0.4 if locked else 1.0)
		draw_circle(p, r + 1.5 * k, Color("0d1f2b"), true, -1.0, true)
		if custom: draw_circle(p, r, c, true, -1.0, true)
		else: draw_circle(p, r, c, false, 1.5 * k, true)   # hollow: the original ease, untouched
		var sel: bool = not is_key and selected == id
		if sel: draw_circle(p, r + 3.5 * k, Color("eef5fa"), false, 1.5 * k, true)
		if hot or sel:
			var txt := ("%s  " % KEY_NAMES[id.y] if is_key else "") + _fmt(_speed_at(p.y))
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := Vector2(clampf(p.x + 10.0 * k, PAD, size.x - PAD - tw), maxf(p.y - 9.0 * k, top + fs))
			draw_rect(Rect2(at + Vector2(-3.0 * k, -fs), Vector2(tw + 6.0 * k, fs + 4.0 * k)), Color(0.05, 0.12, 0.17, 0.92))
			draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("eef5fa"))

## For the link / tests: the curve as data.
func state() -> Dictionary:
	var d = _def()
	var parts: Array = []; var keys: Array = []
	if d != null and _spans.size() == 3:
		for key in 4:
			var sides: Array = []
			if key > 0: sides.append(_part(key - 1).e.y * _c[key - 1])
			if key < 3: sides.append(_part(key).e.x * _c[key])
			keys.append({"name": KEY_NAMES[key], "value": _key_value(key), "sides": sides, "x": _key_x(key), "y": _y(_key_value(key)), "locked": _key_locked(key)})
		for part in 3:
			var w := _part(part)
			var pts: Array = []
			for q in w.pts: pts.append({"t": q[0], "value": q[1] * _c[part], "x": _x(lerpf(_spans[part][0], _spans[part][1], q[0])), "y": _y(q[1] * _c[part])})
			parts.append({"name": Ramp.NAMES[part], "span": _spans[part], "custom": w.custom, "scale": _c[part], "points": pts,
				"mean": Ramp.mean_of(_keys_of(w)) if not w.pts.is_empty() else 1.0, "locked": _part_locked(part)})
	var pv = studio.preview if studio else null
	return {"shown": d != null, "size": [size.x, size.y], "real": _real, "top": _top, "keys": keys, "parts": parts,
		"selected": [selected.x, selected.y], "write_usec": write_usec, "write_count": write_count,
		"retimes": pv.momentum_retime_count if pv else 0, "retime_usec": pv.momentum_retime_usec if pv else 0, "rebuilds": pv.motion_rebuild_count if pv else 0}
