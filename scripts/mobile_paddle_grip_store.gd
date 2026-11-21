extends RefCounted
## App-private main-grip default only. Full pose/body files remain authoritative.
## A new global generation supersedes older grip choices without rewriting poses.
## Ordinary pose saves stamp this generation atomically in their own document.
const Styles = preload("res://scripts/paddle_grip_styles.gd")
const Posture = preload("res://scripts/posture_definition.gd")
const BodyKey = preload("res://scripts/stroke_body_keyframe.gd")
const DEFAULT_PATH := "user://mobile_paddle_grip_v1.json"
const MAX_FILE_BYTES := 16384
const MAX_GENERATION := 1000000000
static var last_error := ""
static var _test_path := ""
static var _loaded := false
static var _document: Dictionary = {}
static var revision := 0

static func storage_path() -> String:
	return DEFAULT_PATH if _test_path.is_empty() else _test_path

static func set_test_path(path: String) -> Error:
	if path != "" and (not path.begins_with("user://pose_store_tests/") or ".." in path or not path.ends_with(".json")):
		return ERR_INVALID_PARAMETER
	_test_path = path; _loaded = false; _document = {}; revision = 0; last_error = ""
	return OK

static func _empty_document() -> Dictionary:
	return {"version": 1, "revision": 0, "generation": 0, "grip": null, "previous": null}

static func _ensure_loaded() -> void:
	if _loaded: return
	_loaded = true
	var loaded := _read_document()
	_document = loaded.document if loaded.error == OK else _empty_document()
	revision = int(_document.revision)
	if loaded.error != OK: push_warning("MobilePaddleGripStore: " + last_error + "; keeping authored grips")

static func has_global() -> bool:
	_ensure_loaded()
	return _document.grip != null

static func current_generation() -> int:
	_ensure_loaded()
	return int(_document.generation) if has_global() else 0

static func global_rotation() -> float:
	_ensure_loaded()
	return float(_document.grip.main_rotation_deg) if has_global() else 0.0

static func can_undo_global() -> bool:
	_ensure_loaded()
	return _document.previous != null

## Call only for the explicit Set as global paddle grip button.
## Successful persistence precedes all live publication.
static func set_global_from_pose(pose: Resource) -> Error:
	last_error = ""
	if pose == null or pose.get_script() != Posture:
		return _fail(ERR_INVALID_DATA, "Choose a paddle pose first")
	var angle: float = Styles.relative_rotation(pose)
	if not is_finite(angle): return _fail(ERR_INVALID_DATA, "Grip angle is invalid")
	var loaded := _read_document()
	if loaded.error != OK: return loaded.error
	var next: Dictionary = loaded.document.duplicate(true)
	if int(next.revision) >= MAX_GENERATION: return _fail(ERR_OUT_OF_MEMORY, "Grip history limit reached")
	next.previous = {"generation": next.generation, "grip": next.grip}
	next.revision = int(next.revision) + 1
	next.generation = next.revision
	next.grip = {"main_rotation_deg": angle}
	return _commit(next)

static func undo_global() -> Error:
	last_error = ""
	var loaded := _read_document()
	if loaded.error != OK: return loaded.error
	var next: Dictionary = loaded.document.duplicate(true)
	if next.previous == null: return _fail(ERR_DOES_NOT_EXIST, "No global grip change to undo")
	if int(next.revision) >= MAX_GENERATION: return _fail(ERR_OUT_OF_MEMORY, "Grip history limit reached")
	next.grip = next.previous.grip; next.generation = next.previous.generation
	next.previous = null; next.revision = int(next.revision) + 1
	return _commit(next)

static func _commit(next: Dictionary) -> Error:
	# Rebase/Undo must be able to restore the authored grip channels. Validate
	# both raw sources before committing rather than reporting a partial global
	# success if an existing pose file is corrupt or unreadable.
	for path in ["res://scripts/mobile_pose_store.gd", "res://scripts/mobile_serve_pose_store.gd"]:
		var source: Script = load(path)
		var loaded: Dictionary = source._read_document()
		if loaded.error != OK: return _fail(loaded.error, source.last_error + "; global grip was not changed")
	var error := _write_document(next)
	if error != OK: return error
	_document = next; _loaded = true; revision = int(next.revision)
	refresh_live()
	return OK

## Does not save and does not touch body/keyframe channels other than shaft spin.
## force=true means use the current global grip even for an explicit local override.
static func apply_to_definition(def: Resource, force: bool = false) -> void:
	if def == null or def.get_script() != Posture or not has_global(): return
	if not force and int(def.get_meta("mobile_grip_saved_generation", -1)) == current_generation(): return
	var angle := global_rotation()
	# Read all three independent main hand angles before touching Contact.
	for property in ["windup_body", "follow_through_body"]:
		var body: Resource = def.get(property)
		var main: float = float(body.values.get("main_grip_rotation_deg", def.main_grip_rotation_deg)) if body != null else def.main_grip_rotation_deg
		if body == null: body = BodyKey.new(); def.set(property, body)
		body.values["paddle_in_hand_rotation_deg"] = wrapf(main - angle * (-1.0 if def.paddle_hand == 1 else 1.0), -180.0, 180.0)
	Styles.set_relative_rotation(def, angle)
	def.set_meta("mobile_grip_applied_generation", current_generation())

static func source_label(def: Resource) -> String:
	if def == null or def.get_script() != Posture: return ""
	if not has_global(): return "Pose main grip"
	if absf(wrapf(Styles.relative_rotation(def) - global_rotation(), -180.0, 180.0)) < 0.01: return "Global main grip"
	return "Pose main grip override"

## Reload only existing live libraries; never instantiate one as a write side effect.
## Stores rehydrate saved body values into the same resource identities before overlay.
static func refresh_live() -> void:
	var poses: Script = load("res://scripts/posture_library.gd")
	if poses._singleton != null:
		var store: Script = load("res://scripts/mobile_pose_store.gd")
		store.refresh_live_grips(poses._singleton.definitions)
	var serves: Script = load("res://scripts/mobile_serve_pose_store.gd")
	serves.refresh_global_grips()

## After a global Undo, replace only the main-grip channels on a private copy.
## Private body/world-orientation edits remain intact.
static func refresh_copy_grips(def: Resource) -> void:
	if def == null or def.get_script() != Posture: return
	var store: Script = load("res://scripts/mobile_pose_store.gd")
	var live: Resource
	if def.has_meta("mobile_serve_style"):
		var serves: Script = load("res://scripts/mobile_serve_pose_store.gd")
		live = serves.get_def(int(def.get_meta("mobile_serve_style")))
	else:
		var poses: Script = load("res://scripts/posture_library.gd")
		live = poses.instance().get_def(def.posture_id)
	if live == null: return
	store.copy_grip_values(live, def)
	def.set_meta("mobile_grip_saved_generation", int(live.get_meta("mobile_grip_saved_generation", -1)))

static func valid_generation(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(value) and value >= 0 and value <= MAX_GENERATION

static func _valid_grip(value) -> bool:
	return value == null or (value is Dictionary and value.size() == 1 and value.has("main_rotation_deg") and (value.main_rotation_deg is int or value.main_rotation_deg is float) and is_finite(float(value.main_rotation_deg)) and absf(value.main_rotation_deg) <= 180.0)

static func _valid_document(value) -> bool:
	if not value is Dictionary or value.size() != 5 or not value.has_all(["version", "revision", "generation", "grip", "previous"]): return false
	if not (value.version is int or value.version is float) or value.version != 1: return false
	if not valid_generation(value.revision) or not valid_generation(value.generation) or value.generation > value.revision or not _valid_grip(value.grip): return false
	if (value.grip == null) != (value.generation == 0): return false
	if value.previous != null:
		var previous = value.previous
		if not previous is Dictionary or previous.size() != 2 or not previous.has_all(["generation", "grip"]): return false
		if not valid_generation(previous.generation) or previous.generation > value.revision or not _valid_grip(previous.grip): return false
		if (previous.grip == null) != (previous.generation == 0): return false
	return true

static func _read_document() -> Dictionary:
	var path := storage_path()
	if not FileAccess.file_exists(path): return {"error": OK, "document": _empty_document()}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"error": _fail(FileAccess.get_open_error(), "Cannot read saved global grip")}
	if file.get_length() > MAX_FILE_BYTES:
		file.close(); return {"error": _fail(ERR_FILE_CORRUPT, "Saved global grip exceeds the size limit")}
	var json := JSON.new(); var error := json.parse(file.get_as_text()); file.close()
	if error != OK or not _valid_document(json.data): return {"error": _fail(ERR_FILE_CORRUPT, "Saved global grip is invalid; existing file was preserved")}
	return {"error": OK, "document": json.data}

static func _write_document(document: Dictionary) -> Error:
	if not _valid_document(document): return _fail(ERR_INVALID_DATA, "Global grip is invalid")
	var path := storage_path(); var temporary := path + ".tmp"
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK: return _fail(error, "Cannot create the grip save folder")
	var encoded := JSON.stringify(document, "\t", true, true)
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return _fail(FileAccess.get_open_error(), "Cannot write the temporary grip file")
	file.store_string(encoded); file.flush(); error = file.get_error(); file.close()
	if error != OK or FileAccess.get_file_as_string(temporary) != encoded:
		DirAccess.remove_absolute(temporary)
		return _fail(ERR_FILE_CORRUPT if error == OK else error, "Grip write failed; previous save was preserved")
	error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return _fail(error, "Grip replacement failed; previous save was preserved")
	return OK

static func _fail(error: Error, message: String) -> Error:
	last_error = message
	return error
