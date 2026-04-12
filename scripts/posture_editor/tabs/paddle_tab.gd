class_name PaddleTab extends VBoxContainer

## Tab for editing paddle position, rotation, commit zone, and signed-angle sources.

signal field_changed(field_name: String, value: Variant)

var _def: PostureDefinition = null

var _forehand_slider: SliderField
var _forward_slider: SliderField
var _y_offset_slider: SliderField

var _pitch_slider: SliderField
var _yaw_slider: SliderField
var _roll_slider: SliderField

var _pitch_signed_slider: SliderField
var _yaw_signed_slider: SliderField
var _roll_signed_slider: SliderField

var _pitch_sign_opt: OptionButton
var _yaw_sign_opt: OptionButton
var _roll_sign_opt: OptionButton

var _floor_clear_slider: SliderField

var _has_zone_check: CheckButton
var _zone_xmin: SliderField
var _zone_xmax: SliderField
var _zone_ymin: SliderField
var _zone_ymax: SliderField

func _ready() -> void:
	add_child(_create_section_label("Position"))

	_forehand_slider = SliderField.new("Forehand Mul", -2.0, 2.0, 0.01, 0.0)
	_forehand_slider.value_changed.connect(func(v): _on_field_changed("paddle_forehand_mul", v))
	add_child(_forehand_slider)

	_forward_slider = SliderField.new("Forward Mul", -2.0, 2.0, 0.01, 0.0)
	_forward_slider.value_changed.connect(func(v): _on_field_changed("paddle_forward_mul", v))
	add_child(_forward_slider)

	_y_offset_slider = SliderField.new("Y Offset", -2.0, 2.0, 0.01, 0.0)
	_y_offset_slider.value_changed.connect(func(v): _on_field_changed("paddle_y_offset", v))
	add_child(_y_offset_slider)

	add_child(_create_section_label("Rotation — base (degrees)"))

	_pitch_slider = SliderField.new("Pitch Base", -180.0, 180.0, 1.0, 0.0)
	_pitch_slider.value_changed.connect(func(v): _on_field_changed("paddle_pitch_base_deg", v))
	add_child(_pitch_slider)

	_yaw_slider = SliderField.new("Yaw Base", -180.0, 180.0, 1.0, 0.0)
	_yaw_slider.value_changed.connect(func(v): _on_field_changed("paddle_yaw_base_deg", v))
	add_child(_yaw_slider)

	_roll_slider = SliderField.new("Roll Base", -180.0, 180.0, 1.0, 0.0)
	_roll_slider.value_changed.connect(func(v): _on_field_changed("paddle_roll_base_deg", v))
	add_child(_roll_slider)

	add_child(_create_section_label("Rotation — signed add (degrees)"))

	_pitch_signed_slider = SliderField.new("Pitch Signed", -180.0, 180.0, 1.0, 0.0)
	_pitch_signed_slider.value_changed.connect(func(v): _on_field_changed("paddle_pitch_signed_deg", v))
	add_child(_pitch_signed_slider)

	_yaw_signed_slider = SliderField.new("Yaw Signed", -180.0, 180.0, 1.0, 0.0)
	_yaw_signed_slider.value_changed.connect(func(v): _on_field_changed("paddle_yaw_signed_deg", v))
	add_child(_yaw_signed_slider)

	_roll_signed_slider = SliderField.new("Roll Signed", -180.0, 180.0, 1.0, 0.0)
	_roll_signed_slider.value_changed.connect(func(v): _on_field_changed("paddle_roll_signed_deg", v))
	add_child(_roll_signed_slider)

	add_child(_create_section_label("Sign source"))

	_pitch_sign_opt = _add_sign_option_row("Pitch")
	_yaw_sign_opt = _add_sign_option_row("Yaw")
	_roll_sign_opt = _add_sign_option_row("Roll")
	_pitch_sign_opt.item_selected.connect(func(i): _on_field_changed("paddle_pitch_sign_source", i))
	_yaw_sign_opt.item_selected.connect(func(i): _on_field_changed("paddle_yaw_sign_source", i))
	_roll_sign_opt.item_selected.connect(func(i): _on_field_changed("paddle_roll_sign_source", i))

	add_child(_create_section_label("Floor & zone"))

	_floor_clear_slider = SliderField.new("Floor clearance", 0.0, 0.8, 0.01, 0.06)
	_floor_clear_slider.value_changed.connect(func(v): _on_field_changed("paddle_floor_clearance", v))
	add_child(_floor_clear_slider)

	_has_zone_check = CheckButton.new()
	_has_zone_check.text = "Has commit zone"
	_has_zone_check.toggled.connect(func(on): _on_field_changed("has_zone", on))
	add_child(_has_zone_check)

	_zone_xmin = SliderField.new("Zone X min", -2.0, 2.0, 0.01, 0.0)
	_zone_xmin.value_changed.connect(func(v): _on_field_changed("zone_x_min", v))
	add_child(_zone_xmin)

	_zone_xmax = SliderField.new("Zone X max", -2.0, 2.0, 0.01, 0.0)
	_zone_xmax.value_changed.connect(func(v): _on_field_changed("zone_x_max", v))
	add_child(_zone_xmax)

	_zone_ymin = SliderField.new("Zone Y min", -1.0, 2.0, 0.01, 0.0)
	_zone_ymin.value_changed.connect(func(v): _on_field_changed("zone_y_min", v))
	add_child(_zone_ymin)

	_zone_ymax = SliderField.new("Zone Y max", -1.0, 2.5, 0.01, 0.0)
	_zone_ymax.value_changed.connect(func(v): _on_field_changed("zone_y_max", v))
	add_child(_zone_ymax)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(spacer)


func _add_sign_option_row(axis_name: String) -> OptionButton:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = axis_name + " ×"
	lbl.custom_minimum_size = Vector2(72, 0)
	row.add_child(lbl)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.add_item("None")
	ob.add_item("Swing sign")
	ob.add_item("Fwd sign")
	row.add_child(ob)
	add_child(row)
	return ob


func _create_section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.modulate = Color(0.8, 0.9, 1.0)
	return lbl


func set_definition(def: PostureDefinition) -> void:
	_def = def
	if def == null:
		return
	_forehand_slider.set_value(def.paddle_forehand_mul)
	_forward_slider.set_value(def.paddle_forward_mul)
	_y_offset_slider.set_value(def.paddle_y_offset)
	_pitch_slider.set_value(def.paddle_pitch_base_deg)
	_yaw_slider.set_value(def.paddle_yaw_base_deg)
	_roll_slider.set_value(def.paddle_roll_base_deg)
	_pitch_signed_slider.set_value(def.paddle_pitch_signed_deg)
	_yaw_signed_slider.set_value(def.paddle_yaw_signed_deg)
	_roll_signed_slider.set_value(def.paddle_roll_signed_deg)
	_floor_clear_slider.set_value(def.paddle_floor_clearance)
	_has_zone_check.button_pressed = def.has_zone
	_zone_xmin.set_value(def.zone_x_min)
	_zone_xmax.set_value(def.zone_x_max)
	_zone_ymin.set_value(def.zone_y_min)
	_zone_ymax.set_value(def.zone_y_max)
	_pitch_sign_opt.select(clampi(def.paddle_pitch_sign_source, 0, 2))
	_yaw_sign_opt.select(clampi(def.paddle_yaw_sign_source, 0, 2))
	_roll_sign_opt.select(clampi(def.paddle_roll_sign_source, 0, 2))


func _on_field_changed(field: String, value: Variant) -> void:
	if _def:
		match field:
			"paddle_forehand_mul": _def.paddle_forehand_mul = value
			"paddle_forward_mul": _def.paddle_forward_mul = value
			"paddle_y_offset": _def.paddle_y_offset = value
			"paddle_pitch_base_deg": _def.paddle_pitch_base_deg = value
			"paddle_yaw_base_deg": _def.paddle_yaw_base_deg = value
			"paddle_roll_base_deg": _def.paddle_roll_base_deg = value
			"paddle_pitch_signed_deg": _def.paddle_pitch_signed_deg = value
			"paddle_yaw_signed_deg": _def.paddle_yaw_signed_deg = value
			"paddle_roll_signed_deg": _def.paddle_roll_signed_deg = value
			"paddle_pitch_sign_source": _def.paddle_pitch_sign_source = value
			"paddle_yaw_sign_source": _def.paddle_yaw_sign_source = value
			"paddle_roll_sign_source": _def.paddle_roll_sign_source = value
			"paddle_floor_clearance": _def.paddle_floor_clearance = value
			"has_zone": _def.has_zone = value
			"zone_x_min": _def.zone_x_min = value
			"zone_x_max": _def.zone_x_max = value
			"zone_y_min": _def.zone_y_min = value
			"zone_y_max": _def.zone_y_max = value

	field_changed.emit(field, value)
