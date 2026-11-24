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
const POINT_WON = preload("res://assets/audio/cues/point_won.wav")
const POINT_LOST = preload("res://assets/audio/cues/point_lost.wav")
const SIDE_OUT = preload("res://assets/audio/cues/side_out.wav")
const MATCH_WON = preload("res://assets/audio/cues/match_won.wav")
const MATCH_LOST = preload("res://assets/audio/cues/match_lost.wav")
const ParkSounds = preload("res://scripts/audio/park_sounds.gd")
const SfxBank = preload("res://scripts/audio/sfx_bank.gd")
const CLAP_AFTER_SHOTS: = 5       # rally length that earns a few claps
const CHEER_AFTER_SHOTS: = 10     # rally length that earns full applause
const ZIP_SPEED: = 11.0           # ball speed (m/s) where a hit starts to cut the air
const SWELL_AFTER_SHOTS: = 8
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
# One entry per player on court (two in singles, four in doubles); sized by _track_players.
var _positions: Array[Vector3] = []
var _directions: Array[Vector3] = []
var _speeds: Array[float] = []
var _right_locked: Array[bool] = []
var _left_locked: Array[bool] = []
var _initialized: Array[bool] = []
var _step_remaining: Array[float] = []
var _squeak_remaining: Array[float] = []
var _turn_remaining: Array[float] = []
var _next_step: Array[int] = []
var _backgrounded: = false
var _ambience_enabled: = true
var _ambience_started: = false
var _resume_ambience_pending: = false
var _footsteps_enabled: = true
var _last_cue_msec: = -1000
var crowd: AudioStreamPlayer
var birds: AudioStreamPlayer
var _chirps: Array[AudioStreamWAV] = []
var _scuffs: Array[AudioStreamWAV] = []
var _park_rng: = RandomNumberGenerator.new()
var _bird_wait: = 3.0
var _rally_shots: = 0
var _crowd_db: = -80.0
var applause: AudioStreamPlayer
var impact: AudioStreamPlayer
var applause_played: = 0
var zips_played: = 0
var _claps_small: AudioStreamWAV
var _claps_big: AudioStreamWAV
var _claps_match: AudioStreamWAV
var _zips: Array[AudioStreamWAV] = []
var _thump: AudioStreamWAV
var accent: AudioStreamPlayer
var _perfect: AudioStreamWAV
var _clack: AudioStreamWAV

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
	_park_rng.seed = 5150
	for variant in 3: _chirps.append(ParkSounds.chirp(variant))
	for variant in 3: _scuffs.append(ParkSounds.scuff(variant))
	birds = AudioStreamPlayer.new()
	birds.process_mode = Node.PROCESS_MODE_PAUSABLE
	birds.name = "ParkBirds"
	birds.bus = "Ambience"
	birds.volume_db = -27.0
	add_child(birds)
	crowd = AudioStreamPlayer.new()
	crowd.process_mode = Node.PROCESS_MODE_PAUSABLE
	crowd.name = "CrowdSwell"
	crowd.bus = "Ambience"
	crowd.volume_db = -80.0
	crowd.stream = ParkSounds.crowd_loop()
	add_child(crowd)
	_claps_small = SfxBank.applause(2.2, 5, 0.0, 811)
	_claps_big = SfxBank.applause(3.4, 11, 0.5, 812)
	_claps_match = SfxBank.applause(5.0, 14, 0.8, 813)
	for variant in 3: _zips.append(SfxBank.zip(variant))
	_thump = SfxBank.thump()
	applause = AudioStreamPlayer.new()
	applause.process_mode = Node.PROCESS_MODE_PAUSABLE
	applause.name = "CrowdApplause"
	applause.bus = "Ambience"
	add_child(applause)
	impact = AudioStreamPlayer.new()
	impact.process_mode = Node.PROCESS_MODE_PAUSABLE
	impact.name = "ImpactLayer"
	impact.bus = "SFX"
	impact.max_polyphony = 2
	add_child(impact)
	_perfect = SfxBank.chime([1318.5, 1975.5, 2637.0], 0.045, 0.34, 13.0)
	_clack = SfxBank.clack()
	accent = AudioStreamPlayer.new()
	accent.process_mode = Node.PROCESS_MODE_PAUSABLE
	accent.name = "AccentLayer"
	accent.bus = "SFX"
	add_child(accent)
	var settings: = get_node_or_null("/root/Settings")
	if settings:
		settings.settings_changed.connect(_on_setting_changed)
		_ambience_enabled = float(settings.get_value("audio.ambience", 0.55)) > 0.0
		_footsteps_enabled = float(settings.get_value("audio.footsteps", 0.75)) > 0.0
	_sync_ambience()

func setup(game: Node) -> void :
	if _game == game: return
	_game = game
	_track_players([game.player_left, game.player_right])
	_hook_match.call_deferred()   # partners and match helpers exist once the game finished _ready
	var ball = game.get("ball")
	if ball != null and ball.has_signal("hit_by_paddle") and not ball.hit_by_paddle.is_connected(_on_rally_shot):
		ball.hit_by_paddle.connect(_on_rally_shot)
	if ball != null and ball.has_signal("hit_player_body") and not ball.hit_player_body.is_connected(_on_body_hit):
		ball.hit_player_body.connect(_on_body_hit)
	reset_contacts()
	_sync_ambience()

## Shoes are tracked for every player on court; each gets a positioned voice.
func _track_players(everyone: Array) -> void :
	_players.clear()
	for player in everyone:
		if player is Node3D and not _players.has(player): _players.append(player)
	var count: = _players.size()
	for track in [_positions, _directions, _speeds, _right_locked, _left_locked, _initialized, _step_remaining, _squeak_remaining, _turn_remaining, _next_step]:
		track.resize(count)
	for index in count:
		_positions[index] = Vector3.ZERO
		_directions[index] = Vector3.ZERO
		_speeds[index] = 0.0
		_right_locked[index] = true
		_left_locked[index] = true
		_initialized[index] = false
		_step_remaining[index] = 0.0
		_squeak_remaining[index] = 0.0
		_turn_remaining[index] = 0.0
		_next_step[index] = index * 2
	while shoe_voices.size() < count:
		var voice: = AudioStreamPlayer3D.new()
		voice.process_mode = Node.PROCESS_MODE_ALWAYS
		voice.name = "ShoeAudio%d" % shoe_voices.size()
		voice.bus = "Footsteps"
		voice.max_polyphony = 1
		voice.unit_size = 10.0
		voice.max_distance = 45.0
		voice.max_db = -12.0
		voice.panning_strength = 0.65
		voice.attenuation_filter_cutoff_hz = 14000.0
		add_child(voice)
		shoe_voices.append(voice)

func _hook_match() -> void :
	if not is_instance_valid(_game): return
	if _game.has_method("get_players"): _track_players(_game.get_players())
	var human = _game.get_human_actor() if _game.has_method("get_human_actor") else null
	if human != null and human.get("posture") != null and human.posture.has_signal("grade_flashed") and not human.posture.grade_flashed.is_connected(_on_grade):
		human.posture.grade_flashed.connect(_on_grade)
	var between = _game.get("between_point_controller")
	if between != null and between.has_signal("partner_tapped") and not between.partner_tapped.is_connected(_on_partner_tap):
		between.partner_tapped.connect(_on_partner_tap)

## A perfectly timed hit rings a small sparkle over the pop.
func _on_grade(grade: String) -> void :
	if grade != "PERFECT" or _backgrounded or not can_process(): return
	accent.stream = _perfect
	accent.volume_db = -15.0
	accent.play()

## Partners tap paddles between points.
func _on_partner_tap(_at: Vector3) -> void :
	if _backgrounded or not can_process(): return
	accent.stream = _clack
	accent.volume_db = -11.0
	accent.play()

func reset_contacts() -> void :
	for index in _players.size():
		_initialized[index] = false
		_speeds[index] = 0.0
		_step_remaining[index] = 0.0
		_turn_remaining[index] = 0.0
		_squeak_remaining[index] = 0.0
		if index < shoe_voices.size(): _stop_voice(shoe_voices[index])
	if cue: _stop_voice(cue)
	_last_cue_msec = -1000
	_rally_shots = 0

func _on_rally_shot(_player_num: int) -> void :
	_rally_shots += 1
	# A hard-hit ball adds a short rush of air on top of the paddle pop.
	var ball = _game.get("ball") if is_instance_valid(_game) else null
	if ball == null or _backgrounded or not can_process(): return
	var speed: float = ball.linear_velocity.length()
	if not is_finite(speed) or speed < ZIP_SPEED: return
	var power: = clampf((speed - ZIP_SPEED) / 9.0, 0.0, 1.0)
	impact.stream = _zips[_rally_shots % _zips.size()]
	impact.volume_db = lerpf(-26.0, -17.0, power)
	impact.pitch_scale = lerpf(0.94, 1.1, power)
	impact.play()
	zips_played += 1

func _on_body_hit(_player_num: int) -> void :
	if _backgrounded or not can_process(): return
	impact.stream = _thump
	impact.volume_db = -9.0
	impact.pitch_scale = 1.0
	impact.play()

## The courtside crowd claps for long rallies and for the end of the match;
## a little quieter when the point went against the player.
func _play_applause(rally_shots: int, player_won: bool, match_finished: bool) -> void :
	if not _ambience_enabled: return
	if match_finished:
		applause.stream = _claps_match
		applause.volume_db = -9.0 if player_won else -15.0
	elif rally_shots >= CHEER_AFTER_SHOTS:
		applause.stream = _claps_big
		applause.volume_db = -13.0 if player_won else -17.0
	elif rally_shots >= CLAP_AFTER_SHOTS:
		applause.stream = _claps_small
		applause.volume_db = -17.0 if player_won else -21.0
	else:
		return
	applause.play()
	applause_played += 1
	PerfMonitor.note("crowd_applause", {"rally": rally_shots, "match": match_finished, "zips": zips_played})

func _update_park(delta: float) -> void :
	if _backgrounded or not _ambience_enabled or not _ambience_started: return
	_bird_wait -= delta
	if _bird_wait <= 0.0:
		_bird_wait = _park_rng.randf_range(3.5, 9.0)
		birds.stream = _chirps[_park_rng.randi() % _chirps.size()]
		birds.pitch_scale = _park_rng.randf_range(0.9, 1.15)
		birds.volume_db = _park_rng.randf_range(-31.0, -25.0)
		birds.play()
	# Crowd swells on long rallies and falls away once the point is over.
	var target: = -80.0
	if _rally_shots > SWELL_AFTER_SHOTS:
		target = lerpf(-38.0, -22.0, clampf(float(_rally_shots - SWELL_AFTER_SHOTS) / 10.0, 0.0, 1.0))
	if absf(target - _crowd_db) > 0.05:
		_crowd_db = move_toward(_crowd_db, target, delta * (14.0 if target > _crowd_db else 24.0))
		crowd.volume_db = _crowd_db
	if _crowd_db > -70.0 and not crowd.playing: crowd.play()
	elif _crowd_db <= -70.0 and crowd.playing: crowd.stop()

func _process(delta: float) -> void:
	var _pt := Time.get_ticks_usec()
	_perf_process(delta)
	PerfMonitor.record("proc.court_audio", Time.get_ticks_usec() - _pt)

func _perf_process(delta: float) -> void:



	if _resume_ambience_pending:
		_resume_ambience_pending = false
		_sync_ambience()
	if _game == null or _players.is_empty() or delta <= 0.0 or _backgrounded: return
	_update_park(delta)

	if not _footsteps_enabled: return
	if _game.has_method("_tool_state_active") and _game._tool_state_active():
		_initialized.fill(false)
		return
	for index in _players.size(): _update_player(index, delta)

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
		if speed > 3.2 and _next_step[index] % 3 == 0:
			voice.stream = _scuffs[(_next_step[index] / 3) % _scuffs.size()]   # hard push-off scuff
			voice.volume_db = lerpf(-27.0, -20.0, clampf((speed - 3.2) / 2.0, 0.0, 1.0))
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
	_play_applause(_rally_shots, winner == 0, match_finished)
	_rally_shots = 0
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
		_initialized.fill(false)
		if not _footsteps_enabled:
			for voice in shoe_voices: _stop_voice(voice)

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
		if crowd: _stop_voice(crowd)
		if applause: _stop_voice(applause)
		if impact: _stop_voice(impact)
		if accent: _stop_voice(accent)
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
		if applause: _stop_voice(applause)
		if impact: _stop_voice(impact)
		for voice in shoe_voices: _stop_voice(voice)
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_backgrounded = false
		_initialized.fill(false)
		_resume_ambience_pending = true
