extends RefCounted


const BallModel = preload("res://scripts/ball.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Profiles = preload("res://scripts/shot_profile.gd")
const Styles = preload("res://scripts/serve_style.gd")
const MAX_CANDIDATES: = 2
const REFINEMENTS: = 5
const MAX_POINTS: = 48

static func solve(start: Vector3, target: Vector3, charge: float, mode: int, intent: String, shot_type: String, arc: float, serve_style: int = -1) -> Dictionary:
	var serve: bool = serve_style >= 0
	var drop: bool = intent == "DROP" and not serve
	var power: float = clampf(charge, 0, 1)
	if serve:
		mode = Styles.spin_mode(serve_style)
		shot_type = "SERVE"
		if serve_style == Styles.Style.HIGH_SOFT:
			power = lerpf(0.02, 0.2, power)
			arc = clampf(arc + 0.22, - 0.1, 0.45)
	elif drop: shot_type = "DROP"
	elif shot_type in ["DINK", "DROP", ""]: shot_type = "GROUNDSTROKE"
	var profile: Dictionary = Profiles.create(mode, power, shot_type).duplicate()
	if serve_style in [Styles.Style.BANANA, Styles.Style.SCREWBALL]:
		profile.topspin_rads = lerpf(9.0, 14.0, charge)
		profile["sidespin_rads"] = (1.0 if serve_style == Styles.Style.BANANA else -1.0) * lerpf(14.0, 22.0, charge)
	var horizontal: float = Vector2(target.x - start.x, target.z - start.z).length()
	var speed_cap: float = clampf(10.0 + horizontal * 0.27, 11.5, 12.5) if drop else BallModel.MAX_SPEED
	var gravity: float = BallModel.get_effective_gravity()
	var drag: float = 0.5 * BallModel.AIR_DENSITY * BallModel.DRAG_COEFFICIENT * PI * BallModel.BALL_RADIUS * BallModel.BALL_RADIUS / BallModel.BALL_MASS * BallModel.AERO_EFFECT_SCALE
	var effective_gravity: float = maxf(3.0, gravity + float(profile.topspin_rads) * BallModel.MAGNUS_COEFFICIENT / BallModel.BALL_MASS * BallModel.AERO_EFFECT_SCALE * 9.0)
	var minimum: float = clampf((exp(drag * horizontal) - 1.0) / (drag * speed_cap), 0.24, 2.32)
	var gentle: float = clampf(sqrt(2.0 * Vector2(horizontal, target.y - start.y).length() / effective_gravity), minimum, 2.32)
	var duration: float = gentle if drop else lerpf(gentle, minimum, pow(power, 0.7))
	var margin: float = 0.14 if serve else 0.12 if drop else 0.08
	if start.z * target.z < 0:
		var fraction: float = absf(start.z) / (absf(start.z) + absf(target.z))
		var net_x: float = lerpf(start.x, target.x, fraction)
		var height_needed: float = Flight.net_clear_y_at(net_x) + margin - lerpf(start.y, target.y, fraction)
		var net_time: float = sqrt(maxf(0, 2.0 * height_needed / (effective_gravity * fraction * (1.0 - fraction))))
		duration = maxf(duration, net_time + 0.05)
	duration = clampf(duration + clampf(arc, - 0.5, 0.5) * 1.2, 0.24, 2.14)
	var best: Dictionary = {}
	var best_score: = INF
	var integration_steps: = 0
	for candidate in MAX_CANDIDATES:
		var time: float = roundf(clampf(duration + candidate * 0.18, 0.24, 2.32) * 60.0) / 60.0
		var travel: Vector3 = Vector3(target.x - start.x, 0, target.z - start.z)
		var velocity: Vector3 = travel.normalized() * ((exp(drag * horizontal) - 1.0) / (drag * time))
		velocity.y = (target.y - start.y) / time + 0.5 * effective_gravity * time
		velocity = velocity.limit_length(speed_cap)
		var omega: = Vector3.ZERO
		var count: int = roundi(time * 60.0)
		for iteration in REFINEMENTS:
			omega = _omega(profile, velocity)
			var position: Vector3 = BallModel.predict_aero_steps(start, velocity, omega, gravity, 1.0 / 60.0, count)[0]
			integration_steps += count
			velocity += (target - Vector3(0, 0.0005, 0) - position) / time * 0.86
			velocity = velocity.limit_length(speed_cap)
		omega = _omega(profile, velocity)
		var flight: Dictionary = Flight.trace(start, velocity, omega, 2.8, 1, false)
		var net: Dictionary = flight.net_crossing
		var clear: bool = start.z * target.z >= 0 or not net.is_empty() and net.pos.y >= Flight.net_clear_y_at(net.pos.x) + margin
		var error: float = flight.first_bounce.distance_to(target) if flight.first_bounce_time >= 0 else INF
		var peak: float = start.y
		for sample in flight.samples: peak = maxf(peak, sample.pos.y)
		var score: float = error * 30.0 + velocity.length() * 0.18 + time * (0.06 + power * 0.3 if drop else power * 2.0)
		if not clear: score += 50
		if peak > 4.6: score += 30
		if score < best_score:
			best_score = score
			best = {"flight": flight, "velocity": velocity, "omega": omega, "duration": time, "landing": flight.first_bounce, "target_error": error, "net_clear": clear, "net_crossing": net.get("pos", Vector3.INF), "feasible": clear and error < 0.2 and peak <= 4.6}
	if best.is_empty(): return {"points": PackedVector3Array(), "integration_steps": integration_steps, "candidates": MAX_CANDIDATES}
	var points: = PackedVector3Array()
	var samples: Array = best.flight.samples
	var stride: int = maxi(1, ceili(float(samples.size()) / MAX_POINTS))
	for index in range(0, samples.size(), stride):
		if not best.net_clear and not best.flight.net_crossing.is_empty() and samples[index].time >= best.flight.net_crossing.time:
			points.append(best.flight.net_crossing.pos)
			break
		points.append(samples[index].pos)
	if best.net_clear and not samples.is_empty() and points.size() < MAX_POINTS: points.append(samples.back().pos)
	best.erase("flight")
	best["points"] = points
	best["integration_steps"] = integration_steps
	best["candidates"] = MAX_CANDIDATES
	return best

static func _omega(profile: Dictionary, velocity: Vector3) -> Vector3:
	return Profiles.angular_velocity(profile, velocity) + Vector3.UP * float(profile.get("sidespin_rads", 0.0))

static func risk_label(estimate: Dictionary) -> String:
	if not estimate.has("landing"): return "ARC UNCERTAIN"
	if not estimate.get("net_clear", false): return "NET RISK"
	var landing: Vector3 = estimate.landing
	if absf(landing.x) > PickleballConstants.COURT_WIDTH * 0.5 or absf(landing.z) > PickleballConstants.BASELINE_Z: return "OUT RISK"
	return "ESTIMATED ARC" if estimate.get("feasible", false) else "ARC UNCERTAIN"
