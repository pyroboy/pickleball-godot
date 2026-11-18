extends "res://scripts/tests/cloud_movement_integration.gd"
## Final-render orientation/camera QA of the automatic production guide.
var scenario := "orientation"
var finished := false
var auditing := false
var event_keys: Dictionary = {}
var render_records: Array = []
var last_record_tick := -1
var max_projection_error := 0.0
var visible_frames := 0
var edge_frames := 0
var legitimate_hidden_frames := 0
var projection_mismatches := 0
var mode_changes := 0
var capture := false
var geometry_only := false
var capture_directory := ""
var wall_start_usec := 0
var late_guide_render := false
var audit_node

class RenderAudit extends Node:
	var test
	func _process(_delta: float) -> void: test.audit_frame()

func _initialize() -> void:
	super._initialize()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scenario="): scenario = argument.trim_prefix("--scenario=")
		if argument == "--capture": capture = true
		if argument == "--geometry-only": geometry_only = true
		if argument == "--late-guide-render": late_guide_render = true
	if capture:
		Engine.max_fps = rate
		Engine.max_physics_steps_per_frame = 1

func run() -> void:
	if not OS.get_user_data_dir().contains("movement-rotation-"):
		push_error("Isolated movement-rotation HOME/XDG required"); quit(2); return
	create_timer(120.0, true).timeout.connect(func(): quit(2))
	settings = root.get_node("Settings")
	var pause = root.get_node("PauseController")
	pause.set_process_input(false)
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	root.content_scale_size = Vector2i(720, 1280); root.size = Vector2i(390, 844)
	root.title = "Arjostyle dynamic movement orientation QA"
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	await frames(5); await physics_frame
	Fixture.configure(game); guide = game.movement_guide
	if late_guide_render: guide.process_priority = game.camera_rig.process_priority + 1
	check(count_guides(game) == 1, "not exactly one automatic guide")
	check(guide._drawing.mouse_filter == Control.MOUSE_FILTER_IGNORE and guide._drawing.focus_mode == Control.FOCUS_NONE, "guide captures pointer or focus")
	check(not guide.is_processing_input() and not guide.is_processing_unhandled_input(), "guide owns input callbacks")
	for phase in ["input", "before", "after"]:
		var node = Probe.new(); node.owner_test = self; node.phase = phase
		if phase == "input": node.process_physics_priority = -100; root.add_child(node)
		else:
			node.process_physics_priority = guide.process_physics_priority; node.process_priority = maxi(guide.process_priority, game.camera_rig.process_priority) + 1; game.add_child(node)
			game.move_child(node, guide.get_index() if phase == "before" else guide.get_index() + 1)
	audit_node = RenderAudit.new(); audit_node.test = self; audit_node.process_priority = 2001; audit_node.process_mode = Node.PROCESS_MODE_ALWAYS; root.add_child(audit_node)
	current_case = "rotation_" + scenario
	if scenario == "interruptions":
		auditing = true
		await interruption_cases()
		auditing = false
	else:
		auditing = true; wall_start_usec = Time.get_ticks_usec()
		capture_directory = OS.get_environment("MOVEMENT_INTEGRATION_REPORT").get_base_dir()
		call_deferred("start_timeline")
		while not finished:
			if capture and not geometry_only:
				await RenderingServer.frame_post_draw
				if not render_records.is_empty() and render_records[-1].get("image", "").is_empty():
					var name := "rotation-%s-%04d.png" % [scenario, render_records.size() - 1]
					check(root.get_texture().get_image().save_png(capture_directory.path_join(name)) == OK, "failed native PNG")
					render_records[-1].image = name
			else: await process_frame
		auditing = false
		check(visible_frames > 0, "timeline never displayed guidance")
		check(event_keys.has("landscape") and event_keys.has("portrait_return"), "timeline missed required rotations")
	check(projection_mismatches == 0, "guide did not match final-render camera: %d frames, max %.3f px" % [projection_mismatches, max_projection_error])
	var report := {"scope": "Frozen portable cloud checkpoint C based on archived build28, not newer Mac builds30/31", "scenario": scenario, "rate": rate,
		"checks": checks, "failures": failures, "events": event_keys, "records": records, "frames": render_records,
		"visible_frames": visible_frames, "edge_frames": edge_frames, "eligible_hidden_frames": legitimate_hidden_frames,
		"max_projection_error_pixels": max_projection_error, "projection_mismatch_frames": projection_mismatches,
		"camera_process_priority": game.camera_rig.process_priority, "guide_process_priority": guide.process_priority,
		"capture": capture, "late_guide_render_candidate": late_guide_render, "rendered_images": capture and not geometry_only,
		"capture_note": "Nominal sample cadence is offline recording configuration, not measured device FPS. Eligible-hidden frames are not classified as flicker; projection-gate diagnosis belongs to separate soak QA."}
	FileAccess.open(OS.get_environment("MOVEMENT_INTEGRATION_REPORT"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	audit_node.queue_free(); game.queue_free(); current_scene = null; await frames(3)
	var until := Time.get_ticks_usec() + 180000
	while Time.get_ticks_usec() < until: OS.delay_msec(5); await process_frame
	for failure in failures: push_error(failure)
	print("MOVEMENT ROTATION %s %d Hz: %d checks, %d failures; max final projection error %.3f px" % [scenario, rate, checks, failures.size(), max_projection_error])
	quit(0 if failures.is_empty() else 1)

func start_timeline() -> void:
	await live_case(true, false, 3.4)
	finished = true

func once(key: String, time: float) -> bool:
	if event_keys.has(key): return false
	event_keys[key] = {"physics_tick": sample_count, "simulation_seconds": time}
	return true

func probe(phase: String, delta: float) -> void:
	if capturing and phase == "input":
		var time := float(sample_count) / rate
		if time < 0.45: Input.action_press("move_right", 0.15)
		else: Input.action_release("move_right")
		game.aim_controller.update(delta, false, Vector2(0.1, -0.1), true)
		game.aim_controller.nudge(Vector2(0.1, -0.1), delta)
		if time >= 0.5 and once("landscape", time): root.size = Vector2i(960, 540)
		if time >= 1.4 and once("portrait_return", time): root.size = Vector2i(430, 932)
		if scenario == "camera":
			if time >= 0.3 and once("third_person", time): game.camera_rig.set_gameplay_camera_mode(1)
			if time >= 1.1 and once("pov", time): game.camera_rig.set_gameplay_camera_mode(2)
			if time >= 2.1 and once("center", time): game.camera_rig.set_gameplay_camera_mode(0)
	super.probe(phase, delta)

func audit_frame() -> void:
	if not auditing or not is_instance_valid(guide): return
	var snapshot := fingerprint()
	var state: Dictionary = guide.presentation_state()
	var eligible: bool = guide._eligible()
	if not eligible:
		check(state.is_empty() and guide._advice.is_empty(), "stale or resurrected guide on ineligible final render")
	elif state.is_empty():
		legitimate_hidden_frames += 1 # Do not infer flicker from eligibility alone.
	var error := 0.0
	if not state.is_empty():
		visible_frames += 1
		var camera: Camera3D = game.camera_rig.camera
		var target: Vector3 = guide._advice.target_root
		var world := Vector3(target.x, PickleballConstants.FLOOR_Y + Guide.FLOOR_LIFT, target.z)
		check(state.target_world.is_equal_approx(world), "marker changed verified world root")
		check(guide._advice.flight_id == game.ball.flight_id, "marker retained old flight")
		if camera.is_position_behind(world):
			projection_mismatches += 1
		else:
			var projected := camera.unproject_position(world)
			error = projected.distance_to(state.center)
			max_projection_error = maxf(max_projection_error, error)
			if error > 0.05: projection_mismatches += 1
		var size := root.get_visible_rect().size
		var current_band := Guide.court_band(size, Guide.Layout.safe_rect(root))
		check(state.band.is_equal_approx(current_band), "guide retained pre-rotation court band")
		check(current_band.grow(0.5).encloses(state.label_rect), "label leaves current safe band")
		check(not Guide._overlaps_any(state.label_rect, state.exclusions), "label covers active input controls")
		if state.edge:
			edge_frames += 1
			check(state.ring.is_empty(), "offscreen edge cue pretends to be a floor ring")
			var floor_root := Vector3(game.player_left.global_position.x, world.y, game.player_left.global_position.z)
			if not camera.is_position_behind(world) and not camera.is_position_behind(floor_root):
				var intended := (camera.unproject_position(world) - camera.unproject_position(floor_root)).normalized()
				var drawn: Vector2 = (state.arrow[1] - state.arrow[0]).normalized()
				if drawn.length_squared() > 0.01:
					check(drawn.dot(intended) > 0.999, "clipped cue reverses or distorts final camera direction")
		# Reprojecting the same geometry must be idempotent and read-only.
		# Skip known final-camera disagreement: do not overwrite its evidence.
		if error <= 0.05:
			var held: Dictionary = state.duplicate(true)
			guide._reproject(); guide._reproject()
			check(guide.presentation_state() == held, "unchanged geometry flickers or changes label/target")
	check(fingerprint() == snapshot, "presentation audit/reprojection changed gameplay or input")
	if last_record_tick != sample_count or not capturing:
		last_record_tick = sample_count
		render_records.append({"physics_tick": sample_count, "simulation_seconds": float(sample_count) / rate,
			"wall_seconds": float(Time.get_ticks_usec() - wall_start_usec) / 1000000.0 if wall_start_usec > 0 else 0.0,
			"window_size": [root.size.x, root.size.y], "viewport": str(root.get_visible_rect()),
			"camera_mode": game.camera_rig.gameplay_camera.mode, "camera_transform": str(game.camera_rig.camera.global_transform),
			"visible": not state.is_empty(), "eligible": eligible, "status": state.get("status", "NEUTRAL"), "edge": state.get("edge", false),
			"projection_error_pixels": error, "target_world": xyz(state.target_world) if state.has("target_world") else null,
			"target_screen": [state.center.x, state.center.y] if state.has("center") else null,
			"ball": xyz(game.ball.global_position), "player": xyz(game.player_left.global_position), "aim": xyz(game.aim_controller.target),
			"flight": game.ball.flight_id, "bounces": game.ball.bounces_since_last_hit,
			"advice_visible": guide._advice.get("visible", false), "advice_reason": guide._advice.get("reason", ""),
			"advice": metadata_value(guide._advice), "presentation": metadata_value(state),
			"statistics": guide.advisor.statistics.duplicate(true)})

func metadata_value(value: Variant) -> Variant:
	# Numeric JSON geometry for paired edge-readability replay. Observation only.
	if value is Vector2 or value is Vector2i: return [value.x, value.y]
	if value is Vector3 or value is Vector3i: return [value.x, value.y, value.z]
	if value is Rect2 or value is Rect2i: return {"position": metadata_value(value.position), "size": metadata_value(value.size)}
	if value is Color: return [value.r, value.g, value.b, value.a]
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[str(key)] = metadata_value(value[key])
		return result
	if value is Array or value is PackedVector2Array or value is PackedVector3Array:
		var result: Array = []
		for item in value: result.append(metadata_value(item))
		return result
	return value

func interruption_cases() -> void:
	await native_interruptions()
	for index in 24:
		root.size = Vector2i(960, 540) if index % 3 == 0 else Vector2i(430, 932)
		settings.set_value("gameplay.movement_guide", index % 2 == 0)
		await process_frame
		if index % 2 == 1:
			check(guide.presentation_state().is_empty() and guide._advice.is_empty(), "rapid off-toggle resurrected guidance")
	settings.set_value("gameplay.movement_guide", false)
	game._reset_ball()
	for frame in 6:
		await process_frame
		check(guide.presentation_state().is_empty(), "reset plus setting off resurrected guidance")

	settings.set_value("gameplay.movement_guide", true)
	root.size = Vector2i(390, 844)
	Fixture.prepare(game, Fixture.cases()[1]); game.ball.freeze = false
	game.hud.set_gameplay_elements_visible(true); game.hud._guide.hide(); game.hud._between_point_active = false
	guide.advisor = Advisor.new(); guide._reset_generation = game._point_reset_generation
	for tick in 8: await physics_frame
	await process_frame
	check(not guide.presentation_state().is_empty(), "input-passthrough fixture had no automatic guide")
	var hit: Vector2 = game.mobile_controls._charge_center
	for input_kind in ["mouse", "touch"]:
		for down in [true, false]:
			var event: InputEvent
			if input_kind == "mouse":
				var mouse := InputEventMouseButton.new(); mouse.position = hit; mouse.global_position = hit; mouse.button_index = MOUSE_BUTTON_LEFT; mouse.pressed = down; event = mouse
			else:
				var touch := InputEventScreenTouch.new(); touch.position = hit; touch.index = 5; touch.pressed = down; event = touch
			root.push_input(event, true)
			await process_frame
			check(Input.is_action_pressed("ui_accept") == down, "automatic guide intercepted " + input_kind + " HIT or release")
	game.input_handler.cancel_charge_input()
	Input.action_release("ui_accept")
