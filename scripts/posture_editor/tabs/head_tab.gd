class_name HeadTab extends VBoxContainer

## Tab for editing head tracking and rotation fields

signal field_changed(field_name: String, value: Variant)

var _def: Resource = null

# Head rotation
var _yaw_slider: SliderField
var _pitch_slider: SliderField

# Tracking weight
var _track_weight_slider: SliderField

func _ready() -> void:
	add_child(_create_section_label("Head Rotation (degrees)"))
	
	_yaw_slider = SliderField.new("Yaw", -90.0, 90.0, 1.0, 0.0)
	_yaw_slider.value_changed.connect(func(v): _on_field_changed("head_yaw_deg", v))
	add_child(_yaw_slider)
	
	_pitch_slider = SliderField.new("Pitch", -60.0, 60.0, 1.0, 0.0)
	_pitch_slider.value_changed.connect(func(v): _on_field_changed("head_pitch_deg", v))
	add_child(_pitch_slider)
	
	add_child(_create_section_label("Tracking"))
	
	_track_weight_slider = SliderField.new("Track Ball Weight", 0.0, 1.0, 0.01, 1.0)
	_track_weight_slider.value_changed.connect(func(v): _on_field_changed("head_track_ball_weight", v))
	add_child(_track_weight_slider)
	
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
		_yaw_slider.set_value(def.head_yaw_deg)
		_pitch_slider.set_value(def.head_pitch_deg)
		_track_weight_slider.set_value(def.head_track_ball_weight)

func _on_field_changed(field: String, value: float) -> void:
	if _def:
		match field:
			"head_yaw_deg": _def.head_yaw_deg = value
			"head_pitch_deg": _def.head_pitch_deg = value
			"head_track_ball_weight": _def.head_track_ball_weight = value
	
	field_changed.emit(field, value)
