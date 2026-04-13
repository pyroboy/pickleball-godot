class_name ChargeTab extends VBoxContainer

signal field_changed(field_name: String, value: Variant)

var _def = null

var _paddle_off
var _paddle_rot
var _body_rot
var _hip_coil
var _back_foot_load

func _ready() -> void:
	add_child(_section("Charge — paddle & body"))

	_paddle_off = Vector3Editor.new()
	_paddle_off.setup("Paddle offset", 0.01, -0.8, 0.8)
	_paddle_off.value_changed.connect(func(v): _on_field_changed("charge_paddle_offset", v))
	add_child(_paddle_off)

	_paddle_rot = Vector3Editor.new()
	_paddle_rot.setup("Paddle rot °", 1.0, -120.0, 120.0)
	_paddle_rot.value_changed.connect(func(v): _on_field_changed("charge_paddle_rotation_deg", v))
	add_child(_paddle_rot)

	_body_rot = SliderField.new("Body rotation °", -120.0, 120.0, 1.0, 0.0)
	_body_rot.value_changed.connect(func(v): _on_field_changed("charge_body_rotation_deg", v))
	add_child(_body_rot)

	_hip_coil = SliderField.new("Hip coil °", -60.0, 60.0, 1.0, 0.0)
	_hip_coil.value_changed.connect(func(v): _on_field_changed("charge_hip_coil_deg", v))
	add_child(_hip_coil)

	_back_foot_load = SliderField.new("Back foot load", 0.0, 1.0, 0.01, 0.7)
	_back_foot_load.value_changed.connect(func(v): _on_field_changed("charge_back_foot_load", v))
	add_child(_back_foot_load)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(spacer)


func _section(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.modulate = Color(0.8, 0.9, 1.0)
	return lbl


func set_definition(def) -> void:
	_def = def
	if def == null:
		return
	_paddle_off.set_value(def.charge_paddle_offset)
	_paddle_rot.set_value(def.charge_paddle_rotation_deg)
	_body_rot.set_value(def.charge_body_rotation_deg)
	_hip_coil.set_value(def.charge_hip_coil_deg)
	_back_foot_load.set_value(def.charge_back_foot_load)


func _on_field_changed(field: String, value: Variant) -> void:
	if _def:
		match field:
			"charge_paddle_offset": _def.charge_paddle_offset = value
			"charge_paddle_rotation_deg": _def.charge_paddle_rotation_deg = value
			"charge_body_rotation_deg": _def.charge_body_rotation_deg = value
			"charge_hip_coil_deg": _def.charge_hip_coil_deg = value
			"charge_back_foot_load": _def.charge_back_foot_load = value
	field_changed.emit(field, value)
