extends RefCounted



const Flight = preload("res://scripts/ball_flight_predictor.gd")
const CURSOR_SPEED: float = 5.2
const PLANT_LEAD: float = 0.85
const PLANT_EXIT_LEAD: float = 1.0
const SETTLE_TIME: float = 0.06
const URGENT_PLANT_LEAD: float = 0.18
const X_LIMIT: float = 2.45
const MIN_DEPTH: float = 0.65
const MAX_DEPTH: float = 6.1
const DROP_DEPTH: float = 1.55
var _game
var target: = Vector3(0, Flight.FLOOR_REST_Y, -4.6)
var _locked_target: = Vector3.INF
var planted: = false
var independent_aim: = false
var _neutral_time: = 0.0
var _context: = ""
var _intent: = "AUTO"
var _is_serve: = false
var _serve_left: = true
var _end_sign: float = 1.0
var _suppressed_until_release: = false
var mode: = "MOVE"
var cursor_visible: = false

func setup(game) -> void :
	_game = game
	_sync_context()

func update(delta: float, held: bool, direction: Vector2, separate_aim: bool = false) -> void :
	independent_aim = separate_aim
	if not held: _suppressed_until_release = false
	if _game == null: return
	if "practice_launcher" in _game and _game.practice_launcher and _game.practice_launcher.is_exchange() and not _game.practice_launcher.allow_attacks:
		cancel(held)
		cursor_visible = false
		_set_mode("PRACTICE")
		return
	if _game._tool_state_active() or _game.game_state == 3 or _game.ball.freeze and _game.game_state != 1:
		cancel(held)
		cursor_visible = false
		_set_mode("MOVE")
		return
	_sync_context()
	if is_locked():
		cursor_visible = false
		_set_mode("LOCKED")
		return
	var human = _game.player_left.posture.human_contact
	var receiving: bool = _game.game_state == 2 and _game.ball.is_in_play and _game.ball.last_hit_by != 0
	cursor_visible = held and not _suppressed_until_release and (_is_serve or receiving) and (human == null or human.phase < 0)
	if not held or _suppressed_until_release or not (_is_serve or receiving) or human != null and human.phase >= 0:
		planted = false
		_neutral_time = 0.0
		_set_mode("SERVE" if _is_serve else "MOVE")
		return
	if _is_serve:
		planted = true
	else:
		# Hysteresis applies only to the time horizon of a current legal contact.
		# Losing that contact, grounding or footwork readiness still exits now.
		var plant_horizon: float = PLANT_EXIT_LEAD if planted else PLANT_LEAD
		var current_reach: Dictionary = human.release_timing_state() if human != null else {}
		var reachable: bool = bool(current_reach.get("current_reachable", false)) and float(current_reach.get("time", INF)) <= plant_horizon
		if human != null and human.footwork.active and not human.footwork.ready_to_strike(): reachable = false
		var grounded: bool = not _game.player_left.is_jumping and absf(_game.player_left.global_position.y - _game.player_left.ground_y) < 0.03
		if not reachable or not grounded:
			planted = false
			_neutral_time = 0.0
		elif not planted:
			var neutral: bool = separate_aim or direction.length_squared() < 0.01
			_neutral_time = _neutral_time + maxf(0.0, delta) if neutral else 0.0
			planted = _neutral_time >= SETTLE_TIME
			# A live/urgent contact can pass the paddle before the normal 60ms
			# settle period ends. Let the same legal contact used by solo focus
			# lock aim immediately; keep the usual gate for distant preparation.
			if not planted and neutral and float(human.contact.time) <= URGENT_PLANT_LEAD:
				planted = bool(human.release_timing_state().get("current_reachable", false))
	if separate_aim:
		# Aiming never steals the movement stick. Reach still gates focus/contact.
		nudge(direction, delta)
		_set_mode("AIM" if planted or _is_serve else "PREPARE")
	elif planted:
		nudge(direction, delta)
		_set_mode("AIM")
	else:
		_set_mode("PREPARE")

func _sync_context() -> void :
	if is_locked() or _game == null: return
	if _game != null and "practice_launcher" in _game and _game.practice_launcher and _game.practice_launcher.is_wall():
		var key: String = "wall_%d" % int(_game.ball.flight_id)
		if key != _context:
			_context = key
			target = Vector3(0, 1.38, 0.015)
			planted = false
			_neutral_time = 0.0
		_is_serve = false
		_intent = str(_game.selected_shot_intent)
		target = _game.practice_launcher.wall_practice.clamp_target(target)
		return
	var serve: bool = _game.game_state == 0 and (_game.human_may_serve() if _game.has_method("human_may_serve") else _game.serving_team == 0)
	var left: bool = _game.get_server_logical_court() == 0 if _game.has_method("get_server_logical_court") else int(_game.score_left) % 2 == 0
	_end_sign = -1.0 if _game.player_left.court_side == 1 else 1.0
	var intent: String = "AUTO" if serve else str(_game.selected_shot_intent)
	var key: String = "serve_%s_%d" % [left, int(_end_sign)] if serve else "rally_%d_%d" % [int(_game.ball.flight_id), int(_end_sign)]
	if key != _context:
		_context = key
		planted = false
		_neutral_time = 0.0
		_is_serve = serve
		_serve_left = left
		_intent = intent
		target = Vector3(((-1.5 if left else 1.5) if serve else 0.0) * _end_sign, Flight.FLOOR_REST_Y, (-1.15 if intent == "DROP" else -4.6) * _end_sign)
	elif intent != _intent:
		_intent = intent
		target.z = (-1.15 if intent == "DROP" else -4.6) * _end_sign
	target = clamp_target(target, _intent, _is_serve, _serve_left, _end_sign)

static func clamp_target(point: Vector3, intent: String = "AUTO", serve: bool = false, left_box: bool = true, end_sign: float = 1.0) -> Vector3:
	end_sign = -1.0 if end_sign < 0.0 else 1.0
	point = Vector3(point.x * end_sign, point.y, point.z * end_sign)
	var depth: float = clampf( - point.z, 2.6 if serve else MIN_DEPTH, DROP_DEPTH if intent == "DROP" and not serve else MAX_DEPTH)
	var x: float = clampf(point.x, - X_LIMIT, X_LIMIT)
	if serve: x = clampf(x, - X_LIMIT, -0.45) if left_box else clampf(x, 0.45, X_LIMIT)
	return Vector3(x * end_sign, Flight.FLOOR_REST_Y, - depth * end_sign)

func nudge(direction: Vector2, delta: float) -> void :
	if is_locked(): return
	if _game != null and "practice_launcher" in _game and _game.practice_launcher and _game.practice_launcher.is_wall():
		target += Vector3(direction.x, - direction.y, 0) * CURSOR_SPEED * 0.55 * maxf(0.0, delta)
		target = _game.practice_launcher.wall_practice.clamp_target(target)
		return
	target += Vector3(direction.x, 0, direction.y) * CURSOR_SPEED * maxf(0.0, delta)
	target = clamp_target(target, _intent, _is_serve, _serve_left, _end_sign)

func get_target() -> Vector3:
	_sync_context()
	return _locked_target if is_locked() else target

func capture() -> Vector3:
	_sync_context()
	_locked_target = target
	planted = true
	cursor_visible = false
	_set_mode("LOCKED")
	return _locked_target

func release() -> void :
	cancel(Input.is_action_pressed("ui_accept"))
	cursor_visible = false
	_set_mode("MOVE")

func cancel(suppress_held: bool = false) -> void :
	cursor_visible = false
	_locked_target = Vector3.INF
	planted = false
	_neutral_time = 0.0
	_suppressed_until_release = suppress_held

func reset() -> void :
	cancel(Input.is_action_pressed("ui_accept"))
	_context = ""
	cursor_visible = false
	_set_mode("MOVE")

func is_locked() -> bool:
	return _locked_target != Vector3.INF

func should_plant_player() -> bool:
	return is_locked() or planted and not independent_aim

func _set_mode(value: String) -> void :
	mode = value
	if _game != null and _game.hud and _game.hud.has_method("set_aim_state"):
		_game.hud.set_aim_state(value)
