extends RefCounted


const COUNTDOWN_HORIZON: = 1.5
const PULSE_DURATION_MS: = 35
const PULSE_AMPLITUDE: = 0.45
const FLASH_DURATION_USEC: = 180000
var active: = false
var ready: = false
var preparation_only: = false
var ring_fraction: = 1.0
var caption: = ""
var flight_id: = -1
var _pulsed_flight: = -1
var _flash_started_usec: = -1
var _vibration_dispatch: Callable

func _init(dispatch: Callable = Callable()) -> void :
	_vibration_dispatch = dispatch if dispatch.is_valid() else _vibrate_device

func clear() -> void :

	active = false
	ready = false
	preparation_only = false
	ring_fraction = 1.0
	caption = ""
	flight_id = -1
	_flash_started_usec = -1

func update(state: Dictionary, held: bool, vibration_enabled: bool) -> void :
	var previous_flash: int = _flash_started_usec
	clear()
	flight_id = int(state.get("flight_id", -1))
	var time: float = float(state.get("time", -1.0))
	if flight_id < 0 or not is_finite(time) or time < 0.0:
		caption = "NO CONTACT" if held else ""
		return
	if bool(state.get("queued", false)): return
	active = true
	preparation_only = bool(state.get("preparation_only", false)) or not bool(state.get("current_reachable", false))
	var until_release: float = float(state.get("time_until_release", time))
	if not is_finite(until_release): until_release = time
	ring_fraction = clampf(until_release / COUNTDOWN_HORIZON, 0.0, 1.0)
	ready = held and not preparation_only and bool(state.get("release_ready", false))
	if ready:
		ring_fraction = 0.0
		caption = "RELEASE"
		_flash_started_usec = previous_flash
		if _pulsed_flight != flight_id:
			_pulsed_flight = flight_id

			_flash_started_usec = Time.get_ticks_usec()
			if vibration_enabled: _vibration_dispatch.call(PULSE_DURATION_MS, PULSE_AMPLITUDE)
	else:
		caption = "MOVE CLOSER" if preparation_only and held else "HOLD" if held else "HOLD HIT"

func flash_strength() -> float:
	if not active or not ready or _flash_started_usec < 0: return 0.0

	return clampf(1.0 - float(Time.get_ticks_usec() - _flash_started_usec) / float(FLASH_DURATION_USEC), 0.0, 1.0)

func _vibrate_device(duration_ms: int, amplitude: float) -> void :


	if OS.has_feature("mobile"): Input.vibrate_handheld(duration_ms, amplitude)
