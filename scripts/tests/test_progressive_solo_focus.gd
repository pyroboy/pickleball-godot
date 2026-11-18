extends SceneTree


var game
var checks: = 0
var failures: Array[String] = []
var evidence: Array = []
var frame_observer: Node
class FrameObserver extends Node:
	signal observed
	func _process(_delta: float) -> void : observed.emit()
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func release_input() -> void :
	Input.action_release("ui_accept")
	game.aim_focus.end_hold()
	game.input_handler.cancel_charge_input()
func deterministic() -> void :
	var focus = game.aim_focus
	var input = game.input_handler
	focus.set_process(false);input.set_process(false)
	release_input();game._reset_match()
	var start: int = Time.get_ticks_usec()
	Input.action_press("ui_accept")
	check(focus.begin_hold(start), "fresh solo press rejected")
	check(focus.deadline_usec - start == 4000000, "focus cap is not four real seconds")
	check(is_equal_approx(Engine.time_scale, 0.6), "press did not immediately enter initial progressive scale")
	check(focus.has_method("scale_for_elapsed"), "focus lacks timestamp-derived progressive curve")
	if not focus.has_method("scale_for_elapsed"):
		release_input();return
	var previous: = 1.0
	var rows: Array = []
	for elapsed in [0, 500000, 1000000, 2000000, 3000000, 3500000, 3999999]:
		focus.tick(start + elapsed, true)
		var expected: float = 0.6 - 0.48 * pow(float(elapsed) / 4000000.0, 2.0)
		check(focus.active and absf(Engine.time_scale - expected) < 1e-06, "wrong active scale at %dus" % elapsed)
		check(Engine.time_scale < previous, "focus did not become progressively slower")
		previous = Engine.time_scale
		rows.append({"elapsed_usec": elapsed, "scale": Engine.time_scale})
	var earlier_drop: float = focus.scale_for_elapsed(2000000) - focus.scale_for_elapsed(3000000)
	var final_drop: float = focus.scale_for_elapsed(3000000) - focus.scale_for_elapsed(4000000)
	check(final_drop > earlier_drop and is_equal_approx(focus.scale_for_elapsed(4000000), 0.12), "final second does not have strongest slowing")
	focus.tick(start + 4000000, true)
	check( not focus.active and focus.holding and focus.exhausted and is_equal_approx(Engine.time_scale, 1.0), "four-real-second boundary did not restore normal time")
	check( not focus.begin_hold(start + 4100000), "same held input restarted after cap")
	focus.tick(start + 9000000, true)
	check( not focus.active and is_equal_approx(Engine.time_scale, 1.0), "long held tail reentered focus")
	evidence.append({"case": "deterministic_curve", "samples": rows})
	release_input()
	check(focus.begin_hold(start + 10000000), "fresh hold after release could not restart")
	check(focus.deadline_usec == start + 14000000 and is_equal_approx(Engine.time_scale, 0.6), "fresh hold inherited old timer or curve")
	focus.tick(start + 13500000, true)
	focus.tick(start + 13500001, false)
	check( not focus.active and not focus.holding and is_equal_approx(Engine.time_scale, 1.0), "release in final second did not immediately restore normal time")


	check(input.has_method("_control_delta"), "input has no independent unscaled focus clock")
	if input.has_method("_control_delta"):
		focus.begin_hold(start)
		input._control_delta(0.01, start + 3000000)
		focus.tick(start + 3500000, true)
		check(is_equal_approx(input._control_delta(0.165, start + 3500000), 0.5), "curve update changed unscaled charge/aim delta")
		check(is_zero_approx(input._control_delta(0.165, start + 3500000)), "same real interval consumed twice")
		focus.tick(start + 4000000, true)
		check(is_equal_approx(input._control_delta(0.11625, start + 4000000), 0.5), "cap frame used old scaled delta for charge/aim")
		focus.cancel()
		check(is_equal_approx(input._control_delta(0.02, start + 6000000), 0.02), "interruption carried paused wall time into controls")
		focus.begin_hold(start + 8000000)
		check(is_equal_approx(input._control_delta(0.02, start + 8100000), 0.1), "fresh focus charged time before its physical press")
		release_input()

	var peer: = ENetMultiplayerPeer.new()
	peer.set_bind_ip("127.0.0.1")
	var peer_error: int = peer.create_server(0, 1)
	check(peer_error == OK, "network-only fixture could not start loopback peer")
	if peer_error == OK:
		game.multiplayer.multiplayer_peer = peer
		check( not focus.begin_hold(), "network session permitted solo focus")
		root.get_node("TimeScale").request_hitstop(0.2, 0.1)
		check(is_equal_approx(Engine.time_scale, 1.0), "network session did not remain realtime")
		game.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		peer.close();focus._sync_realtime_mode()
	focus.set_process(true);input.set_process(true)
func live_hold(fps: int) -> void :
	release_input();game._reset_match()
	Engine.max_fps = fps
	for frame in 4: await process_frame
	Input.action_press("ui_accept")
	var pressed: int = Time.get_ticks_usec()
	var focus = game.aim_focus
	var saw_active: = false
	var sample_rows: Array = []
	var next_sample: = 0
	var first_capped: = 0
	var max_frame_usec: = 0
	var last: int = pressed
	var before_cap_scale: = 1.0
	var charge_checked: = false
	while Time.get_ticks_usec() - pressed < 6000000:
		await frame_observer.observed
		var now: int = Time.get_ticks_usec()
		max_frame_usec = maxi(max_frame_usec, now - last);last = now
		if focus.active:
			saw_active = true
			var elapsed: int = now - focus.started_usec
			check(Engine.time_scale <= before_cap_scale + 1e-06, "%dfps live focus accelerated during hold" % fps)
			before_cap_scale = Engine.time_scale
			if elapsed >= next_sample:
				sample_rows.append({"elapsed_real_ms": elapsed / 1000.0, "scale": Engine.time_scale})
				next_sample += 500000
			if not charge_checked and elapsed >= 200000 and elapsed < 650000:
				var charge: float = game.input_handler.serve_charge_time
				var expected: float = elapsed / 1000000.0
				check(absf(charge - expected) <= max_frame_usec / 1000000.0 + 0.025, "%dfps charge is not real-clock paced" % fps)
				check(absf(charge - game.game_serve.get_charge_ratio() * PickleballConstants.MAX_SERVE_CHARGE_TIME) < 1e-05, "%dfps input/service clocks diverged" % fps)
				charge_checked = true
		elif focus.exhausted and focus.holding:
			first_capped = now
			break
	check(saw_active and charge_checked and first_capped > 0, "%dfps missing active/charge/cap evidence" % fps)
	if first_capped > 0:
		var elapsed: int = first_capped - focus.started_usec
		check(elapsed >= 4000000, "%dfps focus ended before four real seconds" % fps)
		check(elapsed <= 4000000 + max_frame_usec * 2 + 30000, "%dfps cap exceeded frame-observation tolerance" % fps)
		check(is_equal_approx(Engine.time_scale, 1.0) and not focus.begin_hold(), "%dfps capped hold restarted or retained slow motion" % fps)
		var until: int = Time.get_ticks_usec() + 300000
		while Time.get_ticks_usec() < until:
			await frame_observer.observed
			check( not focus.active and is_equal_approx(Engine.time_scale, 1.0), "%dfps held tail retained slow motion" % fps)
		evidence.append({"case": "live_hold", "max_fps": fps, "observed_cap_real_ms": elapsed / 1000.0, "maximum_frame_ms": max_frame_usec / 1000.0, "samples": sample_rows})
	release_input()
	check(is_equal_approx(Engine.time_scale, 1.0), "%dfps release retained slow motion" % fps)
func run() -> void :
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	game.reaction_button.auto_fire_on_perfect = false
	frame_observer = FrameObserver.new();frame_observer.process_priority = 100;root.add_child(frame_observer)
	deterministic()
	if failures.is_empty():
		await live_hold(60)
		await live_hold(10)
	Engine.max_fps = 0
	var output = FileAccess.open("/tmp/progressive-solo-focus-evidence.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures, "cases": evidence}, "\t"));output.close()
	for failure in failures: push_error(failure)
	print("PROGRESSIVE SOLO FOCUS: %d checks, %d failures" % [checks, failures.size()])
	print("FOCUS_TIMING_EVIDENCE " + JSON.stringify(evidence))
	game.queue_free(); await process_frame; await process_frame
	quit(0 if failures.is_empty() else 1)
