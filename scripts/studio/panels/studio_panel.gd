extends VBoxContainer
## Shared base for the Desktop Pose Studio data panels (scripts/studio/panels/*.gd).
## A panel reads pose_studio/*.json directly and sends every write through studio.run_cli
## (tools/pose_notes.py, one writer with the file lock). Work happens on studio signals or
## when the panel's tab becomes visible, never per frame.
## Interactive controls get stable unique names (prefix per panel) for ui_dump / ui_action.

const UI = preload("res://scripts/ui/game_ui_theme.gd")
const STAGE_NAMES := ["windup", "contact", "finish"]
# Font sizes: docs/POSE_STUDIO_SPEC.md 4.2 (studio_theme.gd): body 15, small 13, header 16.
const FONT_BODY := 15
const FONT_SMALL := 13
const FONT_HEAD := 16
const TARGET_H := 28.0

var studio = null
var _stale := true
var _status: Label

func _notification(what: int) -> void:
	# The editor runs with the game paused: panel timers and input must keep working.
	if what == NOTIFICATION_PARENTED: process_mode = Node.PROCESS_MODE_ALWAYS

func bind(s) -> void:
	studio = s
	for sig in ["pose_selected", "stage_changed", "pose_edited", "pose_saved", "pose_reloaded"]:
		var cb := Callable(self, "_on_" + sig)
		if s != null and s.has_signal(sig) and has_method("_on_" + sig) and not s.is_connected(sig, cb):
			s.connect(sig, cb)
	if not visibility_changed.is_connected(_on_visibility):
		visibility_changed.connect(_on_visibility)
	mark_stale()

## Refresh now when shown, else on the next time the tab is opened.
func mark_stale() -> void:
	_stale = true
	if is_visible_in_tree(): _refresh_later()

func _on_visibility() -> void:
	if is_visible_in_tree() and _stale: _refresh_later()

var _queued := false
func _refresh_later() -> void:
	if _queued: return
	_queued = true
	(func() -> void:
		_queued = false
		_stale = false
		refresh()).call_deferred()

## Override in panels.
func refresh() -> void:
	pass

# ---------------------------------------------------------------- studio access

func pose_key() -> String:
	if studio == null: return ""
	var k = studio.get("key")
	return str(k) if k != null else ""

func stage_name() -> String:
	if studio == null: return "contact"
	var s = studio.get("stage")
	return STAGE_NAMES[clampi(int(s), 0, 2)] if s != null else "contact"

func engine():
	if studio == null: return null
	var e = studio.get("engine")
	return e if e != null and is_instance_valid(e) else null

## Repo root whose data/ and logs/ the store uses, and the pose_studio/ folder itself. Same
## env vars as tools/pose_notes.py (POSE_STUDIO_REPO, POSE_STUDIO_ROOT), so the panels read what
## run_cli writes; tests point both at a scratch copy. Defaults: the project folder.
func store_root() -> String:
	var r := OS.get_environment("POSE_STUDIO_REPO")
	return r.trim_suffix("/") if r != "" else project_root()

func studio_dir() -> String:
	var d := OS.get_environment("POSE_STUDIO_ROOT")
	return d.trim_suffix("/") if d != "" else store_root() + "/pose_studio"

func project_root() -> String:
	return ProjectSettings.globalize_path("res://").trim_suffix("/")

func read_json(path: String, fallback = null):
	if not FileAccess.file_exists(path): return fallback
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges() == "": return fallback
	var v = JSON.parse_string(text)
	return fallback if v == null else v

## Notes of one pose (pose_studio/notes/<key>.json).
func notes_of(key: String) -> Array:
	if key == "": return []
	var v = read_json(studio_dir() + "/notes/%s.json" % key, [])
	return v if v is Array else []

func ratings_all() -> Array:
	var v = read_json(studio_dir() + "/ratings.json", [])
	return v if v is Array else []

func ratings_of(key: String) -> Array:
	var out: Array = []
	for r in ratings_all():
		if r is Dictionary and r.get("pose") == key: out.append(r)
	return out

## Version records of one pose, oldest first.
func versions_of(key: String) -> Array:
	var out: Array = []
	if key == "": return out
	var dir := studio_dir() + "/versions/" + key
	var names := DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray()
	var ns: Array[int] = []
	for f in names:
		if f.begins_with("v") and f.ends_with(".json") and f.substr(1, f.length() - 6).is_valid_int():
			ns.append(int(f.substr(1, f.length() - 6)))
	ns.sort()
	for n in ns:
		var rec = read_json(dir + "/v%03d.json" % n, null)
		if rec is Dictionary: out.append(rec)
	return out

func current_version(key: String) -> int:
	var vs := versions_of(key)
	return int(vs[-1].get("n", -1)) if not vs.is_empty() else -1

## Same rule as store.py rating_state: only a rating on the current version counts.
func rating_state(key: String) -> Dictionary:
	var cur := current_version(key)
	var rows := ratings_of(key)
	var last = rows[-1] if not rows.is_empty() else null
	for i in range(rows.size() - 1, -1, -1):
		if int(rows[i].get("version", -2)) == cur:
			return {"stars": int(rows[i].stars), "stale": false, "stale_stars": null, "version": cur,
				"rated_version": cur, "row": rows[i]}
	return {"stars": null, "stale": last != null, "stale_stars": last.stars if last != null else null,
		"version": cur, "rated_version": last.version if last != null else null, "row": last}

## Checker entry {score, flags} for a pose from logs/pose_check/latest.json ({} if none).
func checker_of(key: String) -> Dictionary:
	var d = read_json(store_root() + "/logs/pose_check/latest.json", {})
	if d is Dictionary and d.get(key) is Dictionary: return d[key]
	return {}

## Runs tools/pose_notes.py through the studio. Shows the error in the panel status line.
func cli(args: Array) -> Dictionary:
	if studio == null or not studio.has_method("run_cli"):
		return _fail("studio not bound")
	var r = studio.run_cli(PackedStringArray(args.map(func(a): return str(a))))
	if not (r is Dictionary): return _fail("bad reply from pose_notes.py")
	if not r.get("ok", false): return _fail(str(r.get("error", "pose_notes.py failed")))
	set_status("")
	return r

func _fail(msg: String) -> Dictionary:
	set_status(msg, true)
	return {"ok": false, "error": msg}

## First Array found under one of `keys` in a CLI reply (or the reply itself when it is a list).
static func arr(r, keys: Array) -> Array:
	if r is Array: return r
	if r is Dictionary:
		for k in keys:
			if r.get(k) is Array: return r[k]
	return []

# ---------------------------------------------------------------- building blocks

func status_label(name_: String) -> Label:
	_status = label("", 0, UI.RED)
	_status.name = name_
	_status.visible = false
	return _status

func set_status(text: String, error := false) -> void:
	if _status == null: return
	_status.text = text
	_status.visible = text != ""
	_status.add_theme_color_override("font_color", UI.RED if error else UI.ACCENT)

## wrap: true for running text in a column; false for a cell in a row or grid (a wrapping
## label there gets no width and breaks one character per line).
func label(text: String, size := 0, color = null, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	if size > 0: l.add_theme_font_size_override("font_size", size)
	if color != null: l.add_theme_color_override("font_color", color)
	return l

func header(text: String) -> Label:
	var l := label(text, 0, null, false)
	l.theme_type_variation = &"HeaderLabel"
	return l

func button(name_: String, text: String, cb: Callable, toggle := false) -> Button:
	var b := Button.new()
	b.name = name_
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	_compact(b)
	b.custom_minimum_size.y = TARGET_H
	b.pressed.connect(cb)
	return b

## A check box at the small font, still TARGET_H tall.
func check(name_: String, text: String, on := false) -> CheckBox:
	var c := CheckBox.new()
	c.name = name_
	c.text = text
	c.button_pressed = on
	c.add_theme_font_size_override("font_size", FONT_SMALL)
	c.custom_minimum_size.y = TARGET_H
	return c

func _compact(c: Control) -> void:
	c.add_theme_font_size_override("font_size", FONT_BODY)

func option(name_: String, items: Array) -> OptionButton:
	var o := OptionButton.new()
	o.name = name_
	o.focus_mode = Control.FOCUS_NONE
	for it in items: o.add_item(str(it))
	_compact(o)
	return o

func card() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"Card"
	return p

func scroll_box(name_: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = name_ + "Scroll"
	# As tall as its content: the tab's own ScrollContainer scrolls (no nested scrolling, no
	# empty expanding box).
	sc.size_flags_vertical = Control.SIZE_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.name = name_
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	sc.add_child(v)
	add_child(sc)
	return v

## Tree columns as wide as their widest cell or title (the tree scrolls sideways when the
## sum is wider than the panel), so no cell is cut.
static func fit_tree_columns(t: Tree) -> void:
	var font := t.get_theme_font("font")
	var fs := t.get_theme_font_size("font_size")
	var tfont := t.get_theme_font("title_button_font")
	var tfs := t.get_theme_font_size("title_button_font_size")
	var pad := t.get_theme_constant("inner_item_margin_left") + t.get_theme_constant("inner_item_margin_right") + 4
	var w: Array = []
	for c in t.columns:
		var tw := 0.0
		if t.column_titles_visible and t.get_column_title(c) != "":
			tw = tfont.get_string_size(t.get_column_title(c), HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x + 12
		w.append(tw)
	var root := t.get_root()
	var it := (root.get_first_child() if t.hide_root else root) if root else null
	while it != null:
		for c in t.columns:
			var txt := it.get_text(c)
			if txt == "": continue
			var f := it.get_custom_font_size(c)
			w[c] = maxf(w[c], font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f if f > 0 else fs).x + pad)
		it = it.get_next_in_tree()
	for c in t.columns:
		t.set_column_expand(c, false)
		t.set_column_custom_minimum_width(c, ceili(w[c]))

static func clear(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()

static func stars_text(n) -> String:
	if n == null: return "-"
	var k := clampi(int(n), 0, 5)
	return "★".repeat(k) + "☆".repeat(5 - k)

static func short_time(t) -> String:
	var s := str(t if t != null else "")
	return s.replace("T", " ").substr(0, 16)

static func value_text(v) -> String:
	if v == null: return "-"
	if v is Array: return ", ".join(v.map(func(x): return str(x)))
	if v is float:
		if is_equal_approx(v, roundf(v)) and absf(v) < 1e15: return str(int(roundf(v)))
		return str(snappedf(v, 0.01))
	return str(v)
