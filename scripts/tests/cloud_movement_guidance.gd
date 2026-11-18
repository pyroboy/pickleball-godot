extends SceneTree
## Genuine BallFlightPredictor traces at the requested engine physics rate.
const Advisor = preload("res://scripts/movement_guidance_advisor.gd")
const Fixture = preload("res://scripts/tests/fixtures/charged_footwork_fixture.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Planner = preload("res://scripts/incoming_contact_planner.gd")
const Footwork = preload("res://scripts/charged_footwork.gd")
const Finite = preload("res://scripts/finite_paddle_contact.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Wrist = preload("res://scripts/paddle_wrist_reach.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
var game
var checks := 0
var failures: Array[String] = []
var records: Array = []
var solve_times: Array[int] = []
var rate := 60
var current_case := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--rate="): rate = int(argument.trim_prefix("--rate="))
	Engine.physics_ticks_per_second = rate
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(current_case + ": " + label)

func prepare(data: Dictionary = {}) -> void:
	Fixture.prepare(game, Fixture.cases()[1] if data.is_empty() else data)
	game.ball.freeze = true

func trace() -> Dictionary:
	return Flight.trace(game.ball.global_position, game.ball.linear_velocity, game.ball.angular_velocity)

func solve(name: String, flight: Dictionary = {}) -> Dictionary:
	current_case = name
	var advisor = Advisor.new()
	var before := state_fingerprint()
	var original_flight := flight.duplicate(true)
	var result: Dictionary = advisor.update(0.0, game.player_left, game.ball, trace() if flight.is_empty() else flight)
	check(state_fingerprint() == before, "advisor changed game, charge, feet, NVZ, controller, pose or authored resource state")
	check(flight == original_flight, "advisor changed supplied trajectory")
	check(advisor.statistics.traces == 0, "duplicated existing trace")
	check(advisor.statistics.last_geometry_tests <= Advisor.MAX_GEOMETRY_TESTS, "unbounded geometry search")
	check(advisor.statistics.last_time_samples <= Advisor.MAX_TIME_SAMPLES, "unbounded time samples")
	if result.visible: validate_candidate(result)
	solve_times.append(advisor.statistics.last_solve_usec)
	records.append({"case": name, "result": result, "statistics": advisor.statistics.duplicate()})
	return result

func run() -> void:
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	Fixture.configure(game)
	game.process_mode = Node.PROCESS_MODE_DISABLED
	for data in Fixture.cases():
		prepare(data)
		var result := solve(data.name)
		check(result.visible, "real incoming trajectory has no legal guidance candidate")
		if data.get("impossible", false):
			check(result.status != "MOVE", "too-late feed falsely advertised comfortable")
		else: check(result.status == "MOVE", "comfortable manual return not identified")
	standing_and_large_travel()
	legality_cases()
	stale_and_cache_cases()
	immediate_reach_evidence_cases()
	budget_cases()
	no_time_cases()
	mirrored_case()
	continuous_trajectory()
	# A CPU regression bound, not a claim about this machine's frame rate.
	solve_times.sort()
	current_case = "performance"
	var median: int = solve_times[solve_times.size() / 2]
	var maximum: int = solve_times.back()
	check(median < 30000 and maximum < 100000, "solve CPU exceeded bounded cloud regression budget")
	var output := {"rate": rate, "checks": checks, "failures": failures, "cases": records,
		"solve_cpu_usec": {"median": median, "maximum": maximum, "samples": solve_times},
		"scope": "Archived 0.3.25/build28 cloud candidate; not current Mac build30/31 acceptance"}
	var destination := OS.get_environment("MOVEMENT_GUIDANCE_REPORT")
	if destination.is_empty(): destination = "/tmp/cloud-movement-guidance-%d.json" % rate
	var file := FileAccess.open(destination, FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t")); file.close()
	for failure in failures: push_error(failure)
	print("CLOUD MOVEMENT GUIDANCE %d Hz: %d checks, %d failures; solve median=%d us max=%d us" % [rate, checks, failures.size(), median, maximum])
	game.queue_free(); await process_frame; await process_frame
	# Existing audio teardown owns deferred resources; allow its normal cleanup.
	var until := Time.get_ticks_usec() + 150000
	while Time.get_ticks_usec() < until: OS.delay_msec(5); await process_frame
	quit(0 if failures.is_empty() else 1)

func validate_candidate(result: Dictionary) -> void:
	var player = game.player_left
	var detached = Advisor.snapshot(player)
	detached.place(result.target_root)
	var base: PostureDefinition = PostureLibrary.instance().get_def(result.posture)
	check(Advisor._within_bounds(player, result.target_root), "target outside actual player bounds")
	check(result.target_root.z * player.global_position.z > 0.0, "target crosses net")
	check(Planner.legal_ball(detached, game.ball, result.future_bounces), "target violates bounce or volley law")
	check(Planner.point_fits(detached, base, result.point), "target fails shared legal reach geometry")
	var pose: PostureDefinition = Planner.pose_at(detached, base, result.point)
	var paddle: Transform3D = Path.world_transform(detached, pose)
	check(Finite.touches(paddle, result.point, Ball.BALL_RADIUS), "target does not touch finite paddle head")
	check(Wrist.wrist_world(paddle, pose).distance_to(Body.shoulder_world(detached, pose)) <= Wrist.link_budget(detached, pose) + 0.00011, "target exceeds actual arm budget")
	check(result.time < Planner.predicted_fault_time(player, game.ball, trace()), "target follows predicted rally fault")
	if result.status == "MOVE": check(result.slack >= Advisor.TIGHT_SLACK, "MOVE lacks setup/strike margin")
	if result.status == "NO_TIME": check(result.no_time_proven and result.proof_scope == "predicted_legal_flight", "NO_TIME lacks independent proof")

func standing_and_large_travel() -> void:
	prepare({"name": "standing", "root_z": 4.7, "lateral": 0.42, "height": 1.08, "forward": 0.46, "duration": 1.65, "family": 0})
	var standing := solve("already_in_reach")
	check(not standing.visible and standing.reason == "already_in_reach", "standing-reachable shot asks for unnecessary move")
	prepare()
	game.player_left.global_position.x = -2.0
	game.player_left.leg_ik.feet_initialized = false; game.player_left._process(0.0)
	game.player_left.can_volley_from_feet()
	var larger := solve("manual_travel_beyond_autostep")
	check(larger.visible and larger.status == "MOVE", "manual movement inherited held-autostep limits")
	if larger.visible:
		check(larger.required_travel > Footwork.MAX_TRAVEL, "large-travel fixture did not exceed autostep 2.4 m")
		manual_replay(larger)

func manual_replay(plan: Dictionary) -> void:
	current_case = "real_manual_inertia_replay"
	var player = game.player_left
	var original: Vector3 = player.global_position
	var velocity := Vector3.ZERO
	var elapsed := 0.0
	var arrived := false
	var top_speed := 0.0
	for frame in range(int(rate * plan.remaining_time)):
		var offset: Vector3 = plan.target_root - player.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance < 0.04 and velocity.length() < 0.06:
			arrived = true; break
		var desired_speed: float = minf(player.move_speed, minf(distance * rate, sqrt(2.0 * player.MANUAL_BRAKE * maxf(distance - 0.015, 0.0))))
		var has_input: bool = desired_speed > 0.001
		player.current_velocity = velocity
		velocity = player._manual_ground_velocity(offset.normalized() * desired_speed if has_input else Vector3.ZERO, has_input, 1.0 / rate)
		player.global_position += velocity / rate
		elapsed += 1.0 / rate
		top_speed = maxf(top_speed, velocity.length())
	check(arrived, "actual manual acceleration/braking did not reach the indicated root")
	check(elapsed + plan.plant_time + plan.strike_time <= plan.remaining_time, "actual manual arrival leaves no plant/strike time")
	check(top_speed <= player.move_speed + 0.001, "replay exceeded actual manual speed")
	records.append({"case": current_case, "distance": original.distance_to(player.global_position),
		"arrival_time": elapsed, "contact_time": plan.remaining_time, "top_speed": top_speed,
		"root_error": player.global_position.distance_to(plan.target_root), "arrived": arrived})
	player.global_position = original
	player.current_velocity = Vector3.ZERO
	player._manual_motion_active = false

func legality_cases() -> void:
	prepare()
	game.ball.both_bounces_complete = false
	var first_bounce := solve("opening_required_bounce")
	if first_bounce.visible: check(first_bounce.total_bounces >= 1, "opening-shot volley bypassed required bounce")
	prepare()
	game.ball.both_bounces_complete = false
	game.rally_scorer._serve_was_hit = false
	game.rally_scorer._serving_team = 1
	game.rally_scorer._serving_from_right = false
	check(not solve("wrong_service_court").visible, "post-bounce guidance survived a service-court fault")
	prepare()
	game.ball.global_position = Vector3(2.0, 0.35, -0.8)
	game.ball.linear_velocity = Vector3(0.0, 0.0, 6.0)
	game.ball.angular_velocity = Vector3.ZERO
	check(trace().net_hit, "net-fault fixture missed the net")
	check(not solve("net_fault").visible, "net-fault trajectory produced an impossible target")
	prepare(); game.ball.bounces_since_last_hit = 2
	check(not solve("second_bounce").visible, "second bounce retained guidance")
	prepare(); game.ball.last_hit_by = 0
	check(not solve("outgoing").visible, "outgoing ball retained guidance")
	prepare(); game.ball.is_in_play = false
	check(not solve("dead_ball").visible, "dead ball retained guidance")
	prepare(); game.ball.wall_practice_active = true; game.ball.wall_return_ready = false
	check(not solve("unready_wall_return").visible, "unready wall return retained guidance")
	game.ball.wall_practice_active = false
	prepare()
	game.player_left.global_position.z = 2.0
	game.player_left.leg_ik.feet_initialized = false; game.player_left._process(0.0)
	game.player_left.can_volley_from_feet()
	var kitchen := solve("kitchen_history")
	if kitchen.visible: check(kitchen.total_bounces >= 1, "kitchen history admitted a volley")
	prepare()
	game.player_left.bounds_ready = false
	check(not solve("unknown_bounds").visible, "unverified bounds invented a target")
	game.player_left.bounds_ready = true
	prepare(); game.player_left.is_jumping = true
	check(not solve("jumping").visible, "ground-route advisor predicted unknown airborne plant")
	game.player_left.is_jumping = false

func stale_and_cache_cases() -> void:
	prepare()
	current_case = "cache"
	var advisor = Advisor.new()
	var flight := trace()
	var initial: Dictionary = advisor.update(0.0, game.player_left, game.ball, flight)
	check(initial.visible, "cache fixture lacked target")
	var first_time: float = initial.remaining_time
	for frame in range(1, int(rate / 10)):
		var next: Dictionary = flight.samples[1]
		game.ball.global_position = next.pos
		game.ball.linear_velocity = next.vel
		game.ball.angular_velocity = next.omega
		game.ball.bounces_since_last_hit += int(next.bounces)
		flight = trace()
		var cached: Dictionary = advisor.update(1.0 / rate, game.player_left, game.ball, flight)
		check(cached.visible and cached.remaining_time < first_time, "cached countdown did not age")
	check(advisor.statistics.solves == 1, "search ran faster than 10 Hz")
	check(advisor.statistics.traces == 0, "cache requested duplicate ball trace")
	var returned: Dictionary = advisor.update(0.0, game.player_left, game.ball, flight)
	returned.target_root = Vector3.INF
	var copy_check: Dictionary = advisor.update(0.0, game.player_left, game.ball, flight)
	check(copy_check.visible and copy_check.get("target_root", Vector3.INF).is_finite(), "caller mutated internal cache")
	game.ball.flight_id += 1
	check(not advisor.update(0.0, game.player_left, game.ball, flight).visible, "changed flight reused stale marker")
	check(advisor.statistics.solves == 1, "flight invalidation bypassed rate limit")
	advisor.update(0.11, game.player_left, game.ball, flight)
	game.ball.bounces_since_last_hit += 1
	var after_bounce: Dictionary = advisor.update(0.0, game.player_left, game.ball, flight)
	check(not after_bounce.visible or (after_bounce.get("persisted", false) and after_bounce.total_bounces >= game.ball.bounces_since_last_hit), "bounce reused an unvalidated stale marker")
	advisor.update(0.11, game.player_left, game.ball, flight)
	check(not advisor.update(0.0, game.player_left, game.ball, flight, false).visible, "inactive gate retained guidance")
	prepare()
	advisor = Advisor.new(); advisor.update(0.0, game.player_left, game.ball, trace())
	game.ball.global_position.x += 1.0
	check(not advisor.update(0.0, game.player_left, game.ball).visible, "same-flight teleport reused marker")
	prepare()
	advisor = Advisor.new(); advisor.update(0.0, game.player_left, game.ball, trace())
	game.ball.linear_velocity.x += 5.0
	check(not advisor.update(0.0, game.player_left, game.ball).visible, "velocity discontinuity reused marker")
	prepare()
	advisor = Advisor.new(); advisor.update(0.0, game.player_left, game.ball, trace())
	paused = true
	check(not advisor.update(0.0, game.player_left, game.ball).visible, "paused game retained guidance")
	paused = false
	prepare()
	advisor = Advisor.new(); advisor.update(0.0, game.player_left, game.ball, trace())
	game.player_left.posture.editor_preview_mode = true
	check(not advisor.update(0.0, game.player_left, game.ball).visible, "editor retained gameplay guidance")
	game.player_left.posture.editor_preview_mode = false
	prepare()
	advisor = Advisor.new()
	var stale := trace(); stale.samples[0].pos += Vector3.RIGHT
	game.player_left.debug_visual._last_flight = {}
	advisor.update(0.0, game.player_left, game.ball, stale)
	check(advisor.statistics.traces == 1 and advisor.statistics.reused_flights == 0, "stale predictor data falsely reused")
	prepare()
	advisor = Advisor.new()
	game.player_left.debug_visual._last_flight = trace()
	advisor.update(0.0, game.player_left, game.ball)
	check(advisor.statistics.traces == 0 and advisor.statistics.reused_flights == 1, "existing player flight cache not reused")
	var solves_before: int = advisor.statistics.solves
	for frame in range(rate):
		var next: Dictionary = trace().samples[1]
		game.ball.global_position = next.pos
		game.ball.linear_velocity = next.vel
		game.ball.angular_velocity = next.omega
		game.ball.bounces_since_last_hit += int(next.bounces)
		advisor.update(1.0 / rate, game.player_left, game.ball, trace())
	check(advisor.statistics.solves - solves_before <= 10, "one-second refresh cadence exceeds 10 Hz")
	advisor.reset()
	check(not advisor.update(0.0, game.player_left, game.ball, trace()).visible, "reset displayed a retained target before rate limit")

func immediate_reach_evidence_cases() -> void:
	prepare()
	current_case = "immediate_standing_evidence"
	var player = game.player_left
	var human = player.posture.human_contact
	player.global_position.x = 0.7
	player.leg_ik.feet_initialized = false; player._process(0.0); player.can_volley_from_feet()
	var advisor = Advisor.new()
	var flight := trace()
	var initial: Dictionary = advisor.update(0.0, player, game.ball, flight)
	check(initial.visible, "near-standing fixture lacked initial outside-reach cue")
	if not initial.visible: return
	# Geometry-valid stale controller evidence must not suppress the live cue.
	var base: PostureDefinition = PostureLibrary.instance().get_def(0)
	var false_point: Vector3 = player.global_position + base.resolve_paddle_offset(player._get_forehand_axis(), player._get_forward_axis())
	human._flight_id = game.ball.flight_id
	human.contact = {"def": base, "point": false_point, "time": 1.0, "bounces": 0}
	var before := state_fingerprint()
	check(advisor.update(0.005, player, game.ball, flight).visible, "stale same-flight point falsely suppressed cue")
	check(state_fingerprint() == before, "stale contact verification mutated live history")
	player.global_position = initial.target_root
	player.leg_ik.feet_initialized = false; player._process(0.0); player.can_volley_from_feet()
	human.contact = Planner.select(Advisor.snapshot(player), game.ball, flight)
	human._flight_id = game.ball.flight_id
	check(not human.contact.is_empty(), "indicated root did not provide a standing contact")
	before = state_fingerprint()
	var result: Dictionary = advisor.update(0.005, player, game.ball, flight)
	check(not result.visible and result.reason == "already_in_reach", "standing entry lingered until 10 Hz refresh")
	check(advisor.statistics.solves == 1, "immediate standing suppression started a full solve")
	check(state_fingerprint() == before, "standing suppression mutated controller or feet")
	check(advisor.statistics.traces == 0, "standing suppression retraced flight")

func budget_cases() -> void:
	prepare()
	current_case = "manual_budget"
	var player = game.player_left
	var target: Vector3 = player.global_position + Vector3.RIGHT * 3.0
	var stopped: Dictionary = Advisor.travel_budget(player, target, 0.12)
	check(stopped.speed == player.move_speed, "manual speed not read from actual player")
	check(stopped.required_time > stopped.required_travel / stopped.speed + stopped.plant_time, "time lacks inertia/strike reserve")
	player.current_velocity = Vector3.LEFT * player.move_speed
	var reversed: Dictionary = Advisor.travel_budget(player, target, 0.12)
	check(reversed.required_time > stopped.required_time, "opposite momentum did not increase budget")
	player.current_velocity = Vector3.ZERO
	player.stamina.value = 0.0
	var tired: Dictionary = Advisor.travel_budget(player, target, 0.12)
	check(tired.speed < stopped.speed and tired.required_time > stopped.required_time, "stamina speed limit ignored")
	player.stamina.reset_match()

func no_time_cases() -> void:
	prepare()
	game.ball.global_position = Vector3(3.0, 0.55, 4.0)
	game.ball.linear_velocity = Vector3(0.0, -4.0, 0.3)
	game.ball.angular_velocity = Vector3.ZERO
	game.ball.bounces_since_last_hit = 1
	var late := solve("proven_no_time")
	check(late.visible and late.status == "NO_TIME", "obvious late legal flight lacks lower-bound proof")
	prepare()
	game.player_left.min_x = 0.0; game.player_left.max_x = 0.0
	game.player_left.min_z = 4.7; game.player_left.max_z = 4.7
	var miss := solve("bounded_search_miss")
	check(not miss.visible and miss.status == "UNKNOWN" and not miss.no_time_proven, "search miss was labeled impossible")
	# Restore actual court bounds from the opposite player (mirrored z).
	game.player_left.min_x = game.player_right.min_x; game.player_left.max_x = game.player_right.max_x
	game.player_left.min_z = -game.player_right.max_z; game.player_left.max_z = -game.player_right.min_z

func mirrored_case() -> void:
	prepare()
	current_case = "mirrored_sides"
	var original: Dictionary = Advisor.new().update(0.0, game.player_left, game.ball, trace())
	var player = game.player_right
	player.global_position = Vector3(0.0, player.ground_y, -4.7)
	player.current_velocity = Vector3.ZERO
	player.hitting.clear_charge_visual(); player.hitting.serving_visual_active = false
	player.leg_ik.feet_initialized = false; player._process(0.0); player.can_volley_from_feet()
	game.ball.global_position = Vector3(-game.ball.global_position.x, game.ball.global_position.y, -game.ball.global_position.z)
	game.ball.linear_velocity = Vector3(-game.ball.linear_velocity.x, game.ball.linear_velocity.y, -game.ball.linear_velocity.z)
	game.ball.angular_velocity = Vector3(-game.ball.angular_velocity.x, game.ball.angular_velocity.y, -game.ball.angular_velocity.z)
	game.ball.last_hit_by = 0
	var mirrored: Dictionary = Advisor.new().update(0.0, player, game.ball, trace())
	check(original.visible and mirrored.visible, "mirrored feed lost candidate")
	if original.visible and mirrored.visible:
		check(original.posture == mirrored.posture, "mirroring changed anatomical stroke")
		check(original.target_root.distance_to(Vector3(-mirrored.target_root.x, mirrored.target_root.y, -mirrored.target_root.z)) < 0.002, "target does not mirror with court side")
		records.append({"case": "mirrored", "original": original, "mirrored": mirrored})

func continuous_trajectory() -> void:
	prepare()
	current_case = "advancing_real_flight"
	var advisor = Advisor.new()
	var shown := 0
	var bounces := 0
	for frame in range(int(rate * 1.6)):
		var flight := trace()
		var before := state_fingerprint(false)
		var result: Dictionary = advisor.update(1.0 / rate, game.player_left, game.ball, flight)
		check(state_fingerprint(false) == before, "advancing solve changed controller state")
		if result.visible:
			shown += 1
			check(result.remaining_time > 0.0 and result.target_root.is_finite(), "live cache displayed stale/nonfinite target")
		var next: Dictionary = flight.samples[1]
		game.ball.global_position = next.pos
		game.ball.linear_velocity = next.vel
		game.ball.angular_velocity = next.omega
		game.ball.bounces_since_last_hit += int(next.bounces)
		bounces += int(next.bounces)
		if game.ball.bounces_since_last_hit >= 2: break
	check(shown > rate / 2, "incoming flight did not sustain useful guidance")
	check(advisor.statistics.solves <= 17, "live simulation exceeded 10 Hz")
	check(advisor.statistics.traces == 0, "live simulation retraced cached physical flight")
	solve_times.append(advisor.statistics.max_solve_usec)
	records.append({"case": current_case, "shown_frames": shown, "bounces": bounces, "statistics": advisor.statistics})

func state_fingerprint(include_resources: bool = true) -> String:
	var player = game.player_left
	var human = player.posture.human_contact
	var state := {"root": player.global_transform, "velocity": player.velocity, "current_velocity": player.current_velocity,
		"manual_active": player._manual_motion_active, "jump": player.is_jumping,
		"nvz": values(player._nvz_state), "feet": values(player.leg_ik), "human": values(human),
		"footwork": values(human.footwork), "hitting": values(player.hitting), "posture": values(player.posture),
		"ball": [game.ball.global_transform, game.ball.linear_velocity, game.ball.angular_velocity,
			game.ball.flight_id, game.ball.bounces_since_last_hit, game.ball.is_in_play, game.ball.last_hit_by],
		"input": [Input.is_action_pressed("ui_accept"), Input.is_action_pressed("move_left"), Input.is_action_pressed("move_right")]}
	if include_resources:
		var resources: Array = []
		for definition in PostureLibrary.instance().all_definitions(): resources.append(resource_state(definition))
		state.resources = resources
	return var_to_str(state)

func values(object) -> Dictionary:
	var result: Dictionary = {}
	for field in object.get_property_list():
		if not (field.usage & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
		var value = object.get(field.name)
		if value is Object: continue
		result[field.name] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result

func resource_state(value):
	if value is Script: return value.resource_path
	if value is Resource:
		var result: Dictionary = {}
		for field in value.get_property_list():
			if field.usage & PROPERTY_USAGE_STORAGE: result[field.name] = resource_state(value.get(field.name))
		for key in value.get_meta_list(): result["meta/" + str(key)] = resource_state(value.get_meta(key))
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(resource_state(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[key] = resource_state(value[key])
		return result
	return value
