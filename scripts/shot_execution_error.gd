extends RefCounted
## Bounded game tuning, not measured athlete statistics. The intended solver
## result is perturbed once at genuine contact; no aim reroll or in-court clamp.
const VERSION := "physical-execution-v1"
const MAX_YAW_DEG := 4.4
const MAX_PITCH_DEG := 3.5
const MAX_SPEED_FRACTION := 0.14
const MAX_SPIN_FRACTION := 0.18

static func normalized(context: Dictionary) -> Dictionary:
	var result := {}
	for key in ["timing", "off_center", "balance", "extension", "pace", "power"]:
		var value: float = float(context.get(key, 0.0))
		result[key] = clampf(value, 0.0, 1.0) if is_finite(value) else 1.0
	var skill: float = float(context.get("skill_scale", 1.0))
	result["skill_scale"] = clampf(skill, 0.6, 1.4) if is_finite(skill) else 1.0
	result["perfect"] = bool(context.get("perfect", false))
	return result

static func envelope(context: Dictionary) -> Dictionary:
	var c := normalized(context)
	# Independent nonnegative contributions make every difficulty factor
	# monotonic while retaining small clean-contact variation.
	var difficulty: float = 0.24 * c.timing + 0.24 * c.off_center + 0.20 * c.balance + 0.15 * c.extension + 0.12 * c.pace + 0.05 * c.power
	var gain: float = c.skill_scale
	return {"difficulty": difficulty, "yaw_deg": minf(MAX_YAW_DEG, (0.25 + 2.90 * difficulty) * gain),
		"pitch_deg": minf(MAX_PITCH_DEG, (0.18 + 2.30 * difficulty) * gain),
		"speed_fraction": minf(MAX_SPEED_FRACTION, (0.008 + 0.090 * difficulty) * gain),
		"spin_fraction": minf(MAX_SPIN_FRACTION, (0.015 + 0.11 * difficulty) * gain)}

static func _centered(rng: RandomNumberGenerator) -> float:
	# Symmetric triangular density: zero mean, bounded [-1,1], variance1/6.
	return rng.randf() - rng.randf()

static func apply(velocity: Vector3, omega: Vector3, context: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var c := normalized(context)
	var bound := envelope(c)
	var result := {"velocity": velocity, "omega": omega, "context": c, "envelope": bound,
		"yaw_deg": 0.0, "pitch_deg": 0.0, "speed_fraction": 0.0, "spin_fraction": 0.0,
		"sampled": false, "version": VERSION}
	if c.perfect: return result
	var yaw: float = _centered(rng) * bound.yaw_deg
	var pitch: float = _centered(rng) * bound.pitch_deg
	var speed: float = _centered(rng) * bound.speed_fraction
	var spin: float = _centered(rng) * bound.spin_fraction
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var pitch_axis: Vector3 = horizontal.normalized().cross(Vector3.UP) if horizontal.length_squared() > 0.0000001 else Vector3.RIGHT
	var rotation := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(pitch_axis, deg_to_rad(pitch))
	result.velocity = rotation * velocity * (1.0 + speed)
	result.omega = rotation * omega * (1.0 + spin)
	result.yaw_deg = yaw; result.pitch_deg = pitch
	result.speed_fraction = speed; result.spin_fraction = spin
	result.sampled = true
	return result

static func estimated_landing_axes(distance: float, context: Dictionary) -> Vector2:
	# Stable visual estimate only, not a promise or a containment certificate.
	# Flight arc, Magnus and net contacts can produce larger or nonlinear error.
	var c := normalized(context)
	if c.perfect: return Vector2(0.10, 0.10)
	var e := envelope(c)
	var span := clampf(distance, 0.0, 20.0)
	return Vector2(0.10 + span * tan(deg_to_rad(e.yaw_deg)), 0.10 + span * (2.0 * e.speed_fraction + tan(deg_to_rad(e.pitch_deg))))
