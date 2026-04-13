class_name TorsoTab extends VBoxContainer

## Tab for editing torso, hip, and spine fields

signal field_changed(field_name: String, value: Variant)

var _def: Resource = null

# Hip
var _hip_yaw_slider

# Torso
var _torso_yaw_slider
var _torso_pitch_slider
var _torso_roll_slider

# Spine
var _spine_curve_slider

# Body Pivot
var _body_yaw_slider
var _body_pitch_slider
var _body_roll_slider

func _ready() -> void:
	add_child(_create_section_label("Hip (degrees)"))
	
	_hip_yaw_slider = SliderField.new("Hip Yaw (Coil)", -45.0, 45.0, 1.0, 0.0)
	_hip_yaw_slider.value_changed.connect(func(v): _on_field_changed("hip_yaw_deg", v))
	add_child(_hip_yaw_slider)
	
	add_child(_create_section_label("Torso Rotation (degrees)"))
	
	_torso_yaw_slider = SliderField.new("Torso Yaw", -45.0, 45.0, 1.0, 0.0)
	_torso_yaw_slider.value_changed.connect(func(v): _on_field_changed("torso_yaw_deg", v))
	add_child(_torso_yaw_slider)
	
	_torso_pitch_slider = SliderField.new("Torso Pitch", -30.0, 30.0, 1.0, 0.0)
	_torso_pitch_slider.value_changed.connect(func(v): _on_field_changed("torso_pitch_deg", v))
	add_child(_torso_pitch_slider)
	
	_torso_roll_slider = SliderField.new("Torso Roll", -30.0, 30.0, 1.0, 0.0)
	_torso_roll_slider.value_changed.connect(func(v): _on_field_changed("torso_roll_deg", v))
	add_child(_torso_roll_slider)
	
	add_child(_create_section_label("Spine"))
	
	_spine_curve_slider = SliderField.new("Spine Curve", -30.0, 30.0, 1.0, 0.0)
	_spine_curve_slider.value_changed.connect(func(v): _on_field_changed("spine_curve_deg", v))
	add_child(_spine_curve_slider)
	
	add_child(_create_section_label("Body Pivot Rotation (degrees)"))
	
	_body_yaw_slider = SliderField.new("Body Yaw", -60.0, 60.0, 1.0, 0.0)
	_body_yaw_slider.value_changed.connect(func(v): _on_field_changed("body_yaw_deg", v))
	add_child(_body_yaw_slider)
	
	_body_pitch_slider = SliderField.new("Body Pitch", -30.0, 30.0, 1.0, 0.0)
	_body_pitch_slider.value_changed.connect(func(v): _on_field_changed("body_pitch_deg", v))
	add_child(_body_pitch_slider)
	
	_body_roll_slider = SliderField.new("Body Roll", -30.0, 30.0, 1.0, 0.0)
	_body_roll_slider.value_changed.connect(func(v): _on_field_changed("body_roll_deg", v))
	add_child(_body_roll_slider)
	
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
		_hip_yaw_slider.set_value(def.hip_yaw_deg)
		_torso_yaw_slider.set_value(def.torso_yaw_deg)
		_torso_pitch_slider.set_value(def.torso_pitch_deg)
		_torso_roll_slider.set_value(def.torso_roll_deg)
		_spine_curve_slider.set_value(def.spine_curve_deg)
		_body_yaw_slider.set_value(def.body_yaw_deg)
		_body_pitch_slider.set_value(def.body_pitch_deg)
		_body_roll_slider.set_value(def.body_roll_deg)

func _on_field_changed(field: String, value: float) -> void:
	if _def:
		match field:
			"hip_yaw_deg": _def.hip_yaw_deg = value
			"torso_yaw_deg": _def.torso_yaw_deg = value
			"torso_pitch_deg": _def.torso_pitch_deg = value
			"torso_roll_deg": _def.torso_roll_deg = value
			"spine_curve_deg": _def.spine_curve_deg = value
			"body_yaw_deg": _def.body_yaw_deg = value
			"body_pitch_deg": _def.body_pitch_deg = value
			"body_roll_deg": _def.body_roll_deg = value
	
	field_changed.emit(field, value)
