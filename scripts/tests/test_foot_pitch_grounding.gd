extends "res://scripts/tests/test_scaled_body_gait.gd"
const Split = preload("res://scripts/split_step_timing.gd")

func run() -> void:
	output = "/tmp/foot-pitch-grounding.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	for frame in range(5): await process_frame
	game.game_serve.cleanup(); game.process_mode = Node.PROCESS_MODE_DISABLED
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false); node.set_physics_process(false)
	for p in [game.player_left, game.player_right]:
		p.hitting.serving_visual_active = false; p.hitting.charge_visual_active = false; p.hitting.is_in_follow_through = false
		if p.posture.human_contact != null: p.posture.human_contact.cancel(false)
		p.leg_ik.drive_preparation.reset()
		for lift in [0.0, 0.01, 0.03, 0.10]:
			for pitch in [-30.0, -15.0, 0.0, 15.0, 45.0]:
				for yaw in [-75.0, 0.0, 75.0, 180.0]: _pose_case(p, lift, pitch, yaw)
		for hz in [30, 60, 120]: _split_case(p, hz)
	var f := FileAccess.open(output, FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks": checks, "failures": failures, "records": records}, "\t")); f.close()
	for failure in failures: push_error(failure)
	print("FOOT PITCH GROUNDING: %d checks, %d failures -> %s" % [checks, failures.size(), output])
	game.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)

func _pose_case(p, lift: float, pitch: float, yaw: float) -> void:
	var pose: PostureDefinition = PostureLibrary.instance().get_def(20).duplicate(true)
	pose.right_foot_pitch_deg = pitch; pose.left_foot_pitch_deg = clampf(-pitch, -30.0, 45.0)
	pose.right_foot_yaw_deg = yaw; pose.left_foot_yaw_deg = -yaw
	pose.right_foot_offset.y = lift; pose.left_foot_offset.y = lift
	p.posture.editor_preview_mode = true; p.current_velocity = Vector3.ZERO
	p.posture.transition_pose_blend = pose
	var root_position: Vector3 = p.global_position
	p.posture.force_posture_update(pose)
	var tag := "P%d lift%.2f pitch%.1f yaw%.1f" % [p.player_num, lift, pitch, yaw]
	for side in [0, 1]:
		var leg = p.right_leg_node if side == 0 else p.left_leg_node
		var foot: Vector3 = p.leg_ik.right_foot_smooth if side == 0 else p.leg_ik.left_foot_smooth
		var report: Dictionary = p.leg_ik.foot_pitch_report(side == 0)
		var requested: float = pose.right_foot_pitch_deg if side == 0 else pose.left_foot_pitch_deg
		check(is_equal_approx(report.requested, requested), tag + " report preserves requested pitch")
		check(sole_y(leg.foot_mesh) >= p.COURT_FLOOR_Y - 0.00002, tag + " pitch penetrated court")
		check(leg.foot_pivot.global_position.distance_to(foot) < 0.002, tag + " pitch moved ankle contact")
		if lift == 0.0:
			check(absf(report.applied) < 0.001 and report.grounded, tag + " planted sole did not stay flat")
		elif lift == 0.10:
			check(absf(report.applied - requested) < 0.01 and not report.grounded, tag + " lifted foot cannot show requested pitch")
		if absf(report.applied) > 0.01:
			var tip_y: float = (-leg.foot_pivot.global_basis.z).y
			check(signf(tip_y) == -signf(report.applied), tag + " toe-down sign is wrong after yaw")
		check(is_equal_approx(float(pose.get("right_foot_pitch_deg" if side == 0 else "left_foot_pitch_deg")), requested), tag + " grounding rewrote authored angle")
	check(p.global_position == root_position, tag + " grounding moved gameplay root")

func _split_case(p, hz: int) -> void:
	var ready: PostureDefinition = PostureLibrary.instance().get_def(20).duplicate(true)
	p.posture.editor_preview_mode = false; p.hitting.serving_visual_active = false; p.hitting.charge_visual_active = false; p.hitting.is_in_follow_through = false
	if p.posture.human_contact != null:
		p.posture.human_contact.cancel(false); p.posture.human_contact.contact = {}; p.posture.human_contact.anticipated_contact = {}
	p.leg_ik.drive_preparation.reset(); reset(p, ready)
	game.ball.is_in_play = true; game.ball.last_hit_by = p.player_num
	var timing := Split.new(); p.pose_controller.split_step = timing
	var max_arm_stretch := 1.0
	var maximum_pitch := 0.0; var minimum_sole := INF; var maximum_lift := 0.0
	var before: Vector3 = p.global_position
	for frame in range(hz * 2):
		var context := {"live": true, "hop_allowed": true}
		if frame == 0: context.merge({"cue_id": 1, "cue_lead": 0.18})
		if frame == ceili(0.18 * hz): context.strike_id = 1
		timing.update(1.0 / hz, context)
		tick(p, ready, Vector3.ZERO, 1.0 / hz)
		for side in [0, 1]:
			var leg = p.right_leg_node if side == 0 else p.left_leg_node
			var report: Dictionary = p.leg_ik.foot_pitch_report(side == 0)
			maximum_pitch = maxf(maximum_pitch, report.applied)
			minimum_sole = minf(minimum_sole, sole_y(leg.foot_mesh))
			if report.grounded: check(absf(report.applied) < 0.001, "split lands flat P%d %dHz" % [p.player_num, hz])
		for arm in [p.right_arm_node, p.left_arm_node]: max_arm_stretch = maxf(max_arm_stretch, arm.visual_stretch)
		maximum_lift = maxf(maximum_lift, p.leg_ik.right_foot_smooth.y - p.leg_ik.ANKLE_HEIGHT)
		var feet: Array[Vector3] = [p.leg_ik.right_foot_smooth, p.leg_ik.left_foot_smooth]
		p.leg_ik.update_leg_ik(0.0, ready)
		check(feet[0].is_equal_approx(p.leg_ik.right_foot_smooth) and feet[1].is_equal_approx(p.leg_ik.left_foot_smooth), "zero-clock refresh preserves hop sample")
	print("SPLIT ARM ", p.player_num, " ", hz, " maxstretch=", max_arm_stretch)
	check(max_arm_stretch <= 1.001, "split arm stretch")
	check(maximum_pitch > 2.0 and maximum_pitch <= 12.01, "actual split ankle visibly points down P%d %dHz" % [p.player_num, hz])
	check(maximum_lift > 0.01 and maximum_lift <= 0.02501, "small split foot lift")
	check(minimum_sole >= p.COURT_FLOOR_Y - 0.00002, "split toe never penetrates floor")
	check(p.global_position == before and p.leg_ik.right_foot_locked and p.leg_ik.left_foot_locked, "split ends planted without root relocation")
	records.append({"case": "P%d %dHz" % [p.player_num, hz], "peak_actual_toe_down_deg": maximum_pitch, "minimum_sole_y": minimum_sole, "maximum_lift_m": maximum_lift})
