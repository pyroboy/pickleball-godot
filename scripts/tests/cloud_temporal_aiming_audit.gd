extends SceneTree
## Deterministic production-method temporal audit. No production edits or physics/pose tuning.
const Estimate = preload("res://scripts/aim_preview_estimate.gd")
var game
var focus
var camera: Camera3D
var rate := 60
var physics_rate := -1
var output := "/tmp/cloud_temporal_aiming.json"
var checks := 0
var failures: Array[String] = []
var records: Array = []
var expect_fixed := false
var clock_usec := 100000000
var camera_initial: Transform3D

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rate="): rate = int(arg.trim_prefix("--rate="))
		if arg.begins_with("--physics-rate="): physics_rate = int(arg.trim_prefix("--physics-rate="))
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg == "--expect-fixed": expect_fixed = true
	Engine.physics_ticks_per_second = physics_rate if physics_rate > 0 else rate
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL: ", label)

func prepare_rally() -> void:
	Input.action_release("ui_accept")
	focus.cancel()
	game.input_handler.cancel_charge_input()
	game._reset_match()
	game._set_game_state(game.GameState.PLAYING)
	var player = game.player_left
	var ball = game.ball
	var human = player.posture.human_contact
	player.global_position = Vector3(0, player.ground_y, 3.2)
	player.current_velocity = Vector3.ZERO
	player.is_jumping = false
	ball.is_in_play = true
	ball.last_hit_by = 1
	ball.flight_id += 1
	ball.bounces_since_last_hit = 0
	ball.both_bounces_complete = true
	ball.global_position = Vector3(0.42, 1.1, 2.2)
	ball.linear_velocity = Vector3(0, 0, 6)
	ball.freeze = false
	human._flight_id = ball.flight_id
	human.phase = -1
	human.footwork.cancel("temporal fixture")
	human.contact = {"point": Vector3(0.42, 1.1, 2.6), "time": 0.4, "bounces": 1, "def": PostureLibrary.instance().all_definitions()[0]}
	human.anticipated_contact = {}
	player.hitting.charge_visual_active = true
	game.aim_controller.reset()
	game.aim_controller.get_target()
	game.aim_controller.mode = "AIM"
	game.aim_controller.planted = true
	game.selected_spin_mode = 0
	game.selected_shot_intent = "AUTO"
	game.trajectory_arc_offset = 0.0
	game.input_handler.serve_charge_time = 0.35 * PickleballConstants.MAX_SERVE_CHARGE_TIME
	camera.global_transform = camera_initial
	Input.action_press("ui_accept")
	clock_usec += 10000000
	focus.begin_hold(clock_usec)
	focus.tick(clock_usec + focus.REACH_ENTER_USEC, true)
	clock_usec += focus.REACH_ENTER_USEC
	focus._last_preview_key = ""
	focus._last_preview_usec = -1000000
	focus._last_estimate = {}
	focus._world_path.clear()
	focus._update_presentation(clock_usec)
	check(focus.active and focus._presentation, "rally fixture active")

func vec2(v: Vector2) -> Array: return [v.x, v.y]
func vec3(v: Vector3) -> Array: return [v.x, v.y, v.z]

func snapshot(t: int) -> Dictionary:
	var path: Array = []
	for p in focus._screen_path: path.append(vec2(p))
	var human = game.player_left.posture.human_contact
	return {"usec":t, "visible":focus._drawing.visible and focus._presentation,
		"dim_visible":focus._dim.visible, "active":focus.active, "mode":game.aim_controller.mode,
		"hint":focus.preview_hint, "hud":game.hud._controls_hint.text,
		"hud_matches_hint":game.hud._controls_hint.text.to_lower().contains(focus.preview_hint.to_lower()),
		"strength":float(focus._material.get_shader_parameter("strength")),
		"solves":focus.preview_solves, "point_count":focus._world_path.size(), "display_point_count":focus._screen_path.size(),
		"aim":vec3(game.aim_controller.get_target()), "highlight":vec2(focus._target_screen),
		"path":path, "contact_valid":not human.contact.is_empty(),
		"cache_key":focus._last_preview_key, "cached_risk":Estimate.risk_label(focus._last_estimate)}

func summarize(name: String, frames: Array, note: String = "") -> Dictionary:
	var visible_toggles := 0
	var dim_toggles := 0
	var label_toggles := 0
	var mode_toggles := 0
	var point_count_toggles := 0
	var display_count_toggles := 0
	var worst_highlight := 0.0
	var worst_path := 0.0
	var worst_input := 0.0
	var path_updates := 0
	var worst_strength := 0.0
	var stale_positive := 0
	var updating_frames := 0
	var hud_mismatch_frames := 0
	for i in frames.size():
		var frame: Dictionary = frames[i]
		if frame.hint == "UPDATING ARC": updating_frames += 1
		if frame.mode == "AIM" and not frame.hud_matches_hint: hud_mismatch_frames += 1
		if not frame.contact_valid and frame.visible and frame.hint == "ESTIMATED ARC": stale_positive += 1
		if i == 0: continue
		var previous: Dictionary = frames[i-1]
		if previous.visible != frame.visible: visible_toggles += 1
		if previous.dim_visible != frame.dim_visible: dim_toggles += 1
		if previous.hint != frame.hint: label_toggles += 1
		if previous.mode != frame.mode: mode_toggles += 1
		if previous.point_count != frame.point_count: point_count_toggles += 1
		if previous.display_point_count != frame.display_point_count: display_count_toggles += 1
		worst_highlight = maxf(worst_highlight, Vector2(frame.highlight[0],frame.highlight[1]).distance_to(Vector2(previous.highlight[0],previous.highlight[1])))
		worst_input = maxf(worst_input, Vector3(frame.aim[0],frame.aim[1],frame.aim[2]).distance_to(Vector3(previous.aim[0],previous.aim[1],previous.aim[2])))
		worst_strength = maxf(worst_strength, absf(frame.strength-previous.strength))
		if previous.solves != frame.solves: path_updates += 1
		if not frame.path.is_empty() and frame.path.size() == previous.path.size():
			for k in frame.path.size():
				worst_path = maxf(worst_path, Vector2(frame.path[k][0],frame.path[k][1]).distance_to(Vector2(previous.path[k][0],previous.path[k][1])))
	var result := {"scenario":name,"note":note,"frames":frames.size(),"duration_seconds":float(frames.back().usec-frames.front().usec)/1000000.0,
		"visible_toggles":visible_toggles,"dim_toggles":dim_toggles,"hint_toggles":label_toggles,"mode_toggles":mode_toggles,
		"point_count_changes":point_count_toggles,"display_point_count_changes":display_count_toggles,"path_update_count":path_updates,"max_highlight_jump_px":worst_highlight,
		"max_equal_index_path_jump_px":worst_path,"max_aim_step_world":worst_input,"max_dim_strength_step":worst_strength,
		"positive_hint_without_contact_frames":stale_positive,"updating_frames":updating_frames,"hud_mismatch_frames":hud_mismatch_frames,"samples":frames}
	records.append(result)
	var brief := result.duplicate(); brief.erase("samples")
	print("TEMPORAL SCENARIO ", JSON.stringify(brief))
	return result

func motion_case(name: String) -> void:
	prepare_rally()
	var frames: Array = []
	var human = game.player_left.posture.human_contact
	var target: Vector3 = game.aim_controller.get_target()
	var contact_point: Vector3 = human.contact.point
	var player_point: Vector3 = game.player_left.global_position
	var end := 3 * rate
	for i in end + 1:
		var t := float(i) / rate
		var now := clock_usec + roundi(t * 1000000.0)
		match name:
			"smooth_aim", "natural_update_order": game.aim_controller.target = target + Vector3(0.7 * sin(t * TAU / 3.0), 0, 0)
			"smooth_contact": human.contact.point = contact_point + Vector3(0.3 * sin(t * TAU / 3.0), 0, 0)
			"smooth_player": game.player_left.global_position = player_point + Vector3(0.3 * sin(t * TAU / 3.0), 0, 0)
			"smooth_camera": camera.global_position = camera_initial.origin + camera.global_basis.x * 0.25 * sin(t * TAU / 3.0)
			"charge_ramp": game.input_handler.serve_charge_time = minf(1.0, 0.1 + t * 0.3) * PickleballConstants.MAX_SERVE_CHARGE_TIME
			"realistic_charge": game.input_handler.serve_charge_time = minf(t, PickleballConstants.MAX_SERVE_CHARGE_TIME)
			"aim_then_stop": game.aim_controller.target = target + Vector3(minf(t,1.0) * 0.5, 0, 0)
		if name == "natural_update_order": game.aim_controller.update(1.0 / rate, true, Vector2.ZERO, true)
		focus._update_presentation(now)
		if name != "natural_update_order": game.hud.set_aim_state("AIM")
		frames.append(snapshot(now))
	var result := summarize(name, frames, "Synthetic monotonic timestamps; actual production projection and estimate solver; frozen physics. Animated dashes excluded from flicker metrics.")
	if name in ["static", "smooth_camera", "smooth_player"]:
		check(result.visible_toggles == 0 and result.hint_toggles == 0 and result.point_count_changes == 0, name + " stable path visibility/meaning")

func missing_contact_case() -> void:
	prepare_rally()
	var contact: Dictionary = game.player_left.posture.human_contact.contact.duplicate()
	var frames: Array = [snapshot(clock_usec)]
	var base := clock_usec
	for i in 2 * rate:
		var now := base + roundi(float(i + 1) * 1000000.0 / rate)
		# Empty for 300 ms. This is deliberately presentation-level: focus gating is tested separately.
		game.player_left.posture.human_contact.contact = {} if i < ceili(0.3 * rate) else contact
		focus._update_presentation(now)
		game.hud.set_aim_state("AIM")
		frames.append(snapshot(now))
	var result := summarize("contact_absent_return_same_key", frames, "Direct presentation/cache boundary; separate reach-mode test covers normal gating. Reveals stale state and cache recovery, not a claim of 2 seconds of visible stale legal state in normal gameplay.")
	result["returned_contact_final_path_points"] = focus._world_path.size()
	result["returned_contact_final_hint"] = focus.preview_hint
	result["recovery_bug_reproduced"] = focus._world_path.is_empty() and not game.player_left.posture.human_contact.contact.is_empty()

func cache_return_variants() -> void:
	for duration_usec in [100000, 266667, 500000]:
		for new_flight in [false, true]:
			prepare_rally()
			var human = game.player_left.posture.human_contact
			var contact: Dictionary = human.contact.duplicate()
			var original_key: String = focus._last_preview_key
			var original_solves: int = focus.preview_solves
			var frames: Array = [snapshot(clock_usec)]
			var count: int = ceili(float(duration_usec) / 1000000.0 * rate)
			for i in count:
				human.contact = {}
				var now := clock_usec + roundi(float(i + 1) * 1000000.0 / rate)
				focus._update_presentation(now)
				frames.append(snapshot(now))
			human.contact = contact
			if new_flight:
				game.ball.flight_id += 1
				human._flight_id = game.ball.flight_id
				# Actual flight gate must invalidate the outgoing estimate on _start.
				var current: int = clock_usec + duration_usec + 1
				focus.tick(current, true)
				focus.tick(current + focus.REACH_ENTER_USEC, true)
			for i in rate:
				var now: int = clock_usec + duration_usec + focus.REACH_ENTER_USEC + roundi(float(i + 1) * 1000000.0 / rate)
				focus._update_presentation(now)
				frames.append(snapshot(now))
			var result := summarize("cache_return_%dms_%s" % [duration_usec/1000,"newflight" if new_flight else "sameflight"],frames,"Presentation/cache boundary fixture. New-flight case executes real focus tick/_start invalidation before re-presentation.")
			result["contact_restored"] = not human.contact.is_empty()
			result["final_path_points"] = focus._world_path.size()
			result["final_hint"] = focus.preview_hint
			result["same_final_key"] = original_key == focus._last_preview_key
			result["additional_solves"] = focus.preview_solves - original_solves
			result["recovery_bug_reproduced"] = focus._world_path.is_empty() and not human.contact.is_empty()

func stale_input_case() -> void:
	prepare_rally()
	var old_label: String = focus.preview_hint
	var start: Vector3 = game.player_left.posture.human_contact.contact.point
	var target: Vector3 = game.aim_controller.get_target()
	game.trajectory_arc_offset = -0.5
	var actual: Dictionary = Estimate.solve(start,target,0.35,game.selected_spin_mode,game.selected_shot_intent,game._pending_shot_type,-0.5)
	var expected := Estimate.risk_label(actual)
	var frames: Array = [snapshot(clock_usec)]
	for i in ceili(0.5 * rate):
		var now := clock_usec + roundi(float(i + 1) * 1000000.0 / rate)
		focus._update_presentation(now)
		game.hud.set_aim_state("AIM")
		frames.append(snapshot(now))
	var result := summarize("arc_control_change",frames,"An input relevant to the cached estimate changes while target/contact coordinates stay unchanged.")
	result["old_risk"] = old_label
	result["new_exact_risk"] = expected
	var wrong := 0
	for frame in frames.slice(1):
		if frame.hint != expected and frame.hint != "UPDATING ARC" and frame.hint != "ARC UNCERTAIN": wrong += 1
	result["nonneutral_old_risk_frames_after_change"] = wrong

func mode_dropout_case() -> void:
	prepare_rally()
	# Wall-clock sampling calls the actual production _process branch, not a reimplementation.
	focus.cancel()
	var base := Time.get_ticks_usec()
	focus.begin_hold(base)
	focus.tick(base + focus.REACH_ENTER_USEC, true)
	focus._update_presentation(base - focus.VISUAL_ENTER_USEC)
	focus._update_presentation(base)
	var frames: Array = []
	for i in 2 * rate:
		var elapsed := float(i) / rate
		# One unreachable controller sample every 300 ms; reach-focus threshold still allows TTC <= 1.0.
		var period_frames := maxi(1, roundi(0.3 * rate))
		game.player_left.posture.human_contact.contact.time = 0.86 if i % period_frames == period_frames - 1 else 0.84
		game.aim_controller.update(1.0 / rate, true, Vector2.ZERO, true)
		focus._process(1.0 / rate)
		game.hud.set_aim_state(game.aim_controller.mode)
		frames.append(snapshot(Time.get_ticks_usec()))
		OS.delay_usec(roundi(1000000.0 / rate))
	var result := summarize("reach_threshold_one_frame_dips",frames,"Actual _process and aim-controller update, controlled contact TTC alternating 0.84/0.86 s. These are just inside/outside the controller's 0.85 s plant threshold; 0.86 is still inside the active-focus 1.0 s exit threshold. Each sampled interval uses real wall time.")
	var active_hidden := 0
	for frame in frames:
		if frame.active and not frame.visible: active_hidden += 1
	result["active_focus_hidden_frames"] = active_hidden

func rapid_press_case() -> void:
	prepare_rally()
	focus.cancel()
	var frames: Array = []
	var base := clock_usec
	var deadline := 0
	for i in 2 * rate:
		var now := base + roundi(float(i) * 1000000.0 / rate)
		var period := maxi(2, roundi(0.25 * rate))
		var press := i % period != period - 1
		if press and not focus.holding: focus.begin_hold(now)
		focus.tick(now,press)
		if focus.active:
			focus._update_presentation(now)
			if deadline == 0: deadline = focus.deadline_usec
			check(focus.deadline_usec == deadline,"repeat HIT preserves same-flight deadline")
		frames.append(snapshot(now))
	summarize("rapid_repeated_hit",frames,"Visible exits after deliberate releases are expected and excluded from unintended-flicker claims. Same-flight deadline must not refill.")

func interrupt_cases() -> void:
	for reason in ["pause","fault","reset"]:
		prepare_rally()
		var before := snapshot(clock_usec)
		match reason:
			"pause": root.get_node("PauseController").open();root.get_node("PauseController").close()
			"fault": game._set_game_state(game.GameState.POINT_SCORED)
			"reset": game._reset_match()
		var after := snapshot(clock_usec+1)
		check(not focus.active and not focus._presentation and not focus._dim.visible, "immediate hard stop " + reason)
		focus.tick(clock_usec+100000,true)
		check(not focus.active,"held input does not revive after " + reason)
		summarize("interrupt_"+reason,[before,after],"Intentional immediate removal; not a flicker. No easing may preserve stale legal feedback on exit.")

func aim_legality_cases() -> void:
	var scenarios: Array = []
	for separate in [false,true]:
		for reason in ["contact_missing","anticipation_only","outgoing","second_bounce","stale_flight","new_flight_current","illegal_volley_feet","airborne","above_ground","footwork_not_ready","queued_contact","reset"]:
			prepare_rally()
			var aim = game.aim_controller
			var human = game.player_left.posture.human_contact
			var before_deadline: int = focus.deadline_usec
			aim.update(0.016,true,Vector2.ZERO,separate)
			check(aim.planted and aim.mode == "AIM", "legal gate starts planted " + reason)
			match reason:
				"contact_missing": human.contact = {}
				"anticipation_only": human.anticipated_contact = human.contact.duplicate();human.contact = {}
				"outgoing": game.ball.last_hit_by = 0
				"second_bounce": game.ball.bounces_since_last_hit = 2
				"stale_flight": human._flight_id -= 1
				"new_flight_current": game.ball.flight_id += 1;human._flight_id = game.ball.flight_id
				"illegal_volley_feet": human.contact.bounces = 0;game.player_left._nvz_state.established_outside = false
				"airborne": game.player_left.is_jumping = true
				"above_ground": game.player_left.global_position.y += 0.05
				"footwork_not_ready": human.footwork.active = true;human.footwork.state = "travel"
				"queued_contact": human.phase = 0
				"reset": game._reset_match()
			aim.update(0.001,true,Vector2.ZERO,separate)
			check(not aim.planted and aim.mode != "AIM", "immediate safety exit " + reason + " separate=" + str(separate))
			focus.tick(clock_usec+1000,true)
			if focus.active: focus._update_presentation(clock_usec+1000)
			check(not focus._presentation or focus.preview_hint != "ESTIMATED ARC", "invalid reach never preserves favorable visible arc " + reason)
			scenarios.append({"reason":reason,"separate_aim":separate,"mode_after":aim.mode,"planted_after":aim.planted,"old_deadline":before_deadline,"deadline_after":focus.deadline_usec})
	for separate in [false,true]:
		prepare_rally()
		var aim = game.aim_controller
		var human = game.player_left.posture.human_contact
		var deadline: int = focus.deadline_usec
		for ttc in [0.85,0.86,0.99,1.0]:
			human.contact.time = ttc
			aim.update(0.001,true,Vector2.ZERO,separate)
			focus.tick(clock_usec+1000,true)
			check(aim.planted and aim.mode == "AIM","already-planted legal horizon " + str(ttc))
			check(focus.deadline_usec == deadline,"hysteresis never refills focus deadline")
		human.contact.time = 1.0001
		aim.update(0.001,true,Vector2.ZERO,separate)
		check(not aim.planted,"horizon strictly above 1.0 exits immediately")
		human.contact.time = 0.86
		aim.update(0.5,true,Vector2.ZERO,separate)
		check(not aim.planted,"new entry still rejects 0.86 TTC")
		human.contact.time = 0.84
		aim.update(0.059,true,Vector2.ZERO,separate)
		check(not aim.planted,"initial entry not before unchanged 60 ms")
		aim.update(0.0011,true,Vector2.ZERO,separate)
		check(aim.planted,"initial entry at unchanged 60 ms")
		var prior: Vector3 = aim.get_target()
		aim.update(0.001,true,Vector2(1,0),true)
		check(aim.get_target().x > prior.x,"independent aim moves immediately inside hysteresis")
	records.append({"scenario":"aim_hysteresis_legality","negative_cases":scenarios,"samples":[]})

func run() -> void:
	root.size=Vector2i(540,960)
	root.content_scale_size=Vector2i(720,1280)
	var pause=root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited):root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered):root.focus_entered.disconnect(pause._on_window_focus_entered)
	game=load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene=game
	for i in 12: await process_frame
	game.process_mode=Node.PROCESS_MODE_DISABLED
	focus=game.aim_focus; focus.set_process(false)
	camera=root.get_camera_3d();camera_initial=camera.global_transform
	check(game.player_left.posture.human_contact != null,"contact fixture ready")
	for scenario in ["static","smooth_aim","smooth_contact","smooth_player","smooth_camera","charge_ramp","natural_update_order","realistic_charge","aim_then_stop"]: motion_case(scenario)
	missing_contact_case()
	cache_return_variants()
	stale_input_case()
	mode_dropout_case()
	rapid_press_case()
	interrupt_cases()
	aim_legality_cases()
	if expect_fixed:
		for record in records:
			if record.scenario == "reach_threshold_one_frame_dips": check(record.dim_toggles == 0, "decorative dim stable across reach threshold")
			if record.has("recovery_bug_reproduced"): check(not record.recovery_bug_reproduced, "cached path recovers: " + record.scenario)
			if record.scenario == "arc_control_change": check(record.nonneutral_old_risk_frames_after_change == 0, "changed arc never retains old non-neutral risk")
			if record.scenario == "contact_absent_return_same_key": check(record.positive_hint_without_contact_frames == 0, "missing contact never retains a favorable estimated arc")
			if record.scenario == "natural_update_order": check(record.hud_mismatch_frames == 0, "HUD gets same-frame fresh preview hint")
	var result := {"scope":"Archived 0.3.25/build28 plus cloud focus/settings work; not current Mac build30/31 acceptance", "sampling_rate_hz":rate,"physics_ticks_per_second":Engine.physics_ticks_per_second,"engine":Engine.get_version_info(),"renderer":DisplayServer.get_name(),"checks":checks,"contract_failures":failures,"records":records,"limits":["Physics frozen for deterministic boundary and projection audits","Native rendered pixels not covered by headless samples","No gray-badge build30/31 source available","Dashed path animation, intentional timing flash, user releases, and hard-stop exits are not labeled unintended flicker"]}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("CLOUD TEMPORAL AIMING: %d checks, %d failures, %d Hz; report %s" % [checks,failures.size(),rate,output])
	Input.action_release("ui_accept");focus.cancel();game.queue_free()
	for i in 3:await process_frame
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	quit(0 if failures.is_empty() else 1)
