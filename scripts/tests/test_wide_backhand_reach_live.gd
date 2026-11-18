extends SceneTree
const Store = preload("res://scripts/mobile_pose_store.gd")
const GripStore = preload("res://scripts/mobile_paddle_grip_store.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Profile = preload("res://scripts/wide_backhand_reach_profile.gd")
const D = preload("res://scripts/paddle_dimensions.gd")
var game
var checks := 0
var failures: Array[String] = []
var phases: Dictionary = {}
var maxima := {"main_ratio":0.0,"support_ratio":0.0,"paddle_delta_m":0.0,"basis_delta":0.0,"grip_error_m":0.0,"body_shift_m":0.0,"leg_ratio":0.0}
var measured := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		if failures.size() < 20: push_error(message)
		failures.append(message)
func run() -> void:
	Store.set_test_path("user://pose_store_tests/wide_backhand_live_"+str(OS.get_process_id())+"/poses.json")
	GripStore.set_test_path("user://pose_store_tests/wide_backhand_live_"+str(OS.get_process_id())+"/grips.json")
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.reaction_button.auto_fire_on_perfect = false
	game.pvp_mode = true; game.aim_focus._sync_realtime_mode()
	var p = game.player_left
	for hold in [.12, .6, 1.2]:
		Input.action_release("ui_accept"); game.input_handler.cancel_charge_input()
		game.between_point_controller.cancel()
		game._set_game_state(game.GameState.PLAYING)
		p.global_position = Vector3(0, p.ground_y, 3.8)
		p.current_velocity = Vector3.ZERO
		if p.posture.human_contact == null: p.posture.human_contact = load("res://scripts/human_contact_controller.gd").new(p, p.posture)
		var h = p.posture.human_contact
		h.cancel(false)
		var b = game.ball
		b.reset_rally_state(); b.both_bounces_complete = true; b.bounces_since_last_hit = 1
		b.is_in_play = true; b.last_hit_by = 1; b.flight_id += 1
		b.global_position = Vector3(.65, 1.0, 2.5); b.linear_velocity = Vector3(0, 0, 4)
		h._flight_id = b.flight_id
		var def: PostureDefinition = PostureLibrary.instance().get_def(11)
		h.contact = {"posture":11,"def":def,"time":2.0,"point":b.global_position,"bounces":0}
		h.visual_pose = h._ready_pose(0.0); h._apply_visual()
		p.leg_ik.feet_initialized = false
		Input.action_press("ui_accept"); game.input_handler._handle_swing_charge(0.0)
		for tick in range(ceili(hold*120.0)):
			game.input_handler._handle_swing_charge(1.0/120.0)
			refresh_and_measure(p,h,"held")
		Input.action_release("ui_accept"); game.input_handler._handle_swing_charge(0.0)
		check(h.phase == 0, "actual input release queues selected Wide Backhand")
		h.contact.time = .1
		for tick in range(240):
			h._advance_swing(1.0/120.0,b)
			refresh_and_measure(p,h,"committed")
			if h.phase < 0: break
		check(phases.has(1) and phases.has(2) and phases.has(3), "actual controller crosses strike, sweep, finish phases")
		check(h.phase < 0, "actual controller completes recovery")
	Input.action_release("ui_accept"); game.input_handler.cancel_charge_input()
	check(measured > 100, "actual held/committed rig was measured densely")
	print("[WIDE BACKHAND LIVE REACH] %d checks, %d failures; samples=%d phases=%s" % [checks,failures.size(),measured,str(phases.keys())])
	print(JSON.stringify(maxima))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			var file := FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE)
			file.store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":measured,"phases":phases.keys(),"maxima":maxima},"\t",true,true));file.close()
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self,game)
	quit(0 if failures.is_empty() else 1)
func refresh_and_measure(p,h,label:String) -> void:
	var pose: PostureDefinition = h.visual_pose
	if pose == null: return
	p.leg_ik.update_leg_ik(1.0/120.0,pose)
	p.arm_ik.update_arm_ik(0.0,pose)
	phases[h.phase] = true
	if not Profile.enabled(pose): return
	measured += 1
	var report: Dictionary = p.body_pivot.get_meta("wide_backhand_reach_report",{})
	check(bool(report.get("feasible",false)),label+" correction feasible")
	var expected: Transform3D = Path.world_transform(p,pose)
	var actual: Transform3D = p.paddle_node.global_transform
	var distance := expected.origin.distance_to(actual.origin)
	var angle := maxf(expected.basis.x.distance_to(actual.basis.x),maxf(expected.basis.y.distance_to(actual.basis.y),expected.basis.z.distance_to(actual.basis.z)))
	check(distance < .00001 and angle < .00001,label+" fixed world paddle target retained")
	maxima.paddle_delta_m = maxf(maxima.paddle_delta_m,distance);maxima.basis_delta = maxf(maxima.basis_delta,angle)
	maxima.body_shift_m = maxf(maxima.body_shift_m,(report.get("world_offset",Vector3.ZERO) as Vector3).length())
	for side in range(2):
		var arm = p.right_arm_node if side==0 else p.left_arm_node
		var wrist: Vector3 = arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket
		var ratio: float = maxf(arm.upper_pivot.global_position.distance_to(arm.forearm_pivot.global_position)/arm.upper_arm_length,arm.forearm_pivot.global_position.distance_to(wrist)/arm.forearm_length)
		check(ratio <=1.000004 and arm.visual_stretch<=1.000004,label+" actual nominal arm links")
		var anchor: Vector3 = actual * (D.MAIN_GRIP_OFFSET+pose.right_hand_offset if side==0 else D.SUPPORT_GRIP_OFFSET+Vector3.UP*pose.support_grip_slide_m)
		var error: float = arm.hand_mesh.global_position.distance_to(anchor)
		check(error<.00001,label+" both grips stay seated")
		maxima.grip_error_m=maxf(maxima.grip_error_m,error)
		if side==0:maxima.main_ratio=maxf(maxima.main_ratio,ratio)
		else:maxima.support_ratio=maxf(maxima.support_ratio,ratio)
		var leg = p.right_leg_node if side==0 else p.left_leg_node
		var leg_ratio: float = maxf(leg.thigh_pivot.global_position.distance_to(leg.shin_pivot.global_position)/leg.thigh_length,leg.shin_pivot.global_position.distance_to(leg.foot_pivot.global_position)/leg.shin_length)
		check(leg_ratio<=1.000004,label+" actual nominal leg links")
		maxima.leg_ratio=maxf(maxima.leg_ratio,leg_ratio)
