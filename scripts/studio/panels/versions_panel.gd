extends "res://scripts/studio/panels/studio_panel.gd"
## Versions tab: the pose's versions (author, message, checker score, stars, approved), diff of
## two versions as a field table (version-diff), restore with a confirm step (restore, then
## studio.reload), approve. Reads pose_studio/versions/<key>/vNNN.json; writes via run_cli.

var _title: Label
var _list: VBoxContainer      # one toggle button per version: Versions_Row_vNNN
var _sel_n := -1
var _a: OptionButton
var _b: OptionButton
var _diff_count: Label
var _diff_grid: GridContainer
var _confirm: HBoxContainer
var _confirm_l: Label
var _restore_btn: Button
var _approve_btn: Button
var versions: Array = []   # records shown, oldest first (tests)
var diff_rows: Array = []  # last diff result (tests)
var _pending_restore := -1
var _list_scroll: ScrollContainer
const LIST_MAX := 260.0

func _init() -> void:
	name = "VersionsPanel"
	add_to_group("studio_versions_panel")
	add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	_title = header("Versions")
	_title.name = "Versions_Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	top.add_child(button("Versions_Refresh", "Refresh", refresh))
	add_child(top)
	add_child(status_label("Versions_Status"))
	var sc := ScrollContainer.new()
	sc.name = "Versions_ListScroll"
	sc.custom_minimum_size = Vector2(0, 40)
	sc.size_flags_vertical = Control.SIZE_FILL   # as tall as its rows (up to LIST_MAX); the diff below expands
	_list_scroll = sc
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.name = "Versions_List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	sc.add_child(_list)
	add_child(sc)
	var row := HBoxContainer.new()
	_restore_btn = button("Versions_Restore", "Restore…", _ask_restore)
	_approve_btn = button("Versions_Approve", "Approve", _approve)
	row.add_child(_restore_btn)
	row.add_child(_approve_btn)
	add_child(row)
	_confirm = HBoxContainer.new()
	_confirm.name = "Versions_Confirm"
	_confirm.visible = false
	_confirm_l = label("", FONT_SMALL, UI.RED)
	_confirm_l.name = "Versions_ConfirmText"
	_confirm_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm.add_child(_confirm_l)
	_confirm.add_child(button("Versions_RestoreYes", "Restore", _do_restore))
	_confirm.add_child(button("Versions_RestoreNo", "Cancel", _cancel_restore))
	add_child(_confirm)
	add_child(header("Compare two versions"))
	var crow := HBoxContainer.new()
	_a = option("Versions_A", [])
	_b = option("Versions_B", [])
	crow.add_child(_a)
	crow.add_child(label("→", 0, UI.MUTED, false))
	crow.add_child(_b)
	crow.add_child(button("Versions_Diff", "Diff", run_diff))
	add_child(crow)
	_diff_count = label("", FONT_SMALL, UI.MUTED)
	_diff_count.name = "Versions_DiffCount"
	add_child(_diff_count)
	var body := scroll_box("Versions_DiffBody")
	_diff_grid = GridContainer.new()
	_diff_grid.name = "Versions_DiffTable"
	_diff_grid.columns = 4
	_diff_grid.add_theme_constant_override("h_separation", 12)
	body.add_child(_diff_grid)

func _on_pose_selected(_k) -> void: _clear_diff(); mark_stale()
func _on_pose_saved(_k, _v) -> void: mark_stale()
func _on_pose_reloaded(_k) -> void: mark_stale()

func refresh() -> void:
	var key := pose_key()
	_title.text = "Versions  %s" % (key if key != "" else "-")
	_confirm.visible = false
	versions = versions_of(key)
	var stars := {}
	for r in ratings_of(key): stars[int(r.get("version", -1))] = r.get("stars")
	clear(_list)
	if _record(_sel_n).is_empty(): _sel_n = -1
	for i in range(versions.size() - 1, -1, -1):   # newest first
		var v: Dictionary = versions[i]
		var n := int(v.get("n", 0))
		var msg := str(v.get("message", ""))
		var full := "v%03d  %s  %s  score %s  %s%s%s\n%s" % [n, str(v.get("author", "")), short_time(v.get("time")),
			value_text(v.get("score")), stars_text(stars.get(n)) if stars.has(n) else "unrated",
			"  ✓ approved" if v.get("approved", false) else "", "  (current)" if i == versions.size() - 1 else "", msg]
		# Two short lines (the message trimmed to fit); the tooltip has everything.
		var txt := "v%03d  %s  %s%s%s\n%s · %s" % [n, str(v.get("author", "")), short_time(v.get("time")).substr(5),
			"  ✓" if v.get("approved", false) else "", "  current" if i == versions.size() - 1 else "",
			"score " + value_text(v.get("score")), stars_text(stars.get(n)) if stars.has(n) else "unrated"]
		if msg != "": txt += "\n" + (msg if msg.length() <= 44 else msg.substr(0, 43) + "…")
		var b := button("Versions_Row_v%03d" % n, txt, select_version.bind(n), true)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", FONT_SMALL)
		b.tooltip_text = full
		b.set_pressed_no_signal(n == _sel_n)
		if v.get("approved", false): b.add_theme_color_override("font_color", UI.ACCENT)
		_list.add_child(b)
	if versions.is_empty():
		_list.add_child(label("No versions yet: the first save or rating creates v000 (HEAD) and v001.", FONT_SMALL, UI.MUTED))
	_fill_pickers()
	_update_buttons()
	_fit_list.call_deferred()

func _fit_list() -> void:
	_list_scroll.custom_minimum_size.y = clampf(_list.get_combined_minimum_size().y, 40.0, LIST_MAX)

func _fill_pickers() -> void:
	var a_old := _picked(_a)
	var b_old := _picked(_b)
	_a.clear(); _b.clear()
	for v in versions:
		var n := int(v.get("n", 0))
		_a.add_item("v%03d" % n); _a.set_item_metadata(_a.item_count - 1, str(n))
		_b.add_item("v%03d" % n); _b.set_item_metadata(_b.item_count - 1, str(n))
	_b.add_item("working file"); _b.set_item_metadata(_b.item_count - 1, "file")
	_pick(_a, a_old if a_old != "" else (str(versions[-1].n) if not versions.is_empty() else ""))
	_pick(_b, b_old if b_old != "" else "file")

static func _picked(o: OptionButton) -> String:
	return str(o.get_item_metadata(o.selected)) if o.selected >= 0 and o.item_count > 0 else ""

static func _pick(o: OptionButton, meta: String) -> void:
	for i in o.item_count:
		if str(o.get_item_metadata(i)) == meta:
			o.select(i)
			return

func _selected_n() -> int:
	return _sel_n

func _update_buttons() -> void:
	var n := _selected_n()
	_restore_btn.disabled = n < 0 or pose_key() == ""
	_approve_btn.disabled = n < 0 or pose_key() == ""
	var rec := _record(n)
	_approve_btn.text = "Approved ✓ (undo)" if rec.get("approved", false) else "Approve"

func _record(n: int) -> Dictionary:
	for v in versions:
		if int(v.get("n", -2)) == n: return v
	return {}

## Select version n (row button press; also callable directly).
func select_version(n: int) -> bool:
	if _record(n).is_empty(): return false
	_sel_n = n
	for c in _list.get_children():
		if c is Button: c.set_pressed_no_signal(String(c.name) == "Versions_Row_v%03d" % n)
	_confirm.visible = false
	_update_buttons()
	return true

func _ask_restore() -> void:
	var n := _selected_n()
	if n < 0: return
	_pending_restore = n
	var dirty := false
	var ed = engine()
	if ed != null and ed.get("_dirty") is Dictionary: dirty = not (ed._dirty as Dictionary).is_empty()
	_confirm_l.text = "Write v%03d back to %s's pose file?%s A new version is recorded." % [n, pose_key(),
		" Unsaved edits are lost." if dirty else ""]
	_confirm.visible = true

func _cancel_restore() -> void:
	_confirm.visible = false
	_pending_restore = -1

func _do_restore() -> void:
	var key := pose_key()
	var n := _pending_restore
	_confirm.visible = false
	_pending_restore = -1
	if key == "" or n < 0: return
	var r := cli(["restore", key, n])
	if not r.ok: return
	if studio.has_method("reload"): studio.reload(key)
	refresh()
	set_status("Restored v%03d as v%03d" % [n, current_version(key)])

func _approve() -> void:
	var key := pose_key()
	var n := _selected_n()
	if key == "" or n < 0: return
	var off: bool = _record(n).get("approved", false)
	if not cli(["approve", key, n] + (["--off"] if off else [])).ok: return
	refresh()
	select_version(n)
	set_status("v%03d %s" % [n, "approval removed" if off else "approved"])

func _clear_diff() -> void:
	diff_rows = []
	clear(_diff_grid)
	_diff_count.text = ""

func run_diff() -> void:
	var key := pose_key()
	var a := _picked(_a)
	var b := _picked(_b)
	_clear_diff()
	if key == "" or a == "" or b == "": return
	var r := cli(["version-diff", key, a, b])
	if not r.ok: return
	diff_rows = arr(r, ["changes", "diff", "rows"])
	_diff_count.text = "%d field%s differ: %s → %s" % [diff_rows.size(), "" if diff_rows.size() == 1 else "s",
		"v%03d" % int(a), "working file" if b == "file" else "v%03d" % int(b)]
	for h in ["stage", "field", "v%03d" % int(a), "file" if b == "file" else "v%03d" % int(b)]:
		_diff_grid.add_child(header(h))
	for d in diff_rows:
		_diff_grid.add_child(label(str(d.get("stage", "")), FONT_SMALL, UI.MUTED))
		_diff_grid.add_child(label(str(d.get("field", "")), FONT_SMALL))
		for side in ["a", "b"]:
			var l := label(value_text(d.get(side)) if d.get(side) != null else "(none)", FONT_SMALL,
				UI.RED if side == "a" else UI.ACCENT)
			l.custom_minimum_size.x = 120
			_diff_grid.add_child(l)
