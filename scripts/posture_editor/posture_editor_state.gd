## Manages posture editor state: current selection, dirty flag, workspace mode.

var _current_def = null
var _current_base_def = null
var _current_id: int = -1
var _is_dirty: bool = false
var _editor_restore_posture_id: int = -1
var _workspace_mode: int = 0  # Workspace.STROKE_POSTURES
var _layout_preset: int = 0  # LayoutPreset.HALF

## Injected references (set via init)
var _library
var _base_pose_library
var _posture_list: ItemList
var _save_button: Button
var _status_label: Label
var _transition_button: Button
var _trigger_pose_button: Button

func init(library, base_pose_library, posture_list, save_button, status_label, transition_button, trigger_pose_button: Button) -> void:
	_library = library
	_base_pose_library = base_pose_library
	_posture_list = posture_list
	_save_button = save_button
	_status_label = status_label
	_transition_button = transition_button
	_trigger_pose_button = trigger_pose_button

func is_base_pose_mode() -> bool:
	return _workspace_mode == 1  # Workspace.BASE_POSES

func current_body_resource():
	return _current_base_def if is_base_pose_mode() else _current_def

func current_display_name() -> String:
	var res = current_body_resource()
	return res.display_name if res != null else ""

func set_dirty(dirty: bool) -> void:
	_is_dirty = dirty
	_update_save_button_state()

func _update_save_button_state() -> void:
	if _save_button == null:
		return
	if _is_dirty:
		_save_button.text = "Save Changes"
		_save_button.add_theme_color_override("font_color", Color(1.0, 0.97, 0.8))
	else:
		_save_button.text = "Save to .tres"
		_save_button.add_theme_color_override("font_color", Color(0.97, 0.98, 1.0))

func filename_for_base_pose(def):
	var base: String = def.display_name.to_lower().replace(" ", "_").replace("-", "_")
	return "%02d_%s.tres" % [def.base_pose_id, base]

func filename_for(def):
	var base: String = def.display_name.to_lower().replace(" ", "_").replace("-", "_")
	return "%02d_%s.tres" % [def.posture_id, base]

func populate_posture_list() -> void:
	_posture_list.clear()
	if is_base_pose_mode():
		for def in _base_pose_library.all_definitions():
			_posture_list.add_item(def.display_name)
	else:
		for def in _library.all_definitions():
			_posture_list.add_item(def.display_name)

func set_current_def(def) -> void:
	_current_def = def

func set_current_base_def(def) -> void:
	_current_base_def = def

func get_current_def():
	return _current_def

func get_current_base_def():
	return _current_base_def

func get_current_id() -> int:
	return _current_id

func set_current_id(id: int) -> void:
	_current_id = id

func get_workspace_mode() -> int:
	return _workspace_mode

func set_workspace_mode(mode: int) -> void:
	_workspace_mode = mode

func get_layout_preset() -> int:
	return _layout_preset

func set_layout_preset(preset: int) -> void:
	_layout_preset = preset

func get_editor_restore_posture_id() -> int:
	return _editor_restore_posture_id

func set_editor_restore_posture_id(id: int) -> void:
	_editor_restore_posture_id = id

func is_dirty() -> bool:
	return _is_dirty

func get_library():
	return _library

func get_base_pose_library():
	return _base_pose_library
