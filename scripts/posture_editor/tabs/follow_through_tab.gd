class_name FollowThroughTab extends VBoxContainer

signal field_changed(field_name: String, value: Variant)

var _def: PostureDefinition = null

var _paddle_off: Vector3Editor
var _paddle_rot: Vector3Editor
var _hip_uncoil: SliderField
var _front_foot_load: SliderField
var _dur_strike: SliderField
var _dur_sweep: SliderField
var _dur_settle: SliderField
var _dur_hold: SliderField
var _ease_opt: OptionButton

func _ready() -> void:
	add_child(_section("Follow-through"))

	_paddle_off = Vector3Editor.new()
	_paddle_off.setup("Paddle offset", 0.01, -0.8, 0.8)
	_paddle_off.value_changed.connect(func(v): _on_field_changed("ft_paddle_offset", v))
	add_child(_paddle_off)

	_paddle_rot = Vector3Editor.new()
	_paddle_rot.setup("Paddle rot °", 1.0, -120.0, 120.0)
	_paddle_rot.value_changed.connect(func(v): _on_field_changed("ft_paddle_rotation_deg", v))
	add_child(_paddle_rot)

	_hip_uncoil = SliderField.new("Hip uncoil °", -60.0, 60.0, 1.0, 0.0)
	_hip_uncoil.value_changed.connect(func(v): _on_field_changed("ft_hip_uncoil_deg", v))
	add_child(_hip_uncoil)

	_front_foot_load = SliderField.new("Front foot load", 0.0, 1.0, 0.01, 0.85)
	_front_foot_load.value_changed.connect(func(v): _on_field_changed("ft_front_foot_load", v))
	add_child(_front_foot_load)

	add_child(_section("Durations (s)"))

	_dur_strike = SliderField.new("Strike", 0.02, 0.4, 0.01, 0.09)
	_dur_strike.value_changed.connect(func(v): _on_field_changed("ft_duration_strike", v))
	add_child(_dur_strike)

	_dur_sweep = SliderField.new("Sweep", 0.05, 0.5, 0.01, 0.18)
	_dur_sweep.value_changed.connect(func(v): _on_field_changed("ft_duration_sweep", v))
	add_child(_dur_sweep)

	_dur_settle = SliderField.new("Settle", 0.05, 0.5, 0.01, 0.15)
	_dur_settle.value_changed.connect(func(v): _on_field_changed("ft_duration_settle", v))
	add_child(_dur_settle)

	_dur_hold = SliderField.new("Hold", 0.02, 0.4, 0.01, 0.12)
	_dur_hold.value_changed.connect(func(v): _on_field_changed("ft_duration_hold", v))
	add_child(_dur_hold)

	var row := HBoxContainer.new()
	var elbl := Label.new()
	elbl.text = "Ease"
	elbl.custom_minimum_size = Vector2(80, 0)
	row.add_child(elbl)
	_ease_opt = OptionButton.new()
	_ease_opt.add_item("ExpoOut")
	_ease_opt.add_item("QuadOut")
	_ease_opt.add_item("SineInOut")
	_ease_opt.item_selected.connect(func(i): _on_field_changed("ft_ease_curve", i))
	_ease_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_ease_opt)
	add_child(row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(spacer)


func _section(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.modulate = Color(0.8, 0.9, 1.0)
	return lbl


func set_definition(def: PostureDefinition) -> void:
	_def = def
	if def == null:
		return
	_paddle_off.set_value(def.ft_paddle_offset)
	_paddle_rot.set_value(def.ft_paddle_rotation_deg)
	_hip_uncoil.set_value(def.ft_hip_uncoil_deg)
	_front_foot_load.set_value(def.ft_front_foot_load)
	_dur_strike.set_value(def.ft_duration_strike)
	_dur_sweep.set_value(def.ft_duration_sweep)
	_dur_settle.set_value(def.ft_duration_settle)
	_dur_hold.set_value(def.ft_duration_hold)
	_ease_opt.select(clampi(def.ft_ease_curve, 0, 2))


func _on_field_changed(field: String, value: Variant) -> void:
	if _def:
		match field:
			"ft_paddle_offset": _def.ft_paddle_offset = value
			"ft_paddle_rotation_deg": _def.ft_paddle_rotation_deg = value
			"ft_hip_uncoil_deg": _def.ft_hip_uncoil_deg = value
			"ft_front_foot_load": _def.ft_front_foot_load = value
			"ft_duration_strike": _def.ft_duration_strike = value
			"ft_duration_sweep": _def.ft_duration_sweep = value
			"ft_duration_settle": _def.ft_duration_settle = value
			"ft_duration_hold": _def.ft_duration_hold = value
			"ft_ease_curve": _def.ft_ease_curve = value
	field_changed.emit(field, value)
