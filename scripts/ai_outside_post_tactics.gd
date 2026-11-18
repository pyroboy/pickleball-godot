extends RefCounted
## A low outside-post route is a geometric target choice, not an animation
## override. Only a real bounced, off-court contact can enter this policy.
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Net = preload("res://scripts/net_profile.gd")
const BallScript = preload("res://scripts/ball.gd")

static func choose(physics, ball, point: Vector3, team: int) -> Dictionary:
	if physics == null or ball == null or not ball.is_in_play: return {}
	if ball.last_hit_by == team or ball.bounces_since_last_hit != 1: return {}
	var own: float = 1.0 if team == 0 else -1.0
	if not point.is_finite() or point.z * own <= BallScript.BALL_RADIUS: return {}
	if absf(point.x) <= Net.HALF_COURT_WIDTH + BallScript.BALL_RADIUS: return {}
	if point.y <= Flight.FLOOR_REST_Y or point.y >= Net.top_y_at(Net.HALF_SPAN): return {}
	# Two safe in-court targets keep the probe bounded and on the same side
	# of the post. A crossing through the net/post can never qualify.
	for depth in [4.5, 5.5]:
		var target := Vector3(signf(point.x) * 2.45, Flight.FLOOR_REST_Y, -own * depth)
		var solved: Dictionary = physics.solve_aimed_launch(point, target, .85, team, 0, "DRIVE", "GROUNDSTROKE", 0.0, true)
		if not solved.get("feasible", false) or not solved.get("net_clear", false): continue
		var trace: Dictionary = Flight.trace(point, solved.velocity, solved.omega, 3.0, 1, false, false)
		var crossing: Dictionary = trace.get("net_crossing", {})
		if crossing.is_empty() or trace.get("net_hit", false) or trace.get("post_hit", false): continue
		var cross_point: Vector3 = crossing.pos
		if absf(cross_point.x) <= Net.HALF_SPAN + BallScript.BALL_RADIUS or cross_point.y >= Net.top_y_at(Net.HALF_SPAN): continue
		var landing: Vector3 = trace.get("first_bounce", Vector3.INF)
		if not landing.is_finite() or absf(landing.x) >= 2.8 or landing.z * -own <= .3 or landing.z * -own >= 6.4: continue
		return {"kind": "DRIVE", "target": target, "charge": .85, "shot_type": "GROUNDSTROKE",
			"intent": "DRIVE", "arc": 0.0, "spin_mode": 0, "route": "AROUND_POST",
			"route_crossing": cross_point, "route_landing": landing}
	return {}
