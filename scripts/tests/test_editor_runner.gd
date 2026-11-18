@tool
extends EditorScript











const _TestBasePoseSystem: = preload("res://scripts/tests/test_base_pose_system.gd")
const _TestRallyScorer: = preload("res://scripts/tests/test_rally_scorer.gd")
const _TestPhysicsUtils: = preload("res://scripts/tests/test_physics_utils.gd")
const _TestShotPhysics: = preload("res://scripts/tests/test_shot_physics.gd")
const _TestShotPhysicsShallow: = preload("res://scripts/tests/test_shot_physics_shallow.gd")
const _TestPlayerHitting: = preload("res://scripts/tests/test_player_hitting.gd")
const _TestAITrajectory: = preload("res://scripts/tests/test_ai_trajectory.gd")
const _TestPostureZones: = preload("res://scripts/tests/test_posture_zones.gd")
const _TestPosturePersistence: = preload("res://scripts/tests/test_posture_persistence.gd")
const _TestPostureEditorControls: = preload("res://scripts/tests/test_posture_editor_controls.gd")
const _TestPostureEditorSave: = preload("res://scripts/tests/test_posture_editor_save.gd")
const _TestPostureGizmoSave: = preload("res://scripts/tests/test_posture_gizmo_save.gd")
const _TestPostureGizmoStandard: = preload("res://scripts/tests/test_posture_gizmo_standard.gd")
const _TestPostureEditorV2Flow: = preload("res://scripts/tests/test_posture_editor_v2_flow.gd")

func _run() -> void :
	print("\n━━━ Pickleball Test Suite (editor) ━━━")
	var suites: Array = [
		_TestBasePoseSystem.new(), 
		_TestRallyScorer.new(), 
		_TestPhysicsUtils.new(), 
		_TestShotPhysics.new(), 
		_TestShotPhysicsShallow.new(), 
		_TestPlayerHitting.new(), 
		_TestAITrajectory.new(), 
		_TestPostureZones.new(), 
		_TestPosturePersistence.new(), 
		_TestPostureEditorControls.new(), 
		_TestPostureEditorSave.new(), 
		_TestPostureGizmoStandard.new(), 
		_TestPostureEditorV2Flow.new(), 
	]
	var BYPASS_GIZMO_SAVE: = OS.has_environment("GODOT_TEST_BYPASS_GIZMO_SAVE") and OS.get_environment("GODOT_TEST_BYPASS_GIZMO_SAVE") == "1"
	if BYPASS_GIZMO_SAVE:
		print("[TESTS] ⊘ test_posture_gizmo_save.gd  (bypassed via GODOT_TEST_BYPASS_GIZMO_SAVE=1)")
	else:
		suites.append(_TestPostureGizmoSave.new())
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
