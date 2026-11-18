extends SceneTree



const D = preload("res://scripts/paddle_dimensions.gd")
const G = preload("res://scripts/paddle_clearance.gd")
const R = preload("res://scripts/paddle_wrist_reach.gd")
var game
var checks: = 0
var failures: Array[String] = []
var rows: Array = []
var hits: Array = []
var query: PhysicsShapeQueryParameters3D
func _initialize(): call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func overlaps(paddle, point: Vector3) -> Dictionary:
	query.transform = Transform3D(Basis.IDENTITY, point)
	var result: Dictionary = {"head": false, "handle": false}
	for item in paddle.get_world_3d().direct_space_state.intersect_shape(query, 8):
		if item.collider != paddle: continue
		if item.shape == 0: result.head = true
		elif item.shape == 1: result.handle = true
	return result
func run_case(label: String, local: Vector3, expected: bool, mode: String = "normal") -> void :
	game.input_handler.cancel_charge_input();game._reset_ball()
	game.game_serve.cleanup();game._set_game_state(game.GameState.PLAYING)
	var player = game.player_left
	var human = player.posture.human_contact
	human.cancel();player.hitting.clear_charge_visual();player.hitting.serving_visual_active = false
	player.global_position = Vector3(0, player.ground_y, 1.7 if mode == "nvz" else 3.3)
	player.current_velocity = Vector3.ZERO;player.leg_ik.feet_initialized = false
	var pose: PostureDefinition = PostureLibrary.instance().get_def(0).duplicate(true)
	player.posture.transition_pose_blend = pose;player.posture.force_posture_update(pose);player.can_volley_from_feet()
	var ball = game.ball
	ball.reset_rally_state();ball.freeze = true;ball.is_in_play = true;ball.last_hit_by = 1
	ball.both_bounces_complete = mode != "opening_bounce";ball.bounces_since_last_hit = 0 if mode in ["opening_bounce", "nvz"] else 1
	ball.ball_bounced_since_last_hit = ball.bounces_since_last_hit > 0;ball.flight_id += 1
	var point: Vector3 = player.paddle_node.to_global(local)
	ball.global_position = point
	ball.linear_velocity = - player.paddle_node.global_basis.z * 5.0
	ball.angular_velocity = Vector3.ZERO
	if mode == "same_hitter": ball.last_hit_by = 0
	if mode == "double_bounce": ball.bounces_since_last_hit = 2
	human.visual_pose = pose;human._flight_id = ball.flight_id
	human.contact = {"point": PaddleReach.head_world(player), "time": 0.0, "bounces": 0, "posture": pose.posture_id, "def": pose}
	await physics_frame; await physics_frame
	var physical: Dictionary = overlaps(player.paddle_node, point)
	var center_distance: float = point.distance_to(PaddleReach.head_world(player))
	var gap: float = G.distance_to_head_shape(player.paddle_node.to_local(point)) - Ball.BALL_RADIUS
	check(R.fits(player.paddle_node.global_transform, pose, R.live_shoulder(player, pose), R.link_budget(player, pose)), label + " fixture wrist not physically reachable")
	var before: int = hits.size()
	var rng_before: int = game.shot_physics.accuracy.rng.state
	var samples_before: int = game.shot_physics.accuracy.samples
	var strike_cost_usec: = 0
	if mode == "idle":
		human._advance_swing(0.0, ball)
	else:
		if mode in ["late", "other_flight", "swept", "swept_expired"]: ball.global_position = point + player.paddle_node.global_basis.z * 0.4
		check(human.request_swing(0.0), label + " real commitment method refused fixture")
		var start_usec: int = Time.get_ticks_usec()
		human._advance_swing(0.0, ball)
		strike_cost_usec = Time.get_ticks_usec() - start_usec
		if mode == "late":
			ball.global_position = point;human.elapsed = human.strike_time + 0.1001;human._advance_swing(0.0, ball)
		elif mode in ["swept", "swept_expired"]:
			var sweep_from: Vector3 = player.paddle_node.to_global(Vector3(local.x, local.y, 0.08))
			var sweep_to: Vector3 = player.paddle_node.to_global(Vector3(local.x, local.y, - 0.08))
			query.transform = Transform3D(Basis.IDENTITY, sweep_from);query.motion = sweep_to - sweep_from
			var engine_sweep: PackedFloat32Array = player.paddle_node.get_world_3d().direct_space_state.cast_motion(query)
			check(engine_sweep.size() == 2 and engine_sweep[0] < 1.0, label + " engine sphere sweep missed real head")
			query.motion = Vector3.ZERO
			ball.global_position = sweep_from;human._remember_sweep(ball)
			ball.global_position = sweep_to
			human.elapsed = 0.016 if mode == "swept" else human.strike_time + 0.1 + 0.0161
			start_usec = Time.get_ticks_usec()
			var accepted: bool = human._try_swept_contact(ball, 0.016)
			strike_cost_usec = Time.get_ticks_usec() - start_usec
			check(accepted == expected, label + " swept controller result")
		elif mode == "other_flight":
			ball.global_position = point;ball.flight_id += 1;human._advance_swing(0.0, ball)
	var returned: bool = hits.size() > before
	check(game.shot_physics.accuracy.samples == samples_before + (1 if returned else 0), label + " only accepted contact samples accuracy once")
	if not returned: check(game.shot_physics.accuracy.rng.state == rng_before, label + " rejected contact preserves RNG state")
	check(returned == expected, label + " unexpected registered contact")
	if expected:
		check(physical.head, label + " sphere did not overlap real head collider")
		check( not physical.handle, label + " positive depended on handle collider")
		check(gap <= G.contact_surface_tolerance(), label + " exceeds strict actual surface allowance")
		check(hits.size() == before + 1 and hits.back().phase == 1, label + " contact not singular/committed")
		check(human.last_contact_evidence.get("phase", -1) == 1, label + " missing committed pre-alignment evidence")
		check(float(human.last_contact_evidence.get("raw_gap", INF)) <= G.contact_surface_tolerance(), label + " raw surface was separated before presentation")
		if mode == "swept":
			var evidence: Dictionary = human.last_contact_evidence
			check(evidence.get("swept", false) and float(evidence.get("fraction", -1.0)) > 0.0, label + " missing raw sweep evidence")
			if evidence.has("raw_ball") and evidence.has("swept_paddle"):
				check(evidence.raw_ball.distance_to(evidence.ball_from.lerp(evidence.ball_to, evidence.fraction)) < 1e-05, label + " interpolated ball differs from raw samples")
				check(preload("res://scripts/finite_paddle_contact.gd").touches(evidence.swept_paddle, evidence.raw_ball, Ball.BALL_RADIUS), label + " raw sampled transform does not touch")
			else: check(false, label + " missing accepted raw transform")
		else: check(human.last_contact_evidence.get("raw_ball", Vector3.INF).distance_to(point) < 1e-05, label + " raw ball evidence differs from actual sampled ball")
		if label != "center":
			check(center_distance > 0.1, label + " fails to exercise finite face outside legacy center shortcut")
			check(game.last_shot_profile.get("peripheral_contact", false), label + " peripheral quality not applied")
			check(float(game.last_shot_profile.get("contact_quality", 1.0)) < 1.0, label + " peripheral shot retained perfect speed")
		else: check( not game.last_shot_profile.get("peripheral_contact", false), "center quality unexpectedly penalized")
	if mode == "handle_first":
		check(physical.handle and not physical.head, label + " exact handle-first classification changed")
		check(gap > 0.005, label + " negative unexpectedly touches blade")
	rows.append({"label": label, "mode": mode, "returned": returned, "physical": physical, "gap": gap, "center_distance": center_distance, "phase_after": human.phase, "strike_callback_usec": strike_cost_usec, "timing_scope": "host actual controller callback including existing pose and launch solver", "evidence": human.last_contact_evidence.duplicate(), "quality": game.last_shot_profile.get("contact_quality", 1.0) if returned else null})
func run() -> void :
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game


	for frame in range(10):
		await process_frame; await physics_frame
		if game.player_left.posture.human_contact != null: break
	check(game.player_left.posture.human_contact != null, "human contact owner initialized")
	if game.player_left.posture.human_contact == null:
		quit(2)
		return
	game.process_mode = Node.PROCESS_MODE_DISABLED


	game.player_left.paddle_node.process_mode = Node.PROCESS_MODE_ALWAYS
	game.ball.hit_by_paddle.connect( func(team):
		if team == 0: hits.append({"phase": game.player_left.posture.human_contact.phase, "flight": game.ball.flight_id})
	)
	query = PhysicsShapeQueryParameters3D.new();query.collision_mask = 4;query.margin = 0
	var sphere: = SphereShape3D.new();sphere.radius = Ball.BALL_RADIUS;query.shape = sphere
	var center: = Vector3(0, D.HEAD_CENTER_Y, D.HEAD_HALF_THICKNESS + Ball.BALL_RADIUS - 0.001)
	await run_case("center", center, true)
	await run_case("upper broad face", center + Vector3(0, 0.1, 0), true)
	await run_case("lower broad face", center - Vector3(0, 0.1, 0), true)
	await run_case("side rim", Vector3(D.HEAD_RADIUS + Ball.BALL_RADIUS - 0.001, D.HEAD_CENTER_Y, 0), true)
	await run_case("swept upper face", center + Vector3(0, 0.1, 0), true, "swept")
	await run_case("expired swept face", center + Vector3(0, 0.1, 0), false, "swept_expired")
	await run_case("observed BH handle first", Vector3(0.006319, 0.130699, - 0.052816), false, "handle_first")
	await run_case("off face", center + Vector3(0, 0, 0.02), false)
	await run_case("remote", center + Vector3(1, 0, 0), false)
	for mode in ["idle", "late", "other_flight", "same_hitter", "double_bounce", "opening_bounce", "nvz"]:
		await run_case(mode, center, false, mode)
	var file = FileAccess.open("/tmp/finite-head-contact-gate.json", FileAccess.WRITE);file.store_string(JSON.stringify({"checks": checks, "failures": failures, "rows": rows}, "\t"));file.close()
	game.queue_free(); await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	for failure in failures: push_error(failure)
	print("FINITE HEAD CONTACT GATE: %d checks, %d failures; real registered contacts=%d" % [checks, failures.size(), hits.size()])
	quit(0 if failures.is_empty() else 1)
