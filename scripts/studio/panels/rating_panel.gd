extends "res://scripts/studio/panels/studio_panel.gd"
## Rating tab (spec 4.1): 1-5 stars on the pose's current version, optional aspect stars
## (body, arm and paddle, motion, timing). Below 5 needs a reason: a new note or linked open
## notes. Shows "stale, rate again" when the last rating is on an older version.
## Writes only through studio.run_cli: note-add, then rate ... --by user --source studio.

const ASPECTS := [["body", "Body"], ["arm", "Arm and paddle"], ["motion", "Motion"], ["timing", "Timing"]]

var stars := 0
var aspects: Dictionary = {}   # aspect -> 1..5
var _state_l: Label
var _version_l: Label
var _star_btns: Array[Button] = []
var _aspect_btns: Dictionary = {}   # aspect -> Array[Button]
var _reason_box: VBoxContainer
var _open_box: VBoxContainer
var _note_text: LineEdit
var _comment: LineEdit
var _submit: Button
var _history: VBoxContainer

func _init() -> void:
	name = "RatingPanel"
	add_to_group("studio_rating_panel")
	add_theme_constant_override("separation", 8)
	_state_l = header("Rating")
	_state_l.name = "Rating_State"
	_state_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_state_l)
	_version_l = label("", FONT_SMALL, UI.MUTED)
	_version_l.name = "Rating_Version"
	add_child(_version_l)
	add_child(status_label("Rating_Status"))
	var body := scroll_box("Rating_Body")
	var row := HBoxContainer.new()
	for i in range(1, 6):
		var b := button("Rating_Star%d" % i, "☆", _set_stars.bind(i), true)
		b.add_theme_font_size_override("font_size", FONT_HEAD)
		b.custom_minimum_size = Vector2(32, 0)
		b.tooltip_text = ["", "1 broken", "2 clearly wrong", "3 acceptable but off", "4 good with a small nit", "5 ship it"][i]
		_star_btns.append(b)
		row.add_child(b)
	body.add_child(row)
	body.add_child(label("5 ship it · 4 small nit · 3 acceptable but off · 2 clearly wrong · 1 broken", FONT_SMALL, UI.MUTED))
	body.add_child(header("Aspects (optional)"))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 2)
	for a in ASPECTS:
		var al := label(a[1], FONT_BODY, null, false)
		al.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(al)
		var arr_b: Array[Button] = []
		for i in range(1, 6):
			var b := button("Rating_Aspect_%s_%d" % [a[0], i], "☆", _set_aspect.bind(a[0], i), true)
			b.theme_type_variation = &"ToolButton"
			arr_b.append(b)
			grid.add_child(b)
		_aspect_btns[a[0]] = arr_b
	body.add_child(grid)
	_reason_box = VBoxContainer.new()
	_reason_box.name = "Rating_Reason"
	_reason_box.visible = false
	_reason_box.add_child(label("Below 5: say why. Write a new note, or tick open notes.", FONT_SMALL, UI.BLUE))
	_note_text = LineEdit.new()
	_note_text.name = "Rating_NoteText"
	_note_text.placeholder_text = "New note (request, pinned to the current stage)"
	_note_text.text_changed.connect(func(_t) -> void: _update_submit())
	_note_text.text_submitted.connect(func(_t) -> void: _update_submit())
	_reason_box.add_child(_note_text)
	_open_box = VBoxContainer.new()
	_open_box.name = "Rating_OpenNotes"
	_reason_box.add_child(_open_box)
	body.add_child(_reason_box)
	_comment = LineEdit.new()
	_comment.name = "Rating_Comment"
	_comment.placeholder_text = "Comment (optional)"
	body.add_child(_comment)
	_submit = button("Rating_Submit", "Save rating", _submit_rating)
	_submit.theme_type_variation = &"PrimaryButton"
	_submit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(_submit)
	body.add_child(header("History"))
	_history = VBoxContainer.new()
	_history.name = "Rating_History"
	body.add_child(_history)
	_paint()

func _on_pose_selected(_k) -> void: _reset_form(); mark_stale()
func _on_pose_saved(_k, _v) -> void: mark_stale()
func _on_pose_reloaded(_k) -> void: mark_stale()

func _reset_form() -> void:
	stars = 0
	aspects.clear()
	_note_text.text = ""
	_comment.text = ""
	_paint()

func _set_stars(n: int) -> void:
	stars = 0 if stars == n else n
	_paint()

func _set_aspect(a: String, n: int) -> void:
	if aspects.get(a, 0) == n: aspects.erase(a)
	else: aspects[a] = n
	_paint()

func _paint() -> void:
	for i in 5:
		var on := i < stars
		_star_btns[i].set_pressed_no_signal(on)
		_star_btns[i].text = "★" if on else "☆"
		_star_btns[i].add_theme_color_override("font_color", UI.ACCENT if on else UI.MUTED)
	for a in _aspect_btns:
		var v: int = aspects.get(a, 0)
		for i in 5:
			var b: Button = _aspect_btns[a][i]
			b.set_pressed_no_signal(i < v)
			b.text = "★" if i < v else "☆"
	_reason_box.visible = stars > 0 and stars < 5
	_update_submit()

func linked_notes() -> Array:
	var out: Array = []
	for c in _open_box.get_children():
		if c is CheckBox and c.button_pressed: out.append(c.get_meta("note_id"))
	return out

func _has_reason() -> bool:
	return stars == 5 or _note_text.text.strip_edges() != "" or not linked_notes().is_empty()

func _update_submit() -> void:
	var unsaved := _has_unsaved()
	_submit.disabled = pose_key() == "" or stars == 0 or not _has_reason() or unsaved
	_submit.tooltip_text = "" if not _submit.disabled else ("Save first: a rating belongs to the saved version" if unsaved
		else "Pick stars" if stars == 0 else "Below 5 needs a note")

## The pose on screen differs from its file: a rating would land on a version not seen.
func _has_unsaved() -> bool:
	return studio != null and studio.has_method("diff") and not (studio.diff() as Array).is_empty()

func _on_pose_edited(_k) -> void:
	if _submit: _update_submit()

func refresh() -> void:
	var key := pose_key()
	var st := rating_state(key)
	var cur: int = st.version
	if key == "":
		_state_l.text = "Rating: no pose selected"
	elif st.stars != null:
		_state_l.text = "%s rated %s on v%03d" % [key, stars_text(st.stars), cur]
	elif st.stale:
		_state_l.text = "%s stale, rate again: %s was on v%03d, now v%03d" % [key, stars_text(st.stale_stars), int(st.rated_version), cur]
	else:
		_state_l.text = "%s not rated yet" % key
	_state_l.add_theme_color_override("font_color", UI.RED if st.stale else UI.ACCENT)
	_version_l.text = "Current version: %s" % ("v%03d" % cur if cur >= 0 else "none yet (made on first rating or save)")
	clear(_open_box)
	for n in notes_of(key):
		if not (n is Dictionary) or not (n.get("status") in ["open", "reopened"]): continue
		var cb := check("Rating_Link_" + str(n.id), "")
		cb.set_meta("note_id", str(n.id))
		var nt := str(n.get("text", ""))
		cb.text = "%s  %s" % [n.id, nt if nt.length() <= 40 else nt.substr(0, 39) + "…"]
		cb.tooltip_text = nt
		cb.toggled.connect(func(_on) -> void: _update_submit())
		_open_box.add_child(cb)
	clear(_history)
	var rows := ratings_of(key)
	for i in range(rows.size() - 1, maxi(-1, rows.size() - 11), -1):
		var r: Dictionary = rows[i]
		var asp := " ".join((r.get("aspects", {}) as Dictionary).keys().map(func(k): return "%s %d" % [k, int(r.aspects[k])]))
		var txt := "v%03d %s  %s %s  %s %s" % [int(r.get("version", 0)), stars_text(r.get("stars")), short_time(r.get("time")),
			str(r.get("source", "")), asp, str(r.get("comment", ""))]
		var l := label(txt.strip_edges(), FONT_SMALL, UI.INK if int(r.get("version", -1)) == cur else UI.MUTED)
		_history.add_child(l)
	if rows.is_empty(): _history.add_child(label("No ratings yet", FONT_SMALL, UI.MUTED))
	_update_submit()

func _submit_rating() -> void:
	var key := pose_key()
	if key == "" or stars == 0 or not _has_reason(): return
	if studio != null and studio.get("link_driving"):
		set_status("Ratings come from the user only (refused: driven by the link)", true)
		return
	if _has_unsaved():
		set_status("Save first: a rating belongs to the saved version", true)
		return
	var ids := linked_notes()
	var text := _note_text.text.strip_edges()
	if stars < 5 and text != "":
		var r := cli(["note-add", key, "--kind", "request", "--text=" + text, "--stage", stage_name()])
		if not r.ok: return
		var nid = r.get("id", (r.get("note", {}) as Dictionary).get("id") if r.get("note") is Dictionary else null)
		if nid == null:
			set_status("note-add gave no id", true)
			return
		ids.append(str(nid))
	var args: Array = ["rate", key, "--stars", stars]
	for a in aspects: args += ["--aspect", "%s=%d" % [a, aspects[a]]]
	for n in ids: args += ["--note", n]
	if _comment.text.strip_edges() != "": args += ["--comment=" + _comment.text.strip_edges()]
	args += ["--by", "user", "--source", "studio"]
	var res := cli(args)
	if not res.ok: return
	_reset_form()
	refresh()
	set_status("Rating saved")
	for p in get_tree().get_nodes_in_group("studio_queue_panel"): p.mark_stale()
	for p in get_tree().get_nodes_in_group("studio_notes_panel"): p.mark_stale()
