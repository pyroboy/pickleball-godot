extends Node
## Always-on performance monitor (autoload "PerfMonitor").
##
## - Hot functions call PerfMonitor.record("label", usec) via small timing wrappers.
## - Once per second writes one JSON line: fps, frame-time stats, per-system cost.
## - Any frame slower than SPIKE_MS writes a "spike" line naming what was slow.
## - F3 toggles an on-screen frame-time graph.
##
## --frame-log=path: one line per frame (state, player positions, every scope's
## ms and calls) to see what runs when nothing should; off by default.
##
## Output: logs/perf.jsonl when run from source on Mac, user://perf.jsonl in an
## exported build (iPhone). Summarise with: python3 tools/perf_report.py

const SPIKE_MS := 50.0          # ~3 dropped frames at 60 fps
var _capture_times: Array[float] = []
var _capture_dir := ""
var _capture_hide_ui := false
var _spike_ms: float = SPIKE_MS  # --spike-ms=N overrides (bench: SPIKE_MS=N tools/bench.sh)
const GRAPH_SAMPLES := 240      # ~4 s of history
const TOP_SCOPES := 6

static var _frame_costs: Dictionary = {}   # label -> [calls, total_usec, max_usec] this frame

static func record(label: String, usec: int) -> void:
	var v: Array = _frame_costs.get(label, [0, 0, 0])
	v[0] += 1
	v[1] += usec
	if usec > v[2]: v[2] = usec
	_frame_costs[label] = v

var _file: FileAccess
var _t0 := 0
var _last_usec := 0
var _sec_start := 0
var _sec_frames: PackedFloat32Array = []
var _sec_costs: Dictionary = {}           # label -> [total_usec, max_usec]
var _sec_spikes := 0
var _history: PackedFloat32Array = []
var _frames := 0
var _graph: Control
var _graph_layer: CanvasLayer
var _pose_path := ""
var _frame_file: FileAccess
var _pose_file: FileAccess
var _pose_nodes: Dictionary = {}   # player instance id -> Array[Node3D]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000000   # run after everything else in the frame
	var path := "user://perf.jsonl"
	if not OS.has_feature("template"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs"))
		path = "res://logs/perf.jsonl"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--perf-out="): path = arg.trim_prefix("--perf-out=")
		if arg.begins_with("--pose-trace="): _pose_path = arg.trim_prefix("--pose-trace=")
		if arg.begins_with("--frame-log="): _frame_file = FileAccess.open(arg.trim_prefix("--frame-log="), FileAccess.WRITE)
		# Headless benches: --resolution is ignored, so size the root window here
		# (portrait 720x1280 = the phone's camera framing path).
		if arg.begins_with("--viewport="):
			var wh := arg.trim_prefix("--viewport=").split("x")
			if wh.size() == 2: get_tree().root.size = Vector2i(int(wh[0]), int(wh[1]))
		if arg.begins_with("--spike-ms="): _spike_ms = float(arg.trim_prefix("--spike-ms="))
		# Dev screenshots: --capture-at=20,30,40 --capture-out=/dir (seconds since start)
		if arg.begins_with("--capture-at="):
			for t in arg.trim_prefix("--capture-at=").split(","): _capture_times.append(float(t))
		if arg.begins_with("--capture-out="): _capture_dir = arg.trim_prefix("--capture-out=")
		if arg == "--capture-hide-ui": _capture_hide_ui = true
		if arg.begins_with("--pose-shots="):
			var shots: Node = load("res://scripts/debug/pose_shots.gd").new()
			shots.out_dir = arg.trim_prefix("--pose-shots=")
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--pose-only="): shots.only = a.trim_prefix("--pose-only=").split(",")
			add_child(shots)
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _pose_path != "":
		_pose_file = FileAccess.open(_pose_path, FileAccess.WRITE)
		process_physics_priority = 1000000   # sample after all gameplay physics
	else:
		set_physics_process(false)
	_t0 = Time.get_ticks_usec()
	_last_usec = _t0
	_sec_start = _t0
	_write({"kind": "meta", "engine": Engine.get_version_info().string, "os": OS.get_name(),
		"model": OS.get_model_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"physics_hz": Engine.physics_ticks_per_second, "spike_ms": _spike_ms})
	_build_graph()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_usec) / 1000.0
	_frames += 1
	_last_usec = now

	var vp := get_viewport().get_viewport_rid()
	record("render.cpu", int(RenderingServer.viewport_get_measured_render_time_cpu(vp) * 1000.0))
	record("render.gpu", int(RenderingServer.viewport_get_measured_render_time_gpu(vp) * 1000.0))
	var costs := _frame_costs
	_frame_costs = {}
	for label in costs:
		var c: Array = costs[label]
		var s: Array = _sec_costs.get(label, [0, 0, 0])
		s[0] += c[1]
		s[1] = maxi(s[1], c[1])
		s[2] += c[0]
		_sec_costs[label] = s

	if _frame_file != null: _write_frame(now, frame_ms, costs)
	_motion_frame(now, frame_ms, delta)
	_sec_frames.append(frame_ms)
	_history.append(frame_ms)
	if _history.size() > GRAPH_SAMPLES: _history.remove_at(0)

	if not _capture_times.is_empty() and _capture_dir != "" and _t(now) >= _capture_times[0]:
		var shot_t: float = _capture_times.pop_front()
		if _capture_hide_ui:
			for layer in get_tree().root.find_children("*", "CanvasLayer", true, false): layer.visible = false
		get_viewport().get_texture().get_image().save_png(_capture_dir.path_join("frame_%03d.png" % int(shot_t)))
	if frame_ms >= _spike_ms and _frames > 30:
		_sec_spikes += 1
		_write({"kind": "spike", "t": _t(now), "ms": snappedf(frame_ms, 0.1), "state": _state(),
			"top": _top(costs, func(c): return c[1])})

	if now - _sec_start >= 1000000:
		_flush_second(now)

	if _graph_layer.visible: _graph.queue_redraw()

func _write_frame(now: int, frame_ms: float, costs: Dictionary) -> void:
	var scopes := {}
	for label in costs:
		var c: Array = costs[label]
		scopes[label] = [snappedf(c[1] / 1000.0, 0.001), c[0]]
	var row := {"f": _frames, "t": _t(now), "ms": snappedf(frame_ms, 0.01), "state": _state(), "scopes": scopes}
	if Engine.time_scale != 1.0: row["time_scale"] = snappedf(Engine.time_scale, 0.001)
	if get_tree().paused:
		row["paused"] = true
		var sc := get_tree().current_scene
		if sc != null and "contact_authority" in sc and sc.contact_authority != null and not sc.contact_authority.unresolved_continuation.is_empty():
			row["pause_reason"] = "contact_reset: " + str(sc.contact_authority.unresolved_continuation).left(400)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("get_players"):
		for p in scene.get_players(): row["p%d" % p.actor_id] = _v(p.global_position)
		# Motion (tools/motion_report.py): what is drawn this frame, i.e. the
		# interpolated transforms, plus each player's intended speed.
		var drawn := {}
		var cam := get_viewport().get_camera_3d()
		if cam != null: drawn["cam"] = _v(cam.get_global_transform_interpolated().origin)
		var ball = scene.get("ball")
		if ball is Node3D: drawn["ball"] = _v(ball.get_global_transform_interpolated().origin)
		for p in scene.get_players():
			drawn["p%d" % p.actor_id] = _v(p.get_global_transform_interpolated().origin)
			var want = p.get("current_velocity")
			if want is Vector3: drawn["v%d" % p.actor_id] = snappedf(Vector2(want.x, want.z).length(), 0.001)
		row["drawn"] = drawn
	if not _events.is_empty():
		row["ev"] = _events
		_events = []
	_frame_file.store_line(JSON.stringify(row, "", false))

# Gameplay notes from game code (one small row each, always on), e.g. each AI
# shot plan. Read by tools/shot_report.py.
func note(kind: String, data: Dictionary) -> void:
	data["tick"] = Engine.get_physics_frames()
	_write({"kind": "note", "note": kind, "t": _t(Time.get_ticks_usec()), "data": data})

# ---- events (frame log only): what happened, for the debugging timeline ----
var _events: Array = []
var _ev_state := ""
var _ev_scene: Node = null

func _event(kind: String, data: Dictionary = {}) -> void:
	data["kind"] = kind
	data["tick"] = Engine.get_physics_frames()
	# Point-level events also go to perf.jsonl on every run (a few per point), so
	# bench/phone reports can summarise gameplay; the frame log gets all of them.
	if kind in ["state", "rally_end", "post_hit", "body_hit", "hit"]:
		_write({"kind": "event", "event": kind, "t": _t(Time.get_ticks_usec()), "data": data})
	if _frame_file != null: _events.append(data)

func _hook_events(scene: Node) -> void:
	if scene == _ev_scene: return
	_ev_scene = scene
	var ball = scene.get("ball")
	if ball != null:
		ball.actor_hit_paddle.connect(func(a, team, _side): _event("hit", {"actor": a, "team": team, "pos": _v(ball.global_position), "vel": _v(ball.linear_velocity)}))
		ball.actor_hit_body.connect(func(a, team, _side): _event("body_hit", {"actor": a, "team": team, "pos": _v(ball.global_position)}))
		ball.bounced.connect(func(at): _event("bounce", {"pos": _v(at)}))
	var scorer = scene.get("rally_scorer")
	if scorer != null:
		scorer.rally_ended.connect(func(w, reason, detail): _event("rally_end", {"winner": w, "reason": reason, "detail": detail}))
		scorer.rally_pending.connect(func(w, reason, detail): _event("rally_pending", {"winner": w, "reason": reason, "detail": detail}))
	var serve = scene.get("game_serve")
	if serve != null:
		serve.serve_launched.connect(func(team): _event("serve", {"team": team, "pos": _v(ball.global_position) if ball != null else []}))
		serve.serve_phase_changed.connect(func(phase, _style): _event("serve_phase", {"phase": phase}))
	var between = scene.get("between_point_controller")
	if between != null: between.phase_changed.connect(func(phase): _event("between_phase", {"phase": phase}))
	var net = scene.get_node_or_null("Net")
	if net != null and net.has_signal("ball_hit_post"): net.ball_hit_post.connect(func(at): _event("post_hit", {"pos": _v(at)}))
	if scene.get("score_left") != null: _event("score", {"left": scene.score_left, "right": scene.score_right})

# ---- motion jitter (always on): counts per second + burst snapshots ----
# For every drawn object (camera, ball, players; interpolated = what is on
# screen) compare each frame's movement with its neighbours. Counted into the
# "jitter" field of each "sec" row as "<obj>:<kind>:<zone>:<state>"; zone is where a
# player is (behind = past the baseline). 3+ events for one object within
# 0.5 s writes a "jitter_burst" row with the last ~2 s of positions.
const JIT_MOVING := 0.3      # m/s: neighbours slower than this = standing
const JIT_STALL := 0.25
const JIT_POP := 3.0
const JIT_BUFFER := 120
var _sec_jitter: Dictionary = {}
var _sec_state_frames: Dictionary = {}   # state -> frames this second (exact jitter rates)
var _jit_prev: Array = []          # last 3 frames: {t, ms, state, pos: {obj: Vector3}}
var _jit_buffer: Array = []        # last JIT_BUFFER frames for burst snapshots
var _jit_recent: Dictionary = {}   # obj -> Array of event times (s)
var _jit_last_burst: Dictionary = {}   # obj -> time of its last snapshot

func _motion_frame(now: int, frame_ms: float, delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method("get_players"): return
	_hook_events(scene)
	var st := _state()
	if st != _ev_state:
		_event("state", {"from": _ev_state, "to": st})
		_ev_state = st
	if get_tree().paused: return
	var pos := {}
	var cam := get_viewport().get_camera_3d()
	if cam != null: pos["cam"] = cam.get_global_transform_interpolated().origin
	var ball = scene.get("ball")
	if ball is Node3D: pos["ball"] = ball.get_global_transform_interpolated().origin
	for p in scene.get_players(): pos["p%d" % p.actor_id] = p.get_global_transform_interpolated().origin
	# Speeds use the engine frame delta (game time), not wall time: right on the
	# phone and on --fixed-fps benches alike.
	var frame := {"t": _t(now), "ms": frame_ms, "dt": maxf(delta, 1e-4), "state": st, "pos": pos}
	_sec_state_frames[st] = int(_sec_state_frames.get(st, 0)) + 1
	_jit_prev.append(frame)
	if _jit_prev.size() > 3: _jit_prev.pop_front()
	_jit_buffer.append(frame)
	if _jit_buffer.size() > JIT_BUFFER: _jit_buffer.pop_front()
	if _jit_prev.size() < 3: return
	var a: Dictionary = _jit_prev[0]; var b: Dictionary = _jit_prev[1]; var c: Dictionary = _jit_prev[2]
	for obj in b.pos:
		if not a.pos.has(obj) or not c.pos.has(obj): continue
		var d1: Vector3 = b.pos[obj] - a.pos[obj]
		var d2: Vector3 = c.pos[obj] - b.pos[obj]
		var s1: float = d1.length() / float(b.dt)
		var s2: float = d2.length() / float(c.dt)
		# Judge frame b's step (d1) against its neighbours' speeds.
		var around: float = (_jit_speed(obj) + s2) * 0.5
		_jit_store_speed(obj, s1)
		if around < JIT_MOVING: continue
		var kind := ""
		if s1 < JIT_STALL * around: kind = "stall"
		elif s1 > JIT_POP * around and s1 > 1.0: kind = "pop"
		elif d1.dot(d2) < 0.0 and _jit_prev_step.has(obj) and d1.dot(_jit_prev_step[obj]) < 0.0: kind = "reverse"
		_jit_prev_step[obj] = d1
		if kind == "": continue
		var key := "%s:%s:%s:%s" % [obj, kind, _jit_zone(obj, b.pos[obj]), b.state]
		_sec_jitter[key] = int(_sec_jitter.get(key, 0)) + 1
		var times: Array = _jit_recent.get(obj, [])
		times.append(float(b.t))
		while not times.is_empty() and float(b.t) - float(times[0]) > 0.5: times.pop_front()
		_jit_recent[obj] = times
		if times.size() >= 3 and float(b.t) - float(_jit_last_burst.get(obj, -10.0)) > 3.0:
			_jit_last_burst[obj] = float(b.t)
			_write_jitter_burst(obj, kind, b)

var _jit_speeds: Dictionary = {}
var _jit_prev_step: Dictionary = {}
func _jit_speed(obj: String) -> float: return float(_jit_speeds.get(obj, 0.0))
func _jit_store_speed(obj: String, v: float) -> void: _jit_speeds[obj] = v

func _jit_zone(obj: String, at: Vector3) -> String:
	if not obj.begins_with("p"): return "-"
	var z := absf(at.z)
	return "behind" if z > 6.7 else ("kitchen" if z < 2.13 else "court")

func _write_jitter_burst(obj: String, kind: String, at: Dictionary) -> void:
	var frames := []
	for f in _jit_buffer:
		var row := {"t": f.t, "ms": snappedf(f.ms, 0.01), "state": f.state}
		for k in f.pos: row[k] = _v(f.pos[k])
		frames.append(row)
	var scopes := {}
	for label in _sec_costs: scopes[label] = snappedf(_sec_costs[label][1] / 1000.0, 0.01)
	_write({"kind": "jitter_burst", "t": at.t, "obj": obj, "last_kind": kind, "state": at.state,
		"zone": _jit_zone(obj, at.pos[obj]), "time_scale": Engine.time_scale, "worst_scope_ms_this_sec": scopes, "frames": frames})

# ---- pose trace (--pose-trace=path): joint positions per physics tick, for before/after diffs ----

func _physics_process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method("get_players"): return
	var row := {"tick": Engine.get_physics_frames()}
	var ball = scene.get("ball")
	if ball is Node3D: row["ball"] = _v(ball.global_position)
	for p in scene.get_players():
		var nodes: Array = _pose_nodes.get(p.get_instance_id(), [])
		if nodes.is_empty():
			for n in p.find_children("*", "Node3D", true, false):
				if n.name.ends_with("Pivot") or n.name in ["LeftHand", "RightHand", "LeftFoot", "RightFoot"]: nodes.append(n)
			_pose_nodes[p.get_instance_id()] = nodes
		var joints := {}
		for n in nodes: joints[n.name if not joints.has(n.name) else "%s#%d" % [n.name, joints.size()]] = _v(n.global_position)
		if p.paddle_node:
			var t: Transform3D = p.paddle_node.global_transform
			joints["paddle"] = _v(t.origin)
			joints["paddle_x"] = _v(t.origin + t.basis.x * 0.1)
			joints["paddle_y"] = _v(t.origin + t.basis.y * 0.1)
		row["p%d" % p.actor_id] = joints
	_pose_file.store_line(JSON.stringify(row, "", false))

func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_graph_layer.visible = not _graph_layer.visible

func _flush_second(now: int) -> void:
	var n := _sec_frames.size()
	var sorted := _sec_frames.duplicate()
	sorted.sort()
	var total := 0.0
	for f in sorted: total += f
	var per_frame := {}
	for label in _sec_costs:
		var s: Array = _sec_costs[label]
		per_frame[label] = [snappedf(s[0] / 1000.0 / n, 0.01), snappedf(s[1] / 1000.0, 0.01), snappedf(float(s[2]) / n, 0.01)]
	var top := {}
	var labels := per_frame.keys()
	labels.sort_custom(func(a, b): return per_frame[a][0] > per_frame[b][0])
	for i in labels.size(): top[labels[i]] = per_frame[labels[i]]   # all scopes, sorted by cost
	_write({"kind": "sec", "t": _t(now), "fps": n, "state": _state(),
		"avg_ms": snappedf(total / n, 0.1), "max_ms": snappedf(sorted[n - 1], 0.1),
		"p95_ms": snappedf(sorted[int(n * 0.95)], 0.1), "spikes": _sec_spikes,
		"cpu_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.1),
		"phys_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.1),
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"scopes": top, "jitter": _sec_jitter, "state_frames": _sec_state_frames})
	_sec_frames.clear()
	_sec_costs.clear()
	_sec_spikes = 0
	_sec_jitter = {}
	_sec_state_frames = {}
	_sec_start = now

# label -> [ms total this frame, calls], largest first
func _top(costs: Dictionary, key: Callable) -> Dictionary:
	var labels := costs.keys()
	labels.sort_custom(func(a, b): return key.call(costs[a]) > key.call(costs[b]))
	var out := {}
	for i in mini(TOP_SCOPES, labels.size()):
		var c: Array = costs[labels[i]]
		out[labels[i]] = [snappedf(c[1] / 1000.0, 0.01), c[0]]
	return out

func _state() -> String:
	var scene := get_tree().current_scene
	if scene == null: return "none"
	var gs = scene.get("game_state")
	if gs == null: return scene.name
	return ["WAITING", "SERVING", "PLAYING", "POINT_SCORED"][int(gs)] if int(gs) < 4 else str(gs)

func _t(now: int) -> float:
	return snappedf((now - _t0) / 1000000.0, 0.01)

func _write(row: Dictionary) -> void:
	if _file == null: return
	_file.store_line(JSON.stringify(row, "", false))
	_file.flush()

# ---- on-screen graph (F3) ----

func _build_graph() -> void:
	_graph_layer = CanvasLayer.new()
	_graph_layer.layer = 128
	_graph_layer.visible = false
	add_child(_graph_layer)
	_graph = Control.new()
	_graph.position = Vector2(8, 8)
	_graph.size = Vector2(GRAPH_SAMPLES, 110)
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_graph.draw.connect(_draw_graph)
	_graph_layer.add_child(_graph)

func _draw_graph() -> void:
	var h := _graph.size.y
	var scale := h / 66.0   # top of graph = 66 ms
	_graph.draw_rect(Rect2(Vector2.ZERO, _graph.size), Color(0, 0, 0, 0.6))
	for ref in [16.7, 33.3]:
		var y: float = h - ref * scale
		_graph.draw_line(Vector2(0, y), Vector2(_graph.size.x, y), Color(1, 1, 1, 0.3))
	var last := 0.0
	for i in _history.size():
		var ms := _history[i]
		last = ms
		var col := Color.GREEN if ms < 17.5 else (Color.YELLOW if ms < 34.0 else Color.RED)
		_graph.draw_line(Vector2(i, h), Vector2(i, h - minf(ms, 66.0) * scale), col)
	var font := ThemeDB.fallback_font
	_graph.draw_string(font, Vector2(4, 14), "%d fps  %.1f ms  %s" % [Engine.get_frames_per_second(), last, _state()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
