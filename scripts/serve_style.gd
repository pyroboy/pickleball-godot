class_name ServeStyle extends RefCounted



const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Delivery = preload("res://scripts/serve_delivery_profile.gd")
enum Style{FLAT, TOPSPIN, SLICE, HIGH_SOFT, DROP_DRIVE, BANANA, SCREWBALL}

static func valid_style(id: int) -> int:
	return clampi(id, Style.FLAT, Style.SCREWBALL)

static func options() -> Array[Dictionary]:
	return [
		{"id": 0, "key": "FLAT", "label": "Flat", "delivery": "Volley", "description": "Balanced underhand serve with little spin"}, 
		{"id": 1, "key": "TOPSPIN", "label": "Topspin", "delivery": "Volley", "description": "Lower preparation and upward brush; dips into the service box"}, 
		{"id": 2, "key": "SLICE", "label": "Slice", "delivery": "Drop", "description": "Gravity drop, bounce, then a smooth backspin cut"}, 
		{"id": 3, "key": "HIGH_SOFT", "label": "High Soft", "delivery": "Volley", "description": "Slower upward loft, landing deep beyond the kitchen"}, 
		{"id": 4, "key": "DROP_DRIVE", "label": "Drop Drive", "delivery": "Drop", "description": "Gravity drop and bounce, then a compact topspin drive"}, 
		{"id": 5, "key": "BANANA", "label": "Banana", "delivery": "Experimental drop", "description": "Experimental lateral brush: bends left from the server's view; not a copied pro stroke"}, 
		{"id": 6, "key": "SCREWBALL", "label": "Screwball", "delivery": "Experimental drop", "description": "Experimental opposite lateral brush: bends right from the server's view; not a copied pro stroke"}, 
	]

static func is_drop(style: int) -> bool:
	return style in [Style.SLICE, Style.DROP_DRIVE, Style.BANANA, Style.SCREWBALL]

static func spin_mode(style: int) -> int:
	if style in [Style.TOPSPIN, Style.DROP_DRIVE, Style.BANANA, Style.SCREWBALL]: return 1
	if style == Style.SLICE: return 2
	return 0

static func hold_offset(style: int) -> Vector3:

	return Delivery.hold_offset(is_drop(style))

static func stroke_duration(style: int) -> float:
	return 0.23 if style == Style.HIGH_SOFT else (0.15 if is_drop(style) else 0.12)

static func sweep_duration(style: int) -> float:
	return 0.44 if style == Style.HIGH_SOFT else (0.26 if style == Style.SLICE else 0.3)

static func release_plan(player_origin: Vector3, red: bool, style: int, release: Vector3 = Vector3.INF) -> Dictionary:
	var sign: float = -1.0 if red else 1.0
	if not release.is_finite():
		var offset: Vector3 = hold_offset(style)
		release = player_origin + Vector3(offset.x * sign, offset.y, - offset.z * sign)
	var result: Dictionary = {"release_position": release, "contact_position": player_origin + Motion.serve_launch_offset(red), 
		"contact_time": 0.0, "bounce_time": -1.0, "delivery": "Drop" if is_drop(style) else "Volley", "samples": []}
	var path: Dictionary = Flight.trace(release, Vector3.ZERO, Vector3.ZERO, 2.0, 2, false)
	var samples: Array = path.samples
	var target_y: float = player_origin.y + Motion.SERVE_CONTACT.y
	if is_drop(style):
		result.bounce_time = path.first_bounce_time
		var apex: float = Flight.FLOOR_REST_Y
		for sample in samples:
			if int(sample.bounces) == 1: apex = maxf(apex, sample.pos.y)
		target_y = minf(target_y, apex - 0.025)
	for sample in samples:
		result.samples.append(sample)
		var reaches: bool = int(sample.bounces) == 1 and sample.vel.y > 0.0 and sample.pos.y >= target_y if is_drop(style) else int(sample.bounces) == 0 and sample.vel.y < 0.0 and sample.pos.y <= target_y
		if reaches:
			result.contact_position = sample.pos
			result.contact_time = sample.time
			break
	return result

static func solve_launch(physics, origin: Vector3, requested_target: Vector3, charge: float, player_num: int, style: int, arc: float = 0.0, realized_target: bool = false) -> Dictionary:
	style = valid_style(style)
	var target: Vector3 = requested_target
	var power: float = clampf(charge, 0.0, 1.0)
	var loft: float = arc
	if style == Style.HIGH_SOFT:
		power = lerpf(0.02, 0.2, power)
		loft = clampf(arc + 0.22, -0.1, 0.45)
	var solved: Dictionary = physics.solve_aimed_launch(origin, target, power, player_num, spin_mode(style), "AUTO", "SERVE", loft, realized_target)
	if solved.is_empty(): return solved
	if style in [Style.BANANA, Style.SCREWBALL]:
		solved = _solve_lateral(origin, solved, style, charge)
	var profile: Dictionary = solved.profile.duplicate(true)
	profile["charge"] = clampf(charge, 0.0, 1.0)
	profile["effective_power"] = power
	if style in [Style.BANANA, Style.SCREWBALL]:
		profile["topspin_rads"] = lerpf(9.0, 14.0, clampf(charge, 0, 1))
		profile["sidespin_rads"] = (1.0 if style == Style.BANANA else -1.0) * lerpf(14.0, 22.0, clampf(charge, 0, 1))
	profile["serve_style"] = style
	profile["serve_label"] = options()[style].label
	profile["delivery"] = "Drop" if is_drop(style) else "Volley"
	profile["experimental"] = style >= Style.BANANA
	profile.make_read_only()
	solved.profile = profile
	solved["style"] = style
	return solved

static func _solve_lateral(origin: Vector3, baseline: Dictionary, style: int, charge: float) -> Dictionary:
	var target: Vector3 = baseline.target
	var launch: Vector3 = baseline.velocity
	var side: float = 1.0 if style == Style.BANANA else -1.0
	var lateral: float = side * lerpf(14.0, 22.0, clampf(charge, 0.0, 1.0))
	var best: Dictionary = baseline.duplicate(true)
	var best_score: float = INF
	for iteration in range(36):
		var forward: = Vector3(launch.x, 0, launch.z).normalized()
		var omega: Vector3 = Vector3.UP.cross(forward) * lerpf(9.0, 14.0, charge) + Vector3.UP * lateral
		var flight: Dictionary = Flight.trace(origin, launch, omega, 3.0, 1, false, false)
		var net: Dictionary = flight.net_crossing
		var clear: bool = not net.is_empty() and net.pos.y > Flight.net_clear_y_at(net.pos.x) + 0.06
		var landing: Vector3 = flight.first_bounce
		var error: Vector3 = target - landing
		var score: float = Vector2(error.x, error.z).length() + (4.0 if not clear else 0.0)
		if float(flight.first_bounce_time) < 0: score = INF
		if score < best_score:
			best_score = score
			best = baseline.duplicate(true)
			best.velocity = launch
			best.omega = omega
			best.landing = landing
			best.target_error = Vector2(error.x, error.z).length()
			best.net_clear = clear
			best.feasible = clear and best.target_error < 0.12
		if clear and score < 0.05: break
		var duration: float = maxf(float(flight.first_bounce_time), 0.3)
		launch.x += error.x / duration * 0.85
		launch.z += error.z / duration * 0.85
		if not clear and not net.is_empty():
			launch.y += (Flight.net_clear_y_at(net.pos.x) + 0.16 - net.pos.y) / maxf(float(net.time), 0.1)
		launch = launch.limit_length(Ball.MAX_SPEED)
	return best
