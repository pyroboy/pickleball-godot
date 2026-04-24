@tool
extends Control
class_name PostureEditorDock

signal posture_selected(definition)
signal posture_changed(definition)

var _library: RefCounted
var _definitions: Array = []
var _selected_def = null
var _is_dirty: bool = false

var _posture_dropdown: OptionButton
var _status_label: Label
var _save_button: Button
var _warning_label: Label

# Property editors
var _zone_x_min: SpinBox
var _zone_x_max: SpinBox
var _zone_y_min: SpinBox
var _zone_y_max: SpinBox
var _paddle_fh: SpinBox
var _paddle_fwd: SpinBox
var _paddle_y: SpinBox

func _init() -> void:
	name = "PostureEditorDock"

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	var title := Label.new()
	title.text = "Posture Editor"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	_warning_label = Label.new()
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning_label.modulate = Color(1, 0.8, 0.2)
	vbox.add_child(_warning_label)

	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)

	var posture_label := Label.new()
	posture_label.text = "Posture:"
	hbox.add_child(posture_label)

	_posture_dropdown = OptionButton.new()
	_posture_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_posture_dropdown.item_selected.connect(_on_posture_selected)
	hbox.add_child(_posture_dropdown)

	# Zone section
	vbox.add_child(_section_label("Zone Bounds"))
	var zone_grid := GridContainer.new()
	zone_grid.columns = 2
	vbox.add_child(zone_grid)

	_zone_x_min = _add_spinbox(zone_grid, "X Min", -10.0, 10.0, 0.01)
	_zone_x_max = _add_spinbox(zone_grid, "X Max", -10.0, 10.0, 0.01)
	_zone_y_min = _add_spinbox(zone_grid, "Y Min", -5.0, 5.0, 0.01)
	_zone_y_max = _add_spinbox(zone_grid, "Y Max", -5.0, 5.0, 0.01)

	# Paddle section
	vbox.add_child(_section_label("Paddle Position"))
	var paddle_grid := GridContainer.new()
	paddle_grid.columns = 2
	vbox.add_child(paddle_grid)

	_paddle_fh = _add_spinbox(paddle_grid, "Forehand Mul", -5.0, 5.0, 0.01)
	_paddle_fwd = _add_spinbox(paddle_grid, "Forward Mul", -5.0, 5.0, 0.01)
	_paddle_y = _add_spinbox(paddle_grid, "Y Offset", -5.0, 5.0, 0.01)

	# Save button
	_save_button = Button.new()
	_save_button.text = "Save"
	_save_button.disabled = true
	_save_button.pressed.connect(_on_save)
	vbox.add_child(_save_button)

	_status_label = Label.new()
	_status_label.text = "Loading..."
	vbox.add_child(_status_label)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	_load_library()

func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	return label

func _add_spinbox(parent: Node, label_text: String, min_val: float, max_val: float, step: float) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = step
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.value_changed.connect(_on_property_changed)
	parent.add_child(spin)
	return spin

func _load_library() -> void:
	var PostureLibraryClass = preload("res://scripts/posture_library.gd")
	_library = PostureLibraryClass.new()
	_definitions = _library.all_definitions()

	if _definitions.is_empty():
		_warning_label.text = "No posture definitions found! Run the game once to generate defaults."
		_status_label.text = "No postures loaded"
		return

	for i in range(_definitions.size()):
		var def = _definitions[i]
		var name_text: String = def.display_name if def.display_name != "" else "Posture_%d" % def.posture_id
		_posture_dropdown.add_item(name_text, i)

	if _posture_dropdown.item_count > 0:
		_posture_dropdown.select(0)
		_on_posture_selected(0)

func _on_posture_selected(index: int) -> void:
	if index < 0 or index >= _definitions.size():
		return
	_selected_def = _definitions[index]
	_update_ui()
	posture_selected.emit(_selected_def)

func _update_ui() -> void:
	if _selected_def == null:
		return

	_zone_x_min.set_value_no_signal(_selected_def.zone_x_min)
	_zone_x_max.set_value_no_signal(_selected_def.zone_x_max)
	_zone_y_min.set_value_no_signal(_selected_def.zone_y_min)
	_zone_y_max.set_value_no_signal(_selected_def.zone_y_max)

	_paddle_fh.set_value_no_signal(_selected_def.paddle_forehand_mul)
	_paddle_fwd.set_value_no_signal(_selected_def.paddle_forward_mul)
	_paddle_y.set_value_no_signal(_selected_def.paddle_y_offset)

	var path: String = _selected_def.resource_path
	if path == "":
		path = "(memory — not saved)"
	_status_label.text = "%s  |  %s" % [_selected_def.display_name, path]
	_is_dirty = false
	_save_button.disabled = true

func _on_property_changed(_value: float) -> void:
	if _selected_def == null:
		return

	_selected_def.zone_x_min = _zone_x_min.value
	_selected_def.zone_x_max = _zone_x_max.value
	_selected_def.zone_y_min = _zone_y_min.value
	_selected_def.zone_y_max = _zone_y_max.value

	_selected_def.paddle_forehand_mul = _paddle_fh.value
	_selected_def.paddle_forward_mul = _paddle_fwd.value
	_selected_def.paddle_y_offset = _paddle_y.value

	_is_dirty = true
	_save_button.disabled = false
	posture_changed.emit(_selected_def)

func _on_save() -> void:
	if _selected_def == null:
		return
	var path: String = _selected_def.resource_path
	if path == "":
		var safe_name: String = _selected_def.display_name.replace(" ", "_").replace("/", "_")
		path = "res://data/postures/%s.tres" % safe_name
	# Ensure directory exists
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var err_mkdir := DirAccess.make_dir_recursive_absolute(dir_path)
		if err_mkdir != OK:
			_status_label.text = "Failed to create directory: %s" % dir_path
			return
	var err := ResourceSaver.save(_selected_def, path)
	if err == OK:
		_selected_def.resource_path = path
		_is_dirty = false
		_save_button.disabled = true
		_status_label.text = "%s saved to %s" % [_selected_def.display_name, path]
	else:
		_status_label.text = "Save failed: error %d" % err

func get_selected_definition():
	return _selected_def

func mark_dirty() -> void:
	_is_dirty = true
	_save_button.disabled = false

func sync_from_definition() -> void:
	_update_ui()
