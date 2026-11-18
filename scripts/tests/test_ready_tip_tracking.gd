extends SceneTree
const Tracking = preload("res://scripts/ready_ball_tracking.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Wrist = preload("res://scripts/paddle_wrist_reach.gd")
const D = preload("res://scripts/paddle_dimensions.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
var checks: = 0
var failures: Array[String] = []
var records: Array = []
var game
var wrist_limits: Dictionary = {}
var inherited_wrist: Array = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and failures.size() < 80: failures.append(message)
func angle(a: Vector3, b: Vector3) -> float:
	return acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0))
func snapshot(p) -> Dictionary:
	var pose: PostureDefinition = p.posture.transition_pose_blend
	return {"tip": p.paddle_node.global_basis.y, "torso": p.body_pivot.get_node("TorsoMesh").global_basis, "torso_yaw": pose.torso_yaw_deg, "body_yaw": pose.body_yaw_deg, "tip_turn": pose.get_meta("ready_tracking_tip_angle_deg", 0.0), "grip": Wrist.virtual_grip_world(p.paddle_node.global_transform, pose)}
func present(p, delta: float) -> void:
	if not p.is_ai: p.posture.human_contact.update(delta)
	p._process(delta)
func rig_check(p, label: String) -> void:
	var pose: PostureDefinition = p.posture.transition_pose_blend
	check(p.paddle_node.global_transform.is_finite(), label + " finite paddle")
	check(Wrist.displayed_wrist(p, pose).distance_to(Wrist.wrist_world(p.paddle_node.global_transform, pose)) < 0.0001, label + " seated dominant wrist")
	for arm in [p.right_arm_node, p.left_arm_node]:
		var left: bool = arm == p.left_arm_node
		var shoulder: Vector3 = arm.upper_pivot.global_position
		var elbow: Vector3 = arm.forearm_pivot.global_position
		var wrist: Vector3 = arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket
		check(absf(shoulder.distance_to(elbow) - arm.upper_arm_length) < 0.00002 and absf(elbow.distance_to(wrist) - arm.forearm_length) < 0.00002, label + " finite exact arm links")
		var channels: Dictionary = Anatomy.decompose(Anatomy.forearm_reference_for_arm(arm, wrist, left), arm.articulated_hand.hand_mesh.global_basis * arm.articulated_hand.anatomical_basis, arm.articulated_hand.radial_sign)
		var baseline: Vector2 = wrist_limits.get(arm.get_instance_id(), Vector2(1.0, 90.0))
		check(channels.coupled_budget_ratio <= maxf(1.001, baseline.x) + 0.015 and absf(channels.forearm_axial_deg) <= maxf(90.01, baseline.y) + 0.1, label + " does not exceed authored wrist envelope " + str(channels))
func run() -> void:
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	for frame in range(4): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED; game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false); node.set_physics_process(false)
	game.ball.is_in_play = false
	var ready: PostureDefinition = PostureLibrary.instance().get_def(20)
	var source_text: String = var_to_str(ready)
	for p in [game.player_left, game.player_right]:
		p.current_velocity = Vector3.ZERO; p.hitting.serving_visual_active = false; p.hitting.charge_visual_active = false; p.hitting.is_in_follow_through = false
		p.posture.editor_preview_mode = false; p.posture._committed_incoming_posture = -1
		p._ready_tracking = Tracking.new()
		if not p.is_ai:
			p.posture.human_contact.cancel(); p.posture.human_contact.visual_pose = ready
		p.posture.transition_pose_blend = ready; p.posture.force_posture_update(ready)
		for arm in [p.right_arm_node, p.left_arm_node]:
			var left: bool = arm == p.left_arm_node
			var wrist: Vector3 = arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket
			var channels: Dictionary = Anatomy.decompose(Anatomy.forearm_reference_for_arm(arm, wrist, left), arm.articulated_hand.hand_mesh.global_basis * arm.articulated_hand.anatomical_basis, arm.articulated_hand.radial_sign)
			wrist_limits[arm.get_instance_id()] = Vector2(channels.coupled_budget_ratio, absf(channels.forearm_axial_deg))
			inherited_wrist.append({"court": p.player_num, "left": left, "channels": channels})
		var anchor: Vector3 = Wrist.virtual_grip_world(p.paddle_node.global_transform, ready)
		var first: Vector3 = p.global_position + p._get_forward_axis() * 2.4 - p._get_forehand_axis() * 1.8 + Vector3.UP * 0.6
		var second: Vector3 = p.global_position + p._get_forward_axis() * 2.4 + p._get_forehand_axis() * 1.8 + Vector3.UP * 0.6
		game.ball.global_position = first
		for frame in range(90): present(p, 1.0 / 60.0)
		var start: Dictionary = snapshot(p)
		var samples: Array = []
		game.ball.global_position = second
		for frame in range(60):
			present(p, 1.0 / 60.0)
			samples.append(snapshot(p))
			rig_check(p, "court%d tick%d" % [p.player_num, frame])
			check(samples.back().grip.distance_to(anchor) < 0.00002, "fast tip keeps seated grip fixed")
			check(absf(p.posture.transition_pose_blend.body_yaw_deg - ready.body_yaw_deg) < 0.00001, "Ready does not turn body pivot")
			check(p.posture.transition_pose_blend.right_foot_yaw_deg == ready.right_foot_yaw_deg and p.posture.transition_pose_blend.left_foot_yaw_deg == ready.left_foot_yaw_deg, "ball tracker preserves authored foot yaw")
		var final: Dictionary = samples.back()
		var total_tip: float = angle(start.tip, final.tip)
		var total_body: float = absf(final.torso_yaw - start.torso_yaw)
		var tip_time: = -1.0
		var body_time: = -1.0
		for frame in range(samples.size()):
			if tip_time < 0.0 and angle(samples[frame].tip, final.tip) <= total_tip * 0.1 + 0.00001: tip_time = (frame + 1) / 60.0
			if body_time < 0.0 and absf(samples[frame].torso_yaw - final.torso_yaw) <= total_body * 0.1 + 0.00001: body_time = (frame + 1) / 60.0
		check(total_tip > deg_to_rad(8.0), "actual paddle tip visibly responds")
		check(tip_time > 0.0 and tip_time <= 0.10 and body_time > tip_time * 2.0, "tip responds before smooth body court%d tip=%.3f torso=%.3f" % [p.player_num, tip_time, body_time])
		records.append({"court": p.player_num, "tip_90_percent_seconds": tip_time, "torso_90_percent_seconds": body_time, "tip_response_degrees": rad_to_deg(total_tip), "torso_response_degrees": total_body})
		# Extreme visual targets stay finite, grip-anchored and within the exact
		# same authored wrist/reach envelope. They cannot turn the root or feet.
		for local_target in [Vector3(-8, 0.5, -1), Vector3(8, 0.5, -1), Vector3(0, 8, -1), Vector3(0, -3, -1), Vector3(0, 1, 5), Vector3.ZERO]:
			game.ball.global_position = p.global_position + p._get_forehand_axis() * local_target.x + Vector3.UP * local_target.y - p._get_forward_axis() * local_target.z
			for frame in range(35):
				present(p, 1.0 / 60.0)
				rig_check(p, "extreme court%d target%s tick%d" % [p.player_num, str(local_target), frame])
				check(snapshot(p).grip.distance_to(anchor) < 0.00003, "extreme target retains fixed grip")
		var single = Tracking.new(); var partitioned = Tracking.new()
		var one: PostureDefinition = single.apply(ready, p, second, 0.1)
		var many: PostureDefinition
		for frame in range(10): many = partitioned.apply(ready, p, second, 0.01)
		check(Path.canonical_transform(one).is_equal_approx(Path.canonical_transform(many)), "tip filter is timestep independent")
		check(absf(one.torso_yaw_deg - many.torso_yaw_deg) < 0.00001, "torso filter is timestep independent")
		# Authored swing/serve and the explicit preview owner never get the overlay.
		for pose_id in [0, 2, 20]:
			for stage in [0, 1, 2]:
				var exact: PostureDefinition = Path.endpoint(PostureLibrary.instance().get_def(pose_id), stage)
				p.posture.transition_pose_blend = exact; p.hitting.charge_visual_active = true
				if p.ai_brain: p.ai_brain.incoming_pose_override = null
				if p.posture.human_contact: p.posture.human_contact.visual_pose = exact
				var expected: Transform3D = Path.world_transform(p, exact)
				p._process(1.0 / 60.0)
				check(p.paddle_node.global_transform.is_equal_approx(expected), "authored action frame remains exact court%d pose%d stage%d owner%d between%s charge%s" % [p.player_num, pose_id, stage, p.posture.transition_pose_blend.posture_id, str(p._between_point_owner() != null), str(p.hitting.charge_visual_active)])
				check(not p.posture.transition_pose_blend.has_meta(Tracking.BASE_META), "no tracking on action owner")
		p.hitting.charge_visual_active = false
		# Zero prep weight must return the unmodified contact-side base.
		var base: PostureDefinition = PostureLibrary.instance().get_def(0)
		check(p._ready_tracking.apply(base, p, second, 0.1, 0.0) == base, "tracking is zero by full preparation")
	# Receiving AI has exclusive ownership from its existing delayed/perceived plan.
	var ai_player = game.player_right; var brain = ai_player.ai_brain
	game.ball.is_in_play = true; game.ball.last_hit_by = 0
	brain._perceived_state = {"pos": Vector3(0, 1, -3), "vel": Vector3.ZERO, "omega": Vector3.ZERO}
	var perceived: Dictionary = brain._perceived_state.duplicate(true)
	brain.incoming_pose_override = PostureLibrary.instance().get_def(20).duplicate(true)
	ai_player._process(0.1)
	var before: Transform3D = ai_player.paddle_node.global_transform
	game.ball.global_position += Vector3(8, 3, 0)
	ai_player._process(0.1)
	check(ai_player.paddle_node.global_transform.is_equal_approx(before), "unperceived live ball cannot steer incoming AI paddle")
	check(brain._perceived_state == perceived, "Ready tracking never writes AI perception")
	check(var_to_str(ready) == source_text, "approved Ready source remains unchanged")
	var file = FileAccess.open("/tmp/ready-tip-tracking.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "records": records, "authored_wrist_baselines": inherited_wrist}, "\t")); file.close()
	for failure in failures: push_error(failure)
	print("READY TIP TRACKING: ", checks, " checks, ", failures.size(), " failures; ", records)
	game.queue_free(); await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	quit(0 if failures.is_empty() else 1)
