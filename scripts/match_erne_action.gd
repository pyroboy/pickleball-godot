extends RefCounted
## Optional lateral jump around the kitchen, using ordinary authored paddle
## contact and the existing physical jump/airborne-foot solver. A plan is an
## opportunity, never permission to award a return.
const Identity = preload("res://scripts/special_action_identity.gd")
const Planner = preload("res://scripts/incoming_contact_planner.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const PREPARE_TIME := 0.12
const JUMP_HEIGHT := 0.24
const LANDING_MARGIN := 0.42
const RECOVERY_TIME := 0.35
const COOLDOWN := 2.0
const MAX_APPROACH := 1.55
const MAX_SAMPLE_PROBES := 10
const AI_RETRY_INTERVAL := 0.25
var last_selection: Dictionary = {}
var _issued_candidate := PackedByteArray()
var _issued_ball: Dictionary = {}
var _last_ai_flight := -1
var _next_ai_check_msec := 0
var player
var plan: Dictionary = {}
var active := false
var phase := "idle"
var elapsed := 0.0
var cooldown := 0.0
var hit := false
var cancelled := false
var _landed_time := -1.0
var _taken_off := false
var _step_velocity := Vector3.ZERO

func _init(owner) -> void:
	player = owner

func eligible(ball) -> bool:
	if not Identity.incoming(player, ball): return false
	if ball.bounces_since_last_hit != 0 or not ball.both_bounces_complete: return false
	if active or cooldown > 0.0 or player.is_jumping or player.jump_landing_remaining > 0.0: return false
	if absf(player.global_position.y - player.ground_y) > 0.005: return false
	if not player.can_volley_from_feet(): return false
	if absf(player.global_position.x) < PickleballConstants.COURT_WIDTH * 0.5 - 0.85: return false
	if absf(player.global_position.z) > PickleballConstants.NON_VOLLEY_ZONE + 1.4: return false
	return true

func choose_plan(ball, prediction: Dictionary = {}) -> Dictionary:
	_issued_candidate = PackedByteArray(); _issued_ball = {}
	if not eligible(ball): return {}
	var origin: Vector3 = player.global_position
	var gravity: float = player.JUMP_GRAVITY
	var launch: float = sqrt(2.0 * gravity * JUMP_HEIGHT)
	var flight_time: float = 2.0 * launch / gravity
	var forecast: Dictionary = prediction if not prediction.is_empty() else Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity, PREPARE_TIME + flight_time, 1, true)
	var side: float = signf(origin.x)
	var own: float = 1.0 if player.get_court_side() == 0 else -1.0
	var out_x: float = side * (PickleballConstants.COURT_WIDTH * 0.5 + LANDING_MARGIN)
	var maximum_speed: float = player.move_speed * player.stamina.speed_factor() * 0.9
	var saved: Vector3 = player.global_position
	var best: Dictionary = {}
	var probes := 0
	var last_probe := -INF
	for sample in forecast.get("samples", []):
		var time: float = float(sample.time)
		var in_air: float = time - PREPARE_TIME
		if in_air < flight_time * 0.35 or in_air > flight_time * 0.82 or int(sample.bounces) != 0: continue
		var point: Vector3 = sample.pos
		if point.z * own < ball.BALL_RADIUS or point.y < 0.7 or point.y > 2.05: continue
		if time - last_probe < flight_time * (0.82 - 0.35) / float(MAX_SAMPLE_PROBES - 1): continue
		last_probe = time
		probes += 1
		if probes > MAX_SAMPLE_PROBES: break
		# Land wholly outside the kitchen sideline, never on its boundary.
		# Forward extension remains on the player's side of the net.
		var landing: Vector3 = Vector3(out_x, player.ground_y, own * clampf(absf(point.z) + 0.48, 0.95, absf(origin.z)))
		var travel: Vector3 = landing - origin
		travel.y = 0.0
		if travel.length() > MAX_APPROACH: continue
		var velocity: Vector3 = travel / flight_time
		if velocity.length() > maximum_speed: continue
		var root: Vector3 = origin + velocity * in_air + Vector3.UP * (launch * in_air - 0.5 * gravity * in_air * in_air)
		if root.x < player.min_x or root.x > player.max_x or root.z < player.min_z or root.z > player.max_z: continue
		player.global_position = root
		for id in [0, 1, 2, 3, 10, 11, 12, 13, 14, 15, 16, 17]:
			var base: PostureDefinition = PostureLibrary.instance().get_def(id)
			if base == null or not Planner.point_fits(player, base, point, 0.0): continue
			var pose: PostureDefinition = Planner.pose_at(player, base, point)
			best = {"actor_id": player.get_actor_id(), "team_id": player.get_team_id(), "court_side": player.get_court_side(), "player_num": player.get_team_id(), "kind": "ERNE", "flight_id": ball.flight_id, "time": time, "point": point,
				"def": pose, "posture": id, "bounces": 0, "origin": origin, "landing": landing,
				"velocity": velocity, "launch_speed": launch, "flight_time": flight_time,
				"scope": "predicted_opportunity_requires_real_contact"}
			break
		player.global_position = saved
		if not best.is_empty(): break
	player.global_position = saved
	if not best.is_empty():
		_issued_candidate = var_to_bytes(best)
		_issued_ball = {"position": ball.global_position, "velocity": ball.linear_velocity, "omega": ball.angular_velocity, "flight_id": ball.flight_id, "last_hit_identity": Identity.ball_identity(ball)}
	last_selection = {"candidate_probes": mini(probes, MAX_SAMPLE_PROBES), "found": not best.is_empty()}
	return best

func begin(candidate: Dictionary, ball) -> bool:
	if not eligible(ball) or not Identity.matches(player, candidate) or int(candidate.get("flight_id", -1)) != ball.flight_id: return false
	if _issued_candidate.is_empty() or var_to_bytes(candidate) != _issued_candidate: return false
	if _issued_ball != {"position": ball.global_position, "velocity": ball.linear_velocity, "omega": ball.angular_velocity, "flight_id": ball.flight_id, "last_hit_identity": Identity.ball_identity(ball)}: return false
	if candidate.get("origin", Vector3.INF).distance_to(player.global_position) > 0.03: return false
	plan = candidate.duplicate(true)
	active = true; elapsed = 0.0; cooldown = COOLDOWN; hit = false; cancelled = false
	_taken_off = false; _landed_time = -1.0; phase = "load"
	return true

func maybe_start_ai(ball, prediction: Dictionary = {}, context: Dictionary = {}) -> bool:
	## A tactical opportunity check, never hit permission. Ordinary AI contact
	## still owns the real paddle/rig/ball test and aimed response.
	if not player.is_ai or not player.ai_movement_enabled or not eligible(ball): return false
	if player.ai_brain == null or not player.ai_brain._perception_ready or player.ai_brain._observed_flight_id != ball.flight_id or prediction.get("samples", []).is_empty(): return false
	if (context.has("actor_id") or context.has("team_id") or context.has("court_side") or context.has("player_num")) and not Identity.matches(player, context): return false
	if player.hitting.serving_visual_active or player.hitting.is_in_follow_through or player.hitting.stroke_contact_active: return false
	if player.special_reach_driver != null and player.special_reach_driver.active: return false
	if bool(context.get("normal_reachable", true)): return false
	if int(context.get("flight_id", ball.flight_id)) != ball.flight_id: return false
	var now: int = Time.get_ticks_msec()
	if _last_ai_flight == ball.flight_id and now < _next_ai_check_msec: return false
	_last_ai_flight = ball.flight_id; _next_ai_check_msec = now + int(AI_RETRY_INTERVAL * 1000.0)
	var opportunity: Dictionary = choose_plan(ball, prediction)
	if opportunity.is_empty(): return false
	var point: Vector3 = opportunity.point
	var own: float = 1.0 if player.get_court_side() == 0 else -1.0
	# Prefer the jump only for a genuinely near-kitchen sideline volley that
	# the current ordinary contact plan cannot reach. Baseline side steps do
	# not become an automatic advanced action just because they are possible.
	if absf(point.x) < PickleballConstants.COURT_WIDTH * .5 - .12 or point.z * own > PickleballConstants.NON_VOLLEY_ZONE: return false
	return begin(opportunity, ball)

func before_physics(delta: float, ball) -> void:
	cooldown = maxf(0.0, cooldown - maxf(0.0, delta))
	if not active: return
	if not Identity.matches(player, plan): cancelled = true
	var previous_elapsed: float = elapsed
	elapsed += maxf(0.0, delta)
	_step_velocity = Vector3.ZERO
	if not _taken_off:
		if cancelled or ball == null or not ball.is_in_play or ball.flight_id != int(plan.flight_id) or not player.can_volley_from_feet():
			_finish(); return
		if elapsed >= PREPARE_TIME:
			player.vertical_velocity = float(plan.launch_speed)
			player.is_jumping = true
			player.jump_takeoff_position = player.global_position
			_taken_off = true; phase = "airborne_attack"
	elif not player.is_jumping and player.global_position.y <= player.ground_y + 0.001:
		if _landed_time < 0.0: _landed_time = elapsed; phase = "landing"
		if elapsed - _landed_time >= RECOVERY_TIME and not player.is_jumping:
			_finish()
	if _taken_off and _landed_time < 0.0 and delta > 0.0:
		# Integrate the already-admitted ballistic jump through normal Player
		# movement. Fractional takeoff/landing and the exact height difference
		# remove rate-dependent semi-implicit drift without translating roots.
		var duration: float = float(plan.flight_time)
		var start: float = clampf(previous_elapsed - PREPARE_TIME, 0.0, duration)
		var finish: float = clampf(elapsed - PREPARE_TIME, 0.0, duration)
		_step_velocity = Vector3(plan.velocity) * (finish - start) / delta
		var height: float = float(plan.launch_speed) * finish - .5 * player.JUMP_GRAVITY * finish * finish
		var desired_y: float = player.ground_y + maxf(0.0, height)
		# Player._update_jump_state subtracts gravity before applying velocity.
		player.vertical_velocity = (desired_y - player.global_position.y) / delta + player.JUMP_GRAVITY * delta

func ground_velocity() -> Vector3:
	if not active or not _taken_off or _landed_time >= 0.0: return Vector3.ZERO
	return _step_velocity

func contact_opportunity(ball) -> Dictionary:
	if not active or cancelled or hit or not Identity.matches(player, plan) or not Identity.incoming(player, ball) or ball.flight_id != int(plan.flight_id): return {}
	var result: Dictionary = plan.duplicate(true)
	result.time = maxf(0.0, float(plan.time) - elapsed)
	return result

func notify_hit() -> void:
	hit = true
	phase = "airborne_follow_through" if _landed_time < 0.0 else "landing"

func cancel(_reason: String = "cancelled") -> void:
	cancelled = true
	# Flight cannot disappear when input is canceled. Finish the real landing.
	if not _taken_off: _finish()

func reset() -> void:
	active = false; plan = {}; phase = "idle"; elapsed = 0.0; cooldown = 0.0
	_issued_candidate = PackedByteArray(); _issued_ball = {}; _last_ai_flight = -1; _next_ai_check_msec = 0
	_taken_off = false; _landed_time = -1.0; hit = false; cancelled = false; _step_velocity = Vector3.ZERO

func _finish() -> void:
	active = false; phase = "idle"
