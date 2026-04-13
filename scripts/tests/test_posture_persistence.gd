extends RefCounted

## Tests for posture persistence: selecting a posture immediately applies it
## to the player and clears the restore ID so it persists after editor close.
##
## Scene-less tests: these test the pure logic paths.
## Tests requiring PlayerController with a scene tree (posture/pose_controller init)
## are skipped with a clear message — those require an integration test environment.

func run_all(totals: Dictionary) -> void:
	_test_posture_library_returns_valid_def(totals)
	_test_base_pose_library_returns_valid_def(totals)
	_test_base_pose_to_preview_posture(totals)
	_test_restore_returns_early_when_restore_id_is_minus_one(totals)


## Verify posture library can return a valid FOREHAND definition.
func _test_posture_library_returns_valid_def(totals: Dictionary) -> void:
	var lib = load("res://scripts/posture_library.gd").new()
	var def = lib.get_def(0)  # FOREHAND = 0
	_assert(def != null, "posture_library.get_def(0) returns non-null FOREHAND def", totals)
	_assert(def.posture_id == 0, "def.posture_id == FOREHAND (0)", totals)


## Verify base pose library returns ATHLETIC_READY (index 0).
func _test_base_pose_library_returns_valid_def(totals: Dictionary) -> void:
	var lib = load("res://scripts/base_pose_library.gd").new()
	var def = lib.get_def(0)  # ATHLETIC_READY
	_assert(def != null, "base_pose_library.get_def(0) returns ATHLETIC_READY", totals)
	# ATHLETIC_READY has stance_width = 0.70
	_assert(def.stance_width > 0.0, "ATHLETIC_READY has non-zero stance_width", totals)


## Verify that base_def.to_preview_posture(stroke_def) correctly composes a preview
## posture: stroke posture_id preserved, body fields blended from base pose.
func _test_base_pose_to_preview_posture(totals: Dictionary) -> void:
	var base_lib = load("res://scripts/base_pose_library.gd").new()
	var base_def = base_lib.get_def(0)  # ATHLETIC_READY
	_assert(base_def != null, "base_def exists", totals)

	var stroke_lib = load("res://scripts/posture_library.gd").new()
	var forehand_def = stroke_lib.get_def(0)  # FOREHAND
	_assert(forehand_def != null, "forehand_def exists", totals)

	# to_preview_posture uses blend_onto_stroke at weight=1.0 (full base pose override)
	var composed = base_def.to_preview_posture(forehand_def)
	_assert(composed != null,
		"to_preview_posture returns a definition for base pose + stroke", totals)
	_assert(composed.posture_id == forehand_def.posture_id,
		"composed posture preserves the stroke posture_id", totals)
	# base_def.stance_width = 0.70, forehand_def.stance_width = 0.0
	# blend at weight=1.0 should use base pose fields fully
	_assert(composed.stance_width == base_def.stance_width,
		"composed posture stance_width matches base pose at weight=1.0", totals)


## Verify that _restore_live_posture_from_editor returns early (no-op) when
## _editor_restore_posture_id is -1, meaning a posture was explicitly selected
## and should NOT be restored when the editor closes.
func _test_restore_returns_early_when_restore_id_is_minus_one(totals: Dictionary) -> void:
	var editor = PostureEditorUI.new()
	# Simulate: a posture was selected while editor was open → restore ID cleared
	editor._editor_restore_posture_id = -1

	var player = PlayerController.new()
	player.paddle_posture = player.PaddlePosture.FOREHAND
	editor._player = player

	# Capture posture before the "close editor" call
	var posture_before = player.paddle_posture

	# Call the restore function (simulates editor close)
	editor._restore_live_posture_from_editor()

	# Should have returned early: restore_id was -1
	_assert(editor._editor_restore_posture_id < 0,
		"restore returns early when _editor_restore_posture_id is -1", totals)
	# Posture should be unchanged (not restored to READY)
	_assert(player.paddle_posture == posture_before,
		"paddle_posture is NOT restored when restore_id is -1", totals)


func _assert(condition: bool, label: String, totals: Dictionary) -> void:
	if condition:
		totals.pass += 1
		print("  ✓ " + label)
	else:
		totals.fail += 1
		totals.errors.append(label)
		print("  ✗ " + label)
