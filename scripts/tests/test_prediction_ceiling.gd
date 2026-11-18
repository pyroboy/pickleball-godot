extends SceneTree
const Fixture = preload("res://scripts/tests/fixtures/charged_footwork_fixture.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
var failures: Array[String] = []
var checks: = 0
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func run() -> void :
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	Fixture.configure(game);Fixture.prepare(game, Fixture.cases()[0])
	var ball = game.ball
	ball.global_position = Vector3(-1.5, 3.0, -3.0);ball.linear_velocity = Vector3(0.4, 12, 4);ball.angular_velocity = Vector3.ZERO;ball.flight_id += 1
	var trace: Dictionary = Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity, 1.6)
	var hit_ceiling: = false
	for sample in trace.samples:
		check(sample.pos.y <= Ball.FLIGHT_CEILING_Y + 0.0001, "predicted high lob exceeds live ceiling")
		if is_equal_approx(sample.pos.y, Ball.FLIGHT_CEILING_Y):
			hit_ceiling = true;check(sample.vel.y <= 0, "predicted ceiling retained upward velocity")
	check(hit_ceiling, "test did not exercise ceiling")
	var max_position_error: = 0.0
	for frame in range(70):
		await physics_frame
		var predicted: Vector3 = trace.samples[frame + 1].pos
		max_position_error = maxf(max_position_error, predicted.distance_to(ball.global_position))
	check(max_position_error < 0.15, "live high-lob path diverges from prediction: " + str(max_position_error))
	for failure in failures: push_error(failure)
	print("PREDICTION CEILING: %d checks, %d failures; max live position error=%.4f m" % [checks, failures.size(), max_position_error])
	game.queue_free(); await process_frame; await process_frame
	quit(0 if failures.is_empty() else 1)
