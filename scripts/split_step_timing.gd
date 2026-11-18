extends RefCounted
## A single neutral receive split per visible strike cue. This never predicts a
## shot, chooses a target, changes velocity, or gates paddle contact.
const CUE_WINDOW := 0.24
const MIN_HOP_LEAD := 0.065
const CONTACT_GUARD := 0.22
const LOAD_TIME := 0.045
const LAND_AFTER_STRIKE := 0.025
const LAND_TIME := 0.055
const PUSH_TIME := 0.12
const RECOVER_TIME := 0.10
const READ_TIMEOUT := 0.85
const HOP_HEIGHT := 0.025
const LOAD_DEPTH := 0.028

var phase := "ready"
var event_serial := 0
var landing_serial := 0
var hop_count := 0
var skipped_hop_count := 0
var strike_count := 0
var event_id := -1
var reason := "waiting for opponent cue"
var direction := Vector3.ZERO
var _clock := 0.0
var _start := 0.0
var _load_end := 0.0
var _land_at := 0.0
var _land_start := 0.0
var _phase_start := 0.0
var _last_cue := -1
var _last_strike := -1
var _struck := false
var _hop := false
var _height := HOP_HEIGHT
var _load_depth := LOAD_DEPTH
var intensity := 0.0

func cancel(why: String = "interrupted") -> void:
	phase = "ready"
	direction = Vector3.ZERO
	_hop = false
	_struck = false
	reason = why

func update(delta: float, context: Dictionary) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	_clock += delta
	var strike: int = int(context.get("strike_id", -1))
	var cue: int = int(context.get("cue_id", -1))
	var imminent: bool = bool(context.get("own_stroke", false))
	var own_time: float = float(context.get("time_to_contact", INF))
	imminent = imminent or own_time >= 0.0 and own_time <= CONTACT_GUARD
	if not bool(context.get("live", true)) or imminent:
		# Consuming these IDs prevents a held/late cue bouncing after interruption.
		if strike > _last_strike and bool(context.get("live", true)):
			strike_count += 1
			if event_id != strike:
				event_id = strike
				event_serial += 1
				skipped_hop_count += 1
		_last_cue = maxi(_last_cue, maxi(cue, strike))
		_last_strike = maxi(_last_strike, strike)
		cancel("own contact takes priority" if imminent else "inactive or reset")
		return
	if strike > _last_strike:
		_last_strike = strike
		_last_cue = maxi(_last_cue, strike)
		strike_count += 1
		if event_id != strike:
			_begin(strike, 0.0)
			_land("late strike cue: grounded load")
		elif phase in ["split_load", "split_unweight"]:
			# Land around/just after actual impact, even if the visible cue varied.
			_land_at = minf(_land_at, _clock + LAND_AFTER_STRIKE)
		elif phase in ["ready", "recover"]:
			_land("delayed strike: grounded load")
		_struck = true
	elif cue > _last_cue:
		var lead: float = float(context.get("cue_lead", INF))
		if lead <= CUE_WINDOW:
			_last_cue = cue
			_begin(cue, lead if bool(context.get("hop_allowed", true)) else 0.0)
			if not _hop:
				# Stay grounded until actual impact; do not bob once for a late
				# estimate and again when the delayed real strike arrives.
				phase = "ready"
				reason = "late or unsettled cue: wait grounded"
	if phase in ["split_load", "split_unweight"]:
		if not bool(context.get("hop_allowed", true)): _land("movement or support takes priority")
		elif _clock >= _land_at: _land("land after unweight")
		elif _clock >= _load_end: phase = "split_unweight"
	if phase == "split_land":
		var read: bool = bool(context.get("direction_ready", false))
		var requested: Vector3 = context.get("direction", Vector3.ZERO)
		requested.y = 0.0
		if _struck and read and requested.length_squared() > 0.0001 and _clock - _land_start >= LAND_TIME:
			direction = requested.normalized()
			phase = "push_off"
			_phase_start = _clock
			reason = "push from landed feet after direction read"
		elif _clock - _land_start > (READ_TIMEOUT if _struck else LAND_TIME):
			phase = "recover"
			_phase_start = _clock
			reason = "settle without an invented direction"
	elif phase == "push_off" and _clock - _phase_start >= PUSH_TIME:
		phase = "recover"
		_phase_start = _clock
	elif phase == "recover" and _clock - _phase_start >= RECOVER_TIME:
		phase = "ready"
		direction = Vector3.ZERO

func _begin(id: int, lead: float) -> void:
	event_id = id
	event_serial += 1
	_start = _clock
	_phase_start = _clock
	_load_end = _clock + minf(LOAD_TIME, maxf(lead, 0.0) * 0.4)
	_land_at = _clock + maxf(lead, 0.0) + LAND_AFTER_STRIKE
	_struck = false
	direction = Vector3.ZERO
	_hop = lead >= MIN_HOP_LEAD and lead <= CUE_WINDOW
	# Scale only with observed preparation time, never incoming ball speed.
	intensity = smoothstep(MIN_HOP_LEAD, 0.20, maxf(lead, 0.0)) if _hop else 0.0
	_height = lerpf(0.010, HOP_HEIGHT, intensity)
	_load_depth = lerpf(0.012, LOAD_DEPTH, intensity)
	phase = "split_load"
	if _hop:
		hop_count += 1
		reason = "visible opponent preparation"
	else:
		skipped_hop_count += 1

func _land(why: String) -> void:
	phase = "split_land"
	_land_start = _clock
	_phase_start = _clock
	landing_serial += 1
	_hop = false
	reason = why

func sample() -> Dictionary:
	var lift := 0.0
	var crouch := 0.0
	var ankle_pitch := 0.0
	if phase == "split_load":
		crouch = _load_depth * sin(PI * clampf((_clock - _start) / maxf(_load_end - _start, 0.001), 0.0, 1.0))
	elif phase == "split_unweight" and _hop:
		var flight: float = clampf((_clock - _load_end) / maxf(_land_at - _load_end, 0.001), 0.0, 1.0)
		lift = _height * sin(PI * flight)
		# Natural gentle toe-down, flattened before the sole makes contact.
		ankle_pitch = lerpf(5.0, 12.0, intensity) * sin(PI * flight) * (1.0 - smoothstep(0.60, 0.95, flight))
	elif phase == "split_land":
		crouch = _load_depth * sin(PI * clampf((_clock - _land_start) / LAND_TIME, 0.0, 1.0))
	elif phase == "push_off":
		crouch = _load_depth * 0.35 * (1.0 - clampf((_clock - _phase_start) / PUSH_TIME, 0.0, 1.0))
	return {"phase": phase, "active": phase not in ["ready", "recover"],
		"foot_lift": maxf(lift, 0.0), "body_lift": maxf(lift, 0.0), "crouch": maxf(crouch, 0.0),
		"ankle_pitch_deg": maxf(ankle_pitch, 0.0), "intensity": intensity, "direction": direction, "event_serial": event_serial, "landing_serial": landing_serial,
		"event_id": event_id, "reason": reason}
