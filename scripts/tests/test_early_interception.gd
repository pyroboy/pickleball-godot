extends SceneTree


const Fixture = preload("res://scripts/tests/fixtures/charged_footwork_fixture.gd")
const Geometry = preload("res://scripts/paddle_clearance.gd")
var game
var checks: = 0
var failures: Array[String] = []
var cases: Array = []
var contacts: Array = []
var current_case: = ""
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(current_case + ": " + message)
func setup(data: Dictionary) -> void :
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	Fixture.configure(game);Fixture.prepare(game, data)
	game.ball.hit_by_paddle.connect(record_contact)
	await physics_frame; await physics_frame
func record_contact(team: int) -> void :
	if team != 0: return
	var h = game.player_left.posture.human_contact
	var row: Dictionary = h.last_contact_evidence.duplicate();row["case"] = current_case;contacts.append(row)
	check(row.has("raw_paddle") and row.has("raw_ball"), "real contact lacks pre-alignment evidence")
	if row.has("raw_paddle"):
		check(Geometry.distance_to_head_shape(row.raw_paddle.affine_inverse() * row.raw_ball) <= Ball.BALL_RADIUS + Geometry.contact_surface_tolerance() + 0.0001, "separated paddle returned ball")
		check(row.flight == h.swing_flight_id and row.phase == 1, "contact lost flight/strike ownership")
func teardown() -> void :
	Fixture.release(game);game.queue_free(); await process_frame; await process_frame
func run() -> void :
	create_timer(75).timeout.connect( func(): quit(2))
	await early_case(false)
	await early_case(true)
	await early_case(true, true)
	await recovery_hold(false)
	await recovery_hold(true)
	await recovery_hold(false, true)
	await negative_cases()
	await stable_families()
	await boundary_retarget()
	await intent_release_cases()
	var f = FileAccess.open("/tmp/early-interception-evidence.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks": checks, "failures": failures, "cases": cases, "contacts": contacts}, "\t"));f.close()
	for failure in failures: push_error(failure)
	print("EARLY INTERCEPTION: %d checks, %d failures; actual returns=%d" % [checks, failures.size(), contacts.size()])
	quit(0 if failures.is_empty() else 1)
func early_case(quick_release: bool, long_lob: bool = false) -> void :
	current_case = "long_lob_early_release" if long_lob else ("opposite_net_tap" if quick_release else "passive_opposite_net")
	var data: Dictionary = Fixture.cases()[1].duplicate()
	if long_lob: data.root_z = 5.7;data.duration = 2.55
	await setup(data)
	var p = game.player_left; var h = p.posture.human_contact; var b = game.ball
	var prep: Dictionary = h.preparation_contact().duplicate()
	check( not prep.is_empty(), "future contact not detected while ball opposite net")
	check(h.contact.is_empty(), "fixture should require a future root rather than current reach")
	check( not h.footwork.active, "prediction moved root without held Hit")
	var start: Vector3 = p.global_position
	var row: Dictionary = {"name": current_case, "first_ball": b.global_position, "first_distance": p.global_position.distance_to(b.global_position), "first_ttc": prep.get("time", -1), "first_posture": prep.get("posture", -1)}
	for frame in range(8): await physics_frame
	check(start.distance_to(p.global_position) < 0.001, "passive prediction auto-moved player")
	check( not h.anticipation_path.is_empty() and h.anticipation_path.size() <= 47, "cached flight path missing or unbounded")
	check(h.visual_pose != null and h.visual_pose.posture_id == prep.get("posture", -1), "early body has not selected future pose")
	Fixture.press(game)
	check(game._pending_auto_shot_type != "SMASH", "high airborne ball chose smash despite waist-height future contact")
	if not quick_release:
		for frame in range(12): Fixture.tick_input(game); await physics_frame
	Fixture.release(game)
	check(h.phase == 0 and h.footwork.active, "far release lost cached future interception")
	check(b.last_hit_by == 1, "early release fabricated distant hit")
	var before: = contacts.size()
	for frame in range(190):
		await physics_frame
		if contacts.size() > before or game.game_state != game.GameState.PLAYING: break
	row["returned"] = contacts.size() > before;cases.append(row)
	if row.returned:
		check(h.preparation_contact().is_empty() and not p.posture._ball_incoming, "successful outgoing flight retained incoming preparation")
	check(row.returned, "early input did not return live feed")
	await teardown()
func recovery_hold(delayed: bool, solo: bool = false) -> void :
	current_case = "preheld_after_real_recovery" if delayed else "preheld_during_real_finish"
	await setup(Fixture.cases()[0])
	Fixture.press(game)
	for frame in range(12): Fixture.tick_input(game); await physics_frame
	Fixture.release(game)
	var h = game.player_left.posture.human_contact
	var before: = contacts.size()
	for frame in range(170):
		await physics_frame
		if contacts.size() > before: break
	check(contacts.size() > before and h.phase >= 2, "first real return did not reach finish")
	if solo:
		game.pvp_mode = false;game.aim_focus._sync_realtime_mode()
	Fixture.press(game)
	var original_focus_start: int = game.aim_focus.started_usec
	if solo: check(game.aim_focus.holding and not game.aim_focus.active and game.aim_focus.deadline_usec == 0, "recovery hold did not arm without spending next incoming window")
	check(game.input_handler._deferred_rally_hold, "new held Hit was discarded during previous finish")
	if delayed:
		for frame in range(100):
			Fixture.tick_input(game); await physics_frame
			if h.phase < 0: break
		check(h.phase < 0, "previous strike did not finish recovery")
	var p = game.player_left; var b = game.ball
	var target: Vector3 = p.global_position + p._get_forehand_axis() * -1.0 + p._get_forward_axis() * 0.7;target.y = 1.1
	var origin: = Vector3(target.x * 0.35, 1.1, -2.4)
	var launch: Dictionary = game.practice_launcher.solve_airborne_feed(origin, target, 1.75)
	b.global_position = origin;b.linear_velocity = launch.velocity;b.angular_velocity = launch.omega;b.is_in_play = true
	b.hit_by_player(1)
	before = contacts.size()
	for frame in range(12): Fixture.tick_input(game); await physics_frame
	check(game.input_handler.serve_is_charging and p.hitting.charge_visual_active, "pre-held next flight never started charge")
	check(h.phase < 0 and not h.preparation_contact().is_empty(), "new flight inherited old swing or lacks early pose")
	if solo:
		check(game.aim_focus.holding and game.aim_focus.started_usec == original_focus_start, "promoting deferred hold restarted the physical hold")
		if game.aim_focus.active:
			check(game.aim_controller.mode == "AIM" and game.aim_focus.deadline_usec > original_focus_start, "incoming focus lacks reachable AIM deadline")
		else:
			check(game.aim_focus.deadline_usec == 0, "unlocked deferred hold consumed next flight window")
		check(not game.aim_focus.begin_hold(), "same deferred hold restarted focus")
	Fixture.release(game)
	for frame in range(190):
		await physics_frame
		if contacts.size() > before or game.game_state != game.GameState.PLAYING: break
	check(contacts.size() == before + 1, "held-before-opponent-strike did not return exactly once")
	cases.append({"name": current_case, "returned": contacts.size() == before + 1})
	await teardown()
func negative_cases() -> void :
	for mode in ["outgoing", "away", "dead", "second_bounce", "manual", "changed_flight", "active_away", "stale_preview"]:
		current_case = "negative_" + mode
		await setup(Fixture.cases()[1])
		var p = game.player_left; var h = p.posture.human_contact; var b = game.ball
		var before: = contacts.size()
		if mode in ["manual", "changed_flight", "active_away"]:
			Fixture.press(game)
			for frame in range(8): Fixture.tick_input(game); await physics_frame
			check(h.footwork.active, "negative fixture did not acquire route")
			if mode == "manual": Input.action_press("move_left")
			elif mode == "active_away": b.linear_velocity = Vector3(0, 0, -8)
			else: b.flight_id += 1
		else:
			match mode:
				"outgoing": b.last_hit_by = 0
				"away": b.linear_velocity = Vector3(0, 0, -8)
				"dead": b.is_in_play = false
				"second_bounce": b.bounces_since_last_hit = 2
				"stale_preview":
					Fixture.press(game);b.flight_id += 1;Fixture.release(game)
					check(h.phase < 0 and not h.footwork.active, "release consumed stale previous-flight prediction")
		for frame in range(8): Fixture.tick_input(game); await physics_frame
		check( not h.footwork.active, "invalid/interrupted flight retained assisted movement")
		if mode in ["outgoing", "away", "dead", "second_bounce"]: check(h.preparation_contact().is_empty(), "invalid incoming flight retained prediction")
		Input.action_release("move_left");Fixture.release(game)
		check(contacts.size() == before, "negative case manufactured return")
		await teardown()
func stable_families() -> void :
	for id in [0, 2, 3, 4, 5, 7, 10, 11, 12, 13, 14, 16, 17, 18, 19]:
		current_case = "early_family_%d" % id
		await setup(Fixture.cases()[0])
		var p = game.player_left; var h = p.posture.human_contact; var b = game.ball
		var def: PostureDefinition = PostureLibrary.instance().get_def(id)
		p.global_position = Vector3(0, p.ground_y, 3.3);p.leg_ik.feet_initialized = false;p._process(0);p.can_volley_from_feet()
		var target: Vector3 = p.global_position + def.resolve_paddle_offset(p._get_forehand_axis(), p._get_forward_axis())
		target.y = maxf(target.y, p.COURT_FLOOR_Y + def.paddle_floor_clearance + 0.035)
		var origin: = Vector3(target.x, 1.1, -1.2)
		var launch: Dictionary = game.practice_launcher.solve_airborne_feed(origin, target, 0.9)
		b.global_position = origin;b.linear_velocity = launch.velocity;b.angular_velocity = launch.omega;b.flight_id += 1
		await physics_frame; await physics_frame
		var initial: Dictionary = h.preparation_contact().duplicate()
		check(initial.get("posture", -1) == id, "wrong early authored pose")
		check(float(initial.get("time", 0)) > 0.75 and b.global_position.z < 0, "detected only after near approach")
		var before: = contacts.size(); var selected: Array = []
		Fixture.press(game)
		for frame in range(10):
			Fixture.tick_input(game); await physics_frame
			var c: Dictionary = h.preparation_contact()
			if not c.is_empty() and (selected.is_empty() or selected.back() != c.posture): selected.append(c.posture)
		check(selected == [id], "stable feed hunted between pose families: " + str(selected))
		Fixture.release(game)
		for frame in range(100):
			await physics_frame
			if contacts.size() > before or game.game_state != game.GameState.PLAYING: break
		check(contacts.size() == before + 1, "authored early pose did not return actual ball")
		cases.append({"name": current_case, "first_posture": initial.get("posture", -1), "first_ttc": initial.get("time", 0), "selection_sequence": selected, "returned": contacts.size() > before})
		await teardown()

func boundary_retarget() -> void :
	current_case = "low_floor_boundary_retarget"
	await setup(Fixture.cases()[0])
	var p = game.player_left; var h = p.posture.human_contact; var b = game.ball
	var def: PostureDefinition = PostureLibrary.instance().get_def(5)
	p.global_position = Vector3(0, p.ground_y, 3.3);p.leg_ik.feet_initialized = false;p._process(0);p.can_volley_from_feet()
	var target: Vector3 = p.global_position + def.resolve_paddle_offset(p._get_forehand_axis(), p._get_forward_axis())
	var origin: = Vector3(target.x, 1.1, -1.2)
	var launch: Dictionary = game.practice_launcher.solve_airborne_feed(origin, target, 0.9)
	b.global_position = origin;b.linear_velocity = launch.velocity;b.angular_velocity = launch.omega;b.flight_id += 1
	await physics_frame; await physics_frame
	check(h.contact.get("posture", -1) == 5, "boundary feed did not start low")
	Fixture.press(game)
	var before: = contacts.size(); var switched: = false; var max_turn: = 0.0
	var previous: Basis = load("res://scripts/stroke_swing_path.gd").paddle_basis(p, h.visual_pose)
	for frame in range(15):
		if frame == 3:
			check(h.contact.get("posture", -1) == 5, "accurate boundary prediction drifted before flight changed")


			b.linear_velocity.y -= 0.12
		Fixture.tick_input(game); await physics_frame
		var c: Dictionary = h.preparation_contact()
		if not c.is_empty():
			switched = switched or int(c.posture) == 13
			check(c.point.y >= p.COURT_FLOOR_Y + c.def.paddle_floor_clearance, "retarget preserved invalid floor-clearance contact")
		var current: Basis = load("res://scripts/stroke_swing_path.gd").paddle_basis(p, h.visual_pose)
		max_turn = maxf(max_turn, rad_to_deg(previous.get_rotation_quaternion().angle_to(current.get_rotation_quaternion())))
		previous = current
	check(switched, "boundary invalidation did not retarget a legal earlier pose")
	check(max_turn <= 12.05, "retarget exceeded preparation angular-speed bound")
	Fixture.release(game)
	for frame in range(100):
		await physics_frame
		if contacts.size() > before or game.game_state != game.GameState.PLAYING: break
	check(contacts.size() == before + 1, "legal retarget did not produce actual return")
	cases.append({"name": current_case, "retargeted": switched, "controlled_velocity_y_change": - 0.12, "max_turn_degrees_per_tick": max_turn, "returned": contacts.size() > before})
	await teardown()

func intent_release_cases() -> void :
	for overhead in [false, true]:
		for close in [false, true]:
			current_case = ("overhead" if overhead else "high_now_waist_later") + ("_close_release" if close else "_early_release")
			var data: Dictionary = Fixture.cases()[1].duplicate()
			if overhead: data = {"root_z": 4.7, "lateral": - 0.02, "height": 2.02, "forward": 0.45, "duration": 1.4}
			await setup(data)
			var h = game.player_left.posture.human_contact; var b = game.ball
			game.selected_spin_mode = ShotProfile.Mode.FLAT
			game.selected_shot_intent = "AUTO"

			for frame in range(8): await physics_frame
			Fixture.press(game)
			check(game._pending_auto_shot_type == ("SMASH" if overhead else "GROUNDSTROKE"), "press intent used airborne height/speed instead of future contact")
			var before: = contacts.size()
			for frame in range(120):
				Fixture.tick_input(game); await physics_frame
				var prep: Dictionary = h.preparation_contact()
				if not close and frame >= 10: break
				if close and not prep.is_empty() and float(prep.time) < 0.3 and h.footwork.ready_to_strike(): break
			Fixture.release(game)
			check(game._pending_shot_type == ("SMASH" if overhead else "GROUNDSTROKE"), "release intent disagrees with current future contact")
			for frame in range(170):
				await physics_frame
				if contacts.size() > before or game.game_state != game.GameState.PLAYING: break
			check(contacts.size() == before + 1, "intent regression did not return actual ball")
			check(game.last_shot_profile.get("shot_type", "") == ("SMASH" if overhead else "GROUNDSTROKE"), "outgoing solver used wrong predicted-contact profile")
			if close and not overhead:
				check(float(game.last_shot_profile.get("charge", 0)) >= 0.99 and int(game.last_shot_profile.get("mode", -1)) == 0, "full-charge flat-drive positive missing full power/flat mode")
			check(game.last_shot_profile.get("shot_type", "") == ("SMASH" if overhead else "GROUNDSTROKE"), "actual launch profile disagrees with receiving contact")
			check(game.last_shot_profile.get("mode", -1) == ShotProfile.Mode.FLAT, "flat input changed spin mode")
			if close and not overhead: check(float(game.last_shot_profile.get("charge", 0)) >= 0.95, "close waist-drive case was not full charged")
			cases.append({"name": current_case, "returned": contacts.size() > before, "shot_type": game.last_shot_profile.get("shot_type", "")})
			await teardown()
