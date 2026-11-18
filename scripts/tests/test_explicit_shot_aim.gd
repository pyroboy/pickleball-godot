extends TestBase
const Shot = preload("res://scripts/shot_physics.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const BallScript = preload("res://scripts/ball.gd")

func run_all(totals: Dictionary) -> void :
	_run_test_list(totals, [test_explicit_target_all_spins, test_drop_target_override, 
		test_serve_cursor_target, test_cursor_clamps_and_determinism, test_charge_changes_pace_not_target, test_contact_height_sweep, test_arc_preserves_cursor, test_drop_corner_energy_bounds])

func test_explicit_target_all_spins() -> void :
	var solver: = Shot.new()
	var worst: float = 0.0
	var cases: int = 0
	for side in range(2):
		var sign_z: float = -1.0 if side == 0 else 1.0
		for start_z in [1.8, 4.0, 6.5]:
			for target_x in [-2.45, 0.0, 2.45]:
				for depth in [0.65, 3.4, 6.1]:
					for mode in range(3):
						var start: = Vector3(-0.6, 0.85, - sign_z * start_z)
						var target: = Vector3(target_x, Flight.FLOOR_REST_Y, sign_z * depth)
						var launch: Dictionary = solver.solve_aimed_launch(start, target, 0.65, side, mode)
						var error: float = launch.landing.distance_to(target)
						worst = maxf(worst, error)
						cases += 1
						var tag: String = "side%d from%.1f x%.2f depth%.2f mode%d" % [side, start_z, target_x, depth, mode]
						_assert_true(launch.feasible, tag + " feasible")
						_assert_lt(error, 0.16, tag + " explicit cursor preserved")
						_assert_eq_v3(launch.target, target, 0.0001, "solver never moves valid cursor")
						_assert_le(launch.velocity.length(), BallScript.MAX_SPEED, "no aimed shot speed exploit")
	print("EXPLICIT AIM: %d launches; max error %.3f m" % [cases, worst])

func test_drop_target_override() -> void :
	var solver: = Shot.new()
	for side in range(2):
		var sign_z: float = -1.0 if side == 0 else 1.0
		for charge in [0.0, 1.0]:
			for mode in range(3):
				var target: = Vector3(-2.45, Flight.FLOOR_REST_Y, sign_z * 1.2)
				var launch: Dictionary = solver.solve_aimed_launch(Vector3(1.5, 0.8, - sign_z * 6.2), target, charge, side, mode, "DROP")
				_assert_true(launch.feasible, "explicit drop cursor feasible")
				_assert_lt(launch.landing.distance_to(target), 0.16, "drop charge cannot override cursor depth")
				_assert_eq_v3(launch.target, target, 0.0001, "drop target exact")
				_assert_le(launch.velocity.length(), 12.5, "far diagonal drop remains bounded")

func test_serve_cursor_target() -> void :
	var solver: = Shot.new()
	for side in range(2):
		var sign_z: float = -1.0 if side == 0 else 1.0
		for charge in [0.0, 0.5, 1.0]:
			for mode in range(3):
				for depth in [2.6, 6.1]:
					var target: = Vector3(-1.5, Flight.FLOOR_REST_Y, sign_z * depth)
					var launch: Dictionary = solver.solve_aimed_launch(Vector3(1.5, 0.7, - sign_z * 6.3), target, charge, side, mode, "AUTO", "SERVE")
					_assert_true(launch.feasible, "serve target feasible with radius+margin net clearance")
					_assert_lt(launch.landing.distance_to(target), 0.16, "serve cursor exact")
					_assert_eq(launch.profile.shot_type, "SERVE", "serve spin profile retained")

func test_cursor_clamps_and_determinism() -> void :
	var solver: = Shot.new()
	var start: = Vector3(0, 1, 4)
	var target: = Vector3(-1.5, 0, -4.3)
	seed(30)
	var first: Dictionary = solver.solve_aimed_launch(start, target, 0.65, 0, 1)
	seed(978)
	var second: Dictionary = solver.solve_aimed_launch(start, target, 0.65, 0, 1)
	_assert_eq_v3(first.velocity, second.velocity, 1e-06, "RNG does not change intended direction")
	_assert_eq_v3(first.omega, second.omega, 1e-06, "RNG does not change intended spin")
	var bounded: Dictionary = solver.solve_aimed_launch(start, Vector3(20, 8, -20), 0.8, 0, 2, "DROP")
	_assert_eq_v3(bounded.target, Vector3(2.45, Flight.FLOOR_REST_Y, -1.55), 0.0001, "unsafe drop target is bounded")

func test_charge_changes_pace_not_target() -> void :
	var solver: = Shot.new()
	var start: = Vector3(0, 1.0, 4.0)
	var target: = Vector3(1.5, Flight.FLOOR_REST_Y, -4.6)
	for mode in range(3):
		var soft: Dictionary = solver.solve_aimed_launch(start, target, 0, 0, mode)
		var hard: Dictionary = solver.solve_aimed_launch(start, target, 1, 0, mode)
		_assert_lt(soft.landing.distance_to(target), 0.16, "soft cursor unchanged")
		_assert_lt(hard.landing.distance_to(target), 0.16, "hard cursor unchanged")
		_assert_gt(hard.velocity.length(), soft.velocity.length() + 1, "charge increases normal shot pace")
		_assert_lt(hard.duration, soft.duration, "hard shot flies faster")

func test_contact_height_sweep() -> void :
	var solver: = Shot.new()
	var cases: int = 0
	for height in [0.35, 1.4, 2.3]:
		for start_z in [1.8, 6.5]:
			for target_z in [-0.65, -6.1]:
				for charge in [0.0, 1.0]:
					for mode in range(3):
						var target: = Vector3(2.45, Flight.FLOOR_REST_Y, target_z)
						var launch: Dictionary = solver.solve_aimed_launch(Vector3(-2.0, height, start_z), target, charge, 0, mode)
						cases += 1
						var tag: = "h%.2f from%.2f to%.2f charge%.1f mode%d" % [height, start_z, target_z, charge, mode]
						_assert_true(launch.feasible, tag + " feasible")
						_assert_lt(launch.landing.distance_to(target), 0.16, tag + " landing target")
	print("AIM HEIGHT SWEEP: %d launches" % cases)

func test_arc_preserves_cursor() -> void :
	var solver: = Shot.new()
	var start: = Vector3(1.5, 0.7, 6.3)
	var target: = Vector3(-1.5, Flight.FLOOR_REST_Y, -4.6)
	var neutral: Dictionary = solver.solve_aimed_launch(start, target, 0.5, 0, 1, "AUTO", "SERVE")
	var high: Dictionary = solver.solve_aimed_launch(start, target, 0.5, 0, 1, "AUTO", "SERVE", 0.25)
	var low: Dictionary = solver.solve_aimed_launch(start, target, 0.5, 0, 1, "AUTO", "SERVE", -0.15)
	_assert_gt(high.duration, neutral.duration, "R raises a feasible serve arc")
	_assert_le(low.duration, neutral.duration, "F lowers a serve arc within clearance")
	for shot in [neutral, high, low]:
		_assert_true(shot.feasible, "arc preserves legal serve")
		_assert_lt(shot.landing.distance_to(target), 0.16, "arc preserves cursor")

func test_drop_corner_energy_bounds() -> void :
	var solver: = Shot.new()
	var fastest: float = 0.0
	var fastest_bounce: float = 0.0
	for side in range(2):
		var direction: float = -1.0 if side == 0 else 1.0
		for x in [-2.45, 2.45]:
			for height in [0.35, 1.1]:
				for charge in [0.0, 1.0]:
					for mode in range(3):
						var start: = Vector3(x, height, -6.5 * direction)
						var target: = Vector3( - x, Flight.FLOOR_REST_Y, 1.55 * direction)
						var launch: Dictionary = solver.solve_aimed_launch(start, target, charge, side, mode, "DROP")
						var trace: Dictionary = Flight.trace(start, launch.velocity, launch.omega, 3, 1, false)
						var bounced: Vector3 = trace.samples.back().vel
						fastest = maxf(fastest, launch.velocity.length())
						fastest_bounce = maxf(fastest_bounce, Vector2(bounced.x, bounced.z).length())
						_assert_true(launch.feasible, "far diagonal drop remains feasible")
						_assert_lt(launch.target_error, 0.08, "corner drop still hits cursor")
						_assert_le(launch.velocity.length(), 12.5, "distance allowance cannot reach drive pace")
						_assert_le(Vector2(bounced.x, bounced.z).length(), 6.5, "drop loses pace before its bounce")
						_assert_le(bounced.y, 5.3, "drop has no excessive vertical kick")
	for charge in [0.0, 1.0]:
		var close: Dictionary = solver.solve_aimed_launch(Vector3(0, 0.9, 1.8), Vector3(0, Flight.FLOOR_REST_Y, -1.15), charge, 0, 0, "DROP")
		_assert_le(close.velocity.length(), 6.5, "close-court drop stays gentle at full charge")
	print("DROP CORNERS: max launch %.3f m/s; post-bounce horizontal %.3f m/s" % [fastest, fastest_bounce])
