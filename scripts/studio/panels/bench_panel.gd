extends "res://scripts/studio/panels/studio_panel.gd"
## Bench tab: every logs/bench_*.perf.jsonl run (points, how they ended, endings per 100 shots,
## top systems, spikes, jitter) from `python3 tools/pose_studio/bench.py --json`, and a compare of
## two runs with the tools/pose_diff.py verdict (`--compare a b`). Read-only: it reads existing
## logs and has no button that starts a bench. Python runs on a worker thread so the UI never
## blocks (the compare can take a while on big traces).

const COLS := ["run", "points", "shots", "end/100", "endings", "fps med / 5%", "top system ms", "spikes", "jitter"]

var _table: Tree
var _count: Label
var _detail: Label
var _a: OptionButton
var _b: OptionButton
var _verdict: Label
var _verdict_text: Label
var _thread: Thread
var _busy := false
var runs: Array = []          # last bench.py runs (tests)
var compare_result: Dictionary = {}

func _init() -> void:
	name = "BenchPanel"
	add_to_group("studio_bench_panel")
	add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	var t := header("Bench runs (existing logs only)")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	top.add_child(button("Bench_Reload", "Re-read logs", refresh))
	add_child(top)
	add_child(status_label("Bench_Status"))
	_count = label("", FONT_SMALL, UI.MUTED)
	_count.name = "Bench_Count"
	add_child(_count)
	_table = Tree.new()
	_table.name = "Bench_Table"
	_table.columns = COLS.size()
	_table.column_titles_visible = true
	_table.hide_root = true
	_table.select_mode = Tree.SELECT_ROW
	_table.custom_minimum_size = Vector2(0, 220)
	_table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_table.add_theme_font_size_override("font_size", FONT_SMALL)
	for i in COLS.size():
		_table.set_column_title(i, COLS[i])
		_table.set_column_expand(i, false)
	_table.item_selected.connect(_show_detail)
	add_child(_table)
	var body := scroll_box("Bench_Body")
	_detail = label("Select a run for details", FONT_SMALL, UI.MUTED)
	_detail.name = "Bench_Detail"
	body.add_child(_detail)
	body.add_child(header("Compare two runs"))
	var row := HBoxContainer.new()
	_a = option("Bench_A", [])
	_a.item_selected.connect(func(i) -> void: _show_detail_of(i))
	_b = option("Bench_B", [])
	row.add_child(_a)
	row.add_child(label("vs", 0, UI.MUTED, false))
	row.add_child(_b)
	row.add_child(button("Bench_Compare", "Compare", run_compare))
	body.add_child(row)
	_verdict = header("")
	_verdict.name = "Bench_Verdict"
	body.add_child(_verdict)
	_verdict_text = label("", FONT_SMALL, UI.MUTED)
	_verdict_text.name = "Bench_CompareText"
	body.add_child(_verdict_text)

func _exit_tree() -> void:
	if _thread != null and _thread.is_started(): _thread.wait_to_finish()

func refresh() -> void:
	_run(["--json"], _on_runs)

func run_compare() -> void:
	if _a.selected < 0 or _b.selected < 0: return
	var a := _a.get_item_text(_a.selected)
	var b := _b.get_item_text(_b.selected)
	_verdict.text = "Comparing %s and %s…" % [a, b]
	_verdict_text.text = ""
	_run(["--json", "--compare", a, b], _on_compare)

## Starts bench.py on a worker thread; `done` gets the parsed JSON on the main thread.
func _run(args: Array, done: Callable) -> void:
	if _busy:
		set_status("bench.py is still running", true)
		return
	_busy = true
	set_status("Reading bench logs…")
	if _thread != null and _thread.is_started(): _thread.wait_to_finish()
	_thread = Thread.new()
	var script := project_root() + "/tools/pose_studio/bench.py"
	_thread.start(_worker.bind(PackedStringArray([script] + args), done))

func _worker(args: PackedStringArray, done: Callable) -> void:
	var out: Array = []
	var code := OS.execute("python3", args, out, true)
	var text := "".join(out)
	var parsed = JSON.parse_string(_json_part(text))
	var res: Dictionary
	if parsed == null: res = {"ok": false, "error": "bench.py (exit %d): %s" % [code, text.strip_edges().right(300)]}
	elif parsed is Array: res = {"ok": true, "runs": parsed}
	else: res = parsed
	_finish.call_deferred(res, done)

## stdout may carry stderr lines (read_stderr); keep from the first { or [ on.
static func _json_part(text: String) -> String:
	var i := text.find("{")
	var j := text.find("[")
	if i < 0 or (j >= 0 and j < i): i = j
	return text.substr(i) if i >= 0 else text

func _finish(res: Dictionary, done: Callable) -> void:
	if _thread != null and _thread.is_started(): _thread.wait_to_finish()
	_busy = false
	if not res.get("ok", true):
		set_status(str(res.get("error", "bench.py failed")), true)
		return
	set_status("")
	done.call(res)

func _on_runs(res: Dictionary) -> void:
	runs = arr(res, ["runs"])
	_table.clear()
	var root := _table.create_item()
	_a.clear(); _b.clear()
	for r in runs:
		if not (r is Dictionary): continue
		var it := _table.create_item(root)
		var endings: Array = r.get("endings", [])
		var sys: Array = r.get("systems", [])
		var jit: Array = r.get("jitter", [])
		var sp: Dictionary = r.get("spikes", {})
		var vals := [str(r.get("name")), value_text(r.get("points")), value_text(r.get("shots")), value_text(r.get("endings_per_100_shots")),
			", ".join(endings.slice(0, 3).map(func(e): return "%s %d" % [e.get("cause"), int(e.get("n", 0))])),
			"%s / %s" % [value_text(r.get("fps_median")), value_text(r.get("fps_worst_5"))],
			", ".join(sys.slice(0, 2).map(func(s): return "%s %s" % [s.get("name"), value_text(s.get("ms_per_frame"))])),
			"%d (worst %s)" % [int(sp.get("count", 0)), value_text(sp.get("worst_ms"))],
			", ".join(jit.slice(0, 2).map(func(j): return "%s %s/1k" % [j.get("what"), value_text(j.get("per_1k_frames"))]))]
		for i in vals.size():
			it.set_text(i, vals[i])
			it.set_tooltip_text(i, vals[i])
		it.set_metadata(0, r)
		_a.add_item(str(r.get("name")))
		_b.add_item(str(r.get("name")))
	fit_tree_columns(_table)
	if _b.item_count > 1: _b.select(_b.item_count - 1)
	if _a.item_count > 1: _a.select(_a.item_count - 2)
	_count.text = "%d run%s in logs/ (bench_*.perf.jsonl)" % [runs.size(), "" if runs.size() == 1 else "s"]

func _show_detail() -> void:
	var it := _table.get_selected()
	if it == null: return
	_show_run(it.get_metadata(0))

## Detail of the run picked in Bench_A (keyboard / ui_action path to the same text).
func _show_detail_of(i: int) -> void:
	var name_ := _a.get_item_text(i)
	for r in runs:
		if r is Dictionary and str(r.get("name")) == name_: _show_run(r)

func _show_run(r: Dictionary) -> void:
	var lines: PackedStringArray = []
	lines.append("%s  (%s, %s s, renderer %s, physics %s Hz, pose trace %s)" % [r.get("name"), r.get("file"),
		value_text(r.get("seconds")), str(r.get("renderer")), value_text(r.get("physics_hz")), "yes" if r.get("pose_trace", false) else "no"])
	lines.append("Points %s, shots %s, shots per point %s, endings per 100 shots %s" % [value_text(r.get("points")),
		value_text(r.get("shots")), value_text(r.get("shots_per_point")), value_text(r.get("endings_per_100_shots"))])
	lines.append("How points ended:")
	for e in r.get("endings", []): lines.append("  %s  %d  (%s per 100 shots)" % [e.get("cause"), int(e.get("n", 0)), value_text(e.get("per_100_shots"))])
	lines.append("Top systems (ms/frame):")
	for s in r.get("systems", []): lines.append("  %s  %s" % [s.get("name"), value_text(s.get("ms_per_frame"))])
	for s in r.get("inner_systems", []): lines.append("    inner %s  %s" % [s.get("name"), value_text(s.get("ms_per_frame"))])
	var sp: Dictionary = r.get("spikes", {})
	lines.append("Spikes: %d over %s ms, worst %s ms" % [int(sp.get("count", 0)), value_text(sp.get("threshold_ms")), value_text(sp.get("worst_ms"))])
	for m in sp.get("mostly", []): lines.append("  %s %s  x%d" % [m.get("state"), m.get("scope"), int(m.get("n", 0))])
	lines.append("Jitter:")
	for j in r.get("jitter", []): lines.append("  %s %s  %d  (%s per 1k frames)" % [j.get("state"), j.get("what"), int(j.get("count", 0)), value_text(j.get("per_1k_frames"))])
	_detail.text = "\n".join(lines)
	_detail.add_theme_color_override("font_color", UI.INK)

func _on_compare(res: Dictionary) -> void:
	compare_result = res
	var pd = res.get("pose_diff", {})
	var v := str(pd.get("verdict", "?")) if pd is Dictionary else "?"
	var a: Dictionary = res.get("a", {}) if res.get("a") is Dictionary else {}
	var b: Dictionary = res.get("b", {}) if res.get("b") is Dictionary else {}
	_verdict.text = "pose_diff: %s" % v
	_verdict.add_theme_color_override("font_color", UI.ACCENT if v == "IDENTICAL" else UI.RED)
	var lines: PackedStringArray = []
	for k in ["points", "shots", "endings_per_100_shots", "fps_median", "fps_worst_5"]:
		lines.append("%s: %s vs %s" % [k, value_text(a.get(k)), value_text(b.get(k))])
	var sa: Dictionary = a.get("spikes", {}) if a.get("spikes") is Dictionary else {}
	var sb: Dictionary = b.get("spikes", {}) if b.get("spikes") is Dictionary else {}
	lines.append("spikes: %s vs %s" % [value_text(sa.get("count")), value_text(sb.get("count"))])
	if pd is Dictionary and str(pd.get("text", "")) != "":
		lines.append("")
		lines.append(str(pd.text).right(1200))
	_verdict_text.text = "\n".join(lines)
