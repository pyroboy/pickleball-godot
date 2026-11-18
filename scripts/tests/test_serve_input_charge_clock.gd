extends SceneTree
const PaddleDimensions = preload("res://scripts/paddle_dimensions.gd")
const Hand = preload("res://scripts/player_hand_presentation.gd")
var game
var checks: = 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
var rows: Array = []
var released: Dictionary = {}
func _initialize(): call_deferred("run")
func touch(down: bool) -> void :
	var e: = InputEventScreenTouch.new();e.index = 7;e.position = game.mobile_controls._charge_center;e.pressed = down
	game.mobile_controls._input(e)
func snapshot() -> Dictionary:
	var p = game.player_left
	var tr: Transform3D = p.paddle_node.global_transform
	var pose = p.posture.capture_displayed_pose()
	return {"input_ratio": game.input_handler.serve_charge_time / PickleballConstants.MAX_SERVE_CHARGE_TIME, "service_ratio": game.game_serve.get_charge_ratio(), "pose_charge": p.posture.transition_pose_blend.get_meta("serve_phase_charge", -1), "visual_seconds": game.game_serve.held_hit_seconds, "grip": tr.origin, "head": tr * PaddleDimensions.HEAD_OFFSET, "rotation": tr.basis.get_rotation_quaternion(), "body": p.body_pivot.global_transform, "cup": Hand.ball_center(p.left_arm_node), "palm_gap": Hand.ball_surface_gap(p.left_arm_node, game.ball.global_position, Ball.BALL_RADIUS), "ball": game.ball.global_position, "scale": Engine.time_scale, "pitch": pose.body_pitch_deg, "torso_pitch": pose.torso_pitch_deg}
func release_phase(phase: String, _style: int) -> void :
	if phase == "RELEASE": released = snapshot()
func run() -> void :
	root.content_scale_size = Vector2i(720, 1560);root.size = Vector2i(720, 1560)
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	game.reaction_button.auto_fire_on_perfect = false
	game.game_serve.serve_phase_changed.connect(release_phase)
	for kind in ["touch", "desktop", "touch_pvp", "desktop_pvp"]:
		game._reset_match();game.game_serve.select_serve_style(0)
		game.pvp_mode = kind.ends_with("pvp");game.aim_focus._sync_realtime_mode()
		for frame in 20: await process_frame
		if kind.begins_with("touch"): touch(true)
		else: Input.action_press("ui_accept")
		var start: int = Time.get_ticks_usec(); var max_gap: = 0.0
		while Time.get_ticks_usec() - start < 280000:
			await process_frame
			max_gap = maxf(max_gap, absf(game.input_handler.serve_charge_time / PickleballConstants.MAX_SERVE_CHARGE_TIME - game.game_serve.get_charge_ratio()))
		var before: Dictionary = snapshot();released = {}
		if kind.begins_with("touch"): touch(false)
		else: Input.action_release("ui_accept")
		for frame in 4:
			await process_frame
			if not released.is_empty(): break
		var row: Dictionary = {"input": kind, "before": before, "synchronous_release": released, "max_clock_ratio_gap": max_gap, "hold_real_ms": (Time.get_ticks_usec() - start) / 1000.0}
		if not released.is_empty():
			row["head_step_m"] = before.head.distance_to(released.head)
			row["grip_step_m"] = before.grip.distance_to(released.grip)
			row["paddle_rotation_step_deg"] = rad_to_deg(before.rotation.angle_to(released.rotation))
			row["cup_step_m"] = before.cup.distance_to(released.cup)
			row["committed_charge"] = game.game_serve._pending_release.charge
			check(absf(before.input_ratio - row.committed_charge) < 1e-05, kind + " release changed input-owned charge")
			check(absf(before.pose_charge - smoothstep(0.0, 0.6, before.visual_seconds)) < 1e-05, kind + " held pose ignores its separate visual clock")
			check(absf(before.pose_charge - released.pose_charge) < 1e-05, kind + " release changed held visual preparation")
			check(row.head_step_m < 0.002, kind + " discontinuous held-to-release paddle head")
			check(row.paddle_rotation_step_deg < 0.1, kind + " discontinuous held-to-release paddle orientation")
			check(row.cup_step_m < 0.002, kind + " release jumped held cup")
		check( not released.is_empty(), kind + " actual input did not release serve")
		check(max_gap < 1e-05, kind + " input and service charge clocks diverged")
		check(before.input_ratio > 0.4 and before.input_ratio < 0.85, kind + " short hold did not measure partial charge")
		check((is_equal_approx(before.scale, 1.0) if game.pvp_mode else before.scale <= game.aim_focus.START_FOCUS_SCALE and before.scale >= game.aim_focus.END_FOCUS_SCALE), kind + " wrong held time scale")
		check(is_equal_approx(Engine.time_scale, 1.0) and not game.aim_focus.active, kind + " release retained slow motion")
		rows.append(row)
		game.mobile_controls.cancel_all();game.input_handler.cancel_charge_input()

	game.pvp_mode = false;game.aim_focus._sync_realtime_mode();game._reset_match()
	for frame in 4: await process_frame
	game.game_serve.start_charge()
	for frame in 6: await physics_frame
	check(game.game_serve.get_charge_ratio() > 0.05, "direct service charge lost physics-clock fallback")
	check( not game.input_handler.serve_is_charging, "direct service charge stole human input ownership")
	game.game_serve.cleanup()
	for failure in failures: push_error(failure)
	print("SERVE INPUT CHARGE CLOCK: %d checks, %d failures" % [checks, failures.size()])
	print("CHARGE_CLOCK_DIAGNOSTIC " + JSON.stringify(rows))
	var out = FileAccess.open("/tmp/focus-charge-clock-diagnostic.json", FileAccess.WRITE);out.store_string(JSON.stringify(rows, "\t"));out.close()
	game.queue_free(); await process_frame; await process_frame
	var until: int = Time.get_ticks_usec() + 150000
	while Time.get_ticks_usec() < until: OS.delay_msec(5); await process_frame
	quit(0 if failures.is_empty() else 1)
