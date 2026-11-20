extends "res://scripts/studio/panels/studio_panel.gd"
## Metrics tab: live body metrics of the preview player (the same _body_metrics the link's
## `metrics` command uses, from scripts/debug/pose_shots.gd) plus this pose's checker score and
## flags from logs/pose_check/latest.json. Refreshes after edits / stage changes, debounced to
## at most a few times per second; never per frame.

const Shots = preload("res://scripts/debug/pose_shots.gd")
const MIN_INTERVAL_MS := 300
const SETTLE_SEC := 0.25   # let the solver settle after an edit (link default: 12 frames)
const ORDER := ["hip_height", "com_back_to_front", "com_off_base_m", "com_over_base", "feet_planted",
	"stance_width", "stance_depth", "front_foot", "left_knee_bend", "right_knee_bend",
	"trunk_lean_fwd", "trunk_lean_side", "hip_yaw", "shoulder_yaw", "separation",
	"right_elbow_bend", "elbow_above_shoulder_m", "upper_arm_elevation_deg", "elbow_flare_deg",
	"wrist_angle_deg", "wrist_flex_deg", "wrist_deviation_deg", "paddle_tip_pitch_deg",
	"face_to_net_deg", "paddle_head", "paddle_from_shoulder", "com", "left_ankle", "right_ankle"]

var _shots: Node = null
var _timer: Timer
var _last_ms := -100000
var _title: Label
var _score: Label
var _flags: VBoxContainer
var _grid: GridContainer
var _when: Label
var _rows: Dictionary = {}     # metric -> {value: Label, unit: Label, flag: Label} (reused between refreshes)
var metrics: Dictionary = {}   # last computed metrics (also read by tests)
var computed := 0             # number of computations (tests: debounce check)

func _init() -> void:
	name = "MetricsPanel"
	add_to_group("studio_metrics_panel")
	add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	_title = header("Metrics")
	_title.name = "Metrics_Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	top.add_child(button("Metrics_Refresh", "Refresh", func() -> void: _schedule(true)))
	add_child(top)
	add_child(status_label("Metrics_Status"))
	var body := scroll_box("Metrics_Body")
	var chk := card()
	chk.name = "Metrics_Checker"
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 4)
	chk.add_child(cv)
	_score = label("Checker: -", FONT_BODY, UI.INK)
	_score.name = "Metrics_Score"
	cv.add_child(_score)
	_flags = VBoxContainer.new()
	_flags.name = "Metrics_Flags"
	_flags.add_theme_constant_override("separation", 2)
	cv.add_child(_flags)
	body.add_child(chk)
	body.add_child(header("Live (preview player)"))
	_grid = GridContainer.new()
	_grid.name = "Metrics_Grid"
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 3)
	body.add_child(_grid)
	_when = label("", FONT_SMALL, UI.MUTED)
	_when.name = "Metrics_When"
	body.add_child(_when)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_compute)
	add_child(_timer)

func _exit_tree() -> void:
	if _shots != null:
		_shots.free()
		_shots = null

func _on_pose_selected(_k) -> void: mark_stale()
func _on_pose_reloaded(_k) -> void: mark_stale()
func _on_pose_saved(_k, _v) -> void: mark_stale()
func _on_stage_changed(_s) -> void: _schedule()
func _on_pose_edited(_k) -> void: _schedule()

func refresh() -> void:
	_refresh_checker()
	_schedule(true)

## Debounce: wait for the solver to settle, and keep MIN_INTERVAL_MS between computations.
func _schedule(now := false) -> void:
	if not is_visible_in_tree():
		_stale = true
		return
	var wait := SETTLE_SEC
	var since := Time.get_ticks_msec() - _last_ms
	if since < MIN_INTERVAL_MS: wait = maxf(wait, (MIN_INTERVAL_MS - since) / 1000.0)
	if now and since >= MIN_INTERVAL_MS: wait = 0.05
	if _timer.is_stopped() or now: _timer.start(wait)

func _player():
	var ed = engine()
	if ed == null: return null
	var pv = ed.get("_preview")
	if pv == null or not is_instance_valid(pv): return null
	var p = pv.get("player")
	return p if p != null and is_instance_valid(p) else null

func _compute() -> void:
	_last_ms = Time.get_ticks_msec()
	var p = _player()
	_title.text = "Metrics  %s  %s" % [pose_key() if pose_key() != "" else "-", stage_name()]
	if p == null:
		set_status("no preview player (editor not open)", true)
		return
	if _shots == null: _shots = Shots.new()
	var t0 := Time.get_ticks_usec()
	metrics = _shots._body_metrics(p)
	computed += 1
	var pm = get_node_or_null("/root/PerfMonitor")
	if pm != null and pm.has_method("record"): pm.record("studio.metrics_panel", Time.get_ticks_usec() - t0)
	set_status("")
	_fill_grid()

## Table: metric | value + unit (right-aligned numbers) | flag dot (red = false check).
## Cells are made once per metric and reused; only texts change on later refreshes.
func _fill_grid() -> void:
	var keys: Array = ORDER.filter(func(k): return metrics.has(k))
	for k in metrics:
		if not keys.has(k): keys.append(k)
	if _grid.get_child_count() == 0:
		for h in [["Metric", HORIZONTAL_ALIGNMENT_LEFT], ["Value", HORIZONTAL_ALIGNMENT_RIGHT], ["", HORIZONTAL_ALIGNMENT_CENTER]]:
			var hl := label(h[0], FONT_SMALL, UI.MUTED, false)
			hl.horizontal_alignment = h[1]
			_grid.add_child(hl)
	for k in keys:
		var cells: Dictionary = _rows.get(k, {})
		if cells.is_empty():
			var name_l := label(k, FONT_BODY, UI.MUTED, false)
			name_l.name = "Metrics_n_" + k
			name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_l.tooltip_text = k
			name_l.mouse_filter = Control.MOUSE_FILTER_PASS
			_grid.add_child(name_l)
			var cell := HBoxContainer.new()
			cell.name = "Metrics_c_" + k
			cell.add_theme_constant_override("separation", 3)
			cell.alignment = BoxContainer.ALIGNMENT_END
			var val := label("", FONT_BODY, UI.INK, false)
			val.name = "Metrics_v_" + k
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cell.add_child(val)
			var unit := label(_unit(k), FONT_SMALL, UI.MUTED, false)
			unit.name = "Metrics_u_" + k
			unit.custom_minimum_size.x = 16
			cell.add_child(unit)
			_grid.add_child(cell)
			var flag := label("", FONT_SMALL, UI.MUTED, false)
			flag.name = "Metrics_f_" + k
			flag.custom_minimum_size.x = 12
			flag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_grid.add_child(flag)
			cells = {"value": val, "flag": flag}
			_rows[k] = cells
		var v = metrics[k]
		cells.value.text = value_text(v)
		var bad: bool = v is bool and not v
		cells.value.add_theme_color_override("font_color", UI.RED if bad else UI.INK)
		cells.flag.text = ("●" if v is bool else "")
		cells.flag.add_theme_color_override("font_color", UI.RED if bad else UI.MUTED)
		cells.flag.tooltip_text = ("check failed" if bad else "check passed") if v is bool else ""
	_when.text = "computed at %s" % Time.get_time_string_from_system()

## Unit shown after a value (the value text stays the plain number the link reports).
static func _unit(k: String) -> String:
	if k.ends_with("_deg") or k.ends_with("_yaw") or k.begins_with("trunk_lean") or k.ends_with("_bend") or k == "separation":
		return "°"
	if k.ends_with("_m") or k in ["hip_height", "stance_width", "stance_depth", "paddle_from_shoulder", "com",
			"left_ankle", "right_ankle", "paddle_head"]:
		return "m"
	return ""

func _refresh_checker() -> void:
	clear(_flags)
	var key := pose_key()
	var c := checker_of(key)
	var path := store_root() + "/logs/pose_check/latest.json"
	var age := ""
	if FileAccess.file_exists(path):
		var local := FileAccess.get_modified_time(path) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		age = "  (checker run %s)" % Time.get_datetime_string_from_unix_time(local, true)
	if c.is_empty():
		_score.text = "Checker: no result for %s%s. Run python3 tools/pose_check.py --solve" % [key if key != "" else "-", age]
		return
	_score.text = "Checker score %s%s" % [value_text(c.get("score")), age]
	_score.add_theme_color_override("font_color", UI.INK)
	var flags = c.get("flags", {})
	if flags is Array:
		var d := {}
		for f in flags: d[f] = ""
		flags = d
	if not (flags is Dictionary) or flags.is_empty():
		_flags.add_child(label("No flags", FONT_SMALL, UI.MUTED))
		return
	_flags.add_child(label("Flags (%d)" % flags.size(), FONT_SMALL, UI.MUTED, false))
	for f in flags:
		var l := label("● %s  %s" % [f, flags[f]], FONT_SMALL, UI.RED)
		l.name = "Metrics_Flag_" + str(f)
		_flags.add_child(l)
