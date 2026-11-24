extends RefCounted
## Bounded game tuning, not measured athlete statistics. The intended solver
## result is perturbed once at genuine contact; no aim reroll or in-court clamp.
const VERSION := "physical-execution-v2-carry"
const Tuning = preload("res://scripts/gameplay_tuning.gd")
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
	var carry: float = float(context.get("carry", 0.0))
	result["carry"] = clampf(carry, 0.0, 1.0) if is_finite(carry) else 0.0
	result["carry_facts"] = clampf(float(context.get("carry_facts", context.get("carry", 0.0))), 0.0, 1.0)
	result["tired"] = clampf(float(context.get("tired", 0.0)), 0.0, 1.0)
	result["power_shot"] = bool(context.get("power_shot", false))
	result["low_drive"] = clampf(float(context.get("low_drive", 0.0)), 0.0, 1.0)
	result["miss_roll"] = float(context.get("miss_roll", 1.0))
	result["miss_dir"] = float(context.get("miss_dir", 0.5))
	result["miss_scale"] = clampf(float(context.get("miss_scale", 1.0)), 0.0, 1.0)
	result["timing_dir"] = float(context.get("timing_dir", 0.0))   # + released early, - late
	result["serve"] = bool(context.get("serve", false))
	return result

## Release timing -> {"part": 0..1 of the mishit score, "word": PERFECT / GOOD / EARLY / LATE,
## "dir": +1 early, -1 late}. `error_s`: seconds from the ideal release (+ early, - late).
static func timing_read(error_s: float, good_early: float, good_late: float, widen: float = 1.0) -> Dictionary:
	if not is_finite(error_s): return {"part": 0.0, "word": "", "dir": 0.0}
	var over: float = (error_s - good_early * widen) if error_s > 0.0 else (-error_s - good_late * widen)
	var word: String = "GOOD"
	# Touch shots (no early limit) are PERFECT from a quarter second early: an early tap only queues.
	var perfect_early: float = 0.25 if good_early >= 10.0 else Tuning.TIMING_PERFECT_EARLY
	if error_s <= perfect_early * widen and error_s >= -Tuning.TIMING_PERFECT_LATE * widen: word = "PERFECT"
	elif over > 0.0: word = "EARLY" if error_s > 0.0 else "LATE"
	return {"part": clampf(over / (Tuning.TIMING_FULL_EARLY if error_s > 0.0 else Tuning.TIMING_FULL), 0.0, 1.0), "word": word, "dir": signf(error_s)}

## The mishit score and its cause (docs/SHOT_QUALITY_PLAN.md). Every part is something the
## hitter controls and is shown. Returns {"score", "cause" (stamp word or ""), "parts"}.
static func mishit(c: Dictionary) -> Dictionary:
	var none: Dictionary = {"score": 0.0, "cause": "", "parts": [0.0, 0.0, 0.0, 0.0]}
	if not Tuning.MISHIT_ON or bool(c.get("perfect", false)) or bool(c.get("serve", false)): return none
	var timing: float = Tuning.MISHIT_W_TIMING * clampf(float(c.get("timing", 0.0)), 0.0, 1.0)
	var unset: float = Tuning.MISHIT_W_UNSET * clampf((float(c.get("balance", 0.0)) - Tuning.UNSET_FROM) / (Tuning.UNSET_FULL - Tuning.UNSET_FROM), 0.0, 1.0)
	var risk: float = Tuning.MISHIT_W_RISK * clampf(float(c.get("low_drive", 0.0)), 0.0, 1.0)
	var stamina: float = Tuning.MISHIT_W_STAMINA * clampf(float(c.get("tired", 0.0)), 0.0, 1.0)
	var parts: Array = [timing, unset, risk, stamina]
	var words: Array = ["EARLY" if float(c.get("timing_dir", 0.0)) > 0.0 else "LATE", "MOVING", "TOO LOW TO DRIVE", "LOW STAMINA"]
	var top: int = 0
	for i in 4:
		if float(parts[i]) > float(parts[top]): top = i
	return {"score": clampf(timing + unset + risk + stamina, 0.0, 1.0), "cause": str(words[top]) if float(parts[top]) >= Tuning.MISHIT_SHOW else "", "parts": parts}

## How hard the contact was, from ball / movement facts and input timing only (never
## the pose). Forced vs unforced errors and the large-miss gate both read this.
static func pressure(c: Dictionary) -> float:
	return clampf(float(c.get("carry_facts", c.get("carry", 0.0))) + 0.5 * float(c.get("timing", 0.0)), 0.0, 1.0)

static func large_miss_chance(c: Dictionary) -> float:
	if not Tuning.MISS_ON or bool(c.get("perfect", false)): return 0.0
	# Pressure plus the hitter's own risk of driving hard from below the tape.
	var p: float = clampf(pressure(c) + Tuning.LOW_DRIVE_RISK * float(c.get("low_drive", 0.0)), 0.0, 1.0)
	if p < Tuning.FORCED_LINE: return 0.0     # clean contact: never a large miss
	var t: float = clampf((p - Tuning.FORCED_LINE) / (1.0 - Tuning.FORCED_LINE), 0.0, 1.0)
	return (lerpf(Tuning.MISS_CHANCE_AT_LINE, Tuning.MISS_CHANCE_MAX, t) + Tuning.MISS_TIRED_BONUS * float(c.get("tired", 0.0))) * float(c.get("miss_scale", 1.0))

static func envelope(context: Dictionary) -> Dictionary:
	var c := normalized(context)
	# Independent nonnegative contributions make every difficulty factor
	# monotonic while retaining small clean-contact variation.
	var difficulty: float = 0.24 * c.timing + 0.24 * c.off_center + 0.20 * c.balance + 0.15 * c.extension + 0.12 * c.pace + 0.05 * c.power
	# Wider error only from visible causes (the AI's random loose roll floats, not errs).
	difficulty += Tuning.CARRY_ERROR_WEIGHT * float(c.get("carry_facts", c.carry))
	var gain: float = c.skill_scale
	if bool(c.get("power_shot", false)): gain *= 1.0 + Tuning.STAMINA_POWER_ERROR * float(c.get("tired", 0.0))
	return {"difficulty": difficulty, "yaw_deg": minf(MAX_YAW_DEG, (0.25 + 2.90 * difficulty) * gain),
		"pitch_deg": minf(MAX_PITCH_DEG, (0.18 + 2.30 * difficulty) * gain),
		"speed_fraction": minf(MAX_SPEED_FRACTION, (0.008 + 0.090 * difficulty) * gain),
		"spin_fraction": minf(MAX_SPIN_FRACTION, (0.015 + 0.11 * difficulty) * gain)}

static func carry_float(velocity: Vector3, carry: float) -> Vector3:
	if carry <= 0.0 or (Tuning.CARRY_FLOAT_VY <= 0.0 and Tuning.CARRY_SHORTEN <= 0.0 and Tuning.CARRY_LENGTHEN <= 0.0): return velocity
	var hard: bool = velocity.length() >= Tuning.CARRY_HARD_SPEED
	var lift: float = Tuning.CARRY_FLOAT_VY * carry
	if hard:
		var horizontal := Vector3(velocity.x, 0.0, velocity.z) * (1.0 - Tuning.CARRY_SHORTEN * carry)
		return horizontal + Vector3.UP * (velocity.y + lift)
	# Soft: higher and deeper, not wider. The lift makes the flight longer, so the
	# sideways speed shrinks by about the same ratio and the ball keeps its line
	# (a wide cross-court dink must not sail past the sideline).
	var time_ratio: float = maxf(velocity.y, 1.0) / maxf(velocity.y + lift, 1.0)
	return Vector3(velocity.x * time_ratio, velocity.y + lift, velocity.z * (1.0 + Tuning.CARRY_LENGTHEN * carry))

static func _centered(rng: RandomNumberGenerator) -> float:
	# Symmetric triangular density: zero mean, bounded [-1,1], variance1/6.
	return rng.randf() - rng.randf()

static func apply(velocity: Vector3, omega: Vector3, context: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var c := normalized(context)
	var bound := envelope(c)
	var result := {"velocity": velocity, "omega": omega, "context": c, "envelope": bound,
		"yaw_deg": 0.0, "pitch_deg": 0.0, "speed_fraction": 0.0, "spin_fraction": 0.0,
		"sampled": false, "version": VERSION}
	# The reply floats (no roll): higher and shorter after a hard incoming ball.
	# "Perfect training" keeps it, like the human's own pop-ups (plan change 3).
	# Tired power shots come off slower (shorter, sitting up).
	if bool(c.get("power_shot", false)) and float(c.get("tired", 0.0)) > 0.0:
		var keep: float = 1.0 - Tuning.TIRED_POWER_LOSS * float(c.tired)
		velocity = Vector3(velocity.x * keep, velocity.y, velocity.z * keep)
	var unfloated: Vector3 = velocity
	velocity = carry_float(velocity, c.carry)
	result.velocity = velocity
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
	# Mishit from skill (no dice): below MISHIT_LARGE the float above is all of it; from there the
	# error is large and goes the way of its cause.
	var m: Dictionary = mishit(c)
	result["mishit"] = m.score
	result["mishit_parts"] = m.parts
	result["miss_cause"] = m.cause
	result["large_miss"] = false
	result["low_lob"] = false
	if float(m.score) >= Tuning.MISHIT_LARGE:
		var big: float = lerpf(0.33, 1.0, clampf((float(m.score) - Tuning.MISHIT_LARGE) / (1.0 - Tuning.MISHIT_LARGE), 0.0, 1.0))
		var soft: bool = unfloated.length() < Tuning.CARRY_HARD_SPEED
		var side: float = 1.0 if c.miss_dir < 0.5 else -1.0
		var base: Vector3 = rotation * unfloated * (1.0 + speed)   # a miss into the net replaces the float
		result["large_miss"] = true
		if soft and big < 0.8:
			# A soft shot pops up: higher and deeper, there to be attacked. Only a very large one nets.
			result.velocity = rotation * carry_float(unfloated, 1.0) * (1.0 + speed) + Vector3.UP * Tuning.MISHIT_POP_VY * big
		elif m.cause == "LATE":
			# Late: the face is still open. Up and off line: long or wide.
			result.velocity = Basis(Vector3.UP, deg_to_rad(side * Tuning.MISHIT_YAW_DEG * big)) * Basis(pitch_axis, deg_to_rad(Tuning.MISHIT_PITCH_UP_DEG * big)) * result.velocity
		elif m.cause == "MOVING":
			# No base under the swing: slow and up, a short pop-up.
			var weak: Vector3 = base * (1.0 - Tuning.MISHIT_SPEED_LOSS * big)
			result.velocity = Vector3(weak.x, maxf(weak.y, 0.0) + Tuning.MISHIT_POP_VY * big, weak.z)
		else:
			# Too low to drive: LOW_LOB_CHANCE of the time the ball is scooped up as a lob that clears
			# the net (the roll is the hitter's per-ball miss draw); the rest go into the net.
			var lob: Vector3 = Vector3.ZERO
			if m.cause == "TOO LOW TO DRIVE" and c.miss_dir < Tuning.LOW_LOB_CHANCE and context.get("origin") is Vector3:
				lob = low_lob(context.origin, base, result.omega * Tuning.LOW_LOB_SPIN)
			result["low_lob"] = lob != Vector3.ZERO
			if lob != Vector3.ZERO: result.velocity = lob; result.omega *= Tuning.LOW_LOB_SPIN
			# Early, too low to drive, or no legs left: down into the net.
			else: result.velocity = Basis(pitch_axis, deg_to_rad(-Tuning.MISHIT_PITCH_DOWN_DEG * big)) * base * (1.0 - 0.5 * Tuning.MISHIT_SPEED_LOSS * big)
	result.yaw_deg = yaw; result.pitch_deg = pitch
	result.speed_fraction = speed; result.spin_fraction = spin
	result.sampled = true
	return result

## The lob a too-low drive turns into: along the planned line, about LOW_LOB_CLEAR over the tape,
## landing about LOW_LOB_DEPTH past the net and inside the sidelines. A drag-free first guess,
## then corrections against the real flight; the closest arc that clears the net by half the
## aim or more and lands in court is used. ZERO when there is none.
static func low_lob(origin: Vector3, planned: Vector3, omega: Vector3) -> Vector3:
	var Flight = preload("res://scripts/ball_flight_predictor.gd")
	var side: float = signf(origin.z)
	if side == 0.0 or planned.z * side >= -0.01: return Vector3.ZERO
	var travel: float = (absf(origin.z) + Tuning.LOW_LOB_DEPTH) / absf(planned.z)
	var half: float = PickleballConstants.COURT_WIDTH * 0.5 - 0.8
	var floor_y: float = PickleballConstants.FLOOR_Y + 0.0375
	var flat := Vector3(clampf(origin.x + planned.x * travel, -half, half) - origin.x, 0.0, -Tuning.LOW_LOB_DEPTH * side - origin.z)
	var reach: float = flat.length()
	var dir: Vector3 = flat / reach
	var to_net: float = reach * absf(origin.z) / absf(flat.z)
	var rise_net: float = Flight.net_clear_y_at(origin.x + dir.x * to_net) + Tuning.LOW_LOB_CLEAR - origin.y
	# y(x) = origin.y + a x - b x^2 through the net point and the landing.
	var b: float = (reach * rise_net / to_net - (floor_y - origin.y)) / (reach * reach - to_net * reach)
	if b <= 1e-4: return Vector3.ZERO
	var speed: float = sqrt(preload("res://scripts/ball.gd").get_effective_gravity() / (2.0 * b))
	var vy: float = (rise_net + b * to_net * to_net) / to_net * speed
	var best: Vector3 = Vector3.ZERO
	var best_err: float = INF
	for step in 8:
		var velocity: Vector3 = dir * speed + Vector3.UP * vy
		var flight: Dictionary = Flight.trace(origin, velocity, omega, 4.0, 1, false, true)
		if flight.net_crossing.is_empty():
			vy += 0.6; speed *= 1.1      # fell short of the net: more of both
			continue
		var at: Vector3 = flight.net_crossing.pos
		var clear: float = at.y - Flight.net_clear_y_at(at.x)
		var got: float = Vector2(Vector3(flight.first_bounce).x - origin.x, Vector3(flight.first_bounce).z - origin.z).length() if float(flight.first_bounce_time) > 0.0 else reach * 1.3
		var depth: float = got * absf(flat.z) / reach - absf(origin.z)
		var err: float = absf(clear - Tuning.LOW_LOB_CLEAR) + absf(got - reach)
		if not bool(flight.net_hit) and clear >= 0.5 * Tuning.LOW_LOB_CLEAR and depth >= 2.0 and depth <= PickleballConstants.BASELINE_Z - 0.4 and err < best_err:
			best = velocity; best_err = err
			if err < 0.15: break
		# Height at the net is set by the vertical speed, the landing by the forward speed.
		# Slower forward takes longer to the net, so the vertical speed is redone from the new time.
		var t_net: float = maxf(float(flight.net_crossing.time), 0.05)
		var scale: float = clampf(reach / maxf(got, 0.05), 0.8, 1.25)
		speed *= scale
		vy += (Tuning.LOW_LOB_CLEAR - clear) / t_net * 0.8 + 0.5 * preload("res://scripts/ball.gd").get_effective_gravity() * t_net * (1.0 / scale - 1.0) * 0.5
	return best

static func estimated_landing_axes(distance: float, context: Dictionary) -> Vector2:
	# Stable visual estimate only, not a promise or a containment certificate.
	# Flight arc, Magnus and net contacts can produce larger or nonlinear error.
	var c := normalized(context)
	if c.perfect: return Vector2(0.10, 0.10)
	var e := envelope(c)
	var span := clampf(distance, 0.0, 20.0)
	return Vector2(0.10 + span * tan(deg_to_rad(e.yaw_deg)), 0.10 + span * (2.0 * e.speed_fraction + tan(deg_to_rad(e.pitch_deg))))
