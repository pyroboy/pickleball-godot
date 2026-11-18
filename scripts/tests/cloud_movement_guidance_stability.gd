extends "res://scripts/tests/cloud_movement_guidance.gd"
## Before/after temporal audit. Only test code moves roots/advances ball state.
var audit_stage := "before"
var audit_records: Array = []
func run() -> void:
	audit_stage = OS.get_environment("MOVEMENT_GUIDANCE_STAGE")
	if audit_stage.is_empty(): audit_stage = "before"
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	Fixture.configure(game)
	game.process_mode = Node.PROCESS_MODE_DISABLED
	for spec in [
		{"name": "stationary_forehand", "case": 1, "motion": "still"},
		{"name": "stationary_backhand", "case": 2, "motion": "still"},
		{"name": "stationary_forward", "case": 3, "motion": "still"},
		{"name": "manual_approach", "case": 1, "motion": "chase"},
		{"name": "standing_boundary", "case": 1, "motion": "cross"},
		{"name": "focus_chase", "case": 1, "motion": "chase", "focus": 0.22},
	]:
		audit_case(spec)
	var output := {"stage": audit_stage, "rate": rate, "checks": checks, "failures": failures, "cases": audit_records}
	var destination := OS.get_environment("MOVEMENT_GUIDANCE_REPORT")
	if destination.is_empty(): destination = "/tmp/movement-stability-%s-%d.json" % [audit_stage, rate]
	var file := FileAccess.open(destination, FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t")); file.close()
	for failure in failures: push_error(failure)
	print("MOVEMENT STABILITY %s %d Hz: %d checks, %d failures" % [audit_stage, rate, checks, failures.size()])
	for row in audit_records:
		print("STABILITY ", row.name, " ", JSON.stringify(row.metrics))
	game.queue_free(); await process_frame; await process_frame
	var until := Time.get_ticks_usec() + 150000
	while Time.get_ticks_usec() < until: OS.delay_msec(5); await process_frame
	quit(0 if failures.is_empty() else 1)

func audit_case(spec: Dictionary) -> void:
	current_case = spec.name
	prepare(Fixture.cases()[spec.case])
	var player = game.player_left
	var human = player.posture.human_contact
	var advisor = Advisor.new()
	var delta := 1.0 / rate
	var focus: float = spec.get("focus", 1.0)
	var simulated_time := 0.0
	var previous: Dictionary = {}
	var previous_status := "UNKNOWN"
	var previous_visible := false
	var prior_visible: Dictionary = {}
	var frames: Array = []
	var jump_distances: Array[float] = []
	var posture_changes := 0
	var status_changes := 0
	var visibility_changes := 0
	var visible_with_current_contact := 0
	var hidden_inside_valid_flight := 0
	var gap_runs := 0
	var hidden_run := 0
	var longest_gap := 0
	var appeared := false
	var returned_after_gap := 0
	var cpu: Array[int] = []
	var last_solve_count := 0
	var refresh_records: Array = []
	var transitions: Array = []
	var virtual_ball: Dictionary = {"pos": game.ball.global_position, "vel": game.ball.linear_velocity, "omega": game.ball.angular_velocity}
	# Focus frames use exact fractional aerodynamic steps so camera/render cadence
	# differs from simulation time without cheating by changing prediction Hz.
	for frame in range(int(rate * 2.8 / focus)):
		var flight := trace()
		var controller_contact: Dictionary = Planner.select(Advisor.snapshot(player), game.ball, flight)
		human._flight_id = game.ball.flight_id
		human.contact = controller_contact
		var started := Time.get_ticks_usec()
		var result: Dictionary = advisor.update(delta * focus, player, game.ball, flight)
		cpu.append(Time.get_ticks_usec() - started)
		var visible: bool = result.visible
		if visible and not controller_contact.is_empty(): visible_with_current_contact += 1
		if visible:
			if previous_visible:
				var jump: float = result.target_root.distance_to(previous.target_root)
				if jump > 0.0001: jump_distances.append(jump)
				if result.posture != previous.posture: posture_changes += 1
				if result.status != previous.status: status_changes += 1
			if hidden_run > 0 and appeared:
				returned_after_gap += 1
				longest_gap = maxi(longest_gap, hidden_run)
				hidden_run = 0
			appeared = true
			prior_visible = result.duplicate()
		elif appeared and controller_contact.is_empty() and game.ball.is_in_play and game.ball.bounces_since_last_hit < 2:
			hidden_inside_valid_flight += 1
			if hidden_run == 0: gap_runs += 1
			hidden_run += 1
		if frame > 0 and (visible != previous_visible or result.status != previous_status):
			transitions.append({"frame": frame, "sim_time": simulated_time, "visible": visible, "reason": result.reason,
				"status": result.status, "controller_contact": not controller_contact.is_empty(), "result": result.duplicate()})
		if frame > 0 and visible != previous_visible: visibility_changes += 1
		if advisor.statistics.solves != last_solve_count:
			last_solve_count = advisor.statistics.solves
			refresh_records.append({"frame": frame, "sim_time": simulated_time, "root": player.global_position,
				"result": result.duplicate(true), "controller_contact": not controller_contact.is_empty()})
		if audit_stage == "after":
			check(not (visible and not controller_contact.is_empty()), "current legal contact retained movement cue mid-cache")
			check(advisor.statistics.last_geometry_tests <= Advisor.MAX_GEOMETRY_TESTS, "temporal hold exceeded geometry bound")
			if visible and advisor.statistics.solves == last_solve_count and float(result.get("age", 1.0)) < 0.000001:
				validate_candidate(result)
			if visible and previous_visible and result.target_root.distance_to(previous.target_root) > 0.0001:
				var verifier = Advisor.new()
				var old_candidate: Dictionary = verifier._retain_target(player, game.ball, flight, previous)
				check(old_candidate.is_empty() or (old_candidate.slack < 0.0 and result.slack >= old_candidate.slack + Advisor.RETARGET_SLACK_GAIN - 0.00001), "target changed while old exact target remained feasible")
		if spec.motion != "still":
			var target: Vector3 = player.global_position
			if spec.motion == "chase" and visible: target = result.target_root
			elif spec.motion == "cross": target.x = 1.2 + 0.48 * sin(simulated_time * 5.0)
			var offset: Vector3 = target - player.global_position
			offset.y = 0.0
			var requested: Vector3 = offset.limit_length(2.4 * delta * focus) / maxf(delta * focus, 0.000001)
			player.current_velocity = player._manual_ground_velocity(requested, requested.length() > 0.01, delta * focus)
			player.global_position += player.current_velocity * delta * focus
			player._advance_support_clock(delta * focus)
			player._process(delta * focus)
		previous = result.duplicate(true)
		previous_visible = visible
		previous_status = result.status
		# Match the predictor's one-step physics exactly in normal-speed runs.
		# A focus substep uses the same aerodynamic/bounce functions at scaled dt.
		if focus == 1.0:
			var next: Dictionary = flight.samples[1]
			game.ball.global_position = next.pos
			game.ball.linear_velocity = next.vel
			game.ball.angular_velocity = next.omega
			game.ball.bounces_since_last_hit += int(next.bounces)
		else:
			var next: Array = Ball.predict_aero_step(game.ball.global_position, game.ball.linear_velocity, game.ball.angular_velocity, Ball.get_effective_gravity(), delta * focus)
			game.ball.global_position = next[0]
			game.ball.linear_velocity = next[1]
			game.ball.angular_velocity = next[2]
			if game.ball.global_position.y > Ball.FLIGHT_CEILING_Y:
				game.ball.global_position.y = Ball.FLIGHT_CEILING_Y
				game.ball.linear_velocity.y = minf(game.ball.linear_velocity.y, 0.0)
			if game.ball.global_position.y < Flight.FLOOR_REST_Y and game.ball.linear_velocity.y < 0.0:
				game.ball.global_position.y = Flight.FLOOR_REST_Y
				game.ball.bounces_since_last_hit += 1
				var bounced: Array = Ball.predict_bounce_spin(game.ball.linear_velocity, game.ball.angular_velocity)
				game.ball.linear_velocity = bounced[0]; game.ball.angular_velocity = bounced[1]
		simulated_time += delta * focus
		if game.ball.bounces_since_last_hit >= 2: break
	cpu.sort(); jump_distances.sort()
	var big_jumps := 0
	for distance in jump_distances:
		if distance > 0.35: big_jumps += 1
	var metrics := {"simulated_time": simulated_time, "focus": focus, "frames": cpu.size(),
		"target_changes": jump_distances.size(), "large_target_jumps": big_jumps,
		"max_target_jump": jump_distances.back() if not jump_distances.is_empty() else 0.0,
		"posture_changes": posture_changes, "status_changes": status_changes, "visibility_changes": visibility_changes,
		"visible_with_current_contact_frames": visible_with_current_contact, "hidden_frames_without_current_contact": hidden_inside_valid_flight,
		"gap_runs": gap_runs, "returned_after_gap": returned_after_gap, "longest_closed_gap_frames": longest_gap,
		"update_cpu_median_usec": cpu[cpu.size() / 2], "update_cpu_p99_usec": cpu[mini(cpu.size() - 1, int(cpu.size() * 0.99))],
		"update_cpu_max_usec": cpu.back(), "statistics": advisor.statistics.duplicate()}
	audit_records.append({"name": spec.name, "metrics": metrics, "refreshes": refresh_records, "transitions": transitions})
