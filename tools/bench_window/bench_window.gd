extends Control
## Runs tools/bench.sh for several seeds and shows progress: bench label, elapsed
## and remaining time, one overall bar, one bar per seed, and a console log.
## User args (after "--"): --root=<repo> --name=<bench> --seconds=300 --seeds=1-6
## --jobs=3 [--shot=<png>: save a picture of the window after 4 s, for checking].

const PHYSICS_HZ := 30.0   # game physics tick; the bench runs at a fixed 60 fps
const INK := Color("d7e3ea")
const MUTED := Color("8aa0ad")
const ACCENT := Color("bde879")
const TRACK := Color("223040")

var root_dir := ""
var bench_name := "bench"
var seconds := 300
var seeds: Array[int] = [1, 2, 3, 4, 5, 6]
var jobs := 3
var shot_path := ""

var _pending: Array[int] = []
var _running: Dictionary = {}    # seed -> pid
var _done: Dictionary = {}       # seed -> true
var _started_ms := 0
var _finished := false
var _clock := 0.0
var _shot_clock := 4.0
var _tick_pattern := RegEx.new()

var _title: Label
var _status: Label
var _overall: ProgressBar
var _seed_bars: Dictionary = {}
var _log: RichTextLabel

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--root="): root_dir = arg.trim_prefix("--root=")
		elif arg.begins_with("--name="): bench_name = arg.trim_prefix("--name=")
		elif arg.begins_with("--seconds="): seconds = maxi(1, int(arg.trim_prefix("--seconds=")))
		elif arg.begins_with("--seeds="): seeds = _parse_seeds(arg.trim_prefix("--seeds="))
		elif arg.begins_with("--jobs="): jobs = maxi(1, int(arg.trim_prefix("--jobs=")))
		elif arg.begins_with("--shot="): shot_path = arg.trim_prefix("--shot=")
	_tick_pattern.compile("\"tick\": ?(\\d+)")
	get_window().title = "Pickleball bench: %s" % bench_name
	_build()
	_pending = seeds.duplicate()
	_started_ms = Time.get_ticks_msec()
	_say("bench %s: %d seeds, %d s each, %d at a time" % [bench_name, seeds.size(), seconds, jobs])
	if root_dir.is_empty() or not FileAccess.file_exists(root_dir.path_join("tools/bench.sh")):
		_say("tools/bench.sh not found under --root=%s" % root_dir)
		_pending.clear()

func _parse_seeds(text: String) -> Array[int]:
	var result: Array[int] = []
	for part in text.split(",", false):
		var ends: PackedStringArray = part.split("-", false)
		var low: int = int(ends[0])
		var high: int = int(ends[ends.size() - 1])
		for seed in range(low, high + 1): result.append(seed)
	return result if not result.is_empty() else [1] as Array[int]

func _bar(height: float, fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.001
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back := StyleBoxFlat.new()
	back.bg_color = TRACK
	back.set_corner_radius_all(3)
	var front := StyleBoxFlat.new()
	front.bg_color = fill
	front.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", front)
	return bar

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.clip_text = true
	return label

func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	_title = _label("%s  ·  %d seeds x %d s" % [bench_name, seeds.size(), seconds], 12, INK)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_title)
	_status = _label("starting", 12, ACCENT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_status)
	_overall = _bar(12, ACCENT)
	column.add_child(_overall)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	column.add_child(row)
	for seed in seeds:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(_label(str(seed), 10, INK))
		var bar := _bar(6, Color("5ff0ff"))
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(bar)
		_seed_bars[seed] = bar
		row.add_child(cell)
	_log = RichTextLabel.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.autowrap_mode = TextServer.AUTOWRAP_OFF
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Menlo", "Monaco", "Courier New"])
	_log.add_theme_font_override("normal_font", mono)
	_log.add_theme_font_size_override("normal_font_size", 10)
	_log.add_theme_color_override("default_color", INK)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("0b1016")
	panel.set_corner_radius_all(4)
	panel.set_content_margin_all(5)
	_log.add_theme_stylebox_override("normal", panel)
	column.add_child(_log)

func _say(text: String) -> void:
	print(text)
	_log.add_text(text + "\n")

func _perf_path(seed: int) -> String:
	return root_dir.path_join("logs/bench_%s%d.perf.jsonl" % [bench_name, seed])

func _out_path(seed: int) -> String:
	return root_dir.path_join("logs/benchwin_%s%d.txt" % [bench_name, seed])

func _start(seed: int) -> void:
	DirAccess.remove_absolute(_perf_path(seed))   # a stale log would show false progress
	var command := "cd '%s' && KEEP=40 tools/bench.sh %s%d %d %d > '%s' 2>&1" % [root_dir, bench_name, seed, seconds, seed, _out_path(seed)]
	var pid: int = OS.create_process("/bin/bash", ["-c", command])
	if pid <= 0:
		_say("seed %d: could not start" % seed)
		_done[seed] = true
		return
	_running[seed] = pid
	_say("seed %d: started" % seed)

func _finish(seed: int) -> void:
	_running.erase(seed)
	_done[seed] = true
	var file := FileAccess.open(_out_path(seed), FileAccess.READ)
	if file != null:
		while not file.eof_reached():
			var line: String = file.get_line()
			if line.begins_with("[") or line.begins_with("Points") or line.contains("ERROR"): _say(line)
		file.close()
		DirAccess.remove_absolute(_out_path(seed))
	_say("seed %d: finished (%d/%d)" % [seed, _done.size(), seeds.size()])

func _seed_progress(seed: int) -> float:
	if _done.has(seed): return 1.0
	if not _running.has(seed): return 0.0
	var file := FileAccess.open(_perf_path(seed), FileAccess.READ)
	if file == null: return 0.0
	var length: int = file.get_length()
	file.seek(maxi(0, length - 8192))
	var tail: String = file.get_buffer(mini(length, 8192)).get_string_from_utf8()
	file.close()
	var found: Array[RegExMatch] = _tick_pattern.search_all(tail)
	if found.is_empty(): return 0.0
	return minf(0.99, float(found[found.size() - 1].get_string(1)) / (float(seconds) * PHYSICS_HZ))

func _report() -> void:
	var arguments: PackedStringArray = PackedStringArray([root_dir.path_join("tools/shot_report.py")])
	for seed in seeds:
		if FileAccess.file_exists(_perf_path(seed)): arguments.append(_perf_path(seed))
	var output: Array = []
	OS.execute("python3", arguments, output, true)
	var lines: PackedStringArray = "".join(output).split("\n", false)
	for index in mini(lines.size(), 14): _say(lines[index])

func _process(delta: float) -> void:
	if not shot_path.is_empty():
		_shot_clock -= delta
		if _shot_clock <= 0.0:
			get_viewport().get_texture().get_image().save_png(shot_path)
			shot_path = ""
	_clock -= delta
	if _clock > 0.0: return
	_clock = 0.25
	if not _finished:
		for seed in _running.keys():
			if not OS.is_process_running(int(_running[seed])): _finish(seed)
		while not _pending.is_empty() and _running.size() < jobs: _start(_pending.pop_front())
	var total := 0.0
	for seed in seeds:
		var share: float = _seed_progress(seed)
		_seed_bars[seed].value = share
		total += share
	var overall: float = total / float(seeds.size())
	var elapsed: float = float(Time.get_ticks_msec() - _started_ms) / 1000.0
	if not _finished and _pending.is_empty() and _running.is_empty():
		_finished = true
		_report()
		_say("done in %s" % _clock_text(elapsed))
		_status.text = "done  ·  %s" % _clock_text(elapsed)
		_overall.value = 1.0
		return
	if _finished: return
	_overall.value = overall
	var left: String = "  ·  %s left" % _clock_text(elapsed * (1.0 - overall) / overall) if overall > 0.03 else ""
	_status.text = "%d%%  ·  %s%s" % [roundi(overall * 100.0), _clock_text(elapsed), left]

func _clock_text(value: float) -> String:
	var whole: int = maxi(0, roundi(value))
	return "%d:%02d" % [whole / 60, whole % 60]

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		for seed in _running: OS.kill(int(_running[seed]))
		if not _running.is_empty(): OS.execute("pkill", ["-f", "bench_%s" % bench_name])
