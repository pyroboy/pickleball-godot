extends RefCounted
## Intent state machine. Feet own the actual turn; this class chooses when a
## court-facing shuffle/backpedal is preferable to longer crossover steps.
## Ordinary travel respects the court frame. Live lob retrieval can turn the
## visual pelvis through support-safe steps; targeting axes remain court-fixed.
const IDLE_SPEED := 0.10
const BACKWARD_ENTER := 0.34
const BACKWARD_EXIT := 0.22
const LATERAL_ENTER := 0.65
const LATERAL_EXIT := 0.53
const TURN_ROUTE_TIME := 0.18
const LATERAL_TURN_DISTANCE := 0.75
const WALL_TURN_DISTANCE := 1.25
const LOB_DROP_STEP_TIME := 0.20
const LOB_FACE_TIME := 0.95
const LOB_ENTER_SPEED := 1.15

var state := "ready"
var previous_state := "ready"
var state_elapsed := 0.0
var transition_serial := 0
var reason := "stationary"
var desired_heading := 0.0
var gait := "stance"
var phase := "ready"
var route_distance := 0.0
var route_time := 0.0
var route_direction := Vector3.ZERO
var lob_active := false
var lob_elapsed := 0.0
var lob_heading := 0.0
var lob_replant := false
var _lob_flight := -1

func reset() -> void:
	state = "ready"
	previous_state = state
	state_elapsed = 0.0
	transition_serial = 0
	reason = "stationary"
	desired_heading = 0.0
	gait = "stance"
	phase = "ready"
	route_distance = 0.0
	route_time = 0.0
	route_direction = Vector3.ZERO
	lob_active = false; lob_elapsed = 0.0; lob_heading = 0.0; lob_replant = false; _lob_flight = -1

func update(delta: float, velocity: Vector3, traveled: float, court: Vector3,
		context: String, charged_phase: String, ball_behind: bool, unsettled: bool, shot_context: Dictionary = {}) -> void:
	if not is_finite(delta) or delta < 0.0 or not velocity.is_finite(): return
	var speed := velocity.length()
	var next := "ready"
	desired_heading = 0.0
	gait = "stance"
	phase = "ready"
	reason = "stationary"
	if speed <= IDLE_SPEED:
		route_distance = 0.0
		route_time = 0.0
		route_direction = Vector3.ZERO
		if charged_phase in ["plant", "load", "swing"]:
			next = "planted_contact"; phase = "plant_load"; reason = "contact support"
		elif charged_phase == "split":
			next = "split"; phase = "split"; reason = "receive split step"
		elif unsettled or charged_phase == "recover":
			next = "recover"; phase = "recover"; reason = "finish steps and face play"
	else:
		var travel := velocity / speed
		if route_direction.length_squared() < 0.5 or route_direction.dot(travel) < 0.45:
			route_distance = 0.0
			route_time = 0.0
		route_direction = travel
		route_distance += traveled
		route_time += delta
		var backward := -travel.dot(court)
		var lateral := absf(travel.dot(Vector3(-court.z, 0, court.x)))
		var backward_limit := BACKWARD_EXIT if state in ["backpedal", "backward_strafe"] else BACKWARD_ENTER
		var lateral_limit := LATERAL_EXIT if state in ["lateral_shuffle", "backward_strafe"] else LATERAL_ENTER
		var forced_shuffle := charged_phase in ["shuffle", "adjust", "plant", "load", "swing"]
		phase = "adjust" if charged_phase == "adjust" else "travel"
		var turn_distance := WALL_TURN_DISTANCE if context == "wall" else LATERAL_TURN_DISTANCE
		var sustained := route_time >= TURN_ROUTE_TIME
		if context == "pickup":
			next = "pickup_travel"; reason = "dead-ball approach or carry"
			desired_heading = court.signed_angle_to(travel, Vector3.UP)
			gait = "walk" if speed < 1.65 else "run"
		elif backward > backward_limit:
			next = "backward_strafe" if lateral > 0.35 else "backpedal"
			reason = "retreat while facing play"
			gait = "shuffle"
		elif charged_phase == "crossover" or lateral > lateral_limit and speed > 1.65 and route_distance > turn_distance and sustained and not forced_shuffle:
			next = "lateral_crossover"; reason = "sustained lateral coverage, Ready-facing"
			# Travel direction does not redefine Ready/paddle presentation heading.
			gait = "crossover" if charged_phase == "crossover" or route_distance < turn_distance + 0.72 else "run"
		elif lateral > lateral_limit or forced_shuffle:
			next = "lateral_shuffle"; reason = "short adjustment or contact approach"
			gait = "shuffle"
		else:
			next = "advance"; reason = "forward travel, Ready-facing"
			gait = "walk" if speed < 1.65 else ("jog" if speed < 3.2 else "run")
		if charged_phase == "recover": phase = "recover"
	# A latched live retrieval has one opening step, a bounded turn/run, then a
	# court-facing replant. Losing a ball prediction cannot restart its pivot.
	var flight: int = int(shot_context.get("flight_id", -1))
	var remaining: float = float(shot_context.get("time_to_contact", INF))
	var contact_phase := charged_phase in ["lob_replant", "plant", "load", "swing"]
	var retreating := speed > IDLE_SPEED and -velocity.normalized().dot(court) > BACKWARD_EXIT
	var valid_lob := context == "rally" and bool(shot_context.get("lob_retrieval", ball_behind)) and not bool(shot_context.get("interrupted", false))
	if context != "rally" or bool(shot_context.get("interrupted", false)) or (_lob_flight >= 0 and flight >= 0 and flight != _lob_flight):
		lob_active = false; lob_replant = false; lob_elapsed = 0.0
	if not lob_active and valid_lob and (ball_behind or charged_phase == "lob_drop_step") and retreating and speed >= LOB_ENTER_SPEED and remaining > LOB_FACE_TIME and not contact_phase:
		lob_active = true; lob_replant = false; lob_elapsed = 0.0; _lob_flight = flight
		lob_heading = court.signed_angle_to(velocity.normalized(), Vector3.UP)
		if absf(lob_heading) < deg_to_rad(70.0): lob_heading = signf(lob_heading) * deg_to_rad(70.0)
	if lob_active:
		lob_elapsed += delta
		if contact_phase or remaining <= LOB_FACE_TIME or not retreating or charged_phase == "recover": lob_replant = true
		if lob_replant:
			desired_heading = 0.0
			if contact_phase and charged_phase in ["plant", "load", "swing"] and not unsettled:
				next = "planted_contact"; phase = "plant_load"; gait = "stance"
			elif unsettled or speed > IDLE_SPEED:
				next = "lob_replant"; phase = "recover"; gait = "shuffle" if speed > IDLE_SPEED else "stance"
			else:
				next = "lob_face_play"; phase = "ready"; gait = "stance"; lob_active = false
			reason = "recover court-facing support before contact"
		elif lob_elapsed < LOB_DROP_STEP_TIME:
			next = "lob_drop_step"; phase = "travel"; gait = "drop_step"
			desired_heading = clampf(lob_heading, -deg_to_rad(60.0), deg_to_rad(60.0))
			reason = "open outside foot for live ball behind"
		else:
			next = "lob_pivot_run"; phase = "travel"; gait = "run"
			desired_heading = lob_heading; reason = "turn and run to live lob"
	elif next == "recover":
		var profile: String = str(shot_context.get("profile", "LEGACY"))
		if profile == "JAMMED": next = "jam_recover"
		elif profile == "HALF_VOLLEY": next = "short_hop_recover"
		elif str(shot_context.get("recovery_kind", "")) in ["emergency", "extended_reach", "reach"]: next = "emergency_recover"
	if next != state:
		previous_state = state
		state = next
		state_elapsed = 0.0
		transition_serial += 1
	else:
		state_elapsed += delta
