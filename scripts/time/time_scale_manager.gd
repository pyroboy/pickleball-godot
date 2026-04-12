extends Node
## Autoload singleton "TimeScale".
## Single source of truth for Engine.time_scale. Resolves conflicts between:
##   - Reaction hit button slowmo (held via request_slowmo/release)
##   - Hitstop freeze-frames from strong hits (one-shot via request_hitstop)
##   - Pause menu (force_normal on open, release on close)
##
## Priority (high → low):
##   pause_forced  >  slowmo (any active source)  >  hitstop  >  normal (1.0)
##
## Hitstop is IGNORED while any slowmo source is active — slowmo is already dramatic.

var _slowmo_sources: Dictionary = {}  # id (String) -> scale (float), lowest applied
var _pause_forced: bool = false
var _hitstop_active: bool = false
var _hitstop_timer: float = 0.0
var _hitstop_scale: float = 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)

func _process(delta: float) -> void:
	if _hitstop_active:
		# Hitstop uses unscaled real time, so we tick it with a real clock.
		_hitstop_timer -= delta / maxf(Engine.time_scale, 0.001) if Engine.time_scale > 0.0 else delta
		if _hitstop_timer <= 0.0:
			_hitstop_active = false
			_apply()

func request_slowmo(source_id: String, scale: float) -> void:
	_slowmo_sources[source_id] = clampf(scale, 0.05, 1.0)
	_apply()

func release(source_id: String) -> void:
	if _slowmo_sources.has(source_id):
		_slowmo_sources.erase(source_id)
		_apply()

func release_all_slowmo() -> void:
	if not _slowmo_sources.is_empty():
		_slowmo_sources.clear()
		_apply()

## Queue a one-shot hitstop. Ignored if slowmo is active or pause is forced.
## duration is measured in real seconds (not scaled time).
func request_hitstop(duration: float = 0.06, scale: float = 0.05) -> void:
	if _pause_forced:
		return
	if not _slowmo_sources.is_empty():
		return
	_hitstop_active = true
	_hitstop_timer = maxf(0.01, duration)
	_hitstop_scale = clampf(scale, 0.01, 0.9)
	_apply()

## Pause menu calls this on open so the frozen paused state is consistent.
func force_normal() -> void:
	_pause_forced = true
	_hitstop_active = false
	_apply()

func release_forced_normal() -> void:
	_pause_forced = false
	_apply()

func _apply() -> void:
	if _pause_forced:
		Engine.time_scale = 1.0
		return
	if not _slowmo_sources.is_empty():
		var lowest: float = 1.0
		for v in _slowmo_sources.values():
			lowest = minf(lowest, float(v))
		Engine.time_scale = lowest
		return
	if _hitstop_active:
		Engine.time_scale = _hitstop_scale
		return
	Engine.time_scale = 1.0

func is_slowmo_active() -> bool:
	return not _slowmo_sources.is_empty()

func is_hitstop_active() -> bool:
	return _hitstop_active
