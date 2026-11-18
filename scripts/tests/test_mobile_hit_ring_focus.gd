extends SceneTree


const Distant = preload("res://scripts/tests/fixtures/distant_preparation_fixture.gd")
const Near = preload("res://scripts/tests/fixtures/charged_footwork_fixture.gd")
const Timing = preload("res://scripts/ui/hit_timing_feedback.gd")
var game
var checks: = 0
var failures: Array[String] = []
var pulses: Array = []
var hits: = 0
var trace: Array = []
var pending_captures: Array[String] = []
var output: = ""
var current_case: = ""
var start_usec: = 0
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(message)
func touch(down: bool, canceled: bool = false) -> void :
	var event: = InputEventScreenTouch.new()
	event.index = 86;event.position = game.mobile_controls._charge_center
	event.pressed = down;event.canceled = canceled
	root.push_input(event, true)
func frames(count: int) -> void :
	for i in count: await process_frame
func pulse(duration: int, amplitude: float) -> void :
	var timing = game.mobile_controls._hit_timing
	pulses.append({"case": current_case, "usec": Time.get_ticks_usec(), "flash_start": timing._flash_started_usec, "duration": duration, "amplitude": amplitude, "state": game.player_left.posture.human_contact.release_timing_state()})
	pending_captures.append("ready_flash")
func record_row() -> void :
	var controls = game.mobile_controls
	trace.append({"case": current_case, "elapsed": float(Time.get_ticks_usec() - start_usec) / 1000000.0, "ring_radius": controls._timing_radius(), "active": controls._hit_timing.active, "ready": controls._hit_timing.ready, "flash": controls._hit_timing.flash_strength(), "time_scale": Engine.time_scale, "focus": game.aim_focus.active, "charge": game.player_left.posture.human_contact.charge_ratio, "state": game.player_left.posture.human_contact.release_timing_state()})
func capture_pending() -> void :
	if output.is_empty() or pending_captures.is_empty(): return
	var image: = root.get_texture().get_image()
	for tag in pending_captures:
		image.save_png(output.path_join(current_case + "_" + tag + ".png"))
	pending_captures.clear()
func run() -> void :
	for arg in OS.get_cmdline_args():
		if arg == "--fixed-fps": push_error("Wall-clock test rejects fixed-fps");quit(2);return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): output = arg.trim_prefix("--capture-dir=")
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	if DisplayServer.get_name() == "headless": output = ""
	root.size = Vector2i(540, 1170);root.content_scale_size = Vector2i(720, 1560)
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	var settings = root.get_node("Settings")
	var prior_vibration: bool = settings.get_value("gameplay.timing_vibration")
	settings._config.set_value("gameplay", "timing_vibration", true)
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await frames(6)
	game.mobile_controls._hit_timing = Timing.new(pulse)
	game.ball.hit_by_paddle.connect( func(team): if team == 0: hits += 1)
	if not output.is_empty(): RenderingServer.frame_post_draw.connect(capture_pending)
	current_case = "distant"
	Distant.prepare(game, {"lateral": 5.0, "height": 1.1, "duration": 1.6}, true)
	game.input_handler.set_process(true)
	await frames(2)
	start_usec = Time.get_ticks_usec();touch(true)
	var first_radius: = 0.0
	var late_radius: = 0.0
	var active_frames: = 0
	var milestone: = 0
	while Time.get_ticks_usec() - start_usec < 4350000:
		await process_frame
		var elapsed: float = float(Time.get_ticks_usec() - start_usec) / 1000000.0
		var controls = game.mobile_controls
		if controls._hit_timing.active:
			if first_radius == 0.0: first_radius = controls._timing_radius()
			late_radius = controls._timing_radius()
		if controls._hit_timing.active:
			active_frames += 1
			check( not controls._hit_timing.ready and controls._hit_timing.flash_strength() == 0.0, "unreachable distant forecast gave green/flash")
			check(controls._timing_radius() >= controls._charge_radius + 18.0, "unreachable ring falsely merged with Hit")
		if elapsed >= float(milestone) and milestone < 5:
			pending_captures.append("hold_" + str(milestone));milestone += 1
		record_row()
	check(active_frames > 2, "distant preparation ring was not present during the real forecast")
	check(first_radius > 96.0 and late_radius >= 96.0 and late_radius < first_radius, "valid-forecast portion of real hold did not show readable contracting ring")
	check(not game.aim_focus.active and not game.aim_focus.exhausted and is_equal_approx(Engine.time_scale, 1.0), "unreachable distant hold spent the aim window")
	check(pulses.is_empty(), "unreachable hold pulsed")
	touch(false, true); await frames(2)
	check( not Input.is_action_pressed("ui_accept") and not game.mobile_controls._hit_timing.ready and game.mobile_controls._hit_timing.flash_strength() == 0.0, "canceled hold retained owned Hit/ring")
	current_case = "reachable"
	Near.configure(game);Near.prepare(game, Near.cases()[0])
	game.pvp_mode = false;game.aim_focus._sync_realtime_mode();game.input_handler.set_process(true)
	await frames(2)
	start_usec = Time.get_ticks_usec();touch(true)
	var reached: = false
	while Time.get_ticks_usec() - start_usec < 7000000:
		await process_frame;record_row()
		if game.mobile_controls._hit_timing.ready:
			reached = true;break
		if not game.ball.is_in_play: break
	check(reached, "real touch/solo clock failed to reach authoritative release window")
	if reached:
		var controls = game.mobile_controls
		check(controls._timing_radius() == controls._charge_radius, "actual release cue did not merge")
		check(pulses.size() == 1 and abs(pulses[0].usec - pulses[0].flash_start) < 1000 and pulses[0].duration == 35, "real ready flash and one 35ms pulse not synchronized")
		check(pulses[0].state.release_ready and pulses[0].state.current_reachable, "pulse did not use physical readiness")

		if not output.is_empty(): await RenderingServer.frame_post_draw
		touch(false)
		check(controls._hit_timing.flash_strength() == 0.0 and not controls._hit_timing.ready, "normal release left readiness flash")
		var deadline: int = Time.get_ticks_usec() + 2500000
		while Time.get_ticks_usec() < deadline and hits == 0: await process_frame
		check(hits == 1, "ready touch release failed real legal paddle contact")
		pending_captures.append("after_release")
		await frames(2)
	check(is_equal_approx(Engine.time_scale, 1.0), "release retained slow motion")
	game.mobile_controls.cancel_all()
	settings._config.set_value("gameplay", "timing_vibration", prior_vibration)
	if not output.is_empty():
		var file: = FileAccess.open(output.path_join("evidence.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "pulses": pulses, "hits": hits, "renderer": RenderingServer.get_video_adapter_name(), "trace": trace}, "\t"));file.close()
		RenderingServer.frame_post_draw.disconnect(capture_pending)
	game.queue_free(); await frames(2)
	var drain: int = Time.get_ticks_usec() + 180000
	while Time.get_ticks_usec() < drain: OS.delay_msec(5); await process_frame
	for failure in failures: push_error(failure)
	print("MOBILE HIT RING REAL CLOCK: %d checks, %d failures; pulses=%d hits=%d" % [checks, failures.size(), pulses.size(), hits])
	quit(0 if failures.is_empty() else 1)
