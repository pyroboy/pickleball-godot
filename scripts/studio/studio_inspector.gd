extends VBoxContainer
## Desktop Pose Studio: field inspector. Categories as the mobile editor (mobile_pose_fields.gd
## CATEGORIES, incl. Motion timing) plus a joint jump list (JOINT_IDS). One row per float, a
## collapsible group of three rows per vector (side / up / net), an option picker per option
## field. A label longer than the label column goes on its own line above its control (never
## cut; the tooltip has the full label and field name).
## Values come from the engine (studio.field_values); writes go through studio.set_field.

signal content_changed

const Theme_ = preload("res://scripts/studio/studio_theme.gd")
const Fields = preload("res://scripts/ui/mobile_pose_fields.gd")
const Row = preload("res://scripts/studio/studio_field_row.gd")
const AXES := ["side", "up", "net"]
const AXES_TIP := ["forehand side", "up", "toward net"]
const AXES_ROT_TIP := ["about the forehand-side axis", "about the up axis", "about the toward-net axis"]

var studio
var category_picker: OptionButton
var joint_picker: OptionButton
var fine_hint: Control
var scroll: ScrollContainer
var list: VBoxContainer
var category := 1
var rows: Array = []          # Row nodes
var options: Dictionary = {}  # field -> OptionButton
var collapsed: Dictionary = {}   # vector field -> true when its three rows are folded
var _groups: Dictionary = {}     # vector field -> {head: Button, rows: [Row]}
var _built_for := ""

func build(owner_studio) -> void:
	studio = owner_studio
	name = "Inspector"
	add_theme_constant_override("separation", Theme_.SP2)
	var head := HBoxContainer.new(); head.name = "InspectorHead"; add_child(head)
	head.add_theme_constant_override("separation", Theme_.SP2)
	category_picker = OptionButton.new(); category_picker.name = "CategoryPicker"; category_picker.focus_mode = Control.FOCUS_NONE
	for c in Fields.CATEGORIES: category_picker.add_item(c)
	category_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	category_picker.tooltip_text = "Field group"
	category_picker.item_selected.connect(set_category)
	head.add_child(category_picker)
	joint_picker = OptionButton.new(); joint_picker.name = "JointJump"; joint_picker.focus_mode = Control.FOCUS_NONE
	joint_picker.add_item("Jump to joint…")
	for l in Fields.JOINT_LABELS: joint_picker.add_item(l)
	joint_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	joint_picker.tooltip_text = "Select a joint (same as clicking it in the viewport)"
	joint_picker.item_selected.connect(func(i):
		if i > 0: studio.select_joint(Fields.JOINT_IDS[i - 1]))
	head.add_child(joint_picker)
	fine_hint = _Legend.new(); fine_hint.name = "InspectorHint"
	fine_hint.tooltip_text = "Ticks on each slider: purple wind-up · gold contact · cyan finish · white last saved · red foot-plant stop. Lock = gameplay field (changes how shots play)."
	add_child(fine_hint)
	scroll = ScrollContainer.new(); scroll.name = "FieldScroll"; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	list = VBoxContainer.new(); list.name = "FieldList"; list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	category_picker.select(category)

## Height the inspector needs to show every row without scrolling (head + legend + rows).
func content_height() -> float:
	var sep := get_theme_constant("separation")
	var h := 0.0
	var n := 0
	for c in get_children():
		if not (c is Control) or not c.visible: continue
		n += 1
		h += (list.get_combined_minimum_size().y if c == scroll else c.get_combined_minimum_size().y)
	return h + sep * maxi(0, n - 1)

func set_category(i: int) -> void:
	category = clampi(i, 0, Fields.CATEGORIES.size() - 1)
	category_picker.select(category)
	rebuild()

func jump_to_joint(id: String) -> void:
	var idx := Fields.JOINT_IDS.find(id)
	joint_picker.select(idx + 1 if idx >= 0 else 0)
	var c := Fields.category_for_joint(id)
	if c >= 0 and c != category: set_category(c)

## Label column width (points) and whether a caption fits in it.
func _fits(text: String) -> bool:
	var font := get_theme_font("font")
	var fs := get_theme_font_size("font_size")
	return font == null or font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= Row.LABEL_W - 2

func _caption(n: String, text: String, tip: String, gameplay: bool) -> HBoxContainer:
	# Label on its own line (too long for the label column): lock + full text.
	var line := HBoxContainer.new(); line.name = n
	line.add_theme_constant_override("separation", Row.SEP)
	var lock := Row.Lock.new(); lock.visible_lock = gameplay; lock.custom_minimum_size = Vector2(Row.LOCK_W, 0)
	lock.tooltip_text = Row.LOCK_TIP if gameplay else ""
	lock.mouse_filter = Control.MOUSE_FILTER_PASS if gameplay else Control.MOUSE_FILTER_IGNORE
	line.add_child(lock)
	var l := Label.new(); l.name = "Text"; l.text = text; l.tooltip_text = tip; l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(l)
	return line

## Rebuild rows for the current category / workspace (pose and stage changes only sync).
func rebuild() -> void:
	for c in list.get_children(): list.remove_child(c); c.queue_free()
	rows.clear(); options.clear(); _groups.clear()
	var ed = studio.engine
	if ed == null or not is_instance_valid(ed) or studio.key == "": _built_for = ""; content_changed.emit(); return
	var base: bool = ed._base
	_built_for = "%s:%d" % ["b" if base else "s", category]
	var descs: Array = Fields.category_fields(category, base)
	if descs.is_empty():
		var none := Label.new(); none.name = "NoFields"; none.text = "No fields in this group for this pose type."
		none.theme_type_variation = &"SmallLabel"; list.add_child(none)
	for d in descs:
		var gameplay: bool = d.field in studio.GAMEPLAY_FIELDS
		var wrapped: bool = d.field in Fields.WRAPPED_BODY_FIELDS
		var tip := "%s (%s)" % [d.label, d.field]
		match d.type:
			"vector":
				var head := Button.new(); head.name = "Head_" + d.field; head.text = d.label
				head.theme_type_variation = &"ToolButton"; head.focus_mode = Control.FOCUS_NONE
				head.alignment = HORIZONTAL_ALIGNMENT_LEFT; head.tooltip_text = tip + " · click to fold"
				head.icon = Theme_.icon("chev_right" if collapsed.get(d.field, false) else "chev_down")
				head.pressed.connect(toggle_group.bind(d.field))
				list.add_child(head)
				var rot: bool = String(d.field).ends_with("_rotation_deg")
				var grp: Array = []
				for a in 3:
					var r = Row.new(); list.add_child(r)
					r.setup(studio, d, a, AXES[a], gameplay, wrapped, true)
					r.set_tip("%s · %s (%s[%d])" % [d.label, (AXES_ROT_TIP if rot else AXES_TIP)[a], d.field, a])
					r.visible = not collapsed.get(d.field, false)
					rows.append(r); grp.append(r)
				_groups[d.field] = {"head": head, "rows": grp}
			"option":
				var long := not _fits(d.label)
				if long: list.add_child(_caption("Caption_" + d.field, d.label, tip, gameplay))
				var line := HBoxContainer.new(); line.name = "Row_" + d.field; list.add_child(line)
				line.add_theme_constant_override("separation", Row.SEP)
				var lock := Row.Lock.new(); lock.visible_lock = gameplay and not long; lock.custom_minimum_size = Vector2(Row.LOCK_W, 0)
				line.add_child(lock)
				if not long:
					var l := Label.new(); l.name = "Label_" + d.field; l.text = d.label; l.tooltip_text = tip
					l.custom_minimum_size.x = Row.LABEL_W; l.mouse_filter = Control.MOUSE_FILTER_PASS; line.add_child(l)
				var o := OptionButton.new(); o.name = "Option_" + d.field; o.focus_mode = Control.FOCUS_NONE
				for it in d.items: o.add_item(it)
				o.size_flags_horizontal = Control.SIZE_EXPAND_FILL; o.tooltip_text = tip; o.set_meta("tip", tip)
				o.item_selected.connect(func(i): studio.set_field(d.field, -1, i))
				line.add_child(o); options[d.field] = o
			_:
				var long2 := not _fits(d.label)
				if long2: list.add_child(_caption("Caption_" + d.field, d.label, tip, gameplay))
				var r = Row.new(); list.add_child(r)
				r.setup(studio, d, -1, "" if long2 else d.label, gameplay and not long2, wrapped)
				r.set_tip(tip)
				rows.append(r)
	sync()
	content_changed.emit()

func toggle_group(field: String) -> void:
	var g: Dictionary = _groups.get(field, {})
	if g.is_empty(): return
	var fold: bool = not collapsed.get(field, false)
	collapsed[field] = fold
	g.head.icon = Theme_.icon("chev_right" if fold else "chev_down")
	for r in g.rows: r.visible = not fold and r.has_value
	content_changed.emit()

## Push current / per-stage / saved values into the rows.
func sync() -> void:
	var ed = studio.engine
	if ed == null or not is_instance_valid(ed) or studio.key == "": return
	if _built_for != "%s:%d" % ["b" if ed._base else "s", category]: rebuild(); return
	var data: Dictionary = studio.field_values(_fields_shown())
	var shown_changed := false
	for r in rows:
		var e: Dictionary = data.get(r.field, {})
		var has := not e.is_empty()
		if r.has_value != has: r.has_value = has; shown_changed = true
		var vis: bool = has and not (r.axis >= 0 and collapsed.get(r.field, false))
		if r.visible != vis: r.visible = vis; shown_changed = true
		if not has: continue
		r.set_locked(studio.gameplay_locked(r.field))
		var cur = e.value
		var keys: Array = e.keys
		var saved = e.saved
		if r.axis >= 0:
			cur = cur[r.axis] if cur is Vector3 else 0.0
			var k2: Array = []
			for k in keys: k2.append(k[r.axis] if k is Vector3 else null)
			keys = k2
			saved = saved[r.axis] if saved is Vector3 else null
		r.sync(float(cur), keys, saved)
	for f in options:
		var e2: Dictionary = data.get(f, {})
		var vis2 := not e2.is_empty()
		if options[f].visible != vis2: options[f].visible = vis2; shown_changed = true
		if vis2:
			options[f].select(int(e2.value))
			var lk: bool = studio.gameplay_locked(f)
			options[f].disabled = lk
			options[f].tooltip_text = Row.LOCKED_TIP if lk else str(options[f].get_meta("tip", ""))
	if shown_changed: content_changed.emit()

func _fields_shown() -> Array:
	var out: Array = []
	for r in rows:
		if not (r.field in out): out.append(r.field)
	for f in options: out.append(f)
	return out

func state() -> Dictionary:
	var out: Array = []
	for r in rows: out.append(r.state())
	return {"category": Fields.CATEGORIES[category], "rows": out, "collapsed": collapsed.keys().filter(func(k): return collapsed[k])}

## One-line legend of the slider ticks, drawn (no wrapping text): coloured marks + words.
class _Legend extends Control:
	const ITEMS := [["wind-up", Color("bd80ff")], ["contact", Color("ffdc62")], ["finish", Color("58dfdb")],
		["saved", Color("eef5fa")], ["foot stop", Color("ff6b5e")]]
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
	func _get_minimum_size() -> Vector2:
		return Vector2(0, 18)
	func _draw() -> void:
		var font := get_theme_font("font")
		var fs := 13
		var x := 2.0
		var y := size.y * 0.5
		for it in ITEMS:
			var w := font.get_string_size(it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if x + 10 + w > size.x: break
			draw_line(Vector2(x, y - 5), Vector2(x, y + 5), it[1], 2.0)
			draw_string(font, Vector2(x + 6, y + fs * 0.35), it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("a9becb"))
			x += 6 + w + 14
