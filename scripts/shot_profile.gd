class_name ShotProfile extends RefCounted


enum Mode{FLAT, TOPSPIN, SLICE}

static func valid_mode(mode: int) -> int:
	return mode if mode >= Mode.FLAT and mode <= Mode.SLICE else Mode.FLAT

static func mode_name(mode: int) -> String:
	return ["Flat", "Topspin", "Slice"][valid_mode(mode)]

static func next_mode(mode: int) -> int:
	return (valid_mode(mode) + 1) % 3

static func create(mode: int, charge: float, shot_type: String = "") -> Dictionary:
	mode = valid_mode(mode)
	charge = clampf(charge, 0.0, 1.0)
	var magnitude: float = 0.0
	if mode == Mode.TOPSPIN:
		magnitude = lerpf(20.0, 34.0, charge)
	elif mode == Mode.SLICE:
		magnitude = - lerpf(16.0, 26.0, charge)

	if shot_type in ["DINK", "DROP", "VOLLEY"]:
		magnitude *= 0.35
	elif shot_type == "SERVE":
		magnitude *= 0.82
	var result: Dictionary = {"mode": mode, "label": mode_name(mode), "charge": charge, 
		"shot_type": shot_type, "topspin_rads": magnitude, "brush_sign": signf(magnitude)}
	result.make_read_only()
	return result

static func angular_velocity(profile: Dictionary, velocity: Vector3, contact_spin: Vector3 = Vector3.ZERO) -> Vector3:
	var travel: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if travel.length_squared() < 0.01:
		return Vector3.ZERO
	var axis: Vector3 = Vector3.UP.cross(travel.normalized())

	var residual: Vector3 = Vector3.UP * clampf(contact_spin.y, -4.0, 4.0)
	return axis * float(profile.get("topspin_rads", 0.0)) + residual
