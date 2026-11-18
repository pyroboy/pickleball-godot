class_name BallFlightPredictor extends RefCounted



const _Ball = preload("res://scripts/ball.gd")
const Boundary = preload("res://scripts/ball_boundary_motion.gd")
const FLOOR_REST_Y: float = _Ball.FLOOR_Y + _Ball.BALL_RADIUS
const _NetProfile = preload("res://scripts/net_profile.gd")

const NET_CLEAR_Y: float = _NetProfile.FLOOR_Y + _NetProfile.CENTER_HEIGHT + _Ball.BALL_RADIUS

static func net_clear_y_at(x: float) -> float:
	return _NetProfile.clear_y_at(x, _Ball.BALL_RADIUS)

static func trace(start_pos: Vector3, start_vel: Vector3, start_omega: Vector3, 
		max_time: float = 3.0, max_bounces: int = 2, stop_at_net: bool = true, collect_samples: bool = true) -> Dictionary:
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var gravity: float = _Ball.get_effective_gravity()
	var pos: Vector3 = start_pos
	var vel: Vector3 = start_vel
	var omega: Vector3 = start_omega
	var samples: Array[Dictionary] = []
	if collect_samples: samples.append({"time": 0.0, "pos": pos, "vel": vel, "omega": omega, "bounces": 0})
	var peak_y: float = pos.y
	var first_bounce: Vector3 = Vector3.ZERO
	var first_bounce_time: float = -1.0
	var bounce_events: Array[Dictionary] = []
	var net_crossing: Dictionary = {}
	var net_hit: bool = false
	var post_hit: Dictionary = {}
	var bounces: int = 0
	var step_count: int = ceili(max_time / dt)

	for step in range(step_count):
		var previous: Vector3 = pos
		var stepped: Array = _Ball.predict_aero_step(pos, vel, omega, gravity, dt)
		pos = stepped[0]
		vel = stepped[1]
		omega = stepped[2]
		if pos.y > _Ball.FLIGHT_CEILING_Y or pos.y < FLOOR_REST_Y and vel.y < 0.0:
			var state: Dictionary = {"samples": samples, "bounces": bounces, "first_bounce": first_bounce, "first_bounce_time": first_bounce_time, "bounce_events": bounce_events, "net_crossing": net_crossing, "net_hit": net_hit, "post_hit": post_hit, "peak_y": peak_y}
			var bounded: Dictionary = _boundary_step(previous, vel, omega, dt, step * dt, state, max_bounces, stop_at_net, collect_samples)
			pos = bounded.position; vel = bounded.velocity; omega = bounded.omega
			bounces = state.bounces; first_bounce = state.first_bounce; first_bounce_time = state.first_bounce_time
			net_crossing = state.net_crossing; net_hit = state.net_hit; post_hit = state.post_hit; peak_y = state.peak_y
			if bounded.stop: break
			continue

		if pos.y > _Ball.FLIGHT_CEILING_Y:
			pos.y = _Ball.FLIGHT_CEILING_Y
			vel.y = minf(vel.y, 0.0)
		var elapsed: float = (step + 1) * dt

		if post_hit.is_empty():
			var post_contact: Dictionary = _NetProfile.post_sweep(previous, pos, _Ball.BALL_RADIUS)
			if post_contact.get("hit", false):
				post_hit = post_contact
				post_hit.time = elapsed - dt + float(post_contact.fraction) * dt
				net_hit = true
				if stop_at_net:
					if collect_samples: samples.append({"time": post_hit.time, "pos": post_contact.point, "vel": vel, "omega": omega, "bounces": bounces})
					break

		if net_crossing.is_empty() and ((previous.z < 0.0 and pos.z >= 0.0) or (previous.z > 0.0 and pos.z <= 0.0)):
			var fraction: float = clampf( - previous.z / (pos.z - previous.z), 0.0, 1.0)
			var crossing: Vector3 = previous.lerp(pos, fraction)
			net_crossing = {"time": elapsed - dt + fraction * dt, "pos": crossing}
			net_hit = not post_hit.is_empty() or _NetProfile.spans_x(crossing.x, _Ball.BALL_RADIUS) and crossing.y <= net_clear_y_at(crossing.x)
			if net_hit and stop_at_net:
				peak_y = maxf(peak_y, crossing.y)
				if collect_samples: samples.append({"time": elapsed, "pos": crossing, "vel": vel, "omega": omega, "bounces": bounces})
				break

		if pos.y < FLOOR_REST_Y and vel.y < 0.0:
			pos.y = FLOOR_REST_Y
			bounces += 1
			if collect_samples: bounce_events.append({"time": elapsed, "pos": pos})
			if bounces == 1:
				first_bounce = pos
				first_bounce_time = elapsed
			var bounced: Array = _Ball.predict_bounce_spin(vel, omega)
			vel = bounced[0]
			omega = bounced[1]

		peak_y = maxf(peak_y, pos.y)
		if collect_samples: samples.append({"time": elapsed, "pos": pos, "vel": vel, "omega": omega, "bounces": bounces})
		if bounces >= max_bounces:
			break

	return {
		"samples": samples,
		"peak_y": peak_y, 
		"first_bounce": first_bounce, 
		"first_bounce_time": first_bounce_time, 
		"bounce_events": bounce_events, 
		"net_crossing": net_crossing, 
		"net_hit": net_hit,
		"post_hit": post_hit, 
	}

static func advance(start_pos: Vector3, start_vel: Vector3, start_omega: Vector3, elapsed: float) -> Dictionary:
	if elapsed <= 0.0:
		return {"pos": start_pos, "vel": start_vel, "omega": start_omega, "bounces": 0}
	# The AI and between-point controller consume only the endpoint. Preserve
	# trace's exact stepping, ceiling, bounce order and 99-bounce termination
	# without materializing the unused per-step trajectory/event dictionaries.
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var gravity: float = _Ball.get_effective_gravity()
	var pos := start_pos
	var vel := start_vel
	var omega := start_omega
	var bounces := 0
	for step in range(ceili(elapsed / dt)):
		var previous: Vector3 = pos
		var stepped: Array = _Ball.predict_aero_step(pos, vel, omega, gravity, dt)
		pos = stepped[0]
		vel = stepped[1]
		omega = stepped[2]
		if pos.y > _Ball.FLIGHT_CEILING_Y or pos.y < FLOOR_REST_Y and vel.y < 0.0:
			var bounded: Dictionary = Boundary.drift(previous, vel, omega, dt)
			pos = bounded.position; vel = bounded.velocity; omega = bounded.omega
			for segment in bounded.segments:
				if segment.event.get("type", "") == "floor":
					bounces += 1
					if bounces >= 99:
						pos = segment.event.point; vel = segment.event.outgoing; omega = segment.event.omega_after; break
			if bounces >= 99: break
			continue
		if pos.y > _Ball.FLIGHT_CEILING_Y:
			pos.y = _Ball.FLIGHT_CEILING_Y
			vel.y = minf(vel.y, 0.0)
		if pos.y < FLOOR_REST_Y and vel.y < 0.0:
			pos.y = FLOOR_REST_Y
			bounces += 1
			var bounced: Array = _Ball.predict_bounce_spin(vel, omega)
			vel = bounced[0]
			omega = bounced[1]
		if bounces >= 99: break
	return {"pos": pos, "vel": vel, "omega": omega, "bounces": bounces}

static func _boundary_step(position: Vector3, velocity: Vector3, omega: Vector3, dt: float, origin_time: float, state: Dictionary, max_bounces: int, stop_at_net: bool, collect: bool) -> Dictionary:
	var bounded: Dictionary = Boundary.drift(position, velocity, omega, dt)
	for segment in bounded.segments:
		var from: Vector3 = segment.from; var to: Vector3 = segment.to
		var start: float = origin_time + float(segment.time_from); var end: float = origin_time + float(segment.time_to)
		if state.post_hit.is_empty():
			var post: Dictionary = _NetProfile.post_sweep(from, to, _Ball.BALL_RADIUS)
			if post.get("hit", false):
				state.post_hit = post; state.post_hit.time = lerpf(start, end, float(post.fraction)); state.net_hit = true
				if stop_at_net:
					if collect: state.samples.append({"time": state.post_hit.time, "pos": post.point, "vel": segment.velocity, "omega": segment.omega, "bounces": state.bounces})
					return {"position": post.point, "velocity": segment.velocity, "omega": segment.omega, "stop": true}
		if state.net_crossing.is_empty() and ((from.z < 0.0 and to.z >= 0.0) or (from.z > 0.0 and to.z <= 0.0)):
			var fraction: float = clampf(-from.z / (to.z-from.z), 0.0, 1.0)
			var crossing: Vector3 = from.lerp(to, fraction)
			state.net_crossing = {"time": lerpf(start,end,fraction), "pos": crossing}
			state.net_hit = not state.post_hit.is_empty() or _NetProfile.spans_x(crossing.x,_Ball.BALL_RADIUS) and crossing.y <= net_clear_y_at(crossing.x)
			if state.net_hit and stop_at_net:
				state.peak_y = maxf(state.peak_y,crossing.y)
				if collect: state.samples.append({"time": state.net_crossing.time, "pos": crossing, "vel": segment.velocity, "omega": segment.omega, "bounces": state.bounces})
				return {"position": crossing, "velocity": segment.velocity, "omega": segment.omega, "stop": true}
		state.peak_y = maxf(state.peak_y,maxf(from.y,to.y))
		if segment.event.get("type", "") == "floor":
			state.bounces += 1
			if collect: state.bounce_events.append({"time": end, "pos": to})
			if state.bounces == 1: state.first_bounce = to; state.first_bounce_time = end
			if collect: state.samples.append({"time": end, "pos": to, "vel": segment.event.outgoing, "omega": segment.event.omega_after, "bounces": state.bounces})
			if state.bounces >= max_bounces:
				return {"position": to, "velocity": segment.event.outgoing, "omega": segment.event.omega_after, "stop": true}
	if collect: state.samples.append({"time": origin_time+dt, "pos": bounded.position, "vel": bounded.velocity, "omega": bounded.omega, "bounces": state.bounces})
	return {"position": bounded.position, "velocity": bounded.velocity, "omega": bounded.omega, "stop": not bounded.complete}
