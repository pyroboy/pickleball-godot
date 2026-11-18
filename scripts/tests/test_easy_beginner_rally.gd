extends SceneTree


var game
var failures: Array[String] = []
var checks: = 0
var frame_id: = 0
var home_z: = 6.5
var rallies: Array = []
var volley_hits: = [0, 0]
var bounce_hits: = [0, 0]
var near: = OS.get_cmdline_user_args().has("--near")
var seed_values: = [101, 202, 303]
var max_returns: = 12
var output: = "/tmp/easy-beginner-rally.json"
var attempts: = 0
var hits: = 0
var seed_base: = 101
var diagnostic: = OS.get_cmdline_user_args().has("--diagnostic")
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(message)
func touch(id: int, point: Vector2, pressed: bool) -> void :
	var event: = InputEventScreenTouch.new()
	event.index = id;event.position = point;event.pressed = pressed
	root.push_input(event, true)
func drag(id: int, point: Vector2) -> void :
	var event: = InputEventScreenDrag.new()
	event.index = id;event.position = point
	root.push_input(event, true)
func frames(count: int) -> void :
	for i in range(count): await physics_frame;frame_id += 1
func wait_return(after_serve: bool = false) -> bool:
	var ui = game.mobile_controls
	touch(9, ui._stick_center, true)
	for i in range(420):
		await frames(1)
		if game.game_state == 2 and game.ball.last_hit_by == 1:
			touch(9, ui._stick_center, false)
			return true
		if game.game_state == 3:
			touch(9, ui._stick_center, false)
			return false
		if i % 6 == 0:
			var player: Vector3 = game.player_left.global_position
			var direction: = Vector2(0.0, home_z - player.z)
			if direction.length() < 0.12: direction = Vector2.ZERO
			else: direction = direction.normalized() * clampf(direction.length() * 1.6, 0.42, 0.95)
			drag(9, ui._stick_center + direction * ui._stick_radius)
	touch(9, ui._stick_center, false)
	return false
func receive(ring_threshold: float, tag: String) -> bool:
	var ui = game.mobile_controls
	attempts += 1
	await frames(9)
	touch(1, ui._charge_center, true)
	touch(2, ui._stick_center, true)
	var planted: = false
	var released: = false
	var release_frame: = -1
	var frozen_position: = Vector3.ZERO
	var hit: = false
	var aim_nudged: = false
	for frame in range(360):
		await frames(1)
		if game.game_state != 2: break
		if game.ball.last_hit_by == 0:
			hit = true
			break
		if frame % 6 != 0: continue
		var mode: String = game.hud._aim_mode
		if diagnostic and tag.ends_with("_2"):
			var human = game.player_left.posture.human_contact
			print("TOUCH DIAG ", frame, " mode=", mode, " p=", game.player_left.global_position, " b=", game.ball.global_position, " vel=", game.ball.linear_velocity, " dir=", Input.get_vector("move_left", "move_right", "move_up", "move_down"), " phase=", human.phase, " contact=", human.contact.get("time", -1), " msg=", game.hud.state.text)
		if not released:
			if mode == "AIM":
				planted = true
				if not aim_nudged:
					drag(2, ui._stick_center + Vector2(0.45, - 0.15) * ui._stick_radius)
					aim_nudged = true
				else: drag(2, ui._stick_center)
			elif game.hud.state.text.contains("Release HIT") or game.hud.state.text.contains("Release SPACE"):
				drag(2, ui._stick_center)
			else:
				var ball: Vector3 = game.ball.global_position
				var velocity: Vector3 = game.ball.linear_velocity
				var player: Vector3 = game.player_left.global_position
				var desired_z: float = home_z
				var lead: float = clampf((desired_z - ball.z) / maxf(velocity.z, 1.0), 0, 0.7)
				var desired_x: float = clampf(ball.x + velocity.x * lead, -2.8, 2.8)
				var direction: = Vector2(desired_x - player.x, desired_z - player.z)
				if direction.length() < 0.12: direction = Vector2.ZERO
				else: direction = direction.normalized() * clampf(direction.length() * 1.6, 0.42, 0.95)
				drag(2, ui._stick_center + direction * ui._stick_radius)
			var ring = game.reaction_button
			var progress: float = clampf((105.0 - ring._ring_radius) / 63.0, 0, 1)
			if planted and ring._active and progress >= ring_threshold:
				touch(1, ui._charge_center, false)
				released = true;release_frame = frame_id
				frozen_position = game.player_left.global_position
				drag(2, ui._stick_center + Vector2(0.4, 0) * ui._stick_radius)
				print("TOUCH RELEASE ", tag, " ring=", progress, " position=", frozen_position)
		elif game.hud._aim_mode == "LOCKED":
			check(game.player_left.global_position.distance_to(frozen_position) < 0.045, tag + " movement escaped lock before contact")
	if hit:
		hits += 1
		var contact_position: Vector3 = game.player_left.global_position
		await frames(8)
		check(game.player_left.global_position.distance_to(contact_position) > 0.005, tag + " movement did not return after contact")
		touch(2, ui._stick_center, false)
	else:
		touch(1, ui._charge_center, false)
		touch(2, ui._stick_center, false)
		print("TOUCH MISS ", tag, " planted=", planted, " released=", released, " state=", game.hud.state.text, " fault=", game.hud.fault.text, " ball=", game.ball.global_position, " human_phase=", game.player_left.posture.human_contact.phase, " game_state=", game.game_state)
	check(planted, tag + " ordinary chase did not enter visible AIM")
	check(aim_nudged, tag + " left stick never aimed")
	check(game.selected_shot_intent == "AUTO", tag + " center HIT accidentally selected Drop")
	check(released, tag + " visual ring release was not reached")
	check(hit, tag + " reachable return was not hit through touch input")
	print("TOUCH RALLY ", tag, " hit=", hit, " release_frame=", release_frame, " frame=", frame_id)
	return hit
func run() -> void :
	create_timer(180).timeout.connect( func(): push_error("Easy beginner rally timeout");quit(2))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--seed="): seed_values = [int(arg.trim_prefix("--seed="))]
		if arg.begins_with("--returns="): max_returns = int(arg.trim_prefix("--returns="))
	root.content_scale_size = Vector2i(720, 1560);root.size = Vector2i(720, 1560)
	if near: home_z = 2.85
	for seed_value in seed_values:
		game = load("res://scenes/game.tscn").instantiate()
		root.add_child(game);current_scene = game
		await frames(4)
		seed(seed_value);game.player_right.ai_brain.set_tactic_seed(42)
		game.ai_difficulty = 0;game.player_right.ai_brain.ai_difficulty = 0
		var ui = game.mobile_controls
		volley_hits = [0, 0];bounce_hits = [0, 0]
		game.ball.hit_by_paddle.connect( func(team: int):
			if game.ball.was_volley: volley_hits[team] += 1
			else: bounce_hits[team] += 1)
		if near:
			game.player_left.global_position = Vector3(0, game.player_left.ground_y, home_z)
			game.player_right.global_position = Vector3(0, game.player_right.ground_y, -2.85)
			game.player_left.leg_ik.feet_initialized = false
			game.player_right.leg_ik.feet_initialized = false
			game._set_game_state(game.GameState.PLAYING)
			game.rally_scorer._serve_was_hit = true
			game.ball.reset_rally_state()
			game.ball.both_bounces_complete = true
			game.ball.global_position = Vector3(0, 1.15, 2.1)
			game.ball.linear_velocity = Vector3(0, 2.2, -7.0)
			game.ball.angular_velocity = Vector3.ZERO
			game.ball.last_hit_by = 0;game.ball.is_in_play = true;game.ball.flight_id += 1
		else:
			touch(1, ui._charge_center, true); await frames(18);touch(1, ui._charge_center, false)
		var returned: bool = await wait_return(true)
		var count: = 0
		var ai_returns: = 1 if returned else 0
		var start_checks: = checks
		var start_failures: = failures.size()
		for index in range(max_returns):
			if not returned: break
			if not await receive(0.7, "seed%d_return%d" % [seed_value, index]): break
			count += 1
			returned = await wait_return()
			if returned: ai_returns += 1
		rallies.append({"seed": seed_value, "warm_start": near, "volley_hits": volley_hits.duplicate(), "bounce_hits": bounce_hits.duplicate(), "human_returns": count, "ai_returns": ai_returns, "fault": game.hud.fault.text, "state": game.hud.state.text, "checks": checks - start_checks, "failures": failures.size() - start_failures})
		print("BEGINNER RALLY ", rallies.back())
		game.mobile_controls.cancel_all();game.queue_free(); await process_frame; await process_frame
	var f = FileAccess.open(output, FileAccess.WRITE);f.store_string(JSON.stringify({"rallies": rallies, "checks": checks, "failures": failures, "human_hits": hits, "attempts": attempts}, "\t"));f.close()
	for failure in failures: push_error(failure)
	print("EASY BEGINNER RALLY: ", rallies)
	quit(0 if failures.is_empty() else 1)
