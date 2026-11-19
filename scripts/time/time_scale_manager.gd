extends Node











var _realtime_sources: Dictionary = {}
var _slowmo_sources: Dictionary = {}
var _pause_forced: bool = false
var _hitstop_active: bool = false
var _hitstop_until_usec: int = 0   # wall-clock end of the visual-only hit-stop
var _test_fast_forward: float = 0.0

func _ready() -> void :
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)

	if OS.has_environment("GODOT_TEST_FAST"):
		var scale = OS.get_environment("GODOT_TEST_FAST").to_float()
		if scale > 1.0:
			set_test_fast_forward(scale)
			print("[TimeScale] test fast-forward %.0fx" % scale)

func _process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_process(delta)
	PerfMonitor.record("proc.time_scale_manager", Time.get_ticks_usec() - _pt)

func _perf_process(_delta: float) -> void:
	# Hit-stop is visual only (camera/cards hold still); it never touches Engine.time_scale,
	# so physics, AI and input timing are identical with it on or off.
	if _hitstop_active and Time.get_ticks_usec() >= _hitstop_until_usec:
		_hitstop_active = false

func request_slowmo(source_id: String, scale: float) -> void :
	# The imminent-contact aim brake needs a lower, still nonzero floor.
	_slowmo_sources[source_id] = clampf(scale, 0.001 if source_id == "aim_focus" else 0.05, 1.0)
	_apply()

func release(source_id: String) -> void :
	if _slowmo_sources.has(source_id):
		_slowmo_sources.erase(source_id)
		_apply()

func release_all_slowmo() -> void :
	if not _slowmo_sources.is_empty():
		_slowmo_sources.clear()
		_apply()



# Visual-only: other visual code reads visual_hitstop_active() and holds still ~50 ms.
# `scale` is kept for call compatibility and ignored.
func request_hitstop(duration: float = 0.05, _scale: float = 1.0) -> void :
	if _pause_forced or not _realtime_sources.is_empty():
		return
	if not _slowmo_sources.is_empty():
		return
	_hitstop_active = true
	_hitstop_until_usec = Time.get_ticks_usec() + int(clampf(duration, 0.01, 0.1) * 1000000.0)

func cancel_hitstop() -> void :
	_hitstop_active = false
	_hitstop_until_usec = 0

func visual_hitstop_active() -> bool:
	return _hitstop_active and Time.get_ticks_usec() < _hitstop_until_usec

func force_normal() -> void :
	_pause_forced = true
	_hitstop_active = false

func release_forced_normal() -> void :
	_pause_forced = false
	_apply()

func _apply() -> void :
	if _pause_forced or not _realtime_sources.is_empty():
		Engine.time_scale = 1.0
		return
	if _test_fast_forward > 1.0:
		Engine.time_scale = _test_fast_forward
		return
	if not _slowmo_sources.is_empty():
		var lowest: float = 1.0
		for v in _slowmo_sources.values():
			lowest = minf(lowest, float(v))
		Engine.time_scale = lowest
		return
	Engine.time_scale = 1.0

func set_test_fast_forward(scale: float) -> void :
	_test_fast_forward = clampf(scale, 0.0, 20.0)
	_apply()

# Lowest requested slow-motion scale (1.0 = none). Hitstop is not slow motion.
func slowmo_scale() -> float:
	var lowest: float = 1.0
	for v in _slowmo_sources.values(): lowest = minf(lowest, float(v))
	return lowest

func is_slowmo_active() -> bool:
	return not _slowmo_sources.is_empty()

func is_hitstop_active() -> bool:
	return _hitstop_active


func set_realtime_required(source_id: String, required: bool) -> void :
	if required: _realtime_sources[source_id] = true
	else: _realtime_sources.erase(source_id)
	_apply()
