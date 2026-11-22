extends RefCounted


const ShotFootwork = preload("res://scripts/shot_footwork_profile.gd")
const Planner = preload("res://scripts/incoming_contact_planner.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const MAX_TRAVEL: = 2.4
const MAX_HORIZON: = 3.0
const MAX_SPEED: = 3.4
const SHUFFLE_SPEED: = 1.55
const ACCEL: = 10.0
const BRAKE: = 12.0
const SPLIT_TIME: = 0.1
const PLANT_TIME: = 0.32
const LOAD_TIME: = 0.08
const ADJUST_DISTANCE: = 0.3
# Standard ShotFootwork profile; stance deltas are measured from it.
const STANCE_REF_WIDTH := 0.54
const STANCE_REF_FRONT := 0.06
const STANCE_REF_BACK := -0.06
const STANCE_DELTA_MAX := 0.12
const SPLIT_DIP := 0.045
const ARRIVAL_DISTANCE: = 0.025
# The shared travel estimate already reserves 0.32 s plant + 0.08 s load.
# Add opening/face-play allowance, rather than counting that plant twice.
const LOB_TURN_ALLOWANCE := 0.55
const LOB_REPLANT_DISTANCE := 0.58
const MAX_BACKWARD_TRAVEL := 2.10
# Smash: an overhead contact at least this high above the floor (the AI's rule:
# 0.6 m over the net). The held-HIT footwork steps under such a ball instead of
# letting it drop, and the court marker shows the spot.
const SMASH_MIN_HEIGHT := 1.5
const SMASH_PLAN_BONUS := 0.9        # score units (~2 s of waiting): prefer the smash
const SMASH_SPOT_MAX_TRAVEL := 4.5   # m the marker asks a player to run
const SMASH_SPOT_SETTLE := 0.3       # s to stop and raise the paddle after running
var player
var _human: WeakRef
var human:
	get: return _human.get_ref()
var state: = "idle"
var plan: Dictionary = {}
var load_side: = 0
var velocity: = Vector3.ZERO
var elapsed: = 0.0
var load_elapsed: = 0.0
var active: = false
var suppressed: = false
var _flight_id: = -1
var _start_root: = Vector3.ZERO
var _held_last: = false
var _search_clock: = 0.0
var _invalid_prediction_time: = 0.0
var _recover_time: = 0.0
var _recovery_target: = Vector3.INF
var cancel_reason: = ""
var state_history: Array[String] = []
var _travel_visual_weight := 0.0
var _latched_support: Dictionary = {}

func _init(owner, controller) -> void :
	player = owner
	_human = weakref(controller)

func _state(value: String) -> void :
	if state == value: return
	state = value
	state_history.append(value)

func cancel(reason: String = "cancel", suppress_held: bool = true) -> void :
	active = false
	plan = {}
	velocity = Vector3.ZERO
	elapsed = 0.0
	load_elapsed = 0.0
	_search_clock = 0.0
	_invalid_prediction_time = 0.0
	_recover_time = 0.0
	_recovery_target = Vector3.INF
	_latched_support.clear()
	cancel_reason = reason
	suppressed = suppress_held and Input.is_action_pressed("ui_accept")
	_state("idle")

func wants_plant() -> bool:
	return active and state in ["plant", "load", "swing"]

func ready_to_strike() -> bool:
	return not active or state in ["load", "swing"] and load_elapsed >= _support_profile().load_time

func _support_profile() -> Dictionary:
	if not _latched_support.is_empty(): return _latched_support
	var context: Dictionary = ShotFootwork.context_from(plan).duplicate()
	if player.leg_ik != null: context.merge(player.leg_ik._shot_context, true)
	if human != null: context.merge(ShotFootwork.context_from(human.contact), true)
	return ShotFootwork.from_context(context)

func motion_context() -> Dictionary:
	var context: Dictionary = ShotFootwork.context_from(plan).duplicate()
	context["flight_id"] = _flight_id
	context["time_to_contact"] = plan.get("time", INF)
	context["lob_retrieval"] = bool(plan.get("lob_retrieval", false))
	return context

func _eligible(ball) -> bool:
	var game = player.get_parent()
	return not player.is_ai and not player.posture.editor_preview_mode and game.game_state == game.GameState.PLAYING and not game._tool_state_active() and not game.match_over and ball != null and ball.is_in_play and ball.last_hit_by != player.player_num and ball.bounces_since_last_hit < 2 and not player.is_jumping

func movement(delta: float, manual: Vector3) -> Vector3:
	if not is_finite(delta) or delta <= 0.0: return Vector3.ZERO
	var moving_charge:bool=human.phase <= 0 and player.hitting.charge_visual_active and Vector2(player.current_velocity.x,player.current_velocity.z).length() > .18
	var target_weight:float=1.0 if moving_charge else 0.0
	_travel_visual_weight=move_toward(_travel_visual_weight,target_weight,(3.0 if moving_charge else 1.75)*maxf(delta,0.0))
	var held: = Input.is_action_pressed("ui_accept")
	if not held: suppressed = false
	var fresh: = held and not _held_last
	_held_last = held
	var ball = player._get_ball_ref()
	if manual.length_squared() > 0.0001:
		if active:
			cancel("manual movement")


		elif held: suppressed = true
		return manual * player.move_speed
	var game = player.get_parent()
	if active and human.phase >= 2 and ball != null and ball.is_in_play and game.game_state == game.GameState.PLAYING and not game._tool_state_active():
		_state("recover")
		_recover_time += delta
		if not _recovery_target.is_finite():
			var toward: Vector3 = _start_root - player.global_position
			toward.y = 0.0
			_recovery_target = player.global_position + toward.limit_length(float(_support_profile().recovery_distance))
		if human.phase == 4:
			var offset: Vector3 = _recovery_target - player.global_position
			offset.y = 0.0
			velocity = velocity.move_toward(offset.limit_length(float(_support_profile().recovery_speed) * delta) / maxf(delta, 1e-05), ACCEL * delta)
		else: velocity = velocity.move_toward(Vector3.ZERO, BRAKE * delta)
		return velocity
	if not _eligible(ball):
		if active: cancel("flight ended")
		return Vector3.ZERO
	if active and ball.flight_id != _flight_id:
		cancel("flight changed")
	if human.phase == 1 and active:
		_state("swing")
		velocity = Vector3.ZERO
		return velocity

	if fresh: suppressed = false
	if not active:


		# A ball already in reach starts no footwork, unless stepping under it
		# turns the shot into a smash.
		if not human.contact.is_empty() and not bool(human.anticipated_contact.get("smash", false)): return Vector3.ZERO
		if suppressed or not held or not player.hitting.charge_visual_active: return Vector3.ZERO
		_search_clock -= delta
		if _search_clock > 0.0: return Vector3.ZERO
		_search_clock = 0.1
		var candidate: Dictionary = human.anticipated_contact.duplicate()
		if candidate.is_empty():


			if human.prediction_flight_id == ball.flight_id: return Vector3.ZERO
			var flight: Dictionary = Flight.trace(ball.global_position, ball.linear_velocity, ball.angular_velocity, MAX_HORIZON)
			candidate = select_plan(player, ball, flight)
		if candidate.is_empty(): return Vector3.ZERO

		if float(candidate.distance) < 0.06: return Vector3.ZERO
		if not activate_plan(candidate, ball): return Vector3.ZERO
	if not held and human.phase < 0:
		cancel("released without queued shot", false)
		return Vector3.ZERO
	elapsed += delta
	plan.time = float(plan.time) - delta

	if float(plan.time) < -0.1 or ball.bounces_since_last_hit >= 2:
		if human.phase == 0: human.cancel()
		cancel("interception expired")
		return Vector3.ZERO
	if elapsed < SPLIT_TIME:
		return Vector3.ZERO
	var offset: Vector3 = plan.target_root - player.global_position
	offset.y = 0.0
	var distance: = offset.length()
	if state in ["plant", "load"] or distance <= ARRIVAL_DISTANCE:
		# A late tactical refinement cannot retarget shoes underneath contact.
		if _latched_support.is_empty(): _latched_support = _support_profile().duplicate(true)
		velocity = Vector3.ZERO
		if state != "load": _state("plant")
		var feet_ready: bool = player.leg_ik != null and player.leg_ik.right_foot_locked and player.leg_ik.left_foot_locked and not player.leg_ik._run_active and player.leg_ik._active_side < 0
		if player.leg_ik != null and player.leg_ik.has_method("is_support_ready"):
			feet_ready = player.leg_ik.is_support_ready(load_side)
		if feet_ready:
			load_elapsed += delta
			if load_elapsed >= float(_support_profile().load_time): _state("load")
		else:
			load_elapsed = 0.0
			_state("plant")
		return velocity
	var near: bool = absf(player.global_position.z) < PickleballConstants.NON_VOLLEY_ZONE + 0.85
	var lob: bool = bool(plan.get("lob_retrieval", false))
	var crossing: bool = float(plan.distance) > 0.85 and not near
	var next_state := "adjust" if distance < ADJUST_DISTANCE else ("crossover" if crossing else "shuffle")
	if lob:
		if elapsed < SPLIT_TIME + 0.20: next_state = "lob_drop_step"
		elif distance < LOB_REPLANT_DISTANCE or float(plan.time) <= 0.95: next_state = "lob_replant"
		else: next_state = "lob_run"
	_state(next_state)
	var speed_cap: float = minf(player.move_speed, MAX_SPEED if crossing or lob else SHUFFLE_SPEED)
	if state == "lob_drop_step": speed_cap = minf(speed_cap, 1.45)
	if state == "lob_replant": speed_cap = minf(speed_cap, 1.15)
	if state == "adjust": speed_cap = minf(speed_cap, 0.85)
	var speed: float = minf(speed_cap, sqrt(2.0 * BRAKE * maxf(0.0, distance - ARRIVAL_DISTANCE * 0.5)))
	velocity = velocity.move_toward(offset.normalized() * speed, ACCEL * delta)

	if velocity.length() * delta > distance: velocity = offset / maxf(delta, 1e-05)
	return velocity

func activate_plan(candidate: Dictionary, ball) -> bool:
	if active: return true
	if suppressed or candidate.is_empty() or bool(candidate.get("preparation_only", false)) or not _eligible(ball): return false
	if int(candidate.get("flight_id", -1)) != ball.flight_id: return false
	if not candidate.get("target_root", Vector3.INF).is_finite(): return false
	if candidate.target_root.distance_to(player.global_position) > MAX_TRAVEL: return false
	var shift: Vector3 = candidate.target_root - player.global_position
	if not route_is_safe(player, shift, candidate.get("target_root"), bool(candidate.get("lob_retrieval", false)), int(candidate.get("bounces", 0)) + ball.bounces_since_last_hit, Planner.wall_mode(ball)): return false
	var lob: bool = bool(candidate.get("lob_retrieval", false))
	if lob and float(candidate.get("time", 0.0)) < travel_time(shift.length(), minf(player.move_speed, MAX_SPEED)) + LOB_TURN_ALLOWANCE + float(candidate.def.ft_duration_strike): return false
	plan = candidate.duplicate()
	_latched_support.clear()
	active = true
	_flight_id = ball.flight_id
	_start_root = player.global_position
	elapsed = 0.0
	load_elapsed = 0.0
	state_history.clear()
	load_side = _load_side_for(plan)
	_state("split")
	return true

func refresh_prediction(ball, flight: Dictionary) -> void :
	if not active or human.phase >= 1: return
	if not _eligible(ball) or ball.flight_id != _flight_id:
		cancel("prediction ownership changed")
		return


	var base: PostureDefinition = PostureLibrary.instance().get_def(int(plan.posture))
	var shift: Vector3 = plan.target_root - player.global_position
	var fwd: Vector3 = player._get_forward_axis()
	var samples: Array = flight.get("samples", [])
	var fault_time: float = Planner.predicted_fault_time(player, ball, flight)
	if float(plan.time) >= fault_time and human.contact.is_empty():
		cancel("predicted rally fault")
		if human.phase == 0: human.cancel()
		return
	for index in range(samples.size() - 1):
		var a: Dictionary = samples[index]
		var b: Dictionary = samples[index + 1]
		var da: float = (a.pos - plan.target_root).dot(fwd) - base.zone_forward_offset
		var db: float = (b.pos - plan.target_root).dot(fwd) - base.zone_forward_offset
		if da < 0.0 or db > 0.0 or da - db < 1e-05 or a.bounces != b.bounces: continue
		var fraction: float = clampf(da / (da - db), 0.0, 1.0)
		var point: Vector3 = a.pos.lerp(b.pos, fraction)
		if lerpf(a.time, b.time, fraction) >= fault_time: continue
		var bounces: int = int(b.bounces) + ball.bounces_since_last_hit
		if bounces >= 2 or bounces == 0 and not ball.both_bounces_complete: continue
		if bounces == 0 and ( not Planner.wall_mode(ball) and absf(plan.target_root.z) < PickleballConstants.NON_VOLLEY_ZONE + 0.55 or not Planner.legal_ball(player, ball)): continue
		if not Planner.point_fits(player, base, point - shift): continue
		plan.point = point
		plan.time = lerpf(a.time, b.time, fraction)
		plan.bounces = int(b.bounces)
		plan.def = Planner.pose_at(player, base, point - shift)
		_invalid_prediction_time = 0.0
		return


	if state not in ["plant", "load"] and float(plan.time) > 0.5:
		var revised: Dictionary = select_plan(player, ball, flight)
		if not revised.is_empty() and revised.target_root.distance_to(_start_root) <= MAX_TRAVEL:
			# Replanning may refine geometry, never erase the selected shot intent.
			if plan.has("motion_context"): revised["motion_context"] = plan.motion_context.duplicate(true)
			plan = revised
			load_side = _load_side_for(plan)
			_invalid_prediction_time = 0.0
			return


	_invalid_prediction_time += 0.1
	if _invalid_prediction_time > 0.21 and human.contact.is_empty():
		cancel("prediction no longer reachable")
		if human.phase == 0: human.cancel()

static func _load_side_for(candidate: Dictionary) -> int:
	# Overheads (family 3) load like a forehand.
	var forehand: bool = int(candidate.def.family) in [0, 3]
	return 1 if bool(candidate.neutral) and forehand else (0 if forehand else 1)

static func is_smash_contact(owner, candidate: Dictionary) -> bool:
	var def = candidate.get("def")
	if def == null or not candidate.has("point"): return false
	return int(def.family) == 3 and candidate.point.y - owner.COURT_FLOOR_Y >= SMASH_MIN_HEIGHT

## Where to stand to smash this ball, from the player's current position: the
## nearest overhead contact the player can still run to (manual speed), whether
## or not the held-HIT footwork could get there by itself. Presentation and
## planning hint only; the real contact is still chosen by the planner.
static func select_smash_spot(owner, ball, flight: Dictionary, previous: Dictionary = {}) -> Dictionary:
	if not Planner.should_track(owner, ball) or Planner.wall_mode(ball): return {}
	var fault_time: float = Planner.predicted_fault_time(owner, ball, flight)
	var fwd: Vector3 = owner._get_forward_axis()
	var fh: Vector3 = owner._get_forehand_axis()
	var samples: Array = flight.get("samples", [])
	var previous_target: Vector3 = previous.get("target_root", Vector3.INF)
	var bases: Array = []
	for base in PostureLibrary.instance().all_definitions():
		if base.has_zone and base.family == 3: bases.append(base)
	var best: Dictionary = {}
	var best_base: PostureDefinition
	var best_score: = INF
	for index in range(0, samples.size(), 2):
		var sample: Dictionary = samples[index]
		var time: float = sample.time
		if time < 0.1 or time > MAX_HORIZON or time >= fault_time: continue
		var point: Vector3 = sample.pos
		var height: float = point.y - owner.COURT_FLOOR_Y
		if height < SMASH_MIN_HEIGHT: continue
		var bounces: int = int(sample.bounces) + ball.bounces_since_last_hit
		if bounces >= 2 or bounces == 0 and not ball.both_bounces_complete: continue
		if point.z * owner.global_position.z <= 0.0: continue
		for base in bases:
			if height < base.zone_y_min or height > base.zone_y_max: continue
			var target: Vector3 = point - fh * base.paddle_forehand_mul - fwd * base.zone_forward_offset
			target.y = owner.ground_y
			if owner.bounds_ready and (target.x < owner.min_x or target.x > owner.max_x or target.z < owner.min_z or target.z > owner.max_z): continue
			if target.z * owner.global_position.z <= 0.0: continue
			# A volley needs both shoes clear of the kitchen.
			if bounces == 0 and absf(target.z) < PickleballConstants.NON_VOLLEY_ZONE + 0.55: continue
			var shift: Vector3 = target - owner.global_position
			shift.y = 0.0
			var distance: float = shift.length()
			if distance > SMASH_SPOT_MAX_TRAVEL: continue
			if distance > 0.3 and distance / maxf(owner.move_speed, 0.1) + SMASH_SPOT_SETTLE + base.ft_duration_strike > time: continue
			# Nearest spot, but a ball still in the air beats waiting for its bounce.
			var score: float = distance + time * 0.1 + (0.0 if bounces == 0 else 1.2) - (0.25 if previous_target.is_finite() and previous_target.distance_to(target) < 0.35 else 0.0)
			if score >= best_score: continue
			if not Planner.point_fits(owner, base, point - shift): continue
			best_score = score
			best_base = base
			best = {"flight_id": ball.flight_id, "point": point, "target_root": target, "time": time, "bounces": int(sample.bounces), "posture": base.posture_id, "distance": distance, "smash": true}
	if best.is_empty(): return best
	best["path"] = path_to(flight, best)
	best["def"] = Planner.pose_at(owner, best_base, best.point - (best.target_root - owner.global_position) * Vector3(1, 0, 1))
	return best

## Flight points from the ball to a planned contact, for the smash guide.
static func path_to(flight: Dictionary, candidate: Dictionary) -> PackedVector3Array:
	var path: = PackedVector3Array()
	var samples: Array = flight.get("samples", [])
	for index in range(0, samples.size(), 2):
		if float(samples[index].time) >= float(candidate.time): break
		path.append(samples[index].pos)
	path.append(candidate.point)
	return path

static func travel_time(distance: float, speed: float) -> float:
	if not is_finite(distance) or not is_finite(speed) or distance < 0.0 or speed <= 0.0: return INF
	var ramp_distance: float = speed * speed * (0.5 / ACCEL + 0.5 / BRAKE)
	var motion: float
	if distance <= ramp_distance:
		motion = sqrt(2.0 * distance * (1.0 / ACCEL + 1.0 / BRAKE))
	else:
		motion = speed / ACCEL + speed / BRAKE + (distance - ramp_distance) / speed


	return SPLIT_TIME + motion + minf(distance, ADJUST_DISTANCE) * 0.55 + PLANT_TIME + LOAD_TIME

static func select_plan(owner, ball, flight: Dictionary, smash_only: bool = false) -> Dictionary:
	if not Planner.should_track(owner, ball): return {}
	var fault_time: float = Planner.predicted_fault_time(owner, ball, flight)
	var best: Dictionary = {}
	var best_score: = INF
	var fwd: Vector3 = owner._get_forward_axis()
	var fh: Vector3 = owner._get_forehand_axis()
	var samples: Array = flight.get("samples", [])
	var near: bool = absf(owner.global_position.z) < PickleballConstants.NON_VOLLEY_ZONE + 0.85
	for index in range(0, samples.size(), 3):
		var sample: Dictionary = samples[index]
		var time: float = sample.time
		if time < 0.12 or time > MAX_HORIZON or time >= fault_time: continue
		var point: Vector3 = sample.pos
		var bounces: int = int(sample.bounces) + ball.bounces_since_last_hit
		if bounces >= 2 or bounces == 0 and not ball.both_bounces_complete: continue
		if point.z * owner.global_position.z <= 0.0: continue
		for base in PostureLibrary.instance().all_definitions():
			if not base.has_zone or base.family not in [0, 1, 3] or base.posture_id in [8, 9]: continue
			var height: float = point.y - owner.COURT_FLOOR_Y
			# Overheads join the footwork plan only as a smash (never in wall practice).
			var smash: bool = base.family == 3
			if smash and (height < SMASH_MIN_HEIGHT or Planner.wall_mode(ball)) or smash_only and not smash: continue
			if height < Planner.ActivationZones.minimum_height(base, 0.0) or height > base.zone_y_max: continue
			var target: Vector3 = point - fh * base.paddle_forehand_mul - fwd * base.zone_forward_offset
			target.y = owner.ground_y
			if owner.bounds_ready and (target.x < owner.min_x or target.x > owner.max_x or target.z < owner.min_z or target.z > owner.max_z): continue
			var shift: Vector3 = target - owner.global_position
			shift.y = 0.0
			var distance: = shift.length()
			if distance > MAX_TRAVEL: continue
			var forward_travel: float = shift.dot(fwd)

			var lob: bool = forward_travel < -0.45 and not Planner.wall_mode(ball)
			if not route_is_safe(owner, shift, target, lob, bounces, Planner.wall_mode(ball)): continue
			var speed: float = minf(owner.move_speed, MAX_SPEED if distance > 0.85 and not near else SHUFFLE_SPEED)
			if travel_time(distance, speed) + base.ft_duration_strike + (LOB_TURN_ALLOWANCE if lob else 0.0) > time: continue


			var relative_point: Vector3 = point - shift
			if not Planner.point_fits(owner, base, relative_point): continue


			if bounces == 0 and ( not Planner.wall_mode(ball) and absf(target.z) < PickleballConstants.NON_VOLLEY_ZONE + 0.55 or not Planner.legal_ball(owner, ball)): continue
			var wide: bool = base.posture_id in [10, 11, 16, 17, 18, 19]


			var score: float = time * 0.48 + distance * 0.55 + (0.12 if wide else 0.0) - (SMASH_PLAN_BONUS if smash else 0.0)
			if score >= best_score: continue
			best_score = score
			var pose: PostureDefinition = Planner.pose_at(owner, base, relative_point)
			best = {"flight_id": ball.flight_id, "point": point, "target_root": target, "time": time, "bounces": int(sample.bounces), "posture": base.posture_id, "def": pose, "distance": distance, "score": score, "neutral": forward_travel > absf(shift.dot(fh)) * 1.3, "lunge": wide, "lob_retrieval": lob, "smash": smash}
	return best

static func route_is_safe(owner, shift: Vector3, target: Vector3, lob: bool, bounces: int, wall: bool = false) -> bool:
	if not shift.is_finite() or not target.is_finite() or shift.length() > MAX_TRAVEL: return false
	if owner.bounds_ready and (target.x < owner.min_x or target.x > owner.max_x or target.z < owner.min_z or target.z > owner.max_z): return false
	if target.z * owner.global_position.z <= 0.0: return false
	var backward: float = -shift.dot(owner._get_forward_axis())
	if backward > 0.45 and (not lob or wall or backward > MAX_BACKWARD_TRAVEL): return false
	if bounces == 0 and not wall:
		# Both endpoints plus the entire straight root segment keep a shoe margin
		# outside the NVZ. No off-court exception is invented by this adapter.
		if minf(absf(target.z), absf(owner.global_position.z)) < PickleballConstants.NON_VOLLEY_ZONE + 0.55: return false
	return true

static func select_preparation(owner, ball, flight: Dictionary, previous_id: int = -1) -> Dictionary:



	if not Planner.should_track(owner, ball): return {}
	var samples: Array = flight.get("samples", [])
	var fault_time: float = Planner.predicted_fault_time(owner, ball, flight)
	var fwd: Vector3 = owner._get_forward_axis()
	var fh: Vector3 = owner._get_forehand_axis()
	var half_width: float = PickleballConstants.COURT_WIDTH * 0.5
	var best: Dictionary = {}
	var best_score: = INF
	for base in PostureLibrary.instance().all_definitions():
		if not base.has_zone or base.posture_id in [8, 9]: continue
		for index in range(samples.size() - 1):
			var a: Dictionary = samples[index]
			var b: Dictionary = samples[index + 1]
			var da: float = (a.pos - owner.global_position).dot(fwd) - base.zone_forward_offset
			var db: float = (b.pos - owner.global_position).dot(fwd) - base.zone_forward_offset
			if da < 0.0 or db > 0.0 or da - db < 1e-05 or a.bounces != b.bounces: continue
			var fraction: float = clampf(da / (da - db), 0.0, 1.0)
			var time: float = lerpf(a.time, b.time, fraction)
			if time < 0.0 or time > MAX_HORIZON or time >= fault_time: continue
			var point: Vector3 = a.pos.lerp(b.pos, fraction)
			var bounces: int = int(b.bounces) + ball.bounces_since_last_hit
			if bounces >= 2 or bounces == 0 and not ball.both_bounces_complete: continue
			if point.z * owner.global_position.z <= 0.0: continue
			var target: Vector3 = point - fh * base.paddle_forehand_mul - fwd * base.zone_forward_offset
			target.y = owner.ground_y


			if absf(target.x) > half_width or absf(target.z) > PickleballConstants.BASELINE_Z: continue
			if owner.bounds_ready and (target.x < owner.min_x or target.x > owner.max_x or target.z < owner.min_z or target.z > owner.max_z): continue
			var shift: Vector3 = target - owner.global_position
			shift.y = 0.0
			var relative_point: Vector3 = point - shift
			if not Planner.point_fits(owner, base, relative_point): continue
			if bounces == 0 and ( not Planner.wall_mode(ball) and absf(target.z) < PickleballConstants.NON_VOLLEY_ZONE + 0.55 or not Planner.legal_ball(owner, ball)): continue
			var wide: bool = base.posture_id in [10, 11, 16, 17, 18, 19]
			var distance: float = shift.length()
			var height_error: float = absf(relative_point.y - owner.global_position.y - base.paddle_y_offset)
			var score: float = distance * 0.3 + height_error + time * 0.015 + (0.12 if wide else 0.0) - (0.045 if base.posture_id == previous_id else 0.0)
			if score < best_score:
				best_score = score
				best = {"flight_id": ball.flight_id, "point": point, "target_root": target, "time": time, "bounces": int(b.bounces), "posture": base.posture_id, "def": Planner.pose_at(owner, base, relative_point), "distance": distance, "score": score, "neutral": false, "lunge": wide, "preparation_only": true}
			break
	return best

func apply_stance(pose: PostureDefinition) -> PostureDefinition:
	if pose == null: return pose
	var travel_weight:float=_travel_visual_weight if human.phase <= 0 else 0.0
	if not active and travel_weight <= .00001: return pose


	var result: PostureDefinition = pose.lerp_with(pose, 0.0)
	for key in pose.get_meta_list(): result.set_meta(key, pose.get_meta(key))
	if human.phase <= 0:
		result.set_meta("visual_locomotion_weight",maxf(float(pose.get_meta("visual_locomotion_weight",0.0)),travel_weight))
		result.set_meta("travel_locomotion_weight",maxf(float(pose.get_meta("travel_locomotion_weight",0.0)),travel_weight))
		if travel_weight > .00001: result.set_meta("travel_paddle_follow",true)
	if not active: return result
	var neutral: bool = bool(plan.get("neutral", false))
	var support: Dictionary = _support_profile()
	# The authored stance of the planned stroke (plan.def: width, lead foot,
	# foot spacing, foot yaw, foot offsets) is the base. Footwork only adds a
	# bounded delta: how far its profile differs from the standard profile.
	# Root travel, not stance, reaches the planned spot. plan.def (not the
	# incoming pose) is the base so the delta never compounds across ticks:
	# visual_pose is fed back through blends that drop metadata.
	var authored: PostureDefinition = plan.def
	var width: float = 0.48 if neutral else (0.66 if bool(plan.get("lunge", false)) else float(support.width))
	var front: float = 0.18 if neutral else float(support.front)
	var back: float = -0.14 if neutral else float(support.back)
	result.stance_width = authored.stance_width + clampf(width - STANCE_REF_WIDTH, -STANCE_DELTA_MAX, STANCE_DELTA_MAX)
	result.front_foot_forward = authored.front_foot_forward + clampf(front - STANCE_REF_FRONT, -STANCE_DELTA_MAX, STANCE_DELTA_MAX)
	result.back_foot_back = authored.back_foot_back + clampf(back - STANCE_REF_BACK, -STANCE_DELTA_MAX, STANCE_DELTA_MAX)
	result.lead_foot = authored.lead_foot
	result.left_foot_offset = authored.left_foot_offset
	result.right_foot_offset = authored.right_foot_offset
	result.right_foot_yaw_deg = authored.right_foot_yaw_deg
	result.left_foot_yaw_deg = authored.left_foot_yaw_deg
	# Split step: a short dip on top of the authored crouch (no fixed floor).
	if state == "split": result.crouch_amount = maxf(pose.crouch_amount, authored.crouch_amount + sin(clampf(elapsed / SPLIT_TIME, 0.0, 1.0) * PI) * SPLIT_DIP)

	var load_weight: float = minf(load_elapsed / float(support.load_time), 1.0) if state == "load" else 0.0
	if state == "swing": load_weight = 1.0 - clampf(human.elapsed / maxf(human.strike_time, 0.01), 0.0, 1.0)
	result.set_meta("charged_load_lateral", (0.055 if load_side == 0 else -0.055) * load_weight if not neutral else 0.0)
	return result
