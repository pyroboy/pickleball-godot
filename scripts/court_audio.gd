class_name CourtAudio extends Node




const AIR = preload("res://assets/audio/court/outdoor_air.wav")
const STEPS: Array[AudioStreamWAV] = [
	preload("res://assets/audio/court/shoe_step_0.wav"), 
	preload("res://assets/audio/court/shoe_step_1.wav"), 
	preload("res://assets/audio/court/shoe_step_2.wav"), 
	preload("res://assets/audio/court/shoe_step_3.wav"), 
]
const SQUEAKS: Array[AudioStreamWAV] = [
	preload("res://assets/audio/court/shoe_squeak_0.wav"), 
	preload("res://assets/audio/court/shoe_squeak_1.wav"), 
]
const POINT_WON = preload("res://assets/audio/court/point_won.wav")
const POINT_LOST = preload("res://assets/audio/court/point_lost.wav")
const SIDE_OUT = preload("res://assets/audio/court/side_out.wav")
const MATCH_WON = preload("res://assets/audio/court/match_won.wav")
const MATCH_LOST = preload("res://assets/audio/court/match_lost.wav")
const STEP_COOLDOWN: = 0.075
const SQUEAK_COOLDOWN: = 0.72

var ambience: AudioStreamPlayer
var cue: AudioStreamPlayer
var shoe_voices: Array[AudioStreamPlayer3D] = []
var steps_played: = 0
var squeaks_played: = 0
var cues_played: = 0
var _game: Node
var _players: Array[Node3D] = []
var _positions: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _directions: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _speeds: Array[float] = [0.0, 0.0]
var _right_locked: Array[bool] = [true, true]
var _left_locked: Array[bool] = [true, true]
var _initialized: Array[bool] = [false, false]
var _step_remaining: Array[float] = [0.0, 0.0]
var _squeak_remaining: Array[float] = [0.0, 0.0]
var _turn_remaining: Array[float] = [0.0, 0.0]
var _next_step: Array[int] = [0, 2]
var _backgrounded: = false
var _ambience_enabled: = true
var _ambience_started: = false
var _resume_ambience_pending: = false
var _footsteps_enabled: = true
var _last_cue_msec: = -1000

func _ready() -> void :

	process_priority = 50
	process_mode = Node.PROCESS_MODE_PAUSABLE
	ambience = AudioStreamPlayer.new()
	ambience.process_mode = Node.PROCESS_MODE_ALWAYS
	ambience.name = "CourtAmbience"
	ambience.bus = "Ambience"
	ambience.max_polyphony = 1
	ambience.volume_db = -8.0
	var loop: AudioStreamWAV = AIR.duplicate()
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0
	loop.loop_end = loop.data.size() / 2
	ambience.stream = loop
	add_child(ambience)
	cue = AudioStreamPlayer.new()
	cue.process_mode = Node.PROCESS_MODE_ALWAYS
	cue.name = "PointCue"
	cue.bus = "SFX"
	cue.max_polyphony = 1
	cue.volume_db = -15.0
	add_child(cue)
	for index in range(2):
		var voice: = AudioStreamPlayer3D.new()
		voice.process_mode = Node.PROCESS_MODE_ALWAYS
		voice.name = "ShoeAudio%d" % index
		voice.bus = "Footsteps"
		voice.max_polyphony = 1
		voice.unit_size = 10.0
		voice.max_distance = 45.0
		voice.max_db = -12.0
		voice.panning_strength = 0.65
		voice.attenuation_filter_cutoff_hz = 14000.0
		add_child(voice)
		shoe_voices.append(voice)
	var settings: = get_node_or_null("/root/Settings")
	if settings:
		settings.settings_changed.connect(_on_setting_changed)
		_ambience_enabled = float(settings.get_value("audio.ambience", 0.55)) > 0.0
		_footsteps_enabled = float(settings.get_value("audio.footsteps", 0.75)) > 0.0
	_sync_ambience()

func setup(game: Node) -> void :
	if _game == game: return
	_game = game
	_players.clear()
	_players.append(game.player_left)
	_players.append(game.player_right)
	reset_contacts()
	_sync_ambience()

func reset_contacts() -> void :
	for index in range(2):
		_initialized[index] = false
		_speeds[index] = 0.0
		_step_remaining[index] = 0.0
		_turn_remaining[index] = 0.0
		_squeak_remaining[index] = 0.0
		if index < shoe_voices.size(): _stop_voice(shoe_voices[index])
	if cue: _stop_voice(cue)
	_last_cue_msec = -1000

func _process(delta: float) -> void :



	if _resume_ambience_pending:
		_resume_ambience_pending = false
		_sync_ambience()
	if _game == null or _players.size() != 2 or delta <= 0.0 or _backgrounded: return

	if not _footsteps_enabled: return
	if _game.has_method("_tool_state_active") and _game._tool_state_active():
		_initialized[0] = false
		_initialized[1] = false
		return
	_update_player(0, delta)
	_update_player(1, delta)

func _update_player(index: int, delta: float) -> void :
	var player: Node3D = _players[index]
	if not is_instance_valid(player): return
	var legs = player.get("leg_ik")
	if legs == null or not legs.feet_initialized:
		_initialized[index] = false
		return
	var position_now: = player.global_position
	var displacement: = position_now - _positions[index]
	displacement.y = 0.0
	var velocity: Vector3 = player.current_velocity
	velocity.y = 0.0
	var speed: = velocity.length()
	var right: bool = legs.right_foot_locked
	var left: bool = legs.left_foot_locked
	_step_remaining[index] = maxf(0.0, _step_remaining[index] - delta)
	_squeak_remaining[index] = maxf(0.0, _squeak_remaining[index] - delta)
	_turn_remaining[index] = maxf(0.0, _turn_remaining[index] - delta)

	if not _initialized[index] or displacement.length() > maxf(0.85, speed * delta * 2.5 + 0.1):
		_initialized[index] = true
		_step_remaining[index] = 0.12
		_turn_remaining[index] = 0.0
	else:


		var braking: = _speeds[index] > 2.0 and speed < _speeds[index] * 0.68
		var reversing: = speed > 1.5 and _speeds[index] > 1.5 and velocity.normalized().dot(_directions[index]) < 0.25
		if braking or reversing: _turn_remaining[index] = 0.24
		var landed_right: bool = right and not _right_locked[index]
		var landed_left: bool = left and not _left_locked[index]
		var audible_motion: = maxf(speed, _speeds[index]) > 0.2
		if (landed_right or landed_left) and audible_motion and _step_remaining[index] <= 0.0 and not player.is_jumping:
			var contact: Vector3 = legs.right_foot_lock_pos if landed_right else legs.left_foot_lock_pos
			_play_shoe(index, contact, maxf(speed, _speeds[index]), _turn_remaining[index] > 0.0 and _squeak_remaining[index] <= 0.0)
			_turn_remaining[index] = 0.0
	_positions[index] = position_now
	_right_locked[index] = right
	_left_locked[index] = left
	_speeds[index] = speed
	if speed > 0.1: _directions[index] = velocity / speed

func _play_shoe(index: int, position_now: Vector3, speed: float, squeak: bool) -> void :
	if _backgrounded or not can_process() or not _footsteps_enabled: return
	var voice: AudioStreamPlayer3D = shoe_voices[index]
	voice.global_position = position_now
	if squeak:
		voice.stream = SQUEAKS[_next_step[index] %SQUEAKS.size()]
		voice.volume_db = -20.0
		_squeak_remaining[index] = SQUEAK_COOLDOWN
		squeaks_played += 1
	else:
		voice.stream = STEPS[_next_step[index] %STEPS.size()]
		voice.volume_db = lerpf(-25.0, -17.0, clampf(speed / 5.0, 0.0, 1.0))
		steps_played += 1
	_next_step[index] += 1
	voice.pitch_scale = 0.985 if _next_step[index] %2 == 0 else 1.015
	voice.play()
	_step_remaining[index] = STEP_COOLDOWN

func play_point_cue(winner: int, side_out: bool = false, match_finished: bool = false) -> void :
	if winner not in [0, 1] or _backgrounded or not can_process(): return

	var now: = Time.get_ticks_msec()
	if now - _last_cue_msec < 100: return
	_last_cue_msec = now
	if match_finished: cue.stream = MATCH_WON if winner == 0 else MATCH_LOST
	elif side_out: cue.stream = SIDE_OUT
	else: cue.stream = POINT_WON if winner == 0 else POINT_LOST
	cue.play()
	cues_played += 1

func _on_setting_changed(key: String, value: Variant) -> void :
	if key == "audio.ambience":
		_ambience_enabled = float(value) > 0.0
		_sync_ambience()
	elif key == "audio.footsteps":
		_footsteps_enabled = float(value) > 0.0
		_initialized[0] = false
		_initialized[1] = false
		if not _footsteps_enabled:
			_stop_voice(shoe_voices[0])
			_stop_voice(shoe_voices[1])

func _sync_ambience() -> void :
	if ambience == null: return
	var game_available: = is_instance_valid(_game) and not _game.is_queued_for_deletion()
	if not _ambience_enabled or _backgrounded or not game_available:
		_stop_voice(ambience)
		_ambience_started = false
	elif not get_tree().paused and not _ambience_started:
		ambience.play()
		_ambience_started = true



func _stop_voice(player: Node) -> void :


	player.stream_paused = false
	player.stop()

func _exit_tree() -> void :



	if is_instance_valid(ambience):
		_stop_voice(ambience)
		ambience.stream = null
	_ambience_started = false
	_resume_ambience_pending = false
	if is_instance_valid(cue):
		_stop_voice(cue)
		cue.stream = null
	for voice in shoe_voices:
		if is_instance_valid(voice):
			_stop_voice(voice)
			voice.stream = null

func _notification(what: int) -> void :
	if not is_inside_tree(): return
	if what == NOTIFICATION_PAUSED:



		if ambience: _stop_voice(ambience)
		_ambience_started = false
		_resume_ambience_pending = false
		if cue: _stop_voice(cue)
		for voice in shoe_voices: _stop_voice(voice)
	elif what == NOTIFICATION_UNPAUSED:
		_resume_ambience_pending = true
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_backgrounded = true
		_resume_ambience_pending = false
		_sync_ambience()
		if cue: _stop_voice(cue)
		for voice in shoe_voices: _stop_voice(voice)
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_backgrounded = false
		_initialized[0] = false
		_initialized[1] = false
		_resume_ambience_pending = true
