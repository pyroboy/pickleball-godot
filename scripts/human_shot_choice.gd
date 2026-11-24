extends RefCounted
## Human tap / hold shot choice (docs/CONTROLS_PLAN.md, step 1).
## Tap (short press) = touch shot placed short; hold = power shot placed deep.
## Which touch / power shot it is comes from the situation: court zone of the hitter
## and contact height. Spin is automatic per shot. The decision is made once at
## release, before the swing copies intent, spin, type and aim target.

## false = today's TOPSPIN / SLICE / DROP buttons (classic controls).
const ENABLED := true
## A press this short is a tap. Was 0.18 s: on the phone only 5 of 57 presses were that quick,
## and 11 more between 0.18 and 0.38 s came out as weak drives (phone logs, 2026-11-24).
const TAP_SECONDS := 0.30
## A flick is a touch shot too: the finger swiped at least FLICK_DEADZONE and the whole press
## took no longer than this. A longer press with a drag is a hold that is being aimed.
const FLICK_SECONDS := 0.45
## Touch shots keep their old gentle power: the hold counts toward it only up to this long.
const TOUCH_CHARGE_SECONDS := 0.18
const KITCHEN_DEPTH := 2.75
const TRANSITION_DEPTH := 5.2
const HIGH_CONTACT := 1.0
## Landing depth into the opponent court (m from the net).
const TOUCH_DEPTH := {"DINK": 1.45, "BLOCK": 1.3, "RESET": 1.55, "DROP": 1.5}
const POWER_DEPTH := {"DRIVE": 5.0, "SPEED_UP": 4.2, "SMASH": 4.3}
const SPIN := {"FLAT": 0, "TOPSPIN": 1, "SLICE": 2}
## Flick aiming on touch shots: a swipe past FLICK_DEADZONE (hit-circle radii) picks the
## lane, sideways = cross court to that side; a long quick flick is a fast dink (deeper,
## flatter). court_right: +1 when screen-right is world +x.
const FLICK_DEADZONE := 0.25
const FLICK_WIDE := Vector2(1.5, 2.3)
const FAST_FLICK_SPEED := 4.0      # radii per second
const FAST_DINK_DEPTH := 1.95

static func flick_target(flick: Dictionary, name: String, base: Vector3, court_right: float) -> Vector3:
	var d: Vector2 = flick.get("dir", Vector2.ZERO)
	if d.length() < FLICK_DEADZONE: return base
	var t := base
	if absf(d.x) >= 0.35:
		t.x = signf(d.x) * court_right * lerpf(FLICK_WIDE.x, FLICK_WIDE.y, clampf((absf(d.x) - 0.35) / 0.65, 0.0, 1.0))
	else:
		t.x = d.x * court_right * 1.2
	var fast: bool = d.length() / maxf(0.05, float(flick.get("seconds", 1.0))) >= FAST_FLICK_SPEED and d.length() >= 0.6
	if fast and name in ["DINK", "RESET"]:
		t.z = signf(t.z) * FAST_DINK_DEPTH
	return t

static func is_tap(charge_ratio: float) -> bool:
	return charge_ratio * PickleballConstants.MAX_SERVE_CHARGE_TIME < TAP_SECONDS

static func zone(depth: float) -> String:
	return "KITCHEN" if depth <= KITCHEN_DEPTH else ("TRANSITION" if depth <= TRANSITION_DEPTH else "BASELINE")

## Shot names for a tap and for a hold, from where the hitter is and how high the
## ball will be met. smash: the contact is a smash (overhead) contact.
## swing_room: how far the stroke's wind-up takes the paddle back (shot_names.swing_room). A
## compact pose in front of the body has no room to load a drive: its power shot is a SPEED_UP.
## "hold_depth" is the landing depth of the power shot (unchanged by the name).
static func names_for(depth: float, contact_height: float, smash: bool, swing_room: float = INF) -> Dictionary:
	var where: String = zone(depth)
	var high: bool = contact_height >= HIGH_CONTACT
	var tap: String = "BLOCK" if high else ({"KITCHEN": "DINK", "TRANSITION": "RESET"}.get(where, "DROP"))
	var placed: String = "SMASH" if smash else ("SPEED_UP" if high and where != "BASELINE" else "DRIVE")
	var hold: String = "SPEED_UP" if placed == "DRIVE" and swing_room < preload("res://scripts/shot_names.gd").SHORT_SWING_ROOM else placed
	return {"tap": tap, "hold": hold, "zone": where, "hold_depth": float(POWER_DEPTH.get(placed, 5.0))}

## The shot for this release. aim: the aim controller's target (only its side-to-side
## position is kept; depth comes from the shot). end_sign: +1 when the opponent court
## is at -z. Returns intent / spin / shot_type / target / name / touch.
## Rally release: hold seconds -> touch shot or power. Power grows with the hold up to
## PickleballConstants.RALLY_FULL_HOLD; a touch shot keeps the old serve-scale charge.
## True when this press was a quick swipe (mobile_controls.last_flick: {dir, seconds}).
static func is_flick(flick: Dictionary) -> bool:
	return Vector2(flick.get("dir", Vector2.ZERO)).length() >= FLICK_DEADZONE and float(flick.get("seconds", INF)) <= FLICK_SECONDS

static func rally_hold(seconds: float, flick: Dictionary = {}) -> Dictionary:
	var touch: bool = seconds < TAP_SECONDS or is_flick(flick)
	var charge: float = clampf(minf(seconds, TOUCH_CHARGE_SECONDS) / PickleballConstants.MAX_SERVE_CHARGE_TIME, 0.0, 1.0) if touch \
		else clampf(seconds / PickleballConstants.RALLY_FULL_HOLD, 0.0, 1.0)
	return {"touch": touch, "charge": charge}

static func choose(charge_ratio: float, depth: float, contact_height: float, smash: bool, aim: Vector3, end_sign: float, touch_override: int = -1, flick: Dictionary = {}, swing_room: float = INF) -> Dictionary:
	var touch: bool = is_tap(charge_ratio) if touch_override < 0 else touch_override == 1
	var names: Dictionary = names_for(depth, contact_height, smash, swing_room)
	var name: String = names.tap if touch else names.hold
	var land: float = float(TOUCH_DEPTH.get(name, 1.5)) if touch else float(names.hold_depth)
	var x: float = clampf(aim.x if aim.is_finite() else 0.0, -2.45, 2.45)
	if touch: x = clampf(x, -2.2, 2.2)
	var target := Vector3(x, aim.y if aim.is_finite() else 0.11, -land * (1.0 if end_sign >= 0.0 else -1.0))
	if touch and not flick.is_empty(): target = flick_target(flick, name, target, 1.0 if end_sign >= 0.0 else -1.0)
	var spin: int = SPIN.FLAT if touch else (SPIN.FLAT if name == "SMASH" else SPIN.TOPSPIN)
	var shot_type: String = ("DINK" if name == "DINK" else "DROP") if touch else ("SMASH" if name == "SMASH" else "GROUNDSTROKE")
	return {"touch": touch, "name": name, "zone": names.zone, "intent": "DROP" if touch else "AUTO",
		"spin": spin, "shot_type": shot_type, "target": target}
