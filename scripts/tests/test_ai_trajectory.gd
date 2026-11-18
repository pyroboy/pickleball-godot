class_name TestAITrajectory
extends TestBase
## Legacy trajectory cases plus the solver used by the live AI hit path.
## Each scenario is an individual counted test for fine-grained failure reporting.
##
## Run from the project root:
##   godot --headless --script scripts/tests/test_runner.gd
##
## Or individually:
##   godot --headless --script scripts/tests/test_ai_trajectory.gd

const _FakeGame := preload("res://scripts/tests/fakes/fake_game.gd")
const _FakePlayerAI := preload("res://scripts/tests/fakes/fake_player_ai.gd")
const _Ball := preload("res://scripts/ball.gd")
const _Brain := preload("res://scripts/player_ai_brain.gd")
const _Constants := preload("res://scripts/constants.gd")
const _Flight := preload("res://scripts/ball_flight_predictor.gd")

var _rng: RandomNumberGenerator
var _fake_game: FakeGame
var _ai_player: FakePlayerAI
var _brain: PlayerAIBrain


func _init() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = 12345
	_fake_game = _FakeGame.new()
	_ai_player = _FakePlayerAI.new(1, Vector3(-1.0, 0.075, -5.0))
	_ai_player.ai_desired_posture = 0
	_ai_player.paddle_posture = 0
	# Wire up brain — inject fake game to bypass autoload
	_brain = _Brain.new()
	_brain._game_node = _fake_game
	_brain._player = _ai_player


func run_all(totals: Dictionary) -> void:
	_rng.seed = 12345
	var tests: Array[Callable] = [
		test_baseline_returns,
		test_deep_court_returns,
		test_kitchen_returns,
		test_net_clearance,
		test_in_bounds,
		test_target_zone_coverage,
		test_marker_consistency,
		test_arc_height,
		test_gameplay_launch_solver,
	]
	_run_test_list(totals, tests)


## Simulate a shot in flight and return the landing position on the court floor.
## Detects net crossings and returns the net-crossing point if the ball clips the net.
func simulate_shot_landing(ball_pos: Vector3, shot_vel: Vector3, spin: Vector3) -> Vector3:
	var grav: float = _Ball.get_effective_gravity()
	var p: Vector3 = ball_pos
	var v: Vector3 = shot_vel
	var o: Vector3 = spin
	for _step in range(300):
		var prev_p: Vector3 = p
		var stepped: Array = _Ball.predict_aero_step(p, v, o, grav, 0.02)
		p = stepped[0]
		v = stepped[1]
		o = stepped[2]
		# Net collision check — detect crossing of net plane (z=0)
		if (prev_p.z < 0.0 and p.z >= 0.0) or (prev_p.z > 0.0 and p.z <= 0.0):
			var t: float = absf(prev_p.z) / maxf(absf(p.z - prev_p.z), 0.001)
			var net_y: float = lerpf(prev_p.y, p.y, t)
			if net_y < 1.0:
				return Vector3(lerpf(prev_p.x, p.x, t), net_y, 0.0)
		if p.y <= 0.08:
			return p
	return p


## Seed Godot's global RNG for _pick_ai_target_in_service_box determinism.
## randf() in GDScript uses the global RandomNumberGenerator, not the instance.
func _seed_global_rng(seed_value: int) -> void:
	seed(seed_value)


## ── Scenario 1 — Baseline Returns ────────────────────────────────────────────
## Shots from a variety of mid-court positions should land on the AI side
## (z > 0.5) and not clip the net. Tests the core lob/slice targeting.
func test_baseline_returns() -> void:
	var ai_z_positions := [-5.0, -3.5, -2.0]
	var ball_heights := [0.6, 0.9, 1.2]
	var ball_z_positions := [-2.5, -1.5, -0.5]
	var charges := [0.3, 0.6, 1.0]
	var total := 0
	var passed := 0

	for ai_z in ai_z_positions:
		for ball_h in ball_heights:
			for ball_z in ball_z_positions:
				for ch in charges:
					for _trial in range(10):
						_ai_player.global_position = Vector3(-1.0, 0.075, ai_z)
						var ball_pos := Vector3(-0.5, ball_h, ball_z)
						var shot_vel := _brain.compute_ai_shot_velocity(ball_pos, ch, 0)
						var spin := _fake_game.compute_shot_spin("", shot_vel, ch, 1, 0)
						var landing := simulate_shot_landing(ball_pos, shot_vel, spin)
						total += 1
						if landing.z > 0.5:
							passed += 1

	var rate := float(passed) / float(total) * 100.0
	print("S1 Baseline Returns: %d/%d (%.1f%%)" % [passed, total, rate])
	_assert_ge(rate, 95.0, "S1 landing rate >= 95%%")


## ── Scenario 2 — Deep Court Returns ──────────────────────────────────────────
## Balls arriving deep on the AI side should be returned deep, clearing
## the net reliably at all difficulty levels.
func test_deep_court_returns() -> void:
	_ai_player.global_position = Vector3(-1.0, 0.075, -6.0)
	var ball_pos := Vector3(-0.5, 0.8, -5.5)
	var charges := [0.8, 1.0]
	var difficulties := [1, 2]
	var total := 0
	var passed := 0

	for ch in charges:
		for diff in difficulties:
			for _trial in range(20):
				var shot_vel := _brain.compute_ai_shot_velocity(ball_pos, ch, diff)
				var spin := _fake_game.compute_shot_spin("", shot_vel, ch, 1, 0)
				var landing := simulate_shot_landing(ball_pos, shot_vel, spin)
				total += 1
				if landing.z > 1.0:
					passed += 1

	var rate := float(passed) / float(total) * 100.0
	print("S2 Deep Court Returns: %d/%d (%.1f%%)" % [passed, total, rate])
	_assert_ge(rate, 90.0, "S2 landing rate >= 90%%")


## ── Scenario 3 — Kitchen / Volley Returns ────────────────────────────────────
## Balls hit from inside or just behind the non-volley zone should land
## on the AI side without being shanked into the net.
func test_kitchen_returns() -> void:
	var ai_z_positions := [-1.0, -0.5, 0.0, 0.5]
	var ball_z_positions := [-0.5, 0.0, 0.5, 1.0]
	var charges := [0.5, 1.0]
	var total := 0
	var passed := 0

	for ai_z in ai_z_positions:
		_ai_player.global_position = Vector3(-1.0, 0.075, ai_z)
		for ball_z in ball_z_positions:
			for ch in charges:
				for diff in [0, 1, 2]:
					for _trial in range(10):
						var ball_pos := Vector3(-0.5, 0.75, ball_z)
						var shot_vel := _brain.compute_ai_shot_velocity(ball_pos, ch, diff)
						var spin := _fake_game.compute_shot_spin("", shot_vel, ch, 1, 0)
						var landing := simulate_shot_landing(ball_pos, shot_vel, spin)
						total += 1
						if landing.z > 0.5 and landing.z < 7.0:
							passed += 1

	var rate := float(passed) / float(total) * 100.0
	print("S3 Kitchen Returns: %d/%d (%.1f%%)" % [passed, total, rate])
	_assert_ge(rate, 95.0, "S3 kitchen rate >= 95%%")


## ── Scenario 4 — Net Clearance ───────────────────────────────────────────────
## The ball must clear the net (1.0m at center) on every shot. Uses the
## brain's internal net-height predictor to check clearance directly.
func test_net_clearance() -> void:
	var positions := [
		[Vector3(-1.0, 0.075, -5.0), Vector3(-0.5, 0.9, -2.5), 0.6, 0],
		[Vector3(-1.0, 0.075, -6.0), Vector3(-0.5, 0.8, -5.5), 1.0, 1],
		[Vector3(-1.0, 0.075, -1.0), Vector3(-0.5, 0.75, 0.5), 1.0, 0],
	]
	var total := 0
	var passed := 0

	for pos_data in positions:
		var ai_pos: Vector3 = pos_data[0]
		var ball_pos: Vector3 = pos_data[1]
		var ch: float = pos_data[2]
		var diff: int = pos_data[3]
		_ai_player.global_position = ai_pos
		for _trial in range(20):
			var shot_vel := _brain.compute_ai_shot_velocity(ball_pos, ch, diff)
			var spin := _fake_game.compute_shot_spin("", shot_vel, ch, 1, 0)
			var net_h := _brain._simulate_net_height(ball_pos, shot_vel, spin, 0.0)
			total += 1
			if net_h >= 0.95:
				passed += 1

	var rate := float(passed) / float(total) * 100.0
	print("S4 Net Clearance: %d/%d (%.1f%%)" % [passed, total, rate])
	_assert_ge(rate, 100.0, "S4 net clearance rate >= 100%%")


## ── Scenario 5 — In-Bounds Landing ───────────────────────────────────────────
## No shot should land outside the court boundaries (|x| < 3.05, |z| < 6.7).
## This catches gross targeting errors that send balls wide or long.
func test_in_bounds() -> void:
	var checks := [
		[Vector3(-1.0, 0.075, -5.0), Vector3(-0.5, 0.9, -2.5), 0.6, 0],
		[Vector3(-1.0, 0.075, -6.0), Vector3(-0.5, 0.8, -5.5), 1.0, 1],
		[Vector3(-1.0, 0.075, -1.0), Vector3(-0.5, 0.75, 0.5), 1.0, 0],
	]
	var total := 0
	var passed := 0

	for data in checks:
		_ai_player.global_position = data[0]
		var ball_pos: Vector3 = data[1]
		var ch: float = data[2]
		var diff: int = data[3]
		for _trial in range(20):
			var shot_vel := _brain.compute_ai_shot_velocity(ball_pos, ch, diff)
			var spin := _fake_game.compute_shot_spin("", shot_vel, ch, 1, 0)
			var landing := simulate_shot_landing(ball_pos, shot_vel, spin)
			total += 1
			if absf(landing.x) < 3.05 and absf(landing.z) < 6.7:
				passed += 1

	var rate := float(passed) / float(total) * 100.0
	print("S5 In-Bounds: %d/%d (%.1f%%)" % [passed, total, rate])
	_assert_ge(rate, 95.0, "S5 in-bounds rate >= 95%%")


## ── Scenario 6 — Target Zone Coverage ────────────────────────────────────────
## The AI should always pick targets inside the service box on its side
## (z > NON_VOLLEY_ZONE, z < 6.7, |x| < 3.05). Tests _pick_ai_target_in_service_box.
func test_target_zone_coverage() -> void:
	for diff in [0, 1, 2]:
		var total := 0
		var passed := 0
		for i in range(100):
			_rng.seed = 12345 + diff * 1000 + i
			# _pick_ai_target_in_service_box uses randf() — seed global RNG for determinism
			_seed_global_rng(_rng.seed)
			var target := _brain._pick_ai_target_in_service_box(diff, 0.7)
			total += 1
			var tx: float = target.x
			var tz: float = target.y
			if absf(tx) < 3.05 and absf(tz) > _Constants.NON_VOLLEY_ZONE and absf(tz) < 6.7 and tz > 0.0:
				passed += 1

		var rate := float(passed) / float(total) * 100.0
		print("S6 Target Zone D%d: %d/%d (%.1f%%)" % [diff, passed, total, rate])
		_assert_ge(rate, 100.0, "S6 D%d target zone rate >= 100%%" % diff)


## ── Scenario 7 — Trajectory-Marker Consistency ───────────────────────────────
## The predicted landing should be near the chosen target marker, confirming
## the shot solver and the marker picker are in agreement.
func test_marker_consistency() -> void:
	var total := 0
	var passed := 0
	for i in range(20):
		_rng.seed = 2000 + i
		var ai_z := -5.0 + _rng.randf_range(0.0, 3.0)
		var ball_z := -2.5 + _rng.randf_range(0.0, 2.0)
		_ai_player.global_position = Vector3(-1.0, 0.075, ai_z)
		var ball_pos := Vector3(-0.5, 0.9, ball_z)
		_seed_global_rng(2000 + i)
		var target := _brain._pick_ai_target_in_service_box(0, 0.7)
		var shot_vel := _brain.compute_ai_shot_velocity(ball_pos, 0.7, 0, target)
		var spin := _fake_game.compute_shot_spin("", shot_vel, 0.7, 1, 0)
		var landing := simulate_shot_landing(ball_pos, shot_vel, spin)
		total += 1
		var dz: float = absf(target.y - landing.z)
		var dx: float = absf(target.x - landing.x)
		if dz < 0.4 and dx < 0.4:
			passed += 1

	var rate := float(passed) / float(total) * 100.0
	print("S7 Marker Consistency: %d/%d (%.1f%%)" % [passed, total, rate])
	_assert_ge(rate, 100.0, "S7 marker consistency rate >= 100%%")


## Simulate a shot in flight and return the maximum height (apex) reached.
func simulate_shot_apex(ball_pos: Vector3, shot_vel: Vector3, spin: Vector3) -> float:
	var grav: float = _Ball.get_effective_gravity()
	var p: Vector3 = ball_pos
	var v: Vector3 = shot_vel
	var o: Vector3 = spin
	var apex: float = ball_pos.y
	for _step in range(300):
		var stepped: Array = _Ball.predict_aero_step(p, v, o, grav, 0.02)
		p = stepped[0]
		v = stepped[1]
		o = stepped[2]
		apex = maxf(apex, p.y)
		if p.y <= 0.08:
			break
	return apex


## ── Scenario 8 — Arc Height ──────────────────────────────────────────────────
## The ball must arc high enough above the net to clear reliably.
## A comfortable clearance is apex >= 1.5m for normal shots and >= 2.0m for
## deep-court lobs. Low apex shots are prone to clipping the net.
func test_arc_height() -> void:
	var checks := [
		# [ai_pos, ball_pos, charge, diff, min_apex]
		[Vector3(-1.0, 0.075, -5.0), Vector3(-0.5, 0.9, -2.5), 0.6, 0, 1.5],
		[Vector3(-1.0, 0.075, -6.0), Vector3(-0.5, 0.8, -5.5), 1.0, 1, 2.0],
		[Vector3(-1.0, 0.075, -1.0), Vector3(-0.5, 0.75, 0.5), 1.0, 0, 1.5],
		[Vector3(-1.0, 0.075, -2.0), Vector3(-0.5, 0.6, -1.5), 0.5, 0, 1.5],
	]
	var total := 0
	var passed := 0

	for data in checks:
		_ai_player.global_position = data[0]
		var ball_pos: Vector3 = data[1]
		var ch: float = data[2]
		var diff: int = data[3]
		var min_apex: float = data[4]
		var scenario_passed := 0
		for _trial in range(20):
			var shot_vel := _brain.compute_ai_shot_velocity(ball_pos, ch, diff)
			var spin := _fake_game.compute_shot_spin("", shot_vel, ch, 1, 0)
			var apex := simulate_shot_apex(ball_pos, shot_vel, spin)
			total += 1
			if apex >= min_apex:
				passed += 1
				scenario_passed += 1

	var rate := float(passed) / float(total) * 100.0
	print("S8 Arc Height: %d/%d (%.1f%%)" % [passed, total, rate])
	_assert_ge(rate, 100.0, "S8 arc height rate >= 100%%")


func test_gameplay_launch_solver() -> void:
	var physics := ShotPhysics.new()
	seed(3301)
	for difficulty in range(3):
		for court_z in [-5.0, -3.0, -1.0]:
			var ball_pos := Vector3(-0.5, 0.9, court_z)
			var launch: Dictionary = physics.solve_ai_launch(ball_pos, 0.6, difficulty, 0,
				ball_pos + Vector3(0.03, 0.02, 0.0), Vector3(1.0, 0.0, 2.0), 0.4)
			_assert_false(launch.is_empty(), "gameplay solver found a launch")
			if launch.is_empty():
				continue
			var flight: Dictionary = _Flight.trace(ball_pos, launch["velocity"], launch["omega"], 3.0, 1, false)
			var landing: Vector3 = flight["first_bounce"]
			_assert_false(flight["net_hit"], "gameplay launch clears net")
			_assert_in_range(landing.x, -3.05, 3.05, "gameplay launch stays within sidelines")
			_assert_in_range(landing.z, 0.0, 6.7, "gameplay launch stays within baseline")
			_assert_le(landing.distance_to(launch["target"]), 0.5, "gameplay launch lands near its target")
