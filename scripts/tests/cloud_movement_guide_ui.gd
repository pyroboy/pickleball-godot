extends SceneTree
const Guide = preload("res://scripts/ui/incoming_movement_guide.gd")
const Feeds = preload("res://tools/cloud_qa/movement_guide_fixtures.gd")
const Fixture = preload("res://scripts/tests/fixtures/charged_footwork_fixture.gd")
var game
var guide
var rate := 60
var checks := 0
var failures: Array[String] = []
var records: Array = []
var current_case := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--rate="): rate = int(argument.trim_prefix("--rate="))
	Engine.physics_ticks_per_second = rate
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(current_case + ": " + label)

func prepare(status := "MOVE", mirrored := false) -> Dictionary:
	guide.player = Feeds.prepare(game, status, mirrored)
	guide.advisor = Guide.Advisor.new()
	guide._reset_generation = game._point_reset_generation
	guide.cancel()
	guide.tick(0.0, Feeds.flight(game))
	return guide.presentation_state()

func run() -> void:
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	Fixture.configure(game)
	Feeds.detach_automatic(game)
	game.process_mode = Node.PROCESS_MODE_DISABLED
	guide = Guide.new()
	game.add_child(guide)
	guide.setup(game)
	guide.set_process(false); guide.set_physics_process(false)
	current_case = "layer_input_contract"
	check(guide.layer == 0 and game.aim_focus.layer < guide.layer and game.hud.layer > guide.layer, "guide not between focus and HUD")
	check(guide.process_mode == Node.PROCESS_MODE_ALWAYS and guide.process_physics_priority > game.player_left.process_physics_priority, "pause or predictor ordering wrong")
	check(guide._drawing.mouse_filter == Control.MOUSE_FILTER_IGNORE and guide._drawing.focus_mode == Control.FOCUS_NONE, "guide captures pointer or keyboard focus")
	check(not guide.is_processing_input() and not guide.is_processing_unhandled_input(), "guide owns an input callback")
	for status in ["MOVE", "TIGHT", "NO_TIME"]:
		for mirrored in [false, true]:
			current_case = "%s_%s" % [status, "far" if mirrored else "near"]
			var state := prepare(status, mirrored)
			check(not state.is_empty(), "legal advice not rendered")
			if state.is_empty():
				records.append({"case": current_case, "advice": guide._advice, "camera": game.camera_rig.camera.global_transform, "eligible":guide._eligible()})
				continue
			check(state.status == status, "status changed from advisor: " + str(state.status))
			check(state.label == ("NO TIME" if status == "NO_TIME" else status), "missing unambiguous text label")
			check(state.target_world.x == guide._advice.target_root.x and state.target_world.z == guide._advice.target_root.z, "marker drifted off verified root")
			check(is_equal_approx(state.target_world.y, PickleballConstants.FLOOR_Y + Guide.FLOOR_LIFT), "marker floating at player root height")
			check(state.band.encloses(state.label_rect), "caption outside safe court band")
			check(not Guide._overlaps_any(state.label_rect, state.exclusions), "caption covers gameplay controls")
			var first_center: Vector2 = state.center
			var gameplay_before := gameplay_fingerprint()
			for frame in range(rate):
				guide._reproject()
				var stable: Dictionary = guide.presentation_state()
				check(not stable.is_empty() and stable.center == first_center and stable.status == status, "static rendering flickers or drifts")
			check(guide.advisor.statistics.solves == 1 and guide.advisor.statistics.traces == 0, "render frames duplicate solver or predictor")
			check(gameplay_fingerprint() == gameplay_before, "presentation changed input, motion, charge, aim or contact")
			records.append({"case": current_case, "state": state, "advice": guide._advice})
	cadence_case()
	visibility_cases()
	camera_cases()
	edge_direction_cases()
	sizing_cases()
	control_exclusion_cases()
	await viewport_cases()
	await passthrough_case()
	current_case = "cancel_and_reset"
	prepare()
	guide.cancel()
	check(guide.presentation_state().is_empty() and guide._advice.is_empty() and not guide._drawing.visible, "cancel retained positive guidance")
	for frame in range(rate):
		guide._process(1.0 / rate)
		check(guide.presentation_state().is_empty(), "cancel restored cached target without a new solver update")
	prepare()
	game._point_reset_generation += 1
	guide._process(0.0)
	check(guide.presentation_state().is_empty() and guide._advice.is_empty(), "reset generation retained stale target")
	var report := {"rate": rate, "checks": checks, "failures": failures, "cases": records,
		"scope": "Archived 0.3.25/build28 standalone presentation candidate; not newer Mac build30/31 acceptance"}
	var destination := OS.get_environment("MOVEMENT_GUIDE_UI_REPORT")
	if destination.is_empty(): destination = "/tmp/movement-guide-ui-%d.json" % rate
	FileAccess.open(destination, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	for failure in failures: push_error(failure)
	print("CLOUD MOVEMENT GUIDE UI %d Hz: %d checks, %d failures" % [rate, checks, failures.size()])
	game.queue_free(); await process_frame; await process_frame
	var until := Time.get_ticks_usec() + 150000
	while Time.get_ticks_usec() < until: OS.delay_msec(5); await process_frame
	quit(0 if failures.is_empty() else 1)

func visibility_cases() -> void:
	for gate in ["pause", "guide", "menu", "tool", "preview", "match", "waiting", "outgoing", "dead", "second_bounce", "jump", "wall", "disabled", "setting", "unknown", "unproven", "expired", "flight_changed"]:
		current_case = "hide_" + gate
		prepare()
		match gate:
			"pause": paused = true
			"guide": game.hud._guide.show()
			"menu": game.hud._gameplay_visible = false
			"tool":
				game.mobile_pose_editor = Node.new()
				game.add_child(game.mobile_pose_editor)
			"preview": game.player_left.posture.editor_preview_mode = true
			"match": game.match_over = true
			"waiting": game.game_state = game.GameState.WAITING
			"outgoing": game.ball.last_hit_by = 0
			"dead": game.ball.is_in_play = false
			"second_bounce": game.ball.bounces_since_last_hit = 2
			"jump": game.player_left.is_jumping = true
			"wall": game.ball.wall_practice_active = true; game.ball.wall_return_ready = false
			"disabled": guide.enabled = false
			"setting": root.get_node("Settings")._config.set_value("gameplay", "movement_guide", false)
			"unknown": guide._advice = {"visible": false, "status": "UNKNOWN"}
			"unproven": guide._advice.status = "NO_TIME"; guide._advice.no_time_proven = false
			"expired": guide._advice.remaining_time = 0.0
			"flight_changed": game.ball.flight_id += 1
		guide._process(0.0)
		check(guide.presentation_state().is_empty() and not guide._drawing.visible, "invalid guide not cleared in same render frame")
		paused = false
		game.hud._guide.hide(); game.hud._gameplay_visible = true
		if game.mobile_pose_editor != null:
			game.mobile_pose_editor.free(); game.mobile_pose_editor = null
		game.player_left.posture.editor_preview_mode = false
		game.match_over = false; game.player_left.is_jumping = false; game.ball.wall_practice_active = false
		guide.enabled = true
		if root.get_node("Settings")._config.has_section_key("gameplay", "movement_guide"):
			root.get_node("Settings")._config.erase_section_key("gameplay", "movement_guide")
	current_case = "already_reachable"
	Fixture.prepare(game, {"name": "standing", "root_z": 4.7, "lateral": 0.42, "height": 1.08, "forward": 0.46, "duration": 1.65, "family": 0})
	game.ball.freeze = true
	guide.advisor = Guide.Advisor.new(); guide._reset_generation = game._point_reset_generation
	guide.tick(0.0, Feeds.flight(game))
	check(guide.presentation_state().is_empty(), "standing legal reach asks for unnecessary movement")

func camera_cases() -> void:
	current_case = "camera_safety"
	prepare()
	var camera: Camera3D = root.get_camera_3d()
	var saved: Transform3D = camera.global_transform
	camera.rotate_y(PI)
	guide._process(0.0)
	check(guide.presentation_state().is_empty(), "behind-camera target projected onto screen")
	camera.global_transform = saved
	prepare()
	camera.clear_current(false)
	guide._process(0.0)
	check(guide.presentation_state().is_empty(), "invalid camera retained marker")
	camera.make_current()
	prepare()
	var target: Vector3 = guide._advice.target_root
	var before: Vector2 = guide.presentation_state().center
	camera.global_position.x += 0.2
	guide._process(0.0)
	var projected: Dictionary = guide.presentation_state()
	check(not projected.is_empty() and projected.center != before, "camera move did not reproject")
	check(guide._advice.target_root == target, "camera moved advisor world target")
	camera.global_transform = saved
	var edge := Guide._edge_point(Vector2(50,50), Vector2(200,25), Rect2(10,10,80,80))
	check(edge.x == 90 and edge.y >= 10 and edge.y <= 90, "offscreen edge ray is unstable")

func sizing_cases() -> void:
	current_case = "mobile_sizing"
	for size in [Vector2(390,844), Vector2(430,932), Vector2(540,960), Vector2(960,540), Vector2(720,1280)]:
		var metrics := Guide.visual_metrics(size)
		check(metrics.stroke >= 1.6 and metrics.font_size >= 12 and metrics.min_radius >= 8, "subpixel guide on " + str(size))
		var safe := Rect2(Vector2(4,24), size - Vector2(8,44))
		var band := Guide.court_band(size, safe)
		check(safe.encloses(band) and band.size.x > 0 and band.size.y > 0, "unsafe court band on " + str(size))
	var stretched := Guide.visual_metrics(Vector2(720,1558), 390.0 / 720.0)
	check(stretched.stroke * 390.0 / 720.0 >= 1.6 and stretched.font_size * 390.0 / 720.0 >= 12, "stretched mobile presentation too small")

func passthrough_case() -> void:
	current_case = "pointer_passthrough"
	prepare()
	# Isolated viewport verifies the actual Control path without gameplay's
	# mobile gesture layer consuming this synthetic click first.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(300,300)
	root.add_child(viewport)
	var button := Button.new()
	button.position = Vector2(100,100); button.size = Vector2(100,60)
	viewport.add_child(button)
	var overlay := Guide.GuideDrawing.new()
	overlay.mouse_filter = guide._drawing.mouse_filter
	overlay.focus_mode = guide._drawing.focus_mode
	overlay.size = Vector2(300,300)
	viewport.add_child(overlay)
	var count := [0]
	button.pressed.connect(func(): count[0] += 1)
	await process_frame
	var event := InputEventMouseButton.new()
	event.position = Vector2(150,130); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true
	viewport.push_input(event, true)
	event = event.duplicate(); event.pressed = false
	viewport.push_input(event, true)
	check(count[0] == 1, "ignore overlay intercepted underlying button")
	viewport.queue_free()
	await process_frame

func gameplay_fingerprint() -> String:
	var player = guide.player
	var human = player.posture.human_contact
	return str([player.global_transform, player.velocity, player.current_velocity,
		player.stamina.value, human.phase if human != null else -999,
		human.contact if human != null else {}, human.footwork.active if human != null else false,
		game.aim_controller.mode, game.aim_controller.planted, game.serve_charge_time,
		game.ball.global_transform, game.ball.linear_velocity, game.ball.angular_velocity,
		Input.is_action_pressed("ui_accept"), Input.get_vector("move_left", "move_right", "move_up", "move_down")])

func cadence_case() -> void:
	current_case = "physics_cache_cadence"
	prepare()
	for frame in range(rate):
		var previous_flight := Feeds.flight(game)
		var next: Dictionary = previous_flight.samples[1]
		game.ball.global_position = next.pos
		game.ball.linear_velocity = next.vel
		game.ball.angular_velocity = next.omega
		game.ball.bounces_since_last_hit += int(next.bounces)
		# Gameplay/predictor advance precedes the guide's later-priority tick.
		guide.player.debug_visual._last_flight = Feeds.flight(game)
		var before := gameplay_fingerprint()
		guide._physics_process(1.0 / rate)
		check(not guide.presentation_state().is_empty(), "passive physics lost advancing incoming guidance")
		check(gameplay_fingerprint() == before, "passive physics changed gameplay or input")
	check(guide.advisor.statistics.solves <= 11, "passive UI exceeded 10 Hz solver ceiling")
	check(guide.advisor.statistics.traces == 0, "passive UI duplicated normal predictor cache")

func control_exclusion_cases() -> void:
	current_case = "visible_control_regions"
	prepare()
	var controls = game.mobile_controls
	controls.enabled = true; controls.visible = true
	var saved_cancel: Vector2 = controls._cancel_center
	var saved_caption: Rect2 = controls._timing_caption_rect
	var saved_charge: int = controls._charge_id
	var saved_timing: String = controls._hit_timing.caption
	controls._cancel_center = Vector2(-500, -500)
	controls._timing_caption_rect = Rect2(-900, -900, 120, 40)
	controls._charge_id = -1
	controls._hit_timing.caption = ""
	var hidden: Array[Rect2] = guide._control_exclusions(8.0)
	check(not Guide._overlaps_any(Rect2(-502,-502,4,4), hidden), "hidden CANCEL still blocks guide")
	check(not Guide._overlaps_any(controls._timing_caption_rect, hidden), "hidden timing caption still blocks guide")
	controls._charge_id = 5; controls._hit_timing.caption = "HOLD HIT"
	var shown: Array[Rect2] = guide._control_exclusions(8.0)
	check(Guide._overlaps_any(Rect2(-502,-502,4,4), shown), "visible CANCEL unprotected")
	check(Guide._overlaps_any(controls._timing_caption_rect, shown), "visible timing caption unprotected")
	controls._cancel_center = saved_cancel; controls._timing_caption_rect = saved_caption
	controls._charge_id = saved_charge; controls._hit_timing.caption = saved_timing
	controls._layout()
	# Short portrait layouts previously hid near-side labels by stopping after
	# the first candidate. Verify a genuine alternate position at nearby sizes.
	for viewport_height in [1250.0, 1280.0, 1320.0]:
		var size := Vector2(720, viewport_height)
		var band := Guide.court_band(size, Rect2(Vector2.ZERO, size))
		var center := Vector2(456, viewport_height - 470)
		var first_caption := Rect2(center + Vector2(-55,24), Vector2(110,44))
		var exclusions: Array[Rect2] = [first_caption.grow(2)]
		var label: Rect2 = guide._place_label(center, Vector2(18,12), Vector2(110,44), band, Vector2.INF, Guide.visual_metrics(size,0.75), exclusions)
		check(label.size != Vector2.ZERO and not label.intersects(first_caption), "alternate label not found at " + str(viewport_height))
		check(band.encloses(label), "alternate label left court band")

func viewport_cases() -> void:
	current_case = "short_portrait_regression"
	var saved_size: Vector2i = root.size
	var saved_scale: Vector2i = root.content_scale_size
	for size in [Vector2i(528,940), Vector2i(540,960), Vector2i(552,980)]:
		root.size = size
		root.content_scale_size = Vector2i(720,1280)
		await process_frame
		game.mobile_controls._layout()
		game.camera_rig.update(0.0)
		for status in ["MOVE", "TIGHT", "NO_TIME"]:
			var state := prepare(status)
			check(not state.is_empty(), "%s missing at %s" % [status, size])
			if not state.is_empty(): check(not Guide._overlaps_any(state.label_rect, state.exclusions), "visible label covers controls")
	root.size = saved_size; root.content_scale_size = saved_scale
	await process_frame
	game.mobile_controls._layout()

func edge_direction_cases() -> void:
	current_case = "same_offscreen_edge_direction"
	var camera: Camera3D = root.get_camera_3d()
	var saved: Transform3D = camera.global_transform
	for offset in [-22.0, 22.0]:
		camera.global_transform = saved
		prepare()
		camera.global_position.x += offset
		guide._reproject()
		var state: Dictionary = guide.presentation_state()
		check(not state.is_empty() and state.edge, "same-edge offscreen cue missing")
		if state.is_empty(): continue
		var root_floor := Vector3(guide.player.global_position.x, PickleballConstants.FLOOR_Y + Guide.FLOOR_LIFT, guide.player.global_position.z)
		var player_screen := camera.unproject_position(root_floor)
		var target_screen: Vector2 = state.center
		var both_right: bool = player_screen.x > state.band.end.x and target_screen.x > state.band.end.x
		var both_left: bool = player_screen.x < state.band.position.x and target_screen.x < state.band.position.x
		check(both_right or both_left, "fixture does not place both points past the same edge")
		var expected := (target_screen - player_screen).normalized()
		var wings: PackedVector2Array = state.wings
		var displayed := (wings[1] - (wings[0] + wings[2]) * 0.5).normalized()
		check(displayed.dot(expected) > 0.999, "edge clipping reversed movement direction")
		check(state.ring.is_empty(), "offscreen edge cue pretends to be an exact floor marker")
	camera.global_transform = saved
