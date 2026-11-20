extends RefCounted
## Every shot name the game shows over the hitter, and how a hit is named.
## Visual only: built from what the shot already carries (ball meta "shot_profile":
## AI tactic / human shot type, and the stroke's motion profile), never read by
## gameplay.

## Display name and colour for every shot the game can tell apart.
const NAMES := {
	"SERVE": ["SERVE", Color("ffffff")],
	"RETURN": ["RETURN", Color("d7e6f2")],
	"THIRD_DROP": ["3RD SHOT DROP", Color("7dff9a")],
	"THIRD_DRIVE": ["3RD SHOT DRIVE", Color("ffd24a")],
	"DROP": ["DROP", Color("7dff9a")],
	"DINK": ["DINK", Color("7dff9a")],
	"RESET": ["RESET", Color("9ff0d0")],
	"DRIVE": ["DRIVE", Color("ffd24a")],
	"SPEED_UP": ["SPEED-UP", Color("ffb347")],
	"VOLLEY": ["VOLLEY", Color("e8f1ff")],
	"PUNCH": ["PUNCH VOLLEY", Color("ffb347")],
	"BLOCK": ["BLOCK", Color("9ad7ff")],
	"COUNTER": ["COUNTER", Color("ff8f5a")],
	"ROLL": ["ROLL VOLLEY", Color("ffb347")],
	"FLICK": ["FLICK", Color("ffb347")],
	"HALF_VOLLEY": ["HALF-VOLLEY", Color("c9b8ff")],
	"JAMMED": ["JAMMED", Color("ffa0a0")],
	"LOB": ["LOB", Color("6ec8ff")],
	"SMASH": ["SMASH", Color("ff5a4a")],
	"ERNE": ["ERNE", Color("ff7ad9")],
	"DIVE": ["DIVE", Color("ff7ad9")],
	"STRETCH": ["STRETCH", Color("c9b8ff")],
	"MISHIT": ["MISHIT", Color("bbbbbb")],
	"GROUNDSTROKE": ["GROUNDSTROKE", Color("e8f1ff")],
}

static func display(key: String) -> String:
	return str(NAMES[key][0]) if NAMES.has(key) else ""

static func color(key: String) -> Color:
	return NAMES[key][1] if NAMES.has(key) else Color.WHITE

## Court zone of the hitter by distance from the net.
const KITCHEN_DEPTH := 2.75      # kitchen line area (NVZ 2.13 m + a step)
const TRANSITION_DEPTH := 5.2    # beyond this: baseline area
const HIGH_CONTACT := 1.0        # m: ball met above the net (net 0.91 m)
const SOFT_SPEED := 8.0          # m/s
const HARD_SPEED := 10.5

static func zone(depth: float) -> String:
	return "KITCHEN" if depth <= KITCHEN_DEPTH else ("TRANSITION" if depth <= TRANSITION_DEPTH else "BASELINE")

## Name a hit from position first, then pace and contact height; the plan and the
## stroke style fill in what position cannot tell (smash, lob, serve, half-volley...).
## profile: the ball's "shot_profile" meta (may be empty); velocity: launch velocity;
## volley: hit before the bounce; rally_hit: 1 = serve, 2 = return...; depth: hitter's
## distance from the net; contact_height: ball height at contact.
static func classify(profile: Dictionary, velocity: Vector3, volley: bool, rally_hit: int, depth: float, contact_height: float) -> String:
	var tactic: String = str(profile.get("tactic", ""))
	var shot_type: String = str(profile.get("shot_type", ""))
	var motion: String = str(profile.get("motion_profile", ""))
	if bool(profile.get("mishit", false)) or tactic == "POPUP": return "MISHIT"
	if shot_type == "SERVE" or tactic == "SERVE": return "SERVE"
	if motion == "EMERGENCY_DIVE": return "DIVE"
	if motion == "LONG_REACH": return "STRETCH"
	if tactic == "ERNE" or motion == "ERNE": return "ERNE"
	var speed: float = velocity.length()
	var horizontal: float = Vector2(velocity.x, velocity.z).length()
	var arc: float = velocity.y / maxf(horizontal, 0.01)
	var high: bool = contact_height >= HIGH_CONTACT
	var where: String = zone(depth)
	# Overhead put away, and lobs: clear from plan or flight.
	if motion == "SMASH" or tactic == "SMASH" or shot_type == "SMASH" or (contact_height >= 1.5 and velocity.y <= -1.0 and speed >= HARD_SPEED): return "SMASH"
	var planned_any: bool = tactic != "" or shot_type not in ["", "GROUNDSTROKE"]
	if motion == "OFFENSIVE_LOB" or tactic == "LOB" or shot_type == "LOB" or (not planned_any and arc > 0.7 and horizontal >= 5.0): return "LOB"
	if rally_hit == 2: return "RETURN"
	var hard: bool = speed >= HARD_SPEED
	# In-between pace: the plan decides (a firm dink is still a dink).
	var soft: bool = speed < SOFT_SPEED or (not hard and tactic in ["DINK", "DROP", "RESET"])
	if rally_hit == 3 and not high:
		if soft: return "THIRD_DROP"
		if hard or tactic == "DRIVE": return "THIRD_DRIVE"
	# Contact styles that already describe position and timing.
	if motion in ["COUNTER", "ROLL", "FLICK", "HALF_VOLLEY", "JAMMED"]: return motion
	if high:
		# Ball met above the net: soft is a block, hard is an attack.
		if soft or motion == "BLOCK": return "BLOCK"
		if hard: return ("PUNCH" if motion == "PUNCH" else "SPEED_UP") if where != "BASELINE" else "DRIVE"
		return "PUNCH" if motion == "PUNCH" else "VOLLEY"
	if motion == "BLOCK": return "BLOCK"
	if soft:
		match where:
			"KITCHEN": return "DINK"
			"TRANSITION": return "RESET"
			_: return "DROP"
	if hard: return "SPEED_UP" if where == "KITCHEN" else "DRIVE"
	if volley: return "PUNCH" if motion == "PUNCH" else "VOLLEY"
	return "GROUNDSTROKE"
