extends RefCounted
## Flight quality of a shot as it leaves the paddle (docs/SHOT_QUALITY_PLAN.md, proposal C).
## Read-only: one flight trace per contact. The trail colour, the "flight" note and the AI's
## attack-or-dink choice read the grade.
##
##   clearance  m over the tape where the ball crosses the net (negative: into the net)
##   apex_past  m the top of the flight is past the net (negative: on the hitter's side, so the
##              ball is already falling as it crosses)
##   apex_h     m the top of the flight is above the tape
##   arrive     m over the tape at the receiver's kitchen line (0 when it bounces before it)
##   grade      LOW    just over the tape, apex on the hitter's side: must be dinked or reset
##              LOOSE  can be sped up
##              HIGH   well over the tape or still rising as it crosses: smash it
##              LOB    its own rule: high, apex past the net, landing deep
##              NET    planned into the net
const Flight = preload("res://scripts/ball_flight_predictor.gd")

const LOW := "LOW"
const LOOSE := "LOOSE"
const HIGH := "HIGH"
const LOB := "LOB"
const NET := "NET"

const LOW_CLEARANCE := 0.20      # m: at or under this is a low ball
const HIGH_CLEARANCE := 0.50     # m: over this is smashable
const APEX_NEAR := 0.30          # m past the net the apex may be and still count as "at the net"
const HIGH_ARRIVE := 0.35        # m over the tape at the kitchen line: can be hit down
const LOW_ARRIVE := 0.10         # m over the tape at the kitchen line: has to be lifted
const FAST := 11.0               # m/s: a ball this fast is countered or blocked, not smashed
const LOB_APEX := 1.70           # m over the tape
const LOB_DEPTH := 4.0           # m past the net it lands

static func grade(origin: Vector3, velocity: Vector3, omega: Vector3) -> Dictionary:
	var out: Dictionary = {"grade": "", "clearance": 0.0, "apex_past": 0.0, "apex_h": 0.0, "depth": 0.0, "arrive": 0.0, "speed": 0.0}
	if not velocity.is_finite() or absf(origin.z) < 1e-4: return out
	var flight: Dictionary = Flight.trace(origin, velocity, omega, 3.0, 1, false, true)
	var crossing: Dictionary = flight.net_crossing
	if crossing.is_empty(): return out
	var at: Vector3 = crossing.pos
	var tape: float = Flight.net_clear_y_at(at.x)
	var side: float = signf(origin.z)          # the hitter's side of the net
	var apex: Vector3 = origin
	var arrive: float = INF                    # height over the tape at the receiver's kitchen line, still in the air
	var speed: float = 0.0                     # horizontal speed as it crosses
	for s in flight.samples:
		if int(s.bounces) > 0: break
		var p: Vector3 = s.pos
		if p.y > apex.y: apex = p
		var past: float = -p.z * side
		if past >= 0.0 and speed <= 0.0: speed = Vector2(Vector3(s.vel).x, Vector3(s.vel).z).length()
		if past >= PickleballConstants.NON_VOLLEY_ZONE and arrive == INF: arrive = p.y - tape
	out.clearance = at.y - tape
	out.apex_past = -apex.z * side
	out.apex_h = apex.y - tape
	out.speed = speed
	var landing: Vector3 = flight.first_bounce
	out.depth = -landing.z * side if float(flight.first_bounce_time) > 0.0 else 0.0
	var in_kitchen: bool = arrive == INF       # it bounces before the kitchen line
	out.arrive = 0.0 if in_kitchen else arrive
	if bool(flight.net_hit): out.grade = NET
	elif out.apex_h >= LOB_APEX and out.apex_past > 0.0 and out.depth >= LOB_DEPTH: out.grade = LOB
	elif in_kitchen:
		# A ball that lands in the kitchen bounces about as high as it flew over the net.
		if out.clearance <= LOW_CLEARANCE and out.apex_past <= APEX_NEAR: out.grade = LOW
		else: out.grade = HIGH if out.clearance > HIGH_CLEARANCE else LOOSE
	elif arrive > HIGH_ARRIVE and speed < FAST: out.grade = HIGH      # still well above the net at the kitchen line
	elif out.clearance <= LOW_CLEARANCE and arrive <= LOW_ARRIVE: out.grade = LOW
	else: out.grade = LOOSE
	return out
