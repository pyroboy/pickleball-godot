extends SceneTree

const Ledger = preload("res://scripts/doubles_match_state.gd")
var game
var failures: Array[String] = []
var checks := 0
var events: Array = []
var human_returns := 0
var partner_returns := 0
var continued_human_rallies := 0
var sequences: Dictionary = {}
var held := false
var stick := false
var press_usec := 0
var last_input_usec := 0
var last_status_usec := 0
var finished := false

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func ledger_checks() -> void:
	var state = Ledger.new()
	check(state.configure([[0, 2], [1, 3]], [0, 1]), "four-actor ledger configuration")
	check(state.score_call() == "0–0–2", "opening second-server call")
	check(state.partner_of(0) == 2 and state.partner_of(1) == 3, "partner identities")
	var rally: Dictionary = state.begin_rally()
	var result: Dictionary = state.complete_rally(1, int(rally.token))
	check(bool(result.side_out) and state.serving_team == 1 and state.server_number == 1, "opening service loss is sideout")
	check(not bool(state.complete_rally(1, int(rally.token)).accepted), "duplicate settlement rejected")
	rally = state.begin_rally()
	result = state.complete_rally(0, int(rally.token))
	check(not bool(result.side_out) and state.server_actor == 3 and state.server_number == 2, "first-server loss advances to partner")
	rally = state.begin_rally()
	result = state.complete_rally(0, int(rally.token))
	check(bool(result.side_out) and state.serving_team == 0, "second-server loss is sideout")
	rally = state.begin_rally()
	result = state.complete_rally(0, int(rally.token))
	check(bool(result.point_scored) and state.scores == [1, 0], "only serving team scores")
	var receiver: int = state.correct_receiver()
	rally = state.begin_rally()
	var wrong: Dictionary = state.receiver_contact(state.partner_of(receiver), int(rally.token))
	check(wrong.get("fault_team", -1) == 1, "wrong receiving partner detected")

func touch(id: int, point: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = id
	event.position = point
	event.pressed = down
	root.push_input(event, true)

func drag(point: Vector2) -> void:
	if not stick:
		touch(9, game.mobile_controls._stick_center, true)
		stick = true
	var event := InputEventScreenDrag.new()
	event.index = 9
	event.position = point
	root.push_input(event, true)

func release_inputs() -> void:
	if held: touch(8, game.mobile_controls._charge_center, false)
	if stick: touch(9, game.mobile_controls._stick_center, false)
	held = false
	stick = false

func on_hit(actor: int, team: int, side: int) -> void:
	var token: int = int(game.doubles_state.active_rally.get("token", -1))
	var sequence: Array = sequences.get(token, [])
	var prior_opponent := false
	var prior_human := false
	for item in sequence:
		prior_opponent = prior_opponent or int(item.actor) in [1, 3]
		prior_human = prior_human or bool(item.get("human_return", false))
	var human_return := actor == 0 and prior_opponent
	if human_return: human_returns += 1
	if actor == 2 and prior_opponent: partner_returns += 1
	if actor in [1, 3] and prior_human: continued_human_rallies += 1
	var item := {"actor": actor, "team": team, "side": side, "token": token,
		"human_return": human_return, "physics_frame": Engine.get_physics_frames(),
		"wall_usec": Time.get_ticks_usec(), "position": str(game.ball.global_position)}
	sequence.append(item)
	sequences[token] = sequence
	events.append(item)
	print("DUOS CONTACT ", JSON.stringify(item))

func run() -> void:
	ledger_checks()
	root.content_scale_size = Vector2i(720, 1560)
	root.size = Vector2i(540, 1170)
	set_meta("local_doubles", true)
	set_meta("match_ai_seed", 1013)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.ball.actor_hit_paddle.connect(on_hit)
	for index in 45: await process_frame
	check(game.doubles_mode and game.get_players().size() == 4, "four actors in doubles game")
	check(not game.get_player_by_actor_id(0).is_ai and game.get_player_by_actor_id(2).is_ai, "human plus AI partner")
	check(game.get_team_players(0).size() == 2 and game.get_team_players(1).size() == 2, "two actors on each team")
	check(game.get_player_by_actor_id(1).is_ai and game.get_player_by_actor_id(3).is_ai, "two AI opponents")
	check(game.team_coordination != null and game.doubles_state != null, "coordination and service ledger wired")
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < 90000000:
		await process_frame
		var now := Time.get_ticks_usec()
		if now - last_status_usec > 5000000:
			last_status_usec = now
			var human = game.player_left.posture.human_contact
			print("DUOS STATUS ", JSON.stringify({"seconds": (now-start)/1000000.0, "state": game.game_state,
				"server": game.get_server_actor().actor_id, "score": game.doubles_state.score_call(),
				"contacts": events.size(), "human_returns": human_returns, "partner_returns": partner_returns,
				"continued": continued_human_rallies, "human_phase": human.phase if human != null else -99,
				"reachable": human.release_timing_state() if human != null else {},
				"fault": game.hud.fault.text, "status": game.hud.state.text}))
		if game.match_over or human_returns >= 2 and partner_returns >= 1 and continued_human_rallies >= 1: break
		if now - last_input_usec < 40000: continue
		last_input_usec = now
		var ui = game.mobile_controls
		if ui._blocked() or game._point_transition_blocks_attempt() or game.game_state == 3:
			release_inputs()
			continue
		if game.game_state == 0:
			if game.human_may_serve():
				if not held:
					touch(8, ui._charge_center, true)
					held = true
					press_usec = now
				elif now - press_usec > 450000:
					touch(8, ui._charge_center, false)
					held = false
			else: release_inputs()
			continue
		if game.game_state != 2: continue
		var ball = game.ball
		var player = game.player_left
		var sign_z: float = 1.0 if player.court_side == 0 else -1.0
		var human = player.posture.human_contact
		if ball.last_hit_by == 0:
			if held:
				touch(8, ui._charge_center, false)
				held = false
			drag(ui._stick_center)
			continue
		var depth: float = 5.5 * sign_z
		var time_to_depth: float = clampf((depth - ball.global_position.z) / ball.linear_velocity.z, 0.0, 0.65) if absf(ball.linear_velocity.z) > 0.1 else 0.0
		var target_x: float = clampf(ball.global_position.x + ball.linear_velocity.x * time_to_depth, -2.6, 2.6)
		var direction := Vector2(target_x - player.global_position.x, depth - player.global_position.z)
		if direction.length() < 0.14: direction = Vector2.ZERO
		else: direction = direction.normalized() * clampf(direction.length() * 1.4, 0.35, 0.9)
		if human != null and not human.contact.is_empty() and float(human.contact.time) < 0.65: direction = Vector2.ZERO
		drag(ui._stick_center + direction * ui._stick_radius)
		if human != null and human.phase < 0:
			if not held:
				touch(8, ui._charge_center, true)
				held = true
				press_usec = now
			elif bool(human.release_timing_state().get("release_ready", false)):
				touch(8, ui._charge_center, false)
				held = false
	check(human_returns >= 1, "actual human paddle return through touch input")
	check(partner_returns >= 1, "AI partner physically returned a ball")
	check(continued_human_rallies >= 1, "opponents continued after a human return")
	release_inputs()
	var report := {"checks": checks, "failures": failures, "events": events,
		"human_returns": human_returns, "partner_returns": partner_returns,
		"continued_human_rallies": continued_human_rallies, "seed": 1013,
		"input_route": "viewport InputEventScreenTouch/Drag; normal mobile controls and contact authority",
		"fixture_note": "direct Game bootstrap; no teleports, fed balls, AI-human replacement, forced hit or direct scoring"}
	var file := FileAccess.open("res://../ios-duos-gate-report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t"))
	print("DUOS GATE RESULT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
