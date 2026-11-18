extends RefCounted








func run_all(totals: Dictionary) -> void :
	_test_posture_library_returns_valid_def(totals)
	_test_base_pose_library_returns_valid_def(totals)
	_test_base_pose_to_preview_posture(totals)
	_test_restore_returns_early_when_restore_id_is_minus_one(totals)



func _test_posture_library_returns_valid_def(totals: Dictionary) -> void :
	var lib = load("res://scripts/posture_library.gd").new()
	var def = lib.get_def(0)
	_assert(def != null, "posture_library.get_def(0) returns non-null FOREHAND def", totals)
	_assert(def.posture_id == 0, "def.posture_id == FOREHAND (0)", totals)



func _test_base_pose_library_returns_valid_def(totals: Dictionary) -> void :
	var lib = load("res://scripts/base_pose_library.gd").new()
	var def = lib.get_def(0)
	_assert(def != null, "base_pose_library.get_def(0) returns ATHLETIC_READY", totals)

	_assert(def.stance_width > 0.0, "ATHLETIC_READY has non-zero stance_width", totals)




func _test_base_pose_to_preview_posture(totals: Dictionary) -> void :
	var base_lib = load("res://scripts/base_pose_library.gd").new()
	var base_def = base_lib.get_def(0)
	_assert(base_def != null, "base_def exists", totals)

	var stroke_lib = load("res://scripts/posture_library.gd").new()
	var forehand_def = stroke_lib.get_def(0)
	_assert(forehand_def != null, "forehand_def exists", totals)


	var composed = base_def.to_preview_posture(forehand_def)
	_assert(composed != null, 
		"to_preview_posture returns a definition for base pose + stroke", totals)
	_assert(composed.posture_id == forehand_def.posture_id, 
		"composed posture preserves the stroke posture_id", totals)


	_assert(composed.stance_width == base_def.stance_width, 
		"composed posture stance_width matches base pose at weight=1.0", totals)





func _test_restore_returns_early_when_restore_id_is_minus_one(totals: Dictionary) -> void :

	var preview = load("res://scripts/posture_editor/posture_editor_preview.gd").new()
	var StateClass = load("res://scripts/posture_editor/posture_editor_state.gd")
	preview._state = StateClass.new()

	preview._state.set_editor_restore_posture_id(-1)

	var player = PlayerController.new()
	player.paddle_posture = player.PaddlePosture.FOREHAND
	preview._player = player


	var posture_before = player.paddle_posture


	preview.restore_live_posture_from_editor()


	_assert(preview._state.get_editor_restore_posture_id() < 0, 
		"restore returns early when _editor_restore_posture_id is -1", totals)

	_assert(player.paddle_posture == posture_before, 
		"paddle_posture is NOT restored when restore_id is -1", totals)
	player.free()


func _assert(condition: bool, label: String, totals: Dictionary) -> void :
	if condition:
		totals.pass += 1
		print("  ✓ " + label)
	else:
		totals.fail += 1
		totals.errors.append(label)
		print("  ✗ " + label)
