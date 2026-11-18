extends RefCounted
## Shared court-frame snapshot. Never uses visual pelvis rotation as court axes.
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Context = preload("res://scripts/shot_motion_context.gd")

static func capture(player, ball, base: PostureDefinition, point: Vector3, time: float, options: Dictionary = {}) -> Dictionary:
	var delta: Vector3 = point - player.global_position
	var raw: Dictionary = options.duplicate(true)
	raw["incoming_velocity"] = ball.linear_velocity
	raw["contact_local"] = Vector3(delta.dot(player._get_forehand_axis()), point.y, delta.dot(player._get_forward_axis()))
	raw["contact_height"] = point.y
	raw["bounces"] = int(options.get("bounces", ball.bounces_since_last_hit))
	raw["time_since_bounce"] = float(ball.time_since_last_bounce) if "time_since_last_bounce" in ball and int(raw.bounces) == ball.bounces_since_last_hit else -1.0
	raw["required_bounces"] = int(raw.bounces)
	raw["velocity_source"] = "observed"
	raw["bounce_age_source"] = "observed"
	if int(raw.bounces) > ball.bounces_since_last_hit and time > 0.0:
		# Begin a short-hop preparation before the floor impact without granting
		# an early volley. Admission uses the same physical forecast; contact
		# later requires the real observed bounce count to match this promise.
		var forecast: Dictionary = Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity, minf(2.0, time + 0.035), 2, true)
		var last_bounce := -1.0
		for event in forecast.get("bounce_events", []):
			if float(event.time) <= time: last_bounce = float(event.time)
		if last_bounce >= 0.0:
			raw["time_since_bounce"] = maxf(0.0, time - last_bounce)
			raw["bounce_age_source"] = "forecast"
			var samples: Array = forecast.get("samples", [])
			for sample in samples:
				if float(sample.time) >= time:
					raw["incoming_velocity"] = sample.vel
					raw["velocity_source"] = "forecast"
					break
	raw["time_to_contact"] = maxf(0.0, time)
	raw["near_kitchen"] = absf(player.global_position.z) <= PickleballConstants.NON_VOLLEY_ZONE + 0.65
	raw["flight_id"] = ball.flight_id
	raw["ball_behind"] = delta.dot(player._get_forward_axis()) < -0.35
	raw["lob_retrieval"] = bool(raw.ball_behind) and (point.y >= 1.1 or delta.dot(player._get_forward_axis()) < -0.7)
	return Context.commit(base, raw)

static func apply_feet(player, context: Dictionary) -> void:
	if "leg_ik" in player and player.leg_ik != null and player.leg_ik.has_method("set_shot_context"):
		player.leg_ik.set_shot_context(context)

static func clear_feet(player) -> void:
	if "leg_ik" in player and player.leg_ik != null and player.leg_ik.has_method("clear_shot_context"):
		player.leg_ik.clear_shot_context()
