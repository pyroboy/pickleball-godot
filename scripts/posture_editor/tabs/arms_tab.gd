class_name ArmsTab extends VBoxContainer

## Tab for editing arm and shoulder fields

signal field_changed(field_name: String, value: Variant)

var _def: Resource = null

# Shoulder rotations
var _right_shoulder_editor: Vector3Editor
var _left_shoulder_editor: Vector3Editor

# Elbow poles
var _right_elbow_editor: Vector3Editor
var _left_elbow_editor: Vector3Editor

# Hand offsets (paddle / local IK targets)
var _right_hand_editor: Vector3Editor
var _left_hand_editor: Vector3Editor

# Left hand mode
var _hand_mode_dropdown: OptionButton

func _ready() -> void:
	add_child(_create_section_label("Shoulder Rotation (degrees)"))
	
	_right_shoulder_editor = Vector3Editor.new()
	_right_shoulder_editor.setup("Right Shoulder", 1.0, -180.0, 180.0)
	_right_shoulder_editor.value_changed.connect(func(v): _on_field_changed("right_shoulder_rotation_deg", v))
	add_child(_right_shoulder_editor)
	
	_left_shoulder_editor = Vector3Editor.new()
	_left_shoulder_editor.setup("Left Shoulder", 1.0, -180.0, 180.0)
	_left_shoulder_editor.value_changed.connect(func(v): _on_field_changed("left_shoulder_rotation_deg", v))
	add_child(_left_shoulder_editor)
	
	add_child(_create_section_label("Hand offset (local, m)"))

	_right_hand_editor = Vector3Editor.new()
	_right_hand_editor.setup("Right hand", 0.01, -0.5, 0.5)
	_right_hand_editor.value_changed.connect(func(v): _on_field_changed("right_hand_offset", v))
	add_child(_right_hand_editor)

	_left_hand_editor = Vector3Editor.new()
	_left_hand_editor.setup("Left hand", 0.01, -0.5, 0.5)
	_left_hand_editor.value_changed.connect(func(v): _on_field_changed("left_hand_offset", v))
	add_child(_left_hand_editor)

	add_child(_create_section_label("Elbow Pole Targets"))
	
	_right_elbow_editor = Vector3Editor.new()
	_right_elbow_editor.setup("Right Elbow", 0.01, -2.0, 2.0)
	_right_elbow_editor.value_changed.connect(func(v): _on_field_changed("right_elbow_pole", v))
	add_child(_right_elbow_editor)
	
	_left_elbow_editor = Vector3Editor.new()
	_left_elbow_editor.setup("Left Elbow", 0.01, -2.0, 2.0)
	_left_elbow_editor.value_changed.connect(func(v): _on_field_changed("left_elbow_pole", v))
	add_child(_left_elbow_editor)
	
	add_child(_create_section_label("Left Hand Mode"))
	
	_hand_mode_dropdown = OptionButton.new()
	_hand_mode_dropdown.add_item("1-Hand (Free)")
	_hand_mode_dropdown.add_item("2-Hand (Paddle Neck)")
	_hand_mode_dropdown.add_item("1-Hand (Across Chest)")
	_hand_mode_dropdown.add_item("1-Hand (Overhead Lift)")
	_hand_mode_dropdown.item_selected.connect(func(i): _on_field_changed("left_hand_mode", i))
	add_child(_hand_mode_dropdown)
	
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(spacer)

func _create_section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.modulate = Color(0.8, 0.9, 1.0)
	return lbl

func set_definition(def: Resource) -> void:
	_def = def
	if def:
		_right_shoulder_editor.set_value(def.right_shoulder_rotation_deg)
		_left_shoulder_editor.set_value(def.left_shoulder_rotation_deg)
		_right_hand_editor.set_value(def.right_hand_offset)
		_left_hand_editor.set_value(def.left_hand_offset)
		_right_elbow_editor.set_value(def.right_elbow_pole)
		_left_elbow_editor.set_value(def.left_elbow_pole)
		_hand_mode_dropdown.select(def.left_hand_mode)

func _on_field_changed(field: String, value: Variant) -> void:
	if _def:
		match field:
			"right_shoulder_rotation_deg": _def.right_shoulder_rotation_deg = value
			"left_shoulder_rotation_deg": _def.left_shoulder_rotation_deg = value
			"right_hand_offset": _def.right_hand_offset = value
			"left_hand_offset": _def.left_hand_offset = value
			"right_elbow_pole": _def.right_elbow_pole = value
			"left_elbow_pole": _def.left_elbow_pole = value
			"left_hand_mode": _def.left_hand_mode = value
	
	field_changed.emit(field, value)
