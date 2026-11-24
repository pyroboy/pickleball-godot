extends RefCounted
## Dink flight (docs/SHOT_QUALITY_PLAN.md, proposal D): the lowest arc to a kitchen target.
##
## A soft shot to the kitchen is refitted at contact so that it crosses the net `margin` m over
## the tape and still lands on its planned spot. The margin is the skill: a clean hit by a better
## player (or your PERFECT release) crosses lower. The mishit float is added after this, so a
## poor contact rises from here and gets attacked.
##
## Apex rule: a good dink is already falling as it crosses. When the fitted arc still peaks past
## the net and the target allows it, the landing is pulled toward the net (never under
## MIN_DEPTH) until the apex is at or before it. From a low contact right at the net that
## cannot be done; the flight then grades Loose, which is the truth of that contact.
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const _Ball = preload("res://scripts/ball.gd")

const MAX_ORIGIN := 4.6     # m from the net: farther back it is a drop, planned elsewhere
const MAX_DEPTH := 2.7      # m past the net the planned landing may be (kitchen, or just past it)
const MIN_DEPTH := 0.75     # m past the net: the shortest landing the apex rule pulls to
const PULL_STEP := 0.3
const FIT_PASSES := 4

## Returns the refitted velocity, or `velocity` unchanged when this is not a kitchen shot or no
## arc fits. `origin` is the ball at contact.
static func fit(origin: Vector3, velocity: Vector3, omega: Vector3, margin: float) -> Vector3:
	if absf(origin.z) > MAX_ORIGIN or absf(origin.z) < 0.05: return velocity
	var side: float = signf(origin.z)
	var plan: Dictionary = Flight.trace(origin, velocity, omega, 3.0, 1, false, false)
	if float(plan.first_bounce_time) <= 0.0 or plan.net_crossing.is_empty(): return velocity
	var landing: Vector3 = plan.first_bounce
	var depth: float = -landing.z * side
	if depth <= 0.2 or depth > MAX_DEPTH: return velocity
	var best: Vector3 = velocity
	var found: bool = false
	while true:
		var target := Vector3(landing.x, landing.y, -depth * side)
		var solved: Dictionary = _fit_to(origin, omega, target, margin)
		if solved.is_empty(): break
		best = solved.velocity
		found = true
		if float(solved.apex_past) <= 0.0 or depth - PULL_STEP < MIN_DEPTH: break
		depth -= PULL_STEP
	return best if found else velocity

## One arc from `origin` through `margin` over the tape to `target`: a drag-free first guess,
## then a few corrections against the real flight.
static func _fit_to(origin: Vector3, omega: Vector3, target: Vector3, margin: float) -> Dictionary:
	var flat := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	var reach: float = flat.length()
	if reach < 0.3 or absf(flat.z) < 0.05: return {}
	var dir: Vector3 = flat / reach
	var to_net: float = reach * absf(origin.z) / absf(flat.z)      # along the ground to the net
	if to_net <= 0.02 or to_net >= reach - 0.05: return {}
	var cross_x: float = origin.x + dir.x * to_net
	var gravity: float = _Ball.get_effective_gravity()
	var net_y: float = Flight.net_clear_y_at(cross_x) + margin
	var rise_net: float = net_y - origin.y
	var drop_land: float = target.y - origin.y
	# y(x) = origin.y + a x - b x^2 through the net point and the landing.
	var b: float = (reach * rise_net / to_net - drop_land) / (reach * reach - to_net * reach)
	if b <= 1e-4: return {}
	var speed: float = sqrt(gravity / (2.0 * b))
	var vy: float = (rise_net + b * to_net * to_net) / to_net * speed
	var out: Dictionary = {}
	for step in FIT_PASSES + 1:
		var velocity: Vector3 = dir * speed + Vector3.UP * vy
		var flight: Dictionary = Flight.trace(origin, velocity, omega, 3.0, 1, false, true)
		if flight.net_crossing.is_empty() or float(flight.first_bounce_time) <= 0.0: return out
		var at: Vector3 = flight.net_crossing.pos
		var clear_err: float = (Flight.net_clear_y_at(at.x) + margin) - at.y
		var landed: Vector3 = flight.first_bounce
		var got: float = Vector2(landed.x - origin.x, landed.z - origin.z).length()
		var apex: Vector3 = origin
		for s in flight.samples:
			if Vector3(s.pos).y > apex.y: apex = s.pos
		if not bool(flight.net_hit) and absf(clear_err) < 0.04 and absf(got - reach) < 0.25:
			out = {"velocity": velocity, "apex_past": -apex.z * signf(origin.z)}
			if absf(clear_err) < 0.012 and absf(got - reach) < 0.08: break
		if step == FIT_PASSES: break
		# Height at the net is set by the vertical speed, the landing by the forward speed.
		vy += clear_err / maxf(float(flight.net_crossing.time), 0.05)
		speed *= clampf(reach / maxf(got, 0.05), 0.85, 1.18)
	return out
