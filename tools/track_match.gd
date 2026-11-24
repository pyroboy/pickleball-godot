extends SceneTree
## Pass 1 for the reel: plays the AI match at normal speed and writes, every frame, the
## physics tick, the interpolation fraction, the ball and the four players (as drawn), plus
## every hit, so a camera can be planned with the future known.
## Run: godot --path . --resolution 1080x1920 --fixed-fps 30 -s tools/track_match.gd -- \
##        --mobile-runtime --autoplay --doubles --seed=4 --track-out=<file> [--track-ticks=4400]

var _game: Node
var _f: FileAccess
var _ticks := 4400
var _on := false

class Driver extends Node:
	var d
	func _process(_delta: float) -> void: d._tick()

func _initialize() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--track-out="): out = arg.trim_prefix("--track-out=")
		if arg.begins_with("--track-ticks="): _ticks = int(arg.trim_prefix("--track-ticks="))
	_f = FileAccess.open(out, FileAccess.WRITE)
	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child.call_deferred(_game)
	var dr := Driver.new()
	dr.d = self
	dr.process_mode = Node.PROCESS_MODE_ALWAYS
	dr.process_priority = 10000
	root.add_child.call_deferred(dr)

func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]

func _on_hit(actor_id: int, team: int, _side: int) -> void:
	var b: Vector3 = _game.ball.global_position
	_f.store_line(JSON.stringify({"hit": actor_id, "team": team, "tick": Engine.get_physics_frames(), "pos": _v(b), "vel": _v(_game.ball.linear_velocity)}))

func _tick() -> void:
	if not _on:
		if is_instance_valid(_game) and _game.is_inside_tree():
			current_scene = _game
			_game.ball.actor_hit_paddle.connect(_on_hit)
			_on = true
		return
	var tick: int = Engine.get_physics_frames()
	var row := {"t": tick, "fr": snappedf(Engine.get_physics_interpolation_fraction(), 0.001),
		"st": int(_game.game_state), "b": _v(_game.ball.get_global_transform_interpolated().origin)}
	var ps: Array = []
	for p in _game.get_players():
		ps.append([p.get_actor_id(), p.team_id, _v(p.get_global_transform_interpolated().origin), int(p.paddle_posture)])
	row["p"] = ps
	_f.store_line(JSON.stringify(row))
	if tick >= _ticks:
		_f.flush()
		quit()
