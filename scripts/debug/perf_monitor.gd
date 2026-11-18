extends Node
## Always-on performance monitor (autoload "PerfMonitor").
##
## - Hot functions call PerfMonitor.record("label", usec) via small timing wrappers.
## - Once per second writes one JSON line: fps, frame-time stats, per-system cost.
## - Any frame slower than SPIKE_MS writes a "spike" line naming what was slow.
## - F3 toggles an on-screen frame-time graph.
##
## Output: logs/perf.jsonl when run from source on Mac, user://perf.jsonl in an
## exported build (iPhone). Summarise with: python3 tools/perf_report.py

const SPIKE_MS := 50.0          # ~3 dropped frames at 60 fps
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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000000   # run after everything else in the frame
	var path := "user://perf.jsonl"
	if not OS.has_feature("template"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs"))
		path = "res://logs/perf.jsonl"
	_file = FileAccess.open(path, FileAccess.WRITE)
	_t0 = Time.get_ticks_usec()
	_last_usec = _t0
	_sec_start = _t0
	_write({"kind": "meta", "engine": Engine.get_version_info().string, "os": OS.get_name(),
		"model": OS.get_model_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"physics_hz": Engine.physics_ticks_per_second, "spike_ms": SPIKE_MS})
	_build_graph()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_usec) / 1000.0
	_frames += 1
	_last_usec = now

	var costs := _frame_costs
	_frame_costs = {}
	for label in costs:
		var c: Array = costs[label]
		var s: Array = _sec_costs.get(label, [0, 0])
		s[0] += c[1]
		s[1] = maxi(s[1], c[1])
		_sec_costs[label] = s

	_sec_frames.append(frame_ms)
	_history.append(frame_ms)
	if _history.size() > GRAPH_SAMPLES: _history.remove_at(0)

	if frame_ms >= SPIKE_MS and _frames > 30:
		_sec_spikes += 1
		_write({"kind": "spike", "t": _t(now), "ms": snappedf(frame_ms, 0.1), "state": _state(),
			"top": _top(costs, func(c): return c[1])})

	if now - _sec_start >= 1000000:
		_flush_second(now)

	if _graph_layer.visible: _graph.queue_redraw()

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
		per_frame[label] = [snappedf(s[0] / 1000.0 / n, 0.01), snappedf(s[1] / 1000.0, 0.01)]
	var top := {}
	var labels := per_frame.keys()
	labels.sort_custom(func(a, b): return per_frame[a][0] > per_frame[b][0])
	for i in mini(TOP_SCOPES, labels.size()): top[labels[i]] = per_frame[labels[i]]
	_write({"kind": "sec", "t": _t(now), "fps": n, "state": _state(),
		"avg_ms": snappedf(total / n, 0.1), "max_ms": snappedf(sorted[n - 1], 0.1),
		"p95_ms": snappedf(sorted[int(n * 0.95)], 0.1), "spikes": _sec_spikes,
		"cpu_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.1),
		"phys_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.1),
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"scopes": top})
	_sec_frames.clear()
	_sec_costs.clear()
	_sec_spikes = 0
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
	_file.store_line(JSON.stringify(row))
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
