extends SceneTree


const Fixture = preload("res://scripts/tests/fixtures/charged_footwork_fixture.gd")
const Timing = preload("res://scripts/ui/hit_timing_feedback.gd")
const Layout = preload("res://scripts/ui/mobile_layout.gd")
var game
var checks: = 0
var failures: Array[String] = []
var pulses: = 0
var actual_hits: = 0
var captures: = ""
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(message)
func pulse(_duration: int, _amplitude: float) -> void : pulses += 1
func touch(down: bool, canceled: bool = false) -> void :
	var event: = InputEventScreenTouch.new()
	event.index = 81;event.position = game.mobile_controls._charge_center;event.pressed = down;event.canceled = canceled
	root.push_input(event, true)
func frames(count: int) -> void :
	for i in count: await physics_frame
func prepare() -> void :
	Fixture.prepare(game, Fixture.cases()[0])
	game.input_handler.set_process(true)
func record_hit(team: int) -> void :
	if team == 0: actual_hits += 1
func capture(tag: String) -> void :
	if captures.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(captures.path_join(tag + ".png"))
func wait_ready() -> bool:
	for i in 240:
		await frames(1)
		var timing = game.mobile_controls._hit_timing
		if timing.ready: return true
		if not game.ball.is_in_play: break
	return false
func run() -> void :
	create_timer(45).timeout.connect( func(): push_error("Hit timing live timeout");quit(2))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): captures = arg.trim_prefix("--capture-dir=")
	if not captures.is_empty(): DirAccess.make_dir_recursive_absolute(captures)
	root.size = Vector2i(720, 1280);root.content_scale_size = root.size
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await frames(4)
	Fixture.configure(game)
	var controls = game.mobile_controls
	controls._hit_timing = Timing.new(pulse)
	game.ball.hit_by_paddle.connect(record_hit)
	var settings = root.get_node("Settings")
	var prior_vibration: bool = settings.get_value("gameplay.timing_vibration")
	settings._config.set_value("gameplay", "timing_vibration", true)
	for resolution in [Vector2i(720, 1280), Vector2i(720, 1560), Vector2i(720, 1600), Vector2i(600, 960), Vector2i(1080, 2340)]:
		root.size = resolution;root.content_scale_size = resolution
		await process_frame; await process_frame
		controls._layout()
		var safe: Rect2 = Layout.safe_rect(root)
		var ring: = Rect2(controls._charge_center - Vector2.ONE * controls._timing_ring_max, Vector2.ONE * controls._timing_ring_max * 2)
		check(ring.size.x >= safe.size.x * 0.5 and ring.size.x <= safe.size.x * 0.58, "approach ring is not approximately half safe width at " + str(resolution))
		check(controls._timing_ring_max >= controls._charge_radius * 1.7, "ring is not visibly larger than Hit")

		var base_center: Vector2 = controls._charge_center
		var base_safe: Rect2 = controls._timing_safe
		for inset in [0.0, 22.0 * controls._s]:
			controls._charge_center = base_center - Vector2(inset, inset)
			controls._timing_safe = base_safe.grow( - inset)
			for radius in [controls._charge_radius, controls._charge_radius + 25.0 * controls._s, controls._timing_ring_max]:
				var angles: Vector2 = controls._timing_arc_angles(radius)
				var corner: Vector2 = controls._timing_corner_arc_angles(radius)
				check(angles.y - angles.x > PI, "safe clipping discarded readable majority of circle")
				for sample in 97:
					var point: Vector2 = controls._charge_center + Vector2.from_angle(lerpf(angles.x, angles.y, float(sample) / 96.0)) * radius
					check(controls._timing_safe.grow(0.1).has_point(point), "drawn ring arc enters unsafe inset at " + str(resolution))
					if corner.y > corner.x:
						var corner_point: Vector2 = controls._charge_center + Vector2.from_angle(lerpf(corner.x, corner.y, float(sample) / 96.0)) * radius
						check(controls._timing_safe.grow(0.1).has_point(corner_point), "corner arc enters unsafe inset")
		controls._charge_center = base_center
		controls._timing_safe = base_safe

		check(controls._timing_caption_center.distance_to(controls._charge_center) > controls._charge_radius * 1.5, "release caption is thumb-obscured")
		for caption_rect in controls._guide_caption_rects:
			check(safe.encloses(caption_rect), "timing-ring Y caption backing clipped at " + str(resolution))
	root.size = Vector2i(720, 1280);root.content_scale_size = root.size
	await process_frame; await process_frame
	prepare(); await frames(2);touch(true); await frames(2)
	check(Input.is_action_pressed("ui_accept") and controls._charge_owns_action, "real touch failed to own Hit")
	check( not controls._hit_timing.ready, "early held ball was prematurely green")
	await capture("incoming_large_ring")
	var reached: bool = await wait_ready()
	check(reached, "actual incoming feed never reached release window")
	if reached:
		var human = game.player_left.posture.human_contact
		var state: Dictionary = human.release_timing_state()
		check(state.release_ready and state.current_reachable and not state.preparation_only, "green did not come from legal current-root readiness")
		check(pulses == 1, "first real release window did not pulse exactly once")
		check(controls._timing_radius() == controls._charge_radius, "ready ring did not merge with Hit circumference")
		check(controls._hit_timing.flash_strength() > 0.0, "real touch readiness did not flash with pulse")
		await capture("release_ready")
		game.ball.is_in_play = false
		controls._update_hit_timing(false)
		check( not controls._hit_timing.active and not controls._hit_timing.ready and controls._hit_timing.caption == "NO CONTACT", "dead flight retained release UI")
		await capture("invalid_no_contact")
	touch(false, true); await frames(2)
	check( not Input.is_action_pressed("ui_accept") and not controls._hit_timing.ready, "canceled invalid flight retained charge/readiness")
	prepare(); await frames(2);touch(true); await frames(2)
	reached = await wait_ready()
	check(reached, "second real feed never reached release window")
	if reached:
		touch(false)
		check( not controls._hit_timing.ready and controls._hit_timing.flash_strength() == 0.0, "normal release retained green cue/flash")
		for i in 180:
			await frames(1)
			if game.ball.last_hit_by == 0: break
		check(actual_hits > 0, "green-window real touch release did not produce paddle contact")
		controls._update_hit_timing(false)
		check( not controls._hit_timing.active, "committed stroke revived approach ring")
	check(is_equal_approx(Engine.time_scale, 1.0), "mobile timing changed PvP clock")
	prepare(); await frames(2);touch(true); await frames(2)
	paused = true;controls._process(0.016)
	check( not Input.is_action_pressed("ui_accept") and not controls._hit_timing.active and not controls._hit_timing.ready, "pause left timing/charge live")
	paused = false
	prepare(); await frames(2);touch(true); await frames(2)
	controls._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check( not Input.is_action_pressed("ui_accept") and not controls._hit_timing.active, "background retained ring/charge")
	prepare(); await frames(2);touch(true); await frames(2)
	game._reset_ball()
	check( not controls._hit_timing.active and not controls._hit_timing.ready, "reset retained timing feedback")
	controls.cancel_all();settings._config.set_value("gameplay", "timing_vibration", prior_vibration)
	game.queue_free(); await process_frame; await process_frame
	var deadline: int = Time.get_ticks_usec() + 180000
	while Time.get_ticks_usec() < deadline: OS.delay_msec(5); await process_frame
	for failure in failures: push_error(failure)
	print("HIT TIMING LIVE: %d checks, %d failures; mocked pulses=%d, actual hits=%d" % [checks, failures.size(), pulses, actual_hits])
	quit(0 if failures.is_empty() else 1)
