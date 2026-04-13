class_name LegsTab extends VBoxContainer

## Tab for editing leg and foot fields

signal field_changed(field_name: String, value: Variant)

var _def: Resource = null

# Stance fields
var _stance_slider
var _front_foot_slider
var _back_foot_slider

# Foot yaw
var _right_yaw_slider
var _left_yaw_slider

# Knee poles
var _right_knee_editor
var _left_knee_editor

# Foot fine offsets (stance basis)
var _right_foot_off
var _left_foot_off
var _lead_foot_opt

# Other
var _crouch_slider
var _weight_shift_slider

func _ready() -> void:
	add_child(_create_section_label("Stance"))
	
	_stance_slider = SliderField.new("Stance Width", 0.0, 1.0, 0.01, 0.35)
	_stance_slider.value_changed.connect(func(v): _on_field_changed("stance_width", v))
	add_child(_stance_slider)
	
	_front_foot_slider = SliderField.new("Front Foot Fwd", -0.5, 0.5, 0.01, 0.12)
	_front_foot_slider.value_changed.connect(func(v): _on_field_changed("front_foot_forward", v))
	add_child(_front_foot_slider)
	
	_back_foot_slider = SliderField.new("Back Foot Back", -0.5, 0.5, 0.01, -0.08)
	_back_foot_slider.value_changed.connect(func(v): _on_field_changed("back_foot_back", v))
	add_child(_back_foot_slider)
	
	add_child(_create_section_label("Foot Yaw (degrees)"))
	
	_right_yaw_slider = SliderField.new("Right Foot", -90.0, 90.0, 1.0, 0.0)
	_right_yaw_slider.value_changed.connect(func(v): _on_field_changed("right_foot_yaw_deg", v))
	add_child(_right_yaw_slider)
	
	_left_yaw_slider = SliderField.new("Left Foot", -90.0, 90.0, 1.0, 0.0)
	_left_yaw_slider.value_changed.connect(func(v): _on_field_changed("left_foot_yaw_deg", v))
	add_child(_left_yaw_slider)
	
	add_child(_create_section_label("Knee Pole Targets"))
	
	_right_knee_editor = Vector3Editor.new()
	_right_knee_editor.setup("Right Knee", 0.01, -2.0, 2.0)
	_right_knee_editor.value_changed.connect(func(v): _on_field_changed("right_knee_pole", v))
	add_child(_right_knee_editor)
	
	_left_knee_editor = Vector3Editor.new()
	_left_knee_editor.setup("Left Knee", 0.01, -2.0, 2.0)
	_left_knee_editor.value_changed.connect(func(v): _on_field_changed("left_knee_pole", v))
	add_child(_left_knee_editor)

	add_child(_create_section_label("Foot offset (fh.x, up.y, fwd.z)"))

	_right_foot_off = Vector3Editor.new()
	_right_foot_off.setup("Right foot", 0.01, -1.0, 1.0)
	_right_foot_off.value_changed.connect(func(v): _on_field_changed("right_foot_offset", v))
	add_child(_right_foot_off)

	_left_foot_off = Vector3Editor.new()
	_left_foot_off.setup("Left foot", 0.01, -1.0, 1.0)
	_left_foot_off.value_changed.connect(func(v): _on_field_changed("left_foot_offset", v))
	add_child(_left_foot_off)

	var lead_row := HBoxContainer.new()
	var lead_lbl := Label.new()
	lead_lbl.text = "Lead foot"
	lead_lbl.custom_minimum_size = Vector2(100, 0)
	lead_row.add_child(lead_lbl)
	_lead_foot_opt = OptionButton.new()
	_lead_foot_opt.add_item("Right")
	_lead_foot_opt.add_item("Left")
	_lead_foot_opt.item_selected.connect(func(i): _on_field_changed("lead_foot", i))
	_lead_foot_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lead_row.add_child(_lead_foot_opt)
	add_child(lead_row)
	
	add_child(_create_section_label("Other"))
	
	_crouch_slider = SliderField.new("Crouch", 0.0, 1.0, 0.01, 0.0)
	_crouch_slider.value_changed.connect(func(v): _on_field_changed("crouch_amount", v))
	add_child(_crouch_slider)
	
	_weight_shift_slider = SliderField.new("Weight Shift", -1.0, 1.0, 0.01, 0.0)
	_weight_shift_slider.value_changed.connect(func(v): _on_field_changed("weight_shift", v))
	add_child(_weight_shift_slider)
	
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
		_stance_slider.set_value(def.stance_width)
		_front_foot_slider.set_value(def.front_foot_forward)
		_back_foot_slider.set_value(def.back_foot_back)
		_right_yaw_slider.set_value(def.right_foot_yaw_deg)
		_left_yaw_slider.set_value(def.left_foot_yaw_deg)
		_right_knee_editor.set_value(def.right_knee_pole)
		_left_knee_editor.set_value(def.left_knee_pole)
		_right_foot_off.set_value(def.right_foot_offset)
		_left_foot_off.set_value(def.left_foot_offset)
		_lead_foot_opt.select(clampi(def.lead_foot, 0, 1))
		_crouch_slider.set_value(def.crouch_amount)
		_weight_shift_slider.set_value(def.weight_shift)

func _on_field_changed(field: String, value: Variant) -> void:
	if _def:
		match field:
			"stance_width": _def.stance_width = value
			"front_foot_forward": _def.front_foot_forward = value
			"back_foot_back": _def.back_foot_back = value
			"right_foot_yaw_deg": _def.right_foot_yaw_deg = value
			"left_foot_yaw_deg": _def.left_foot_yaw_deg = value
			"right_knee_pole": _def.right_knee_pole = value
			"left_knee_pole": _def.left_knee_pole = value
			"right_foot_offset": _def.right_foot_offset = value
			"left_foot_offset": _def.left_foot_offset = value
			"lead_foot": _def.lead_foot = value
			"crouch_amount": _def.crouch_amount = value
			"weight_shift": _def.weight_shift = value
	
	field_changed.emit(field, value)
