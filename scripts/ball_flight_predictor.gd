class_name BallFlightPredictor extends RefCounted

## Predicts the free flight used by gameplay, including the manual floor bounce.
## The returned samples carry time, position, velocity, spin and bounce count.
const _Ball = preload("res://scripts/ball.gd")
const FLOOR_REST_Y: float = _Ball.FLOOR_Y + _Ball.BALL_RADIUS
const NET_CLEAR_Y: float = PickleballConstants.NET_HEIGHT + _Ball.BALL_RADIUS

static func trace(start_pos: Vector3, start_vel: Vector3, start_omega: Vector3,
		max_time: float = 3.0, max_bounces: int = 2, stop_at_net: bool = true) -> Dictionary:
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var gravity: float = _Ball.get_effective_gravity()
	var pos: Vector3 = start_pos
	var vel: Vector3 = start_vel
	var omega: Vector3 = start_omega
	var samples: Array[Dictionary] = [{"time": 0.0, "pos": pos, "vel": vel, "omega": omega, "bounces": 0}]
	var first_bounce: Vector3 = Vector3.ZERO
	var first_bounce_time: float = -1.0
	var bounce_events: Array[Dictionary] = []
	var net_crossing: Dictionary = {}
	var net_hit: bool = false
	var bounces: int = 0
	var step_count: int = ceili(max_time / dt)

	for step in range(step_count):
		var previous: Vector3 = pos
		var stepped: Array = _Ball.predict_aero_step(pos, vel, omega, gravity, dt)
		pos = stepped[0]
		vel = stepped[1]
		omega = stepped[2]
		var elapsed: float = (step + 1) * dt

		if net_crossing.is_empty() and ((previous.z < 0.0 and pos.z >= 0.0) or (previous.z > 0.0 and pos.z <= 0.0)):
			var fraction: float = clampf(-previous.z / (pos.z - previous.z), 0.0, 1.0)
			var crossing: Vector3 = previous.lerp(pos, fraction)
			net_crossing = {"time": elapsed - dt + fraction * dt, "pos": crossing}
			net_hit = crossing.y <= NET_CLEAR_Y
			if net_hit and stop_at_net:
				samples.append({"time": elapsed, "pos": crossing, "vel": vel, "omega": omega, "bounces": bounces})
				break

		if pos.y < FLOOR_REST_Y and vel.y < 0.0:
			pos.y = FLOOR_REST_Y
			bounces += 1
			bounce_events.append({"time": elapsed, "pos": pos})
			if bounces == 1:
				first_bounce = pos
				first_bounce_time = elapsed
			var bounced: Array = _Ball.predict_bounce_spin(vel, omega)
			vel = bounced[0]
			omega = bounced[1]

		samples.append({"time": elapsed, "pos": pos, "vel": vel, "omega": omega, "bounces": bounces})
		if bounces >= max_bounces:
			break

	return {
		"samples": samples,
		"first_bounce": first_bounce,
		"first_bounce_time": first_bounce_time,
		"bounce_events": bounce_events,
		"net_crossing": net_crossing,
		"net_hit": net_hit,
	}

static func advance(start_pos: Vector3, start_vel: Vector3, start_omega: Vector3, elapsed: float) -> Dictionary:
	if elapsed <= 0.0:
		return {"pos": start_pos, "vel": start_vel, "omega": start_omega}
	var flight: Dictionary = trace(start_pos, start_vel, start_omega, elapsed, 99, false)
	var sample: Dictionary = flight["samples"].back()
	return {"pos": sample["pos"], "vel": sample["vel"], "omega": sample["omega"]}
