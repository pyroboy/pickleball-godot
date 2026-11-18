extends RefCounted
## Deliberate, one-shot athletic setup. Ball gaze is never an input to this
## state: only the already selected, reachable incoming stroke can request it.
const STABLE_CHOICE_SECONDS := 0.10
const MIN_SETUP_SECONDS := 0.55
const MAX_SETUP_SECONDS := 2.20
var state := "idle"
var facing_deg := 0.0
var family := -1
var flight_id := -1
var body_alignment_active := false
var offset := Vector3.ZERO
var lead_side := 1
var stance_kind := "open"
var profile: Dictionary = {}
var entered_serial := 0
var _candidate_flight := -1
var _candidate_family := -1
var _candidate_seconds := 0.0
var _blocked_flight := -1
var _was_authored := false

func reset() -> void:
	state = "idle"; facing_deg = 0.0; family = -1; flight_id = -1
	body_alignment_active = false; offset = Vector3.ZERO; profile = {}; stance_kind = "open"
	_candidate_flight = -1; _candidate_family = -1; _candidate_seconds = 0.0; _blocked_flight = -1; _was_authored = false

func active() -> bool:
	return state != "idle"

func update(delta: float, candidate: Dictionary, lifecycle: String, moving: bool, authored_swing: bool) -> void:
	var fresh_intent := authored_swing and not _was_authored
	_was_authored = authored_swing
	if fresh_intent and state == "idle": _blocked_flight = -1
	body_alignment_active = false
	if lifecycle == "reset": reset(); return
	if state in ["setup", "hold"]:
		if lifecycle == "cancel": _blocked_flight = flight_id
		if moving or lifecycle in ["cancel", "recover", "invalid"]:
			state = "recover"; facing_deg = 0.0
		elif not candidate.is_empty() and int(candidate.flight) != flight_id and lifecycle != "finish":
			state = "recover"; facing_deg = 0.0
		body_alignment_active = state in ["setup", "hold"] and not authored_swing
		return
	if state == "recover": return
	if moving or lifecycle != "receive" or candidate.is_empty():
		_candidate_seconds = 0.0; return
	var contact_time: float = candidate.time
	if contact_time < MIN_SETUP_SECONDS or contact_time > MAX_SETUP_SECONDS or int(candidate.flight) == _blocked_flight:
		_candidate_seconds = 0.0; return
	if _candidate_flight != int(candidate.flight) or _candidate_family != int(candidate.family):
		_candidate_flight = int(candidate.flight); _candidate_family = int(candidate.family); _candidate_seconds = 0.0
	_candidate_seconds += maxf(delta, 0.0)
	if _candidate_seconds < STABLE_CHOICE_SECONDS: return
	state = "setup"; flight_id = int(candidate.flight); family = int(candidate.family)
	profile = candidate.get("profile", {"kind": "open", "facing": 0.0, "right": Vector3(0.33, 0, 0), "left": Vector3(-0.33, 0, 0), "right_yaw": 0.0, "left_yaw": 0.0, "right_pitch": 0.0, "left_pitch": 0.0, "crouch": 0.18, "lead": 1}).duplicate(true)
	stance_kind = profile.kind
	facing_deg = profile.facing
	lead_side = profile.lead
	offset = candidate.get("offset", Vector3.ZERO)
	entered_serial += 1
	body_alignment_active = not authored_swing

func mark_settled(allow_recovery_finish: bool = true) -> void:
	if state == "setup": state = "hold"
	elif state == "recover" and allow_recovery_finish:
		state = "idle"; facing_deg = 0.0; family = -1; flight_id = -1
		_candidate_seconds = 0.0

static func profile_from(pose) -> Dictionary:
	var right_leads: bool = pose.lead_foot == 0
	var right: Vector3 = Vector3(pose.stance_width * 0.5, 0, pose.front_foot_forward if right_leads else pose.back_foot_back) + pose.right_foot_offset
	var left: Vector3 = Vector3(-pose.stance_width * 0.5, 0, pose.back_foot_back if right_leads else pose.front_foot_forward) + pose.left_foot_offset
	right.y = 0.0; left.y = 0.0
	var facing: float = wrapf(pose.body_yaw_deg + pose.hip_yaw_deg, -180.0, 180.0)
	var kind := "authored"
	if absf(facing) < 15.0 and absf(right.z - left.z) < 0.12: kind = "open"
	elif absf(facing) >= 35.0 and absf(right.z - left.z) >= 0.25: kind = "closed"
	return {"kind": kind, "facing": facing, "right": right, "left": left, "right_yaw": pose.right_foot_yaw_deg, "left_yaw": pose.left_foot_yaw_deg, "right_pitch": pose.right_foot_pitch_deg, "left_pitch": pose.left_foot_pitch_deg, "crouch": pose.crouch_amount, "lead": pose.lead_foot}
