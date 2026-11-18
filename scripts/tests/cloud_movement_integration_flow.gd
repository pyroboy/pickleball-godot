extends "res://scripts/tests/cloud_movement_integration.gd"
## Continuous real-physics capture. No standalone guide, frozen fixture, CUA, or
## supplied predictor cache. Capture scheduling is bounded, not an FPS benchmark.
var flow_done := false
var flow_frames: Array = []
var capture_start_usec := 0
var output := ""
var rendered := false
var requested_size := Vector2i(540, 960)

func _initialize() -> void:
	super._initialize()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--size="):
			var parts := argument.trim_prefix("--size=").split("x")
			requested_size = Vector2i(int(parts[0]), int(parts[1]))
	Engine.max_fps = rate
	# One physics step per recorded render avoids skipped trajectory samples
	# when software rendering and PNG encoding are slower than the target rate.
	Engine.max_physics_steps_per_frame = 1

func run() -> void:
	if not OS.get_user_data_dir().contains("movement-integration-"):
		push_error("Isolated HOME/XDG required"); quit(2); return
	create_timer(180.0, true).timeout.connect(func(): quit(2))
	settings = root.get_node("Settings")
	var pause = root.get_node("PauseController")
	pause.set_process_input(false)
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	root.content_scale_size = Vector2i(720, 1280); root.size = requested_size
	root.title = "Arjostyle continuous movement guidance QA"
	rendered = DisplayServer.get_name() != "headless"
	output = OS.get_environment("MOVEMENT_INTEGRATION_REPORT").get_base_dir()
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	await frames(5); await physics_frame
	Fixture.configure(game); guide = game.movement_guide
	current_case = "continuous_automatic_flow"
	check(count_guides(game) == 1, "continuous flow lacks exactly one automatic guide")
	check(guide.get_index() == game.player_left.get_index() + 1 and guide.process_physics_priority == game.player_left.process_physics_priority, "continuous flow changed actual integrated ordering")
	for phase in ["input", "before", "after"]:
		var node = Probe.new(); node.owner_test = self; node.phase = phase
		if phase == "input": node.process_physics_priority = -100; root.add_child(node)
		else:
			node.process_physics_priority = guide.process_physics_priority; node.process_priority = 101; game.add_child(node)
			game.move_child(node, guide.get_index() if phase == "before" else guide.get_index() + 1)
	capture_start_usec = Time.get_ticks_usec()
	call_deferred("start_flow")
	var last_tick := -1
	while not flow_done:
		if rendered: await RenderingServer.frame_post_draw
		else: await process_frame
		if sample_count == last_tick or not capturing and not flow_done: continue
		last_tick = sample_count
		capture_frame()
		check(flow_frames.size() <= int(rate * 4.0) + 2, "continuous capture exceeded bounded PNG count")
	if rendered: await RenderingServer.frame_post_draw
	else: await process_frame
	if flow_frames.is_empty() or flow_frames[-1].physics_tick != sample_count: capture_frame()
	var max_bounces := 0
	for row in live_trace: max_bounces = maxi(max_bounces, row.bounces)
	check(max_bounces == 2, "continuous flow did not include both real ground bounces")
	check(invalid_render_frames > 0, "continuous flow lacks terminal neutral render")
	check(flow_frames.size() >= int(rate * 3.0), "too few recorded samples for continuous trajectory review")
	var metadata := {"scope": "Archived build28 plus cloud A/B/C/D integration; not unavailable Mac build30/31", "rendered_images": rendered,
		"render_backend": DisplayServer.get_name(), "window_size": [root.size.x, root.size.y],
		"nominal_physics_hz": rate, "nominal_capture_hz": rate, "simulation_seconds": float(sample_count) / rate,
		"wall_seconds": float(Time.get_ticks_usec() - capture_start_usec) / 1000000.0,
		"capture_scheduler": "max_physics_steps_per_frame=1; bounded offline recording, not an FPS or device-performance benchmark",
		"automatic_guide": true, "ball_frozen": false, "supplied_flights": false, "max_bounces": max_bounces,
		"checks": checks, "failures": failures, "records": records, "trace": live_trace, "frames": flow_frames,
		"source_sha256": {"game.gd": FileAccess.get_sha256("res://scripts/game.gd"), "guide.gd": FileAccess.get_sha256("res://scripts/ui/incoming_movement_guide.gd"), "advisor.gd": FileAccess.get_sha256("res://scripts/movement_guidance_advisor.gd")}}
	FileAccess.open(OS.get_environment("MOVEMENT_INTEGRATION_REPORT"), FileAccess.WRITE).store_string(JSON.stringify(metadata, "\t"))
	game.queue_free(); current_scene = null; await frames(3)
	var until := Time.get_ticks_usec() + 180000
	while Time.get_ticks_usec() < until: OS.delay_msec(5); await process_frame
	for failure in failures: push_error(failure)
	print("CLOUD MOVEMENT CONTINUOUS FLOW: %d samples, %d checks, %d failures, rendered=%s" % [flow_frames.size(), checks, failures.size(), rendered])
	quit(0 if failures.is_empty() else 1)

func start_flow() -> void:
	await live_case(true, false, 3.4)
	flow_done = true

func probe(phase: String, delta: float) -> void:
	if capturing and phase == "input":
		var time := float(sample_count) / rate
		if time < 0.55: Input.action_press("move_right", 0.20)
		else: Input.action_release("move_right")
		if time >= 1.10 and time < 1.40: Input.action_press("move_left", 0.12)
		else: Input.action_release("move_left")
		game.aim_controller.update(delta, false, Vector2(0.2, -0.15), true)
		game.aim_controller.nudge(Vector2(0.2, -0.15), delta)
	super.probe(phase, delta)

func capture_frame() -> void:
	var state: Dictionary = guide.presentation_state()
	var filename := "flow-%04d.png" % flow_frames.size()
	if rendered:
		var image := root.get_texture().get_image()
		check(image.get_size() == requested_size, "rendered capture size differs from request")
		check(image.save_png(output.path_join(filename)) == OK, "PNG save failed: " + filename)
	flow_frames.append({"index": flow_frames.size(), "image": filename if rendered else "", "physics_tick": sample_count,
		"nominal_seconds": float(flow_frames.size()) / rate, "simulation_seconds": float(sample_count) / rate,
		"wall_seconds": float(Time.get_ticks_usec() - capture_start_usec) / 1000000.0,
		"ball_position": xyz(game.ball.global_position), "ball_velocity": xyz(game.ball.linear_velocity), "bounces": game.ball.bounces_since_last_hit,
		"player_position": xyz(game.player_left.global_position), "player_velocity": xyz(game.player_left.current_velocity), "aim_target": xyz(game.aim_controller.target),
		"flight_id": game.ball.flight_id, "in_play": game.ball.is_in_play, "game_state": game.game_state,
		"eligible": guide._eligible(), "visible": not state.is_empty(), "status": state.get("status", "NEUTRAL"),
		"target_root": xyz(guide._advice.target_root) if guide._advice.has("target_root") else null,
		"target_screen": [state.center.x, state.center.y] if state.has("center") else null,
		"label_rect": str(state.get("label_rect", Rect2())), "advice_reason": guide._advice.get("reason", ""),
		"statistics": guide.advisor.statistics.duplicate(true)})
