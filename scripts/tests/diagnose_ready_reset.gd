extends "res://scripts/tests/test_menu_reset_first_rally.gd"


var reset_trace: Array = []
var recording_reset: = false
func record(frame: int):
	super.record(frame)
	if not recording_reset: return
	var p = game.player_right; var ik = p.leg_ik
	var pose = p.posture.transition_pose_blend if p.posture.transition_pose_blend != null else p.get_runtime_posture_def()
	var body = p.body_pivot
	reset_trace.append({"frame": frame, "pose": pose.posture_id, "crouch": pose.crouch_amount, 
		"body_y": body.global_position.y, "body_rotation": str(body.global_rotation), "fit_offset": str(ik.hip_shift_applied), 
		"right_foot": str(ik.right_foot_smooth), "left_foot": str(ik.left_foot_smooth), "right_target": str(ik.right_step_target), "left_target": str(ik.left_step_target), 
		"locked": [ik.right_foot_locked, ik.left_foot_locked], "active_side": ik._active_side, "step_progress": ik._live_step_progress, "run_active": ik._run_active, "run_stopping": ik._run_stopping, 
		"velocity": str(p.current_velocity), "serving_visual": p.hitting.serving_visual_active, "base_pose_state": p.pose_controller.base_pose_state, 
		"incoming_override": p.ai_brain.incoming_pose_override != null, "between_owner": p._between_point_owner() != null, 
		"shoulder_actual": str(p.right_arm_node.upper_pivot.global_position), "shoulder_query": str(preload("res://scripts/stroke_body_pose.gd").shoulder_world(p, pose)), 
		"support_wrist_channels": metrics.samples[-1].opponent.arms[1].anatomical_channels, 
		"support_forearm_clearance": metrics.samples[-1].opponent.limb_clearance_m["1_forearm"]})
func run():
	create_timer(90).timeout.connect( func(): push_error("Ready reset diagnostic timeout");quit(2))
	late = LateFrame.new();late.process_priority = 20000;late.process_mode = Node.PROCESS_MODE_ALWAYS;root.add_child(late)
	metrics = load("res://scripts/debug/pose_simulation_review.gd").new();metrics.surface = Geometry.sample_head_surface()
	issues = []
	if not await title_match(): quit(2);return
	if not await open_practice(): quit(2);return
	check(press_named(game.practice_panel._content, "Watch fast-hands demo"), "actual Fast Hands button")
	await observe_practice("Fast Hands initial")
	issues = []
	if not await open_practice(): quit(2);return
	check(press_named(game.practice_panel._content, "Repeat current drill"), "actual Repeat button")
	await observe_practice("Fast Hands repeat")
	issues = []
	if not await open_practice(): quit(2);return
	check(press_named(game.practice_panel._content, "Return to match"), "actual Return button")
	recording_reset = true
	await ordinary_serve("Fast Hands return to match")
	var file: = FileAccess.open("/workspace/shared/pickleball-hands/ready-reset-diagnostic.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"trace": reset_trace, "results": results, "checks": checks}, "\t"));file.close()
	print("READY RESET DIAGNOSTIC ", checks, " checks, ", issues.size(), " final issues")
	Input.action_release("ui_accept");metrics.free();game.queue_free();late.queue_free(); await process_frame;quit(0 if issues.is_empty() else 1)
