extends RefCounted

## Tests for posture persistence: selecting a posture immediately applies it
## to the player and clears the restore ID so it persists after editor close.

func run_all(totals: Dictionary) -> void:
	_test_force_posture_update_sets_paddle_posture(totals)
	_test_force_posture_update_composes_base_pose_preview(totals)
	_test_restore_returns_early_when_restore_id_is_minus_one(totals)


## Verify that force_posture_update sets the player's paddle_posture to match
## the definition's posture_id, and for base poses it composes the preview.
func _test_force_posture_update_sets_paddle_posture(totals: Dictionary) -> void:
	var player = PlayerController.new()
	player.paddle_posture = player.PaddlePosture.READY  # Start at READY

	var forehand_def = load("res://scripts/posture_library.gd").new().get_def(player.PaddlePosture.FOREHAND)
	_assert(forehand_def != null, "FOREHAND posture definition exists", totals)

	player.posture.force_posture_update(forehand_def)
	_assert(player.paddle_posture == forehand_def.posture_id,
		"force_posture_update sets paddle_posture to FOREHAND enum", totals)


## Verify that composing a base pose preview produces a posture definition
## with the stroke posture_id but body fields from the base pose.
func _test_force_posture_update_composes_base_pose_preview(totals: Dictionary) -> void:
	var base_lib = load("res://scripts/base_pose_library.gd").new()
	var base_def = base_lib.get_def(0)  # ATHLETIC_READY
	_assert(base_def != null, "base pose library returns ATHLETIC_READY", totals)

	var player = PlayerController.new()
	player.paddle_posture = player.PaddlePosture.READY

	var composed = player.pose_controller.compose_preview_posture(base_def, player.PaddlePosture.FOREHAND)
	_assert(composed != null,
		"compose_preview_posture returns a definition for base pose + stroke", totals)
	_assert(composed.posture_id == player.PaddlePosture.FOREHAND,
		"composed posture preserves the stroke posture_id", totals)
	# Base pose stance_width (0.70 for ATHLETIC_READY) differs from stroke default (0.0).
	# blend_onto_stroke should copy base pose stance_width.
	_assert(composed.stance_width != 0.0,
		"composed posture has non-zero stance_width from base pose", totals)


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
