extends RefCounted
## Human tap / hold shot choice (docs/CONTROLS_PLAN.md, step 1).
## Tap (short press) = touch shot placed short; hold = power shot placed deep.
## Which touch / power shot it is comes from the situation: court zone of the hitter
## and contact height. Spin is automatic per shot. The decision is made once at
## release, before the swing copies intent, spin, type and aim target.

## false = today's TOPSPIN / SLICE / DROP buttons (classic controls).
const ENABLED := true
const TAP_SECONDS := 0.18
const KITCHEN_DEPTH := 2.75
const TRANSITION_DEPTH := 5.2
const HIGH_CONTACT := 1.0
## Landing depth into the opponent court (m from the net).
const TOUCH_DEPTH := {"DINK": 1.45, "BLOCK": 1.3, "RESET": 1.55, "DROP": 1.5}
const POWER_DEPTH := {"DRIVE": 5.0, "SPEED_UP": 4.2, "SMASH": 4.3}
const SPIN := {"FLAT": 0, "TOPSPIN": 1, "SLICE": 2}

static func is_tap(charge_ratio: float) -> bool:
	return charge_ratio * PickleballConstants.MAX_SERVE_CHARGE_TIME < TAP_SECONDS

static func zone(depth: float) -> String:
	return "KITCHEN" if depth <= KITCHEN_DEPTH else ("TRANSITION" if depth <= TRANSITION_DEPTH else "BASELINE")

## Shot names for a tap and for a hold, from where the hitter is and how high the
## ball will be met. smash: the contact is a smash (overhead) contact.
static func names_for(depth: float, contact_height: float, smash: bool) -> Dictionary:
	var where: String = zone(depth)
	var high: bool = contact_height >= HIGH_CONTACT
	var tap: String = "BLOCK" if high else ({"KITCHEN": "DINK", "TRANSITION": "RESET"}.get(where, "DROP"))
	var hold: String = "SMASH" if smash else ("SPEED_UP" if high and where != "BASELINE" else "DRIVE")
	return {"tap": tap, "hold": hold, "zone": where}

## The shot for this release. aim: the aim controller's target (only its side-to-side
## position is kept; depth comes from the shot). end_sign: +1 when the opponent court
## is at -z. Returns intent / spin / shot_type / target / name / touch.
static func choose(charge_ratio: float, depth: float, contact_height: float, smash: bool, aim: Vector3, end_sign: float) -> Dictionary:
	var touch: bool = is_tap(charge_ratio)
	var names: Dictionary = names_for(depth, contact_height, smash)
	var name: String = names.tap if touch else names.hold
	var land: float = float(TOUCH_DEPTH.get(name, 1.5)) if touch else float(POWER_DEPTH.get(name, 5.0))
	var x: float = clampf(aim.x if aim.is_finite() else 0.0, -2.45, 2.45)
	if touch: x = clampf(x, -2.2, 2.2)
	var target := Vector3(x, aim.y if aim.is_finite() else 0.11, -land * (1.0 if end_sign >= 0.0 else -1.0))
	var spin: int = SPIN.FLAT if touch else (SPIN.FLAT if name == "SMASH" else SPIN.TOPSPIN)
	var shot_type: String = ("DINK" if name == "DINK" else "DROP") if touch else ("SMASH" if name == "SMASH" else "GROUNDSTROKE")
	return {"touch": touch, "name": name, "zone": names.zone, "intent": "DROP" if touch else "AUTO",
		"spin": spin, "shot_type": shot_type, "target": target}
