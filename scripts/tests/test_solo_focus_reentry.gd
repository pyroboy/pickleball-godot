extends SceneTree

var game
var checks: = 0
var failures: Array[String] = []
var now: = 100000000

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func prepare_flight(ttc: float = 0.4, locked: bool = true) -> void:
	game.input_handler.cancel_charge_input()
	game._reset_match()
	game._set_game_state(game.GameState.PLAYING)
	var player = game.player_left
	var ball = game.ball
	var human = player.posture.human_contact
	player.global_position = Vector3(0, player.ground_y, 3.2)
	ball.is_in_play = true
	ball.last_hit_by = 1
	ball.flight_id += 1
	ball.bounces_since_last_hit = 0
	ball.both_bounces_complete = true
	ball.global_position = Vector3(0.42, 1.1, 2.2)
	ball.linear_velocity = Vector3(0, 0, 6)
	ball.freeze = true
	human._flight_id = ball.flight_id
	human.phase = -1
	human.contact = {"point": Vector3(0.42, 1.1, 2.6), "time": ttc, "bounces": 1, "def": PostureLibrary.instance().all_definitions()[0]}
	human.anticipated_contact = {}
	player.hitting.charge_visual_active = true
	game.aim_controller.mode = "AIM" if locked else "PREPARE"
	game.aim_controller.planted = locked
	Input.action_press("ui_accept")
	now += 10000000

func step(usec: int) -> void:
	now += usec
	game.aim_focus.tick(now, true)

func run() -> void:
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	# Human contact setup is deferred; do not disable the scene before it exists.
	for setup_frame in 10:
		if game.player_left.posture.human_contact != null: break
		await process_frame; await physics_frame
	if game.player_left.posture.human_contact == null:
		push_error("Human contact setup did not complete");quit(2);return
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var f = game.aim_focus
	f.set_process(false)
	var settings = root.get_node("Settings")
	settings._config.set_value("gameplay", "aim_focus_seconds", 3.0)
	check(is_equal_approx(f.rally_window_seconds(), 3.0), "three-second default")

	prepare_flight(2.0, false)
	check(f.begin_hold(now) and f.holding and not f.active, "far press arms without slow motion")
	step(6000000)
	check(not f.active and not f.exhausted and f.deadline_usec == 0, "far preparation consumed aim deadline")
	game.player_left.posture.human_contact.contact.time = 0.4
	step(100000)
	check(not f.active and f.deadline_usec == 0, "unplanted reach started aim timer")
	game.aim_controller.mode = "AIM"; game.aim_controller.planted = true
	step(1)
	check(not f.active, "entry debounce missing")
	step(f.REACH_ENTER_USEC)
	check(f.active and f.deadline_usec == now + 3000000, "AIM lock-in failed to reserve entire three seconds")
	check(Engine.time_scale > 0.0 and Engine.time_scale < 0.13, "imminent adaptive brake not stronger than old curve")
	var deadline: int = f.deadline_usec
	var first_scale: float = Engine.time_scale
	var contact: Dictionary = game.player_left.posture.human_contact.contact.duplicate()
	game.player_left.posture.human_contact.contact = {}
	step(1); step(f.REACH_EXIT_USEC - 1)
	check(f.active and is_equal_approx(Engine.time_scale, first_scale), "one short reach dropout flickered or accelerated")
	step(1)
	check(not f.active and f.holding and is_equal_approx(Engine.time_scale, 1.0), "leaving reach did not restore normal speed while retaining hold")
	step(800000)
	game.player_left.posture.human_contact.contact = contact
	step(1); step(f.REACH_ENTER_USEC)
	check(f.active and f.deadline_usec == deadline, "held reentry failed or extended same-flight deadline")
	f.end_hold()
	check(not f.active and not f.holding, "release failed to clear focus")
	check(f.begin_hold(now), "same-flight new press could not arm remaining time")
	step(f.REACH_ENTER_USEC)
	check(f.active and f.deadline_usec == deadline, "repress refreshed same-flight timer")
	settings._config.set_value("gameplay", "aim_focus_seconds", 5.0)
	step(1)
	check(f.deadline_usec == deadline, "mid-flight settings change extended deadline")
	now = deadline
	f.tick(now, true)
	check(f.exhausted and not f.active and f.holding and is_equal_approx(Engine.time_scale, 1.0), "exact three-second wall cap failed")
	game.player_left.posture.human_contact.contact = {}; step(200000)
	game.player_left.posture.human_contact.contact = contact; step(200000)
	check(not f.active and f.exhausted, "edge wiggle refilled exhausted flight")
	f.end_hold(); f.begin_hold(now); step(100000)
	check(not f.active and f.exhausted, "repress refilled exhausted flight")
	game.ball.bounces_since_last_hit = 1; step(100000)
	check(not f.active and f.exhausted, "bounce refilled exhausted flight")

	game.ball.flight_id += 1
	game.player_left.posture.human_contact._flight_id = game.ball.flight_id
	game.player_left.posture.human_contact.contact.bounces = 0
	game.player_left._nvz_state.established_outside = true
	step(1); step(f.REACH_ENTER_USEC)
	check(f.active and not f.exhausted and f.deadline_usec == now + 5000000, "new incoming flight did not get configured window during held input")
	settings._config.set_value("gameplay", "aim_focus_seconds", 3.0)

	prepare_flight(0.09)
	f.begin_hold(now)
	check(f.active and f.deadline_usec == now + 3000000 and Engine.time_scale <= 0.020001, "urgent contact did not brake immediately for full configured window")
	prepare_flight(0.0)
	f.begin_hold(now)
	check(f.active and is_equal_approx(Engine.time_scale, f.RALLY_MIN_SCALE), "zero TTC must use finite floor, never freeze")
	game.ball.last_hit_by = 0; step(1)
	check(not f.active and is_equal_approx(Engine.time_scale, 1.0), "outgoing ball retained focus")

	prepare_flight(0.1)
	game.player_left.posture.human_contact._flight_id -= 1
	f.begin_hold(now); step(100000)
	check(not f.active and f.deadline_usec == 0, "stale flight contact activated focus")
	prepare_flight(0.1)
	game.player_left.posture.human_contact.anticipated_contact = game.player_left.posture.human_contact.contact.duplicate()
	game.player_left.posture.human_contact.contact = {}
	f.begin_hold(now); step(100000)
	check(not f.active and f.deadline_usec == 0, "anticipation-only contact activated focus")
	prepare_flight(0.1)
	game.ball.bounces_since_last_hit = 2
	f.begin_hold(now); step(100000)
	check(not f.active, "illegal second bounce activated focus")

	for reason in ["guide", "panel", "pause", "pvp", "window", "fault"]:
		prepare_flight(0.1); f.begin_hold(now)
		check(f.active, "cancel fixture not active: " + reason)
		match reason:
			"guide": game.hud._guide.show(); step(1); game.hud._guide.hide()
			"panel": game.practice_panel.show(); step(1); game.practice_panel.hide()
			"pause": paused = true; step(1); paused = false
			"pvp": game.pvp_mode = true; step(1); game.pvp_mode = false; f._sync_realtime_mode()
			"window": f._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
			"fault": game._set_game_state(game.GameState.POINT_SCORED)
		check(not f.active and not f.holding and is_equal_approx(Engine.time_scale, 1.0), "hard cancel retained focus: " + reason)
		step(100000)
		check(not f.active and not f.holding, "hard cancel restarted on held tail: " + reason)

	# A continuously updated legal TTC must not slide the timer or make the
	# ball reach the contact plane before the promised real aim window.
	for initial_ttc in [0.85, 0.18, 0.09]:
		prepare_flight(initial_ttc)
		f.begin_hold(now)
		if not f.active: step(f.REACH_ENTER_USEC)
		var simulation_deadline: int = f.deadline_usec
		var ttc: float = initial_ttc
		var duration: = 0.0
		while now + 16667 < simulation_deadline:
			ttc -= Engine.time_scale * 0.016667
			game.player_left.posture.human_contact.contact.time = maxf(0.0, ttc)
			step(16667); duration += 0.016667
			check(f.active and f.deadline_usec == simulation_deadline and Engine.time_scale >= f.RALLY_MIN_SCALE, "TTC controller lost active fixed deadline")
		check(ttc > 0.0 and duration > 2.95, "adaptive braking spent contact before three real seconds: " + str(initial_ttc))
		f.tick(simulation_deadline, true)
		check(not f.active and f.exhausted, "simulated window did not terminate at exact deadline")

	# Exercise actual planner live-window results, rather than manufacturing a
	# positive time value. The ball moves through that real planner slab.
	var planner = load("res://scripts/incoming_contact_planner.gd")
	var predictor = load("res://scripts/ball_flight_predictor.gd")
	for forward_offset in [0.52, 0.40, 0.34]:
		prepare_flight(0.0)
		var player = game.player_left
		var ball = game.ball
		var human = player.posture.human_contact
		ball.global_position = player.global_position + player._get_forward_axis() * forward_offset + player._get_forehand_axis() * 0.42
		ball.global_position.y = 1.1
		ball.linear_velocity = -player._get_forward_axis() * 8.0
		ball.bounces_since_last_hit = 1
		game.rally_scorer._serve_was_hit = true
		human.contact = planner.select(player, ball, predictor.trace(ball.global_position, ball.linear_velocity, Vector3.ZERO))
		check(not human.contact.is_empty() and is_zero_approx(float(human.contact.get("time", -1.0))), "actual live-slab planner fixture lacks zero-TTC contact")
		var live_sample: Dictionary = f._rally_contact_sample()
		check(not live_sample.is_empty() and float(live_sample.ttc) > 0.0, "live-slab zero TTC lost its remaining physical opportunity")
		f.begin_hold(now)
		var live_deadline: int = f.deadline_usec
		check(f.active and live_deadline == now + 3000000, "live-slab entry failed immediate full window")
		while now + 16667 < live_deadline:
			ball.global_position += ball.linear_velocity * Engine.time_scale * 0.016667
			human.contact = planner.select(player, ball, predictor.trace(ball.global_position, ball.linear_velocity, Vector3.ZERO))
			step(16667)
			check(f.active and not human.contact.is_empty() and Engine.time_scale > 0.0 and f.deadline_usec == live_deadline, "live-slab opportunity disappeared before fixed deadline")
		f.tick(live_deadline, true)
		check(f.exhausted and not f.active, "live-slab timer extended beyond three seconds")

	# Check the real wall clock and displayed countdown separately from the
	# accelerated deterministic/predictor cases above.
	prepare_flight(0.09)
	now = Time.get_ticks_usec()
	f.begin_hold(now)
	var real_start: int = now
	var real_deadline: int = f.deadline_usec
	game.hud.set_charge(0.4, true)
	check(game.hud._charge_label.text.contains("FOCUS 3.0s"), "HUD does not show the configured three-second countdown")
	Engine.max_fps = 60
	var maximum_frame: = 0
	while now < real_deadline:
		await process_frame
		var next: int = Time.get_ticks_usec()
		maximum_frame = maxi(maximum_frame, next - now)
		now = next
		f.tick(now, true)
	check(f.exhausted and not f.active and now - real_start >= 3000000 and now - real_start <= 3000000 + maximum_frame + 20000, "live three-second cap exceeded one observed frame")
	game.hud.set_charge(0.4, true)
	check(game.hud._charge_label.text.contains("REAL TIME"), "expired rally timer has no real-time feedback")
	Engine.max_fps = 0
	print("RALLY REAL CLOCK CAP: %dus, max frame %dus" % [now - real_start, maximum_frame])

	var panel = load("res://scripts/ui/settings_panel.gd").new()
	root.add_child(panel)
	var slider = panel.find_child("gameplay_aim_focus_seconds", true, false)
	check(slider is HSlider and slider.min_value == 1.0 and slider.max_value == 5.0 and slider.value == 3.0, "Gameplay lacks the default three-second rally timer slider")
	if slider is HSlider:
		slider.value = 2.5
		check(is_equal_approx(f.rally_window_seconds(), 2.5), "rally timer slider did not update preference")
		slider.value = 3.0
	panel.queue_free()

	Input.action_release("ui_accept"); f.end_hold()
	game.queue_free(); await process_frame; await process_frame
	check(is_equal_approx(Engine.time_scale, 1.0), "scene exit leaked slow motion")
	for failure in failures: push_error(failure)
	print("SOLO FOCUS REENTRY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
