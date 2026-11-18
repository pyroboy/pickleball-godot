extends SceneTree
const Guide = preload("res://scripts/ui/incoming_movement_guide.gd")
const Feeds = preload("res://tools/cloud_qa/movement_guide_fixtures.gd")
const Fixture = preload("res://scripts/tests/fixtures/charged_footwork_fixture.gd")
var game
var guide
var rate := 60
var baseline := false
var output := "/tmp/movement-status-stability.json"
var checks := 0
var failures: Array[String] = []
var records: Array = []
var name := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rate="): rate = int(arg.trim_prefix("--rate="))
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg == "--baseline": baseline = true
	Engine.physics_ticks_per_second = rate
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(name + ": " + label)

func run() -> void:
	root.size = Vector2i(540,960); root.content_scale_size = Vector2i(720,1280)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	Fixture.configure(game)
	Feeds.detach_automatic(game)
	game.process_mode = Node.PROCESS_MODE_DISABLED
	guide = load("res://tools/cloud_qa/movement_status_stability/before_incoming_movement_guide.gd").new() if baseline else Guide.new()
	game.add_child(guide); guide.setup(game)
	guide.set_process(false); guide.set_physics_process(false)
	captured_episode()
	for moving in [false, true]: real_flight(moving)
	if not baseline:
		gate_controls()
		presentation_controls()
	var report := {"rate": rate, "baseline": baseline, "checks": checks, "failures": failures, "cases": records,
		"scope": "Presentation-only C follow-up on archived build28 source; frozen C and unseen newer Mac source unmodified"}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for failure in failures: push_error(failure)
	print("MOVEMENT STATUS STABILITY %d Hz baseline=%s: %d checks, %d failures" % [rate,baseline,checks,failures.size()])
	game.queue_free(); await process_frame; await process_frame
	var until := Time.get_ticks_usec() + 150000
	while Time.get_ticks_usec() < until: OS.delay_msec(5); await process_frame
	quit(0 if failures.is_empty() else 1)

func captured_episode() -> void:
	name = "captured_status_episode"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/cloud_qa/movement_status_stability/captured_episode.json"))
	var gate := Guide.NoTimeEntryGate.new()
	var changes := 0
	var entries := 0
	var invalid_no_time := 0
	var previous := ""
	var previous_usec := -1
	for row in data.samples:
		var raw := str(row.guide_status)
		var delta := 0.0 if previous_usec < 0 else float(int(row.usec) - previous_usec) / 1000000.0
		previous_usec = int(row.usec)
		# This is the observed status sequence only. The captured source did
		# not record proof/target geometry, so none is invented in this replay.
		var accepted := gate.observe(raw == "NO_TIME", [row.flight,row.bounce], delta)
		var shown := raw if baseline or raw != "NO_TIME" or accepted else "TIGHT"
		if shown == "NO_TIME" and raw != "NO_TIME": invalid_no_time += 1
		if previous != "" and shown != previous: changes += 1
		if shown == "NO_TIME" and previous != "NO_TIME": entries += 1
		previous = shown
	check(invalid_no_time == 0, "added unsupported NO_TIME to captured statuses")
	if not baseline: check(entries == 0, "captured one-frame proof pulses still flash")
	records.append({"case":name,"status_switches":changes,"no_time_entries":entries,"false_no_time_frames":invalid_no_time,"samples":data.samples.size(),"evidence":"Exact observed status replay only; separate real-advisor scenarios validate geometry."})

func prepare_long_feed() -> void:
	guide.player = Feeds.prepare(game,"NO_TIME")
	game.player_left.global_position.x = -3.0
	game.player_left.current_velocity = Vector3.ZERO
	game.player_left.leg_ik.feet_initialized = false
	game.player_left._process(0.0)
	game.ball.global_position = Vector3(3.0,1.1,4.0)
	game.ball.linear_velocity = Vector3(0.0,-0.5,0.3)
	game.ball.angular_velocity = Vector3.ZERO
	guide.advisor = Guide.Advisor.new()
	guide._reset_generation = game._point_reset_generation
	guide.cancel()

func real_flight(moving: bool) -> void:
	name = "real_manual_moving" if moving else "real_stationary"
	prepare_long_feed()
	var rows := []
	var raw_entries := 0
	var shown_entries := 0
	var false_no_time := 0
	var last_raw := ""
	var last_shown := ""
	var raw_frames := 0
	var shown_frames := 0
	var target_changes := 0
	var last_target := Vector3.INF
	for frame in range(rate):
		var flight := Feeds.flight(game)
		var before := str([game.player_left.global_transform, game.player_left.current_velocity, game.ball.global_transform,game.ball.linear_velocity,Input.is_action_pressed("ui_accept")])
		guide.tick(0.0 if frame == 0 else 1.0/rate,flight)
		var raw := str(guide._advice.get("status","UNKNOWN"))
		var presentation: Dictionary = guide.presentation_state()
		var shown := str(presentation.get("status","UNKNOWN"))
		check(before == str([game.player_left.global_transform, game.player_left.current_velocity, game.ball.global_transform,game.ball.linear_velocity,Input.is_action_pressed("ui_accept")]),"guide changed gameplay/input")
		if raw == "NO_TIME": raw_frames += 1
		if raw == "NO_TIME" and last_raw != raw: raw_entries += 1
		if shown == "NO_TIME":
			shown_frames += 1
			if raw != "NO_TIME" or not guide._advice.get("no_time_proven",false) or guide._advice.get("proof_scope","") != "predicted_legal_flight": false_no_time += 1
		if shown == "NO_TIME" and last_shown != shown: shown_entries += 1
		if not presentation.is_empty():
			check(presentation.target_world.x == guide._advice.target_root.x and presentation.target_world.z == guide._advice.target_root.z,"marker left exact advisor root")
			if last_target.is_finite() and last_target != guide._advice.target_root: target_changes += 1
			last_target = guide._advice.target_root
			var detached = Guide.Advisor.snapshot(game.player_left)
			detached.place(guide._advice.target_root)
			check(Guide.Advisor.Planner.point_fits(detached,PostureLibrary.instance().get_def(guide._advice.posture),guide._advice.point),"displayed candidate lost legal reach geometry")
			if raw == "NO_TIME": check(shown != "MOVE","pending global proof invented comfortable MOVE")
		rows.append({"frame":frame,"raw":raw,"shown":shown,"proof":guide._advice.get("no_time_proven",false),"root":game.player_left.global_position,"target":guide._advice.get("target_root",Vector3.INF),"remaining":guide._advice.get("remaining_time",0.0),"reason":guide._advice.get("reason","")})
		last_raw = raw; last_shown = shown
		var next: Dictionary = flight.samples[1]
		game.ball.global_position = next.pos; game.ball.linear_velocity = next.vel; game.ball.angular_velocity = next.omega
		game.ball.bounces_since_last_hit += int(next.bounces)
		if moving:
			# Real manual acceleration/braking method with a bounded manual
			# command; integrate the returned velocity exactly as player.gd does.
			game.player_left.current_velocity = game.player_left._manual_ground_velocity(Vector3.RIGHT * 0.4,true,1.0/rate)
			game.player_left.global_position += game.player_left.current_velocity / rate
		if game.ball.bounces_since_last_hit >= 2: break
	check(raw_frames > 0,"fixture failed to produce real global proof")
	check(false_no_time == 0,"displayed NO_TIME without current advisor proof")
	if not baseline:
		check(shown_entries == 0 if moving else shown_frames > 0 and shown_entries == 1,"moving proof flashed or continuous stationary proof blinked")
	records.append({"case":name,"raw_no_time_entries":raw_entries,"shown_no_time_entries":shown_entries,"raw_no_time_frames":raw_frames,"shown_no_time_frames":shown_frames,"false_no_time_frames":false_no_time,"target_changes":target_changes,"rows":rows})

func gate_controls() -> void:
	name = "entry_gate_controls"
	var gate := Guide.NoTimeEntryGate.new()
	var dt := 1.0 / rate
	var context := [21,1,1,true,1,1,Vector2(720,1280)]
	for cycle in 10:
		check(not gate.observe(true,context,dt),"first proof sample admitted")
		for frame in range(maxi(1,rate/10-1)): check(not gate.observe(false,context,dt),"invalid proof retained")
	gate.reset()
	var first := -1
	for frame in range(rate/4):
		if gate.observe(true,context,dt) and first < 0: first = frame
	check(first >= 0 and float(first)/rate >= Guide.NO_TIME_ENTRY_SECONDS - 0.00001 and float(first)/rate <= Guide.NO_TIME_ENTRY_SECONDS + dt,"entry is not rate-aware")
	check(not gate.observe(false,context,0.0),"proof loss waited to clear")
	check(not gate.observe(true,context,dt),"reentry inherited old admission")
	for changed in [[22,1,1,true,1,1,Vector2(720,1280)],[21,0,1,true,1,1,Vector2(720,1280)],[21,1,1,false,1,1,Vector2(720,1280)],[21,1,1,true,1,2,Vector2(720,1280)],[21,1,1,true,1,1,Vector2(1280,720)]]:
		for frame in range(rate/4): gate.observe(true,context,dt)
		check(not gate.observe(true,changed,dt),"changed flight/bounce/rules/camera/viewport inherited proof time")
	gate.reset(); check(not gate.admitted,"reset retained admission")
	for scale in [1.0,0.12,0.001]:
		gate.reset()
		var first_frame := -1
		for frame in range(rate/4):
			var physics_delta: float = dt * scale
			if gate.observe(true,context,physics_delta/scale) and first_frame < 0: first_frame = frame
		check(first_frame == first,"slow motion stretched real display entry delay")

func presentation_controls() -> void:
	name = "presentation_safety_controls"
	prepare_long_feed()
	guide.tick(0.0,Feeds.flight(game))
	for frame in 100: guide._reproject()
	check(not guide._no_time_entry.admitted and guide._no_time_entry.elapsed == 0.0,"render-only callbacks manufacture continuous proof time")
	for frame in range(rate/4): guide.tick(1.0/rate,Feeds.flight(game))
	var base: Dictionary = guide._advice.duplicate(true)
	check(guide.presentation_state().get("status","") == "NO_TIME","stationary held test did not admit")
	game.player_left.global_position.x += 0.001
	guide._process(0.0)
	check(guide.presentation_state().get("status","") != "NO_TIME","render retained proof after between-tick root move")
	game.player_left.global_position = base.solved_root
	guide._advice = base.duplicate(true)
	guide._reproject()
	check(guide.presentation_state().get("status","") != "NO_TIME","root return bypassed reentry")
	for frame in range(rate/4): guide.tick(1.0/rate,Feeds.flight(game))
	game.player_left.current_velocity = Vector3.RIGHT * (game.player_left.move_speed + 1.0)
	guide._process(0.0)
	check(guide.presentation_state().get("status","") != "NO_TIME","between-tick speed increase retained an invalid proof")
	game.player_left.current_velocity = Vector3.ZERO
	guide._process(0.0)
	check(guide.presentation_state().get("status","") != "NO_TIME","speed return bypassed reentry")
	for invalid in ["unknown","unproven","scope","expired","nonfinite_time","target","pause","setting","reset","camera","flight","bounce","outgoing","opening_bounce"]:
		prepare_long_feed()
		for frame in range(rate/4): guide.tick(1.0/rate,Feeds.flight(game))
		var camera: Camera3D = root.get_camera_3d()
		match invalid:
			"unknown": guide._advice = {"visible":false,"status":"UNKNOWN"}
			"unproven": guide._advice.no_time_proven = false
			"scope": guide._advice.proof_scope = "candidate_only"
			"expired": guide._advice.remaining_time = 0.0
			"nonfinite_time": guide._advice.remaining_time = NAN
			"target": guide._advice.target_root = Vector3.INF
			"pause": paused = true
			"setting": root.get_node("Settings")._config.set_value("gameplay","movement_guide",false)
			"reset": game._point_reset_generation += 1
			"camera": camera.clear_current(false)
			"flight": game.ball.flight_id += 1
			"bounce": game.ball.bounces_since_last_hit = 0
			"outgoing": game.ball.last_hit_by = game.player_left.player_num
			"opening_bounce": game.ball.both_bounces_complete = false
		guide._process(0.0)
		check(guide.presentation_state().is_empty(),invalid + " retained stale positive guidance")
		paused = false; root.get_node("Settings")._config.set_value("gameplay","movement_guide",true); camera.make_current()
		guide.cancel()
		check(not guide._no_time_entry.admitted,"cancel did not reset entry")

	# A different valid camera clears admission even between physics updates;
	# current legal target remains advisory TIGHT until new proof observations.
	prepare_long_feed()
	for frame in range(rate/4): guide.tick(1.0/rate,Feeds.flight(game))
	var old_camera: Camera3D = root.get_camera_3d()
	var alternate := Camera3D.new()
	game.add_child(alternate); alternate.global_transform = old_camera.global_transform
	alternate.make_current(); guide._process(0.0)
	check(guide.presentation_state().get("status","") != "NO_TIME","camera switch retained prior admission")
	old_camera.make_current(); alternate.free()
	for scale in [0.12,0.001]:
		prepare_long_feed()
		Engine.time_scale = scale
		var first_admitted := -1
		for frame in range(rate/4):
			guide.tick(scale/rate,Feeds.flight(game))
			if guide.presentation_state().get("status","") == "NO_TIME" and first_admitted < 0: first_admitted = frame
		check(first_admitted >= 0 and float(first_admitted)/rate <= Guide.NO_TIME_ENTRY_SECONDS + 1.0/rate,"slow focus delayed stationary proof beyond display interval")
		Engine.time_scale = 1.0
