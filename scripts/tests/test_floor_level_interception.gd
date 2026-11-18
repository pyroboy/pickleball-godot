extends "res://scripts/tests/test_human_incoming_contact.gd"

# A ball's center and a finite paddle's head center are different targets at
# floor level. These checks deliberately never use IMPACT_DISTANCE as a gate.
const Zones = preload("res://scripts/contact_activation_zones.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Wrist = preload("res://scripts/paddle_wrist_reach.gd")
const Geometry = preload("res://scripts/paddle_clearance.gd")
const Finite = preload("res://scripts/finite_paddle_contact.gd")
const Dimensions = preload("res://scripts/paddle_dimensions.gd")
const CourtSide = preload("res://scripts/tests/test_stroke_orientation.gd").CourtSide
const HEIGHTS = [0.0375, 0.06, 0.10, 0.20, 0.299, 0.30]
const LANES = [-0.42, -0.10, 0.0, 0.10, 0.42]
var records: Array[Dictionary] = []
var snapshots: Dictionary = {}
var source_hashes: Dictionary = {}
var red_returns := 0
var planned := 0
var tested := 0
var minimum_paddle_floor := INF
var maximum_wrist := 0.0
var maximum_center_gap := 0.0
var surface: Array[Vector3] = []

class IncomingBall extends RefCounted:
	var is_in_play := true
	var last_hit_by := 1
	var bounces_since_last_hit := 1
	var both_bounces_complete := true
	var global_position := Vector3.ZERO
	var linear_velocity := Vector3.BACK * 6.0

func point(player, lateral: float, height: float, front: float) -> Vector3:
	return Vector3(player.global_position.x, player.COURT_FLOOR_Y + height, player.global_position.z) + player._get_forehand_axis() * lateral + player._get_forward_axis() * front

func snapshot(value):
	if value is Script: return value.resource_path
	if value is Resource:
		var result: Dictionary = {}
		for field in value.get_property_list():
			if field.usage & PROPERTY_USAGE_STORAGE and not str(field.name).begins_with("metadata/"):
				result[field.name] = snapshot(value.get(field.name))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[key] = snapshot(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(snapshot(item))
		return result
	return value

func flight_for(player, ball, lateral: float, height: float) -> Dictionary:
	ball.global_position = point(player, lateral, height, 1.0)
	return {"samples": [{"pos": ball.global_position, "time": 0.0, "bounces": 0}, {"pos": point(player, lateral, height, 0.20), "time": 0.16, "bounces": 0}]}

func assert_geometry(player, pose: PostureDefinition, ball_point: Vector3, tag: String) -> Dictionary:
	var transform: Transform3D = Path.world_transform(player, pose)
	var head: Vector3 = transform * Dimensions.HEAD_OFFSET
	var wrist: Vector3 = Wrist.wrist_world(transform, pose)
	var reach := wrist.distance_to(Body.shoulder_world(player, pose))
	var floor_min := INF
	for vertex in surface: floor_min = minf(floor_min, (transform * vertex).y - player.COURT_FLOOR_Y)
	var gap := Geometry.distance_to_head_shape(transform.affine_inverse() * ball_point) - Ball.BALL_RADIUS
	minimum_paddle_floor = minf(minimum_paddle_floor, floor_min)
	maximum_wrist = maxf(maximum_wrist, reach)
	maximum_center_gap = maxf(maximum_center_gap, head.distance_to(ball_point))
	check(transform.origin.is_finite() and transform.basis.is_finite() and wrist.is_finite(), tag + " non-finite geometry")
	check(Finite.touches(transform, ball_point, Ball.BALL_RADIUS), tag + " finite paddle does not touch planned ball")
	check(reach <= Wrist.DEFAULT_LINK_BUDGET + Wrist.NUMERICAL_EPSILON, tag + " wrist exceeds 0.70 m")
	check(floor_min >= -0.0001, tag + " paddle intersects court")
	check(ball_point.y >= player.COURT_FLOOR_Y + Ball.BALL_RADIUS - 0.00001, tag + " ball intersects court")
	return {"head": head, "ball": ball_point, "wrist_reach": reach, "floor": floor_min, "gap": gap, "center_gap": head.distance_to(ball_point)}

func assert_guide_owner(def: PostureDefinition, lateral: float, height: float, tag: String) -> void:
	var shown := false
	for region in Zones.display_regions():
		var rect: Rect2 = region.rect
		if def.posture_id in region.owners and lateral >= rect.position.x - 0.00001 and lateral <= rect.end.x + 0.00001 and height >= rect.position.y - 0.00001 and height <= rect.end.y + 0.00001: shown = true
	check(shown, tag + " selected contact missing from owned displayed coverage")
	check(Zones.contains(def, lateral, height), tag + " displayed/detector coverage mismatch")

func deterministic_cases() -> void:
	var library := PostureLibrary.instance()
	for def in library.all_definitions():
		snapshots[def.posture_id] = snapshot(def)
		if not def.resource_path.is_empty() and FileAccess.file_exists(def.resource_path): source_hashes[def.resource_path] = FileAccess.get_sha256(def.resource_path)
	Zones.refresh()
	for side in range(2):
		var player = CourtSide.new(side)
		player.global_position = Vector3(0, 1.0, 3.2 if side == 0 else -3.2)
		player.global_transform.origin = player.global_position
		var ball := IncomingBall.new()
		ball.last_hit_by = 1 - side
		ball.linear_velocity = -player._get_forward_axis() * 6.0
		for lateral in LANES:
			for height in HEIGHTS:
				var tag := "side%d x%.2f h%.4f" % [side, lateral, height]
				var flight := flight_for(player, ball, lateral, height)
				var plan: Dictionary = Planner.select(player, ball, flight)
				tested += 1
				check(not plan.is_empty(), tag + " legal floor-level contact excluded")
				var row: Dictionary = {"kind": "planner", "side": side, "lateral": lateral, "height": height, "planned": not plan.is_empty()}
				if not plan.is_empty():
					planned += 1
					check(Planner.point_fits(player, plan.def, plan.point), tag + " selected contact fails admission")
					check(is_equal_approx(plan.point.y - player.COURT_FLOOR_Y, height), tag + " planner moved the ball target")
					if lateral > 0.25: check(plan.def.family == 0, tag + " expected forehand")
					if lateral < -0.25: check(plan.def.family == 1, tag + " expected backhand")
					assert_guide_owner(plan.def, lateral, height, tag)
					row.merge(assert_geometry(player, plan.def, plan.point, tag))
					row.posture = plan.posture
					var repeated: Dictionary = Planner.select(player, ball, flight, plan.posture)
					check(not repeated.is_empty() and repeated.posture == plan.posture, tag + " unstable selected owner")
				records.append(row)
		wider_and_swept_cases(player, ball)
		negative_cases(player, ball)
	# Debug geometry must expose the same exact boundaries as detection.
	for region in Zones.display_regions():
		var rect: Rect2 = region.rect
		for x in [rect.position.x, rect.get_center().x, rect.end.x]:
			for height in [rect.position.y, rect.get_center().y, rect.end.y]:
				for owner in region.owners:
					check(Zones.contains(library.get_def(owner), x, height), "displayed guide edge/corner has no detector owner")
	print("FLOOR PLANNER: %d/%d legal contacts planned; minimum paddle floor %.5f, maximum wrist %.5f" % [planned, tested, minimum_paddle_floor, maximum_wrist])

func wider_and_swept_cases(player, ball) -> void:
	for lateral in [-0.82, -0.62, 0.62, 0.82]:
		for height in HEIGHTS:
			var flight := flight_for(player, ball, lateral, height)
			var plan: Dictionary = Planner.select(player, ball, flight)
			var reachable := false
			for def in PostureLibrary.instance().all_definitions():
				if def.has_zone: reachable = reachable or Planner.point_fits(player, def, point(player, lateral, height, def.zone_forward_offset))
			check(not reachable or not plan.is_empty(), "physically reachable wide low contact excluded")
			var row: Dictionary = {"kind": "wide", "side": player.player_num, "lateral": lateral, "height": height, "planned": not plan.is_empty()}
			if not plan.is_empty():
				row.merge(assert_geometry(player, plan.def, plan.point, "wide side%d x%.2f h%.4f" % [player.player_num, lateral, height]))
				records.append(row)
	for height in HEIGHTS:
		for dt in [1.0 / 30.0, 1.0 / 60.0, 1.0 / 120.0]:
			var a := point(player, -1.30, height, 0.55)
			var b := point(player, 1.30, height, 0.55)
			ball.global_position = a
			ball.linear_velocity = (b - a) / dt
			var flight := {"samples": [{"pos": a, "time": 0.0, "bounces": 0}, {"pos": b, "time": dt, "bounces": 0}]}
			var plan: Dictionary = Planner.select(player, ball, flight)
			var tag := "swept floor side%d h%.4f dt%.5f" % [player.player_num, height, dt]
			check(not plan.is_empty(), tag + " between-sample low crossing lost")
			if not plan.is_empty():
				assert_geometry(player, plan.def, plan.point, tag)
				check(plan.time >= 0.0 and plan.time <= dt, tag + " plan escaped temporal segment")
	ball.linear_velocity = -player._get_forward_axis() * 6.0

func seam_and_prebounce_regressions() -> void:
	var player = CourtSide.new(0)
	player.global_position = Vector3(0, 1.0, 3.8)
	player.global_transform.origin = player.global_position
	for height in [0.29999, 0.30, 0.32, 0.35, 0.38]:
		var target := point(player, -0.62, height, 0.40)
		var owners: Array = []
		for def in PostureLibrary.instance().all_definitions():
			if def.has_zone and Planner.point_fits(player, def, target):
				owners.append(def.posture_id)
				assert_geometry(player, Planner.pose_at(player, def, target), target, "continuous .30m seam h%.5f" % height)
		check(not owners.is_empty(), "reachable low-wide contact hole at former .30m cutoff h%.5f" % height)
	var old_hz := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 30
	var ball := IncomingBall.new()
	ball.global_position = Vector3(0.82, 0.38, 2.9)
	ball.linear_velocity = Vector3(0, -12, 16)
	var flight: Dictionary = Flight.trace(ball.global_position, ball.linear_velocity, Vector3.ZERO, 0.15, 1, false)
	var fault: float = Planner.predicted_fault_time(player, ball, flight)
	var plan: Dictionary = Planner.select(player, ball, flight)
	check(not plan.is_empty(), "legal within-frame pre-second-bounce intercept excluded")
	if not plan.is_empty():
		check(plan.time < fault and plan.bounces == 0, "planned after second bounce or spoofed preimpact count")
		assert_geometry(player, plan.def, plan.point, "pre-second-bounce floor intercept")
	# Fast diagonal paths can enter a narrow physical wrist interval between
	# all coarse samples while staying above the impending second bounce.
	for fixture in [
		{"hz": 30, "start": Vector3(0.655474, 0.423633, 2.726475), "velocity": Vector3(-6.454947, -13.08427, 12.44394)},
		{"hz": 30, "start": Vector3(1.183085, 0.406864, 3.365412), "velocity": Vector3(-10.18622, -11.09052, 0.483201)},
		{"hz": 30, "start": Vector3(-0.51536, 0.283549, 2.686902), "velocity": Vector3(12.10281, 11.64499, 8.472374)},
		{"hz": 120, "start": Vector3(-0.147924, 0.475388, 2.898327), "velocity": Vector3(12.61804, 12.55926, 5.609721)}]:
		Engine.physics_ticks_per_second = fixture.hz
		ball.global_position = fixture.start
		ball.linear_velocity = fixture.velocity
		var diagonal: Dictionary = Flight.trace(ball.global_position, ball.linear_velocity, Vector3.ZERO, 1.0 / float(fixture.hz), 1, false)
		var diagonal_plan: Dictionary = Planner.select(player, ball, diagonal)
		var diagonal_fault := Planner.predicted_fault_time(player, ball, diagonal)
		var tag := "narrow diagonal " + str(fixture.start)
		check(not diagonal_plan.is_empty(), tag + " missed interior low-contact interval")
		if not diagonal_plan.is_empty():
			check(diagonal_plan.time < diagonal_fault and diagonal_plan.bounces == 0, tag + " contact after second bounce")
			assert_geometry(player, diagonal_plan.def, diagonal_plan.point, tag)
			records.append({"kind": "narrow_diagonal", "start": fixture.start, "velocity": fixture.velocity, "point": diagonal_plan.point, "time": diagonal_plan.time, "fault": diagonal_fault, "posture": diagonal_plan.posture})
	ball.global_position = Vector3(0.82, 0.38, 2.9)
	ball.linear_velocity = Vector3(0, -12, 16)
	ball.bounces_since_last_hit = 0
	ball.both_bounces_complete = false
	plan = Planner.select(player, ball, flight)
	check(plan.is_empty() or plan.bounces > 0, "floor interception bypassed required first bounce")
	Engine.physics_ticks_per_second = old_hz
	# Custom loaded values are never capped down when they need no extra load.
	var source: PostureDefinition = PostureLibrary.instance().get_def(5).duplicate(true)
	source.crouch_amount = 0.70
	var original = snapshot(source)
	var result: PostureDefinition = Planner.pose_at(player, source, point(player, 0.42, 0.20, source.zone_forward_offset))
	check(result.crouch_amount >= source.crouch_amount, "custom crouch above .65 was reduced")
	check(snapshot(source) == original, "custom low pose mutated by runtime fit")

func negative_cases(player, ball) -> void:
	var flight := flight_for(player, ball, 0.42, 0.10)
	ball.bounces_since_last_hit = 2
	check(Planner.select(player, ball, flight).is_empty(), "second-bounce floor contact accepted")
	ball.bounces_since_last_hit = 0
	ball.both_bounces_complete = false
	check(Planner.select(player, ball, flight).is_empty(), "required opening bounce bypassed")
	ball.both_bounces_complete = true
	var old_position: Vector3 = player.global_position
	player.global_position.z = 1.9 if player.player_num == 0 else -1.9
	player.global_transform.origin = player.global_position
	flight = flight_for(player, ball, 0.42, 0.10)
	check(Planner.select(player, ball, flight).is_empty(), "kitchen floor-level volley accepted")
	ball.bounces_since_last_hit = 1
	check(Planner.legal_ball(player, ball), "kitchen groundstroke rejected by legal gate")
	check(not Planner.select(player, ball, flight).is_empty(), "legal kitchen floor groundstroke excluded")
	player.global_position = old_position
	player.global_transform.origin = player.global_position
	for forbidden in [Vector3(0.42, -0.001, 0.55), Vector3(0.42, Ball.BALL_RADIUS - 0.001, 0.55), Vector3(0.42, 0.10, -0.01), Vector3(-3.0, 0.10, 0.55), Vector3(3.0, 0.10, 0.55)]:
		var target := point(player, forbidden.x, forbidden.y, forbidden.z)
		var accepted := false
		for def in PostureLibrary.instance().all_definitions():
			if def.has_zone: accepted = accepted or Planner.point_fits(player, def, target)
		check(not accepted, "underground/behind/outside-reach point accepted " + str(forbidden))

func prepare_live(game, lateral: float, height: float, vertical_speed: float, kitchen: bool = false) -> void:
	var player = game.player_left
	var human = player.posture.human_contact
	human.cancel()
	player.hitting.clear_charge_visual()
	player.hitting.is_in_follow_through = false
	player.posture.transition_pose_blend = null
	player.global_position = Vector3(0, player.ground_y, 1.9 if kitchen else 3.2)
	player.current_velocity = Vector3.ZERO
	plant_fixture(player)
	game._set_game_state(game.GameState.PLAYING)
	game.rally_scorer.start_rally(0, true)
	game.rally_scorer._serve_was_hit = true
	incoming(game, lateral, player.COURT_FLOOR_Y + height, 6.0)
	game.ball.global_position = point(player, lateral, height, 1.35)
	game.ball.linear_velocity.y = vertical_speed
	game.ball.bounces_since_last_hit = 1
	game.ball.ball_bounced_since_last_hit = true
	game.ball.can_register_floor_bounce = true

func live_case(game, lateral: float, height: float, vertical_speed: float, kitchen: bool = false) -> void:
	prepare_live(game, lateral, height, vertical_speed, kitchen)
	await physics_frame
	await physics_frame
	var player = game.player_left
	var human = player.posture.human_contact
	var tag := "live x%.2f start-h%.3f vy%.1f %s" % [lateral, height, vertical_speed, "kitchen" if kitchen else "court"]
	var initial: Dictionary = human.contact.duplicate()
	check(not initial.is_empty(), tag + " no automatic floor preparation")
	var samples: Array[Dictionary] = []
	var callback = func(id):
		if id != 0: return
		var pose: PostureDefinition = player.get_runtime_posture_def()
		var transform: Transform3D = player.paddle_node.global_transform
		var floor_min := INF
		for vertex in surface: floor_min = minf(floor_min, (transform * vertex).y - player.COURT_FLOOR_Y)
		var raw: Dictionary = human.last_contact_evidence.duplicate()
		var row: Dictionary = {"ball": game.ball.global_position, "paddle": transform, "floor": floor_min,
			"wrist": Wrist.wrist_world(transform, pose).distance_to(Wrist.live_shoulder(player, pose)),
			"displayed_wrist": Wrist.displayed_wrist(player, pose).distance_to(Wrist.live_shoulder(player, pose)),
			"center_gap": PaddleReach.head_world(player).distance_to(game.ball.global_position), "evidence": raw}
		samples.append(row)
	game.ball.hit_by_paddle.connect(callback)
	if not initial.is_empty():
		check(initial.point.y < player.COURT_FLOOR_Y + 0.30, tag + " fixture did not select floor-level ball")
		check(human.visual_pose != null, tag + " automatic preparation has no visible pose")
		check(player.debug_visual.human_committed_contact_position.distance_to(initial.point) < 0.0001, tag + " guide marker moved away from actual planned ball")
		var marker = player.debug_visual.human_intercept_indicator
		if marker: check(marker.global_position.distance_to(initial.point) < 0.0001, tag + " visible intercept marker uses paddle center")
		Input.action_press("ui_accept")
		game.input_handler._handle_swing_charge(0.08)
		check(player.hitting.charge_visual_active, tag + " charge did not begin")
		Input.action_release("ui_accept")
		game.input_handler._handle_swing_charge(0.0)
		check(samples.is_empty() and game.ball.last_hit_by == 1, tag + " early release applied distant instant hit")
		for frame in range(ceili(0.55 * Engine.physics_ticks_per_second)):
			await physics_frame
			if not samples.is_empty() or game.game_state != game.GameState.PLAYING: break
		check(samples.size() == 1, tag + " legal released shot missed or returned twice")
		if not samples.is_empty():
			returns += 1
			var row: Dictionary = samples[0]
			check(row.ball.y < player.COURT_FLOOR_Y + 0.30, tag + " live hit was not below old coverage")
			check(row.ball.is_finite() and row.paddle.origin.is_finite() and row.paddle.basis.is_finite(), tag + " live non-finite geometry")
			check(Finite.touches(row.paddle, row.ball, Ball.BALL_RADIUS), tag + " live finite head misses ball")
			check(row.floor >= -0.0001, tag + " live paddle intersects court")
			check(row.wrist <= Wrist.DEFAULT_LINK_BUDGET + Wrist.NUMERICAL_EPSILON, tag + " live wrist exceeds .70 m")
			check(row.displayed_wrist <= Wrist.DEFAULT_LINK_BUDGET + Wrist.NUMERICAL_EPSILON, tag + " displayed arm exceeds .70 m")
			check(row.evidence.has("raw_paddle") and row.evidence.has("raw_ball"), tag + " no pre-alignment contact evidence")
			if row.evidence.has("raw_paddle"):
				check(Finite.touches(row.evidence.raw_paddle, row.evidence.raw_ball, Ball.BALL_RADIUS), tag + " raw pre-alignment paddle misses ball")
			check(not game.ball.was_volley, tag + " legal postbounce hit counted as volley")
			maximum_center_gap = maxf(maximum_center_gap, row.center_gap)
			minimum_paddle_floor = minf(minimum_paddle_floor, row.floor)
			maximum_wrist = maxf(maximum_wrist, row.wrist)
			print("FLOOR LIVE HIT: ", tag, " h=", row.ball.y - player.COURT_FLOOR_Y, " floor=", row.floor, " wrist=", row.wrist, " center_gap=", row.center_gap)
		records.append({"kind": "live", "tag": tag, "plan": initial.point, "hits": samples})
	else:
		records.append({"kind": "live", "tag": tag, "plan": {}, "hits": []})
	game.ball.hit_by_paddle.disconnect(callback)
	game.ball.is_in_play = false
	human.cancel()
	player.hitting.clear_charge_visual()

func live_cases() -> void:
	var game = await setup_game()
	for lateral in [-0.42, 0.0, 0.42]:
		for launch in [Vector2(0.04, 1.2), Vector2(0.08, 0.6), Vector2(0.20, 0.0), Vector2(0.299, -0.3)]:
			await live_case(game, lateral, launch.x, launch.y)
	for lateral in [-0.42, 0.42]:
		await live_case(game, lateral, 0.08, 0.6, true)
	# Merely seeing and preparing a low ball cannot return it without a release.
	prepare_live(game, 0.42, 0.08, 0.6)
	for frame in range(ceili(0.4 * Engine.physics_ticks_per_second)):
		await physics_frame
		if game.game_state != game.GameState.PLAYING: break
	check(game.ball.last_hit_by == 1, "passive low preparation returned ball without release")
	game.ball.is_in_play = false
	game.queue_free()
	await process_frame
	await process_frame

func red_contact_cases() -> void:
	var game = await setup_game()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var p = game.player_right
	var ai = p.ai_brain
	game.ball.freeze = true
	for lateral in [-0.42, 0.0, 0.42]:
		for height in HEIGHTS:
			game._set_game_state(game.GameState.PLAYING)
			p.global_position = Vector3(0, p.ground_y, -3.2)
			p.current_velocity = Vector3.ZERO
			p.hitting.clear_charge_visual()
			p.hitting.serving_visual_active = false
			p.hitting.is_in_follow_through = false
			if p.hitting.paddle_swing_tween: p.hitting.paddle_swing_tween.kill()
			p.leg_ik.feet_initialized = false
			var b = game.ball
			b.reset_rally_state()
			b.is_in_play = true
			b.last_hit_by = 0
			b.both_bounces_complete = true
			b.bounces_since_last_hit = 1
			b.ball_bounced_since_last_hit = true
			b.flight_id += 1
			b.linear_velocity = -p._get_forward_axis() * 6.0
			var plan: Dictionary = Planner.select(p, b, flight_for(p, b, lateral, height))
			var tag := "red native x%.2f h%.4f" % [lateral, height]
			check(not plan.is_empty(), tag + " missing plan")
			if plan.is_empty(): continue
			p.posture.transition_pose_blend = plan.def
			p.posture.force_posture_update(plan.def)
			ai.incoming_pose_override = plan.def
			ai.ai_desired_posture = plan.posture
			ai._perception_ready = true
			ai.ai_is_charging = true
			ai.ai_charge_time = 0.0
			ai.ai_swing_threshold = 1.0
			ai.ai_hit_cooldown = 0.0
			ai.ai_selected_contact_reachable = true
			ai.ai_selected_contact_time = 0.1
			ai.ai_reach_pose = plan.def
			ai.ai_predicted_contact_position = plan.point
			ai._exchange_align_flight = -1
			ai._pose_alignment_tick = -1
			ai.ai_ball_bounced_on_side = true
			ai._observed_flight_id = b.flight_id
			ai._last_support_attempt_tick = -1
			var raw_transform: Transform3D = p.paddle_node.global_transform
			# Admit at the first finite surface crossing, as a moving ball would,
			# rather than teleporting its center deep inside the paddle volume.
			var approach: Vector3 = plan.point + p._get_forward_axis() * 0.15
			var fraction := Finite.first_sweep_fraction(approach, plan.point, raw_transform, raw_transform, Ball.BALL_RADIUS)
			check(fraction >= 0.0, tag + " no physical approach crossing")
			b.global_position = approach.lerp(plan.point, maxf(0.0, fraction))
			var actual_ball_point: Vector3 = b.global_position
			check(Finite.touches(raw_transform, b.global_position, Ball.BALL_RADIUS), tag + " native pose misses planned floor ball")
			ai._try_ai_hit_ball()
			check(b.last_hit_by == 1, tag + " native legal floor hit rejected")
			if b.last_hit_by == 1:
				red_returns += 1
				var floor_min := INF
				for vertex in surface: floor_min = minf(floor_min, (p.paddle_node.global_transform * vertex).y - p.COURT_FLOOR_Y)
				check(floor_min >= -0.0001, tag + " red paddle intersects court")
				check(Finite.touches(p.paddle_node.global_transform, actual_ball_point, Ball.BALL_RADIUS), tag + " returned red hit has no finite contact")
				var reach := Wrist.wrist_world(p.paddle_node.global_transform, plan.def).distance_to(Wrist.live_shoulder(p, plan.def))
				check(reach <= Wrist.DEFAULT_LINK_BUDGET + Wrist.NUMERICAL_EPSILON, tag + " red wrist exceeds .70 m")
				records.append({"kind": "red_native", "lateral": lateral, "height": height, "floor": floor_min, "wrist": reach})
	game.queue_free()
	await process_frame
	await process_frame

func ai_floor_alignment_cases() -> void:
	var game = await setup_game()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var p = game.player_right
	var ai = p.ai_brain
	game.ball.freeze = true
	for lateral in [-0.42, 0.0, 0.42]:
		for height in [0.0375, 0.06, 0.20]:
			p.global_position = Vector3(0, p.ground_y, -3.2)
			p.current_velocity = Vector3.ZERO
			p.hitting.clear_charge_visual()
			p.hitting.serving_visual_active = false
			p.hitting.is_in_follow_through = false
			p.leg_ik.feet_initialized = false
			var b = game.ball
			b.reset_rally_state(); b.is_in_play = true; b.last_hit_by = 0
			b.both_bounces_complete = true; b.bounces_since_last_hit = 1
			b.ball_bounced_since_last_hit = true; b.flight_id += 1
			b.linear_velocity = -p._get_forward_axis() * 6.0
			var plan: Dictionary = Planner.select(p, b, flight_for(p, b, lateral, height))
			if plan.is_empty(): continue
			p.posture.transition_pose_blend = plan.def
			p.posture.force_posture_update(plan.def)
			p.refresh_contact_support(plan.def)
			b.global_position = plan.point
			ai.incoming_pose_override = plan.def
			ai.ai_reach_pose = plan.def
			ai.ai_desired_posture = plan.posture
			ai.ai_selected_contact_reachable = true
			ai.ai_selected_contact_time = 0.10
			ai.ai_predicted_contact_position = plan.point
			ai._exchange_align_flight = -1
			ai._pose_alignment_tick = -1
			ai.align_paddle_to_contact(1.0)
			PaddleReach.clamp_paddle_for_player(p)
			var pose: PostureDefinition = ai.incoming_pose_override
			var transform: Transform3D = p.paddle_node.global_transform
			var floor_min := INF
			for vertex in surface: floor_min = minf(floor_min, (transform * vertex).y - p.COURT_FLOOR_Y)
			var wrist := Wrist.wrist_world(transform, pose).distance_to(Wrist.live_shoulder(p, pose))
			var tag := "AI floor alignment x%.2f h%.4f" % [lateral, height]
			check(floor_min >= -0.0001, tag + " aligned paddle crosses court")
			check(wrist <= Wrist.DEFAULT_LINK_BUDGET + Wrist.NUMERICAL_EPSILON, tag + " aligned wrist exceeds .70m")
			check(Finite.touches(transform, plan.point, Ball.BALL_RADIUS), tag + " alignment loses finite ball contact")
			if floor_min < -0.0001 or wrist > 0.7001: print("FLOOR AI ALIGN: ", tag, " floor=", floor_min, " wrist=", wrist, " head=", transform * Dimensions.HEAD_OFFSET)
	game.queue_free()
	await process_frame
	await process_frame

func run() -> void:
	create_timer(120.0).timeout.connect(func(): quit(2))
	Engine.physics_ticks_per_second = int(OS.get_environment("GODOT_TEST_PHYSICS_HZ")) if OS.has_environment("GODOT_TEST_PHYSICS_HZ") else 60
	surface = Geometry.sample_head_surface()
	deterministic_cases()
	seam_and_prebounce_regressions()
	if not OS.has_environment("GODOT_TEST_FLOOR_STATIC_ONLY"):
		if not OS.has_environment("GODOT_TEST_FLOOR_RED_ONLY"): await live_cases()
		await red_contact_cases()
		await ai_floor_alignment_cases()
	for def in PostureLibrary.instance().all_definitions():
		check(snapshots[def.posture_id] == snapshot(def), def.display_name + " authored pose mutated")
	for path in source_hashes: check(source_hashes[path] == FileAccess.get_sha256(path), "authored pose file changed " + path)
	var output := FileAccess.open("/tmp/floor-level-interception-%d.json" % Engine.physics_ticks_per_second, FileAccess.WRITE)
	output.store_string(JSON.stringify({"planner_sha256": FileAccess.get_sha256("res://scripts/incoming_contact_planner.gd"), "checks": checks, "failures": failures, "planned": planned, "tested": tested, "live_returns": returns, "red_native_returns": red_returns, "minimum_paddle_floor": minimum_paddle_floor, "maximum_wrist": maximum_wrist, "maximum_center_gap": maximum_center_gap, "records": records}, "\t"))
	output.close()
	for failure in failures: push_error(failure)
	print("FLOOR LEVEL INTERCEPTION: %d checks, %d failures; %d/%d plans, %d live returns, %d red native returns" % [checks, failures.size(), planned, tested, returns, red_returns])
	quit(0 if failures.is_empty() else 1)
