extends "res://scripts/tests/test_human_incoming_contact.gd"
const ActivationZones = preload("res://scripts/contact_activation_zones.gd")
const WristReach = preload("res://scripts/paddle_wrist_reach.gd")


const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Geometry = preload("res://scripts/paddle_clearance.gd")
const CourtSide = preload("res://scripts/tests/test_stroke_orientation.gd").CourtSide
var observations: Array[Dictionary] = []
var planned: = 0
var excluded: = 0
var minimum_floor_clearance: = INF
var maximum_grip_reach: = 0.0
var grip_overreach: Array[String] = []
var maximum_live_grip_reach: = 0.0

class IncomingBall extends RefCounted:
	var is_in_play: = true
	var last_hit_by: = 1
	var bounces_since_last_hit: = 1
	var both_bounces_complete: = true
	var global_position: = Vector3.ZERO
	var linear_velocity: = Vector3.BACK * 4.0

func _point(player, lateral: float, height: float, forward: float) -> Vector3:
	return Vector3(player.global_position.x, height, player.global_position.z) + player._get_forehand_axis() * lateral + player._get_forward_axis() * forward

func _low_floor_reach_audit() -> void :


	var player = CourtSide.new(0)
	player.global_position.z = 3.2
	player.global_transform.origin = player.global_position
	var surface: Array[Vector3] = Geometry.sample_head_surface()
	for id in [5, 6, 7, 18, 19]:
		var def: PostureDefinition = PostureLibrary.instance().get_def(id)
		for height in [0.2, 0.25, 0.3, 0.35, 0.375]:
			var pose: PostureDefinition = Planner.pose_at(player, def, _point(player, def.paddle_forehand_mul, height, def.zone_forward_offset))
			var floor_clearance: = INF
			var grip_reach: = 0.0
			for power in [0.3, 0.65, 1.0]:
				for step in range(65):
					var sampled: PostureDefinition = Motion.sample_drive(pose, step / 64.0, power, false, 0, false)
					var basis: Basis = Path.paddle_basis(player, sampled)
					var head: Vector3 = player.global_position + sampled.resolve_paddle_offset(player._get_forehand_axis(), player._get_forward_axis())
					var raw: = Transform3D(basis, head - basis.y * PaddleSize.HEAD_CENTER_Y)
					var offset: Vector3 = sampled.left_hand_offset if sampled.paddle_hand == 1 else sampled.right_hand_offset
					grip_reach = maxf(grip_reach, WristReach.wrist_world(raw, sampled).distance_to(Body.shoulder_world(player, sampled)))
					for vertex in surface: floor_clearance = minf(floor_clearance, (raw * vertex).y - player.COURT_FLOOR_Y)
			print("LOW FLOOR AUDIT: %s world_y=%.3f min_raw_floor=%.3f max_raw_grip=%.3f" % [def.display_name, height, floor_clearance, grip_reach])

func _rejection_summary(player, ball) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var samples: Array = Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity).samples
	for def in PostureLibrary.instance().all_definitions():
		if not def.has_zone: continue
		for i in range(samples.size() - 1):
			var a: Dictionary = samples[i]
			var b: Dictionary = samples[i + 1]
			var da: float = (a.pos - player.global_position).dot(player._get_forward_axis()) - def.zone_forward_offset
			var db: float = (b.pos - player.global_position).dot(player._get_forward_axis()) - def.zone_forward_offset
			if da < 0 or db > 0 or da - db < 1e-05 or a.bounces != b.bounces: continue
			var point: Vector3 = a.pos.lerp(b.pos, da / (da - db))
			var lateral: float = (point - player.global_position).dot(player._get_forehand_axis())
			var height: float = point.y - player.COURT_FLOOR_Y
			var zone_miss: float = maxf(0.0, maxf(def.zone_x_min - 0.03 - lateral, lateral - def.zone_x_max - 0.03)) + maxf(0.0, maxf(def.zone_y_min - 0.03 - height, height - def.zone_y_max - 0.03))
			var pose: PostureDefinition = Planner.pose_at(player, def, point)
			var hand_offset: Vector3 = pose.left_hand_offset if pose.paddle_hand == 1 else pose.right_hand_offset
			var grip: Vector3 = point + Path.paddle_basis(player, pose) * ((PaddleSize.MAIN_GRIP_OFFSET - PaddleSize.HEAD_OFFSET) + hand_offset)
			candidates.append({"posture": def.posture_id, "height": point.y, "zone_miss": zone_miss, "grip": grip.distance_to(Body.shoulder_world(player, pose)), "floor_ok": height >= def.paddle_floor_clearance, "legal": Planner.legal_ball(player, ball, b.bounces)})
			break
	candidates.sort_custom( func(a, b): return a.zone_miss < b.zone_miss)
	return candidates.slice(0, 3)

func _boundary_checks() -> void :
	var surface: Array[Vector3] = Geometry.sample_head_surface()
	for side in range(2):
		var player = CourtSide.new(side)
		player.global_position.z = 3.2 if side == 0 else -3.2
		player.global_transform.origin = player.global_position
		var ball: = IncomingBall.new()
		ball.last_hit_by = 1 - side
		ball.linear_velocity = - player._get_forward_axis() * 4.0
		for def in PostureLibrary.instance().all_definitions():
			if not def.has_zone: continue
			for x in [def.zone_x_min - 0.031, def.zone_x_min, (def.zone_x_min + def.zone_x_max) / 2.0, def.zone_x_max, def.zone_x_max + 0.031]:
				for height in [player.COURT_FLOOR_Y + def.paddle_floor_clearance - 0.001, player.COURT_FLOOR_Y + def.zone_y_min, player.COURT_FLOOR_Y + (def.zone_y_min + def.zone_y_max) / 2.0, player.COURT_FLOOR_Y + def.zone_y_max, player.COURT_FLOOR_Y + def.zone_y_max + 0.031]:
					var point: = _point(player, x, height, def.zone_forward_offset)
					var fits: bool = Planner.point_fits(player, def, point)
					var tag: = "%s side%d x%.3f y%.3f" % [def.display_name, side, x, height]
					if not ActivationZones.contains(def, x, height - player.COURT_FLOOR_Y):
						check( not fits, tag + " outside-boundary point accepted")
					if fits:
						var pose: PostureDefinition = Planner.pose_at(player, def, point)
						var transform: Transform3D = Path.world_transform(player, pose)
						var hand_offset: Vector3 = pose.left_hand_offset if pose.paddle_hand == 1 else pose.right_hand_offset
						var grip_reach: float = WristReach.wrist_world(transform, pose).distance_to(Body.shoulder_world(player, pose))
						maximum_grip_reach = maxf(maximum_grip_reach, grip_reach)
						if grip_reach > 0.7001: grip_overreach.append(tag + " grip %.3f" % grip_reach)
						check(grip_reach <= WristReach.DEFAULT_LINK_BUDGET + WristReach.NUMERICAL_EPSILON, tag + " wrist exceeds physical arm reach")
						if pose.height_tier == 0 and pose.paddle_floor_clearance < 0.3:
							check(preload("res://scripts/finite_paddle_contact.gd").touches(transform, point, Ball.BALL_RADIUS), tag + " low blade cannot touch selected ball")
						else:
							check((transform * PaddleSize.HEAD_OFFSET).distance_to(point) < 0.0001, tag + " selected head is reach-clamped away from ball")
						check(point.distance_to(Body.shoulder_world(player, pose)) <= PaddleReach.MAX_HEAD_DISTANCE + 1e-05, tag + " beyond shoulder reach")
						for vertex in surface:
							minimum_floor_clearance = minf(minimum_floor_clearance, (transform * vertex).y - player.COURT_FLOOR_Y)
					var behind: = _point(player, x, height, -0.001)
					check( not Planner.point_fits(player, def, behind), tag + " behind-player contact accepted")
			var center: = _point(player, def.paddle_forehand_mul, player.global_position.y + def.paddle_y_offset, def.zone_forward_offset)
			ball.global_position = center + player._get_forward_axis() * 0.8
			var samples: Array[Dictionary] = [{"pos": ball.global_position, "time": 0.0, "bounces": 0}, {"pos": center - player._get_forward_axis() * 0.2, "time": 0.25, "bounces": 0}]
			var plan: Dictionary = Planner.select(player, ball, {"samples": samples})
			check( not plan.is_empty(), "%s side%d authored zone has no incoming plan" % [def.display_name, side])
			if not plan.is_empty(): check(Planner.point_fits(player, plan.def, plan.point), "planner returned invalid contact")
			ball.bounces_since_last_hit = 2
			check(Planner.select(player, ball, {"samples": samples}).is_empty(), "second-bounce contact accepted")
			ball.bounces_since_last_hit = 0
			ball.both_bounces_complete = false
			check(Planner.select(player, ball, {"samples": samples}).is_empty(), "pre-double-bounce volley accepted")
			ball.both_bounces_complete = true
			var old_z: float = player.global_position.z
			player.global_position.z = 1.9 if side == 0 else -1.9
			check( not Planner.legal_ball(player, ball), "kitchen airborne ball legal")
			player.global_position.z = PickleballConstants.NON_VOLLEY_ZONE * (1 if side == 0 else -1)
			check( not Planner.legal_ball(player, ball), "volley on kitchen boundary line accepted")
			ball.bounces_since_last_hit = 1
			check(Planner.legal_ball(player, ball), "kitchen groundstroke rejected")
			player.global_position.z = old_z
			var opposite: = center
			opposite.z = - old_z
			check( not Planner.point_fits(player, def, opposite), "opposite-court point accepted")
	print("LOW ZONE GEOMETRY: %d checks; minimum sampled whole-paddle floor clearance %.3f m" % [checks, minimum_floor_clearance])
	check(minimum_floor_clearance >= 0.0, "accepted zone contact puts the paddle through the floor")

func _live_case(game, lane: float, height: float, speed: float, kitchen: bool, bounce_count: int = 1, behind: bool = false) -> void :
	var player = game.player_left
	var human = player.posture.human_contact
	human.cancel()
	player.hitting.clear_charge_visual()
	player.hitting.is_in_follow_through = false
	player.posture.transition_pose_blend = null
	player.global_position = Vector3(0, player.ground_y, 1.9 if kitchen else 3.2)
	game._set_game_state(game.GameState.PLAYING)
	game.rally_scorer.start_rally(0, true)
	game.rally_scorer._serve_was_hit = true
	var lead: = 0.85 / speed

	incoming(game, lane, height + 0.5 * 9.8 * lead * lead - 1.1 * lead, speed)
	game.ball.global_position.z = player.global_position.z - 1.35 if not behind else player.global_position.z + 0.25
	game.ball.bounces_since_last_hit = bounce_count
	game.ball.ball_bounced_since_last_hit = bounce_count > 0
	game.ball.linear_velocity.y = 1.1
	await physics_frame
	await physics_frame
	var initial: Dictionary = human.contact.duplicate()
	var tag: = "x%.3f y%.3f v%.0f %s b%d%s" % [lane, height, speed, "kitchen" if kitchen else "court", bounce_count, " behind" if behind else ""]
	var record: = {"tag": tag, "lane": lane, "height": height, "speed": speed, "kitchen": kitchen, "planned": not initial.is_empty(), "hit": false, "closest": INF, "posture": initial.get("posture", -1), "early_time": initial.get("time", -1.0)}
	var distances: Array[float] = []
	var live_grips: Array[float] = []
	var callback = func(id):
		if id == 0:
			distances.append(PaddleReach.head_world(player).distance_to(game.ball.global_position))
			var pose: PostureDefinition = player.get_runtime_posture_def()
			var hand_offset: Vector3 = pose.left_hand_offset if pose.paddle_hand == 1 else pose.right_hand_offset
			live_grips.append(WristReach.displayed_wrist(player, pose).distance_to(WristReach.live_shoulder(player, pose)))
	game.ball.hit_by_paddle.connect(callback)
	if initial.is_empty():
		excluded += 1
		record.rejection_candidates = _rejection_summary(player, game.ball)
		game._perform_player_swing(0.65)
		check(human.phase == -1 and game.ball.last_hit_by == 1, tag + " impossible shot queued or auto-hit")
	else:
		planned += 1
		check(Planner.point_fits(player, initial.def, initial.point), tag + " plan is unreachable")
		check(human.visual_pose != null and human.visual_pose.posture_id == initial.posture, tag + " early prepared pose disagrees with prediction")
		check(player.debug_visual.human_committed_contact_position.distance_to(initial.point) < 0.001, tag + " marker disagrees with prediction")
		Input.action_press("ui_accept")
		game.input_handler._handle_swing_charge(0.65 * PickleballConstants.MAX_SERVE_CHARGE_TIME)
		Input.action_release("ui_accept")
		game.input_handler._handle_swing_charge(0.0)
		check(distances.is_empty(), tag + " distant release auto-hit")
		for frame in range(ceili(float(Engine.physics_ticks_per_second) * 0.6)):
			var previous_ball: Vector3 = game.ball.global_position
			var previous_head: Vector3 = PaddleReach.head_world(player)
			var previous_phase: int = human.phase
			await physics_frame
			if OS.has_environment("GODOT_TEST_FAST_CONTACTS_ONLY"):
				print("LOW FAST TRACE: ", tag, " frame=", frame, " phase=", previous_phase, "->", human.phase, " ball=", previous_ball, "->", game.ball.global_position, " head=", previous_head, "->", PaddleReach.head_world(player), " rel=", previous_ball - previous_head, "->", game.ball.global_position - PaddleReach.head_world(player), " elapsed=", human.elapsed, " strike=", human.strike_time, " plan=", human.contact.get("posture", -1), " time=", human.contact.get("time", -1))
			record.closest = minf(record.closest, PaddleReach.head_world(player).distance_to(game.ball.global_position))
			if not distances.is_empty() or game.game_state != game.GameState.PLAYING: break
			if (game.ball.global_position - player.global_position).dot(player._get_forward_axis()) < -0.12: break
		if not distances.is_empty():
			returns += 1
			record.hit = true
			maximum_error = maxf(maximum_error, distances[0])
			maximum_live_grip_reach = maxf(maximum_live_grip_reach, live_grips[0])
			record.live_grip_reach = live_grips[0]
			check(distances.size() == 1 and distances[0] <= Planner.IMPACT_DISTANCE, tag + " nonphysical or duplicate impact")
		else:
			record.reason = "timing_or_pose_miss"
			print("LOW SWEEP MISS: ", record)
			check(false, tag + " misses its selected legal contact")
	game.ball.hit_by_paddle.disconnect(callback)
	game.ball.is_in_play = false
	observations.append(record)

func _transition_checks(game) -> void :
	var player = game.player_left
	var human = player.posture.human_contact
	for kitchen in [false, true]:
		human.cancel()
		player.hitting.clear_charge_visual()
		player.hitting.is_in_follow_through = false
		player.global_position = Vector3(0, player.ground_y, 1.9 if kitchen else 3.2)
		game._set_game_state(game.GameState.PLAYING)
		game.rally_scorer.start_rally(0, true)
		game.rally_scorer._serve_was_hit = true
		incoming(game, 0.42, 0.8, 4.0)
		game.ball.global_position.z = player.global_position.z - 2.9
		game.ball.linear_velocity.y = -4.0

		if kitchen:
			game.ball.global_position.z = 0.25
			game.ball.linear_velocity.z = 3.0
		game.ball.both_bounces_complete = false
		await physics_frame
		await physics_frame
		check(human.contact.is_empty() or human.contact.bounces > 0, "pre-bounce prediction attempts illegal volley")
		var chosen: bool = not human.contact.is_empty()
		check(chosen, "legal future bounce is not prepared (%s)" % ("kitchen" if kitchen else "court"))
		if chosen:
			print("LOW BOUNCE PLAN: kitchen=", kitchen, " contact=", human.contact.point, " posture=", human.contact.posture, " time=", human.contact.time)
			game._perform_player_swing(0.65)
			check(game.ball.last_hit_by == 1, "future-bounce release auto-hits")
			for frame in range(Engine.physics_ticks_per_second):
				await physics_frame
				if OS.has_environment("GODOT_TEST_TRANSITIONS_ONLY"):
					print("LOW BOUNCE TRACE: k=", kitchen, " frame=", frame, " phase=", human.phase, " pos=", game.ball.global_position, " plan=", human.contact.get("posture", -1), " time=", human.contact.get("time", -1), " err=", PaddleReach.head_world(player).distance_to(game.ball.global_position))
				if game.ball.last_hit_by == 0 or game.game_state != game.GameState.PLAYING: break
			check(game.ball.last_hit_by == 0, "future-bounce legal contact missed")
			check( not game.ball.was_volley, "post-bounce return counted as a volley")
		game.ball.is_in_play = false

	human.cancel()
	player.hitting.clear_charge_visual()
	player.hitting.is_in_follow_through = false
	player.global_position = Vector3(0, player.ground_y, 3.2)
	game._set_game_state(game.GameState.PLAYING)
	game.rally_scorer.start_rally(0, true)
	game.rally_scorer._serve_was_hit = true
	incoming(game, 0.42, 1.12, 4.0)
	await physics_frame
	await physics_frame
	check( not human.contact.is_empty(), "movement fixture has no first contact")
	if not human.contact.is_empty():
		human.set_charge(0.65)
		player.global_position.x = 0.85
		plant_fixture(player)
		await physics_frame
		check( not human.contact.is_empty() and human.contact.def.family == 1, "moving across flight does not reselect backhand")
		if not human.contact.is_empty():
			check(player.posture.transition_pose_blend.posture_id == human.contact.posture, "movement leaves stale held pose")
			game._perform_player_swing(0.65)
			for frame in range(Engine.physics_ticks_per_second):
				await physics_frame
				if game.ball.last_hit_by == 0 or game.game_state != game.GameState.PLAYING: break
			check(game.ball.last_hit_by == 0, "moved forehand-to-backhand contact missed")
	game.ball.is_in_play = false

	human.cancel()
	player.hitting.clear_charge_visual()
	player.hitting.is_in_follow_through = false
	player.global_position = Vector3(0, player.ground_y, 3.2)
	game._set_game_state(game.GameState.PLAYING)
	game.rally_scorer.start_rally(0, true)
	game.rally_scorer._serve_was_hit = true
	incoming(game, 0.42, 1.12, 6.0)
	for frame in range(ceili(Engine.physics_ticks_per_second * 0.45)):
		await physics_frame
		if game.game_state != game.GameState.PLAYING: break
	check(game.ball.last_hit_by == 1 and human.phase == -1, "automatic preparation returns without a release")
	game.ball.is_in_play = false

func run() -> void :
	var test_hz: int = int(OS.get_environment("GODOT_TEST_PHYSICS_HZ")) if OS.has_environment("GODOT_TEST_PHYSICS_HZ") else 60
	Engine.physics_ticks_per_second = test_hz
	create_timer(240.0).timeout.connect( func(): quit(2))
	if OS.has_environment("GODOT_TEST_LOW_FLOOR_ONLY"):
		_low_floor_reach_audit()
		quit()
		return
	_boundary_checks()
	var game = await setup_game()
	if OS.has_environment("GODOT_TEST_FAST_CONTACTS_ONLY"):
		await _live_case(game, -0.82, 1.12, 10.0, false)
		await _live_case(game, 0.42, 0.4, 10.0, false)
		await _live_case(game, 0.42, 0.4, 14.0, false)
		await _live_case(game, -0.43, 1.12, 14.0, false)
		print("FAST CONTACT RESULTS: ", failures)
		game.queue_free()
		await process_frame
		quit(0 if failures.is_empty() else 1)
		return
	if OS.has_environment("GODOT_TEST_TRANSITIONS_ONLY"):
		await _transition_checks(game)
		print("TRANSITION RESULTS: ", failures)
		print("GRIP OVERREACH: maximum=", maximum_grip_reach, " count=", grip_overreach.size(), " samples=", grip_overreach.slice(0, 20))
		game.queue_free()
		await process_frame
		quit(0 if failures.is_empty() else 1)
		return
	for kitchen in [false, true]:
		for lane in [-1.0, -0.82, -0.64, -0.43, -0.235, 0.0, 0.235, 0.42, 0.64, 0.82, 1.0]:
			for height in [0.3, 0.375, 0.4, 0.53, 0.61, 0.8, 1.12]:
				await _live_case(game, lane, height, 6.0, kitchen)
	for speed in [4.0, 10.0, 14.0]:
		for lane in [-0.82, -0.43, 0.0, 0.42, 0.82]:
			for height in [0.4, 0.61, 1.12]:
				await _live_case(game, lane, height, speed, false)
	for lane in [-3.0, 0.42, 3.0]:
		await _live_case(game, lane, 0.61, 6.0, false, 1, true)
		await _live_case(game, lane, 0.61, 6.0, true, 0)
	await _transition_checks(game)
	var report: = {"hz": test_hz, "checks": checks, "failures": failures, "planned": planned, "returns": returns, "excluded": excluded, "max_impact_error": maximum_error, "minimum_floor_clearance": minimum_floor_clearance, "maximum_grip_reach": maximum_grip_reach, "maximum_live_grip_reach": maximum_live_grip_reach, "grip_overreach": grip_overreach, "observations": observations}
	var output: = FileAccess.open("/tmp/low-return-zone-sweep-%d.json" % test_hz, FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("LOW RETURN ZONE SWEEP: %d checks, %d failures; %d/%d selected legal contacts returned, %d excluded; maximum impact error %.3f m" % [checks, failures.size(), returns, planned, excluded, maximum_error])
	quit(0 if failures.is_empty() else 1)
