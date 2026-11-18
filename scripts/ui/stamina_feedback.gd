extends RefCounted

# Presentation only. Net changes coalesce, so tiny per-frame steps do not flash.
const IDLE_ALPHA := 0.28
const ACTIVE_ALPHA := 0.92
const MEANINGFUL_CHANGE := 0.15 # stamina points, out of 100
const HOLD_SECONDS := 0.70
const ATTACK_SECONDS := 0.12
const FADE_SECONDS := 0.65
var alpha := IDLE_ALPHA
var hold_remaining := 0.0
var sampled_value := 100.0

func reset(value: float) -> void:
	sampled_value = value
	hold_remaining = 0.0
	alpha = IDLE_ALPHA

func advance(value: float, delta: float) -> float:
	if delta <= 0.0: return alpha
	if absf(value - sampled_value) >= MEANINGFUL_CHANGE:
		sampled_value = value
		hold_remaining = HOLD_SECONDS
	else:
		hold_remaining = maxf(0.0, hold_remaining - delta)
	var active := hold_remaining > 0.0
	var target := ACTIVE_ALPHA if active else IDLE_ALPHA
	var duration := ATTACK_SECONDS if active else FADE_SECONDS
	alpha = move_toward(alpha, target, (ACTIVE_ALPHA - IDLE_ALPHA) * delta / duration)
	return alpha
