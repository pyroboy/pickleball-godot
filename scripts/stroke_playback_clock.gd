extends RefCounted
## Shared gameplay time contract. Never changes Engine.time_scale.
const Grip = preload("res://scripts/grip_transition.gd")
const ReadyMotion = preload("res://scripts/incoming_ready_motion.gd")
const Ramp = preload("res://scripts/stroke_speed_ramp.gd")
static func transition_for_curve(curve: int) -> Tween.TransitionType:
	return Tween.TRANS_QUAD if curve == 1 else Tween.TRANS_SINE if curve == 2 else Tween.TRANS_EXPO
static func ease_for_curve(curve: int) -> Tween.EaseType:
	return Tween.EASE_IN_OUT if curve == 2 else Tween.EASE_OUT
static func recovery_duration(def: PostureDefinition, finish: PostureDefinition, ready: PostureDefinition) -> float:
	return maxf(def.ft_duration_settle, ReadyMotion.GRIP_TRANSITION_TIME) if Grip.supports_both_joined(finish, ready) else maxf(0.01, def.ft_duration_settle)
static func strike_duration(def: PostureDefinition) -> float:
	return maxf(0.01, def.ft_duration_strike)
static func sweep_duration(def: PostureDefinition) -> float:
	return maxf(0.01, def.ft_duration_sweep)
static func hold_duration(def: PostureDefinition) -> float:
	return maxf(0.0, def.ft_duration_hold)
static func durations(def: PostureDefinition, finish: PostureDefinition, ready: PostureDefinition) -> Dictionary:
	var strike := strike_duration(def)
	var sweep := sweep_duration(def)
	var hold := hold_duration(def)
	var recovery := recovery_duration(def, finish, ready)
	return {"strike": strike, "sweep": sweep, "hold": hold, "recovery": recovery, "stroke": strike+sweep, "total": strike+sweep+hold+recovery}
static func state(def: PostureDefinition, seconds: float, finish: PostureDefinition, ready: PostureDefinition) -> Dictionary:
	var d := durations(def, finish, ready)
	var t := clampf(seconds, 0.0, d.total)
	var phase := "Strike"
	var progress := 0.0
	var recovery := 0.0
	if t <= d.strike:
		progress = 0.5 * Ramp.normalized(def, Ramp.STRIKE, t / d.strike) if Ramp.custom(def, Ramp.STRIKE) else Tween.interpolate_value(0.0, 0.5, t, d.strike, transition_for_curve(def.ft_ease_curve), ease_for_curve(def.ft_ease_curve))
	elif t <= d.stroke:
		phase = "Sweep"
		progress = 0.5 + 0.5 * Ramp.normalized(def, Ramp.FINISH, (t-d.strike) / d.sweep) if Ramp.custom(def, Ramp.FINISH) else Tween.interpolate_value(0.5, 0.5, t-d.strike, d.sweep, transition_for_curve(def.ft_ease_curve), ease_for_curve(def.ft_ease_curve))
	else:
		progress = 1.0
		phase = "Hold"
		if t > d.stroke+d.hold:
			phase = "Ready" if t >= d.total else "Recovery"
			var joined := Grip.supports_both_joined(finish, ready)
			recovery = Tween.interpolate_value(0.0, 1.0, t-d.stroke-d.hold, d.recovery, Tween.TRANS_LINEAR if joined else Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	return {"phase": phase, "progress": progress, "recovery": recovery, "elapsed": t, "duration": d.total}
