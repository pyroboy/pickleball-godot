extends RefCounted

## Tests for posture editor v2 save/load and PostureLibrary singleton identity.

func run_all(totals: Dictionary) -> void:
	_test_posture_library_singleton_identity(totals)
	_test_posture_library_singleton_mutation_visible(totals)
	_test_save_load_round_trip(totals)
	_test_save_creates_file(totals)


## Verify PostureLibrary.instance() returns the same object repeatedly.
func _test_posture_library_singleton_identity(totals: Dictionary) -> void:
	var a = PostureLibrary.instance()
	var b = PostureLibrary.instance()
	_assert(a == b, "PostureLibrary.instance() returns same object", totals)
	_assert(a != null, "PostureLibrary.instance() is non-null", totals)


## Verify mutating a definition via the singleton is visible from another instance() call.
func _test_posture_library_singleton_mutation_visible(totals: Dictionary) -> void:
	var lib = PostureLibrary.instance()
	var def = lib.get_def(0)  # FOREHAND
	_assert(def != null, "singleton has FOREHAND def", totals)
	var original: float = def.paddle_forehand_mul
	def.paddle_forehand_mul = 99.99
	var lib2 = PostureLibrary.instance()
	var def2 = lib2.get_def(0)
	_assert(def2 != null, "second instance() still has FOREHAND def", totals)
	_assert(def2.paddle_forehand_mul == 99.99, "mutation visible across instance() calls", totals)
	# Restore so later tests aren't polluted
	def.paddle_forehand_mul = original


## Verify a PostureDefinition can be saved and loaded back with correct values.
func _test_save_load_round_trip(totals: Dictionary) -> void:
	var lib = load("res://scripts/posture_library.gd").new()
	var def = lib.get_def(0)
	_assert(def != null, "library has FOREHAND for round-trip", totals)
	
	# Mutate to unique values
	def.paddle_forehand_mul = 0.123
	def.paddle_forward_mul = 0.456
	def.paddle_y_offset = -0.789
	def.zone_x_min = -1.11
	def.zone_x_max = 2.22
	def.zone_y_min = -0.33
	def.zone_y_max = 1.44
	def.zone_forward_offset = 0.99
	
	var tmp_path := "user://test_posture_editor_save_roundtrip.tres"
	var err := ResourceSaver.save(def, tmp_path, ResourceSaver.FLAG_CHANGE_PATH)
	_assert(err == OK, "ResourceSaver.save returns OK (err=%d)" % err, totals)
	
	var loaded: Resource = load(tmp_path)
	_assert(loaded != null, "load() returns non-null resource", totals)
	
	var loaded_def = loaded as PostureDefinition
	_assert(loaded_def != null, "loaded resource is PostureDefinition", totals)
	_assert(loaded_def.paddle_forehand_mul == 0.123, "round-trip paddle_forehand_mul", totals)
	_assert(loaded_def.paddle_forward_mul == 0.456, "round-trip paddle_forward_mul", totals)
	_assert(loaded_def.paddle_y_offset == -0.789, "round-trip paddle_y_offset", totals)
	_assert(loaded_def.zone_x_min == -1.11, "round-trip zone_x_min", totals)
	_assert(loaded_def.zone_x_max == 2.22, "round-trip zone_x_max", totals)
	_assert(loaded_def.zone_y_min == -0.33, "round-trip zone_y_min", totals)
	_assert(loaded_def.zone_y_max == 1.44, "round-trip zone_y_max", totals)
	_assert(loaded_def.zone_forward_offset == 0.99, "round-trip zone_forward_offset", totals)
	
	# Cleanup
	var dir := DirAccess.open("user://")
	if dir:
		dir.remove(tmp_path)


## Verify saving creates an actual file on disk.
func _test_save_creates_file(totals: Dictionary) -> void:
	var lib = load("res://scripts/posture_library.gd").new()
	var def = lib.get_def(18)  # LOW_WIDE_FOREHAND
	_assert(def != null, "library has LOW_WIDE_FOREHAND (18) for file test", totals)
	
	var tmp_path := "user://test_posture_editor_save_file.tres"
	var err := ResourceSaver.save(def, tmp_path, ResourceSaver.FLAG_CHANGE_PATH)
	_assert(err == OK, "save to user:// returns OK (err=%d)" % err, totals)
	
	var exists := FileAccess.file_exists(tmp_path)
	_assert(exists, "saved file exists on disk", totals)
	
	# Cleanup
	var dir := DirAccess.open("user://")
	if dir:
		dir.remove(tmp_path)


func _assert(condition: bool, label: String, totals: Dictionary) -> void:
	if condition:
		totals.pass += 1
		print("  ✓ " + label)
	else:
		totals.fail += 1
		totals.errors.append(label)
		print("  ✗ " + label)
