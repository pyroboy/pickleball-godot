extends SceneTree
const WristReach = preload("res://scripts/paddle_wrist_reach.gd")
const PaddleDimensions = preload("res://scripts/paddle_dimensions.gd")
const Planner = preload("res://scripts/incoming_contact_planner.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Geometry = preload("res://scripts/paddle_clearance.gd")
var checks: = 0
var failures: Array[String] = []
var game
var live_hits: = 0
var long_cases: Array = []
var physical_paddle_contacts: Array = []
var registered_contacts: Array = []
func handle_gap(local: Vector3) -> float:
	var q: = Vector2(Vector2(local.x, local.z).length() - PaddleDimensions.HANDLE_RADIUS, absf(local.y - PaddleDimensions.HANDLE_CENTER_Y) - PaddleDimensions.HANDLE_LENGTH * 0.5)
	return q.max(Vector2.ZERO).length() + minf(maxf(q.x, q.y), 0.0) - Ball.BALL_RADIUS
func _initialize(): call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func plant(player) -> void :
	player.leg_ik.feet_initialized = false
	player._process(0.0)
	player.can_volley_from_feet()
func run() -> void :
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	game.input_handler.set_process(false)
	game.reaction_button.auto_fire_on_perfect = false
	for team in [0, 1]:
		var player = game.player_left if team == 0 else game.player_right
		player.global_position = Vector3(0, player.ground_y, 3.3 if team == 0 else -3.3)
		player.current_velocity = Vector3.ZERO
		plant(player)
		var found: = 0
		var leaned: = 0
		for base in PostureLibrary.instance().all_definitions():
			if not base.has_zone: continue
			for extra in [0.22, 0.32, 0.42]:
				var front: float = base.zone_forward_offset + extra
				var point: Vector3 = player.global_position + player._get_forehand_axis() * ((base.zone_x_min + base.zone_x_max) * 0.5) + player._get_forward_axis() * front
				point.y = player.COURT_FLOOR_Y + (base.zone_y_min + base.zone_y_max) * 0.5
				var pose: PostureDefinition = Planner.balanced_reach_pose(player, base, point)
				if pose == null: continue
				if pose.has_meta("extended_reach"):
					leaned += 1
					check(pose.body_pitch_deg - base.body_pitch_deg <= 8.0001 and pose.torso_pitch_deg - base.torso_pitch_deg <= 4.0001 and pose.crouch_amount - base.crouch_amount <= 0.02001, "reach exceeded bounded balanced lean")
					check(pose.weight_shift <= 1.0 and pose.weight_shift - base.weight_shift <= 0.45001, "reach exaggerated body weight shift")
				game.ball.is_in_play = true;game.ball.last_hit_by = 1 - team;game.ball.both_bounces_complete = true;game.ball.bounces_since_last_hit = 0
				game.ball.global_position = point + player._get_forward_axis() * 0.08
				game.ball.linear_velocity = - player._get_forward_axis() * 0.3
				var flight: Dictionary = {"samples": [{"pos": point + player._get_forward_axis() * 0.02, "time": 0.1, "bounces": 0}, {"pos": point, "time": 0.14, "bounces": 0}]}
				var selected: Dictionary = Planner.select(player, game.ball, flight)
				check( not selected.is_empty(), "P%d valid extended point not selected pose%d extra%.2f" % [team, base.posture_id, extra])
				if selected.is_empty(): continue
				check(Planner.point_fits(player, selected.def, selected.point), "extended selection broke exact grip/head reach")
				var wrist: Vector3 = WristReach.wrist_from_head(selected.point, Path.paddle_basis(player, selected.def), selected.def)
				check(wrist.distance_to(Body.shoulder_world(player, selected.def)) <= WristReach.link_budget(player, selected.def) + WristReach.NUMERICAL_EPSILON, "extended wrist exceeds physical arm length")
				found += 1
				if team == 0 and extra >= 0.32 and base.family in [0, 1] and base.height_tier == 2: long_cases.append({"point": point, "posture": base.posture_id, "extra": extra})
		check(found >= 3, "P%d lacks multiple genuine extended reach candidates" % team)
		check(leaned > 0, "P%d has no validated lean-assisted reach candidate" % team)
		print("EXTENDED CANDIDATES team=", team, " accepted=", found, " bounded_lean=", leaned)
		game.ball.both_bounces_complete = false
		check(Planner.select_extended(player, game.ball, {"samples": [{"pos": game.ball.global_position, "time": 0.1, "bounces": 0}]}).is_empty(), "extended reach bypassed opening bounce rule")
		game.ball.both_bounces_complete = true
		var far: Vector3 = player.global_position + player._get_forward_axis() * 2.0
		far.y = 1.1
		check(Planner.select_extended(player, game.ball, {"samples": [{"pos": far, "time": 0.1, "bounces": 0}]}).is_empty(), "extended reach manufactured an impossible contact")
	game.ball.hit_by_paddle.connect( func(team):
		if team == 0:
			live_hits += 1
			var human = game.player_left.posture.human_contact
			var evidence: Dictionary = human.last_contact_evidence.duplicate()
			evidence["strike_time"] = human.strike_time
			evidence["committed_flight"] = human.swing_flight_id
			if evidence.has("raw_paddle") and evidence.has("raw_ball"):
				evidence["raw_local"] = evidence.raw_paddle.affine_inverse() * evidence.raw_ball
				evidence["raw_handle_gap"] = handle_gap(evidence.raw_local)
			registered_contacts.append({"physics_frame": Engine.get_physics_frames(), "evidence": evidence, "physical_contacts_before": physical_paddle_contacts.size()})
			check(absf(Geometry.distance_to_head_shape(game.player_left.paddle_node.to_local(game.ball.global_position)) - 0.0375) <= 0.0051, "live long return missed actual paddle surface")
	)
	game.ball.body_entered.connect( func(body):
		if body != game.player_left.paddle_node: return
		var local: Vector3 = body.to_local(game.ball.global_position)
		physical_paddle_contacts.append({"physics_frame": Engine.get_physics_frames(), "phase": game.player_left.posture.human_contact.phase, "elapsed": game.player_left.posture.human_contact.elapsed, "velocity": game.ball.linear_velocity, "world": game.ball.global_position, "paddle": body.global_transform, "local": local, "handle_gap": handle_gap(local), "head_gap": Geometry.distance_to_head_shape(local) - Ball.BALL_RADIUS, "paddle_gap": Geometry.distance_to_paddle_shape(local) - Ball.BALL_RADIUS})
	)
	for index in mini(3, long_cases.size()): await live_case(long_cases[index], index)
	for offset in [Vector3(1, 0.12, - 0.25), Vector3(1, 0.12, - 0.5)]:
		await live_case({"point": Vector3( - 0.4634, 1.2476, 2.5394), "posture": 2, "extra": 0.32, "origin_offset": offset, "required": offset.z < - 0.3, "handle_first_negative": offset.z > - 0.3}, 3)
	check(live_hits > 0, "no extended candidate became an actual paddle return")
	await verify_raw_engine_samples()
	var file = FileAccess.open("/tmp/extended-contact-evidence.json", FileAccess.WRITE);file.store_string(JSON.stringify({"failures": failures, "physical": physical_paddle_contacts, "registered": registered_contacts}, "\t"));file.close()
	game.queue_free(); await process_frame; await process_frame


	var audio_deadline: int = Time.get_ticks_usec() + 150000
	while Time.get_ticks_usec() < audio_deadline:
		OS.delay_msec(5)
		await process_frame
	await process_frame; await process_frame
	for failure in failures: push_error(failure)
	print("EXTENDED PADDLE REACH: %d checks, %d failures; live hits=%d" % [checks, failures.size(), live_hits])
	quit(0 if failures.is_empty() else 1)
func live_case(data: Dictionary, index: int) -> void :
	game._reset_ball()
	game._set_game_state(game.GameState.PLAYING);game.rally_scorer._serve_was_hit = true
	var player = game.player_left
	player.global_position = Vector3(0, player.ground_y, 3.3)



	player.hitting.clear_charge_visual();player.hitting.serving_visual_active = false
	plant(player)
	game.player_right.set_ai_movement_enabled(false)
	var origin: Vector3 = data.point + data.get("origin_offset", - player._get_forehand_axis() * 1.0 + player._get_forward_axis() * 0.08 + Vector3.UP * 0.12)
	var launch: Dictionary = game.practice_launcher.solve_airborne_feed(origin, data.point, 0.42)
	game.ball.reset_rally_state();game.ball.both_bounces_complete = true;game.ball.is_in_play = true;game.ball.last_hit_by = 1
	game.ball.global_position = origin;game.ball.linear_velocity = launch.velocity;game.ball.angular_velocity = launch.omega;game.ball.flight_id += 1
	await physics_frame; await physics_frame
	var human = player.posture.human_contact
	Input.action_press("ui_accept");game.input_handler._handle_swing_charge(0.08)
	for frame in range(4): await physics_frame
	check(player.hitting.charge_visual_active and human.phase < 0 and human._charge_target_pose != null, "desktop held input did not own preparation")
	Input.action_release("ui_accept");game.input_handler._handle_swing_charge(0.0)
	check( not game.aim_focus.active, "desktop release did not restore real time")
	var phases: Dictionary = {}
	var extended_seen: bool = human.contact.get("extended", false)
	var hits_before: = live_hits
	var contacts_before: int = physical_paddle_contacts.size()
	for frame in range(180):
		await physics_frame
		phases[human.phase] = true
		extended_seen = extended_seen or human.contact.get("extended", false)
		if not game.ball.is_in_play or (live_hits > hits_before and human.phase < 0): break
	var returned: bool = live_hits > hits_before
	print("EXTENDED LIVE ", index, " source=", data, " phases=", phases, " hit=", returned)
	if returned: check(phases.has(2) and phases.has(4), "live release skipped finish/recovery")
	if data.get("required", false):
		check(returned, "reachable angled backhand failed real paddle return")
		check(extended_seen and human.swing_def != null and human.swing_def.posture_id == 2, "angled backhand did not exercise the extended backhand path")

	if data.get("handle_first_negative", false):
		if returned:
			var evidence: Dictionary = human.last_contact_evidence
			check( not evidence.get("swept", true), "later head contact must not sweep across handle rebound")
			check(float(evidence.get("raw_gap", INF)) <= Geometry.contact_surface_tolerance(), "later actual paddle did not reach finite head")


		check(physical_paddle_contacts.size() > contacts_before, "handle-first fixture did not reach the physical paddle")
		if physical_paddle_contacts.size() > contacts_before:
			var first: Dictionary = physical_paddle_contacts[contacts_before]
			check(first.head_gap > Geometry.MAX_CONTACT_SURFACE_GAP and first.paddle_gap <= 0.001, "known contact no longer classified handle-only")
			print("HANDLE FIRST NEGATIVE ", first)

func verify_raw_engine_samples() -> void :


	game.process_mode = Node.PROCESS_MODE_DISABLED;game.ball.freeze = true
	var probe = load("res://scenes/paddle.tscn").instantiate()
	probe.collision_layer = 1024;probe.collision_mask = 0;root.add_child(probe)
	var query: = PhysicsShapeQueryParameters3D.new()
	var sphere: = SphereShape3D.new();sphere.radius = Ball.BALL_RADIUS
	query.shape = sphere;query.collision_mask = 1024;query.margin = 0.0
	for contact in physical_paddle_contacts:
		probe.global_transform = contact.paddle
		await physics_frame; await physics_frame
		query.transform = Transform3D(Basis.IDENTITY, contact.world)
		var actual: Dictionary = {"head": false, "handle": false}
		for result in probe.get_world_3d().direct_space_state.intersect_shape(query, 8):
			if result.collider != probe: continue
			if result.shape == 0: actual.head = true
			elif result.shape == 1: actual.handle = true
		contact["independent_engine_shapes"] = actual
		check(actual.handle and not actual.head, "first recorded handle-only collision independently classified")
	for contact in registered_contacts:
		var evidence: Dictionary = contact.evidence
		probe.global_transform = evidence.raw_paddle
		await physics_frame; await physics_frame
		query.transform = Transform3D(Basis.IDENTITY, evidence.raw_ball)
		var actual: Dictionary = {"head": false, "handle": false}
		for result in probe.get_world_3d().direct_space_state.intersect_shape(query, 8):
			if result.collider != probe: continue
			if result.shape == 0: actual.head = true
			elif result.shape == 1: actual.handle = true
		evidence["independent_engine_shapes"] = actual
		check(actual.head, "registered direct raw transform lacks real engine head overlap")
		check(evidence.phase == 1 and evidence.elapsed <= evidence.strike_time + 0.1 and evidence.flight == evidence.committed_flight, "registered sample lost legal strike ownership/window")
	probe.queue_free(); await process_frame
