extends SceneTree
## Integration acceptance on archived build28 plus cloud candidates.
## Owns only probes: the game's automatic guide remains attached throughout.
const Guide = preload("res://scripts/ui/incoming_movement_guide.gd")
const Advisor = preload("res://scripts/movement_guidance_advisor.gd")
const Feeds = preload("res://tools/cloud_qa/movement_guide_fixtures.gd")
const Fixture = preload("res://scripts/tests/fixtures/charged_footwork_fixture.gd")
const Planner = preload("res://scripts/incoming_contact_planner.gd")
const Finite = preload("res://scripts/finite_paddle_contact.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
var game
var guide
var settings
var rate := 60
var mode := "integration"
var candidate_order := false
var checks := 0
var failures: Array[String] = []
var records: Array = []
var current_case := ""
var capturing := false
var sample_count := 0
var sample_limit := 0
var before: Array = []
var live_fresh := 0
var live_visible := 0
var live_status: Dictionary = {}
var live_trace: Array = []
var invalid_render_frames := 0
var input_probe
var before_probe
var after_probe
signal samples_done

class Probe extends Node:
	var owner_test
	var phase: String
	func _physics_process(delta: float) -> void:
		owner_test.probe(phase, delta)
	func _process(_delta: float) -> void:
		if phase == "after": owner_test.render_probe()

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--rate="): rate = int(argument.trim_prefix("--rate="))
		if argument.begins_with("--mode="): mode = argument.trim_prefix("--mode=")
	candidate_order = OS.get_cmdline_user_args().has("--candidate-order")
	Engine.physics_ticks_per_second = rate
	seed(123456)
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(current_case + ": " + label)

func frames(count: int = 3) -> void:
	for frame in count: await process_frame

func run() -> void:
	if not OS.get_user_data_dir().contains("movement-integration-"):
		push_error("Isolated HOME/XDG required")
		quit(2); return
	create_timer(100.0, true).timeout.connect(func(): quit(2))
	settings = root.get_node("Settings")
	var pause = root.get_node("PauseController")
	pause.set_process_input(false)
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	if mode.begins_with("settings"):
		await settings_cases()
		finish(); return
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game); current_scene = game
	await frames(); await physics_frame
	Fixture.configure(game)
	guide = game.movement_guide
	if candidate_order:
		guide.process_physics_priority = game.player_left.process_physics_priority
		game.move_child(guide, game.player_left.get_index() + 1)
	current_case = "automatic_lifecycle"
	check(is_instance_valid(guide) and guide.get_script() == Guide, "game did not create the real guidance node")
	check(count_guides(game) == 1, "not exactly one automatic guide")
	check(game.aim_focus != null, "aim focus not integrated alongside guide")
	check(guide.get_index() == game.player_left.get_index() + 1 and guide.process_physics_priority == game.player_left.process_physics_priority, "guide not immediately after native predictor in existing physics order")
	check(guide.is_physics_processing() and guide.is_processing(), "automatic guide clock disabled")
	check(guide.process_mode == Node.PROCESS_MODE_ALWAYS and guide.process_physics_priority >= game.player_left.process_physics_priority, "native predictor ordering invalid")
	check(guide.layer > game.aim_focus.layer and guide.layer < game.hud.layer, "layer not between focus and HUD")
	check(guide._drawing.mouse_filter == Control.MOUSE_FILTER_IGNORE and guide._drawing.focus_mode == Control.FOCUS_NONE, "guide captures pointer/focus")
	check(not guide.is_processing_input() and not guide.is_processing_unhandled_input(), "guide owns gameplay input")
	for phase in ["input", "before", "after"]:
		var node = Probe.new(); node.owner_test = self; node.phase = phase
		if phase == "input":
			node.process_physics_priority = -100; root.add_child(node)
		else:
			node.process_physics_priority = guide.process_physics_priority; node.process_priority = maxi(guide.process_priority, game.camera_rig.process_priority) + 1; game.add_child(node)
			game.move_child(node, guide.get_index() if phase == "before" else guide.get_index() + 1)
	if mode.begins_with("trace-"):
		await live_case(mode == "trace-on", true)
	elif mode == "native-interruptions":
		await native_interruptions()
	elif mode == "native-events":
		await live_case(true, false, 3.4)
		var max_bounces := 0
		var neutral_ticks := 0
		for row in live_trace:
			max_bounces = maxi(max_bounces, row.bounces)
			if not row.in_play or row.bounces >= 2 or row.state != game.GameState.PLAYING: neutral_ticks += 1
		check(max_bounces >= 1, "real arc never bounced")
		check(neutral_ticks > 0 and invalid_render_frames > 0, "real terminal bounce/fault cancellation never exercised")
		records.append({"case": "native_terminal_boundary", "max_bounces": max_bounces, "neutral_physics_ticks": neutral_ticks, "neutral_render_ticks": invalid_render_frames})
	else:
		controlled_cases()
		await live_case(true, false)
		current_case = "repeated_reset_lifecycle"
		for iteration in 8:
			game._reset_ball()
			check(count_guides(game) == 1 and game.movement_guide == guide, "reset duplicated or replaced the automatic guide")
			check(guide._advice.is_empty() and guide.presentation_state().is_empty(), "reset retained advice")
	game.queue_free(); current_scene = null
	await frames(3)
	current_case = "scene_teardown"
	check(not is_instance_valid(guide), "automatic guide survived game teardown")
	var until := Time.get_ticks_usec() + 180000
	while Time.get_ticks_usec() < until: OS.delay_msec(5); await process_frame
	finish()

func count_guides(node: Node) -> int:
	var count := int(node.get_script() == Guide)
	for child in node.get_children(): count += count_guides(child)
	return count

func prepare(status := "MOVE") -> void:
	guide.player = Feeds.prepare(game, status)
	if status == "NO_TIME":
		# Real long-lived proof feed from movement_status_stability_ui_regression.
		# The old low/fast feed expires before the intentional 50 ms admission.
		guide.player.global_position.x = -3.0
		guide.player.current_velocity = Vector3.ZERO
		guide.player.leg_ik.feet_initialized = false
		guide.player._process(0.0)
		game.ball.global_position = Vector3(3.0, 1.1, 4.0)
		game.ball.linear_velocity = Vector3(0.0, -0.5, 0.3)
		game.ball.angular_velocity = Vector3.ZERO
	guide.advisor = Advisor.new()
	guide._reset_generation = game._point_reset_generation
	guide.cancel()
	var snapshot := fingerprint()
	guide.tick(0.0, Feeds.flight(game))
	check(fingerprint() == snapshot, "advisor or drawing changed gameplay snapshot")
	if status == "NO_TIME":
		check(guide._advice.get("status") == "NO_TIME" and guide._valid_no_time_proof(), "entry fixture lacks genuine current impossibility proof")
		check(guide.presentation_state().get("status") == "TIGHT", "NO_TIME appeared before continuous proof admission")
		var entry: Array = [{"elapsed": 0.0, "shown": guide.presentation_state().get("status"), "proof": guide._valid_no_time_proof()}]
		for frame in range(ceili(Guide.NO_TIME_ENTRY_SECONDS * rate)):
			var before_tick := fingerprint()
			guide.tick(1.0 / rate, Feeds.flight(game))
			var elapsed := float(frame + 1) / rate
			check(fingerprint() == before_tick, "proof-entry observation mutated gameplay")
			check(guide._advice.get("status") == "NO_TIME" and guide._valid_no_time_proof(), "current proof did not remain continuous during entry")
			var shown: String = guide.presentation_state().get("status", "UNKNOWN")
			check(shown == ("TIGHT" if elapsed + 0.000001 < Guide.NO_TIME_ENTRY_SECONDS else "NO_TIME"), "NO_TIME admission violates the real 50 ms continuous-proof interval")
			entry.append({"elapsed": elapsed, "shown": shown, "proof": guide._valid_no_time_proof()})
		records.append({"case": "automatic_continuous_no_time_entry", "samples": entry, "minimum_seconds": Guide.NO_TIME_ENTRY_SECONDS})

func controlled_cases() -> void:
	game.process_mode = Node.PROCESS_MODE_DISABLED
	guide.set_process(false); guide.set_physics_process(false)
	for status in ["MOVE", "TIGHT", "NO_TIME"]:
		current_case = "automatic_legal_" + status
		prepare(status)
		var advice: Dictionary = guide._advice
		var view: Dictionary = guide.presentation_state()
		check(advice.get("visible", false) and advice.get("status") == status, "legal fixture status missing")
		check(view.get("status") == status, "legal fixture not presented")
		if advice.get("visible", false):
			var detached = Advisor.snapshot(game.player_left); detached.place(advice.target_root)
			var base: PostureDefinition = PostureLibrary.instance().get_def(advice.posture)
			check(Advisor._within_bounds(game.player_left, advice.target_root), "root outside bounds")
			check(Planner.legal_ball(detached, game.ball, advice.future_bounces), "illegal bounce or NVZ target")
			check(Planner.point_fits(detached, base, advice.point), "target fails shared reach geometry")
			var pose: PostureDefinition = Planner.pose_at(detached, base, advice.point)
			check(Finite.touches(Path.world_transform(detached, pose), advice.point, Ball.BALL_RADIUS), "target misses finite paddle")
			if status == "NO_TIME": check(advice.no_time_proven and advice.proof_scope == "predicted_legal_flight", "impossibility claim lacks proof")
		records.append({"case": current_case, "advice": advice, "state": view})
		if status == "NO_TIME":
			var saved_root: Vector3 = guide.player.global_position
			guide.player.global_position.x += 0.001
			guide._process(0.0)
			check(guide.presentation_state().get("status") != "NO_TIME", "between-tick root motion retained an invalid impossibility claim")
			guide.player.global_position = saved_root
			guide._process(0.0)
			check(guide.presentation_state().get("status") != "NO_TIME", "returning to solved root bypassed fresh proof admission")
	current_case = "automatic_neutral_standing"
	Fixture.prepare(game, {"name": "standing", "root_z": 4.7, "lateral": 0.42, "height": 1.08, "forward": 0.46, "duration": 1.65, "family": 0})
	game.ball.freeze = true
	guide.advisor = Advisor.new(); guide._reset_generation = game._point_reset_generation
	guide.tick(0.0, Feeds.flight(game))
	check(not guide._advice.get("visible", true) and guide._advice.get("reason") == "already_in_reach", "standing legal reach asks to move")
	check(guide.presentation_state().is_empty(), "standing guidance not neutral")
	for gate in ["pause", "guide", "tool", "reset", "waiting", "match", "outgoing", "second_bounce", "setting"]:
		current_case = "automatic_cancel_" + gate
		prepare()
		check(not guide.presentation_state().is_empty(), "cancellation fixture not visible")
		match gate:
			"pause": paused = true
			"guide": game.hud._guide.show()
			"tool":
				game.mobile_pose_editor = Node.new(); game.add_child(game.mobile_pose_editor)
				game._suspend_tool_gameplay()
			"reset": game._reset_ball()
			"waiting": game._set_game_state(game.GameState.WAITING)
			"match": game.match_over = true; game._clear_finished_match_controls([])
			"outgoing": game.ball.last_hit_by = 0
			"second_bounce": game.ball.bounces_since_last_hit = 2
			"setting": settings.set_value("gameplay.movement_guide", false)
		if gate in ["tool", "reset", "waiting", "match"]:
			check(guide._advice.is_empty() and guide.presentation_state().is_empty(), "explicit lifecycle cancellation not immediate")
		guide._process(0.0)
		check(guide._advice.is_empty() and guide.presentation_state().is_empty() and not guide._drawing.visible, "invalid guide survived current render")
		paused = false; game.hud._guide.hide(); game.match_over = false
		if gate == "tool":
			game.mobile_pose_editor.free(); game.mobile_pose_editor = null
			game._resume_tool_gameplay()
		settings.set_value("gameplay.movement_guide", true)
	game.process_mode = Node.PROCESS_MODE_INHERIT
	guide.set_process(true); guide.set_physics_process(true)

func native_interruptions() -> void:
	var automatic_id: int = guide.get_instance_id()
	for gate in ["pause", "guide", "tool", "reset", "waiting", "match", "outgoing", "second_bounce", "setting", "new_flight"]:
		current_case = "native_interrupt_" + gate
		Fixture.prepare(game, Fixture.cases()[1])
		game.ball.freeze = false
		game.hud.set_gameplay_elements_visible(true); game.hud._guide.hide(); game.hud._between_point_active = false
		guide.advisor = Advisor.new(); guide._reset_generation = game._point_reset_generation
		for tick in 6: await physics_frame
		await process_frame
		check(not guide.presentation_state().is_empty(), "native cancellation had no visible live guide")
		var previous_flight: int = game.ball.flight_id
		match gate:
			"pause": root.get_node("PauseController").open()
			"guide": game.hud._guide.show()
			"tool":
				game.mobile_pose_editor = Node.new(); game.add_child(game.mobile_pose_editor)
				game._suspend_tool_gameplay()
			"reset": game._reset_ball()
			"waiting": game._set_game_state(game.GameState.WAITING)
			"match": game.match_over = true; game._clear_finished_match_controls([])
			"outgoing": game.ball.last_hit_by = 0; game.ball.flight_id += 1
			"second_bounce": game.ball.bounces_since_last_hit = 2
			"setting": settings.set_value("gameplay.movement_guide", false)
			"new_flight": game.ball.flight_id += 1
		for frame in 4:
			await process_frame
			if gate == "new_flight":
				check(guide.presentation_state().is_empty() or guide._advice.get("flight_id") == game.ball.flight_id, "old-flight marker retained during next native frame")
			else:
				check(guide.presentation_state().is_empty() and guide._advice.is_empty(), "guide survives native interruption frame " + str(frame))
		check(count_guides(game) == 1 and guide.get_instance_id() == automatic_id, "interruption duplicated or replaced automatic guide")
		if gate == "pause": root.get_node("PauseController").close()
		game.hud._guide.hide(); game.match_over = false
		if gate == "tool":
			game.mobile_pose_editor.free(); game.mobile_pose_editor = null
			game._resume_tool_gameplay()
		settings.set_value("gameplay.movement_guide", true)
		await frames(2)
		records.append({"case": current_case, "previous_flight": previous_flight, "current_flight": game.ball.flight_id, "automatic_id": automatic_id})

func live_case(enabled: bool, with_input: bool, duration: float = 1.8) -> void:
	current_case = "native_live_" + str(enabled)
	Fixture.prepare(game, Fixture.cases()[1])
	game.hud.set_gameplay_elements_visible(true); game.hud._guide.hide(); game.hud._between_point_active = false
	game.ball.freeze = false
	guide.advisor = Advisor.new(); guide._reset_generation = game._point_reset_generation
	settings.set_value("gameplay.movement_guide", enabled)
	game.set_meta("integration_inputs", with_input)
	sample_count = 0; sample_limit = int(rate * duration)
	live_fresh = 0; live_visible = 0; live_status = {}; live_trace = []
	capturing = true
	await samples_done
	for action in ["move_left", "move_right", "move_up", "move_down", "ui_accept"]: Input.action_release(action)
	check(live_trace.size() == sample_limit, "native physics sampling incomplete")
	var first: Array = live_trace[0].ball_position; var last: Array = live_trace[-1].ball_position
	check(first != last, "native rigid body never advanced")
	if enabled:
		check(live_fresh > sample_limit * 0.5, "active native predictor cache rarely fresh")
		check(guide.advisor.statistics.reused_flights > 5, "guide did not reuse active native predictor")
		check(guide.advisor.statistics.traces == 0, "guide duplicated real player's prediction trace")
		check(guide.advisor.statistics.solves <= ceili(duration / Advisor.REFRESH_INTERVAL) + 1, "automatic solver exceeded 10 Hz limit")
		check(live_visible > 0, "actual live arc never showed guidance")
	else:
		check(guide.advisor.statistics.solves == 0 and live_visible == 0, "disabled guide solved or rendered")
	records.append({"case": current_case, "frames": sample_count, "fresh_predictor_frames": live_fresh, "visible_frames": live_visible, "statuses": live_status, "statistics": guide.advisor.statistics.duplicate(true)})

func probe(phase: String, _delta: float) -> void:
	if not capturing: return
	if phase == "input":
		if game.get_meta("integration_inputs", false):
			var t := float(sample_count) / rate
			if t < 0.5: Input.action_press("move_left", 0.55)
			else: Input.action_release("move_left")
			if t >= 0.65 and t < 1.1: Input.action_press("move_right", 0.4)
			else: Input.action_release("move_right")
			# Explicit aim nudges are deterministic player input, with real
			# aim controller state recorded in the paired enabled/disabled runs.
			game.aim_controller.update(_delta, false, Vector2(0.2, 0.0), true)
			game.aim_controller.nudge(Vector2(0.2, -0.15), _delta)
		return
	if phase == "before":
		before = fingerprint()
		if Advisor._fresh_flight(game.player_left.debug_visual._last_flight, game.ball): live_fresh += 1
		if sample_count < 3:
			var flight: Dictionary = game.player_left.debug_visual._last_flight
			records.append({"case": "native_order_probe", "frame": sample_count, "samples": flight.get("samples", []).size(), "first": flight.get("samples", [{}])[0], "ball_pos": game.ball.global_position, "ball_vel": game.ball.linear_velocity, "ball_spin": game.ball.angular_velocity, "player_priority": game.player_left.process_physics_priority, "ball_priority": game.ball.process_physics_priority, "player_index": game.player_left.get_index(), "ball_index": game.ball.get_index(), "player_physics": game.player_left.is_physics_processing()})
		return
	check(fingerprint() == before, "guide mutated input/player/ball/aim during native physics tick %d" % sample_count)
	check(guide.advisor.statistics.last_geometry_tests <= Advisor.MAX_GEOMETRY_TESTS, "geometry solve budget exceeded")
	check(guide.advisor.statistics.last_time_samples <= Advisor.MAX_TIME_SAMPLES, "time sample budget exceeded")
	var view: Dictionary = guide.presentation_state()
	if not view.is_empty():
		live_visible += 1; live_status[view.status] = int(live_status.get(view.status, 0)) + 1
	var human = game.player_left.posture.human_contact
	live_trace.append({"frame": sample_count, "ball_position": xyz(game.ball.global_position), "ball_velocity": xyz(game.ball.linear_velocity), "ball_spin": xyz(game.ball.angular_velocity), "player_position": xyz(game.player_left.global_position), "player_velocity": xyz(game.player_left.current_velocity), "aim": xyz(game.aim_controller.target), "aim_mode": game.aim_controller.mode, "aim_planted": game.aim_controller.planted, "stamina": game.player_left.stamina.value, "human_phase": human.phase, "bounces": game.ball.bounces_since_last_hit, "in_play": game.ball.is_in_play, "state": game.game_state})
	sample_count += 1
	if sample_count >= sample_limit:
		capturing = false
		call_deferred("emit_signal", "samples_done")

func render_probe() -> void:
	if not capturing: return
	if not guide.presentation_state().is_empty():
		check(guide._advice.get("flight_id") == game.ball.flight_id, "stale old-flight marker survived native render")
	if not guide._eligible():
		invalid_render_frames += 1
		check(guide._advice.is_empty() and guide.presentation_state().is_empty(), "ineligible automatic guide survived native render")

func xyz(value: Vector3) -> Array: return [value.x, value.y, value.z]

func fingerprint() -> Array:
	var player = game.player_left
	var human = player.posture.human_contact
	return [player.global_transform, player.velocity, player.current_velocity,
		player.stamina.value, human.phase, human.contact.duplicate(true), human.footwork.active,
		player._nvz_state.established_outside, player._nvz_state._last_root,
		player.leg_ik.right_foot_smooth, player.leg_ik.left_foot_smooth, player.leg_ik.feet_initialized,
		player._manual_motion_active, player.is_jumping,
		game.aim_controller.target, game.aim_controller.mode, game.aim_controller.planted, game.serve_charge_time,
		game.ball.global_transform, game.ball.linear_velocity, game.ball.angular_velocity,
		game.ball.flight_id, game.ball.bounces_since_last_hit,
		Input.is_action_pressed("ui_accept"), Input.get_vector("move_left", "move_right", "move_up", "move_down")]

func settings_cases() -> void:
	current_case = mode
	if mode == "settings-seed":
		for malformed in [0, 1, -1, 0.0, 1.0, "false", "true", "", null, [], {}, Vector2.ONE]:
			settings.set_value("gameplay.movement_guide", malformed)
			check(typeof(settings.get_value("gameplay.movement_guide")) == TYPE_BOOL and settings.get_value("gameplay.movement_guide"), "invalid setter did not sanitize to true")
		settings.set_value("gameplay.movement_guide", false)
		settings.set_value("video.focus_dim", 0.31)
		settings.set_value("pose_editor.integration_sentinel", {"preserve": [3, 8]})
		await frames()
		check(FileAccess.file_exists(settings.CONFIG_PATH), "queued save did not write config")
		check(settings.get_value("gameplay.movement_guide") == false, "seed preference not disabled")
		return
	if mode == "settings-reload":
		check(settings.get_value("gameplay.movement_guide") == false, "fresh process lost saved off preference")
		check(settings.get_value("pose_editor.integration_sentinel") == {"preserve": [3, 8]}, "sentinel lost across processes")
		settings.reset_focus_visuals()
		check(settings.get_value("gameplay.movement_guide") == false, "focus reset changes guidance preference")
		settings.reset_to_defaults()
		check(settings.get_value("gameplay.movement_guide") == true, "all-defaults reset excludes movement guide")
		check(settings.get_value("pose_editor.integration_sentinel") == {"preserve": [3, 8]}, "all-defaults reset erased custom data")
		await frames(); return
	if mode == "settings-default-reload":
		check(settings.get_value("gameplay.movement_guide") == true, "fresh process lost reset default")
		return
	if mode.begins_with("settings-invalid-"):
		var variants: Array = [0, 1, -1, 0.0, 1.0, "false", "true", "", null, [], {}, Vector2.ONE]
		var index := int(mode.get_slice("-", 3))
		if mode.begins_with("settings-invalid-seed-"):
			settings._config.set_value("gameplay", "movement_guide", variants[index]); settings._do_save()
			check(FileAccess.file_exists(settings.CONFIG_PATH), "invalid serialized fixture not written")
		else:
			check(typeof(settings._config.get_value("gameplay", "movement_guide", "<missing>")) != TYPE_BOOL, "invalid serialized fixture not loaded")
			check(typeof(settings.get_value("gameplay.movement_guide")) == TYPE_BOOL and settings.get_value("gameplay.movement_guide") == true, "serialized invalid type did not safely default true")
		return
	if mode == "settings-ui" or mode == "settings-native":
		await settings_ui(); return
	check(false, "unknown settings mode")

func settings_ui() -> void:
	root.content_scale_size = Vector2i(720, 1280)
	paused = true
	for size in [Vector2i(390, 844), Vector2i(430, 932), Vector2i(540, 960), Vector2i(960, 540)]:
		root.size = size; await frames(5)
		var panel = load("res://scripts/ui/settings_panel.gd").new(); root.add_child(panel)
		await frames(5)
		var scroll: ScrollContainer = panel.find_child("Gameplay", true, false)
		var tabs: TabContainer = scroll.get_parent(); tabs.current_tab = 1
		var control: CheckButton = panel.find_child("gameplay_movement_guide", true, false)
		await frames(5)
		check(control != null, "actual movement toggle missing at " + str(size))
		if control == null: panel.queue_free(); await frames(); continue
		scroll.ensure_control_visible(control); await frames(5)
		var rect: Rect2 = control.get_global_rect()
		var logical := root.get_visible_rect().size
		var px := rect.size * Vector2(size) / logical
		check(px.x >= 43.9 and px.y >= 43.9, "actual toggle below 44 pixel touch target at %s: %s" % [size, px])
		check(root.get_visible_rect().grow(0.5).encloses(panel._panel.get_global_rect()), "panel outside viewport at " + str(size))
		check(scroll.get_global_rect().grow(0.5).encloses(rect), "toggle clipped after scrolling at " + str(size))
		check(scroll.get_h_scroll_bar().max_value <= scroll.get_h_scroll_bar().page + 0.5, "horizontal overflow at " + str(size))
		var legend := ""
		for node in scroll.find_children("*", "Label", true, false):
			if node.text.begins_with("MOVE marks"): legend = node.text
		check(legend.contains("TIGHT") and legend.contains("NO TIME") and legend.contains("never moves your player"), "missing guide explanation")
		settings.set_value("gameplay.movement_guide", true)
		check(control.button_pressed, "external preference update not reflected by checkbox")
		for location in [rect.get_center(), rect.position + Vector2(2, 2), rect.end - Vector2(2, 2)]:
			var previous: bool = settings.get_value("gameplay.movement_guide")
			await pointer_tap(location)
			check(settings.get_value("gameplay.movement_guide") != previous, "pointer failed actual target at %s %s" % [size, location])
		for location in [rect.get_center(), rect.position + Vector2(2, 2), rect.end - Vector2(2, 2)]:
			var touch_previous: bool = settings.get_value("gameplay.movement_guide")
			await touch_tap(location)
			check(settings.get_value("gameplay.movement_guide") != touch_previous, "touch failed actual target at %s %s" % [size, location])
		records.append({"size": [size.x, size.y], "viewport": [logical.x, logical.y], "toggle_pixels": [px.x, px.y], "toggle_rect": str(rect), "legend": legend})
		if mode == "settings-native":
			await RenderingServer.frame_post_draw
			var output := OS.get_environment("MOVEMENT_INTEGRATION_REPORT").get_base_dir()
			check(root.get_texture().get_image().save_png(output.path_join("settings-%dx%d.png" % [size.x, size.y])) == OK, "native settings capture failed")
		panel._on_close(); await frames(3)
		check(not is_instance_valid(panel), "settings close leaked panel")
	paused = false

func pointer_tap(point: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT
		event.position = point; event.global_position = point; event.pressed = down
		root.push_input(event, true); await process_frame

func touch_tap(point: Vector2) -> void:
	Input.set_emulate_mouse_from_touch(true)
	for down in [true, false]:
		var event := InputEventScreenTouch.new(); event.index = 0; event.position = root.get_final_transform() * point; event.pressed = down
		Input.parse_input_event(event); await process_frame

func finish() -> void:
	var report := {"rate": rate, "mode": mode, "candidate_order": candidate_order, "checks": checks, "failures": failures, "records": records,
		"trace": live_trace if mode.begins_with("trace-") or mode == "native-events" else [], "scope": "Archived build28 plus cloud A/B/C/D integration, NOT unavailable Mac build30/31", "user_data_dir": OS.get_user_data_dir()}
	var destination := OS.get_environment("MOVEMENT_INTEGRATION_REPORT")
	FileAccess.open(destination, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	for failure in failures: push_error(failure)
	print("CLOUD MOVEMENT INTEGRATION %s %d Hz: %d checks, %d failures" % [mode, rate, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
