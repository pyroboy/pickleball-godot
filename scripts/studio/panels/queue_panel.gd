extends "res://scripts/studio/panels/studio_panel.gd"
## Queue tab (spec 4.1): the work queue (rated by stars, then unrated, then stale; inside a pose
## open notes, then checker flags) from `pose_notes.py queue`, progress per pose type (star-count
## bar, share at 5 stars vs the 80% target, none below 4, history line) from `progress`, and the
## changelog. Read-only apart from selecting a pose in the studio. Refreshes when shown.

const STAR_COLORS := [Color("e5534b"), Color("f0883e"), Color("d4b106"), Color("84ceff"), Color("bde879")]

var _show_done: CheckBox
var _queue_box: VBoxContainer
var _progress_box: VBoxContainer
var _log_box: VBoxContainer
var queue: Array = []        # last queue reply (tests)
var progress: Dictionary = {}
var changelog: Array = []

## Small line chart of share at 5 stars over the rating log. Draws only when data changes.
class History extends Control:
	var points: PackedFloat32Array = []
	var target := 0.8
	func _init() -> void:
		custom_minimum_size = Vector2(0, 48)
	func set_points(p: PackedFloat32Array, t: float) -> void:
		points = p
		target = t
		queue_redraw()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(1, 1, 1, 0.04))
		var ty := r.size.y * (1.0 - target)
		draw_line(Vector2(0, ty), Vector2(r.size.x, ty), Color("bde879", 0.5), 1.0)
		if points.size() < 2: return
		var line := PackedVector2Array()
		for i in points.size():
			line.append(Vector2(r.size.x * i / float(points.size() - 1), r.size.y * (1.0 - points[i])))
		draw_polyline(line, Color("84ceff"), 2.0)

func _init() -> void:
	name = "QueuePanel"
	add_to_group("studio_queue_panel")
	add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	var t := header("Queue")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	_show_done = check("Queue_ShowDone", "show done")
	_show_done.toggled.connect(func(_on) -> void: _fill_queue())
	top.add_child(_show_done)
	top.add_child(button("Queue_Refresh", "Refresh", refresh))
	add_child(top)
	add_child(status_label("Queue_Status"))
	var body := scroll_box("Queue_Body")
	_progress_box = VBoxContainer.new()
	_progress_box.name = "Queue_Progress"
	body.add_child(_progress_box)
	body.add_child(header("Work queue"))
	_queue_box = VBoxContainer.new()
	_queue_box.name = "Queue_List"
	body.add_child(_queue_box)
	body.add_child(header("Change log"))
	_log_box = VBoxContainer.new()
	_log_box.name = "Queue_Changelog"
	body.add_child(_log_box)

func _on_pose_saved(_k, _v) -> void: mark_stale()
func _on_pose_reloaded(_k) -> void: mark_stale()

func refresh() -> void:
	var q := cli(["queue", "--all"])
	queue = arr(q, ["queue", "poses", "items"]) if q.ok else []
	var p := cli(["progress"])
	progress = {}
	if p.ok:
		progress = p.get("progress", p) if p.get("progress") is Dictionary else p
	var c := cli(["changelog"])
	changelog = []
	if c.ok:
		var log_d = c.get("changelog", c)
		changelog = arr(log_d, ["versions"])
	_fill_progress()
	_fill_queue()
	_fill_log()

func _fill_queue() -> void:
	clear(_queue_box)
	var shown := 0
	for e in queue:
		if not (e is Dictionary): continue
		if e.get("done", false) and not _show_done.button_pressed: continue
		shown += 1
		var key := str(e.get("key", ""))
		var stars_s: String
		match str(e.get("group", "")):
			"rated": stars_s = stars_text(e.get("stars"))
			"stale": stars_s = "stale %s (v%s)" % [stars_text(e.get("stale_stars")), value_text(e.get("rated_version"))]
			_: stars_s = "unrated"
		var items: Array = e.get("items", [])
		var n_notes := items.filter(func(it): return it.get("type") == "note").size()
		var b := button("Queue_" + key, "%s  %s  v%s  score %s  %d notes, %d flags%s" % [key, stars_s,
			value_text(e.get("version")), value_text(e.get("score")),
			n_notes, items.size() - n_notes, "  done" if e.get("done", false) else ""], _select.bind(key))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", FONT_SMALL)
		if key == pose_key(): b.add_theme_color_override("font_color", UI.ACCENT)
		_queue_box.add_child(b)
		for it in items.slice(0, 3):
			var tag := str(it.get("id", "")) if it.get("type") == "note" else "flag " + str(it.get("id", ""))
			_queue_box.add_child(label("    %s: %s" % [tag, str(it.get("text", "")).substr(0, 90)], FONT_SMALL,
				UI.BLUE if it.get("type") == "note" else UI.MUTED))
		if items.size() > 3: _queue_box.add_child(label("    … %d more" % (items.size() - 3), FONT_SMALL, UI.MUTED))
	var count := label("%d of %d poses in the queue" % [shown, queue.size()], FONT_SMALL, UI.MUTED)
	count.name = "Queue_Count"
	_queue_box.add_child(count)

func _select(key: String) -> void:
	if studio != null and studio.has_method("select_pose"): studio.select_pose(key)

func _fill_progress() -> void:
	clear(_progress_box)
	_progress_box.add_child(header("Progress (target: 80% at 5 stars, none below 4)"))
	for typ in ["stroke", "base", "serve"]:
		var p = progress.get(typ)
		if not (p is Dictionary): continue
		var total := int(p.get("total", 0))
		var counts: Dictionary = p.get("counts", {})
		var line := label("%s: %d/%d at 5 stars (%d%%), below 4: %d, unrated %d, stale %d%s" % [
			{"stroke": "Strokes", "base": "Body stances", "serve": "Serves"}[typ], int(p.get("at_5", 0)), total,
			roundi(100.0 * float(p.get("share_5", 0.0))), int(p.get("below_4", 0)), int(p.get("unrated", 0)),
			int(p.get("stale", 0)), "  TARGET MET" if p.get("met", false) else ""], FONT_SMALL,
			UI.ACCENT if p.get("met", false) else UI.INK)
		line.name = "Queue_Progress_" + typ
		_progress_box.add_child(line)
		# Star-count bar: 1..5 stars, then unrated / stale, widths by count.
		var bar := HBoxContainer.new()
		bar.name = "Queue_Bar_" + typ
		bar.add_theme_constant_override("separation", 1)
		bar.custom_minimum_size = Vector2(0, 16)
		var segs: Array = []
		for s in range(1, 6): segs.append([int(counts.get(str(s), 0)), STAR_COLORS[s - 1], "%d★ %d" % [s, int(counts.get(str(s), 0))]])
		segs.append([int(p.get("unrated", 0)), UI.BORDER, "unrated %d" % int(p.get("unrated", 0))])
		segs.append([int(p.get("stale", 0)), Color("6d5a7a"), "stale %d" % int(p.get("stale", 0))])
		for sg in segs:
			if sg[0] <= 0: continue
			var r := ColorRect.new()
			r.color = sg[1]
			r.tooltip_text = sg[2]
			r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.size_flags_stretch_ratio = float(sg[0])
			bar.add_child(r)
		_progress_box.add_child(bar)
		var share := ProgressBar.new()
		share.name = "Queue_Share_" + typ
		share.min_value = 0.0
		share.max_value = 1.0
		share.value = float(p.get("share_5", 0.0))
		share.show_percentage = true
		share.custom_minimum_size = Vector2(0, 14)
		_progress_box.add_child(share)
		var hist: Array = p.get("history", [])
		if hist.size() >= 2:
			var h := History.new()
			h.name = "Queue_History_" + typ
			var pts := PackedFloat32Array()
			for e in hist: pts.append(float(e.get("share_5", 0.0)))
			h.set_points(pts, float(p.get("target_share_5", 0.8)))
			_progress_box.add_child(h)
		else:
			_progress_box.add_child(label("history: %d rating%s so far" % [hist.size(), "" if hist.size() == 1 else "s"], FONT_SMALL, UI.MUTED))
	if progress.is_empty(): _progress_box.add_child(label("No progress data", FONT_SMALL, UI.MUTED))

func _fill_log() -> void:
	clear(_log_box)
	var shown := 0
	for e in changelog:
		if not (e is Dictionary) or int(e.get("n", 0)) <= 1: continue   # v000/v001 are the baseline
		shown += 1
		if shown > 40: break
		var ch: Array = e.get("changes", [])
		var l := label("%s  %s v%03d  %s%s  %s  (%d change%s)" % [short_time(e.get("time")), e.get("pose"), int(e.get("n", 0)),
			e.get("author", ""), "  ✓" if e.get("approved", false) else "", str(e.get("message", "")),
			ch.size(), "" if ch.size() == 1 else "s"], FONT_SMALL)
		_log_box.add_child(l)
	if shown == 0: _log_box.add_child(label("No saved versions yet", FONT_SMALL, UI.MUTED))
