## Manages posture editor state: current selection, dirty flag, workspace mode.
## Pure state container — no UI widget references. Emits signals on changes.

signal dirty_changed(is_dirty: bool)
signal workspace_changed(mode: int)
signal selection_changed(def, base_def, id: int)

var _current_def = null
var _current_base_def = null
var _current_id: int = -1
var _is_dirty: bool = false
var _editor_restore_posture_id: int = -1
var _workspace_mode: int = 0  # Workspace.STROKE_POSTURES
var _layout_preset: int = 0  # LayoutPreset.HALF
var _preview_context_option_idx: int = 0  # Preview context (Live, Neutral, Incoming, etc.)

## Injected references (set via init)
var _library
var _base_pose_library

func init(library, base_pose_library) -> void:
	_library = library
	_base_pose_library = base_pose_library

func is_base_pose_mode() -> bool:
	return _workspace_mode == 1  # Workspace.BASE_POSES

func current_body_resource():
	return _current_base_def if is_base_pose_mode() else _current_def

func current_display_name() -> String:
	var res = current_body_resource()
	return res.display_name if res != null else ""

func set_dirty(dirty: bool) -> void:
	_is_dirty = dirty
	dirty_changed.emit(dirty)

func populate_posture_list(posture_list: ItemList) -> void:
	if posture_list == null:
		push_warning("PostureEditorState: populate_posture_list called with null ItemList")
		return
	if is_base_pose_mode():
		if _base_pose_library == null:
			push_warning("PostureEditorState: populate_posture_list — _base_pose_library is null")
			return
		posture_list.clear()
		for def in _base_pose_library.all_definitions():
			posture_list.add_item(def.display_name)
	else:
		if _library == null:
			push_warning("PostureEditorState: populate_posture_list — _library is null")
			return
		posture_list.clear()
		for def in _library.all_definitions():
			posture_list.add_item(def.display_name)

func set_current_def(def) -> void:
	_current_def = def
	selection_changed.emit(_current_def, _current_base_def, _current_id)

func set_current_base_def(def) -> void:
	_current_base_def = def
	selection_changed.emit(_current_def, _current_base_def, _current_id)

func get_current_def():
	return _current_def

func get_current_base_def():
	return _current_base_def

func get_current_id() -> int:
	return _current_id

func set_current_id(id: int) -> void:
	_current_id = id
	selection_changed.emit(_current_def, _current_base_def, _current_id)

func get_workspace_mode() -> int:
	return _workspace_mode

func set_workspace_mode(mode: int) -> void:
	_workspace_mode = mode
	workspace_changed.emit(mode)

func get_layout_preset() -> int:
	return _layout_preset

func set_layout_preset(preset: int) -> void:
	_layout_preset = preset

func get_preview_context_option_idx() -> int:
	return _preview_context_option_idx

func set_preview_context_option_idx(idx: int) -> void:
	_preview_context_option_idx = idx

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

func filename_for_base_pose(def) -> String:
	var base: String = def.display_name.to_lower().replace(" ", "_").replace("-", "_")
	return "%02d_%s.tres" % [def.base_pose_id, base]

func filename_for(def) -> String:
	var base: String = def.display_name.to_lower().replace(" ", "_").replace("-", "_")
	return "%02d_%s.tres" % [def.posture_id, base]
