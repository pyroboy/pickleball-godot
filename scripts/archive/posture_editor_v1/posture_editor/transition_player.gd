extends Node

## Plays through charge→contact→follow-through→settle sequence

enum Phase { CHARGE, CONTACT, FOLLOW_THROUGH, SETTLE, READY }

signal phase_changed(new_phase: Phase)
signal playback_started()
signal playback_stopped()
signal playback_finished()

# Phase durations (in seconds at normal time scale)
var phase_durations := {
	Phase.CHARGE: 0.5,
	Phase.CONTACT: 0.1,
	Phase.FOLLOW_THROUGH: 0.3,
	Phase.SETTLE: 0.2
}

var _current_phase: Phase = Phase.READY
var _phase_time: float = 0.0
var _total_duration: float = 1.1  # Sum of all phases
var _playing: bool = false
var _loop: bool = false
var _speed: float = 1.0

# Posture definitions for each phase
var _ready_def = null
var _charge_def = null
var _contact_def = null
var _follow_through_defs: Array = []

# Player reference
var _player: PlayerController = null
var _restore_posture_id: int = -1

func setup(player, ready_def, 
		   charge_def, contact_def,
		   ft_defs: Array) -> void:
	_player = player
	_ready_def = ready_def if ready_def != null else contact_def
	_charge_def = charge_def if charge_def != null else contact_def
	_contact_def = contact_def
	_follow_through_defs = ft_defs

	if _contact_def != null:
		phase_durations[Phase.CONTACT] = maxf(0.04, _contact_def.ft_duration_strike)
		phase_durations[Phase.FOLLOW_THROUGH] = maxf(0.08, _contact_def.ft_duration_sweep)
		phase_durations[Phase.SETTLE] = maxf(0.06, _contact_def.ft_duration_settle + _contact_def.ft_duration_hold)
	
	# Recalculate total duration
	_total_duration = 0.0
	for duration in phase_durations.values():
		_total_duration += duration

func play(from_start: bool = true) -> void:
	if from_start:
		_current_phase = Phase.CHARGE
		_phase_time = 0.0
	if _player and _player.posture:
		_restore_posture_id = _player.posture.paddle_posture
	
	_playing = true
	playback_started.emit()
	set_process(true)

func pause() -> void:
	_playing = false
	set_process(false)

func stop() -> void:
	_playing = false
	_current_phase = Phase.READY
	_phase_time = 0.0
	set_process(false)
	playback_stopped.emit()
	_restore_live_posture()

func seek(normalized_time: float) -> void:
	# normalized_time: 0.0 to 1.0 across all phases
	var t: float = clamp(normalized_time, 0.0, 1.0) * _total_duration
	
	# Find which phase we're in
	var accumulated := 0.0
	for phase in [Phase.CHARGE, Phase.CONTACT, Phase.FOLLOW_THROUGH, Phase.SETTLE]:
		var duration: float = phase_durations[phase]
		if t <= accumulated + duration:
			_current_phase = phase
			_phase_time = t - accumulated
			_apply_phase_pose()
			return
		accumulated += duration

func set_loop(enabled: bool) -> void:
	_loop = enabled

func set_speed(speed: float) -> void:
	_speed = speed

func get_current_phase() -> Phase:
	return _current_phase

func get_phase_progress() -> float:
	# Returns 0.0-1.0 progress within current phase
	var duration: float = phase_durations[_current_phase]
	if duration <= 0:
		return 1.0
	return clamp(_phase_time / duration, 0.0, 1.0)

func get_total_progress() -> float:
	# Returns 0.0-1.0 progress across entire sequence
	var accumulated := 0.0
	for phase in [Phase.CHARGE, Phase.CONTACT, Phase.FOLLOW_THROUGH, Phase.SETTLE]:
		if phase == _current_phase:
			return (accumulated + _phase_time) / _total_duration
		accumulated += phase_durations[phase]
	return 1.0

func get_total_duration() -> float:
	return _total_duration

func is_playing() -> bool:
	return _playing

func _ready() -> void:
	set_process(false)

func _process(delta: float) -> void:
	if not _playing:
		return
	
	_phase_time += delta * _speed
	
	# Check if phase is complete
	var current_duration: float = phase_durations[_current_phase]
	if _phase_time >= current_duration:
		_advance_phase()
	else:
		_apply_phase_pose()

func _advance_phase() -> void:
	# Move to next phase
	match _current_phase:
		Phase.CHARGE:
			_current_phase = Phase.CONTACT
			_phase_time = 0.0
			_apply_posture(_contact_def)
			
		Phase.CONTACT:
			_current_phase = Phase.FOLLOW_THROUGH
			_phase_time = 0.0
			
		Phase.FOLLOW_THROUGH:
			_current_phase = Phase.SETTLE
			_phase_time = 0.0
			
		Phase.SETTLE:
			if _loop:
				_current_phase = Phase.CHARGE
				_phase_time = 0.0
			else:
				_playing = false
				set_process(false)
				_restore_live_posture()
				playback_finished.emit()
				return
	
	phase_changed.emit(_current_phase)

func _apply_phase_pose() -> void:
	match _current_phase:
		Phase.CHARGE:
			var factor := get_phase_progress()
			_lerp_postures(_ready_def, _charge_def, factor)
			
		Phase.CONTACT:
			# Instant contact
			_apply_posture(_contact_def)
			
		Phase.FOLLOW_THROUGH:
			var factor := get_phase_progress()
			if _follow_through_defs.size() >= 2:
				var idx := int(factor * (_follow_through_defs.size() - 1))
				var local_t := fmod(factor * (_follow_through_defs.size() - 1), 1.0)
				idx = clamp(idx, 0, _follow_through_defs.size() - 2)
				_lerp_postures(_follow_through_defs[idx], _follow_through_defs[idx + 1], local_t)
			elif _follow_through_defs.size() == 1:
				_apply_posture(_follow_through_defs[0])
				
		Phase.SETTLE:
			var factor := get_phase_progress()
			if _follow_through_defs.size() > 0:
				_lerp_postures(_follow_through_defs.back(), _ready_def, factor)
			else:
				_apply_posture(_ready_def)

func _clear_transition_blend_override() -> void:
	if _player and _player.posture:
		_player.posture.transition_pose_blend = null


func _restore_live_posture() -> void:
	if not _player or not _player.posture:
		return

	var restore_id := _restore_posture_id
	if restore_id >= 0:
		var restore_def = load("res://scripts/posture_library.gd").new().get_def(restore_id)
		if restore_def != null:
			_apply_posture(restore_def)
		else:
			_player.posture.paddle_posture = restore_id
	_clear_transition_blend_override()


func _apply_posture(def) -> void:
	if not _player or not def or not _player.posture:
		return
	# Avoid PlayerController.paddle_posture setter — it would re-apply the library skeleton.
	_player.posture.transition_pose_blend = def
	_player.posture.paddle_posture = def.posture_id
	_player.posture.force_posture_update(def)

func _lerp_postures(from_def, to_def, t: float) -> void:
	if not _player or not from_def or not to_def:
		return
	var blended = from_def.lerp_with(to_def, t)
	_apply_posture(blended)
