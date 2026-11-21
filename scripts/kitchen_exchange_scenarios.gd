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
