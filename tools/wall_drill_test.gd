extends SceneTree
## Headless wall-drill check: loads the match, starts the WALL practice drill and plays it
## as the human (holds HIT while the fed / rebounding ball comes in, releases when it is
## close). Reports returns, wall rebounds, how each attempt ended, contact holds and
## whether the tree ever got stuck paused.
## Run: godot --headless --path . --fixed-fps 60 -s tools/wall_drill_test.gd -- --mobile-runtime [--wd-seconds=40]

var _game: Node
var _frame := 0
var _t := 0.0
var _seconds := 40.0
var _started := false
var _held := false
var _paused_frames := 0
var _max_paused_run := 0
var _paused_run := 0
var _statuses: Array = []
var _holds: Array = []
var _last_status := ""

class Driver extends Node:
	var bench
	func _physics_process(delta: float) -> void: bench._tick(delta)

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wd-seconds="): _seconds = float(a.trim_prefix("--wd-seconds="))
	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(_game)
	var d := Driver.new()
	d.bench = self
	d.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child.call_deferred(d)

func _tick(delta: float) -> void:
	_frame += 1
	_t += delta
	if current_scene != _game and _game.is_inside_tree(): current_scene = _game
	if _frame == 45:
		_game.practice_launcher.start_drill("WALL")
		_started = true
	if not _started: return
	var p = _game.practice_launcher
	if p.status_text != _last_status:
		_last_status = p.status_text
		_statuses.append("%5.1fs %s" % [_t, _last_status])
	var ca = _game.contact_authority
	if ca != null and not ca.unresolved_continuation.is_empty():
		var reason := str(ca.unresolved_continuation.get("reason", "?"))
		if _holds.is_empty() or _holds[-1] != reason: _holds.append("%.1fs %s" % [_t, reason])
	if paused:
		_paused_run += 1
		_paused_frames += 1
		_max_paused_run = maxi(_max_paused_run, _paused_run)
		# A stuck pause would block the drill forever; resume like a player would.
		if _paused_run > 60:
			var pc = root.get_node_or_null("PauseController")
			if pc: pc.close()
	else:
		_paused_run = 0
	# Play as the human: hold HIT while the ball comes toward the player, release near it.
	var ball = _game.ball
	var player = _game.player_left
	var to_player: Vector3 = player.global_position - ball.global_position
	var incoming: bool = ball.is_in_play and ball.linear_velocity.z > 0.5
	if incoming and not _held:
		Input.action_press("ui_accept"); _held = true
	elif _held and (not incoming or Vector2(to_player.x, to_player.z).length() < 1.4):
		Input.action_release("ui_accept"); _held = false
	if _t > 1.5 + _seconds: _report()

func _report() -> void:
	var p = _game.practice_launcher
	var w = p.wall_practice
	print("WALL DRILL  attempts=%d returns=%d rebounds=%d targets=%d" % [p.attempt_count, w.returns, w.rebounds, w.targets])
	print("paused frames=%d  longest pause=%d frames" % [_paused_frames, _max_paused_run])
	print("contact holds: %s" % [", ".join(_holds) if not _holds.is_empty() else "none"])
	for s in _statuses.slice(0, 60): print("  ", s)
	quit()
