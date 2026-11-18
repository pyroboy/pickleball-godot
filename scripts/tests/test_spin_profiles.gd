extends TestBase
const Profile = preload("res://scripts/shot_profile.gd")
const Shot = preload("res://scripts/shot_physics.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const BallScript = preload("res://scripts/ball.gd")

func run_all(totals: Dictionary) -> void :
	_run_test_list(totals, [test_cycle_and_immutable_profile, test_spin_direction_both_sides, 
		test_flight_curves_and_bounce, test_target_preservation_sweep, test_soft_shot_limits, test_seeded_shot_intent, test_drop_placement_sweep])

func test_cycle_and_immutable_profile() -> void :
	_assert_eq(Profile.next_mode(0), 1, "flat to topspin")
	_assert_eq(Profile.next_mode(1), 2, "topspin to slice")
	_assert_eq(Profile.next_mode(2), 0, "slice to flat")
	_assert_eq(Profile.valid_mode(99), 0, "invalid input safely flat")
	var mode: int = 1
	var frozen: Dictionary = Profile.create(mode, 0.7, "FAST")
	mode = 2
	_assert_true(frozen.is_read_only(), "committed profile is immutable")
	_assert_eq(frozen.mode, 1, "selection change does not mutate frozen profile")
	_assert_le(absf(frozen.topspin_rads), 42.0, "spin magnitude remains modest")

func test_spin_direction_both_sides() -> void :
	for side in [-1.0, 1.0]:
		var velocity: Vector3 = Vector3(1.3, 3.0, 11.0 * side)
		var axis: Vector3 = Vector3.UP.cross(Vector3(velocity.x, 0, velocity.z).normalized())
		var flat: Vector3 = Profile.angular_velocity(Profile.create(0, 1), velocity)
		var top: Vector3 = Profile.angular_velocity(Profile.create(1, 1), velocity)
		var slice: Vector3 = Profile.angular_velocity(Profile.create(2, 1), velocity)
		_assert_eq_v3(flat, Vector3.ZERO, 0.0001, "flat no imposed brush")
		_assert_gt(top.dot(axis), 0, "topspin follows travel on either side")
		_assert_lt(slice.dot(axis), 0, "slice opposes travel on either side")
		_assert_lt(top.cross(velocity).y, 0, "topspin Magnus dips")
		_assert_gt(slice.cross(velocity).y, 0, "slice Magnus floats")

func test_flight_curves_and_bounce() -> void :
	for direction in [-1.0, 1.0]:
		var velocity: = Vector3(0, 3.0, 10.0 * direction)
		var spin_top: Vector3 = Profile.angular_velocity(Profile.create(1, 0.7), velocity)
		var spin_slice: Vector3 = Profile.angular_velocity(Profile.create(2, 0.7), velocity)
		var flat: Dictionary = Flight.advance(Vector3(0, 1, -3 * direction), velocity, Vector3.ZERO, 0.3)
		var top: Dictionary = Flight.advance(Vector3(0, 1, -3 * direction), velocity, spin_top, 0.3)
		var slice: Dictionary = Flight.advance(Vector3(0, 1, -3 * direction), velocity, spin_slice, 0.3)
		_assert_lt(top.pos.y, flat.pos.y - 0.08, "topspin dips below flat at same launch")
		_assert_gt(slice.pos.y, flat.pos.y + 0.06, "slice floats above flat at same launch")
		var impact: = Vector3(0, -4, 8 * direction)
		var flat_bounce: Array = BallScript.predict_bounce_spin(impact, Vector3.ZERO)
		var top_bounce: Array = BallScript.predict_bounce_spin(impact, spin_top)
		var slice_bounce: Array = BallScript.predict_bounce_spin(impact, spin_slice)
		_assert_gt(absf(top_bounce[0].z), absf(flat_bounce[0].z) + 0.15, "topspin kicks forward")
		_assert_lt(absf(slice_bounce[0].z), absf(flat_bounce[0].z) - 0.12, "slice checks on bounce")
		_assert_lt(top_bounce[0].length(), impact.length(), "bounce does not manufacture energy")

func test_target_preservation_sweep() -> void :
	var solver: = Shot.new()
	var worst: float = 0.0
	var cases: int = 0
	for side in [-1.0, 1.0]:
		for charge in [0.0, 0.4, 1.0]:
			for x in [-1.0, 0.0, 1.0]:
				var origin: = Vector3(x, 0.85, 4.0 * side)
				var velocity: = Vector3( - x * 1.1, 5.0 + charge, - (9.0 + charge * 2.0) * side)
				for mode in range(3):
					var launch: Dictionary = solver.solve_spin_launch(origin, velocity, mode, charge)
					var trace: Dictionary = Flight.trace(origin, launch.velocity, launch.omega, 4, 1, false)
					var error: float = trace.first_bounce.distance_to(launch.target)
					worst = maxf(worst, error)
					cases += 1
					_assert_lt(error, 0.24, "side%.0f charge%.1f x%.1f mode%d preserves target" % [side, charge, x, mode])
					_assert_true(launch.net_clear, "selected mode retains baseline net clearance")
					_assert_le(launch.velocity.length(), minf(BallScript.MAX_SPEED, velocity.length() * 1.06 + 0.1), "no spin power exploit")
	print("SPIN AIM SWEEP: %d launches; max target error %.3f m" % [cases, worst])

func test_soft_shot_limits() -> void :
	var solver: = Shot.new()
	for mode in range(3):
		for kind in ["DINK", "DROP"]:
			var cap: float = 6.0 if kind == "DINK" else 7.5
			var launch: Dictionary = solver.solve_spin_launch(Vector3(0, 1, 1.8), Vector3(0, 3.5, -4), mode, 1.0, kind)
			_assert_le(launch.velocity.length(), cap, "selected spin respects soft-shot speed cap")
			_assert_le(launch.omega.length(), 27.0, "soft shot spin stays gentle")

func test_seeded_shot_intent() -> void :
	var solver: = Shot.new()
	var worst: float = 0.0
	var cases: int = 0
	for side in range(2):
		for shot in ["", "FAST", "DINK", "DROP"]:
			for charge in [0.15, 0.65, 1.0]:
				for trial in range(3):
					seed(73019 + trial)
					var origin: = Vector3(-0.4 + trial * 0.4, 0.65 + trial * 0.3, (2.5 if shot in ["DINK", "DROP"] else 4.0) * (1.0 if side == 0 else -1.0))
					var baseline: Vector3 = solver.compute_shot_velocity(origin, charge, side, shot, 0).limit_length(BallScript.MAX_SPEED)
					var legacy_spin: Vector3 = solver.compute_shot_spin(shot, baseline, charge, side, -1)
					for mode in range(3):
						var launch: Dictionary = solver.solve_drop_launch(origin, charge, side, mode) if shot == "DROP" else solver.solve_spin_launch(origin, baseline, mode, charge, shot, legacy_spin)
						var error: float = launch.landing.distance_to(launch.target)
						worst = maxf(worst, error)
						cases += 1
						_assert_lt(error, 0.25, "seed%d side%d type%s charge%.2f mode%d target drift" % [trial, side, shot, charge, mode])
						_assert_true(launch.net_clear, "seed%d side%d type%s charge%.2f mode%d net clearance" % [trial, side, shot, charge, mode])
	print("SPIN SEEDED INTENT: %d launches; max target error %.3f m" % [cases, worst])

func test_drop_placement_sweep() -> void :
	var solver: = Shot.new()
	var worst: float = 0.0
	var fastest: float = 0.0
	var cases: int = 0
	for side in range(2):
		for z in [1.5, 3.5, 5.5, 6.5]:
			for height in [0.55, 1.1, 1.7]:
				for charge in [0.0, 0.5, 1.0]:
					var start: = Vector3(0.7, height, z * (1.0 if side == 0 else -1.0))
					var launch: Dictionary = solver.solve_drop_launch(start, charge, side)
					var error: float = launch.landing.distance_to(launch.target)
					worst = maxf(worst, error)
					fastest = maxf(fastest, launch.velocity.length())
					cases += 1
					_assert_lt(error, 0.16, "drop side%d z%.1f h%.2f charge%.1f stable short target" % [side, z, height, charge])
					_assert_true(launch.net_clear, "drop clears net with margin")
					_assert_in_range(absf(launch.landing.z), 0.5, 1.72, "drop lands safely inside kitchen")
					_assert_le(launch.velocity.length(), 11.5, "deep drops remain bounded below drive speed")
					_assert_eq(launch.profile.shot_type, "DROP", "drop has immutable placement intent")
	print("DROP PLACEMENT: %d launches; max target error %.3f m; max launch %.2f m/s" % [cases, worst, fastest])
