extends "res://scripts/studio/panels/studio_panel.gd"
## Notes tab: the current pose's notes (kinds request / rule), pinned to the studio's stage,
## field and scrubber time; status flow open -> addressed -> verified | reopened; Claude's reply
## block (text, changes, evidence, version). A note set to verified suggests re-rating.
## Reads pose_studio/notes/<key>.json; writes through studio.run_cli (note-add, note-set).

const NEXT := {"open": ["addressed"], "addressed": ["verified", "reopened"], "verified": ["reopened"],
	"reopened": ["addressed"]}
const STATUS_COLOR := {"open": Color("ffab9c"), "reopened": Color("ffab9c"), "addressed": Color("84ceff"),
	"verified": Color("bde879")}

var _title: Label
var _filter: OptionButton
var _list: VBoxContainer
var _kind: OptionButton
var _text: LineEdit
var _pin_stage: CheckBox
var _pin_field: CheckBox
var _field: LineEdit
var _pin_time: CheckBox
var _rerate: HBoxContainer
var shown_ids: Array = []   # note ids currently listed (tests)

func _init() -> void:
	name = "NotesPanel"
	add_to_group("studio_notes_panel")
	add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	_title = header("Notes")
	_title.name = "Notes_Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	_filter = option("Notes_Filter", ["Open", "All"])
	_filter.selected = 1
	_filter.item_selected.connect(func(_i) -> void: refresh())
	top.add_child(_filter)
	add_child(top)
	add_child(status_label("Notes_Status"))
	_rerate = HBoxContainer.new()
	_rerate.name = "Notes_RerateHint"
	_rerate.visible = false
	var hint := label("Note verified: rate this pose again?", FONT_SMALL, UI.ACCENT)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rerate.add_child(hint)
	_rerate.add_child(button("Notes_RateAgain", "Rate now", _open_rating))
	add_child(_rerate)
	_list = scroll_box("Notes_List")
	# New note form
	add_child(header("New note"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_kind = option("Notes_Kind", ["request", "rule"])
	_kind.tooltip_text = "request: one-off fix. rule: standing check."
	row.add_child(_kind)
	_field = LineEdit.new()
	_field.name = "Notes_Field"
	_field.placeholder_text = "Field name (optional)"
	_field.custom_minimum_size.x = 170
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_field)
	add_child(row)
	var pins := HFlowContainer.new()
	pins.name = "Notes_Pins"
	pins.add_theme_constant_override("h_separation", 12)
	pins.add_child(label("Pin to", FONT_SMALL, UI.MUTED, false))
	_pin_stage = check("Notes_PinStage", "stage", true)
	_pin_time = check("Notes_PinTime", "time")
	_pin_field = check("Notes_PinField", "field", true)
	for c in [_pin_stage, _pin_time, _pin_field]: pins.add_child(c)
	add_child(pins)
	_text = LineEdit.new()
	_text.name = "Notes_Text"
	_text.placeholder_text = "What is wrong, or what should always hold"
	add_child(_text)
	var add := button("Notes_Add", "Add note", _add_note)
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(add)

func _on_pose_selected(_k) -> void: _rerate.visible = false; _field.text = ""; mark_stale()
func _on_pose_saved(_k, _v) -> void: mark_stale()
func _on_stage_changed(_s) -> void: _update_title()

func _update_title() -> void:
	var key := pose_key()
	_title.text = "Notes  %s" % (key if key != "" else "-")
	_pin_stage.text = "stage (%s)" % stage_name()
	_pin_time.text = "time (%.2f)" % _scrub_time()

## Scrubber position 0..1 (0 wind-up, 0.5 contact, 1 finish) from the editor engine.
func _scrub_time() -> float:
	var ed = engine()
	if ed == null: return 0.5
	var p = ed.get("_progress")
	return clampf(float(p), 0.0, 1.0) if p != null else 0.5

## Field to pin: the studio's selected field when it exposes one, else the typed name.
func _studio_field() -> String:
	if studio == null: return ""
	for m in ["field", "selected_field"]:
		var f = studio.get(m)
		if f != null and str(f) != "": return str(f)
	return ""

func refresh() -> void:
	_update_title()
	var sf := _studio_field()
	if sf != "" and _field.text == "": _field.text = sf
	clear(_list)
	shown_ids.clear()
	var key := pose_key()
	if key == "":
		_list.add_child(label("No pose selected", FONT_SMALL, UI.MUTED))
		return
	var only_open := _filter.selected == 0
	var notes := notes_of(key)
	notes.reverse()   # newest first
	for n in notes:
		if not (n is Dictionary): continue
		if only_open and not (n.get("status") in ["open", "reopened"]): continue
		shown_ids.append(str(n.id))
		_list.add_child(_note_card(n))
	if shown_ids.is_empty():
		_list.add_child(label("No %snotes for %s" % ["open " if only_open else "", key], FONT_SMALL, UI.MUTED))

func _note_card(n: Dictionary) -> Control:
	var id := str(n.id)
	var c := card()
	c.name = "Notes_Card_" + id
	var v := VBoxContainer.new()
	c.add_child(v)
	var pin: PackedStringArray = []
	if n.get("stage") != null: pin.append(str(n.stage))
	if n.get("field") != null: pin.append(str(n.field))
	if n.get("time") != null: pin.append("t %.2f" % float(n.time))
	var st := str(n.get("status", "open"))
	var head := label("%s · %s · %s%s · %s · v%s" % [id, n.get("kind", "request"), st,
		("  [" + " / ".join(pin) + "]") if not pin.is_empty() else "", short_time(n.get("created")),
		value_text(n.get("created_version"))], FONT_SMALL, STATUS_COLOR.get(st, UI.MUTED))
	head.name = "Notes_Head_" + id
	v.add_child(head)
	v.add_child(label(str(n.get("text", ""))))
	if n.get("rule") is Dictionary and not (n.rule as Dictionary).is_empty():
		v.add_child(label("rule: " + JSON.stringify(n.rule), FONT_SMALL, UI.MUTED))
	var rep = n.get("reply")
	if rep is Dictionary:
		var rc := card()
		rc.name = "Notes_Reply_" + id
		var rv := VBoxContainer.new()
		rc.add_child(rv)
		rv.add_child(label("%s replied%s" % [str(rep.get("author", "claude")).capitalize(),
			(" · in v%03d" % int(rep.version)) if rep.get("version") != null else ""], FONT_SMALL, UI.BLUE))
		rv.add_child(label(str(rep.get("text", ""))))
		for ch in rep.get("changes", []):
			rv.add_child(label("  %s.%s  %s → %s" % [ch.get("stage"), ch.get("field"), value_text(ch.get("from")),
				value_text(ch.get("to"))], FONT_SMALL, UI.INK))
		if str(rep.get("evidence", "")) != "":
			rv.add_child(label("Evidence: " + str(rep.evidence), FONT_SMALL, UI.MUTED))
		v.add_child(rc)
	var row := HBoxContainer.new()
	for nxt in NEXT.get(st, []):
		row.add_child(button("Notes_%s_%s" % [id, nxt], {"addressed": "Mark addressed", "verified": "Verify",
			"reopened": "Reopen"}[nxt], _set_status.bind(id, nxt)))
	v.add_child(row)
	return c

func _set_status(id: String, status: String) -> void:
	if status == "verified" and studio != null and studio.get("link_driving"):
		set_status("Only the user verifies notes (refused: driven by the link)", true)
		return
	var r := cli(["note-set", id, "--status", status])
	if not r.ok: return
	refresh()
	_rerate.visible = status == "verified"
	set_status("%s → %s" % [id, status])
	for p in get_tree().get_nodes_in_group("studio_queue_panel"): p.mark_stale()
	for p in get_tree().get_nodes_in_group("studio_rating_panel"): p.mark_stale()

func _add_note() -> void:
	var key := pose_key()
	var text := _text.text.strip_edges()
	if key == "" or text == "":
		set_status("Write the note text first" if key != "" else "No pose selected", true)
		return
	var args: Array = ["note-add", key, "--kind", _kind.get_item_text(_kind.selected), "--text=" + text]
	if _pin_stage.button_pressed: args += ["--stage", stage_name()]
	if _pin_field.button_pressed and _field.text.strip_edges() != "": args += ["--field", _field.text.strip_edges()]
	if _pin_time.button_pressed: args += ["--time", "%.3f" % _scrub_time()]
	var r := cli(args)
	if not r.ok: return
	_text.text = ""
	refresh()
	var nid = r.get("id", (r.note as Dictionary).get("id") if r.get("note") is Dictionary else "")
	set_status("Added %s" % str(nid))
	for p in get_tree().get_nodes_in_group("studio_queue_panel"): p.mark_stale()
	for p in get_tree().get_nodes_in_group("studio_rating_panel"): p.mark_stale()

## Switch the right-side tabs to the rating panel (best effort; parent is a TabContainer).
func _open_rating() -> void:
	_rerate.visible = false
	for p in get_tree().get_nodes_in_group("studio_rating_panel"):
		var n: Node = p
		while n != null and n.get_parent() != null and not (n.get_parent() is TabContainer): n = n.get_parent()
		if n != null and n.get_parent() is TabContainer:
			var tc: TabContainer = n.get_parent()
			tc.current_tab = tc.get_tab_idx_from_control(n)
		return
