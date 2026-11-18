extends TestBase
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Styles = preload("res://scripts/serve_style.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Geometry = preload("res://scripts/paddle_clearance.gd")
const Side = preload("res://scripts/tests/test_stroke_orientation.gd").CourtSide
const Physics = preload("res://scripts/shot_physics.gd")
const Aim = preload("res://scripts/aim_controller.gd")
const Wrist = preload("res://scripts/tests/pose_anatomical_wrist.gd")

func run_all(totals: Dictionary) -> void :
	_run_test_list(totals, [test_style_contract, test_gravity_release, test_style_flights, test_style_geometry, test_style_contact_tangents, test_style_aim_edges])

func test_style_contract() -> void :
	var choices = Styles.options()
	_assert_eq(choices.size(), 7, "seven distinct named deliveries")
	for id in range(7):
		_assert_eq(choices[id].id, id, "stable style IDs")
		_assert_true(choices[id].has("key") and choices[id].has("description"), "UI identity and instruction")
	_assert_true("Experimental" in choices[5].delivery and "Experimental" in choices[6].delivery, "curve presets do not claim exact verified pro technique")

func test_gravity_release() -> void :
	for id in range(7):
		for red in [false, true]:
			var root: = Vector3(1.5 if not red else -1.5, 1, 6.8 if not red else -6.8)
			var plan = Styles.release_plan(root, red, id)
			_assert_gt(plan.contact_time, 0.2, "real released fall is visible")
			_assert_eq_v3(plan.samples[0].vel, Vector3.ZERO, 1e-05, "no propulsion on release")
			_assert_eq_v3(plan.samples[0].omega, Vector3.ZERO, 1e-05, "no release spin")
			for sample in plan.samples:
				_assert_eq_f(sample.pos.x, plan.release_position.x, 1e-05, "no precontact lateral toss")
				_assert_eq_f(sample.pos.z, plan.release_position.z, 1e-05, "no precontact forward toss")
			if Styles.is_drop(id):
				_assert_ge(plan.bounce_time, 0.5, "drop falls for half a second before bounce")
				_assert_gt(plan.contact_time, plan.bounce_time + 0.1, "drop contact occurs after real rebound")
				_assert_eq(plan.samples.back().bounces, 1, "one bounce actually precedes contact")
			else:
				_assert_eq_f(plan.bounce_time, -1, 1e-05, "volley does not invent a bounce")
				_assert_eq(plan.samples.back().bounces, 0, "volley contact before court")

func test_style_flights() -> void :
	var physics = Physics.new()
	for id in range(7):
		for side in [0, 1]:
			for parity in [0, 1]:
				var root: = Vector3((1.5 if side == 0 else -1.5) * (1 if parity == 0 else -1), 1, 6.8 if side == 0 else -6.8)
				var target: = Vector3( - signf(root.x) * 1.5, Flight.FLOOR_REST_Y, -4.6 if side == 0 else 4.6)
				var plan = Styles.release_plan(root, side == 1, id)
				for charge in [0.0, 0.25, 0.65, 1.0]:
					var launch = Styles.solve_launch(physics, plan.contact_position, target, charge, side, id)
					_assert_true( not launch.is_empty(), "style has an executable launch")
					if launch.is_empty(): continue
					var flight = Flight.trace(plan.contact_position, launch.velocity, launch.omega, 3, 1, false)
					var landing: Vector3 = flight.first_bounce
					var tag = "style%d side%d parity%d charge%.2f" % [id, side, parity, charge]
					_assert_false(flight.net_hit, tag + " clears net")
					_assert_true(signf(landing.x) == signf(target.x) and absf(landing.x) < 3.05 and signf(landing.z) == signf(target.z) and absf(landing.z) > 2.134 and absf(landing.z) < 6.7, tag + " legal diagonal landing")
					_assert_le(landing.distance_to(target), 0.13, tag + " preserves aim")
					_assert_le(launch.velocity.length(), Ball.MAX_SPEED + 0.001, tag + " speed budget")
					_assert_eq_f(launch.profile.charge, charge, 1e-05, "charge frozen independently of style pace")
					if id == 0: _assert_eq_v3(launch.omega, Vector3.ZERO, 1e-05, "Flat is low spin")
					if id >= 5:
						_assert_true(signf(launch.omega.y) == (1.0 if id == 5 else -1.0), "opposite experimental curve axis")
						var forehand: Vector3 = Vector3.RIGHT if side == 0 else Vector3.LEFT
						var side_force: float = launch.omega.cross(launch.velocity).dot(forehand)
						_assert_true(side_force < 0 if id == 5 else side_force > 0, "curve bends left/right from either server view")
	var root: = Vector3(1.5, 1, 6.8)
	var origin: Vector3 = Styles.release_plan(root, false, 0).contact_position
	var target: = Vector3(-1.5, Flight.FLOOR_REST_Y, -4.6)
	var flat = Styles.solve_launch(physics, origin, target, 0.65, 0, 0)
	var soft = Styles.solve_launch(physics, origin, target, 0.65, 0, 3)
	_assert_gt(soft.duration, flat.duration + 0.25, "HighSoft is a distinct deeper loft")
	_assert_lt(soft.velocity.length(), flat.velocity.length(), "HighSoft is not a power drive")

func test_style_geometry() -> void :
	var surface = Geometry.sample_head_surface()
	for id in range(7):
		for side in [0, 1]:
			var p = Side.new(side)
			for charge in [0.0, 0.25, 0.65, 1.0]:
				var hold: Vector3 = Styles.hold_offset(id)
				var prep: PostureDefinition = Motion.serve_style_preparation(id, charge, hold)
				var contact: = Motion.SERVE_CONTACT
				var released: PostureDefinition = Motion.serve_style_wait(prep, 1, id, contact)
				for step in range(33):
					var t: float = step / 32.0
					for pose in [Motion.serve_style_wait(prep, t, id, contact), Motion.serve_style_strike(released, t, id, contact), Motion.serve_style_follow_through(id, charge, t, contact)]:
						var tx: Transform3D = Path.world_transform(p, pose)
						var tag = "style%d side%d charge%.2f sample%d" % [id, side, charge, step]
						_assert_le(Wrist.main_world(p, pose).distance_to(Body.shoulder_world(p, pose)), 0.7001, tag + " dominant anatomical wrist reach")
						var left: PostureDefinition = pose.lerp_with(pose, 0)
						left.paddle_hand = 1
						var hand: Vector3 = Wrist.support_world(p, pose)
						_assert_le(hand.distance_to(Body.shoulder_world(p, left)), 0.7001, tag + " support anatomical wrist reach")
						_assert_gt(Geometry.face_clearance(p, pose), 0.01, tag + " face clearance")
						_assert_ge(Geometry.sampled_chest_clearance(p, pose, surface), 0, tag + " chest clearance")

func test_style_contact_tangents() -> void :
	var p = Side.new(0)
	for id in [0, 1, 3]:
		for charge in [0.0, 0.25, 0.65, 1.0]:
			var prep = Motion.serve_style_preparation(id, charge, Styles.hold_offset(id))
			var before = Motion.serve_style_strike(prep, 0.99, id)
			var contact = Motion.serve_style_contact(id)
			_assert_gt(contact.paddle_y_offset, before.paddle_y_offset, "volley paddle rises into contact")
			var tx: Transform3D = Path.world_transform(p, contact)
			var wrist: Vector3 = tx * PaddleSize.MAIN_GRIP_OFFSET
			var maximum: float = - INF
			for point in Geometry.sample_head_surface():
				if point.y >= 0.25: maximum = maxf(maximum, (tx * point).y)
			_assert_le(maximum, wrist.y, "entire volley head stays below wrist")
			_assert_lt((p.global_position + Motion.serve_launch_offset(false)).y, p.global_position.y, "volley ball below waist")

	for id in [5, 6]:
		for charge in [0.0, 0.25, 0.65, 1.0]:
			var prep = Motion.serve_style_preparation(id, charge, Styles.hold_offset(id))
			var before = Motion.serve_style_strike(prep, 0.999, id)
			var contact = Motion.serve_style_contact(id)
			var derivative: float = contact.paddle_forehand_mul - before.paddle_forehand_mul
			_assert_true(derivative > 0 if id == 5 else derivative < 0, "curve spin has a matching lateral paddle brush")

func test_style_aim_edges() -> void :
	var physics = Physics.new()
	for style in range(7):
		for side in [0, 1]:
			var root: = Vector3(1.5 if side == 0 else -1.5, 1, 6.8 if side == 0 else -6.8)
			var origin: Vector3 = Styles.release_plan(root, side == 1, style).contact_position
			for x in [0.45, 1.5, Aim.X_LIMIT]:
				for z in [2.6, 4.6, Aim.MAX_DEPTH]:
					for charge in [0.0, 1.0]:
						var target: = Vector3( - x if side == 0 else x, Flight.FLOOR_REST_Y, - z if side == 0 else z)
						var launch = Styles.solve_launch(physics, origin, target, charge, side, style)
						var flight = Flight.trace(origin, launch.velocity, launch.omega, 3, 1, false)
						var tag = "style%d side%d target%s charge%.1f" % [style, side, str(target), charge]
						_assert_false(flight.net_hit, tag + " clears net at cursor extremes")
						_assert_le(flight.first_bounce.distance_to(target), 0.13, tag + " preserves legal edge aim")
