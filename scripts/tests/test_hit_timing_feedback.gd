extends SceneTree

const Timing = preload("res://scripts/ui/hit_timing_feedback.gd")
var checks: = 0
var failures: Array[String] = []
var pulses: Array = []
var pulse_ticks: Array[int] = []
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(message)
func pulse(duration: int, amplitude: float) -> void :
	pulses.append([duration, amplitude])
	pulse_ticks.append(Time.get_ticks_usec())
func state(flight: int, remaining: float, ready: bool = false, reachable: bool = true) -> Dictionary:
	return {"flight_id": flight, "time": remaining + 0.2, "time_until_release": remaining, "release_ready": ready, "current_reachable": reachable, "preparation_only": not reachable, "queued": false}
func run() -> void :
	var timing = Timing.new(pulse)
	var previous: = 2.0
	for remaining in [1.5, 1.0, 0.7, 0.4, 0.1, 0.0]:
		timing.update(state(1, remaining), true, true)
		check(timing.active and timing.ring_fraction <= previous, "consistent countdown expanded")
		previous = timing.ring_fraction
	check(pulses.is_empty(), "countdown alone vibrated without authoritative readiness")
	timing.update(state(1, 0, true, false), true, true)
	check( not timing.ready and timing.caption == "MOVE CLOSER" and pulses.is_empty(), "broad future-only plan gave green/haptic")
	for i in range(120): timing.update(state(1, 0, true), true, true)
	check(timing.ready and timing.ring_fraction == 0 and pulses.size() == 1, "ready window did not deliver exactly one pulse")
	check(pulses[0] == [35, 0.45], "haptic is not short bounded pulse")
	check(timing.flash_strength() > 0.9 and abs(timing._flash_started_usec - pulse_ticks[0]) < 1000, "flash and haptic did not start in the same readiness event")
	timing.update({}, true, true)
	check( not timing.active and not timing.ready and timing.caption == "NO CONTACT", "invalid forecast retained readiness")
	check(timing.flash_strength() == 0.0, "invalid forecast retained flash")
	timing.update(state(1, 0, true), true, true)
	check(pulses.size() == 1, "same flight invalidation/replan rumble repeated")
	check(timing.flash_strength() == 0.0, "same flight invalidation/replan repeated flash")
	timing.clear()
	check( not timing.active and not timing.ready and timing.caption.is_empty(), "lifecycle clear retained feedback")
	timing.update(state(1, 0, true), true, true)
	check(pulses.size() == 1, "pause/repress retriggered same flight")
	timing.update(state(2, 0, true), false, true)
	check( not timing.ready and pulses.size() == 1, "unheld control gave release pulse")
	timing.update(state(2, 0, true), true, false)
	check(timing.ready and pulses.size() == 1, "vibration setting failed to silence ready window")
	check(timing.flash_strength() > 0.9, "disabled vibration also disabled visible readiness flash")
	timing.update(state(2, 0, true), true, true)
	check(pulses.size() == 1, "toggling setting mid-window gave delayed pulse")
	timing.update(state(3, 0, true), true, true)
	check(pulses.size() == 2, "new incoming flight did not rearm")
	var queued: = state(4, 0, true);queued.queued = true
	timing.update(queued, true, true)
	check( not timing.active and not timing.ready and pulses.size() == 2, "committed swing retained release cue")
	for bad in [NAN, INF, -1.0]:
		var invalid: = state(5, 0, true);invalid.time = bad
		timing.update(invalid, true, true)
		check( not timing.active and not timing.ready, "invalid time entered timing ring")
	timing.update(state(6, 0.1), true, true)
	timing.update(state(6, 0.8), true, true)
	check(timing.ring_fraction > 0.4, "replanning suppressed honest later timing")

	timing.update(state(7, 0, true), true, true)
	var flash_start: int = timing._flash_started_usec
	var prior_scale: float = Engine.time_scale
	Engine.time_scale = 0.1
	OS.delay_msec(200)
	timing.update(state(7, 0, true), true, true)
	check(timing.flash_strength() == 0.0 and timing._flash_started_usec == flash_start, "flash did not expire on wall time or restarted while ready")
	Engine.time_scale = prior_scale
	timing.clear()
	check(timing.flash_strength() == 0.0, "cancel/lifecycle clear retained flash")

	var settings = root.get_node("Settings")
	var original: bool = settings.get_value("gameplay.timing_vibration")
	var panel = load("res://scripts/ui/settings_panel.gd").new()
	root.add_child(panel)
	await process_frame
	var toggle: CheckButton = panel.find_child("gameplay_timing_vibration", true, false)
	check(toggle != null and toggle.button_pressed == original, "Gameplay vibration toggle missing or not bound")
	if toggle != null:
		toggle.button_pressed = true
		toggle.button_pressed = false
	check( not settings.get_value("gameplay.timing_vibration"), "UI vibration toggle did not update Settings")
	await process_frame; await process_frame
	var config: = ConfigFile.new()
	check(config.load(settings.CONFIG_PATH) == OK and not config.get_value("gameplay", "timing_vibration", true), "vibration preference was not persisted")
	panel.queue_free()
	settings.set_value("gameplay.timing_vibration", original)
	await process_frame; await process_frame
	for failure in failures: push_error(failure)
	print("HIT TIMING FEEDBACK: %d checks, %d failures; mocked pulses=%d" % [checks, failures.size(), pulses.size()])
	quit(0 if failures.is_empty() else 1)
