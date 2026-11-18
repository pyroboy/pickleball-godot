extends SceneTree


class CountLegs extends PlayerLegIK:
	var calls: = 0
	var positive_seconds: = 0.0
	func update_leg_ik(delta: float, pose = null) -> void :
		calls += 1
		positive_seconds += maxf(delta, 0.0)
		super.update_leg_ik(delta, pose)
class CountArms extends PlayerArmIK:
	var calls: = 0
	func update_arm_ik(delta: float, pose = null) -> void :
		calls += 1
		super.update_arm_ik(delta, pose)
var checks: = 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func close(a: float, b: float) -> bool: return absf(a - b) < 1e-08
func same_transform(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < 2e-06 and a.basis.x.distance_to(b.basis.x) < 2e-06 and a.basis.y.distance_to(b.basis.y) < 2e-06 and a.basis.z.distance_to(b.basis.z) < 2e-06
func _initialize() -> void : call_deferred("run")
func run() -> void :
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.between_point_controller.cancel()
	game.ball.freeze = true
	game.ball.is_in_play = true
	game.ball.both_bounces_complete = true
	for side in [0, 1]:
		var p = game.player_left if side == 0 else game.player_right
		p.is_ai = true
		p.posture.human_contact = null
		p.is_jumping = false
		p.current_velocity = Vector3.ZERO
		p.hitting.clear_charge_visual()
		p.hitting.serving_visual_active = false
		p.hitting.is_in_follow_through = false
		p.global_position = Vector3(0, 1, 3.5 if side == 0 else -3.5)
		p.ground_y = 1.0
		game.ball.last_hit_by = 1 - side
		var pose: PostureDefinition = PostureLibrary.instance().get_def(13)
		p.ai_brain.incoming_pose_override = pose
		p.posture.transition_pose_blend = pose
		var legs: = CountLegs.new()
		p.add_child(legs)
		p.leg_ik = legs
		var arms: = CountArms.new()
		p.add_child(arms)
		p.arm_ik = arms
		p.posture.force_posture_update(pose)
		legs.initialize_serve_stance(pose)
		p.arm_ik.update_arm_ik(0.0, pose)
		p.reset_support_clock()
		legs.calls = 0
		legs.positive_seconds = 0.0
		arms.calls = 0

		for i in range(7): p._advance_support_clock(1.0 / 60.0)
		check(legs.calls == 0 and arms.calls == 0, "P%d clock accrual has no IK work" % side)
		var raw: Transform3D = p.paddle_node.global_transform
		var root_before: Transform3D = p.global_transform
		var cached_pos: Vector3 = p.posture._posture_lerp_pos
		var cached_rot: Vector3 = p.posture._posture_lerp_rot
		var cached_basis: Basis = p.posture._posture_lerp_basis
		check(p.refresh_contact_support(pose), "P%d genuine candidate refreshes" % side)
		check(close(legs.positive_seconds, 7.0 / 60.0), "P%d contact spends pending time exactly" % side)
		check(legs.calls == 1 and arms.calls == 1, "P%d one ordered contact solve" % side)
		check(same_transform(raw, p.paddle_node.global_transform), "P%d raw world paddle preserved" % side)
		check(same_transform(root_before, p.global_transform), "P%d root unchanged" % side)
		check(cached_pos == p.posture._posture_lerp_pos and cached_rot == p.posture._posture_lerp_rot and cached_basis == p.posture._posture_lerp_basis, "P%d tracking caches preserved" % side)
		check(p.paddle_rest_position == p.paddle_node.position and p.paddle_rest_rotation == p.paddle_node.rotation_degrees, "P%d rest cache uses refitted local frame" % side)
		for arm in [p.right_arm_node, p.left_arm_node]:
			check(absf(arm.upper_pivot.global_position.distance_to(arm.forearm_pivot.global_position) - arm.upper_arm_length) < 2e-05, "P%d actual upper link exact" % side)
			check(absf(arm.forearm_pivot.global_position.distance_to(arm.anatomical_wrist_world) - arm.forearm_length) < 2e-05, "P%d actual forearm link exact" % side)
		check(p.can_volley_from_feet(), "P%d current outside feet establish legal history" % side)
		check( not p.refresh_contact_support(pose), "P%d duplicate same-tick contact skipped" % side)
		check(legs.calls == 1 and arms.calls == 1, "P%d duplicate has no solves" % side)
		p._process(0.125)
		check(close(legs.positive_seconds, 7.0 / 60.0), "P%d next render cannot spend contact time twice" % side)
		check(legs.calls == 2 and arms.calls == 2, "P%d render keeps its single leg/arm solve (legs=%d arms=%d)" % [side, legs.calls, arms.calls])
		p._advance_support_clock(1.0 / 240.0)
		p._process(0.5)
		check(close(legs.positive_seconds, 7.0 / 60.0 + 1.0 / 240.0), "P%d render consumes scaled physics time, not render delta" % side)
		var sim: float = p._support_sim_time
		paused = true
		p._advance_support_clock(0.5)
		check(close(p._support_sim_time, sim), "P%d pause accrues no simulation time" % side)
		check( not p.refresh_contact_support(pose), "P%d paused contact skips" % side)
		paused = false
		p._advance_support_clock(0.04)
		p.posture.editor_preview_mode = true
		p._advance_support_clock(0.1)
		check(close(p._support_consumed_time, p._support_sim_time), "P%d editor discards earlier debt" % side)
		check( not p.refresh_contact_support(pose), "P%d editor contact skips" % side)
		p.posture.editor_preview_mode = false
		check(close(p._consume_support_delta(), 0.0), "P%d editor exit does not catch up preview time" % side)

		p._advance_support_clock(0.125)
		legs.initialize_serve_stance(pose)
		check(close(p._consume_support_delta(), 0.0), "P%d serve stance clears old-foot debt" % side)
		p._advance_support_clock(1.0 / 60.0)
		var spent: float = legs.positive_seconds
		check(p.refresh_contact_support(pose), "P%d reset allows fresh quick contact" % side)
		check(close(legs.positive_seconds - spent, 1.0 / 60.0), "P%d quick contact spends only new stance time" % side)
		p._advance_support_clock(0.1)
		legs.feet_initialized = false
		check(close(p._consume_support_delta(), 0.0), "P%d reset feet discard prior time" % side)
		legs.initialize_serve_stance(pose)
		p._advance_support_clock(0.1)
		p.global_position.z += 2.0 if side == 0 else -2.0
		check(close(p._consume_support_delta(), 0.0), "P%d teleport discards prior time" % side)

		p.global_position.z = 1.5 if side == 0 else -1.5
		p.posture.force_posture_update(pose, false)
		legs.initialize_serve_stance(pose)
		check(p.refresh_contact_support(pose), "P%d inside-court candidate can refresh support" % side)
		check( not p.can_volley_from_feet(), "P%d inside feet remain illegal after refresh" % side)
		p.reset_support_clock()
		p.is_ai = false
		check( not p.refresh_contact_support(pose), "P%d human swept owner remains untouched" % side)
		p.is_ai = true
		p.hitting.is_in_follow_through = true
		check( not p.refresh_contact_support(pose), "P%d completed stroke owner remains untouched" % side)
		p.hitting.is_in_follow_through = false
	print("PLAYER SUPPORT CLOCK: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures: print("FAIL: ", failure)
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game)
	quit(0 if failures.is_empty() else 1)
