extends SceneTree
const Fixture = preload("res://scripts/tests/fixtures/charged_footwork_fixture.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Planner = preload("res://scripts/incoming_contact_planner.gd")
const Feet = preload("res://scripts/charged_footwork.gd")
var game
var checks: = 0
var failures: Array[String] = []
var rows: Array = []
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func reset() -> void :
	Fixture.prepare(game, Fixture.cases()[0])
	var p = game.player_left
	p.global_position = Vector3(0, p.ground_y, 3.3);p.leg_ik.feet_initialized = false;p._process(0);p.can_volley_from_feet()
func run() -> void :
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	Fixture.configure(game)
	for mode in ["wrong_half", "out_first_bounce", "legal_receiver_bounce", "legal_opening_bounce", "wrong_service_diagonal", "legal_service"]:
		reset()
		var b = game.ball; var p = game.player_left
		b.global_position = Vector3(0.45, 0.8, 1.0);b.linear_velocity = Vector3(0, -4, 6);b.angular_velocity = Vector3.ZERO
		var rejected: bool = mode in ["wrong_half", "out_first_bounce", "wrong_service_diagonal"]
		if mode == "wrong_half": b.global_position = Vector3(0.45, 0.8, -2);b.linear_velocity = Vector3(0, -12, 6)
		if mode == "out_first_bounce":
			p.global_position.x = 2.6;b.global_position = Vector3(3.2, 0.8, 1.4);b.linear_velocity = Vector3(0, -12, 6)
			p.leg_ik.feet_initialized = false;p._process(0);p.can_volley_from_feet()
		if mode == "legal_opening_bounce": b.both_bounces_complete = false
		if mode in ["wrong_service_diagonal", "legal_service"]:
			game.rally_scorer._serve_was_hit = false;game.rally_scorer._serving_team = 1;game.rally_scorer._serving_from_right = true
			b.both_bounces_complete = false
			b.global_position = Vector3( - 0.45 if rejected else 0.45, 1.0, -2);b.linear_velocity = Vector3(0, 2, 7.3)
		b.flight_id += 1
		await physics_frame; await physics_frame
		var h = p.posture.human_contact
		var flight: Dictionary = Flight.trace(b.global_position, b.linear_velocity, b.angular_velocity)
		var fault: float = Planner.predicted_fault_time(p, b, flight)
		var standing: Dictionary = Planner.select(p, b, flight)
		var future: Dictionary = Feet.select_plan(p, b, flight)
		var first_bounce: float = flight.first_bounce_time
		if rejected:
			check(fault <= first_bounce + 1e-05, mode + " fault not recognized by first landing")
			check(standing.is_empty() and future.is_empty(), mode + " advertised contact after predicted fault")
			check(h.preparation_contact().is_empty(), mode + " live preparation retained invalid target")
			Fixture.press(game);Fixture.release(game)
			check(h.phase < 0 and not h.footwork.active, mode + " invalid flight queued assistance")
		else:
			check(fault > first_bounce + 0.001, mode + " legal first bounce incorrectly discarded")
			check( not standing.is_empty() or not future.is_empty(), mode + " valid receiving contact disappeared")
			var plan: Dictionary = standing if not standing.is_empty() else future
			if not plan.is_empty(): check(float(plan.time) < fault, mode + " selected contact is after fault")
		rows.append({"name": mode, "first_bounce": flight.first_bounce, "first_bounce_time": first_bounce, "fault_time": fault, "standing": standing.get("posture", -1), "future": future.get("posture", -1)})
		Fixture.release(game)

	reset(); var p = game.player_left; var b = game.ball
	var def = PostureLibrary.instance().get_def(0)
	b.global_position = p.global_position + def.resolve_paddle_offset(p._get_forehand_axis(), p._get_forward_axis())
	b.linear_velocity = Vector3(0, 0, 6);b.angular_velocity = Vector3.ZERO
	var out: Vector3 = Vector3(3.3, Flight.FLOOR_REST_Y, 4)
	var synthetic: Dictionary = {"samples": [{"time": 0.0, "pos": b.global_position, "bounces": 0}, {"time": 0.5, "pos": out, "bounces": 1}], "bounce_events": [{"time": 0.5, "pos": out}]}
	var contact: Dictionary = Planner.select(p, b, synthetic)
	check( not contact.is_empty() and float(contact.time) < 0.5, "legal pre-fault airborne contact rejected")
	var f = FileAccess.open("/tmp/early-predicted-fault-evidence.json", FileAccess.WRITE);f.store_string(JSON.stringify({"checks": checks, "failures": failures, "rows": rows}, "\t"));f.close()
	for failure in failures: push_error(failure)
	print("PREDICTED FAULT CUTOFF: %d checks, %d failures; %s" % [checks, failures.size(), JSON.stringify(rows)])
	game.queue_free(); await process_frame; await process_frame
	quit(0 if failures.is_empty() else 1)
