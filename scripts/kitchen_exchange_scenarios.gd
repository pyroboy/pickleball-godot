extends RefCounted


const Flight = preload("res://scripts/ball_flight_predictor.gd")
const LANES: = [1.53, 0.65, 1.85, 0.45, 1.25, 0.95]
const DEPTHS: = [1.3, 1.45, 1.1, 1.48, 1.25, 1.35]
const CASES: = ["WIDE", "CENTER", "ACUTE", "SHORT_LOW", "SAFE_DINK", "NET_POPUP", "HIGH_POPUP", "UNREACHABLE"]

static func dink_target(pattern: String, exchange: int, team: int, diagonal: int) -> Vector3:
	var side: float = -1.0 if team == 0 else 1.0
	var index: int = int(exchange / 2) % LANES.size()
	var lane: float = LANES[index] if pattern != "STANDARD" else 1.05
	var depth: float = DEPTHS[index] if pattern != "STANDARD" else 1.3
	return Vector3(side * diagonal * lane, Flight.FLOOR_REST_Y, side * depth)

static func recovery_x(receiver_x: float, diagonal_home: float) -> float:


	return clampf( - receiver_x * 0.38 + diagonal_home * 0.16, -1.1, 1.1)

static func receive_target(player_position: Vector3, flight: Dictionary, total_bounces: int, 
		require_bounce: bool, safe_z: float, move_speed: float) -> Vector3:
	var best: = Vector3.INF
	var best_score: = INF
	var samples: Array = flight.get("samples", [])
	for index in range(1, samples.size(), 3):
		var sample: Dictionary = samples[index]
		var point: Vector3 = sample.pos
		var bounces: int = total_bounces + int(sample.bounces)
		if point.z <= 0.05 or bounces >= 2 or (require_bounce and bounces == 0): continue
		if point.y < Flight.FLOOR_REST_Y + 0.18 or point.y > 2.15: continue
		var target: = Vector3(clampf(point.x, -2.65, 2.65), player_position.y, clampf(point.z + 0.52, 1.55, 3.25))
		if bounces == 0: target.z = maxf(target.z, safe_z)


		if target.z - point.z > 0.68: continue
		var travel: float = Vector2(target.x - player_position.x, target.z - player_position.z).length()
		var time: float = float(sample.time)
		if travel > move_speed * time + 0.1: continue
		var score: float = time + travel * 0.045 + (0.1 if point.y < 0.4 else 0.0)
		if score < best_score:
			best_score = score
			best = target
	return best

static func movement_input(offset: Vector3, current_velocity: Vector3, move_speed: float, delta: float) -> Vector3:
	offset.y = 0.0
	if offset.length() < 0.035: return Vector3.ZERO
	var speed: float = minf(move_speed, sqrt(18.0 * offset.length()))
	speed = minf(speed, offset.length() / maxf(delta, 0.001))
	var desired: Vector3 = offset.normalized() * speed
	var current: = Vector3(current_velocity.x, 0.0, current_velocity.z)
	return current.move_toward(desired, 18.0 * delta) / maxf(move_speed, 0.1)

static func review_case(kind: String, receiver: int, diagonal: int = 1) -> Dictionary:
	var side: float = 1.0 if receiver == 0 else -1.0
	var lane: float = side * diagonal
	var result: = {"kind": kind, "receiver": receiver, 
		"player": Vector3(lane * 0.55, 0, side * 2.72), 
		"origin": Vector3( - lane * 1.15, 0.72, - side * 1.55), 
		"target": Vector3(lane * 1.05, Flight.FLOOR_REST_Y, side * 1.3), 
		"duration": 0.0}
	match kind:
		"WIDE": result.target.x = lane * 1.75
		"CENTER":
			result.player.x = lane * 1.75
			result.target.x = lane * 0.4
		"ACUTE":
			result.origin.x = - lane * 1.9
			result.target = Vector3(lane * 1.95, Flight.FLOOR_REST_Y, side * 1.12)
		"SHORT_LOW": result.target = Vector3(lane * 0.9, Flight.FLOOR_REST_Y, side * 0.88)
		"NET_POPUP", "HIGH_POPUP":
			result.player.x = lane * 0.4
			result.origin = Vector3( - lane * 0.15, 1.05, - side * 1.85)
			result.target = Vector3(lane * 0.4, 1.2 if kind == "NET_POPUP" else 1.95, side * 2.18)
			result.duration = 0.88 if kind == "NET_POPUP" else 1.1
		"UNREACHABLE":
			result.player.x = - lane * 2.3


			result.origin = Vector3(lane * 2.1, 0.45, side * 1.3)
			result.target = Vector3(lane * 2.1, 0.2, side * 2.0)
			result.duration = 0.12
	return result
