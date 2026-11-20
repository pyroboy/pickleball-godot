extends SceneTree
## Headless tests for the ball-hits-player reaction (scripts/fx/body_hit_fx.gd):
## the ball deflects off the body, the spark/burst and "Ouch!" bubble spawn and
## free themselves, and the shared global RNG is never drawn from.
## Run: godot --headless --path . -s tools/body_hit_fx_tests.gd

var Fx   # loaded in _run: autoloads (PerfMonitor) must exist first

class FakeScorer extends Node:
	signal body_struck(actor_id: int, evidence: Dictionary)

class FakeBall extends RigidBody3D:
	var flight_id := 7

class FakeGame extends Node:
	var ball: FakeBall
	var rally_scorer: FakeScorer
	var players := {}
	func get_player_by_actor_id(id: int):
		return players.get(id)

var _fails := 0
var _checks := 0

func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond: _fails += 1
	print("PASS  " if cond else "FAIL  ", label)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _named(node: Node, prefix: String) -> int:
	var count := 0
	for child in node.get_children():
		if str(child.name).contains(prefix): count += 1
	return count

func _run() -> void:
	Fx = load("res://scripts/fx/body_hit_fx.gd")
	# Deflection maths over many random incoming hits.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var all_out := true
	var all_slower := true
	var all_moving := true
	for i in 500:
		var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.3), rng.randf_range(-1, 1)).normalized() * rng.randf_range(3.0, 22.0)
		var n := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3), rng.randf_range(-1, 1))
		if i % 50 == 0: n = Vector3.ZERO   # missing normal: fallback path
		var r: Dictionary = Fx.deflect(v, n, -v + Vector3(0.01, 0, 0), rng)
		var out: Vector3 = r.velocity
		all_out = all_out and out.dot(r.normal) > 0.0 and Vector3(r.normal).dot(v) <= 0.0
		all_slower = all_slower and out.length() < v.length() + 2.0
		all_moving = all_moving and out.length() > 0.8
	_check(all_out, "deflected ball always leaves the body (never back into it)")
	_check(all_slower, "deflection loses energy (soft body)")
	_check(all_moving, "deflected ball never stops dead")

	# Scene check through the signal, as the game wires it.
	var game := FakeGame.new()
	game.ball = FakeBall.new()
	game.ball.gravity_scale = 0.0
	game.rally_scorer = FakeScorer.new()
	var player := Node3D.new()
	var head := Node3D.new()
	head.name = "HeadMesh"
	head.position = Vector3(0, 0.65, 0)
	player.add_child(head)
	player.position = Vector3(0.5, 1.0, -3.0)
	game.players[2] = player
	root.add_child(game)
	game.add_child(game.ball)
	game.add_child(game.rally_scorer)
	game.add_child(player)
	var fx = Fx.new()
	game.add_child(fx)
	fx.setup(game)
	var spawned: Array = []
	fx.fx_spawned.connect(func(kind, node): spawned.append([kind, node]))

	var incoming := Vector3(0.0, -1.0, -11.0)   # drive coming at the player's front (+z face)
	game.ball.global_position = Vector3(0.45, 1.2, -3.25)
	game.ball.linear_velocity = incoming
	seed(1234)
	var expected_global: int = randi()
	seed(1234)
	game.rally_scorer.body_struck.emit(2, {"point": Vector3(0.45, 1.2, -2.8), "normal": Vector3(0, 0, -1), "part": "ChestMesh"})
	_check(randi() == expected_global, "shared global RNG untouched by the deflection")
	var out: Vector3 = game.ball.linear_velocity
	_check(out.z > 1.0, "ball bounces back off the body (vz %.2f -> %.2f)" % [incoming.z, out.z])
	_check(out.length() > 1.5 and out.length() < incoming.length(), "outgoing speed %.2f m/s: deflected with energy loss, not stopped" % out.length())
	_check(game.ball.global_position.z > -2.8, "ball pushed out of the body to the front")
	var first_out := out
	game.ball.linear_velocity = incoming
	game.ball.global_position = Vector3(0.45, 1.2, -3.25)
	game.rally_scorer.body_struck.emit(2, {"point": Vector3(0.45, 1.2, -2.8), "normal": Vector3(0, 0, -1)})
	_check(game.ball.linear_velocity.is_equal_approx(first_out), "same hit gives the same bounce (bench reproducible)")

	_check(_named(fx, "OuchBubble") == 1, "one Ouch bubble per player (a repeat hit restarts it)")
	var kinds: Array = spawned.map(func(e): return e[0])
	_check(kinds.count("spark") == 2 and kinds.count("burst") == 2 and spawned.all(func(e): return e[1].get_parent() == fx), "spark and burst spawned at the impact for each hit")
	var bubble: Node3D = fx.get_node("OuchBubble")
	var label: Label3D = bubble.get_child(1)
	_check(label.text == "Ouch!", "bubble says Ouch!")
	_check(bubble.global_position.y > head.global_position.y, "bubble sits above the head")
	_check(not player.is_ancestor_of(bubble), "effects are not parented under the player")

	# Legacy capsule path: no evidence -> no deflection, still the visuals.
	game.ball.linear_velocity = incoming
	game.rally_scorer.body_struck.emit(2, {})
	_check(game.ball.linear_velocity == incoming, "capsule contact (physics already bounced it) is not deflected again")

	var start: int = Time.get_ticks_msec()
	var mid_alpha := -1.0
	while Time.get_ticks_msec() - start < 1400:
		await process_frame
		if mid_alpha < 0.0 and Time.get_ticks_msec() - start > 300 and is_instance_valid(label): mid_alpha = label.modulate.a
	await process_frame
	_check(mid_alpha > 0.9, "bubble fully visible early on (alpha %.2f at 0.3 s)" % mid_alpha)
	_check(fx.active_count() == 0 and fx.get_child_count() == 0, "bubble, spark and burst freed after ~1 s (%d children left)" % fx.get_child_count())
	print("body hit fx tests: %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
