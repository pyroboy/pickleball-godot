extends RefCounted









const PATH: = "user://test_posture_gizmo_temp.tres"

func run_all(totals: Dictionary) -> void :
	if OS.has_environment("GODOT_TEST_BYPASS_GIZMO_SAVE"):
		print("  SKIPPED (bypass)")
		return
	_test_paddle_offset_axis_projection(totals)
	_test_paddle_field_round_trip(totals)
	_test_dirty_tracking_marks_def_dirty(totals)











func _test_paddle_offset_axis_projection(totals: Dictionary) -> void :
	var forehand_axis: = Vector3(1, 0, 0)
	var forward_axis: = Vector3(0, 0, 1)
	var offset: = Vector3(0.5, 0.3, 1.0)

	var forehand_mul: = offset.dot(forehand_axis)
	var forward_mul: = offset.dot(forward_axis)
	var y_offset: = offset.y

	_assert(is_equal_approx(forehand_mul, 0.5), "forehand_mul dot = 0.5 (got %.4f)" % forehand_mul, totals)
	_assert(is_equal_approx(forward_mul, 1.0), "forward_mul  dot = 1.0 (got %.4f)" % forward_mul, totals)
	_assert(is_equal_approx(y_offset, 0.3), "y_offset     = 0.3 (got %.4f)" % y_offset, totals)




func _test_paddle_field_round_trip(totals: Dictionary) -> void :
	var lib = load("res://scripts/posture_library.gd").new()
	var def: PostureDefinition = lib.get_def(0)
	_assert(def != null, "library has FOREHAND for round-trip", totals)

	def.paddle_forehand_mul = 0.123
	def.paddle_forward_mul = 0.456
	def.paddle_y_offset = -0.789

	var err: = ResourceSaver.save(def, PATH, ResourceSaver.FLAG_CHANGE_PATH)
	_assert(err == OK, "ResourceSaver.save returns OK (err=%d)" % err, totals)

	var loaded: Resource = load(PATH)
	_assert(loaded != null, "load() returns non-null", totals)

	var loaded_def: = loaded as PostureDefinition
	_assert(loaded_def != null, "loaded resource is PostureDefinition", totals)
	_assert(is_equal_approx(loaded_def.paddle_forehand_mul, 0.123), "round-trip paddle_forehand_mul", totals)
	_assert(is_equal_approx(loaded_def.paddle_forward_mul, 0.456), "round-trip paddle_forward_mul", totals)
	_assert(is_equal_approx(loaded_def.paddle_y_offset, -0.789), "round-trip paddle_y_offset", totals)


	DirAccess.open("user://").remove(PATH)



func _test_dirty_tracking_marks_def_dirty(totals: Dictionary) -> void :
	var editor = load("res://scripts/posture_editor_v2.gd").new()
	var lib = load("res://scripts/posture_library.gd").new()
	var def: PostureDefinition = lib.get_def(0)
	_assert(def != null, "library has FOREHAND for dirty test", totals)

	editor._current_def = def
	editor._is_base_pose_mode = false
	editor._mark_dirty()

	_assert( not editor._dirty_defs.is_empty(), "_dirty_defs is not empty after _mark_dirty()", totals)
	_assert(editor._dirty_defs.has(0), "_dirty_defs has posture_id 0", totals)
	_assert(editor._dirty_defs.get(0) == def, "_dirty_defs[0] is the same def object", totals)
	editor.free()


func _assert(condition: bool, label: String, totals: Dictionary) -> void :
	if condition:
		totals.pass += 1
		print("  ✓ " + label)
	else:
		totals.fail += 1
		totals.errors.append(label)
		print("  ✗ " + label)
