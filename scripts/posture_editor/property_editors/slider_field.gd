class_name SliderField extends VBoxContainer

## Reusable slider with label and value display

signal value_changed(new_value: float)

var _label: Label
var _slider: HSlider
var _spin: SpinBox

func _init(label_text: String, min_val: float, max_val: float, step: float, default_val: float) -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	# Label
	_label = Label.new()
	_label.text = label_text
	_label.add_theme_font_size_override("font_size", 13)
	_label.modulate = Color(0.88, 0.92, 0.98)
	add_child(_label)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	# Slider
	_slider = HSlider.new()
	_slider.min_value = min_val
	_slider.max_value = max_val
	_slider.step = step
	_slider.value = default_val
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_slider)
	
	# Spin box for precise input
	_spin = SpinBox.new()
	_spin.min_value = min_val
	_spin.max_value = max_val
	_spin.step = step
	_spin.value = default_val
	_spin.custom_minimum_size = Vector2(88, 0)
	row.add_child(_spin)
	
	# Connect signals
	_slider.value_changed.connect(_on_slider_changed)
	_spin.value_changed.connect(_on_spin_changed)

func _on_slider_changed(val: float) -> void:
	_spin.value = val
	value_changed.emit(val)

func _on_spin_changed(val: float) -> void:
	_slider.value = val
	value_changed.emit(val)

func set_value(val: float) -> void:
	_slider.value = val
	_spin.value = val

func get_value() -> float:
	return _slider.value
