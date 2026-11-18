extends SceneTree
const Fixture = preload("res://scripts/tests/fixtures/charged_footwork_fixture.gd")
const Footwork = preload("res://scripts/charged_footwork.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Geometry = preload("res://scripts/paddle_clearance.gd")
var game
var checks: = 0
var failures: Array[String] = []
var results: Array = []
var contacts: Array = []
var current_case: = ""
var previous_ring_setting
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(current_case + ": " + label)
func run() -> void :
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	Fixture.configure(game)
	var settings = root.get_node("Settings")
	previous_ring_setting = settings.get_value("beta_debug.reach_rings", false)
	settings._config.set_value("beta_debug", "reach_rings", true)
	settings.settings_changed.emit("beta_debug.reach_rings", true)
	game.ball.hit_by_paddle.connect(record_hit)
	for data in Fixture.cases(): await live_case(data)
	await too_late_legal_feed()
	await mirrored_plans()
	await cancellation_cases()
	await verify_raw_shapes()
	var output = FileAccess.open("/tmp/charged-footwork-evidence.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures, "cases": results, "contacts": contacts}, "\t"));output.close()
	Input.action_release("ui_accept")
	settings._config.set_value("beta_debug", "reach_rings", previous_ring_setting)
	game.queue_free(); await process_frame; await process_frame
	var until: int = Time.get_ticks_usec() + 150000
	while Time.get_ticks_usec() < until: OS.delay_msec(5); await process_frame
	for failure in failures: push_error(failure)
	print("CHARGED FOOTWORK: %d checks, %d failures; actual contacts=%d" % [checks, failures.size(), contacts.size()])
	quit(0 if failures.is_empty() else 1)
func record_hit(team: int) -> void :
	if team != 0: return
	var human = game.player_left.posture.human_contact
	var evidence: Dictionary = human.last_contact_evidence.duplicate()
	evidence["case"] = current_case
	evidence["strike_time"] = human.strike_time
	evidence["swing_flight"] = human.swing_flight_id
	contacts.append(evidence)
	check(evidence.has("raw_paddle") and evidence.has("raw_ball"), "hit lacks pre-alignment finite-head evidence")
	if evidence.has("raw_paddle"):
		var local: Vector3 = evidence.raw_paddle.affine_inverse() * evidence.raw_ball
		check(Geometry.distance_to_head_shape(local) <= Ball.BALL_RADIUS + Geometry.contact_surface_tolerance() + 0.0001, "raw finite head is not touching returned ball")
		check(evidence.phase == 1 and evidence.flight == human.swing_flight_id, "return lost legal strike/flight ownership")
func live_case(data: Dictionary) -> void :
	current_case = data.name
	var launch: Dictionary = Fixture.prepare(game, data)
	await physics_frame; await physics_frame
	var player = game.player_left
	var human = player.posture.human_contact
	var feet = human.footwork
	var initial_root: Vector3 = player.global_position
	var previous: Vector3 = initial_root
	var hit_count: = contacts.size()
	var max_step: = 0.0
	var max_speed: = 0.0
	var travelled: = 0.0
	var states: Array[String] = []
	var plan: Dictionary = {}
	var phases: Array[int] = []
	var released: = false
	var queued_before_arrival: = false
	var ownership_violation: = false
	var load_record: Dictionary = {}
	var ring_checked: = false
	Fixture.press(game)
	for frame in range(250):
		Fixture.tick_input(game)
		await physics_frame
		var step: float = player.global_position.distance_to(previous)
		previous = player.global_position
		max_step = maxf(max_step, step)
		max_speed = maxf(max_speed, player.current_velocity.length())
		travelled += step
		if states.is_empty() or states.back() != feet.state: states.append(feet.state)
		if phases.is_empty() or phases.back() != human.phase: phases.append(human.phase)
		if feet.active and plan.is_empty(): plan = feet.plan.duplicate()
		if feet.active and not ring_checked:
			var rings = player.get_node("ReachRings")
			rings.refresh()
			check(rings.planned_movement, "future root plan not shown separately")
			check(rings.outer_radius <= 1.2, "future root inflated standing-reach radius")
			if human.contact.is_empty(): check(rings.active_band == 0, "future movement falsely glows as actual contact")
			ring_checked = true
		if feet.state == "load" and load_record.is_empty():
			load_record = {"side": feet.load_side, "support_ready": player.leg_ik.is_support_ready(feet.load_side), "right_locked": player.leg_ik.right_foot_locked, "left_locked": player.leg_ik.left_foot_locked, "velocity": player.current_velocity}
			var expected_side: int = 1 if bool(feet.plan.neutral) and int(feet.plan.def.family) == 0 else (0 if int(feet.plan.def.family) == 0 else 1)
			check(feet.load_side == expected_side, "load is on wrong anatomical foot")
			check(player.leg_ik.is_support_ready(feet.load_side), "load became ready before real support settled")
		if game.ball.last_hit_by != 1 and contacts.size() == hit_count: ownership_violation = true
		if frame == 12:
			Fixture.release(game);released = true
			queued_before_arrival = feet.active and human.phase == 0 and player.global_position.distance_to(feet.plan.target_root) > 0.03
		if game.game_state != game.GameState.PLAYING: break
		if frame > 80 and contacts.size() > hit_count and human.phase < 0: break
	if not released: Fixture.release(game)
	var returned: = contacts.size() > hit_count
	check( not ownership_violation, "ball ownership changed without actual contact")
	check(max_speed <= Footwork.MAX_SPEED + 0.001, "root speed exceeds assistance bound")
	check(max_step <= Footwork.MAX_SPEED / Engine.physics_ticks_per_second + 0.002, "root teleported")
	check(initial_root.distance_to(player.global_position) <= Footwork.MAX_TRAVEL + 0.03, "assisted root exceeds total bound")
	if data.get("impossible", false):
		check( not returned and plan.is_empty(), "impossible feed fabricated movement/contact")
	else:
		check( not plan.is_empty(), "no assisted interception planned")
		check(queued_before_arrival, "early release did not remain queued while travelling")
		check(returned, "reachable assisted feed did not return through finite paddle")
		check(states.has("plant") and states.has("load"), "no genuine plant and load")
		if states.has("swing"): check(states.find("plant") < states.find("swing") and states.find("load") < states.find("swing"), "swing preceded plant/load")
		check(phases.has(2) and phases.has(4), "swing did not finish and recover")
		if not plan.is_empty(): check(int(plan.def.family) == int(data.family), "wrong anatomical stroke family")
	var row: Dictionary = {"name": data.name, "launch": launch, "plan": plan, "states": states, "phases": phases, "returned": returned, "max_step": max_step, "max_speed": max_speed, "travelled": travelled, "cancel": feet.cancel_reason, "root": player.global_position, "queue_early": queued_before_arrival, "load": load_record}
	results.append(row)
	print("CHARGED CASE ", JSON.stringify(row))
func mirrored_plans() -> void :
	current_case = "mirrored planning"
	var data: Dictionary = Fixture.cases()[0]
	Fixture.prepare(game, data)
	var ball = game.ball
	var left = game.player_left
	var right = game.player_right
	right.global_position = Vector3(0, right.ground_y, - float(data.root_z))
	right.hitting.clear_charge_visual();right.hitting.serving_visual_active = false
	right.leg_ik.feet_initialized = false;right._process(0.0);right.can_volley_from_feet()
	for sample in Fixture.cases():
		if sample.get("impossible", false): continue
		Fixture.prepare(game, sample)
		right.global_position = Vector3(0, right.ground_y, - float(sample.root_z))
		right.current_velocity = Vector3.ZERO
		right.hitting.clear_charge_visual();right.hitting.serving_visual_active = false
		right.leg_ik.feet_initialized = false;right._process(0.0);right.can_volley_from_feet()
		var normal: Dictionary = Footwork.select_plan(left, ball, Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity, Footwork.MAX_HORIZON))
		ball.global_position = Vector3( - ball.global_position.x, ball.global_position.y, - ball.global_position.z)
		ball.linear_velocity = Vector3( - ball.linear_velocity.x, ball.linear_velocity.y, - ball.linear_velocity.z)
		ball.last_hit_by = 0
		var mirror: Dictionary = Footwork.select_plan(right, ball, Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity, Footwork.MAX_HORIZON))
		check( not normal.is_empty() and not mirror.is_empty(), sample.name + " has no mirrored plan")
		if not normal.is_empty() and not mirror.is_empty():
			check(normal.posture == mirror.posture and absf(normal.distance - mirror.distance) < 0.001, sample.name + " orientation changes selected reach")
			check(normal.target_root.distance_to(Vector3( - mirror.target_root.x, mirror.target_root.y, - mirror.target_root.z)) < 0.001, sample.name + " target root not mirrored")
func cancellation_cases() -> void :
	for mode in ["manual", "queued_manual", "flight", "fault", "reset", "opening_bounce"]:
		current_case = "cancel_" + mode
		Fixture.prepare(game, Fixture.cases()[1])
		await physics_frame; await physics_frame
		if mode == "opening_bounce":
			game.ball.both_bounces_complete = false

			var no_bounce: Dictionary = Flight.trace(game.ball.global_position, game.ball.linear_velocity, game.ball.angular_velocity, 0.6)
			check(Footwork.select_plan(game.player_left, game.ball, no_bounce).is_empty(), "opening volley bypasses bounce rule")
			continue
		Fixture.press(game)
		for frame in range(5): Fixture.tick_input(game); await physics_frame
		var human = game.player_left.posture.human_contact
		check(human.footwork.active, "fixture never activated")
		if mode == "queued_manual":
			Fixture.release(game)
			check(human.phase == 0, "release did not queue before cancellation")
		var before_manual: Vector3 = game.player_left.global_position
		match mode:
			"manual", "queued_manual": Input.action_press("move_left")
			"flight": game.ball.flight_id += 1
			"fault": game.ball.is_in_play = false
			"reset": game._reset_ball()
		for frame in range(3): Fixture.tick_input(game); await physics_frame
		check( not human.footwork.active, "assistance survived interruption")
		if mode == "queued_manual":


			check(human.phase == 0 and game.player_left.hitting.charge_visual_active, "manual movement discarded queued charge")
			check(game.player_left.global_position.x < before_manual.x - 0.1, "manual override did not move actual root")
			check(game.ball.last_hit_by == 1, "queued manual movement fabricated distant contact")
		Input.action_release("move_left")
		if mode in ["manual", "queued_manual"]:
			for frame in range(4): Fixture.tick_input(game); await physics_frame
			check( not human.footwork.active, "same cancelled hold silently rearmed assistance")
		Fixture.release(game)

func verify_raw_shapes() -> void :
	current_case = "independent finite head"
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.ball.freeze = true
	var probe = load("res://scenes/paddle.tscn").instantiate()
	probe.collision_layer = 1024;probe.collision_mask = 0;root.add_child(probe)
	var query: = PhysicsShapeQueryParameters3D.new()
	var sphere: = SphereShape3D.new();sphere.radius = Ball.BALL_RADIUS
	query.shape = sphere;query.collision_mask = 1024;query.margin = 0.0
	for evidence in contacts:
		if not evidence.has("raw_paddle"): continue
		probe.global_transform = evidence.raw_paddle
		await physics_frame; await physics_frame
		query.transform = Transform3D(Basis.IDENTITY, evidence.raw_ball)
		var actual: Dictionary = {"head": false, "handle": false}
		for result in probe.get_world_3d().direct_space_state.intersect_shape(query, 8):
			if result.collider != probe: continue
			if result.shape == 0: actual.head = true
			elif result.shape == 1: actual.handle = true
		evidence["independent_shapes"] = actual
		check(actual.head, evidence.case + " pre-alignment sample has no real finite-head overlap")
	probe.queue_free(); await process_frame

func too_late_legal_feed() -> void :
	current_case = "too_late_inbounds"
	Fixture.prepare(game, Fixture.cases()[1])
	var player = game.player_left
	var ball = game.ball
	ball.global_position = Vector3(2.6, 1.1, 3.6)
	ball.linear_velocity = Vector3(0, 0, 12.0)
	ball.angular_velocity = Vector3.ZERO
	ball.flight_id += 1
	var initial: Vector3 = player.global_position
	var before: = contacts.size()
	Fixture.press(game)
	for frame in range(12):
		Fixture.tick_input(game)
		await physics_frame
	check( not player.posture.human_contact.footwork.active, "late in-bounds ball attracted impossible positioning")
	check(initial.distance_to(player.global_position) < 0.001, "late in-bounds ball teleported/moved root")
	check(contacts.size() == before, "late in-bounds ball fabricated a return")
	Fixture.release(game)
