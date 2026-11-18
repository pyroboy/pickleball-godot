extends RefCounted
## Passive, standalone candidate. It never owns input, movement, charge or contact.
## All times are simulation seconds, so focus/slow motion needs no special scaling.
## UNKNOWN is deliberately neutral: a bounded search is not an impossibility proof.
const Planner = preload("res://scripts/incoming_contact_planner.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const NVZ = preload("res://scripts/player_nvz_state.gd")
const Footwork = preload("res://scripts/charged_footwork.gd")
const PlayerScript = preload("res://scripts/player.gd")
const REFRESH_INTERVAL := 0.1
const MAX_HORIZON := 3.0
const MAX_TIME_SAMPLES := 37
const MAX_RAW_SAMPLES := 721
const MAX_GEOMETRY_TESTS := 512
const TIGHT_SLACK := 0.20
const MOVE_REENTRY_SLACK := 0.32
const STANDING_EXIT_HOLD := 0.06
const RETARGET_SLACK_GAIN := 0.35
const MIN_MOVE := 0.08
const POSITION_EPSILON := 0.0002
const TARGET_FOOT_RESERVE := 0.55

# Only value copies are retained. Shared geometry sees a planted, detached player,
# never the actual rig, controller, foot history, or authored-resource mutators.
class ArmSnapshot extends RefCounted:
	var upper_arm_length := 0.35
	var forearm_length := 0.35

class PlayerSnapshot extends RefCounted:
	const COURT_FLOOR_Y = PickleballConstants.FLOOR_Y
	var player_num := 0
	var global_position := Vector3.ZERO
	var global_transform := Transform3D.IDENTITY
	var current_velocity := Vector3.ZERO
	var is_jumping := false
	var ground_y := 1.0
	var forehand := Vector3.RIGHT
	var forward := Vector3.FORWARD
	var volley_legal := false
	var leg_ik = null
	var right_arm_node = ArmSnapshot.new()
	var left_arm_node = ArmSnapshot.new()
	func _get_forward_axis() -> Vector3: return forward
	func _get_forehand_axis() -> Vector3: return forehand
	func can_volley_from_feet() -> bool: return volley_legal
	func place(point: Vector3) -> void:
		global_position = point
		global_transform.origin = point

var _clock := 0.0
var _next_solve := 0.0
var _solved_at := 0.0
var _cache: Dictionary = {}
var _key: Array = []
var _last_ball_position := Vector3.INF
var _last_ball_velocity := Vector3.ZERO
var _last_player_position := Vector3.INF
var _geometry_tests := 0
var _last_status := "UNKNOWN"
var _standing_recent := false
var _outside_since := -1.0
var statistics := {"solves": 0, "reused_flights": 0, "traces": 0,
	"last_solve_usec": 0, "max_solve_usec": 0, "last_geometry_tests": 0,
	"last_time_samples": 0, "cache_hits": 0, "retained_targets": 0,
	"event_revalidations": 0, "standing_suppressions": 0}

func reset() -> void:
	# Retain the rate limit across repeated reset/flight changes.
	_cache = {}
	_key = []
	_last_ball_position = Vector3.INF
	_last_player_position = Vector3.INF
	_last_status = "UNKNOWN"
	_standing_recent = false
	_outside_since = -1.0

func update(delta: float, player, ball, cached_flight: Dictionary = {}, active: bool = true) -> Dictionary:
	_clock += maxf(0.0, delta)
	if not active or not _eligible(player, ball):
		reset()
		return _neutral("inactive")
	var key := [ball.flight_id, ball.last_hit_by, ball.bounces_since_last_hit,
		ball.both_bounces_complete, bool(ball.wall_practice_active) if "wall_practice_active" in ball else false,
		bool(ball.wall_return_ready) if "wall_return_ready" in ball else false]
	var available_flight := _available_flight(player, ball, cached_flight)
	var discontinuity := false
	var position_discontinuity := false
	if _last_ball_position.is_finite():
		var expected: Vector3 = _last_ball_position + _last_ball_velocity * maxf(0.0, delta)
		discontinuity = expected.distance_to(ball.global_position) > maxf(0.35, _last_ball_velocity.length() * maxf(delta, 0.0) * 0.6)
		position_discontinuity = discontinuity
		var velocity_limit := 1.0 + 40.0 * maxf(delta, 0.0)
		discontinuity = discontinuity or _last_ball_velocity.distance_to(ball.linear_velocity) > velocity_limit
	if _last_player_position.is_finite() and _last_player_position.distance_to(player.global_position) > 0.85:
		discontinuity = true
		position_discontinuity = true
	_last_ball_position = ball.global_position
	_last_ball_velocity = ball.linear_velocity
	_last_player_position = player.global_position
	if key != _key or discontinuity:
		var bounce_continuation: bool = not position_discontinuity and _key.size() == key.size() and key[0] == _key[0] and key[1] == _key[1] and int(key[2]) == int(_key[2]) + 1
		var previous := _cache
		_cache = {}
		if bounce_continuation and not available_flight.is_empty() and previous.get("visible", false):
			# An actual bounce invalidates old timing. Recheck the exact old root
			# against the NEW arc now, without starting another full search/trace.
			var count_before := _geometry_tests
			_geometry_tests = 0
			_cache = _retain_target(player, ball, available_flight, previous)
			_geometry_tests = count_before
			if not _cache.is_empty():
				_solved_at = _clock
				var proof_player := snapshot(player)
				_cache.no_time_proven = _no_time_proof(player, proof_player, ball, available_flight.samples, PostureLibrary.instance().all_definitions(), Planner.predicted_fault_time(player, ball, available_flight))
				statistics.event_revalidations += 1
		else:
			_last_status = "UNKNOWN"
			_standing_recent = false
			_outside_since = -1.0
		_key = key
	if _clock + 0.000001 < _next_solve:
		statistics.cache_hits += 1
		return _read_cache(player, ball, available_flight)
	_next_solve = _clock + REFRESH_INTERVAL
	var started := Time.get_ticks_usec()
	var flight := available_flight
	if not flight.is_empty():
		statistics.reused_flights += 1
	else:
		flight = Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity, MAX_HORIZON)
		statistics.traces += 1
	_geometry_tests = 0
	statistics.last_time_samples = 0
	_cache = _solve(player, ball, flight)
	_solved_at = _clock
	statistics.solves += 1
	statistics.last_solve_usec = Time.get_ticks_usec() - started
	statistics.max_solve_usec = maxi(statistics.max_solve_usec, statistics.last_solve_usec)
	statistics.last_geometry_tests = _geometry_tests
	return _read_cache(player, ball, flight)

static func _available_flight(player, ball, supplied: Dictionary) -> Dictionary:
	if _fresh_flight(supplied, ball): return supplied
	if "debug_visual" in player and player.debug_visual != null and _fresh_flight(player.debug_visual._last_flight, ball): return player.debug_visual._last_flight
	return {}

func _eligible(player, ball) -> bool:
	if player == null or ball == null or not ball.is_in_play or ball.last_hit_by == player.player_num or ball.bounces_since_last_hit >= 2: return false
	if not player.global_position.is_finite() or not ball.global_position.is_finite() or not ball.linear_velocity.is_finite(): return false
	if "is_jumping" in player and player.is_jumping: return false
	if "posture" in player and player.posture != null and player.posture.editor_preview_mode: return false
	if player is Node:
		if player.get_tree() != null and player.get_tree().paused: return false
		var game = player.get_parent()
		if game != null and "game_state" in game and game.game_state != game.GameState.PLAYING: return false
		if game != null and "match_over" in game and game.match_over: return false
	if Planner.wall_mode(ball) and not ball.wall_return_ready: return false
	return Planner.should_track(player, ball)

static func _fresh_flight(flight: Dictionary, ball) -> bool:
	var samples: Array = flight.get("samples", [])
	if samples.is_empty(): return false
	var first: Dictionary = samples[0]
	if absf(float(first.get("time", -1.0))) > 0.000001: return false
	if not first.has("pos") or first.pos.distance_to(ball.global_position) > POSITION_EPSILON: return false
	if not first.has("vel") or first.vel.distance_to(ball.linear_velocity) > POSITION_EPSILON: return false
	return first.has("omega") and first.omega.distance_to(ball.angular_velocity) <= POSITION_EPSILON

static func snapshot(player) -> PlayerSnapshot:
	var result := PlayerSnapshot.new()
	result.player_num = player.player_num
	result.global_position = player.global_position
	result.global_transform = player.global_transform
	result.ground_y = player.ground_y
	result.forward = player._get_forward_axis()
	result.forehand = player._get_forehand_axis()
	result.current_velocity = player.current_velocity
	for key in ["right_arm_node", "left_arm_node"]:
		if key in player and player.get(key) != null:
			result.get(key).upper_arm_length = player.get(key).upper_arm_length
			result.get(key).forearm_length = player.get(key).forearm_length
	# can_volley_from_feet() calls NVZ.update and mutates live foot history.
	# Clone the state and execute the existing rule against read-only live geometry.
	if "_nvz_state" in player and player._nvz_state != null:
		var nvz := NVZ.new()
		nvz.established_outside = player._nvz_state.established_outside
		nvz._last_root = player._nvz_state._last_root
		result.volley_legal = nvz.can_volley(player)
	return result

static func effective_speed(player) -> float:
	var factor := 1.0
	if "stamina" in player and player.stamina != null: factor = player.stamina.speed_factor()
	return maxf(0.0, player.move_speed * factor)

static func travel_budget(player, target: Vector3, strike_time: float = 0.0) -> Dictionary:
	var offset: Vector3 = target - player.global_position
	offset.y = 0.0
	var distance := offset.length()
	var speed := effective_speed(player)
	var current := Vector3(player.current_velocity.x, 0.0, player.current_velocity.z)
	var brake: float = PlayerScript.MANUAL_BRAKE
	var accel: float = PlayerScript.MANUAL_ACCEL
	# Constructive conservative route: brake current momentum, travel from the
	# resulting stopped position, then brake and plant before the actual strike.
	# Unlike an optimistic distance/speed estimate, reversals/lateral inertia count.
	var stop_time := current.length() / brake
	var stopped: Vector3 = player.global_position + current * stop_time * 0.5
	var travel: Vector3 = target - stopped
	travel.y = 0.0
	var travel_distance := travel.length()
	var motion := INF
	if speed > 0.00001:
		var ramp := speed * speed * (0.5 / accel + 0.5 / brake)
		motion = sqrt(2.0 * travel_distance * (1.0 / accel + 1.0 / brake)) if travel_distance <= ramp else speed / accel + speed / brake + (travel_distance - ramp) / speed
	elif travel_distance <= 0.001: motion = 0.0
	# A tick reserve covers discrete acceleration/plant scheduling at all rates.
	var tick_reserve := 2.0 / maxf(1.0, Engine.physics_ticks_per_second)
	var required := stop_time + motion + Footwork.PLANT_TIME + Footwork.LOAD_TIME + maxf(0.0, strike_time) + tick_reserve
	return {"required_time": required, "required_travel": distance, "route_travel": travel_distance,
		"speed": speed, "inertia_time": stop_time, "plant_time": Footwork.PLANT_TIME + Footwork.LOAD_TIME,
		"tick_reserve": tick_reserve}

func _read_cache(player, ball, flight: Dictionary = {}) -> Dictionary:
	if _cache.is_empty(): return _neutral("waiting_for_refresh")
	var result := _cache.duplicate(true)
	if not result.get("visible", false) and not _standing_recent: return result
	var read_only := snapshot(player)
	if _current_contact_verified(player, read_only, ball, flight):
		_standing_recent = true
		_outside_since = -1.0
		statistics.standing_suppressions += 1
		return _neutral("already_in_reach")
	if _standing_recent:
		if _outside_since < 0.0: _outside_since = _clock
		if _clock - _outside_since < STANDING_EXIT_HOLD: return _neutral("reach_transition") if result.get("visible", false) else result
		_standing_recent = false
	if not result.get("visible", false): return result
	var remaining := float(result.time) - (_clock - _solved_at)
	if remaining <= 0.0: return _neutral("expired")
	if not _within_bounds(player, result.target_root): return _neutral("bounds_changed")
	# An immediately changed kitchen history must hide an old volley marker,
	# even while the expensive search is throttled.
	if int(result.total_bounces) == 0 and not Planner.wall_mode(ball):
		if not read_only.volley_legal: return _neutral("volley_history_changed")
	var budget := travel_budget(player, result.target_root, result.strike_time)
	if budget.required_travel < MIN_MOVE: return _neutral("at_target")
	result.merge(budget, true)
	result.remaining_time = remaining
	result.slack = remaining - budget.required_time
	result.direction = (Vector3(result.target_root.x, player.global_position.y, result.target_root.z) - player.global_position).normalized()
	result.age = _clock - _solved_at
	# The whole-flight proof belongs to the solved root. Moving may invalidate it.
	var proof_valid: bool = result.get("no_time_proven", false) and player.global_position.distance_to(result.solved_root) < 0.0001 and maxf(player.move_speed, player.current_velocity.length()) <= result.proof_speed + 0.0001
	result.no_time_proven = proof_valid
	result.proof_scope = "predicted_legal_flight" if proof_valid else "candidate_only"
	var move_threshold: float = MOVE_REENTRY_SLACK if _last_status == "TIGHT" else TIGHT_SLACK
	result.status = "NO_TIME" if proof_valid else ("MOVE" if result.slack >= move_threshold else "TIGHT")
	_last_status = result.status
	return result

func _solve(player, ball, flight: Dictionary) -> Dictionary:
	var samples: Array = flight.get("samples", [])
	if samples.size() < 2: return _neutral("no_trajectory")
	if samples.size() > MAX_RAW_SAMPLES: return _neutral("trajectory_over_budget")
	var pose_player := snapshot(player)
	var definitions: Array = PostureLibrary.instance().all_definitions()
	Planner.ActivationZones.refresh(Planner.CONTACT_MARGIN)
	var fault: float = Planner.predicted_fault_time(player, ball, flight)
	if flight.get("net_hit", false): fault = minf(fault, float(flight.get("net_crossing", {}).get("time", INF)))
	if fault <= 0.0: return _neutral("predicted_fault")
	if _current_contact_verified(player, pose_player, ball, flight):
		_standing_recent = true
		_outside_since = -1.0
		return _neutral("already_in_reach")
	if _standing_reachable(pose_player, ball, samples, definitions, fault):
		_standing_recent = true
		_outside_since = -1.0
		return _neutral("already_in_reach")
	var retained := _retain_target(player, ball, flight, _cache, pose_player, fault)
	pose_player.place(player.global_position)
	if not retained.is_empty() and retained.slack >= 0.0:
		statistics.retained_targets += 1
		return retained
	var times := _time_samples(samples, fault)
	statistics.last_time_samples = times.size()
	var best: Dictionary = {}
	var score := INF
	for sample in times:
		var time: float = sample.time
		var point: Vector3 = sample.pos
		var total_bounces: int = ball.bounces_since_last_hit + int(sample.bounces)
		if time < 0.06 or time > MAX_HORIZON or time >= fault or total_bounces >= 2: continue
		if not ball.both_bounces_complete and total_bounces == 0 and not Planner.wall_mode(ball): continue
		if point.z * player.global_position.z <= 0.0: continue
		for base: PostureDefinition in definitions:
			if not base.has_zone or base.posture_id in [8, 9]: continue
			var height := point.y - pose_player.COURT_FLOOR_Y
			if height < Planner.ActivationZones.minimum_height(base) or height > base.zone_y_max + Planner.CONTACT_MARGIN: continue
			var current_lateral: float = (point - player.global_position).dot(pose_player.forehand)
			# Try the nearest authored lateral first, then the canonical paddle lane.
			var lanes: Array[float] = [clampf(current_lateral, base.zone_x_min, base.zone_x_max), base.paddle_forehand_mul]
			for lateral in lanes:
				var target: Vector3 = point - pose_player.forehand * lateral - pose_player.forward * base.zone_forward_offset
				target.y = player.ground_y
				if not _within_bounds(player, target) or target.z * player.global_position.z <= 0.0: continue
				var distance: float = Vector2(target.x - player.global_position.x, target.z - player.global_position.z).length()
				if distance < MIN_MOVE: continue
				if total_bounces == 0 and not Planner.wall_mode(ball) and not _safe_volley_target(pose_player, base, target): continue
				var budget := travel_budget(player, target, base.ft_duration_strike)
				var slack: float = time - budget.required_time
				# Prefer a comfortably executable target; otherwise show the best
				# verified difficult target, without claiming all others impossible.
				var candidate_score: float = (0.0 if slack >= TIGHT_SLACK else 5.0 + maxf(0.0, -slack) * 4.0) + distance * 0.7 + time * 0.35
				if candidate_score >= score: continue
				pose_player.place(target)
				if not Planner.legal_ball(pose_player, ball, int(sample.bounces)): continue
				if not _point_fits(pose_player, base, point): continue
				score = candidate_score
				best = {"visible": true, "status": "MOVE", "reason": "legal_target", "flight_id": ball.flight_id,
					"target_root": target, "point": point, "time": time, "remaining_time": time,
					"total_bounces": total_bounces, "future_bounces": int(sample.bounces), "posture": base.posture_id,
					"strike_time": base.ft_duration_strike, "slack": slack, "solved_root": player.global_position,
					"search_exhaustive": false, "proof_speed": maxf(player.move_speed, player.current_velocity.length())}
				best.merge(budget)
				if _geometry_tests >= MAX_GEOMETRY_TESTS: break
			if _geometry_tests >= MAX_GEOMETRY_TESTS: break
		if _geometry_tests >= MAX_GEOMETRY_TESTS: break
	if not retained.is_empty():
		# Keep a verified exact root while it remains feasible, rather than
		# chasing slightly different sampled minima every tenth of a second.
		# A materially easier executable alternative may replace a difficult one.
		if best.is_empty() or retained.slack >= 0.0 or float(best.slack) < float(retained.slack) + RETARGET_SLACK_GAIN:
			best = retained
			statistics.retained_targets += 1
	if best.is_empty(): return _neutral("bounded_search_no_candidate")
	pose_player.place(player.global_position)
	best.no_time_proven = _no_time_proof(player, pose_player, ball, samples, definitions, fault)
	best.proof_scope = "predicted_legal_flight" if best.no_time_proven else "candidate_only"
	return best

static func _current_contact_verified(owner, detached: PlayerSnapshot, ball, flight: Dictionary) -> bool:
	if flight.is_empty() or not "posture" in owner or owner.posture == null or owner.posture.human_contact == null: return false
	var human = owner.posture.human_contact
	var contact: Dictionary = human.contact
	if human._flight_id != ball.flight_id or contact.is_empty() or not contact.has("def") or not contact.has("point"): return false
	var samples: Array = flight.get("samples", [])
	if samples.size() < 2 or samples.size() > MAX_RAW_SAMPLES: return false
	var time: float = contact.get("time", -1.0)
	if time < 0.0 or time > float(samples.back().time): return false
	# A logarithmic time lookup ties controller evidence to this exact current
	# trajectory. Same flight ID alone is not proof that an old point is live.
	var low := 0
	var high := samples.size() - 1
	while low + 1 < high:
		var middle: int = (low + high) / 2
		if float(samples[middle].time) <= time: low = middle
		else: high = middle
	var a: Dictionary = samples[low]
	var b: Dictionary = samples[high]
	var fraction := clampf((time - float(a.time)) / maxf(0.000001, float(b.time) - float(a.time)), 0.0, 1.0)
	if int(b.bounces) < int(a.bounces) or int(b.bounces) > int(a.bounces) + 1: return false
	if a.bounces != b.bounces and fraction >= 1.0: return false
	var point: Vector3 = a.pos.lerp(b.pos, fraction)
	if point.distance_to(contact.point) > 0.025: return false
	if time >= Planner.predicted_fault_time(owner, ball, flight): return false
	if not Planner.legal_ball(detached, ball, int(a.bounces)): return false
	return Planner.point_fits(detached, contact.def, point)

func _retain_target(owner, ball, flight: Dictionary, previous: Dictionary, detached = null, known_fault: float = -1.0) -> Dictionary:
	if not previous.get("visible", false) or int(previous.get("flight_id", -1)) != ball.flight_id: return {}
	var target: Vector3 = previous.target_root
	if not _within_bounds(owner, target) or target.z * owner.global_position.z <= 0.0: return {}
	if Vector2(target.x - owner.global_position.x, target.z - owner.global_position.z).length() < MIN_MOVE: return {}
	var base: PostureDefinition = PostureLibrary.instance().get_def(int(previous.posture))
	if base == null or not base.has_zone: return {}
	var samples: Array = flight.get("samples", [])
	if samples.size() < 2 or samples.size() > MAX_RAW_SAMPLES: return {}
	var fault: float = known_fault if known_fault >= 0.0 else Planner.predicted_fault_time(owner, ball, flight)
	if flight.get("net_hit", false): fault = minf(fault, float(flight.get("net_crossing", {}).get("time", INF)))
	if detached == null: detached = snapshot(owner)
	detached.place(target)
	for index in range(samples.size() - 1):
		var a: Dictionary = samples[index]
		var b: Dictionary = samples[index + 1]
		var da: float = (a.pos - target).dot(detached.forward) - base.zone_forward_offset
		var db: float = (b.pos - target).dot(detached.forward) - base.zone_forward_offset
		if da < 0.0 or db > 0.0 or da - db < 0.00001: continue
		var fraction := clampf(da / (da - db), 0.0, 1.0)
		# An endpoint is post-bounce; never treat an interpolated pre-bounce
		# portion as fulfilling the required ground contact.
		if int(b.bounces) < int(a.bounces) or int(b.bounces) > int(a.bounces) + 1: continue
		if a.bounces != b.bounces and fraction >= 1.0: continue
		var time := lerpf(a.time, b.time, fraction)
		# Do not hold a nearly expired target across another cache interval.
		if time < REFRESH_INTERVAL + 2.0 / Engine.physics_ticks_per_second or time >= fault or time > MAX_HORIZON: continue
		var total: int = ball.bounces_since_last_hit + int(a.bounces)
		if total == 0 and not Planner.wall_mode(ball) and not _safe_volley_target(detached, base, target): continue
		if not Planner.legal_ball(detached, ball, int(a.bounces)): continue
		var point: Vector3 = a.pos.lerp(b.pos, fraction)
		if not _point_fits(detached, base, point): continue
		var result := previous.duplicate(true)
		var budget := travel_budget(owner, target, base.ft_duration_strike)
		result.merge(budget, true)
		result.point = point
		result.time = time
		result.remaining_time = time
		result.slack = time - budget.required_time
		result.strike_time = base.ft_duration_strike
		result.future_bounces = int(a.bounces)
		result.total_bounces = total
		result.solved_root = owner.global_position
		result.proof_speed = maxf(owner.move_speed, owner.current_velocity.length())
		result.no_time_proven = false
		result.proof_scope = "candidate_only"
		result.persisted = true
		return result
	return {}

static func _safe_volley_target(detached: PlayerSnapshot, base: PostureDefinition, target: Vector3) -> bool:
	var authored_front: float = maxf(absf(base.front_foot_forward + base.right_foot_offset.z), absf(base.front_foot_forward + base.left_foot_offset.z))
	var authored_back: float = maxf(absf(base.back_foot_back + base.right_foot_offset.z), absf(base.back_foot_back + base.left_foot_offset.z))
	var foot_reserve: float = maxf(TARGET_FOOT_RESERVE, maxf(authored_front, authored_back) + 0.30)
	return detached.volley_legal and absf(target.z) > PickleballConstants.NON_VOLLEY_ZONE + foot_reserve

func _standing_reachable(player: PlayerSnapshot, ball, samples: Array, definitions: Array, fault: float) -> bool:
	for base: PostureDefinition in definitions:
		if not base.has_zone or base.posture_id in [8, 9]: continue
		var live_forward: float = (ball.global_position - player.global_position).dot(player.forward)
		if absf(live_forward - base.zone_forward_offset) <= Planner.LIVE_WINDOW and Planner.legal_ball(player, ball):
			if _point_fits(player, base, ball.global_position): return true
		for index in range(samples.size() - 1):
			var a: Dictionary = samples[index]
			var b: Dictionary = samples[index + 1]
			var da: float = (a.pos - player.global_position).dot(player.forward) - base.zone_forward_offset
			var db: float = (b.pos - player.global_position).dot(player.forward) - base.zone_forward_offset
			if da < 0.0 or db > 0.0 or da - db < 0.00001: continue
			var fraction := clampf(da / (da - db), 0.0, 1.0)
			if a.bounces != b.bounces and fraction >= 1.0: continue
			if int(b.bounces) < int(a.bounces) or int(b.bounces) > int(a.bounces) + 1: continue
			if lerpf(a.time, b.time, fraction) >= fault: continue
			if not Planner.legal_ball(player, ball, int(a.bounces)): continue
			if _point_fits(player, base, a.pos.lerp(b.pos, fraction)): return true
	return false

func _point_fits(player: PlayerSnapshot, base: PostureDefinition, point: Vector3) -> bool:
	if _geometry_tests >= MAX_GEOMETRY_TESTS: return false
	_geometry_tests += 1
	return Planner.point_fits(player, base, point)

static func _within_bounds(player, target: Vector3) -> bool:
	if not target.is_finite(): return false
	if not player.bounds_ready: return false # No verified playable rectangle.
	return target.x >= player.min_x and target.x <= player.max_x and target.z >= player.min_z and target.z <= player.max_z

static func _time_samples(samples: Array, fault: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var end: float = minf(MAX_HORIZON, minf(float(samples.back().time), fault))
	if end <= 0.0: return result
	var index := 0
	for slot in range(MAX_TIME_SAMPLES):
		var time := end * float(slot) / float(MAX_TIME_SAMPLES - 1)
		while index + 1 < samples.size() - 1 and float(samples[index + 1].time) < time: index += 1
		var a: Dictionary = samples[index]
		var b: Dictionary = samples[index + 1]
		# Never interpolate through a bounce; that segment has two different
		# physical arcs. Each side remains eligible via its real sample endpoint.
		if a.bounces != b.bounces:
			result.append(a if time < float(b.time) else b)
			continue
		var span: float = float(b.time) - float(a.time)
		var fraction := clampf((time - float(a.time)) / maxf(span, 0.000001), 0.0, 1.0)
		result.append({"pos": a.pos.lerp(b.pos, fraction), "time": time, "bounces": int(a.bounces)})
	return result

static func _no_time_proof(player, detached: PlayerSnapshot, ball, samples: Array, definitions: Array, fault: float) -> bool:
	# A finite fault ends the predicted legal window. A horizon truncation alone
	# cannot prove the remainder of the shot unreachable.
	if not is_finite(fault) or fault > MAX_HORIZON: return false
	var reach := 0.0
	for base: PostureDefinition in definitions:
		if not base.has_zone: continue
		var shoulder: Vector3 = Planner.Body.shoulder_world(detached, base) - detached.global_position
		# Reserve covers the planner's bounded lean variants, beyond the actual
		# shoulder/head limit. A looser upper bound can only reject a proof.
		reach = maxf(reach, Vector2(shoulder.x, shoulder.z).length() + PaddleReach.MAX_HEAD_DISTANCE + 0.50)
	var speed: float = maxf(player.move_speed, Vector2(player.current_velocity.x, player.current_velocity.z).length())
	var root := Vector2(player.global_position.x, player.global_position.z)
	var eligible_segment := false
	for index in range(samples.size() - 1):
		var a: Dictionary = samples[index]
		var b: Dictionary = samples[index + 1]
		if float(a.time) >= fault: break
		if int(a.bounces) + ball.bounces_since_last_hit >= 2: continue
		if not ball.both_bounces_complete and int(a.bounces) + ball.bounces_since_last_hit == 0 and not Planner.wall_mode(ball): continue
		if a.pos.z * player.global_position.z < 0.0 and b.pos.z * player.global_position.z < 0.0: continue
		eligible_segment = true
		var first := Vector2(a.pos.x, a.pos.z)
		var second := Vector2(b.pos.x, b.pos.z)
		var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(root, first, second)
		var minimum_travel := maxf(0.0, root.distance_to(nearest) - reach)
		# Compare an optimistic distance bound to the latest time of the entire
		# segment, ignoring acceleration, reaction, plant and stroke costs.
		if minimum_travel <= speed * float(b.time) + 0.02: return false
	return eligible_segment

static func _neutral(reason: String) -> Dictionary:
	return {"visible": false, "status": "UNKNOWN", "reason": reason,
		"remaining_time": 0.0, "required_travel": 0.0, "slack": 0.0,
		"search_exhaustive": false, "no_time_proven": false}
