@tool
extends EditorScript
## Editor-side test runner — runs the pickleball test suite directly from the
## Godot script editor without needing a scene or CLI invocation.
##
## How to run:
##   1. Open this file in the Godot script editor
##   2. Press Ctrl+Shift+X (File menu → "Run" on macOS: Cmd+Shift+X)
##   3. Check the Output dock at the bottom for the test report
##
## Exit: EditorScripts don't affect the running editor — just prints results.
## For CLI/headless runs use scripts/tests/test_runner.gd instead.

# Note: Using different const name to avoid SHADOWED_GLOBAL_IDENTIFIER warning
const _TestRallyScorer := preload("res://scripts/tests/test_rally_scorer.gd")
const _TestBasePoseSystem := preload("res://scripts/tests/test_base_pose_system.gd")

func _run() -> void:
	print("\n━━━ Pickleball Test Suite (editor) ━━━")
	var suites: Array = [
		_TestBasePoseSystem.new(),
		_TestRallyScorer.new(),
	]
	var totals: Dictionary = {
		"pass": 0,
		"fail": 0,
		"errors": [],
	}
	for suite in suites:
		suite.run_all(totals)
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	if totals.fail == 0:
		print("[TESTS] ✅  %d passed, 0 failed" % totals.pass)
	else:
		print("[TESTS] ❌  %d passed, %d FAILED" % [totals.pass, totals.fail])
		for err in totals.errors:
			print("  ✗ " + err)
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
