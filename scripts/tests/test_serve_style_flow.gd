extends SceneTree
const Styles = preload("res://scripts/serve_style.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Geometry = preload("res://scripts/paddle_clearance.gd")
var failures: Array[String] = []
var checks: int = 0
var contacts: int = 0
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func fresh(side: int = 0):
	var g = load("res://scenes/game.tscn").instantiate()
	root.add_child(g)
	await physics_frame
	g.input_handler.set_process(false)
	g.serving_team = side
	g._reset_ball()
	return g
func run() -> void :
	create_timer(90).timeout.connect( func(): quit(2))
	for side in [0, 1]:
		for id in range(7):
			for power in [0.0, 1.0]:
				var g = await fresh(side)
				var serve = g.game_serve
				serve.select_serve_style(id)
				for i in range(24): await physics_frame
				serve.start_charge()
				serve.tick_charge(power * PickleballConstants.MAX_SERVE_CHARGE_TIME)
				var p = g.player_left if side == 0 else g.player_right
				var tag = "style%d side%d power%.1f" % [id, side, power]
				var released: Vector3 = serve.get_held_ball_position()
				var hits: Array[Dictionary] = []
				var bounces: Array[Vector3] = []
				g.ball.bounced.connect( func(pos: Vector3):
					if not g.ball.is_in_play: bounces.append(pos))
				serve.serve_launched.connect( func(team: int):
					var local: Vector3 = p.paddle_node.to_local(g.ball.global_position)
					hits.append({"team": team, "pos": g.ball.global_position, "surface_gap": Geometry.distance_to_head_shape(local) - Ball.BALL_RADIUS, "style": g.ball.get_meta("serve_style"), "elapsed": g.ball.get_meta("serve_release_elapsed"), "bounces": g.ball.get_meta("serve_delivery_bounces"), "profile": g.ball.get_meta("shot_profile"), "target": g.ball.get_meta("aim_target"), "feet": serve._legal_service_feet(p, side), "timing": serve.get_serve_timing_state(), "rally_bounces": g.ball.bounces_since_last_hit}))
				serve.release(power)
				check(serve.is_release_pending(), tag + " release queued")
				check(g.ball.linear_velocity.length() < 1e-05 and g.ball.angular_velocity.length() < 1e-05, tag + " zero force/spin at release")
				check(g.ball.global_position.distance_to(released) < 1e-05, tag + " release retains actual held position")
				var frozen_target: Vector3 = serve._pending_release.target
				check( not serve.select_serve_style((id + 1) % 7), tag + " committed style rejects changes")
				g.selected_spin_mode = (Styles.spin_mode(id) + 1) % 3
				g.serve_aim_offset_x += 0.7
				serve.release(0.13)
				var phases: Array[String] = []
				var previous: Vector3 = g.ball.global_position
				var drop_seen: bool = false
				for frame in range(120):
					var state: Dictionary = serve.get_serve_timing_state()
					if not state.phase in phases: phases.append(state.phase)
					if not hits.is_empty(): break
					check(state.locked and state.style == id, tag + " timing ring uses frozen style")
					check(state.progress >= 0 and state.progress <= 1, tag + " timing progress bounded")
					check(g.ball.angular_velocity.length() < 0.001, tag + " no release spin before contact")
					check(Vector2(g.ball.global_position.x - released.x, g.ball.global_position.z - released.z).length() < 0.005, tag + " gravity fall has no propelled lateral motion")
					check(g.ball.global_position.distance_to(previous) < 0.13, tag + " precontact ball is continuous")
					if g.ball.global_position.y < released.y - 0.2: drop_seen = true
					previous = g.ball.global_position
					await physics_frame
				check(hits.size() == 1, tag + " exactly one launch")
				if not hits.is_empty():
					contacts += 1
					var hit: Dictionary = hits[0]
					check(hit.style == id and hit.team == side, tag + " original style/server at impact")
					check(is_equal_approx(hit.profile.charge, power), tag + " original power at impact")
					check(hit.target.distance_to(frozen_target) < 0.001, tag + " original target at impact")
					check(absf(hit.surface_gap) < 0.003, tag + " exact ball/paddle surface contact")
					check(hit.feet, tag + " full soles legal at strike")
					check(hit.timing.phase == "CONTACT" and is_equal_approx(hit.timing.progress, 1), tag + " ring completes at actual contact")
					check(hit.rally_bounces == 0, tag + " release bounce is excluded from rally rules")
					check(drop_seen, tag + " actual visible fall")
					if Styles.is_drop(id):
						check(hit.elapsed > 0.6 and hit.bounces >= 1 and bounces.size() >= 1, tag + " actual rebound before strike")
						check("DROP" in phases and "BOUNCE" in phases and "SWING" in phases, tag + " distinct physical drop phases")
					else:
						check(hit.elapsed > 0.2 and hit.bounces == 0 and bounces.is_empty(), tag + " volley before bounce")
					check("SWING" in phases, tag + " moving stroke is scheduled before contact")
				g.ball.freeze = true
				g.ball.is_in_play = false
				g.set_physics_process(false)
				g.player_right.set_ai_movement_enabled(false)
				for i in range(52): await physics_frame
				check( not p.hitting.serving_visual_active and not p.hitting.is_in_follow_through, tag + " recovery returns ownership")
				g.queue_free()
				await process_frame

	for action in ["cleanup", "reset", "pause", "editor", "move"]:
		var g = await fresh()
		var serve = g.game_serve
		serve.select_serve_style(4)
		for i in range(20): await physics_frame
		serve.start_charge();serve.tick_charge(0.75);serve.release(0.5)
		for i in range(8): await physics_frame
		match action:
			"cleanup": serve.cleanup()
			"reset": g._reset_ball()
			"pause": paused = true
			"editor": g._suspend_tool_gameplay()
			"move": g.player_left.global_position.x += 0.12
		await process_frame
		await physics_frame
		check( not serve.is_release_pending(), action + " cancels queued serve")
		check( not g.ball.is_in_play, action + " never produces an impact")
		if action == "pause": paused = false
		if action == "editor": g._resume_tool_gameplay()
		serve.release(1.0)
		check( not serve.is_release_pending(), action + " stale release cannot restart")
		g.queue_free(); await process_frame
	for failure in failures: push_error(failure)
	print("SERVE STYLE FLOW: %d checks, %d failures; %d/28 contacts" % [checks, failures.size(), contacts])
	quit(0 if failures.is_empty() else 1)
