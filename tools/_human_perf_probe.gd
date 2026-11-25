extends SceneTree
## Headless human-seat probe: plays the match as the human (holds HIT while a ball comes in,
## releases near it; pulses HIT to serve). Timings go to logs/perf.jsonl (or --perf-out=).
## tools/human_seat_bench.sh runs it and sums the human seat's tick cost.
## Run: godot --headless --path . --fixed-fps 60 -s tools/_human_perf_probe.gd -- --mobile-runtime --doubles --seed=1 [--hp-seconds=60]
##   --perf-toggles=human_plan_once=0,touch_on_change=1   set PerfToggles before the match loads
##   --blend-probe   also report who calls stroke_swing_path.blend_pose most in one tick
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
var _blend := false
var _presses := 0
var _hits := 0
var _flight := -1

class Driver extends Node:
	var bench
	func _physics_process(delta: float) -> void: bench._tick(delta)

func _initialize() -> void:
	var toggles = load("res://scripts/debug/perf_toggles.gd")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hp-seconds="): _seconds = float(a.trim_prefix("--hp-seconds="))
		if a == "--blend-probe": _blend = true
		if a.begins_with("--perf-toggles="):
			for kv in a.trim_prefix("--perf-toggles=").split(",", false):
				var parts: PackedStringArray = kv.split("=")
				if parts.size() == 2: toggles.set_toggle(parts[0], parts[1] not in ["0", "false", "off"])
	var state: PackedStringArray = []
	for n in toggles.NAMES: state.append("%s=%d" % [n, int(toggles.get_toggle(n))])
	print("PROBE toggles: " + ", ".join(state))
	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(_game)
	var d := Driver.new()
	d.bench = self
	d.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child.call_deferred(d)

func _tick(delta: float) -> void:
	_t += delta
	if current_scene != _game and _game.is_inside_tree(): current_scene = _game
	if _blend: _blend_tick()
	if _t < 2.0: return
	var ball = _game.ball
	var player = _game.player_left
	if ball.flight_id != _flight:
		_flight = ball.flight_id
		if ball.is_in_play and ball.last_hit_by == player.player_num: _hits += 1
	var want := false
	if ball.is_in_play:
		var to_player: Vector3 = player.global_position - ball.global_position
		var incoming: bool = ball.linear_velocity.z > 0.5 and ball.last_hit_by != player.player_num
		want = incoming and Vector2(to_player.x, to_player.z).length() >= 1.4
	else:
		want = fmod(_t, 1.2) < 0.6
	if want and not _held: _set_hit(true); _held = true; _presses += 1
	elif not want and _held: _set_hit(false); _held = false
	if _t > _seconds: _report()

## HIT goes through the touch pad like a thumb (mobile_controls.gd), so the touch path is timed
## too; without the portrait touch controls it falls back to the ui_accept action.
func _set_hit(down: bool) -> void:
	var mobile = _game.get("mobile_controls")
	if mobile == null or not mobile.enabled:
		if down: Input.action_press("ui_accept")
		else: Input.action_release("ui_accept")
		return
	var ev := InputEventScreenTouch.new()
	ev.index = 3
	ev.pressed = down
	ev.position = mobile._charge_center
	mobile._input(ev)

func _blend_tick() -> void:
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

func _report() -> void:
	if _held: _set_hit(false); _held = false
	print("PROBE done: %.0f s, HIT presses %d, human-side hits %d" % [_t, _presses, _hits])
	if _blend:
		print("PROBE ticks=%d  ticks with over 20 blends=%d  worst tick=%d blends" % [_ticks, _busy_ticks, _worst])
		var keys: Array = _worst_callers.keys()
		keys.sort_custom(func(a, b): return int(_worst_callers[a]) > int(_worst_callers[b]))
		for k in keys.slice(0, 8): print("  worst tick %4d  %s" % [_worst_callers[k], k])
		keys = _total.keys()
		keys.sort_custom(func(a, b): return int(_total[a]) > int(_total[b]))
		for k in keys.slice(0, 10): print("  total %7d  %s" % [_total[k], k])
	quit()
