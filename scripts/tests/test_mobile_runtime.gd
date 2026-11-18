extends SceneTree

const Policy = preload("res://scripts/runtime_policy.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Planner = preload("res://scripts/incoming_contact_planner.gd")
var checks: = 0
var failures: Array[String] = []
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(message)
func run() -> void :
	check(Policy.mobile_runtime and not Policy.developer_tools, "run with --mobile-runtime")
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	game.set_physics_process(false)
	game.input_handler.set_process(false)
	game.player_left.set_physics_process(false)
	game.player_right.set_physics_process(false)
	for key in ["posture_editor_ui", "posture_editor_v2", "game_sound_tune", "game_drop_test", "game_debug_ui", "ball_physics_probe", "swing_e2e_probe"]:
		check(game.get(key) == null, key + " constructed on mobile")
	check( not game.hud.debug_available, "mobile debug button available")
	check(game.find_child("DebugZones", true, false) == null, "court debug geometry constructed")
	check(game.game_trajectory.trajectory_mesh == null, "mobile preview arc allocated")
	check(game.game_trajectory.landing_cursor != null, "gameplay aim cursor removed")
	check(root.get_node("McpBridge").udp_server == null, "developer bridge listening")
	for p in [game.player_left, game.player_right]:
		check(p.awareness_grid == null, "hidden volumetric grid constructed")
		check(p.posture.posture_ghost_root == null and p.posture.posture_ghosts.is_empty(), "ghost geometry constructed")
		check(p.debug_visual.incoming_traj_mesh == null, "incoming debug mesh constructed")
		check(p.debug_visual.human_intercept_indicator == null, "debug contact marker constructed")
	var player = game.player_left
	var ball = game.ball
	ball.freeze = true;ball.set_physics_process(false)
	player.global_position = Vector3(0, 1, 3.2)
	player.hitting.clear_charge_visual()
	player.hitting.serving_visual_active = false
	player.leg_ik.feet_initialized = false;player._process(0.0)
	ball.is_in_play = true;ball.last_hit_by = 1;ball.both_bounces_complete = true
	var selected: = 0
	for lane in [ - 0.65, 0, 0.65]:
		for height in [0.6, 1.1, 1.5]:
			for spin in [Vector3.ZERO, Vector3(-30, 0, 0), Vector3(0, 30, 0)]:
				ball.global_position = Vector3(lane, height, 1.5)
				ball.linear_velocity = Vector3(0.1, 1.5, 8)
				ball.angular_velocity = spin;ball.flight_id += 1
				player.debug_visual.update_human_intercept_pools(ball)
				var cached: Dictionary = player.debug_visual._last_flight
				var direct: = Flight.trace(ball.global_position, ball.linear_velocity, spin)
				check(cached == direct, "mobile incoming flight differs from canonical physics")
				var a: = Planner.select(player, ball, cached, -1)
				var b: = Planner.select(player, ball, direct, -1)
				check(a.get("posture", -1) == b.get("posture", -1), "mobile posture selection changed")
				if not a.is_empty():
					selected += 1
					check(a.point == b.point and a.time == b.time, "mobile contact point/time changed")
	check(selected > 0, "parity fixture has no reachable contacts")

	for state in ["outgoing", "stopped", "dead", "wrong_direction"]:
		ball.is_in_play = state != "dead";ball.last_hit_by = 0 if state == "outgoing" else 1
		ball.linear_velocity = Vector3.ZERO if state == "stopped" else Vector3(0, 0, -8 if state == "wrong_direction" else 8)
		player.debug_visual.update_human_intercept_pools(ball)
		check(player.debug_visual._last_flight.is_empty(), state + " retained stale flight")
		check(player.debug_visual._last_trajectory_points.is_empty(), state + " retained debug points")
	game._reset_ball();game._set_debug_visuals_visible(true)
	check( not ball.spin_debug_visible, "mobile debug ball visuals reenabled")
	var controller = root.get_node("PauseController")
	Engine.max_fps = 60
	for repetition in range(3):
		controller._on_window_focus_exited()
		controller._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		controller._on_window_focus_exited()
		check(Engine.max_fps == 5 and controller._previous_max_fps == 60, "duplicate pause overwrote60FPS")
		controller._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		controller._on_window_focus_entered()
		controller.close()
		check(Engine.max_fps == 60 and not paused, "resume did not restore60FPS")
	Engine.max_fps = 0
	game.queue_free(); await process_frame
	for failure in failures: push_error(failure)
	print("MOBILE RUNTIME: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
