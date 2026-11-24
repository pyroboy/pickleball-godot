extends SceneTree
## Headless perf probe (temporary tool): plays the match as the human (holds HIT while a ball
## comes in, releases near it; pulses HIT to serve) and reports who calls
## stroke_swing_path.blend_pose most in one physics tick. Timings go to logs/perf.jsonl.
## Run: godot --headless --path . --fixed-fps 60 -s tools/_human_perf_probe.gd -- --mobile-runtime --doubles --seed=1 --blend-probe [--hp-seconds=60]
var Path   # loaded at run time: the script needs the autoloads
var _game: Node
var _t := 0.0
var _seconds := 60.0
var _held := false
var _worst := 0
var _worst_callers: Dictionary = {}
var _total: Dictionary = {}
var _ticks := 0
var _busy_ticks := 0

class Driver extends Node:
	var bench
	func _physics_process(delta: float) -> void: bench._tick(delta)

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hp-seconds="): _seconds = float(a.trim_prefix("--hp-seconds="))
	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(_game)
	var d := Driver.new()
	d.bench = self
	d.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child.call_deferred(d)

func _tick(delta: float) -> void:
	_t += delta
	if current_scene != _game and _game.is_inside_tree(): current_scene = _game
	if Path == null: Path = load("res://scripts/around_body.gd")
	# Callers of the tick that just ran.
	var n := 0
	for k in Path._probe: n += int(Path._probe[k])
	_ticks += 1
	if n > 20: _busy_ticks += 1
	for k in Path._probe: _total[k] = int(_total.get(k, 0)) + int(Path._probe[k])
	if n > _worst and _game.ball.is_in_play:
		_worst = n; _worst_callers = Path._probe.duplicate()
	Path._probe.clear()
	if _t < 2.0: return
	var ball = _game.ball
	var player = _game.player_left
	var want := false
	if ball.is_in_play:
		var to_player: Vector3 = player.global_position - ball.global_position
		var incoming: bool = ball.linear_velocity.z > 0.5 and ball.last_hit_by != player.player_num
		want = incoming and Vector2(to_player.x, to_player.z).length() >= 1.4
	else:
		want = fmod(_t, 1.2) < 0.6
	if want and not _held: Input.action_press("ui_accept"); _held = true
	elif not want and _held: Input.action_release("ui_accept"); _held = false
	if _t > _seconds: _report()

func _report() -> void:
	print("PROBE ticks=%d  ticks with over 20 blends=%d  worst tick=%d blends" % [_ticks, _busy_ticks, _worst])
	var keys: Array = _worst_callers.keys()
	keys.sort_custom(func(a, b): return int(_worst_callers[a]) > int(_worst_callers[b]))
	for k in keys.slice(0, 8): print("  worst tick %4d  %s" % [_worst_callers[k], k])
	keys = _total.keys()
	keys.sort_custom(func(a, b): return int(_total[a]) > int(_total[b]))
	for k in keys.slice(0, 10): print("  total %7d  %s" % [_total[k], k])
	quit()
