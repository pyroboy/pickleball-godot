extends RefCounted
## Isolated prototype. Disabled by default; no normal-match hookup.
## Forecast is only eligibility, never permission to award a save.
const Contact = preload("res://scripts/finite_paddle_contact.gd")
const Motion = preload("res://scripts/prototype/long_reach_pose.gd")
const WINDUP := 0.12
const CONTACT_OPEN := 0.38
const CONTACT_CLOSE := 0.57
const RECOVERY_END := Motion.DURATION
const COOLDOWN := 2.50
const MAX_TRAVEL := Motion.MAX_TRAVEL
var enabled := false
var active := false
var elapsed := 0.0
var cooldown := 0.0
var flight_id := -1
var contacted := false
var plan: Dictionary = {}

static func eligible(state: Dictionary) -> bool:
	# Groundstroke-only first prototype. Volleys intentionally unavailable until
	# actual all-body kitchen momentum/landing legality has a verified adapter.
	return bool(state.get("playing", false)) and not bool(state.get("paused", false)) and bool(state.get("in_play", false)) and int(state.get("last_hit_by", -1)) != int(state.get("player_num", 0)) and int(state.get("last_hit_by", -1)) >= 0 and int(state.get("bounces", 0)) == 1 and not bool(state.get("jumping", false))

static func choose_plan(origin: Vector3, state: Dictionary, samples: Array, bounds: Rect2) -> Dictionary:
	if not eligible(state) or not origin.is_finite() or samples.size() > 128: return {}
	for s: Dictionary in samples:
		var t := float(s.get("time", -1.0))
		if t < CONTACT_OPEN or t > CONTACT_CLOSE or int(s.get("bounces", 0)) != 0: continue
		var point: Vector3 = s.get("pos", Vector3.INF)
		if not point.is_finite() or point.y < 0.12 or point.y > 2.80 or point.z * origin.z <= 0.0: continue
		var toward := Vector3(point.x-origin.x, 0, point.z-origin.z)
		var high_blend:float=smoothstep(1.05,1.25,point.y)
		if toward.length() <= lerpf(.90,.70,high_blend): continue
		var direction := toward.normalized()
		# Coarse step candidate only. The real rig/paddle fit is still required
		# before admission; a larger radial window never creates a hitbox.
		if toward.length()>MAX_TRAVEL+1.02:continue
		var travel := clampf(toward.length() - (.82 if point.y>.50 else .70),.25,MAX_TRAVEL)
		if high_blend>0.0:travel=lerpf(travel,clampf(toward.length()-.78,.16,.28),high_blend)
		if WINDUP + travel / 4.5 > t: continue
		var target := origin + direction * travel
		if not bounds.has_point(Vector2(target.x, target.z)): continue
		return {"target": target, "point": point, "direction": direction, "travel": travel, "time": t, "flight_id": state.get("flight_id", -1), "scope": "forecast_candidate_not_save_guarantee"}
	return {}

func begin(candidate: Dictionary, state: Dictionary) -> bool:
	if not enabled or active or cooldown > 0.0 or candidate.is_empty() or not eligible(state): return false
	if int(candidate.get("flight_id", -2)) != int(state.get("flight_id", -1)): return false
	if float(candidate.get("travel", INF)) > MAX_TRAVEL: return false
	plan = candidate.duplicate(true); flight_id = int(state.flight_id)
	active = true; elapsed = 0.0; contacted = false; cooldown = COOLDOWN
	return true

func advance(delta: float, state: Dictionary) -> void:
	if bool(state.get("paused", false)): return
	cooldown = maxf(0.0, cooldown - maxf(0.0, delta))
	if not active: return
	if not bool(state.get("playing", false)) or not bool(state.get("in_play", false)) or (not contacted and (not eligible(state) or int(state.get("flight_id", -1)) != flight_id)):
		active = false; plan = {}; return
	elapsed += maxf(0.0, delta)
	if elapsed >= RECOVERY_END: active = false

func contact_fraction(ball_from: Vector3, ball_to: Vector3, paddle_from: Transform3D, paddle_to: Transform3D, state: Dictionary, radius := 0.0375, step_seconds := 0.0) -> float:
	if not active or contacted or not eligible(state) or int(state.get("flight_id", -1)) != flight_id: return -1.0
	var low := 0.0
	var high := 1.0
	if step_seconds > 0.0:
		var start := elapsed - step_seconds
		if elapsed < CONTACT_OPEN or start > CONTACT_CLOSE: return -1.0
		low = clampf((CONTACT_OPEN - start) / step_seconds, 0.0, 1.0)
		high = clampf((CONTACT_CLOSE - start) / step_seconds, 0.0, 1.0)
	elif elapsed < CONTACT_OPEN or elapsed > CONTACT_CLOSE: return -1.0
	var clipped_from := Contact.interpolate_head_transform(paddle_from, paddle_to, low)
	var clipped_to := Contact.interpolate_head_transform(paddle_from, paddle_to, high)
	var fraction := Contact.first_sweep_fraction(ball_from.lerp(ball_to, low), ball_from.lerp(ball_to, high), clipped_from, clipped_to, radius)
	if fraction >= 0.0:
		contacted = true
		return lerpf(low, high, fraction)
	return -1.0

func reset() -> void:
	active = false; elapsed = 0.0; cooldown = 0.0; flight_id = -1; contacted = false; plan = {}
