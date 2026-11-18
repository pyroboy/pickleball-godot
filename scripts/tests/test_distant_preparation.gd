extends SceneTree


const Fixture = preload("res://scripts/tests/fixtures/distant_preparation_fixture.gd")
const Geometry = preload("res://scripts/paddle_clearance.gd")
const Planner = preload("res://scripts/incoming_contact_planner.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Footwork = preload("res://scripts/charged_footwork.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const AudioTeardown = preload("res://scripts/tests/audio_teardown.gd")
var game
var checks: = 0
var failures: Array[String] = []
var cases: Array = []
var contacts: Array = []
var current_case: = ""
var only: = ""
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(current_case + ": " + message)
func setup(data: Dictionary, solo: bool = false) -> Dictionary:
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	var seed: Dictionary = Fixture.prepare(game, data, solo)
	game.ball.hit_by_paddle.connect(record_contact)
	await physics_frame; await physics_frame
	return seed
func record_contact(team: int) -> void :
	if team != 0: return
	var h = game.player_left.posture.human_contact
	var evidence: Dictionary = h.last_contact_evidence.duplicate()
	evidence["case"] = current_case
	evidence["family"] = h.swing_def.family if h.swing_def else -1
	evidence["posture"] = h.swing_def.posture_id if h.swing_def else -1
	contacts.append(evidence)
	check(evidence.has("raw_paddle") and evidence.has("raw_ball"), "real hit lacks pre-alignment evidence")
	if evidence.has("raw_paddle"):
		var local: Vector3 = evidence.raw_paddle.affine_inverse() * evidence.raw_ball
		check(Geometry.distance_to_head_shape(local) <= Ball.BALL_RADIUS + Geometry.contact_surface_tolerance() + 0.0001, "real return outside raw finite paddle head")
		check(evidence.phase == 1 and evidence.flight == h.swing_flight_id, "real return lost strike/flight ownership")
func teardown() -> void :
	for action in ["move_left", "move_right", "move_up", "move_down"]: Input.action_release(action)
	Fixture.release(game)
	game.queue_free(); await process_frame; await process_frame
func summary(prep: Dictionary) -> Dictionary:
	if prep.is_empty(): return {}
	var result: Dictionary = prep.duplicate()
	result.erase("def")
	result["family"] = prep.def.family
	result["height_tier"] = prep.def.height_tier
	result["paddle_offset"] = Vector3(prep.def.paddle_forehand_mul, prep.def.paddle_y_offset, prep.def.paddle_forward_mul)
	return result
func selected(group: String) -> bool: return only.is_empty() or only == group
func run() -> void :
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): only = arg.trim_prefix("--case=")
	create_timer(160).timeout.connect( func(): quit(2))
	if selected("preparation"):
		for data in Fixture.cases(): await preparation_case(data)
		for side in [1.0, -1.0]:
			await preparation_case({"name": "4m_low_%s" % side, "lateral": 4.0 * side, "height": 0.4, "duration": 1.6, "family": 0 if side > 0 else 1, "low": true})
			await preparation_case({"name": "5m_overhead_%s" % side, "lateral": 5.0 * side, "height": 2.02, "forward": 0.45, "duration": 1.4, "family": 3})
	if selected("manual"):
		await manual_hold(1.0)
		await manual_hold(-1.0)
		await manual_side_retarget()
		await changed_height_retarget()
	if selected("returns"):
		for side in [1.0, -1.0]:
			await manual_return(side, false)
			await manual_return(side, true)
			await manual_return(side, true, {"lateral": 4.0 * side, "name": "4m_normal"})
			await manual_return(side, true, {"lateral": 4.0 * side, "height": 0.4, "name": "4m_low"})
			await manual_return(side, true, {"lateral": 4.0 * side, "height": 2.02, "forward": 0.45, "duration": 1.4, "name": "4m_overhead", "family": 3})
	if selected("negative"):
		await impossible_time()
		await invalid_cases()
	if selected("focus"): await focus_lifecycle()
	if selected("mirror"): await mirrored_preparation()


	await AudioTeardown.drain(self)
	var f = FileAccess.open("/tmp/distant-preparation-evidence%s.json" % ("_" + only if not only.is_empty() else ""), FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks": checks, "failures": failures, "cases": cases, "contacts": contacts}, "\t"));f.close()
	for failure in failures: push_error(failure)
	print("DISTANT PREPARATION: %d checks, %d failures; actual returns=%d" % [checks, failures.size(), contacts.size()])
	quit(0 if failures.is_empty() else 1)
func preparation_case(data: Dictionary) -> void :
	current_case = data.name
	var seed: Dictionary = await setup(data, true)
	var p = game.player_left; var h = p.posture.human_contact
	check(absf(seed.target.x) < PickleballConstants.COURT_WIDTH * 0.5, "fixture contact outside court")
	check(game.ball.global_position.z < 0.0, "fixture ball has crossed net")
	var start: Vector3 = p.global_position
	for frame in range(3): await physics_frame
	check(p.global_position.distance_to(start) < 0.001, "passive anticipation moved player")
	Fixture.press(game)
	check(game.aim_focus.active and Engine.time_scale < 1.0, "Hit did not start immediate solo focus")
	check(p.hitting.charge_visual_active, "Hit did not start charging")
	var prep: Dictionary = h.preparation_contact()
	check( not prep.is_empty(), "distant legal future contact lacks preparation")
	if not prep.is_empty():
		check(prep.def.family == int(data.family), "wrong distant stroke family: " + str(prep.def.family))
		if data.get("low", false): check(prep.def.height_tier <= 1, "low target selected upright/high family")
		if prep.has("target_root"):
			var shifted: Vector3 = prep.point - (prep.target_root - p.global_position)
			check(Planner.point_fits(p, prep.def, shifted), "future pose does not fit prospective translated body")
	check(h.contact.is_empty(), "distant preview acquired current-root physical reach")
	var timing: Dictionary = h.release_timing_state()
	check( not timing.release_ready and not timing.current_reachable and timing.preparation_only, "broad preview falsely enables physical release cue")
	check(timing.time_until_release >= 0.0 and is_equal_approx(timing.time_until_release, maxf(0.0, timing.time - timing.release_lead)), "distant release countdown inconsistent with forecast")
	for frame in range(8): Fixture.tick(game); await physics_frame
	check(h._charge_target_pose != null and h.visual_pose != null, "held Hit failed to prepare a charged pose")
	check(h.visual_pose != null and h.visual_pose.family == int(data.family), "held visual lost predicted family")
	if absf(float(data.lateral)) >= 4.0:
		check( not h.footwork.active and p.global_position.distance_to(start) < 0.001, "broad preview bypassed bounded auto-assist")
	check(contacts.is_empty(), "preparation fabricated distant contact")
	cases.append({"name": current_case, "seed": seed, "first_preparation": summary(prep), "focus": game.aim_focus.active})
	await teardown()
func manual_hold(side: float) -> void :
	current_case = "manual_hold_%s" % side
	await setup({"lateral": 5.0 * side})
	var p = game.player_left; var h = p.posture.human_contact
	Fixture.press(game)
	for frame in range(12): Fixture.tick(game); await physics_frame
	var before_charge: float = h.charge_ratio
	var start: Vector3 = p.global_position
	var action: = "move_right" if side > 0 else "move_left"
	Input.action_press(action)
	var preserved: = true
	var max_turn: = 0.0
	var previous: Basis = Path.paddle_basis(p, h.visual_pose)
	for frame in range(20):
		Fixture.tick(game); await physics_frame
		preserved = preserved and p.hitting.charge_visual_active and h._charge_target_pose != null and h.phase < 0
		if h.visual_pose:
			var basis: Basis = Path.paddle_basis(p, h.visual_pose)
			max_turn = maxf(max_turn, rad_to_deg(previous.get_rotation_quaternion().angle_to(basis.get_rotation_quaternion())))
			previous = basis
	Input.action_release(action)
	check(p.global_position.distance_to(start) > 1.0, "manual stick did not move actual root")
	check( not h.footwork.active, "manual stick retained automatic chase")
	check(preserved and h.charge_ratio > before_charge, "manual movement dropped/restarted held charge")
	check( not h.preparation_contact().is_empty(), "manual travel discarded future preparation")
	check(max_turn <= 12.05, "held manual preparation snapped beyond angular-speed bound")
	var settled: Vector3 = p.global_position
	for frame in range(6): Fixture.tick(game); await physics_frame
	check( not h.footwork.active and p.global_position.distance_to(settled) < 0.001, "same held input silently resumed auto-chase")
	cases.append({"name": current_case, "travel": p.global_position.distance_to(start), "charge_before": before_charge, "charge_after": h.charge_ratio, "max_turn": max_turn, "preparation": summary(h.preparation_contact())})
	await teardown()
func manual_side_retarget() -> void :
	current_case = "manual_cross_body_retarget"
	await setup({"lateral": 4.0, "duration": 1.6})
	var p = game.player_left; var h = p.posture.human_contact
	Fixture.press(game)
	var start: Dictionary = h.preparation_contact().duplicate()
	check( not start.is_empty() and start.def.family == 0, "cross-body fixture did not begin forehand")
	Input.action_press("move_right")
	for frame in range(57): Fixture.tick(game); await physics_frame
	Input.action_release("move_right")
	for frame in range(8): Fixture.tick(game); await physics_frame
	var ending: Dictionary = h.preparation_contact()
	check( not ending.is_empty() and ending.def.family == 1, "moving beyond target did not replan to backhand")
	check(p.hitting.charge_visual_active and h._charge_target_pose != null and h._charge_target_pose.family == 1, "side replan lost held charge or retained forehand pose")
	cases.append({"name": current_case, "first": summary(start), "last": summary(ending), "root": p.global_position})
	await teardown()
func changed_height_retarget() -> void :
	current_case = "same_flight_height_retarget"
	await setup({"lateral": 5.0, "height": 2.02, "forward": 0.45, "duration": 1.4})
	var h = game.player_left.posture.human_contact; var b = game.ball
	Fixture.press(game)
	var initial: Dictionary = h.preparation_contact().duplicate()
	check( not initial.is_empty() and initial.def.family == 3, "height fixture did not begin overhead")

	b.linear_velocity.y -= 0.65
	for frame in range(10): Fixture.tick(game); await physics_frame
	var changed: Dictionary = h.preparation_contact()
	check( not changed.is_empty() and changed.def.height_tier < 3, "height change did not replan future preparation")
	check(game.player_left.hitting.charge_visual_active and h._charge_target_pose != null, "height replan lost held charging")
	cases.append({"name": current_case, "first": summary(initial), "last": summary(changed), "delta_velocity_y": - 0.65})
	await teardown()
func manual_return(side: float, early_release: bool, data: Dictionary = {}) -> void :
	current_case = "%s_%s_%s_return" % [data.get("name", "5m"), "fh" if side > 0 else "bh", "queued" if early_release else "held"]
	if not data.has("lateral"): data["lateral"] = 5.0 * side
	var seed: Dictionary = await setup(data)
	var p = game.player_left; var h = p.posture.human_contact
	var before: = contacts.size()
	Fixture.press(game)
	var prep: Dictionary = h.preparation_contact().duplicate()
	check( not prep.is_empty(), "manual return lacks initial broad preparation")
	if not prep.is_empty(): check(prep.def.family == int(data.get("family", 0 if side > 0 else 1)), "manual return chose wrong initial family")


	var target: Vector3 = prep.get("target_root", Vector3(seed.target.x - side * 0.55, p.ground_y, 4.7))
	var action: = "move_right" if side > 0 else "move_left"
	Input.action_press(action)
	for frame in range(4): Fixture.tick(game); await physics_frame
	if early_release:
		Fixture.release(game)
		check(h.phase == 0 and p.hitting.charge_visual_active, "far release did not retain queued charge")
		check( not h.footwork.active and game.ball.last_hit_by == 1, "far release acquired illegal auto-chase/contact")
	var stayed_queued: = true
	var travelled: = 0.0
	var previous: Vector3 = p.global_position
	var max_step: = 0.0
	var released: = early_release
	var saw_release_ready: = false
	for frame in range(220):
		if side * (target.x - p.global_position.x) <= 0.05: Input.action_release(action)
		Fixture.tick(game); await physics_frame
		var step: float = p.global_position.distance_to(previous)
		max_step = maxf(max_step, step);travelled += step;previous = p.global_position
		if early_release and h.contact.is_empty() and game.ball.last_hit_by == 1 and game.game_state == game.GameState.PLAYING:
			stayed_queued = stayed_queued and h.phase == 0 and p.hitting.charge_visual_active
		if not released and h.release_timing_state().release_ready:
			saw_release_ready = true
			check( not h.contact.is_empty() and absf(p.global_position.y - p.ground_y) < 0.03 and p.current_velocity.length() <= 0.35, "release cue green without grounded actual reach")
			Fixture.release(game);released = true
		if contacts.size() > before or game.game_state != game.GameState.PLAYING: break
	check(travelled > absf(float(data.lateral)) - 1.25, "manual return did not cover distant root travel")
	check(max_step <= p.move_speed / Engine.physics_ticks_per_second + 0.002, "manual root teleported")
	if early_release: check(stayed_queued, "manual stick canceled queued distant charge before contact")
	else: check(saw_release_ready, "grounded physically reachable hold never enabled release cue")
	check(contacts.size() == before + 1, "legal distant manual feed did not produce exactly one finite-paddle return")
	if contacts.size() > before:
		check(contacts.back().family == int(data.get("family", 0 if side > 0 else 1)), "actual strike used wrong anatomical family")
	cases.append({"name": current_case, "seed": seed, "target_root": target, "root": p.global_position, "travel": travelled, "max_step": max_step, "phase": h.phase, "returned": contacts.size() > before, "charge": h.charge_ratio, "preparation": summary(h.preparation_contact())})
	await teardown()
func impossible_time() -> void :
	current_case = "insufficient_time_legal_anticipation"
	await setup({"lateral": 5.0, "duration": 0.75})
	var p = game.player_left; var h = p.posture.human_contact
	var before: = contacts.size(); var start: Vector3 = p.global_position
	Fixture.press(game)
	check( not h.preparation_contact().is_empty(), "too-late legal ball lost presentation-only preparation")
	check( not h.footwork.active, "too-late preview became impossible chase")
	Fixture.release(game)
	for frame in range(110):
		await physics_frame
		if game.game_state != game.GameState.PLAYING: break
	check(contacts.size() == before and game.ball.last_hit_by != 0, "too-late distant ball fabricated hit")
	check(start.distance_to(p.global_position) < 0.001, "too-late ball auto-moved/teleported player")
	cases.append({"name": current_case, "returned": contacts.size() > before, "phase": h.phase})
	await teardown()
func invalid_cases() -> void :
	for mode in ["outgoing", "away", "dead", "second_bounce", "fault", "reset", "out"]:
		current_case = "invalid_" + mode
		await setup({"lateral": 5.0})
		var h = game.player_left.posture.human_contact; var b = game.ball
		Fixture.press(game)
		check( not h.preparation_contact().is_empty(), "invalid fixture never acquired anticipation")
		Fixture.release(game)
		var before: = contacts.size()
		match mode:
			"outgoing": b.last_hit_by = 0
			"away": b.linear_velocity = Vector3(0, 0, -8)
			"dead": b.is_in_play = false
			"second_bounce": b.bounces_since_last_hit = 2
			"fault": game._set_game_state(game.GameState.POINT_SCORED)
			"reset": game._reset_ball()
			"out":
				b.global_position = Vector3(3.7, 0.35, 2.6)
				b.linear_velocity = Vector3(0, -2, 6)
		for frame in range(8): Fixture.tick(game); await physics_frame
		check( not h.footwork.active and h.phase < 0, "invalid flight retained queued/assisted strike")
		check(h.preparation_contact().is_empty(), "invalid flight retained preparation")
		var timing: Dictionary = h.release_timing_state()
		check( not timing.release_ready and timing.time < 0 and timing.time_until_release < 0, "invalid flight retained release countdown/cue")
		check(contacts.size() == before, "invalid flight fabricated contact")
		await teardown()
func focus_lifecycle() -> void :
	current_case = "distant_solo_focus_cap"
	await setup({"lateral": 5.0}, true)
	Fixture.press(game)
	var f = game.aim_focus; var h = game.player_left.posture.human_contact
	check(f.holding and not f.active and not h.preparation_contact().is_empty(), "distant solo press lacks armed focus/preparation")
	var start: int = f.started_usec
	check(f.deadline_usec == 0, "distant preparation spent aim window before lock-in")
	f.tick(start + 6000000, true)
	check(not f.active and not f.exhausted and f.deadline_usec == 0 and is_equal_approx(Engine.time_scale, 1.0), "distant hold consumed a focus deadline")
	check(not f.begin_hold() and game.player_left.hitting.charge_visual_active, "same distant hold restarted or lost charging")
	await teardown()
	current_case = "distant_pvp_realtime"
	await setup({"lateral": 5.0})
	Fixture.press(game)
	check( not game.aim_focus.active and is_equal_approx(Engine.time_scale, 1.0), "PvP distant preparation enabled slow motion")
	check( not game.player_left.posture.human_contact.preparation_contact().is_empty(), "PvP lost distant preparation")
	await teardown()

func mirrored_preparation() -> void :
	for data in [{"lateral": 5.0}, {"lateral": -5.0}, {"lateral": 4.0, "height": 0.4}, {"lateral": -4.0, "height": 0.4}, {"lateral": 5.0, "height": 2.02, "forward": 0.45, "duration": 1.4}]:
		current_case = "mirrored_" + str(data)
		await setup(data)
		var left = game.player_left; var right = game.player_right; var b = game.ball
		var normal: Dictionary = Footwork.select_preparation(left, b, Flight.trace(b.global_position, b.linear_velocity, b.angular_velocity))

		right.global_position = Vector3( - left.global_position.x, right.ground_y, - left.global_position.z)
		right.current_velocity = Vector3.ZERO
		right.leg_ik.feet_initialized = false;right._process(0.0);right.can_volley_from_feet()
		b.global_position = Vector3( - b.global_position.x, b.global_position.y, - b.global_position.z)
		b.linear_velocity = Vector3( - b.linear_velocity.x, b.linear_velocity.y, - b.linear_velocity.z)
		b.last_hit_by = 0
		var mirror: Dictionary = Footwork.select_preparation(right, b, Flight.trace(b.global_position, b.linear_velocity, b.angular_velocity))
		check( not normal.is_empty() and not mirror.is_empty(), "court direction lost broad preparation")
		if not normal.is_empty() and not mirror.is_empty():
			check(normal.posture == mirror.posture and absf(normal.time - mirror.time) < 0.001, "court direction changed family/timing")
			check(normal.target_root.distance_to(Vector3( - mirror.target_root.x, mirror.target_root.y, - mirror.target_root.z)) < 0.001, "prospective root failed court-direction mirror")
		cases.append({"name": current_case, "normal": summary(normal), "mirror": summary(mirror)})
		await teardown()
