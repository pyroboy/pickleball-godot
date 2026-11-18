extends RefCounted


const Base = preload("res://scripts/tests/fixtures/charged_footwork_fixture.gd")

static func cases() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for distance in [3.0, 4.0, 5.0]:
		for side in [1.0, -1.0]:
			result.append({"name": "%dm_%s" % [int(distance), "fh" if side > 0 else "bh"], "lateral": distance * side, "height": 1.1, "duration": 1.6, "family": 0 if side > 0 else 1})
	return result

static func prepare(game, data: Dictionary, solo: bool = false) -> Dictionary:
	Base.configure(game)
	Base.prepare(game, {"root_z": 4.7, "lateral": 1.0, "height": 1.1, "forward": 0.7, "duration": 1.85})
	game.pvp_mode = not solo
	game.aim_focus._sync_realtime_mode()
	var player = game.player_left
	var lateral: float = data.get("lateral", 4.0)
	player.global_position = Vector3(-2.6 * signf(lateral), player.ground_y, float(data.get("root_z", 4.7)))
	player.current_velocity = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player.leg_ik.feet_initialized = false
	player._process(0.0)
	player.can_volley_from_feet()
	var target: Vector3 = player.global_position + player._get_forehand_axis() * lateral + player._get_forward_axis() * float(data.get("forward", PostureLibrary.instance().get_def(0 if lateral > 0.0 else 2).zone_forward_offset))
	target.y = float(data.get("height", 1.1))
	var origin: Vector3 = Vector3(target.x * 0.35, 1.1, -2.4)
	var launch: Dictionary = game.practice_launcher.solve_airborne_feed(origin, target, float(data.get("duration", 1.6)))
	game.ball.global_position = origin
	game.ball.linear_velocity = launch.velocity
	game.ball.angular_velocity = launch.omega
	game.ball.flight_id += 1
	return {"root": player.global_position, "origin": origin, "target": target, "flight": game.ball.flight_id}

static func press(game) -> void : Base.press(game)
static func release(game) -> void : Base.release(game)
static func tick(game) -> void : Base.tick_input(game)
