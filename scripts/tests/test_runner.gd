extends SceneTree











func _init() -> void :



	call_deferred("_run_suites")

func _run_suites() -> void :
	print("\n━━━ Pickleball Test Suite ━━━")
	var BYPASS_GIZMO_SAVE: = OS.has_environment("GODOT_TEST_BYPASS_GIZMO_SAVE") and OS.get_environment("GODOT_TEST_BYPASS_GIZMO_SAVE") == "1"
	var suites: Array = [
		preload("res://scripts/tests/test_body_proportions.gd").new(), 
		preload("res://scripts/tests/test_paddle_clearance.gd").new(), 
		preload("res://scripts/tests/test_contact_and_pose_blend.gd").new(), 
		preload("res://scripts/tests/test_explicit_shot_aim.gd").new(), 
		preload("res://scripts/tests/test_spin_profiles.gd").new(), 
		preload("res://scripts/tests/test_player_leg_ik.gd").new(), 
		preload("res://scripts/tests/test_drive_serve_motion.gd").new(), 
		preload("res://scripts/tests/test_serve_styles.gd").new(), 
		preload("res://scripts/tests/test_control_bindings.gd").new(), 
		preload("res://scripts/tests/test_aim_controller.gd").new(), 
		preload("res://scripts/tests/test_incoming_ready_motion.gd").new(), 
		preload("res://scripts/tests/test_stroke_orientation.gd").new(), 
		preload("res://scripts/tests/test_base_pose_system.gd").new(), 
		preload("res://scripts/tests/test_rally_scorer.gd").new(), 
		preload("res://scripts/tests/test_physics_utils.gd").new(), 
		preload("res://scripts/tests/test_shot_physics.gd").new(), 
		preload("res://scripts/tests/test_shot_physics_shallow.gd").new(), 
		preload("res://scripts/tests/test_player_hitting.gd").new(), 
		preload("res://scripts/tests/test_posture_zones.gd").new(), 
		preload("res://scripts/tests/test_posture_persistence.gd").new(), 
		preload("res://scripts/tests/test_posture_editor_controls.gd").new(), 
		preload("res://scripts/tests/test_posture_editor_save.gd").new(), 
		preload("res://scripts/tests/test_posture_gizmo_standard.gd").new(), 
		preload("res://scripts/tests/test_posture_editor_v2_flow.gd").new(), 
		preload("res://scripts/tests/test_paddle_reach_and_pose_data.gd").new(), 
		preload("res://scripts/tests/test_ai_trajectory.gd").new(), 
	]
	if BYPASS_GIZMO_SAVE:
		print("[TESTS] ⊘ test_posture_gizmo_save.gd  (bypassed via GODOT_TEST_BYPASS_GIZMO_SAVE=1)")
	else:
		suites.append(preload("res://scripts/tests/test_posture_gizmo_save.gd").new())
	var totals: Dictionary = {
		"pass": 0, 
		"fail": 0, 
		"errors": [], 
	}
	for suite in suites:
		suite.run_all(totals)
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	if totals.fail == 0:
		print("[TESTS] ✅  %d passed, 0 failed" % totals.pass)
	else:
		print("[TESTS] ❌  %d passed, %d FAILED" % [totals.pass, totals.fail])
		for err in totals.errors:
			print("  ✗ " + err)

	await process_frame
	await process_frame
	quit(0 if totals.fail == 0 else 1)
