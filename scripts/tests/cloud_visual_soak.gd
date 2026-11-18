extends SceneTree
## Real-time seeded input/scene-lifecycle audit. Never writes ball/contact/score/pose state.
var game
var observer
var rate := 60
var duration := 240.0
var seed_value := 271828
var output := ""
var guidance_disabled := false
var start_usec := 0
var scene_number := 0
var checks := 0
var failures: Array = []
var counts: Dictionary = {}
var records: Array = []
var teardowns: Array = []
var deadlines: Dictionary = {}
var trace_file: FileAccess
var events_file: FileAccess
var next_control := 0
var last_hit_change := 0
var driver_hit := false
var driver_stick := false
var hit_position := Vector2.ZERO
var stick_position := Vector2.ZERO
var last_driver_direction := Vector2.INF
var schedule: Array = []
var schedule_index := 0
var changing_scene := false
var last_state := {}
var last_solve := -1
var last_solve_at := 0
var last_active := false
var focus_epoch := 0
var last_preview_epoch := -1
var last_advisor_solves := 0
var last_advisor_clock := 0.0
var frame_count := 0
var last_frame_usec := 0
var max_frame_usec := 0
var normal_frames := 0
var normal_delta := 0.0
var normal_physics_frames := 0
var reset_before := {}
var monitor := false
var rng := RandomNumberGenerator.new()

class TailObserver extends Node:
	var harness
	func _process(delta: float) -> void: harness.observe(delta)
	func _physics_process(delta: float) -> void:
		if not get_tree().paused and is_equal_approx(Engine.time_scale, 1.0):
			harness.normal_physics_frames += 1
			harness.normal_delta += delta

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rate="): rate = int(a.trim_prefix("--rate="))
		if a.begins_with("--seconds="): duration = float(a.trim_prefix("--seconds="))
		if a.begins_with("--seed="): seed_value = int(a.trim_prefix("--seed="))
		if a.begins_with("--output="): output = a.trim_prefix("--output=")
		if a == "--guidance-disabled": guidance_disabled = true
	Engine.physics_ticks_per_second = rate
	Engine.max_fps = rate
	rng.seed = seed_value
	seed(seed_value)
	call_deferred("run")

func count(key: String, amount: int = 1) -> void: counts[key] = int(counts.get(key, 0)) + amount
func check(ok: bool, label: String, detail: Dictionary = {}) -> void:
	checks += 1
	if ok: return
	var failure := {"label": label, "usec": Time.get_ticks_usec(), "elapsed": elapsed(), "scene": scene_number, "detail": detail, "state": last_state}
	failures.append(failure)
	print("VISUAL_SOAK_ACTIONABLE_FAILURE ", JSON.stringify(failure))

func elapsed() -> float: return float(Time.get_ticks_usec() - start_usec) / 1000000.0 if start_usec else 0.0
func event(kind: String, data: Dictionary = {}) -> void:
	var row := {"usec": Time.get_ticks_usec(), "elapsed": elapsed(), "scene": scene_number, "physics_frame": Engine.get_physics_frames(), "kind": kind, "data": data}
	if events_file: events_file.store_line(JSON.stringify(row)); events_file.flush()

func touch(id: int, point: Vector2, pressed: bool, canceled: bool = false) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = id; ev.position = point; ev.pressed = pressed; ev.canceled = canceled
	event("touch", {"id": id, "point": [point.x, point.y], "pressed": pressed, "canceled": canceled})
	root.push_input(ev, true)

func drag(id: int, point: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = id; ev.position = point
	event("drag", {"id": id, "point": [point.x, point.y]})
	root.push_input(ev, true)

func set_hit(down: bool) -> void:
	if down == driver_hit: return
	driver_hit = down
	last_hit_change = Time.get_ticks_usec()
	if down: hit_position = game.mobile_controls._charge_center
	touch(41, hit_position, down)

func set_movement(direction: Vector2) -> void:
	if direction.is_equal_approx(last_driver_direction): return
	last_driver_direction = direction
	if direction.length() < 0.12:
		if driver_stick: touch(42, stick_position, false)
		driver_stick = false
		return
	stick_position = game.mobile_controls._stick_center + direction.limit_length(1.0) * game.mobile_controls._stick_radius
	if not driver_stick:
		driver_stick = true
		touch(42, game.mobile_controls._stick_center, true)
	drag(42, stick_position)

func release_driver() -> void:
	if driver_hit: touch(41, hit_position, false, true)
	if driver_stick: touch(42, stick_position, false, true)
	driver_hit = false; driver_stick = false; last_driver_direction = Vector2.INF
	for action in ["ui_accept", "move_up", "move_down", "move_left", "move_right"]: Input.action_release(action)

func frames(n: int) -> void:
	for i in n: await process_frame

func spawn_game() -> void:
	scene_number += 1
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game); current_scene = game
	await frames(8)
	check(game.mobile_controls.enabled, "mobile controls not enabled")
	game.ball.hit_by_paddle.connect(on_hit)
	game.rally_scorer.rally_ended.connect(on_point)
	last_solve = -1; last_advisor_solves = 0; last_advisor_clock = 0.0; last_active = false
	event("scene_created", {"nodes": get_node_count(), "resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)})

func on_hit(team: int) -> void: count("paddle_hits_%d" % team); event("paddle_hit", {"team": team})
func on_point(team: int, reason: String, detail: String) -> void: count("natural_points_%d" % team); event("natural_point", {"team": team, "reason": reason, "detail": detail})

func teardown() -> void:
	monitor = false
	release_driver()
	root.get_node("PauseController").close()
	var weak: WeakRef = weakref(game)
	game.queue_free(); game = null
	await frames(3)
	var stop := Time.get_ticks_usec() + 250000
	while Time.get_ticks_usec() < stop: await process_frame
	var ts = root.get_node("TimeScale")
	var data := {"elapsed": elapsed(), "scene": scene_number, "nodes": get_node_count(), "orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), "objects": Performance.get_monitor(Performance.OBJECT_COUNT), "resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), "size_signal_connections": root.size_changed.get_connections().size(), "focus_signal_connections": root.focus_exited.get_connections().size(), "time_scale": Engine.time_scale, "scene_freed": weak.get_ref() == null}
	teardowns.append(data); event("scene_teardown", data)
	check(weak.get_ref() == null, "game scene still referenced after teardown")
	check(not paused and is_equal_approx(Engine.time_scale, 1.0) and not ts._slowmo_sources.has("aim_focus"), "teardown left pause/slowmo state")
	check(not Input.is_action_pressed("ui_accept"), "teardown left held HIT")
	if teardowns.size() > 1:
		check(data.nodes <= teardowns[0].nodes, "scene teardown leaked nodes", data)
		check(data.size_signal_connections <= teardowns[0].size_signal_connections, "scene teardown leaked viewport signals", data)
		check(data.orphans <= teardowns[0].orphans, "scene teardown leaked orphan nodes", data)

func build_schedule() -> void:
	# Explicit lifecycle events run through their ordinary menu handlers. Their
	# nominal times and actual dispatch times are both saved; no scene state is fabricated.
	schedule = [[7.0,"pause"], [7.5,"resume"], [10.0,"guide_open"], [10.7,"guide_close"],
		[14.0,"settings_open"], [14.2,"settings_change"], [14.6,"settings_close"], [14.9,"resume"],
		[19.0,"reset_open"], [19.3,"reset_cancel"], [19.6,"resume"], [23.0,"reset_open"], [23.4,"reset_confirm"],
		[28.0,"practice_DRIVE"], [38.0,"practice_RETURN"], [48.0,"practice_DINK"], [58.0,"practice_HANDS"],
		[68.0,"return_match"], [72.0,"new_scene"]]
	# Quick validation scales the same menu sequence, then runs a brief natural segment.
	if duration < 80.0:
		for item in schedule: item[0] = float(item[0]) * duration * 0.75 / 72.0

func lifecycle(kind: String, nominal: float) -> void:
	event("lifecycle", {"action": kind, "nominal_seconds": nominal})
	count(kind)
	var pause = root.get_node("PauseController")
	match kind:
		"pause":
			pause.open(); check(paused and is_instance_valid(pause._menu), "Pause action did not open menu")
		"resume":
			pause.close(); check(not paused, "Resume action left paused tree")
		"guide_open":
			var point: Vector2 = game.hud._guide_button.get_global_rect().get_center()
			touch(43, point, true); touch(43, point, false)
		"guide_close":
			var point: Vector2 = game.hud._guide_button.get_global_rect().get_center()
			touch(43, point, true); touch(43, point, false)
		"settings_open":
			pause.open(); pause._menu._settings_button.pressed.emit()
			check(is_instance_valid(pause._menu._settings_overlay), "Settings action did not create overlay")
		"settings_change":
			var panel = pause._menu._settings_overlay
			for name in ["video_focus_blur", "video_focus_dim", "gameplay_aim_focus_seconds"]:
				var slider = panel.find_child(name, true, false)
				if slider is HSlider:
					slider.value = slider.min_value
					slider.value = slider.max_value
					slider.value = 3.0 if name == "gameplay_aim_focus_seconds" else 0.65 if name == "video_focus_blur" else 0.14
					count("settings_sliders_exercised")
		"settings_close": pause._menu.close_settings()
		"reset_open":
			pause.open(); reset_before = {"left": game.score_left, "right": game.score_right, "serving": game.serving_team, "position": game.ball.global_position}
			pause._menu._reset_button.pressed.emit()
			check(pause._menu._reset_dialog.visible, "Reset confirmation did not appear")
		"reset_cancel":
			pause._menu._reset_dialog.get_cancel_button().pressed.emit()
			check(game.score_left == reset_before.left and game.score_right == reset_before.right and game.serving_team == reset_before.serving and game.ball.global_position.is_equal_approx(reset_before.position), "Cancel reset changed frozen score/ball")
		"reset_confirm":
			pause._menu._reset_dialog.get_ok_button().pressed.emit()
			check(not paused and game.score_left == 0 and game.score_right == 0 and game.game_state == 0, "Confirm reset did not create clean match")
		"return_match":
			game.practice_panel.open_practice(); game.practice_panel._return_to_match()
		"new_scene":
			changing_scene = true
			await teardown()
			await spawn_game()
			monitor = true; changing_scene = false
		_:
			if kind.begins_with("practice_"):
				game.practice_panel.open_practice(); game.practice_panel._start(kind.trim_prefix("practice_"))

func driver(now: int) -> void:
	if now < next_control or not is_instance_valid(game): return
	next_control = now + 50000
	var mobile = game.mobile_controls
	# A UI cancellation is a real canceled pointer; do not synthesize a new
	# down edge from the old finger. Send its late release, then start afresh.
	if driver_hit and mobile._charge_id != 41:
		set_hit(false); return
	if driver_stick and mobile._stick_id != 42:
		set_movement(Vector2.ZERO); return
	if game.match_over:
		game.practice_panel._rematch(); count("natural_rematch"); return
	if mobile._blocked(): return
	var held_seconds := float(now - last_hit_change) / 1000000.0
	if game.game_state == 0 and game.serving_team == 0:
		if not driver_hit and held_seconds > 0.2: set_hit(true)
		var cap := 4.5 if scene_number == 3 and elapsed() < 6.0 else 0.55
		if driver_hit and held_seconds >= cap: set_hit(false)
		set_movement(Vector2.ZERO)
		if driver_hit and elapsed() < 6.0:
			hit_position = mobile._charge_center + Vector2(sin(elapsed() * 1.4), cos(elapsed() * 1.1)) * 14.0
			drag(41, hit_position)
		return
	if game.game_state != 2:
		set_hit(false); set_movement(Vector2.ZERO); return
	var human = game.player_left.posture.human_contact
	var timing: Dictionary = human.release_timing_state() if human != null else {}
	var phase := fmod(elapsed(), 23.0)
	var rapid := phase > 16.0 and phase < 18.0
	if rapid:
		if held_seconds > 0.07: set_hit(not driver_hit); count("rapid_hit_edges")
	elif not driver_hit and held_seconds > 0.2:
		set_hit(true)
	elif driver_hit and (bool(timing.get("release_ready", false)) and held_seconds > 0.12 or held_seconds > 4.5):
		set_hit(false)
	# Only input is moved: pursue the existing displayed legal root when
	# offered, otherwise track the live incoming ball with manual movement.
	var target: Vector3 = game.ball.global_position + Vector3(-0.4, 0, 0.55)
	var advice: Dictionary = game.movement_guide._advice
	if bool(advice.get("visible", false)): target = advice.target_root
	var offset: Vector3 = target - game.player_left.global_position
	var move := Vector2(offset.x, offset.z).limit_length(1.0)
	if bool(timing.get("current_reachable", false)) or game.ball.last_hit_by == 0: move = Vector2.ZERO
	if offset.length() < 0.25: move = Vector2.ZERO
	if phase > 12.0 and phase < 14.0: move = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).limit_length(1.0)
	set_movement(move)
	if driver_hit and game.aim_controller.mode == "AIM":
		hit_position = mobile._charge_center + Vector2(sin(elapsed() * 0.6), cos(elapsed() * 0.4)) * 9.0
		drag(41, hit_position)

func observe(_delta: float) -> void:
	if not monitor or changing_scene or not is_instance_valid(game): return
	var now := Time.get_ticks_usec()
	frame_count += 1
	if last_frame_usec: max_frame_usec = maxi(max_frame_usec, now - last_frame_usec)
	last_frame_usec = now
	var f = game.aim_focus
	var guide = game.movement_guide
	var mobile = game.mobile_controls
	var human = game.player_left.posture.human_contact
	var timing: Dictionary = human.release_timing_state() if human != null else {}
	var presentation: Dictionary = guide.presentation_state()
	var positive_guide := bool(presentation.get("visible", false))
	var stats: Dictionary = guide.advisor.statistics
	var blocked: bool = mobile._blocked()
	if f.active and not last_active: focus_epoch += 1; count("focus_entries")
	last_active = f.active
	last_state = {"elapsed": elapsed(), "usec": now, "scene": scene_number, "process_frame": Engine.get_process_frames(), "physics_frame": Engine.get_physics_frames(), "state": game.game_state, "flight": game.ball.flight_id, "bounce": game.ball.bounces_since_last_hit, "last_hit": game.ball.last_hit_by, "ball_in_play": game.ball.is_in_play, "ball_position": [game.ball.position.x, game.ball.position.y, game.ball.position.z], "player_position": [game.player_left.position.x, game.player_left.position.y, game.player_left.position.z], "score": [game.score_left, game.score_right], "serving": game.serving_team, "practice": game.practice_launcher.drill_mode if game.practice_launcher.is_active else "", "match_over": game.match_over, "paused": paused, "blocked": blocked, "held": Input.is_action_pressed("ui_accept"), "owners": mobile._owners.duplicate(), "focus": f.active, "focus_holding": f.holding, "focus_exhausted": f.exhausted, "deadline": f.deadline_usec, "rally_deadline": f._rally_deadline_usec, "rally_flight": f._rally_flight_id, "time_scale": Engine.time_scale, "aim_mode": game.aim_controller.mode, "planted": game.aim_controller.planted, "arc_visible": f._drawing.visible, "arc_hint": f.preview_hint, "arc_revision": f._preview_revision, "arc_context": f._current_preview_context(), "arc_target": [f._target_screen.x, f._target_screen.y], "aim_target": [game.aim_controller.target.x, game.aim_controller.target.y, game.aim_controller.target.z], "dim_visible": f._dim.visible, "hud_hint": game.hud._controls_hint.text, "arc_points": f._world_path.size(), "preview_solves": f.preview_solves, "guide_visible": positive_guide, "guide_status": presentation.get("status", ""), "guide_advice_status": guide._advice.get("status", ""), "guide_no_time_proven": guide._advice.get("no_time_proven", false), "guide_reason": guide._advice.get("reason", ""), "guide_flight": guide._advice.get("flight_id", -1), "advisor_solves": stats.solves, "advisor_clock": guide.advisor._clock, "advisor_traces": stats.traces, "reach_ready": mobile._hit_timing.ready, "reach_caption": mobile._hit_timing.caption, "reach_time": timing.get("time", -1.0), "reach_current": timing.get("current_reachable", false), "reach_flight": timing.get("flight_id", -1), "human_phase": human.phase if human != null else -9}
	trace_file.store_line(JSON.stringify(last_state))
	if frame_count % rate == 0: trace_file.flush()
	count("state_%d_frames" % game.game_state)
	if positive_guide: count("positive_guide_frames")
	if mobile._hit_timing.ready: count("reach_ready_frames")
	if f._drawing.visible: count("arc_visible_frames")
	if game.hud._between_point_active: count("retrieval_frames")
	if game.match_over: count("match_end_frames")
	check(not positive_guide or guide._eligible(), "positive movement cue on ineligible frame")
	check(not positive_guide or int(guide._advice.get("flight_id", -1)) == game.ball.flight_id, "movement cue from stale flight")
	if positive_guide and str(presentation.get("status", "")) == "NO_TIME":
		check(bool(guide._advice.get("no_time_proven", false)) and str(guide._advice.get("proof_scope", "")) == "predicted_legal_flight", "NO_TIME displayed without current whole-flight proof")
	check(not f._drawing.visible or f.active and f._eligible(), "visible arc on inactive/ineligible frame")
	check(not f.active or f._eligible(), "focus active on ineligible frame")
	if f._drawing.visible and f.preview_hint != "UPDATING ARC" and game.game_state == 2:
		check(human != null and not human.contact.is_empty() and int(human._flight_id) == game.ball.flight_id and game.aim_controller.mode == "AIM", "nonneutral arc from missing/stale/unlocked contact")
	check(not mobile._hit_timing.ready or not blocked and bool(timing.get("current_reachable", false)) and bool(timing.get("release_ready", false)) and int(timing.get("flight_id", -1)) == game.ball.flight_id, "stale positive RELEASE/reach cue")
	if blocked:
		check(not f.active and not f.holding and mobile._owners.is_empty(), "UI cancellation retained focus or touch ownership")
		check(not Input.is_action_pressed("ui_accept"), "UI cancellation retained held HIT")
	check(is_finite(Engine.time_scale) and Engine.time_scale > 0.0 and Engine.time_scale <= 1.0, "invalid/stuck time scale")
	var ts = root.get_node("TimeScale")
	check(f.active or not ts._slowmo_sources.has("aim_focus"), "inactive focus retained time-scale source")
	check(f._world_path.size() <= f.MAX_PREVIEW_POINTS, "preview point count unbounded")
	check(stats.last_geometry_tests <= guide.advisor.MAX_GEOMETRY_TESTS and stats.last_time_samples <= guide.advisor.MAX_TIME_SAMPLES, "advisor search budget exceeded")
	if int(stats.solves) > last_advisor_solves:
		if last_advisor_solves > 0: check(guide.advisor._next_solve - guide.advisor.REFRESH_INTERVAL - last_advisor_clock >= guide.advisor.REFRESH_INTERVAL - 0.00001, "advisor solve cadence exceeded", {"solve_clock_gap": guide.advisor._next_solve - guide.advisor.REFRESH_INTERVAL - last_advisor_clock})
		last_advisor_solves = stats.solves; last_advisor_clock = guide.advisor._next_solve - guide.advisor.REFRESH_INTERVAL
	if f.preview_solves != last_solve:
		if last_solve >= 0 and last_preview_epoch == focus_epoch: check(f._last_preview_usec - last_solve_at >= f.PREVIEW_INTERVAL_USEC, "preview cadence exceeded within continuous focus", {"gap_usec": f._last_preview_usec - last_solve_at})
		last_solve = f.preview_solves; last_solve_at = f._last_preview_usec; last_preview_epoch = focus_epoch
	if f._rally_deadline_usec > 0:
		var key := "%d:%d:%d" % [scene_number, game._point_reset_generation, f._rally_flight_id]
		if deadlines.has(key): check(int(deadlines[key]) == f._rally_deadline_usec, "same-flight focus deadline changed")
		else: deadlines[key] = f._rally_deadline_usec; count("distinct_rally_deadlines")

func run() -> void:
	for a in OS.get_cmdline_args():
		if a == "--fixed-fps": push_error("Real-time soak rejects --fixed-fps"); quit(2); return
	if output.is_empty(): output = "/tmp/visual_soak"
	DirAccess.make_dir_recursive_absolute(output)
	trace_file = FileAccess.open(output.path_join("state_trace.jsonl"), FileAccess.WRITE)
	events_file = FileAccess.open(output.path_join("input_schedule.jsonl"), FileAccess.WRITE)
	root.size = Vector2i(720, 1280); root.content_scale_size = Vector2i(720, 1280)
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	root.get_node("Settings").set_value("gameplay.movement_guide", not guidance_disabled)
	observer = TailObserver.new(); observer.harness = self; observer.process_mode = Node.PROCESS_MODE_ALWAYS; observer.process_priority = 10000
	root.add_child(observer)
	# Two warm lifecycle cycles establish the unloaded baseline after caches initialize.
	for i in 2: await spawn_game(); await teardown()
	await spawn_game()
	build_schedule()
	start_usec = Time.get_ticks_usec(); event("start", {"physics_hz": rate, "render_cap": rate, "seed": seed_value, "duration": duration, "utc": Time.get_datetime_string_from_system(true)})
	monitor = true
	while elapsed() < duration and failures.is_empty():
		await process_frame
		if changing_scene: continue
		if schedule_index < schedule.size() and elapsed() >= float(schedule[schedule_index][0]):
			var item: Array = schedule[schedule_index]; schedule_index += 1
			await lifecycle(item[1], item[0])
		driver(Time.get_ticks_usec())
	var wall := elapsed()
	await teardown()
	trace_file.close(); events_file.close()
	var data := {"scope": "Archived build28-derived frozen cloud candidate. Real Godot engine, seeded legal touch/menu inputs; no ball/contact/score manipulation. Headless state/projection checks do not measure device or raster performance.", "engine": Engine.get_version_info(), "physics_hz": rate, "render_cap": rate, "wall_seconds": wall, "requested_seconds": duration, "seed": seed_value, "guidance_disabled": guidance_disabled, "checks": checks, "failures": failures, "counts": counts, "teardowns": teardowns, "observed_frames": frame_count, "max_observed_frame_usec": max_frame_usec, "normal_physics_frames": normal_physics_frames, "normal_sim_seconds": normal_delta, "distinct_rally_deadlines": deadlines.size(), "schedule": schedule, "completed_schedule": schedule_index, "coverage_gap": "Match end/rematch is reported only if reached naturally; no fabricated score. No pixel/raster acceptance. Shader and real-phone performance excluded."}
	var f := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t")); f.close()
	print("VISUAL_SOAK_RESULT ", JSON.stringify({"wall_seconds": wall, "checks": checks, "failures": failures.size(), "counts": counts, "report": output.path_join("result.json")}))
	quit(0 if failures.is_empty() else 1)
