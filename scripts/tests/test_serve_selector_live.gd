extends SceneTree

var checks: = 0
var failures: Array[String] = []
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(message)
func touch(id: int, point: Vector2, pressed: bool) -> void :
	var event: = InputEventScreenTouch.new()
	event.index = id;event.position = point;event.pressed = pressed
	root.push_input(event, true)
func drag(id: int, point: Vector2) -> void :
	var event: = InputEventScreenDrag.new()
	event.index = id;event.position = point
	root.push_input(event, true)
func run() -> void :
	create_timer(70).timeout.connect( func(): push_error("Serve selector test timed out");quit(2))
	root.content_scale_size = Vector2i(720, 1560);root.size = Vector2i(720, 1560)
	for style in range(7):
		var game = load("res://scenes/game.tscn").instantiate()
		root.add_child(game);current_scene = game
		await process_frame; await physics_frame; await physics_frame
		if game.get("mobile_controls") == null:
			push_error("Game setup failed before UI integration test")
			quit(1);return
		game.input_handler.set_process(false)
		var ui = game.mobile_controls
		var server = game.game_serve
		var options: Array = server.get_serve_style_options()
		check(options.size() == 7, "all implemented serve presets must appear")
		check(ui._show_serve_selector(), "pre-serve wheel hidden for style%d" % style)
		var wheel: Vector2 = ui._serve_selector_center
		var radius: float = ui._serve_selector_radius * 0.9
		touch(10, wheel + Vector2.RIGHT * radius, true)
		touch(11, ui._charge_center, true)
		game.input_handler._process(1.0 / 60.0)
		check(Input.is_action_pressed("ui_accept") and ui._gesture_is_serve, "wheel/HIT ownership collided")
		for tick in range(1, style + 1):
			drag(10, wheel + Vector2.from_angle(TAU * tick / options.size()) * radius)
			game.input_handler._process(1.0 / 60.0)
			await physics_frame
		check(server.selected_serve_style == style, "rotation chose wrong serve%d" % style)
		touch(12, ui._stick_center, true)
		drag(12, ui._stick_center + Vector2(0.4, 0) * ui._stick_radius)
		for frame in range(10):
			game.input_handler._process(1.0 / 60.0)
			await physics_frame
		var target: Vector3 = game.aim_controller.get_target()
		touch(12, ui._stick_center, false)
		touch(10, wheel, false)
		check(Input.is_action_pressed("ui_accept"), "wheel release stole held charge")
		touch(11, ui._charge_center, false)
		game.input_handler._process(0)
		var state: Dictionary = server.get_serve_timing_state()
		check(state.locked and int(state.style) == style, "released serve type not frozen%d" % style)
		check( not ui._show_serve_selector(), "rotary selector remained active aftercommit")
		check( not server._pending_release.is_empty(), "real serve release missing style%d" % style)
		if not server._pending_release.is_empty():
			check(server._pending_release.target.distance_to(target) < 0.0001, "aimtarget changed atrelease")
			var frozen: Dictionary = server._pending_release.duplicate(true)
			check( not server.select_serve_style((style + 1) % 7), "committed style accepted a replacement")
			check(server._pending_release.style == frozen.style and server._pending_release.target == frozen.target, "committed snapshot mutated")
		var phases: Array[String] = []
		var contact: = false
		for frame in range(150):
			await physics_frame
			state = server.get_serve_timing_state()
			var phase: String = state.phase
			if not phases.has(phase): phases.append(phase)
			check(float(state.progress) >= 0 and float(state.progress) <= 1, "timing progress outsidebounds")
			if phase == "CONTACT":
				contact = true
				check(game.ball.is_in_play and game.ball.last_hit_by == 0, "contact ring preceded actual hit")
				break
			if phase == "HELD" and frame > 3: break
		check(contact, "no real serve contact style%d phases%s" % [style, phases])
		if style in [2, 4, 5, 6]: check(phases.has("DROP") and (phases.has("BOUNCE") or phases.has("SWING")), "drop delivery did notshowfall/bounce path")
		ui._process(0)
		check(contact and ui._serve_contact_flash > 0, "actual contact did notreach HIT circle")
		print("LIVE WHEEL style%d phases%s contact%s" % [style, phases, contact])
		ui.cancel_all()
		game.queue_free(); await process_frame; await process_frame
	for failure in failures: push_error(failure)
	print("LIVE SERVE SELECTOR: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
