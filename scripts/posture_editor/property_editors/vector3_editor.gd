class_name Vector3Editor extends VBoxContainer

## Reusable Vector3 editor with X/Y/Z spin boxes

signal value_changed(new_value: Vector3)

var _label: Label
var _x_spin: SpinBox
var _y_spin: SpinBox
var _z_spin: SpinBox
var _current_value: Vector3 = Vector3.ZERO
var _label_text: String = ""
var _step: float = 0.01
var _min_val: float = -10.0
var _max_val: float = 10.0

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	# Label
	_label = Label.new()
	_label.text = _label_text
	_label.add_theme_font_size_override("font_size", 13)
	_label.modulate = Color(0.88, 0.92, 0.98)
	add_child(_label)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	
	# X component - _create_spin already adds to self, just get reference
	_x_spin = _create_spin(row, "X", Color(1, 0.3, 0.3), _step, _min_val, _max_val)
	
	# Y component
	_y_spin = _create_spin(row, "Y", Color(0.3, 1, 0.3), _step, _min_val, _max_val)
	
	# Z component
	_z_spin = _create_spin(row, "Z", Color(0.3, 0.3, 1), _step, _min_val, _max_val)

func setup(label_text: String, step: float, min_val: float, max_val: float) -> void:
	_label_text = label_text
	_step = step
	_min_val = min_val
	_max_val = max_val

func _create_spin(parent_row: HBoxContainer, label: String, color: Color, step: float, min_val: float, max_val: float) -> SpinBox:
	var container := VBoxContainer.new()
	container.custom_minimum_size = Vector2(84, 0)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var lbl := Label.new()
	lbl.text = label
	lbl.modulate = color
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(lbl)
	
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = step
	spin.value = 0.0
	spin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(spin)
	
	parent_row.add_child(container)
	
	spin.value_changed.connect(_on_value_changed)
	
	return spin

func _on_value_changed(_val: float) -> void:
	_current_value = Vector3(_x_spin.value, _y_spin.value, _z_spin.value)
	value_changed.emit(_current_value)

func set_value(val: Vector3) -> void:
	_current_value = val
	_x_spin.value = val.x
	_y_spin.value = val.y
	_z_spin.value = val.z

func get_value() -> Vector3:
	return _current_value
