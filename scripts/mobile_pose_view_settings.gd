extends RefCounted
## Editor-only visual preference, deliberately separate from authored pose data.
const DEFAULT_INBETWEEN_COUNT := 2
const MAX_INBETWEEN_COUNT := 6
const DEFAULT_PATH := "user://mobile_pose_view_v1.json"
static var _test_path := ""

static func storage_path() -> String:
	return DEFAULT_PATH if _test_path.is_empty() else _test_path

static func set_test_path(path: String) -> Error:
	if path != "" and (not path.begins_with("user://pose_store_tests/") or ".." in path or not path.ends_with(".json")):
		return ERR_INVALID_PARAMETER
	_test_path = path
	return OK

static func load_inbetween_count() -> int:
	var data := _load_data()
	var value = data.get("inbetween_per_gap")
	if not value is float and not value is int: return DEFAULT_INBETWEEN_COUNT
	if not is_finite(float(value)) or float(value) != floorf(float(value)): return DEFAULT_INBETWEEN_COUNT
	return clampi(int(value), 0, MAX_INBETWEEN_COUNT)

static func _load_data() -> Dictionary:
	var file := FileAccess.open(storage_path(), FileAccess.READ)
	if file == null or file.get_length() > 4096: return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK: return {}
	var data = parser.data
	return data if data is Dictionary and data.get("version") == 1 else {}

static func load_gizmo() -> Dictionary:
	var data := _load_data()
	return {"mode": 1 if data.get("gizmo_mode") == 1 else 0, "shown": data.get("gizmo_shown", true) != false}

static func save_gizmo(mode: int, shown: bool) -> Error:
	var data := _load_data()
	data.gizmo_mode = clampi(mode, 0, 1); data.gizmo_shown = shown
	return _save_data(data)

static func save_inbetween_count(value: int) -> Error:
	var data := _load_data()
	data.inbetween_per_gap = clampi(value, 0, MAX_INBETWEEN_COUNT)
	return _save_data(data)

static func _save_data(data: Dictionary) -> Error:
	data.version = 1
	var path := storage_path()
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK: return error
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	file.flush(); error = file.get_error(); file.close()
	if error != OK: return error
	return DirAccess.rename_absolute(path + ".tmp", path)
