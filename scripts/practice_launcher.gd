extends Node
class_name PracticeLauncher
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")


const PRACTICE_LOOP_INTERVAL: = 1.7
const ATTEMPT_TIMEOUT: = 8.0
const _Flight = preload("res://scripts/ball_flight_predictor.gd")
const Scenarios = preload("res://scripts/kitchen_exchange_scenarios.gd")
const Tactics = preload("res://scripts/ai_kitchen_tactics.gd")
var wall_practice
var _game: Node
var _ball: RigidBody3D
var _player_left: CharacterBody3D
var _player_right: CharacterBody3D
var _ball_physics_probe: Node
var is_active: = false
var loop_enabled: = false
var drill_mode: = "DRIVE"
var status_text: = ""
var attempt_count: = 0
var success_count: = 0
var _loop_timer: = 0.0
var _attempt_timer: = 0.0
var _attempt_finished: = false
var _match_snapshot: Dictionary = {}
var demo_enabled: = false
var allow_attacks: = false
var diagonal: = 1
var exchange_pattern: = "STANDARD"
var _demo_receive_x: = 0.0
var _last_launch_targets: Dictionary = {}
var last_response_kind: = "SOFT"
var _demo_rng: = RandomNumberGenerator.new()
var _demo_target: = Vector3.ZERO
var exchange_count: = 0
var best_exchange_count: = 0
var last_failure: = ""
var _exchange_status_timer: = 0.0
var _saved_ai_difficulty: = 0
var _saved_shot_intent: = "AUTO"
const EXCHANGE_MODES: = ["DINK", "HANDS"]
const HANDS_SAFE_Z: = 2.72


func setup(game: Node, ball: RigidBody3D, p_left: CharacterBody3D, p_right: CharacterBody3D, probe: Node) -> void :
	_game = game
	_ball = ball
	_player_left = p_left
	_player_right = p_right
	_ball_physics_probe = probe
	wall_practice = preload("res://scripts/wall_practice.gd").new()
	add_child(wall_practice)
	wall_practice.setup(game, self)
	_ball.bounced.connect(_on_bounced)
	_ball.hit_by_paddle.connect(_on_exchange_hit)
	call_deferred("_connect_serve")
	if OS.has_environment("GODOT_TEST_AUTO_LAUNCH"):
		call_deferred("launch_ball")

func _connect_serve() -> void :
	_game.game_serve.serve_launched.connect(_on_serve_launched)

func start_drill(mode: String, demo: bool = false, direction: int = 1, pattern: String = "STANDARD") -> void :
	if mode not in ["SERVE", "DRIVE", "RETURN", "DINK", "HANDS", "WALL"] or _game == null:
		return
	if not is_active:
		_saved_ai_difficulty = _player_right.ai_brain.ai_difficulty
		_saved_shot_intent = _game.selected_shot_intent
		_match_snapshot = {"left": _game.score_left, "right": _game.score_right, 
			"server": _game.serving_team, "over": _game.match_over, "winner": _game.match_winner}
	if is_wall(): wall_practice.leave()
	is_active = true
	loop_enabled = true
	drill_mode = mode
	demo_enabled = demo and mode in EXCHANGE_MODES
	allow_attacks = mode == "DINK" and ( not demo or pattern == "ATTACK")
	diagonal = 1 if direction >= 0 else -1
	exchange_pattern = pattern if pattern in ["STANDARD", "WIDE", "ATTACK"] else "STANDARD"
	best_exchange_count = 0
	last_failure = ""
	attempt_count = 0
	success_count = 0
	_game.match_over = false
	_game.match_winner = -1
	if is_wall(): wall_practice.enter()
	repeat_drill()

func is_wall() -> bool:
	return is_active and drill_mode == "WALL"

func repeat_drill() -> void :
	if not is_active or _game._tool_state_active(): return
	_loop_timer = 0.0
	_attempt_timer = 0.0
	_attempt_finished = false
	exchange_count = 0
	last_failure = ""
	attempt_count += 1
	_game.serving_team = 0 if drill_mode == "SERVE" else 1
	_game._reset_ball()
	_player_right.set_ai_movement_enabled(false)
	_game.selected_shot_intent = _saved_shot_intent
	_player_right.ai_brain.ai_difficulty = _saved_ai_difficulty
	if is_wall():
		wall_practice.feed()
		return
	if is_exchange():
		_start_exchange()
		return
	if drill_mode == "SERVE":
		_set_status("Hold to serve into the diagonal box")
		return
	if drill_mode == "RETURN":

		_game._perform_serve(0.55)
		_set_status("Let the serve bounce, then return it")
		return


	_player_left.global_position = Vector3(1.25, _player_left.ground_y, 5.65)
	_player_right.global_position = Vector3(-1.25, _player_right.ground_y, -5.9)
	var origin: = Vector3(-1.25, 0.95, -5.5)
	var target: = Vector3(1.25, _Flight.FLOOR_REST_Y, 4.4)
	var launch: Dictionary = _game.shot_physics.solve_aimed_launch(origin, target, 0.48, 1, 0, "AUTO", "DRIVE")
	_ball.global_position = origin
	_ball.suppress_paddle_collision(_player_right.paddle_node)
	_ball.linear_velocity = launch.velocity
	_ball.angular_velocity = launch.omega
	_ball.last_hit_by = 1
	_ball.serve_team = 1
	_ball.is_in_play = true
	_ball.both_bounces_complete = true
	_ball.serving_side_bounced = true
	_ball.receiving_side_bounced = true
	_ball.flight_id += 1
	_game._set_game_state(_game.GameState.PLAYING)
	_game.rally_scorer._serve_was_hit = true
	_player_right.set_ai_movement_enabled(false)
	_set_status("Let the feed bounce, then drive it back")

func _on_serve_launched(_team: int) -> void :
	if not is_active: return
	_player_right.set_ai_movement_enabled(false)
	_set_status("Land in the diagonal service box" if drill_mode == "SERVE" else "Let the serve bounce, then return it")

func _on_bounced(position: Vector3) -> void :
	if is_wall():
		wall_practice.on_floor_bounce(position)
		return
	if is_exchange() and not _attempt_finished:
		if _game.game_state != _game.GameState.PLAYING: return
		if drill_mode == "HANDS":
			finish_attempt(1, "MISSED VOLLEY", "Keep the paddle compact and meet the ball before it bounces")
		elif not allow_attacks and (absf(position.x) > 2.45 or absf(position.z) > PickleballConstants.NON_VOLLEY_ZONE):
			finish_attempt(1, "DINK TOO DEEP", "Keep the exchange soft and inside the diagonal kitchen target")
		return
	if not is_active or _attempt_finished or _ball.last_hit_by != 0:
		return

	if _game.game_state != _game.GameState.PLAYING: return
	if absf(position.x) > PickleballConstants.COURT_WIDTH * 0.5 or absf(position.z) > PickleballConstants.BASELINE_Z:
		finish_attempt(1, "OUT", "Aim farther inside the sidelines and baseline")
	elif position.z < 0.0:
		finish_attempt(0, "GOOD SERVE" if drill_mode == "SERVE" else "IN BOUNDS", "Legal diagonal serve" if drill_mode == "SERVE" else "Your shot landed in the opponent's court")

func finish_attempt(winner: int, reason: String, detail: String) -> void :
	if not is_active or _attempt_finished: return
	_attempt_finished = true
	_loop_timer = 0.0
	if winner == 0 and not is_exchange(): success_count += 1
	last_failure = reason
	_game._set_game_state(_game.GameState.POINT_SCORED)
	_ball.is_in_play = false
	_player_right.set_ai_movement_enabled(false)
	_game.game_serve.cleanup()
	_ball.freeze = true
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_game.scoreboard_ui.show_fault(reason.replace("_", " "), detail)
	if is_wall():
		_set_status("%s · next ball shortly" % reason.capitalize())
		return
	if is_exchange():
		_set_status("%s · %d legal hits · best %d\n%s" % [reason.replace("_", " ").capitalize(), exchange_count, best_exchange_count, "Next exchange shortly" if loop_enabled else "Repeat from Pause"])
		return
	_set_status("%s · %d/%d in · %s" % [reason.replace("_", " ").capitalize(), success_count, attempt_count, "Next ball shortly" if loop_enabled else "Repeat from Pause"])

func _process(delta: float) -> void :
	if not is_active or _ball == null or _ball.is_time_frozen() or _game._tool_state_active(): return
	if _attempt_finished:
		if loop_enabled:
			_loop_timer += delta
			if _loop_timer >= PRACTICE_LOOP_INTERVAL: repeat_drill()
	elif _game.game_state == _game.GameState.PLAYING:
		_attempt_timer += delta
		if is_wall(): wall_practice.tick(delta)
		if is_exchange():
			_exchange_status_timer += delta
			if _exchange_status_timer >= 0.25:
				_exchange_status_timer = 0.0
				_show_exchange_status()
		if _attempt_timer >= ATTEMPT_TIMEOUT:
			finish_attempt(1, "MISSED RETURN", "Move behind the bounce and release your swing in reach")

func stop_practice() -> void :
	if not is_active: return
	if is_wall(): wall_practice.leave()
	is_active = false
	demo_enabled = false
	_game.selected_shot_intent = _saved_shot_intent
	_player_right.ai_brain.ai_difficulty = _saved_ai_difficulty
	loop_enabled = false
	_attempt_finished = false
	_loop_timer = 0.0
	_attempt_timer = 0.0
	_game._practice_mode = false
	_game.score_left = int(_match_snapshot.left)
	_game.score_right = int(_match_snapshot.right)
	_game.serving_team = int(_match_snapshot.server)
	_game.match_over = bool(_match_snapshot.over)
	_game.match_winner = int(_match_snapshot.winner)
	_game.scoreboard_ui.update_score(_game.score_left, _game.score_right)
	_game._reset_ball()
	if _game.match_over:
		_ball.freeze = true
		_game._set_game_state(_game.GameState.POINT_SCORED)
		_game.scoreboard_ui.set_state_text("%s · %d - %d\nChoose Rematch to play again" % ["You win!" if _game.match_winner == 0 else "AI wins", _game.score_left, _game.score_right])
	_match_snapshot.clear()
	status_text = ""

func _set_status(detail: String) -> void :
	status_text = "PRACTICE %s · NO SCORE\n%s" % [drill_mode, detail]
	_game.scoreboard_ui.set_state_text(status_text)


func launch_ball() -> void :
	start_drill("DRIVE")
	if _ball_physics_probe: _ball_physics_probe.begin_probe(_ball)

func toggle_loop() -> void :
	if not is_active:
		start_drill("DRIVE")
	else:
		loop_enabled = not loop_enabled


func toggle_auto_hit() -> void :
	if RuntimePolicy.developer_tools: print("[PRACTICE] Manual contact drills; use Repeat to try the same feed")



func is_exchange() -> bool:
	return is_active and drill_mode in EXCHANGE_MODES

func is_exchange_demo() -> bool:
	return is_exchange() and demo_enabled and not _attempt_finished

func needs_bounce() -> bool:
	return is_exchange() and drill_mode == "DINK" and not allow_attacks

func get_exchange_home(team: int) -> Vector3:
	var side: float = 1.0 if team == 0 else -1.0
	var p = _player_left if team == 0 else _player_right


	if allow_attacks and demo_enabled and _game.rally_scorer._volley_momentum_watches.has(team):
		return Vector3(p.global_position.x, p.ground_y, p.global_position.z)
	var x: float = side * diagonal * 1.05 if drill_mode == "DINK" else 0.0
	var z: float = 2.18 if drill_mode == "DINK" and not allow_attacks else HANDS_SAFE_Z
	if drill_mode == "DINK" and exchange_pattern != "STANDARD" and _last_launch_targets.has(team):
		x = Scenarios.recovery_x(_last_launch_targets[team].x, x)
	return Vector3(x, p.ground_y, side * z)

func _start_exchange() -> void :
	_last_launch_targets.clear()
	last_response_kind = "SOFT"
	_demo_target = Vector3.ZERO
	_demo_rng.seed = 1403 + diagonal
	for team in [0, 1]:
		var p = _player_left if team == 0 else _player_right
		p.global_position = get_exchange_home(team)
		p.velocity = Vector3.ZERO
		p.current_velocity = Vector3.ZERO
		if p.leg_ik: p.leg_ik.feet_initialized = false


	_player_right.ai_brain.ai_difficulty = _saved_ai_difficulty if allow_attacks else 2
	_player_right.ai_brain.set_tactic_seed(1403 + diagonal)
	var origin: Vector3 = Vector3( - diagonal * 1.05, 0.7, -1.5) if drill_mode == "DINK" else Vector3(-0.28, 1.1, -2.05)
	var launch: Dictionary = solve_exchange_launch(origin, 1)
	_ball.global_position = origin
	_ball.suppress_paddle_collision(_player_right.paddle_node)
	_ball.linear_velocity = launch.velocity
	_ball.angular_velocity = launch.omega
	_ball.last_hit_by = 1
	_ball.serve_team = 1
	_ball.is_in_play = true
	_ball.both_bounces_complete = true
	_ball.serving_side_bounced = true
	_ball.receiving_side_bounced = true
	_ball.flight_id += 1
	_game.selected_shot_intent = "DROP" if drill_mode == "DINK" and not allow_attacks else "AUTO"
	_game._set_game_state(_game.GameState.PLAYING)
	_game.rally_scorer._serve_was_hit = true
	_player_right.set_ai_movement_enabled(true)
	_show_exchange_status()

func solve_exchange_launch(origin: Vector3, team: int) -> Dictionary:
	var direction: float = -1.0 if team == 0 else 1.0
	if drill_mode == "DINK":
		var target: Vector3 = Scenarios.dink_target(exchange_pattern, exchange_count, team, diagonal)
		if allow_attacks and demo_enabled and _ball.is_in_play:
			var context: Dictionary = kitchen_context(origin, team)
			var response: String = Tactics.response_kind(context, _demo_rng.randf())
			if response in ["SPEED_UP", "SMASH"]:
				return solve_kitchen_attack(origin, team, context)
			if response == "RESET":
				last_response_kind = "RESET"
				return _remember_launch(_game.shot_physics.solve_drop_launch(origin, 0.16, team, 0, target), team)



			if exchange_count >= 2 and exchange_count % 5 == 2:
				var receiver = _player_right if team == 0 else _player_left
				var high: bool = int(exchange_count / 5) % 2 == 1
				var popup_target: = Vector3(clampf(receiver.global_position.x, -1.8, 1.8), 1.95 if high else 1.32, direction * 2.18)
				last_response_kind = "HIGH_POPUP" if high else "POPUP"
				return _remember_launch(solve_airborne_feed(origin, popup_target, 1.08 if high else 0.91), team)
		last_response_kind = "SOFT"
		return _remember_launch(_game.shot_physics.solve_drop_launch(origin, 0.25, team, 0, target), team)


	var receiver_home: Vector3 = get_exchange_home(1 - team)
	var target: = Vector3(receiver_home.x + 0.42 * direction * (1.0 if int(exchange_count / 2) % 2 == 0 else -1.0), 1.1, direction * 2.05)
	var duration: float = maxf(0.55, 0.66 - floorf(exchange_count / 6.0) * 0.025) + _player_right.ai_brain.extra_reaction_delay * 0.7
	var velocity: Vector3 = (target - origin) / duration
	velocity.y += 0.5 * preload("res://scripts/ball.gd").get_effective_gravity() * duration
	for step in range(12):
		var end: Vector3 = _game.shot_physics._spin_position_after(origin, velocity, Vector3.ZERO, duration)
		velocity += (target - end) / duration * 0.86
	var profile: Dictionary = preload("res://scripts/shot_profile.gd").create(0, 0.25, "VOLLEY")
	return {"velocity": velocity, "omega": Vector3.ZERO, "profile": profile, "target": target}

func _on_exchange_hit(team: int) -> void :
	if is_wall():
		wall_practice.on_paddle_hit(team)
		return
	if not is_exchange() or _attempt_finished or _game.game_state != _game.GameState.PLAYING: return
	if needs_bounce() and _ball.was_volley:
		finish_attempt(1 - team, "LET IT BOUNCE", "Dink exchanges require a real floor bounce before every contact")
		return
	exchange_count += 1
	best_exchange_count = maxi(best_exchange_count, exchange_count)
	_attempt_timer = 0.0
	_show_exchange_status()

func _show_exchange_status() -> void :
	var hint: String = ("LIVE DINK · pop-ups may be attacked" if allow_attacks else "Cooperative diagonal targets · bounce, stay low, recover") if drill_mode == "DINK" else "Compact blocks · keep both feet behind the kitchen line"
	_set_status("%s · %d legal hits · best %d\n%s · warm-start, opening bounces complete" % ["DEMO" if demo_enabled else "YOUR TURN", exchange_count, best_exchange_count, hint])

func get_demo_movement() -> Vector3:
	if not is_exchange_demo() or _game._tool_state_active(): return Vector3.ZERO
	var home: Vector3 = get_exchange_home(0)
	if allow_attacks and _game.rally_scorer._volley_momentum_watches.has(0): return Vector3.ZERO
	if drill_mode != "DINK" or exchange_pattern == "STANDARD":
		if drill_mode == "DINK" and _ball.last_hit_by == 1: home.x = _demo_receive_x
		var old_offset: Vector3 = home - _player_left.global_position
		old_offset.y = 0.0
		return old_offset.normalized() if old_offset.length() > 0.07 else Vector3.ZERO
	if _ball.last_hit_by == 1:


		var human = _player_left.posture.human_contact
		var flight: Dictionary = _player_left.debug_visual._last_flight if _player_left.debug_visual and human != null and human._flight_id == _ball.flight_id else {}
		var target: Vector3 = Scenarios.receive_target(_player_left.global_position, flight, 
			_ball.bounces_since_last_hit, needs_bounce(), HANDS_SAFE_Z, _player_left.move_speed)
		if target.is_finite(): home = target
		else: home.x = _demo_receive_x
		if human != null and human._flight_id == _ball.flight_id and not human.contact.is_empty() and human.phase in [0, 1] and float(human.contact.time) <= 0.14:


			return Vector3.ZERO
	_demo_target = home
	return Scenarios.movement_input(home - _player_left.global_position, _player_left.current_velocity, 
		_player_left.move_speed, get_physics_process_delta_time())

func _physics_process(_delta: float) -> void :
	if not is_exchange_demo() or _ball.is_time_frozen() or _game._tool_state_active() or _game.game_state != _game.GameState.PLAYING: return
	var human = _player_left.posture.human_contact
	if human == null: return
	if _ball.last_hit_by == 0 or human.phase >= 0 or human.contact.is_empty(): return
	if needs_bounce() and not _ball.ball_bounced_since_last_hit and int(human.contact.get("bounces", 0)) == 0: return


	var charge: float = 0.25
	if allow_attacks and float(human.contact.point.y) > _Flight.net_clear_y_at(human.contact.point.x) + 0.2:
		charge = 0.7
	human.request_swing(charge)

func set_allow_attacks(enabled: bool) -> void :
	if not is_exchange() or drill_mode != "DINK": return
	allow_attacks = enabled
	_show_exchange_status()

func _remember_launch(launch: Dictionary, team: int) -> Dictionary:
	_last_launch_targets[team] = launch.target
	if team == 1: _demo_receive_x = launch.target.x
	return launch

func kitchen_context(origin: Vector3, team: int) -> Dictionary:
	var player = _player_left if team == 0 else _player_right
	var reachable: bool = not player.posture.human_contact.contact.is_empty() if team == 0 else player.ai_brain.ai_selected_contact_reachable
	return {"near_kitchen": absf(player.global_position.z) <= PickleballConstants.NON_VOLLEY_ZONE + 1.4, 
		"legal_volley": _ball.both_bounces_complete and player.can_volley_from_feet() and not player.is_jumping, 
		"reachable": reachable, "balanced": _game.rally_scorer._has_regained_balance(player), 
		"reaction_ready": team == 0 or player.ai_brain._perception_ready, 
		"ball_height": origin.y, "net_height": _Flight.net_clear_y_at(origin.x), 
		"net_distance": absf(origin.z), "contact_distance": PaddleReach.shoulder_world(player).distance_to(origin), 
		"incoming_speed": _ball.linear_velocity.length(), "difficulty": _player_right.ai_brain.ai_difficulty}

func solve_kitchen_attack(origin: Vector3, team: int, context: Dictionary) -> Dictionary:
	var receiver = _player_right if team == 0 else _player_left
	var direction: float = -1.0 if team == 0 else 1.0
	last_response_kind = Tactics.attack_kind(context)
	var target: = Vector3(clampf(receiver.global_position.x, -2.0, 2.0), _Flight.FLOOR_REST_Y, 
		direction * (3.8 if last_response_kind == "SMASH" else 4.8))
	var launch: Dictionary = _game.shot_physics.solve_aimed_launch(origin, target, Tactics.attack_charge(context), team, 
		0, "AUTO", "SMASH" if last_response_kind == "SMASH" else "VOLLEY")
	if team == 1: _player_right.ai_brain.last_kitchen_tactic = "ATTACK"
	return _remember_launch(launch, team)

func solve_airborne_feed(origin: Vector3, target: Vector3, duration: float) -> Dictionary:


	var velocity: Vector3 = (target - origin) / duration
	velocity.y += 0.5 * preload("res://scripts/ball.gd").get_effective_gravity() * duration
	for step in range(12):
		velocity += (target - _game.shot_physics._spin_position_after(origin, velocity, Vector3.ZERO, duration)) / duration * 0.86
	return {"velocity": velocity, "omega": Vector3.ZERO, "target": target, 
		"profile": preload("res://scripts/shot_profile.gd").create(0, 0.18, "DINK")}
