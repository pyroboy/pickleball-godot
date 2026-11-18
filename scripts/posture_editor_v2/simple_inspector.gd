class_name SimpleInspector extends VBoxContainer

## Generic property inspector that builds sliders/editors from a field descriptor array.
## Supports float, vector3, option, and bool fields.

signal field_changed(field_name: String, value: Variant)

var _def: Resource = null
var _widgets: Dictionary = {}  # field_name -> control
var _field_parent: VBoxContainer

## Descriptor format per field:
##   {
##     "label": String,
##     "type": "float" | "vector3" | "option" | "bool",
##     "min": float, "max": float, "step": float,   # for float/vector3
##     "items": ["Option 0", "Option 1", ...]         # for option
##   }
func build(fields: Array[String], descriptors: Dictionary) -> void:
	_field_parent = self
	for field in fields:
		var desc: Dictionary = descriptors.get(field, {})
		var label: String = desc.get("label", field)
		var type: String = desc.get("type", "float")
		match type:
			"section":
				_add_section(label, bool(desc.get("collapsible", false)))
			"float":
				_add_float(field, label, desc)
			"vector3":
				_add_vector3(field, label, desc)
			"option":
				_add_option(field, label, desc)
			"bool":
				_add_bool(field, label)
			_:
				push_warning("SimpleInspector: unknown type '%s' for field %s" % [type, field])
		if _widgets.has(field):
			_widgets[field].tooltip_text = desc.get("help", label + ": drag the slider or type an exact value.")

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(spacer)

func _add_section(label: String, collapsible: bool) -> void:
	_field_parent = self
	if collapsible:
		var toggle := Button.new()
		toggle.text = "%s  ▸" % label
		toggle.toggle_mode = true
		toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
		add_child(toggle)
		var details := VBoxContainer.new()
		details.visible = false
		add_child(details)
		toggle.toggled.connect(func(on: bool):
			details.visible = on
			toggle.text = "%s  %s" % [label, "▾" if on else "▸"]
		)
		_field_parent = details
	else:
		var heading := Label.new()
		heading.text = label
		heading.add_theme_font_size_override("font_size", 26)
		heading.add_theme_color_override("font_color", Color(0.65, 0.84, 1.0))
		add_child(heading)

func set_definition(def: Resource) -> void:
	_def = def
	for field in _widgets:
		_widgets[field].visible = def != null and def.get(field) != null
	if def == null:
		return
	for field in _widgets:
		var control = _widgets[field]
		if def.get(field) == null:
			continue
		var value = def.get(field)
		match control.get_meta("field_type"):
			"float":
				control.set_value(float(value))
			"vector3":
				control.set_value(value as Vector3)
			"option":
				control.select(clampi(int(value), 0, control.item_count - 1))
			"bool":
				control.set_pressed_no_signal(bool(value))

func _add_float(field: String, label: String, desc: Dictionary) -> void:
	var min_v: float = desc.get("min", -10.0)
	var max_v: float = desc.get("max", 10.0)
	var step: float = desc.get("step", 0.01)
	var slider := SliderField.new(label, min_v, max_v, step, 0.0)
	slider.value_changed.connect(func(v): _on_field_changed(field, v))
	slider.set_meta("field_type", "float")
	_widgets[field] = slider
	_field_parent.add_child(slider)

func _add_vector3(field: String, label: String, desc: Dictionary) -> void:
	var step: float = desc.get("step", 0.01)
	var min_v: float = desc.get("min", -10.0)
	var max_v: float = desc.get("max", 10.0)
	var editor := Vector3Editor.new()
	editor.setup(label, step, min_v, max_v)
	editor.value_changed.connect(func(v): _on_field_changed(field, v))
	editor.set_meta("field_type", "vector3")
	_widgets[field] = editor
	_field_parent.add_child(editor)

func _add_option(field: String, label: String, desc: Dictionary) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in desc.get("items", []):
		opt.add_item(item)
	opt.item_selected.connect(func(i): _on_field_changed(field, i))
	opt.set_meta("field_type", "option")
	_widgets[field] = opt
	row.add_child(opt)
	_field_parent.add_child(row)

func _add_bool(field: String, label: String) -> void:
	var check := CheckButton.new()
	check.text = label
	check.toggled.connect(func(on): _on_field_changed(field, on))
	check.set_meta("field_type", "bool")
	_widgets[field] = check
	_field_parent.add_child(check)

func _on_field_changed(field: String, value: Variant) -> void:
	if _def:
		_def.set(field, value)
	field_changed.emit(field, value)
