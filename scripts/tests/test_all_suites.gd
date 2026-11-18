class_name TestAllSuites
extends RefCounted
## Runs all test suites and returns results.
## Compatible with godot_run_script: execute(scene_tree) → String summary.
##
## Usage (MCP):
##   run_script -> TestAllSuites.new().execute(get_tree())
##   Then check get_debug_output() for results.
##
## Usage (CLI — same as test_runner.gd):
##   godot --headless --script scripts/tests/test_all_suites.gd

func execute(_scene_tree) -> String:
	var suites: Array = [
		preload("res://scripts/tests/test_base_pose_system.gd").new(),
		preload("res://scripts/tests/test_rally_scorer.gd").new(),
		preload("res://scripts/tests/test_physics_utils.gd").new(),
		preload("res://scripts/tests/test_shot_physics.gd").new(),
		preload("res://scripts/tests/test_shot_physics_shallow.gd").new(),
		preload("res://scripts/tests/test_player_hitting.gd").new(),
		preload("res://scripts/tests/test_ai_trajectory.gd").new(),
		preload("res://scripts/tests/test_posture_zones.gd").new(),
		preload("res://scripts/tests/test_posture_persistence.gd").new(),
		preload("res://scripts/tests/test_posture_editor_controls.gd").new(),
		preload("res://scripts/tests/test_posture_editor_save.gd").new(),
		preload("res://scripts/tests/test_posture_gizmo_standard.gd").new(),
		preload("res://scripts/tests/test_posture_editor_v2_flow.gd").new(),
		preload("res://scripts/tests/test_paddle_reach_and_pose_data.gd").new(),
	]
	var BYPASS_GIZMO_SAVE := OS.has_environment("GODOT_TEST_BYPASS_GIZMO_SAVE") and OS.get_environment("GODOT_TEST_BYPASS_GIZMO_SAVE") == "1"
	if BYPASS_GIZMO_SAVE:
		print("[TESTS] ⊘ test_posture_gizmo_save.gd  (bypassed via GODOT_TEST_BYPASS_GIZMO_SAVE=1)")
	else:
		suites.append(preload("res://scripts/tests/test_posture_gizmo_save.gd").new())
	var totals: Dictionary = {
		"pass": 0,
		"fail": 0,
		"errors": [],
	}

	print("\n━━━ Pickleball Test Suite ━━━")
	for suite in suites:
		suite.run_all(totals)
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	if totals.fail == 0:
		print("[TESTS] ✅  %d passed, 0 failed" % totals.pass)
	else:
		print("[TESTS] ❌  %d passed, %d FAILED" % [totals.pass, totals.fail])
		for err in totals.errors:
			print("  ✗ " + err)

	var summary := "[TESTS] %d passed, %d failed" % [totals.pass, totals.fail]
	return summary
