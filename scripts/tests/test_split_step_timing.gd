extends SceneTree
const Split = preload("res://scripts/split_step_timing.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func run() -> void:
	for rate in [30, 60, 120]:
		for side in [-1.0, 1.0]:
			var s = Split.new()
			var dt: float = 1.0 / rate
			var peak := 0.0
			var phases: Dictionary = {}
			for frame in int(rate * 1.4):
				var time: float = frame * dt
				var context := {"cue_id": 7, "cue_lead": 0.15 - time,
					"direction_ready": time >= 0.45, "direction": Vector3(side, 0, 0)}
				if time >= 0.15: context.strike_id = 7
				s.update(dt, context)
				var sample: Dictionary = s.sample()
				peak = maxf(peak, sample.foot_lift)
				phases[s.phase] = true
				if time < 0.45: check(sample.direction == Vector3.ZERO, "No direction before read %d" % rate)
				if time >= 0.20: check(sample.foot_lift == 0.0, "Lands promptly after strike %d" % rate)
			check(s.event_serial == 1 and s.hop_count == 1 and s.strike_count == 1 and s.landing_serial == 1, "Exactly one split per strike %d" % rate)
			check(peak > 0.015 and peak <= Split.HOP_HEIGHT, "Bounded actual unweight %d" % rate)
			for phase in ["split_load", "split_unweight", "split_land", "push_off", "recover", "ready"]:
				check(phases.has(phase), "Explicit phase %s at %d" % [phase, rate])
			for frame in rate: s.update(dt, {"cue_id": 7, "cue_lead": .1, "strike_id": 7})
			check(s.event_serial == 1, "Held/repeated cue never bounces again")
			s.update(dt, {"cue_id": 8, "cue_lead": .15})
			check(s.event_serial == 2, "Next exchange rearms")
			s.update(dt, {"live": false})
			check(s.sample().foot_lift == 0.0 and s.phase == "ready", "Reset grounds immediately")
			s.update(dt, {"cue_id": 8, "cue_lead": .15})
			check(s.event_serial == 2, "Interrupted cue not replayed")
			for urgent in [{"time_to_contact": .08}, {"own_stroke": true}]:
				var h = Split.new()
				h.update(dt, {"cue_id": 1, "cue_lead": .15})
				for frame in 5: h.update(dt, {})
				h.update(dt, urgent)
				check(h.phase == "ready" and h.sample().foot_lift == 0.0, "Contact overrides split")
			var late = Split.new()
			late.update(dt, {"strike_id": 1})
			check(late.phase == "split_land" and late.hop_count == 0 and late.sample().foot_lift == 0, "Late strike skips hop")
			var early = Split.new()
			early.update(dt, {"cue_id": 2, "cue_lead": .02})
			check(early.hop_count == 0 and early.phase == "ready", "Short cue skips hop")
			for frame in rate * 2: early.update(dt, {"cue_id": 2, "cue_lead": .02})
			check(early.phase == "ready" and early.event_serial == 1, "Missed/cancelled opponent strike settles once")
			var zero = Split.new()
			zero.update(0, {"cue_id": 4, "cue_lead": .15})
			check(zero.event_serial == 0, "Zero-time support refresh cannot restart/tick split")
	var peaks: Array[float] = []
	for lead in [.07, .12, .20]:
		var sample_split = Split.new()
		var lift := 0.0; var pitch := 0.0
		for frame in 160:
			sample_split.update(.0025, {"cue_id": 10, "cue_lead": lead - frame * .0025})
			var sample: Dictionary = sample_split.sample()
			lift = maxf(lift, sample.foot_lift); pitch = maxf(pitch, sample.ankle_pitch_deg)
			check(sample.ankle_pitch_deg >= 0 and sample.ankle_pitch_deg <= 12, "Contextual toe-down remains conservative")
			if sample.foot_lift == 0: check(sample.ankle_pitch_deg == 0, "Grounded pitch is exactly zero")
		peaks.append(lift)
		check(pitch > 0 and sample_split.sample().body_lift == 0 and sample_split.sample().crouch == 0, "Flight pitch present and outputs settle")
	check(peaks[0] < peaks[1] and peaks[1] < peaks[2], "Available preparation time scales intensity")
	var urgent = Split.new()
	urgent.update(.01, {"strike_id": 5, "time_to_contact": .08})
	urgent.update(.01, {"strike_id": 5, "time_to_contact": .08})
	check(urgent.strike_count == 1 and urgent.event_serial == 1 and urgent.hop_count == 0, "Urgent strike counted once without hop")
	print("SPLIT STEP TIMING ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
