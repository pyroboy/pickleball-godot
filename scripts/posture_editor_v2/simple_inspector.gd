class_name SimpleInspector extends VBoxContainer

## Generic property inspector that builds sliders/editors from a field descriptor array.
## Supports float, vector3, option, and bool fields.

signal field_changed(field_name: String, value: Variant)

var _def: Resource = null
var _widgets: Dictionary = {}  # field_name -> control

## Descriptor format per field:
##   {
##     "label": String,
##     "type": "float" | "vector3" | "option" | "bool",
##     "min": float, "max": float, "step": float,   # for float/vector3
##     "items": ["Option 0", "Option 1", ...]         # for option
##   }
func build(fields: Array[String], descriptors: Dictionary) -> void:
	for field in fields:
		var desc: Dictionary = descriptors.get(field, {})
		var label: String = desc.get("label", field)
		var type: String = desc.get("type", "float")
		match type:
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

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(spacer)

func set_definition(def: Resource) -> void:
	_def = def
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
				control.button_pressed = bool(value)

func _add_float(field: String, label: String, desc: Dictionary) -> void:
	var min_v: float = desc.get("min", -10.0)
	var max_v: float = desc.get("max", 10.0)
	var step: float = desc.get("step", 0.01)
	var slider := SliderField.new(label, min_v, max_v, step, 0.0)
	slider.value_changed.connect(func(v): _on_field_changed(field, v))
	slider.set_meta("field_type", "float")
	_widgets[field] = slider
	add_child(slider)

func _add_vector3(field: String, label: String, desc: Dictionary) -> void:
	var step: float = desc.get("step", 0.01)
	var min_v: float = desc.get("min", -10.0)
	var max_v: float = desc.get("max", 10.0)
	var editor := Vector3Editor.new()
	editor.setup(label, step, min_v, max_v)
	editor.value_changed.connect(func(v): _on_field_changed(field, v))
	editor.set_meta("field_type", "vector3")
	_widgets[field] = editor
	add_child(editor)

func _add_option(field: String, label: String, desc: Dictionary) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(100, 0)
	row.add_child(lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in desc.get("items", []):
		opt.add_item(item)
	opt.item_selected.connect(func(i): _on_field_changed(field, i))
	opt.set_meta("field_type", "option")
	_widgets[field] = opt
	row.add_child(opt)
	add_child(row)

func _add_bool(field: String, label: String) -> void:
	var check := CheckButton.new()
	check.text = label
	check.toggled.connect(func(on): _on_field_changed(field, on))
	check.set_meta("field_type", "bool")
	_widgets[field] = check
	add_child(check)

func _on_field_changed(field: String, value: Variant) -> void:
	if _def:
		_def.set(field, value)
	field_changed.emit(field, value)
