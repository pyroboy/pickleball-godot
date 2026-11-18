extends RefCounted
## A timed intersection with a saved contact area; no visual offsets or gravity-only projection.
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const IMPACT_DISTANCE: float = 0.10
const CONTACT_MARGIN: float = 0.03
const LIVE_WINDOW: float = 0.14

static func legal_ball(player, ball, future_bounces: int = 0) -> bool:
	if not ball.is_in_play or ball.last_hit_by == player.player_num: return false
	var total_bounces: int = ball.bounces_since_last_hit + future_bounces
	if total_bounces >= 2: return false
	if not ball.both_bounces_complete and total_bounces == 0: return false
	# A volley is illegal while the player is in the kitchen.
	if total_bounces == 0 and absf(player.global_position.z) < PickleballConstants.NON_VOLLEY_ZONE: return false
	return true

static func point_fits(player, def: PostureDefinition, point: Vector3, margin: float = CONTACT_MARGIN) -> bool:
	var offset: Vector3 = point - player.global_position
	var lateral: float = offset.dot(player._get_forehand_axis())
	var forward: float = offset.dot(player._get_forward_axis())
	var height: float = point.y - player.COURT_FLOOR_Y
	if forward < 0.0 or absf(point.z) < 0.02: return false
	if point.z * player.global_position.z < 0.0: return false
	if lateral < def.zone_x_min - margin or lateral > def.zone_x_max + margin: return false
	if height < def.zone_y_min - margin or height > def.zone_y_max + margin: return false
	if point.y < player.COURT_FLOOR_Y + def.paddle_floor_clearance: return false
	return point.distance_to(Body.shoulder_world(player, def)) <= PaddleReach.MAX_HEAD_DISTANCE

static func pose_at(player, def: PostureDefinition, point: Vector3) -> PostureDefinition:
	var pose: PostureDefinition = def.lerp_with(def, 0.0)
	var offset: Vector3 = point - player.global_position
	pose.paddle_forehand_mul = offset.dot(player._get_forehand_axis())
	pose.paddle_forward_mul = offset.dot(player._get_forward_axis())
	pose.paddle_y_offset = offset.y
	return pose

static func select(player, ball, flight: Dictionary, previous_id: int = -1) -> Dictionary:
	var samples: Array = flight.get("samples", [])
	if samples.is_empty() or not ball.is_in_play or ball.last_hit_by == player.player_num: return {}
	if ball.linear_velocity.dot(-player._get_forward_axis()) < 0.1: return {}
	var choices: Array[Dictionary] = []
	var fwd: Vector3 = player._get_forward_axis()
	for def in PostureLibrary.instance().all_definitions():
		if not def.has_zone: continue
		var candidate: Dictionary = {}
		var forward_now: float = (ball.global_position - player.global_position).dot(fwd)
		if absf(forward_now - def.zone_forward_offset) <= LIVE_WINDOW and legal_ball(player, ball) and point_fits(player, def, ball.global_position):
			candidate = {"point": ball.global_position, "time": 0.0, "bounces": 0}
		else:
			for i in range(samples.size() - 1):
				var a: Dictionary = samples[i]
				var b: Dictionary = samples[i + 1]
				var da: float = (a.pos - player.global_position).dot(fwd) - def.zone_forward_offset
				var db: float = (b.pos - player.global_position).dot(fwd) - def.zone_forward_offset
				if da < 0 or db > 0 or da - db < 0.00001: continue
				# Never interpolate through a bounce discontinuity.
				if a.bounces != b.bounces: continue
				var fraction: float = clampf(da / (da - db), 0.0, 1.0)
				var point: Vector3 = a.pos.lerp(b.pos, fraction)
				if not legal_ball(player, ball, b.bounces) or not point_fits(player, def, point): continue
				candidate = {"point": point, "time": lerpf(a.time, b.time, fraction), "bounces": b.bounces}
				break
		if candidate.is_empty(): continue
		var rest: Vector3 = player.global_position + def.resolve_paddle_offset(player._get_forehand_axis(), fwd)
		candidate["score"] = rest.distance_to(candidate.point) + candidate.time * 0.015
		candidate["posture"] = def.posture_id
		candidate["def"] = pose_at(player, def, candidate.point)
		choices.append(candidate)
	if choices.is_empty(): return {}
	choices.sort_custom(func(a, b): return a.score < b.score)
	var best: Dictionary = choices[0]
	# Keep a valid pose through small prediction noise, but switch when its zone is missed.
	for choice in choices:
		if choice.posture == previous_id and choice.score <= best.score + 0.045: return choice
	return best
