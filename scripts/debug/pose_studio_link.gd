extends "res://scripts/debug/pose_shots.gd"
## Pose Studio link: TCP JSON-lines server (127.0.0.1 only) so Claude can drive and check the
## Desktop Pose Studio by data. Contract: tools/pose_studio/PROTOCOL.md section 1.
## Loaded by perf_monitor.gd on user arg --pose-studio=<port>. Windowed runs only for frames.
## Boot: once the game scene is ready it starts scripts/studio/pose_studio.gd (window
## maximized, or --studio-window=full) and works on studio.engine, routing select / stage /
## set / undo / redo / save / revert / reload through the studio so link and UI agree.
## Without the studio script it opens the mobile editor itself (link-only mode).
## Studio mode skips the user:// pose overrides so the preview shows the repo .tres files.
## The link never writes pose files itself: `save` goes through studio.save (tools/pose_notes.py).

const Fields = preload("res://scripts/ui/mobile_pose_fields.gd")
const Keyframe = preload("res://scripts/stroke_body_keyframe.gd")
const PaddleRotation = preload("res://scripts/paddle_rotation.gd")
const Store = preload("res://scripts/mobile_pose_store.gd")
const PoseDiff = preload("res://scripts/studio/pose_diff_util.gd")
const LayoutAudit = preload("res://scripts/studio/studio_layout_audit.gd")
const STUDIO_SCRIPT := "res://scripts/studio/pose_studio.gd"
const VERSION := 1
const TICK := 1.0 / 30.0
const MAX_LINE := 1 << 20
const KEEPS_LOOP := ["ping", "poses", "fields", "metrics", "diff", "frame", "nodes", "timeline", "view", "toggle", "play", "ui", "ui_audit", "window"]

var port := 8766
var _server := TCPServer.new()
var _peer: StreamPeerTCP
var _buf := PackedByteArray()
var _queue: Array = []
var _busy := false
var _ed = null
var _studio = null        # Desktop Pose Studio root (null in link-only mode)
var window_report := {}  # maximize_window result (ping: window)
var _sel := ""            # selected pose key in link-only mode (s13 / b04); see _key()
var _loop := false
var _contact_on := true
var _seq := 0
var _last_hash := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Store.skip_overrides = true
	# Libraries made before this node (none today) still hold overrides: reload them without.
	if PostureLibrary._singleton != null: PostureLibrary._singleton.load_or_default()
	if BasePoseLibrary._singleton != null: BasePoseLibrary._singleton.load_or_default()
	var err := _server.listen(port, "127.0.0.1")
	if err != OK: push_error("PoseStudioLink: cannot listen on 127.0.0.1:%d (%s)" % [port, error_string(err)]); return
	print("[PoseStudioLink] listening on 127.0.0.1:%d" % port)
	_setup.call_deferred()

func _exit_tree() -> void:
	if _peer: _peer.disconnect_from_host()
	_server.stop()

func _setup() -> void:
	var game: Node = null
	for i in 1200:
		await _frames(1)
		game = get_tree().current_scene
		if game and game.has_method("open_mobile_pose_editor") and game.get("player_left"): break
	if game == null or not game.has_method("open_mobile_pose_editor"):
		push_error("PoseStudioLink: game scene not found (launch res://scenes/game.tscn)"); return
	await _frames(30)
	if await _boot_studio(game): return
	game.open_mobile_pose_editor()
	await _frames(20)
	var ed = game.mobile_pose_editor
	for z in 3: ed._preview.zoom(0.3)  # same framing as pose_shots: both feet in frame
	_ed = ed
	print("[PoseStudioLink] editor ready (link only, no studio)")

# Start the Desktop Pose Studio (if its script exists) and adopt its engine. False = fall
# back to the link opening the mobile editor itself.
func _boot_studio(game: Node) -> bool:
	var existing := get_tree().get_first_node_in_group("pose_studio")
	var studio: Node = existing
	if studio == null:
		if not ResourceLoader.exists(STUDIO_SCRIPT): return false
		var scr = load(STUDIO_SCRIPT)
		if scr == null or not scr.can_instantiate():
			push_error("PoseStudioLink: %s does not load; link-only mode" % STUDIO_SCRIPT); return false
		_set_window_mode()
		studio = scr.new()
		studio.name = "PoseStudio"
		game.add_child(studio)
	for i in 1200:   # up to ~20 s for the studio to open its engine
		if not is_instance_valid(studio): break
		var eng = studio.get("engine")
		var ready_flag = studio.get("is_ready")   # studio sets it after adopting the engine
		if eng != null and is_instance_valid(eng) and eng.get("_preview") != null and ready_flag != false: break
		await _frames(1)
	if not is_instance_valid(studio) or studio.get("engine") == null:
		push_error("PoseStudioLink: studio did not create its engine; link-only mode")
		if is_instance_valid(studio) and existing == null: studio.queue_free()
		await _frames(2)
		return false
	_studio = studio
	_ed = studio.engine
	print("[PoseStudioLink] studio ready")
	return true

# --studio-window=max (default; safer on macOS) | full | none
func _set_window_mode() -> void:
	if DisplayServer.get_name() == "headless": return
	var mode := "max"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--studio-window="): mode = a.trim_prefix("--studio-window=")
	match mode:
		"full": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"none": pass
		_: maximize_window()

## Fill the usable rect of the window's screen (no menu bar / Dock), then ask the OS to
## maximize (macOS zoom). The project's 540 x 960 phone window is never left behind: the size
## is set explicitly first, and checked again once the studio has laid out (_check_maximized).
## Window size / position / mode in pixels and the screen's usable rect (ping reply).
func _window_info() -> Dictionary:
	if DisplayServer.get_name() == "headless": return {}
	var u := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var sz := DisplayServer.window_get_size(); var d := DisplayServer.window_get_size_with_decorations()
	var p := DisplayServer.window_get_position()
	return {"size": [sz.x, sz.y], "size_with_decorations": [d.x, d.y], "position": [p.x, p.y], "mode": DisplayServer.window_get_mode(),
		"usable": [u.position.x, u.position.y, u.size.x, u.size.y], "scale": DisplayServer.screen_get_scale(), "boot": window_report}

func maximize_window() -> void:
	if DisplayServer.get_name() == "headless": return
	var scr := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(scr)
	if usable.size.x < 2 or usable.size.y < 2: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED); return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_position(usable.position)
	DisplayServer.window_set_size(usable.size)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	_check_maximized.call_deferred(usable)

func _check_maximized(usable: Rect2i) -> void:
	await _frames(20)
	var got := DisplayServer.window_get_size_with_decorations()
	# macOS may refuse the zoom while the window is still appearing: size it to the rect.
	if got.x < usable.size.x - 40 or got.y < usable.size.y - 80:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_position(usable.position)
		DisplayServer.window_set_size(usable.size)
	window_report = {"usable": [usable.position.x, usable.position.y, usable.size.x, usable.size.y],
		"size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y], "corrected": got.x < usable.size.x - 40 or got.y < usable.size.y - 80}

func _has_studio() -> bool: return _studio != null and is_instance_valid(_studio)

# Current pose key: the studio's selection (UI or link), else the link's own.
func _key() -> String:
	if _has_studio():
		var k = _studio.get("key")
		return str(k) if k != null else ""
	return _sel

func _need_studio() -> Dictionary:
	return {} if _has_studio() else _err("studio not running (link-only mode)")

# Studio methods may be coroutines: await works for both.
# A studio reply that means failure: {ok: false} or a bare false.
func _failed(r) -> bool: return (r is bool and not r) or (r is Dictionary and r.get("ok", true) == false)

func _as_err(r, fallback: String) -> Dictionary: return r if r is Dictionary else _err(fallback)

func _studio_call(method: String, args: Array = []):
	if not _studio.has_method(method): return _err("studio has no " + method + "()")
	return await _studio.callv(method, args)

# ---------------------------------------------------------------- transport

func _process(_delta: float) -> void:
	# Claude drives the link while the user may be in another app: undo the focus pause
	# (5 fps throttle + stopped playback) that PauseController applies.
	if PauseController._focus_paused: PauseController._on_window_focus_entered()
	if _has_studio() and _studio.engine != _ed and is_instance_valid(_studio.engine): _ed = _studio.engine
	if _ed != null and is_instance_valid(_ed):
		var pv = _ed._preview
		pv.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		if not _contact_on and pv.contact_preview and pv.contact_preview.visible: pv.contact_preview.visible = false
		if _loop and not _ed._playing and not _busy:
			if _ed._variant_mode != 0: _ed._play_variant(_ed._variant_mode)
			else: _ed._toggle_play()
	_poll()

func _poll() -> void:
	if not _server.is_listening(): return
	while _server.is_connection_available():
		var c := _server.take_connection()
		if _peer and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			c.put_data((JSON.stringify({"ok": false, "error": "busy: one client at a time"}) + "\n").to_utf8_buffer())
			c.disconnect_from_host()
		else:
			_peer = c; _peer.set_no_delay(true); _buf.clear(); _queue.clear()
	if _peer == null: return
	_peer.poll()
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTING: _peer = null
		return
	var n := _peer.get_available_bytes()
	if n > 0:
		var got: Array = _peer.get_partial_data(n)
		if got[0] == OK: _buf.append_array(got[1])
	while true:
		var nl := _buf.find(10)
		if nl < 0: break
		var line := _buf.slice(0, nl).get_string_from_utf8().strip_edges()
		_buf = _buf.slice(nl + 1)
		if line != "": _queue.append(line)
	if _buf.size() > MAX_LINE: _buf.clear(); _send({"ok": false, "error": "line too long"})
	if not _busy and not _queue.is_empty(): _drain()

func _drain() -> void:
	_busy = true
	while not _queue.is_empty():
		var line: String = _queue.pop_front()
		var req = JSON.parse_string(line)
		var id = null
		var reply: Dictionary
		if not (req is Dictionary):
			# Not a JSON-lines client (e.g. a web page POSTing to 127.0.0.1): reply once and drop
			# the connection with everything queued behind it, so no later line is run.
			_send({"id": null, "ok": false, "error": "bad JSON: connection closed"})
			_queue.clear(); _buf.clear()
			if _peer: _peer.disconnect_from_host()
			_peer = null
			break
		else:
			id = req.get("id")
			if id is float and id == floorf(id): id = int(id)
			reply = await _dispatch(req)
		var out := {"id": id}
		out.merge(_json(reply))
		_send(out)
	_busy = false

func _send(d: Dictionary) -> void:
	if _peer and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_peer.put_data((JSON.stringify(d) + "\n").to_utf8_buffer())

func _dispatch(req: Dictionary) -> Dictionary:
	var cmd := str(req.get("cmd", ""))
	if cmd == "ping": return {"ok": true, "version": VERSION, "ready": _ed != null, "window": _window_info()}
	while _ed == null or not is_instance_valid(_ed): await _frames(1)
	if not (cmd in KEEPS_LOOP): _loop = false
	var fn := "_c_" + cmd
	if cmd == "" or not has_method(fn): return {"ok": false, "error": "unknown cmd: " + cmd}
	# UI input from the link (Claude's channel) must not rate or verify as the user: the
	# rating panel and note Verify refuse while this is set (PROTOCOL.md section 1).
	var drives: bool = cmd in ["ui_action", "key", "mouse"] and _has_studio() and "link_driving" in _studio
	if drives: _studio.link_driving = true
	var r = await call(fn, req)
	if drives and _has_studio(): _studio.link_driving = false
	if r == null: return _err(cmd + " failed (script error, see the Godot log)")
	if r is Dictionary and not r.has("ok"): r["ok"] = true
	return r

# Vector3 -> [x, y, z]; non-finite floats -> null so the line stays valid JSON.
func _json(v):
	if v is Vector3: return [_f(v.x), _f(v.y), _f(v.z)]
	if v is Vector2: return [_f(v.x), _f(v.y)]
	if v is float: return _f(v)
	if v is Dictionary:
		var o := {}
		for k in v: o[str(k)] = _json(v[k])
		return o
	if v is Array or v is PackedFloat32Array or v is PackedFloat64Array or v is PackedInt32Array or v is PackedStringArray:
		var a := []
		for x in v: a.append(_json(x))
		return a
	if v is StringName or v is NodePath: return str(v)
	return v

func _f(x: float): return x if is_finite(x) else null

# ---------------------------------------------------------------- helpers

func _err(t: String) -> Dictionary: return {"ok": false, "error": t}

func _stage_name(i: int) -> String: return STAGES[clampi(i, 0, 2)]

func _key_of(def: Resource) -> String: return PoseDiff.key_of(def)

func _copy_key(key: String) -> String: return PoseDiff.copy_key(key)

func _live_def(key: String) -> Resource: return PoseDiff.live_def(key)

func _is_timing(field: String) -> bool:
	for d in Fields.fields(5, _ed._base):
		if d.field == field: return true
	return false

func _descriptor(field: String) -> Dictionary:
	for g in 6:
		for d in Fields.fields(g, _ed._base):
			if d.field == field: return d
	return {}

# Value of a field at a stage: endpoints resolve the keyframe dict + charge/ft deltas.
func _at(def: Resource, stage: int, field: String, cache: Dictionary):
	if def == null: return null
	if def is BasePoseDefinition or stage == 1 or _is_timing(field): return def.get(field)
	if not cache.has(stage): cache[stage] = Path.endpoint(def, stage)
	return cache[stage].get(field)

func _reselect(stage: int) -> void:
	var idx := -1
	for i in _ed._definitions.size():
		if _key_of(_ed._definitions[i]) == _key(): idx = i
	if idx < 0: return
	_ed._select_pose(idx)
	if stage != 1 and _ed._has_motion(): _ed._select_stage(stage)

# ---------------------------------------------------------------- commands

func _c_poses(_r) -> Dictionary:
	var list: Array = []
	for d in PostureLibrary.instance().all_definitions():
		list.append({"key": _key_of(d), "name": String(d.display_name), "kind": "stroke",
			"file": d.resource_path.trim_prefix("res://"), "family": int(d.family), "dirty": _ed._dirty.has(_copy_key(_key_of(d)))})
	for d in BasePoseLibrary.instance().all_definitions():
		list.append({"key": _key_of(d), "name": String(d.display_name), "kind": "base",
			"file": d.resource_path.trim_prefix("res://"), "family": null, "dirty": _ed._dirty.has(_copy_key(_key_of(d)))})
	list.sort_custom(func(a, b): return a.key < b.key)
	return {"poses": list}

func _c_select(r: Dictionary) -> Dictionary:
	var key := str(r.get("key", ""))
	var live := _live_def(key)
	if live == null: return _err("unknown pose key: " + key)
	if _has_studio():
		var r2 = await _studio_call("select_pose", [key])
		if _failed(r2): return _as_err(r2, "select failed for " + key)
		if _key() != key or _ed._key != _copy_key(key): return _err("select failed for " + key)
		await _frames(2)
		return {"key": key, "stage": _stage_name(_ed._stage),
			"stages": ["windup", "contact", "finish"] if _ed._has_motion() else ["contact"]}
	var ws := 1 if key.begins_with("b") else 2 if PoseDiff.is_serve_key(key) else 0
	if _ed._serve != (ws == 2) or _ed._base != (ws == 1): _ed._select_workspace(ws)
	_sel = key
	_ed._group.select(6)
	_reselect(1)
	if _ed._key != _copy_key(key): return _err("select failed for " + key)
	await _frames(2)
	return {"key": key, "stage": _stage_name(_ed._stage),
		"stages": ["windup", "contact", "finish"] if _ed._has_motion() else ["contact"]}

func _c_stage(r: Dictionary) -> Dictionary:
	if _key() == "": return _err("no pose selected")
	var s = r.get("stage", 1)
	var i: int = STAGES.find(s) if s is String else int(s)
	if i < 0 or i > 2: return _err("bad stage: " + str(s))
	if _has_studio(): await _studio_call("set_stage", [i])
	else: _ed._select_stage(i)
	await _frames(2)
	return {"stage": _stage_name(_ed._stage)}

func _c_fields(_r) -> Dictionary:
	if _key() == "": return _err("no pose selected")
	var cur: Resource = _ed._current
	var disk: Resource = PoseDiff.load_disk(_key())
	var wc := {}
	var dc := {}
	var motion: bool = _ed._has_motion()
	var groups: Array = []
	for ci in Fields.CATEGORIES.size():
		var rows: Array = []
		for d in Fields.category_fields(ci, _ed._base):
			var field: String = d.field
			var timing := ci == 8
			var target: Resource = cur if timing else _ed._edit
			if target.get(field) == null: continue
			var row := {"field": field, "label": d.label, "type": d.type,
				"wrapped": field in Fields.WRAPPED_BODY_FIELDS}
			if d.type == "option":
				row.merge({"min": 0, "max": d.items.size() - 1, "step": 1, "items": d.items})
			else:
				row.merge({"min": d.min, "max": d.max, "step": d.step})
			row["value"] = target.get(field)
			row["saved"] = _at(disk, _ed._stage, field, dc)
			var keys := {}
			for st in 3:
				keys[STAGES[st]] = _at(cur, st, field, wc) if (motion or st == 1) else null
			row["keys"] = keys
			rows.append(row)
		if not rows.is_empty(): groups.append({"name": Fields.CATEGORIES[ci], "fields": rows})
	return {"stage": _stage_name(_ed._stage), "groups": groups}

func _c_set(r: Dictionary) -> Dictionary:
	if _key() == "": return _err("no pose selected")
	var field := str(r.get("field", ""))
	var d := _descriptor(field)
	if d.is_empty(): return _err("unknown field: " + field)
	var timing := _is_timing(field)
	var target: Resource = _ed._current if timing else _ed._edit
	if target.get(field) == null: return _err("field not on this pose: " + field)
	var axis: int = -1 if r.get("axis") == null else int(r.get("axis"))
	var raw = r.get("value")
	if d.type == "vector" and (axis < 0 or axis > 2): return _err("vector field needs axis 0..2")
	if d.type != "vector": axis = -1
	var clamped := false
	var value
	var current
	if d.type == "option":
		var n := clampi(int(raw), 0, d.items.size() - 1)
		clamped = float(n) != float(raw)
		value = n
		current = int(target.get(field))
	else:
		if not (raw is float or raw is int): return _err("value must be a number")
		var v: float = Fields.body_input_value(d, float(raw))
		if not is_finite(v): return _err("value must be finite")
		clamped = not is_equal_approx(v, float(raw))
		value = v
		current = float(target.get(field)) if axis < 0 else float(target.get(field)[axis])
	if field in _ed.FOOT_GUARDED_FIELDS and not is_equal_approx(float(value), float(current)):
		var reason: String = _ed._body_edit_limit(d, axis, float(value))
		if reason != "":
			await _frames(1)
			return {"value": current, "clamped": clamped, "stopped": {"reason": reason, "at": current}}
	# Gameplay rule: the link may still set it (Claude follows the rule itself) but is told.
	var warning = null
	if _has_studio() and _studio.has_method("gameplay_locked"):
		var was: bool = _studio.gameplay_edit
		_studio.gameplay_edit = false
		if _studio.gameplay_locked(field): warning = "gameplay field at %s: %s changes how shots play" % [_stage_name(_ed._stage), field]
		_studio.gameplay_edit = was
	if _has_studio():
		var sr = await _studio_call("set_field", [field, axis, value, true])
		if _failed(sr): return _as_err(sr, "set failed")
		if sr is Dictionary and sr.get("stopped") != null:
			return {"value": current, "clamped": clamped, "stopped": sr["stopped"], "warning": warning}
	else:
		var prev_group: int = _ed._group.selected
		_ed._group.select(5 if timing else 6)
		if axis < 0: _ed._changed(field, value)
		else:
			var vec: Vector3 = target.get(field); vec[axis] = value; _ed._changed(field, vec)
		_ed._group.select(prev_group)
	await _frames(1)
	target = _ed._current if timing else _ed._edit  # the studio may swap the working copy
	var now = target.get(field)
	return {"value": now if axis < 0 else now[axis], "clamped": clamped, "stopped": null, "warning": warning}

# A viewport drag never outlives a play / scrub / seek / step (studio.stop_drag).
func _stop_drag() -> void:
	if _has_studio() and _studio.has_method("stop_drag"): _studio.stop_drag()

func _c_scrub(r: Dictionary) -> Dictionary:
	if _key() == "": return _err("no pose selected")
	_stop_drag()
	_ed._scrubbed(clampf(float(r.get("progress", 0.5)), 0.0, 1.0))
	await _frames(1)
	return {"progress": _ed._progress}

func _seq_ok() -> bool:
	return _key() != "" and _ed._timeline._configure()

func _c_seek(r: Dictionary) -> Dictionary:
	if not _seq_ok(): return _err("no timeline for this pose")
	var tl = _ed._timeline
	_stop_drag()
	tl._seek(clampf(float(r.get("t", 0.0)), 0.0, 1.0))
	await _frames(1)
	return _tl_state()

func _tl_state() -> Dictionary:
	var tl = _ed._timeline
	return {"t": tl.elapsed / maxf(tl.sequence.duration, 0.001), "seconds": tl.elapsed,
		"phase": String(tl.sample.get("phase", "")), "progress": _ed._progress}

func _c_timeline(_r) -> Dictionary:
	if not _seq_ok(): return _err("no timeline for this pose")
	var s = _ed._timeline.sequence
	return {"duration": s.duration, "prefix_seconds": s.prefix_seconds, "release_seconds": s.release_seconds,
		"stroke_seconds": s.stroke_seconds, "tick": TICK}

func _c_step(r: Dictionary) -> Dictionary:
	if not _seq_ok(): return _err("no timeline for this pose")
	var tl = _ed._timeline
	_stop_drag()
	var dur: float = maxf(tl.sequence.duration, 0.001)
	var from: float = tl.elapsed if tl.active else 0.0
	var tick_i := roundi(from / TICK) + (1 if int(r.get("dir", 1)) >= 0 else -1)
	tl._seek(clampf(tick_i * TICK, 0.0, dur) / dur)
	await _frames(1)
	return _tl_state()

func _c_play(r: Dictionary) -> Dictionary:
	if _key() == "" or not _ed._has_motion(): return _err("pose has no motion")
	_stop_drag()
	var sp := float(r.get("speed", 1.0))
	_ed._timeline.speed = sp if sp in [1.0, 0.5, 0.25] else 1.0
	_loop = bool(r.get("loop", false))
	if not _ed._playing:
		if _ed._variant_mode != 0: _ed._play_variant(_ed._variant_mode)
		else: _ed._toggle_play()
	return {"playing": _ed._playing}

func _c_stop(_r) -> Dictionary:
	_loop = false
	_ed._stop()
	return {"playing": _ed._playing}

func _c_variant(r: Dictionary) -> Dictionary:
	if _key() == "" or not _ed._has_motion(): return _err("pose has no motion")
	var m := clampi(int(r.get("variant", 0)), 0, 2)
	_stop_drag()
	if m == 0:
		_ed._clear_variant(); _ed._stop(); _ed._refresh_preview()
	else:
		_ed._play_variant(m)
	await _frames(1)
	return {"variant": _ed._variant_mode, "playing": _ed._playing}

func _c_view(r: Dictionary) -> Dictionary:
	var pv = _ed._preview
	if r.has("name"):
		var n := str(r["name"])
		if not (n in ["front", "side", "back", "reset"]): return _err("bad view: " + n)
		pv.view(n)
	else:
		if r.has("yaw"): pv.yaw = float(r["yaw"])
		if r.has("pitch"): pv.pitch = clampf(float(r["pitch"]), -1.5, 1.5)
		if r.has("distance"):
			pv.distance = clampf(float(r["distance"]), 1.4, 7.0); pv._manual_zoom = true
			if _studio != null and _studio._view_input != null: _studio._view_input.auto_fit = false
		pv.update_camera()
	await _frames(1)
	return {"yaw": pv.yaw, "pitch": pv.pitch, "distance": pv.distance if pv._manual_zoom else maxf(pv.distance, pv._fitted_distance)}

func _c_toggle(r: Dictionary) -> Dictionary:
	var what := str(r.get("what", ""))
	var on := bool(r.get("on", true))
	var pv = _ed._preview
	if _has_studio() and what.begins_with("autopose"):   # AutoPose mode and bar (Stage 6b)
		match what:
			"autopose": _studio.set_autopose_mode(on)
			"autopose_balance": _studio.set_autopose_balance(on)
			"autopose_look": _studio.set_autopose_look(on)
			"autopose_regions": _studio.set_autopose_regions_shown(on)
			"autopose_pin":
				var pr: Dictionary = _studio.set_autopose_pin(str(r.get("handle", "")), r.get("on"))
				pr["what"] = what
				pr["config"] = _studio.autopose_config()
				return _json(pr)
			_: return _err("bad toggle: " + what)
		return _json({"what": what, "on": on, "config": _studio.autopose_config()})
	if _has_studio() and what in ["ghosts", "arc", "contact"]:   # keep the studio toolbar in sync
		if what == "ghosts" and r.get("count") != null: _studio.set_ghost_count(int(r["count"]))
		_studio.set_overlay(what, on)
		return {"what": what, "on": on}
	match what:
		"ghosts":
			pv.set_ghosts_visible(on)
			if r.get("count") != null:
				pv.set_inbetween_count(int(r["count"]))  # not _ghost_count_changed: that writes user:// view settings
				_ed._ghost_slider.set_value_no_signal(pv.inbetween_count); _ed._update_ghost_label()
		"arc": pv.set_arc_visible(on)
		"contact":
			_contact_on = on
			if pv.contact_preview: pv.contact_preview.visible = on and pv._contact_enabled
		_: return _err("bad toggle: " + what)
	return {"what": what, "on": on}

func _c_metrics(r: Dictionary) -> Dictionary:
	if _key() == "": return _err("no pose selected")
	await _frames(int(r.get("settle", 12)))
	return {"stage": _stage_name(_ed._stage), "metrics": _body_metrics(_ed._preview.player)}

func _c_diff(_r) -> Dictionary:
	if _key() == "": return _err("no pose selected")
	var key := _key()
	var disk: Resource = PoseDiff.load_disk(key)
	if disk == null: return _err("cannot load file for " + key)
	return {"key": key, "file": PoseDiff.file_of(key), "changes": PoseDiff.diff(_ed._current, disk, _ed._base)}

func _c_revert(_r) -> Dictionary:
	if _key() == "": return _err("no pose selected")
	if _has_studio(): await _studio_call("revert")
	else:
		var st: int = _ed._stage
		_ed._copies.erase(_ed._key); _ed._dirty.erase(_ed._key)
		_reselect(st)
	await _frames(2)
	return {"key": _key(), "stage": _stage_name(_ed._stage)}

# Copy the file on disk into the live library resource (same identity the game holds),
# then drop the working copy. Call it after a CLI (tools/pose_notes.py / pose_set.py) wrote the .tres.
func _c_reload(r: Dictionary) -> Dictionary:
	var key := str(r.get("key", _key()))
	var live := _live_def(key)
	if live == null: return _err("unknown pose key: " + key)
	if _has_studio():
		var rr = await _studio_call("reload", [key])
		if _failed(rr): return _as_err(rr, "cannot reload " + key)
		await _frames(2)
		return {"key": key}
	if not PoseDiff.reload_live(key): return _err("cannot load " + live.resource_path)
	_ed._copies.erase(_copy_key(key)); _ed._dirty.erase(_copy_key(key))
	if key == _sel: _reselect(_ed._stage)
	await _frames(2)
	return {"key": key}

func _c_frame(r: Dictionary) -> Dictionary:
	var vp: SubViewport = _ed._preview.viewport
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await RenderingServer.frame_post_draw
	var tex := vp.get_texture()
	var img: Image = tex.get_image() if tex else null
	if img == null or img.is_empty(): return _err("no frame (headless run renders nothing)")
	var h: int = hash(img.get_data())
	if h != _last_hash: _seq += 1; _last_hash = h
	var w := int(r.get("w", 0)) if r.get("w") != null else 0
	var hh := int(r.get("h", 0)) if r.get("h") != null else 0
	if w > 0 and hh > 0 and (w != img.get_width() or hh != img.get_height()):
		img.resize(clampi(w, 16, 2048), clampi(hh, 16, 2048), Image.INTERPOLATE_BILINEAR)
	var jpg := img.save_jpg_to_buffer(0.85)
	return {"jpeg_b64": Marshalls.raw_to_base64(jpg), "w": img.get_width(), "h": img.get_height(), "seq": _seq}

func _c_nodes(_r) -> Dictionary:
	var p = _ed._preview.player
	var parent: Node = p.get_parent()
	return {"pixel_cards": parent.get_node_or_null("PixelCards_%d" % p.get_instance_id()) != null,
		"player": str(p.get_path())}

# ---------------------------------------------------------------- studio commands

func _c_ui(_r) -> Dictionary:
	var e := _need_studio()
	if not e.is_empty(): return e
	var tree = await _studio_call("ui_dump")
	if tree is Dictionary and tree.get("ok", true) == false: return tree
	return {"key": _key(), "stage": _stage_name(_ed._stage), "tree": tree}

func _c_ui_action(r: Dictionary) -> Dictionary:
	var e := _need_studio()
	if not e.is_empty(): return e
	var res = await _studio_call("ui_action", [str(r.get("name", "")), str(r.get("action", "press")), r.get("value")])
	await _frames(2)
	if res is Dictionary: return res
	return {"result": res}

## Objective layout audit of the studio UI (scripts/studio/studio_layout_audit.gd); `settle`
## frames (default 4) let a resize / tab switch finish its layout first.
func _c_ui_audit(r: Dictionary) -> Dictionary:
	var e := _need_studio()
	if not e.is_empty(): return e
	await _frames(clampi(int(r.get("settle", 4)), 0, 120))
	var res: Dictionary = LayoutAudit.run(_studio)
	res["key"] = _key(); res["stage"] = _stage_name(_ed._stage)
	return res

## Windowed, w x h in screen points (window pixels / screen scale). Replies the size the OS
## gave (`clamped` when it is smaller, e.g. bigger than the screen) and the studio canvas size.
## `emulate: true` leaves the window and lays the studio out as a w x h point window would
## (same desktop scale rule, canvas stretched to the window): for sizes bigger than the screen.
## `emulate: false` (or a plain call) ends emulation.
func _c_window(r: Dictionary) -> Dictionary:
	if DisplayServer.get_name() == "headless": return _err("no window (headless)")
	var w := int(r.get("w", 0)); var h := int(r.get("h", 0))
	if w < 320 or h < 240 or w > 8192 or h > 8192: return _err("w, h in points: 320..8192 x 240..8192")
	var s := DisplayServer.screen_get_scale()
	var emu := bool(r.get("emulate", false))
	if _has_studio() and "layout_override" in _studio:
		var ov := Vector2i.ZERO
		if emu:   # pose_studio._apply_desktop_scale for a w*s x h*s pixel window
			var ui := maxf(maxf(s, h * s / 1400.0), 1.0)
			ov = Vector2i(roundi(w * s / ui), roundi(h * s / ui))
		if _studio.layout_override != ov or not emu:
			_studio.layout_override = ov
			if not emu: get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
			_studio._apply_desktop_scale()
		if emu:
			await _frames(10)
			var u := get_viewport().get_visible_rect().size
			return {"emulated": true, "w": w, "h": h, "ui": [u.x, u.y], "screen_scale": s}
	elif emu: return _err("emulate needs the studio")
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		await _frames(10)
	var want := Vector2i(roundi(w * s), roundi(h * s))
	DisplayServer.window_set_size(want)
	await _frames(10)
	var got := DisplayServer.window_get_size()
	var ui := get_viewport().get_visible_rect().size
	var screen := DisplayServer.screen_get_usable_rect()
	return {"w": got.x / s, "h": got.y / s, "px": [got.x, got.y], "screen_scale": s, "clamped": got != want,
		"ui": [ui.x, ui.y], "screen_usable_points": [screen.size.x / s, screen.size.y / s],
		"min_points": [DisplayServer.window_get_min_size().x / s, DisplayServer.window_get_min_size().y / s]}

func _c_undo(_r) -> Dictionary: return await _history("undo")

func _c_redo(_r) -> Dictionary: return await _history("redo")

func _history(method: String) -> Dictionary:
	var e := _need_studio()
	if not e.is_empty(): return e
	var res = await _studio_call(method)
	if res is Dictionary and res.get("ok", true) == false: return res
	await _frames(1)
	if res is bool and not res: return {"key": _key(), "stage": _stage_name(_ed._stage), "applied": false}
	var out := {"key": _key(), "stage": _stage_name(_ed._stage)}
	if res is Dictionary: out.merge(res)
	elif res is bool: out["applied"] = res
	return out

# studio.save runs tools/pose_notes.py save (minimal .tres text edits + a version), then reloads.
func _c_save(r: Dictionary) -> Dictionary:
	var e := _need_studio()
	if not e.is_empty(): return e
	if _key() == "": return _err("no pose selected")
	var res = await _studio_call("save", [str(r.get("message", "")), "claude"])   # versions credit Claude
	await _frames(2)
	if res is Dictionary: return res
	return _err("studio.save returned " + type_string(typeof(res)))

# ---------------------------------------------------------------- input (tests by data)
# Real input through the root window (push_input: GUI routing, focus, _input), so key and mouse
# tests hit the same code paths a user does. Debug link only.

# key {key: "Space"|"Comma"|"Z"|"S"|"Question"..., mods: ["cmd", "shift", "alt"]} -> press + release
func _c_key(r: Dictionary) -> Dictionary:
	var e := _need_studio()
	if not e.is_empty(): return e
	var kname := str(r.get("key", ""))
	var code := OS.find_keycode_from_string(kname)
	if code == KEY_NONE: return _err("unknown key: " + kname)
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code; ev.physical_keycode = code; ev.pressed = pressed
		var mods: Array = r.get("mods", [])
		ev.shift_pressed = "shift" in mods; ev.alt_pressed = "alt" in mods
		if "ctrl" in mods: ev.ctrl_pressed = true
		if "cmd" in mods:
			if OS.get_name() == "macOS": ev.meta_pressed = true
			else: ev.ctrl_pressed = true
		var ch := OS.get_keycode_string(code)
		if kname == "Question": ev.unicode = 63
		elif ch.length() == 1 and not ev.meta_pressed and not ev.ctrl_pressed: ev.unicode = (ch if ev.shift_pressed else ch.to_lower()).unicode_at(0)
		get_tree().root.push_input(ev)
		await _frames(2)
	return {"key": _key(), "stage": _stage_name(_ed._stage), "keycode": code}

# mouse {events: [{type: down|up|move|wheel|pan|magnify, x, y, button: 1 left|2 right|3 middle,
# shift, ctrl, cmd, alt; wheel: dir up|down, factor; pan: dx, dy (InputEventPanGesture delta,
# a trackpad two-finger scroll); magnify: factor (pinch)}]}, x/y in
# preview-local pixels (the space gizmo / joint_screen_position use), or relative to the named
# studio control `target` (a Tree row centre with `item`). One frame per event.
const LINK_DEVICE := 77   # = studio_viewport.gd LINK_DEVICE
func _c_mouse(r: Dictionary) -> Dictionary:
	var e := _need_studio()
	if not e.is_empty(): return e
	var pv: Control = _ed._preview
	var base: Control = pv
	var at := Vector2.ZERO
	if str(r.get("target", "")) != "":   # a named studio control instead of the preview
		base = _studio._root.find_child(str(r.target), true, false) as Control
		if base == null: return _err("no control named " + str(r.target))
		if base is Tree and r.has("item"):   # centre of the row whose metadata is `item`
			var row: TreeItem = null
			for it in base.get_root().get_children():
				if str(it.get_metadata(0)) == str(r.item): row = it
			if row == null: return _err("no row " + str(r.item))
			base.scroll_to_item(row)
			await _frames(1)
			at = base.get_item_area_rect(row, 0).get_center()
	elif str(r.get("handle", "")) != "":   # x / y relative to a handle (AutoPose handle in AutoPose mode, else joint dot / tip)
		if _studio._view_input == null: return _err("no viewport")
		at = _studio._view_input.handle_screen(str(r.handle))
		if not at.is_finite(): return _err("handle %s is not on screen" % str(r.handle))
	var events = r.get("events", [])
	if not (events is Array): return _err("events must be a list")
	for m in events:   # check every event before pushing any (a bad one would stop half way)
		if not (m is Dictionary): return _err("each event must be an object")
		for k in ["x", "y", "dx", "dy", "factor", "button"]:
			if m.has(k) and not (m[k] is float or m[k] is int): return _err("event %s must be a number (got %s)" % [k, type_string(typeof(m[k]))])
	var to_win: Transform2D = get_tree().root.get_final_transform() * base.get_global_transform_with_canvas()
	var last := Vector2.ZERO
	var held := 0
	for m in events:
		var local := at + Vector2(float(m.get("x", 0)), float(m.get("y", 0)))
		var pos: Vector2 = to_win * local
		var ev: InputEventMouse
		var kind := str(m.get("type", "move"))
		match kind:
			"down", "up":
				var b := InputEventMouseButton.new()
				b.button_index = int(m.get("button", 1)); b.pressed = kind == "down"
				held = (held | (1 << (b.button_index - 1))) if b.pressed else (held & ~(1 << (b.button_index - 1)))
				b.button_mask = held
				ev = b
			"wheel":   # one notch: press + release like a real wheel
				for pressed in [true, false]:
					var w := InputEventMouseButton.new()
					w.button_index = MOUSE_BUTTON_WHEEL_UP if str(m.get("dir", "up")) == "up" else MOUSE_BUTTON_WHEEL_DOWN
					w.pressed = pressed; w.factor = float(m.get("factor", 1.0)); w.button_mask = held
					w.position = pos; w.global_position = pos
					_mods(w, m)
					if pressed: get_tree().root.push_input(w)
					else: ev = w
			"pan":
				var g := InputEventPanGesture.new()
				g.delta = Vector2(float(m.get("dx", 0)), float(m.get("dy", 0)))
				g.position = pos
				_mods(g, m); last = pos
				get_tree().root.push_input(g)
				await _frames(1)
				continue
			"magnify":
				var g := InputEventMagnifyGesture.new()
				g.factor = float(m.get("factor", 1.0))
				g.position = pos
				_mods(g, m); last = pos
				get_tree().root.push_input(g)
				await _frames(1)
				continue
			_:
				var mm := InputEventMouseMotion.new()
				mm.relative = pos - last; mm.button_mask = held
				ev = mm
		ev.position = pos; ev.global_position = pos
		_mods(ev, m)
		last = pos
		get_tree().root.push_input(ev)
		await _frames(1)
	await _frames(2)
	var out := {"key": _key(), "stage": _stage_name(_ed._stage), "selected_joint": pv.selected_joint}
	if str(r.get("handle", "")) != "": out["handle_at"] = at
	if "autopose_on" in _studio and _studio.autopose_on: out["autopose"] = _json(_studio.last_autopose)
	return out

func _mods(ev: InputEventWithModifiers, m: Dictionary) -> void:
	ev.device = LINK_DEVICE   # the viewport ignores other (real OS) mouse events while the link drives it
	ev.alt_pressed = bool(m.get("alt", false)); ev.shift_pressed = bool(m.get("shift", false))
	ev.ctrl_pressed = bool(m.get("ctrl", false)); ev.meta_pressed = bool(m.get("cmd", false))

# quit -> {unsaved: [keys]}: like closing the window (quits now when nothing is unsaved, else
# the studio shows Save all / Discard / Cancel). tools/pose_studio.sh sends it on Ctrl+C.
func _c_quit(_r) -> Dictionary:
	var e := _need_studio()
	if not e.is_empty(): return e
	var keys = await _studio_call("request_quit")
	return {"unsaved": keys if keys is Array else []}

# aim_probe {x, y} -> studio.aim_probe: best paddle-tip error any pitch / yaw gives (roll, grip fixed). Test hook.
func _c_aim_probe(r: Dictionary) -> Dictionary:
	var e := _need_studio()
	if not e.is_empty(): return e
	return _studio.aim_probe(Vector2(float(r.get("x", 0)), float(r.get("y", 0))))

# autopose (Stage 6b prototype, scripts/studio/autopose_solver.gd): drag a handle to world points.
#   {handle, target: [x,y,z]}            one mouse move (starts a drag on a new handle / key)
#   {handle, path: [[x,y,z], ...]}        a fresh drag with one move per point: {begin, moves: [...]}
#   options: mode broyden|fd, scope full|arm, stiffness {region: x}, pins [{joint, point?}], budget_usec,
#            balance (default true: soft goal + centre of gravity never further off than max(5 cm, grab))
#   {release: true, commit: bool, backoff: bool}  end the drag (commit = one undo step through set_field; backoff = keep the largest stop-free fraction)
#   {probe: true, handle, samples}        evaluation cost, determinism, arm-path check, paddle / feet coupling
#   {config: {balance, look, stiffness: {all, arms, torso, legs}, reset_pins}}  set the studio's AutoPose bar -> {config}
#   {relax: true}                         the bar's Relax at this key (one undo step) -> solver report + release
#   drag options also: unpin [right_foot|left_foot|paddle], look_at [x,y,z] | look: true (studio's point),
#            studio: true (all options from the AutoPose bar: what a UI drag uses)
func _c_autopose(r: Dictionary) -> Dictionary:
	var e := _need_studio()
	if not e.is_empty(): return e
	var ap = _studio.autopose_solver()
	if r.get("config") is Dictionary:
		var cf: Dictionary = r.config
		if cf.has("balance"): _studio.set_autopose_balance(bool(cf.balance))
		if cf.has("look"): _studio.set_autopose_look(bool(cf.look))
		if cf.get("stiffness") is Dictionary:
			for k in cf.stiffness: _studio.set_autopose_stiffness(str(k), float(cf.stiffness[k]))
		if bool(cf.get("reset_pins", false)): _studio.reset_autopose_pins()
		return _json({"config": _studio.autopose_config()})
	if bool(r.get("relax", false)): return _json(_studio.autopose_relax())
	if bool(r.get("release", false)): return _json(ap.release(bool(r.get("commit", false)), bool(r.get("backoff", false))))
	var h := str(r.get("handle", ""))
	if bool(r.get("probe", false)): return _json(ap.probe(h, int(r.get("samples", 60))))
	var opts := {"mode": str(r.get("mode", "broyden")), "scope": str(r.get("scope", "full")),
		"stiffness": r.get("stiffness", {}), "pins": r.get("pins", []), "balance": bool(r.get("balance", true)),
		"unpin": r.get("unpin", []), "look_at": r.get("look_at")}
	if r.has("follow"): opts["follow"] = float(r.follow)
	if bool(r.get("look", false)): opts["look_at"] = _studio.autopose_look_point()
	if bool(r.get("studio", false)): opts.merge(_studio.autopose_options(), true)
	if not (opts.mode in ["broyden", "fd"]) or not (opts.scope in ["full", "arm"]): return _err("mode broyden|fd, scope full|arm")
	var pts: Array = []
	if r.has("path"):
		if not (r.path is Array): return _err("path must be a list of [x, y, z]")
		pts = r.path
	elif r.has("target"): pts = [r.target]
	else: return _err("autopose needs target, path, release or probe")
	var targets: Array[Vector3] = []
	for p in pts:
		if not (p is Array) or p.size() != 3 or not (p[0] is float or p[0] is int) or not (p[1] is float or p[1] is int) or not (p[2] is float or p[2] is int):
			return _err("each target must be [x, y, z] numbers")
		targets.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	var b = null
	if r.has("path") or not ap.active or ap.handle != h or ap.key != _key() or ap.stage != _ed._stage \
			or ap.mode != opts.mode or ap.scope != opts.scope or ap._balance_on != opts.balance:   # other options apply when a drag starts
		b = ap.begin(h, opts)
		if not b.get("ok", false): return _json(b)
	ap.budget_usec = maxi(0, int(r.get("budget_usec", 0)))   # per-move time cap (live drags); 0 = run to convergence
	var moves: Array = []
	for t in targets: moves.append(ap.move(t))
	if r.has("path"): return _json({"begin": b, "moves": moves})
	var out: Dictionary = moves[0]
	if b != null: out["begin"] = b
	return _json(out)

# autopose_handles -> AutoPose drag UI state: {on, dragging, handle, target, target_screen, handles: [{id, name, x, y,
# inside, world, locked, reason, hover}], last_drag: studio.last_autopose}. x / y in preview pixels (mouse coordinates).
## Elbow bake (stage 6c step 2): {correction: bool} sets PlayerArmIk.paddle_elbow_wrist_correction
## and refreshes; {swivel: deg} writes that elbow swivel (weight 1) at this key; always replies
## the solved elbow now, the correction state and the swivel that reproduces it (target).
func _c_elbow(r: Dictionary) -> Dictionary:
	if not _has_studio(): return _err("no studio")
	var ik = load("res://scripts/player_arm_ik.gd")
	if r.has("correction"):
		ik.paddle_elbow_wrist_correction = bool(r["correction"])
		_ed._refresh_preview()
	var out := {"correction": ik.paddle_elbow_wrist_correction}
	if r.has("swivel"): out["set"] = _studio.elbow_set_swivel(float(r["swivel"]))
	out["elbow"] = _studio.elbow_now()
	out["target"] = _studio.elbow_bake_target()
	return out

func _c_autopose_handles(_r) -> Dictionary:
	var e := _need_studio()
	if not e.is_empty(): return e
	if _studio._view_input == null: return _err("no viewport")
	var out: Dictionary = _studio._view_input.autopose_state()
	out["last_drag"] = _studio.last_autopose
	out["config"] = _studio.autopose_config()
	out["last_relax"] = _studio.last_relax
	out["at_key"] = _studio.at_key()
	return _json(out)

# gizmo -> {joints: {id: [x, y]}, selected_joint, enabled, mode, anchor, axes: [{axis, bound, grip, end, depth}]}
# in preview-local pixels; grip = a point on the move arrow (mode 0) or ring (mode 1) to start a drag.
func _c_gizmo(_r) -> Dictionary:
	var pv = _ed._preview
	var gz = pv.gizmo
	var projected: Array = []   # optional `project: [[x, y, z], ...]` world points -> preview points
	for w in (_r.get("project", []) if _r is Dictionary else []):
		projected.append(pv._world_screen_position(Vector3(float(w[0]), float(w[1]), float(w[2]))))
	var drag := {}              # an active Move-arrow drag: the gizmo's line parameter (metres) and axis
	if gz and gz._axis >= 0 and gz.mode == 0:
		drag = {"axis": gz._axis, "value": gz._drag_value, "origin0": gz._drag_origin, "dir": gz._drag_axis}
	var joints := {}
	for id in Fields.JOINT_IDS: joints[id] = pv.joint_screen_position(id)
	var axes: Array = []
	if gz and gz.enabled and gz.anchor().is_finite():
		gz.sync_scene()
		for a in 3:
			var bound: bool = not gz.bindings[a].is_empty()
			var row := {"axis": a, "bound": bound, "binding": gz.bindings[a]}
			if gz.mode == 0:
				var g: Dictionary = gz.axis_geometry(a)
				var start: Vector2 = pv._world_screen_position(gz.origin() + gz.world_axes[a].normalized() * gz._length * .25)
				row.merge({"grip": g.end if g.depth else start.lerp(g.end, 0.7), "end": g.end, "depth": g.depth, "direction": g.direction})
			else:
				row["grip"] = gz.ring_point(a, 0.0)
			axes.append(row)
	var world := {}   # world positions of every joint (metres) and the paddle tip
	for id in Fields.JOINT_IDS: world[id] = pv.joint_world_position(id)
	var extra := {}
	if _has_studio() and _studio._view_input:
		var tw: Vector3 = _studio._view_input.tip_world()
		extra = {"tip": {"world": tw, "screen": pv._world_screen_position(tw), "available": _studio.tip_available()},
			"last_aim": _studio.last_aim, "hand_slide": _studio.hand_slide, "drag_kind": _studio._view_input.drag_kind}
	return {"joints": joints, "selected_joint": pv.selected_joint, "enabled": gz.enabled if gz else false,
		"mode": gz.mode if gz else -1, "anchor": gz.anchor() if gz else Vector2.INF, "axes": axes,
		"world_axes": gz.world_axes if gz else [], "origin": gz.origin() if gz else Vector3.INF,
		"scene_visible": gz != null and is_instance_valid(gz.scene_root) and gz.scene_root.visible,
		"world": world, "projected": projected, "drag": drag, "progress": _ed._progress, "stage_index": _ed._stage,
		"preview_size": pv.size, "camera": [pv.camera.global_position, pv.camera.h_offset, pv.camera.v_offset]}.merged(extra)
