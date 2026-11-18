extends SceneTree
## Real serve physics/contact ordering and real wall collisions. Run with
## --fixed-fps 120; physics rates vary independently at 30/60/120 Hz.
var checks := 0
var failures: Array[String] = []
var records: Array = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text)
func frames(count: int) -> void:
	for i in count: await physics_frame; await process_frame
func run() -> void:
	var pause = root.get_node_or_null("PauseController")
	if pause:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
		pause.close()
	paused = false
	create_timer(90, true).timeout.connect(func(): quit(2))
	for hz in [30, 60, 120]:
		Engine.physics_ticks_per_second = hz
		for side in [0, 1]: await serve_case(side, hz)
		await wall_case(hz)
		await rally_case(hz)
	Engine.physics_ticks_per_second = 60
	var file := FileAccess.open("/tmp/split-step-live-events.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "records": records}, "\t")); file.close()
	for failure in failures: push_error(failure)
	print("SPLIT STEP LIVE EVENTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
func serve_case(side: int, hz: int) -> void:
	var g = load("res://scenes/game.tscn").instantiate(); root.add_child(g); current_scene = g
	await frames(2)
	g.input_handler.set_process(false); g.serving_team = side; g._reset_ball()
	g.game_serve.select_serve_style(0)
	await frames(ceili(hz * .4))
	var server = g.player_left if side == 0 else g.player_right
	var receiver = g.player_right if side == 0 else g.player_left
	var split = receiver.pose_controller.split_step
	var server_hops: int = server.pose_controller.split_step.hop_count
	var strikes: int = split.strike_count
	var events: int = split.event_serial
	var contact: Array = []
	g.game_serve.serve_launched.connect(func(team): contact.append({"team": team, "flight": g.ball.flight_id, "receiver_phase": split.phase, "receiver_hops": split.hop_count, "receiver_foot_lift": split.sample().foot_lift}))
	g.game_serve.start_charge(); g.game_serve.tick_charge(.2); g.game_serve.release(.65)
	check(g.game_serve.is_release_pending(), "Serve release queued side%d %dHz" % [side, hz])
	var peak := 0.0; var cue_before_hit := false
	for frame in hz * 2:
		await frames(1)
		peak = maxf(peak, float(split.sample().foot_lift))
		if contact.is_empty() and split.event_serial > events: cue_before_hit = true
		if not contact.is_empty() and split.strike_count > strikes: break
	check(contact.size() == 1, "One real serve contact side%d %dHz" % [side, hz])
	check(cue_before_hit, "Visible serve cue precedes impact side%d %dHz" % [side, hz])
	check(split.strike_count == strikes + 1 and split.event_serial == events + 1, "Serve impact reconciles same split side%d %dHz" % [side, hz])
	check(server.pose_controller.split_step.hop_count == server_hops, "Own serve never hops")
	if not contact.is_empty(): check(split.event_id == contact[0].flight, "Receive event belongs to actual serve flight")
	await frames(ceili(hz * .10))
	check(split.sample().foot_lift == 0.0, "Receiver landed promptly after actual serve")
	if receiver.is_ai and not receiver.ai_brain._perception_ready: check(split.sample().direction == Vector3.ZERO, "Red has no direction before perception")
	var serial: int = split.event_serial
	await frames(ceili(hz * .12))
	check(split.event_serial == serial, "Same serve cannot repeat split")
	g.ball.freeze = true; g.ball.is_in_play = false
	await frames(2)
	check(split.phase == "ready", "Deadball cancels receiver split")
	records.append({"kind": "real_serve", "side": side, "hz": hz, "contacts": contact, "peak_lift": peak, "cue_before_hit": cue_before_hit})
	g.queue_free(); await process_frame
func wall_case(hz: int) -> void:
	var g = load("res://scenes/game.tscn").instantiate(); root.add_child(g); current_scene = g
	await frames(3)
	g.practice_launcher.start_drill("WALL"); await frames(3)
	var wall = g.practice_launcher.wall_practice
	var p = g.player_left
	var split = p.pose_controller.split_step
	var initial: int = split.event_serial
	await frames(ceili(hz * .9))
	check(split.event_serial == initial, "Initial wall feed is not a wall strike %dHz" % hz)
	var evidence: Array = []
	for speed in [7.0, 20.0]:
		g.practice_launcher.repeat_drill(); await frames(3)
		wall._pending_feed = 0.0
		g.ball.freeze = false; g.ball.is_in_play = true
		g.ball.global_position = Vector3(0, 1.5, 1.2)
		g.ball.linear_velocity = Vector3(0, 0, -speed)
		g.ball.last_hit_by = 0; g.ball.wall_return_ready = false; g.ball.flight_id += 1
		if speed == 7.0: Input.action_press("ui_accept")
		var before: int = wall.rebounds; var strike_before: int = split.strike_count
		var events_before: int = split.event_serial; var hops_before: int = split.hop_count
		var peak := 0.0; var visible_peak := 0.0
		for frame in hz:
			await frames(1); peak = maxf(peak, float(split.sample().foot_lift))
			visible_peak = maxf(visible_peak, p.leg_ik.right_foot_smooth.y - p.leg_ik.ANKLE_HEIGHT)
			if wall.rebounds > before and split.strike_count > strike_before: break
		check(wall.rebounds == before + 1, "Physical wall rebound %dHz speed%.0f" % [hz, speed])
		check(split.strike_count == strike_before + 1 and split.event_serial == events_before + 1, "One split event per physical rebound %dHz speed%.0f" % [hz, speed])
		if speed >= 20: check(split.hop_count == hops_before, "Late fast wall cue skips hop")
		else: check(visible_peak > .01, "Held Hit early-ready actually lifts planted feet before wall strike %dHz" % hz)
		evidence.append({"speed": speed, "peak_lift": peak, "visible_peak": visible_peak, "held_ready": speed == 7.0, "hops": split.hop_count - hops_before, "reason": split.reason})
		await frames(ceili(hz * .10))
		check(split.sample().foot_lift == 0.0, "Wall split landed promptly")
		Input.action_release("ui_accept")
	# Pause notification cancels state even though game physics stops ticking.
	split.update(.01, {"cue_id": g.ball.flight_id + 100, "cue_lead": .15}); split.update(.07, {})
	paused = true; await process_frame
	check(split.phase == "ready", "Pause cancels timing without a physics advance")
	paused = false; g.practice_launcher.stop_practice(); await frames(2)
	check(split.sample().foot_lift == 0.0, "Wall exit cannot retain airborne pose")
	records.append({"kind": "physical_wall", "hz": hz, "events": evidence})
	g.queue_free(); await process_frame

func rally_case(hz: int) -> void:
	var g = load("res://scenes/game.tscn").instantiate(); root.add_child(g); current_scene = g
	await frames(2)
	g.input_handler.set_process(false); g.serving_team = 0; g._reset_ball()
	await frames(ceili(hz * .4))
	var blue = g.player_left; var red = g.player_right
	var returns: Array = []
	g.ball.hit_by_paddle.connect(func(team):
		if team == 1: returns.append({"flight": g.ball.flight_id, "blue_phase": blue.pose_controller.split_step.phase, "cue": blue.pose_controller.split_observer.last_context.get("cue_source", "") }))
	g.game_serve.start_charge(); g.game_serve.tick_charge(.2); g.game_serve.release(.65)
	var blue_events: int = blue.pose_controller.split_step.event_serial
	var read_frames := 0; var blue_peak := 0.0; var first_cue: Dictionary = {}
	for frame in hz * 6:
		await frames(1)
		var split = red.pose_controller.split_step
		if not red.ai_brain._perception_ready:
			read_frames += 1
			check(split.sample().direction == Vector3.ZERO, "Natural Red receive has no directional push before delayed read")
		if first_cue.is_empty() and blue.pose_controller.split_observer.last_context.has("cue_id"):
			first_cue = blue.pose_controller.split_observer.last_context.duplicate()
			first_cue["phase"] = blue.pose_controller.split_step.phase
			first_cue["reason"] = blue.pose_controller.split_step.reason
			first_cue["serve"] = blue.hitting.serving_visual_active
		blue_peak = maxf(blue_peak, float(blue.pose_controller.split_step.sample().foot_lift))
		if not returns.is_empty() and blue.pose_controller.split_step.strike_count > 0: break
	check(returns.size() == 1, "Natural AI finite-paddle return %dHz" % hz)
	check(read_frames > 0, "Actual delayed Red perception was exercised")
	if not returns.is_empty():
		check(blue.pose_controller.split_step.event_serial == blue_events + 1, "One Blue receive split on actual Red return %dHz" % hz)
		check(blue.pose_controller.split_step.event_id == returns[0].flight, "Rally split reconciles physical strike flight")
	records.append({"kind": "natural_rally", "hz": hz, "returns": returns, "blue_peak_lift": blue_peak, "blue_hops": blue.pose_controller.split_step.hop_count, "first_cue": first_cue, "reason": blue.pose_controller.split_step.reason})
	g.queue_free(); await process_frame
