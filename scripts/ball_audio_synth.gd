class_name BallAudioSynth extends Node
const RuntimePolicy = preload("res://scripts/runtime_policy.gd")





const AUDIO_SAMPLE_RATE: = 44100.0
const POP_FREQ: = 1200.0
const POP_UPPER_FREQ: = 1720.0
const COURT_BOUNCE_FREQ: = 620.0
const COURT_BOUNCE_UPPER_FREQ: = 780.0
const COURT_BOUNCE_BODY_FREQ: = 150.0
const NET_MESH_FREQ: = 4100.0
const NET_TAPE_FREQ: = 520.0
const NET_AUDIO_COOLDOWN: = 0.08

const PADDLE_MODE_FREQ: = 1273.0
const PADDLE_MODE_UPPER_FREQ: = 1425.0
const PADDLE_RING_FREQ: = 1800.0
const BALL_STRIKE_FREQ: = 910.0
const BALL_HELMHOLTZ_FREQ: = 1399.0
const BALL_SHELL_FREQ: = 1804.0
const CONTACT_CHIRP_RANGE: = 429.0

const BODY_LOW_FREQ: = 200.0
const BODY_FREQ: = 236.0
const BODY_MID_FREQ: = 323.0
const BODY_UPPER_FREQ: = 410.0
const BODY_HIGH_FREQ: = 368.0
const BRIGHTNESS_FREQ: = 2870.0


var paddle_hit_player: AudioStreamPlayer
var bounce_player: AudioStreamPlayer3D
var net_hit_player: AudioStreamPlayer3D
var net_audio_cooldown: = 0.0

var _audio_rng: = RandomNumberGenerator.new()


var _thock_pool: Array[AudioStreamWAV] = []
var _volley_pool: Array[AudioStreamWAV] = []
var _smash_pool: Array[AudioStreamWAV] = []
var _dink_pool: Array[AudioStreamWAV] = []   # soft hollow tick for dinks and resets
var _last_dink_idx: = -1
const DINK_SPEED: = 3.4
var _rim_pool: Array[AudioStreamWAV] = []
var _frame_pool: Array[AudioStreamWAV] = []
var _court_pool: Array[AudioStreamWAV] = []
var _net_tape_pool: Array[AudioStreamWAV] = []
var _net_mesh_pool: Array[AudioStreamWAV] = []
const COURT_SPEEDS: = [1.0, 3.0, 5.0, 7.0, 10.0, 14.0]
const NET_SPEEDS: = [2.0, 7.0, 14.0]
var _last_thock_idx: = -1
var _last_volley_idx: = -1
var _last_smash_idx: = -1
var _last_rim_idx: = -1
var _last_frame_idx: = -1


var paddle_attack_tune: = 0.1
var paddle_metallic_tune: = -0.35
var paddle_pitch_tune: = 0.05
var paddle_sub_pitch_tune: = 0.0
var paddle_pitch_blend_tune: = 0.0
var paddle_upper_pitch_tune: = 0.1
var paddle_body_pitch_tune: = -0.05
var paddle_hollow_pitch_tune: = -0.2
var paddle_ring_tune: = -0.35
var paddle_body_tune: = -0.15
var paddle_tail_tune: = -0.35
var paddle_wood_tune: = -0.25
var paddle_echo_tune: = -0.6
var paddle_damp_tune: = 0.35
var paddle_noise_tune: = -0.7
var paddle_hollow_tune: = -0.55
var paddle_clack_tune: = 0.1
var paddle_compress_tune: = 0.35
var paddle_dead_tune: = 0.35
var paddle_presence_tune: = 0.15
var paddle_rumble_tune: = -0.7
var paddle_crackle_tune: = -0.9
var paddle_reflection_tune: = -0.2
var paddle_sweet_spot_tune: = 0.35
var paddle_core_softness_tune: = 0.55
var paddle_variation_tune: = -0.35
var court_weight_tune: = 0.0
var court_snap_tune: = 0.0
var court_decay_tune: = 0.0
var court_hardness_tune: = 0.0
var court_surface_tune: = 0.0
var paddle_chirp_tune: = 0.15
var paddle_helmholtz_tune: = 0.0

func _ready() -> void :
	RuntimePolicy.seed_rng(_audio_rng, 12)
	_setup_audio()

func _exit_tree() -> void :

	if is_instance_valid(paddle_hit_player):
		paddle_hit_player.stream_paused = false
		paddle_hit_player.stop()
		paddle_hit_player.stream = null
	if is_instance_valid(bounce_player):
		bounce_player.stream_paused = false
		bounce_player.stop()
		bounce_player.stream = null
	if is_instance_valid(net_hit_player):
		net_hit_player.stream_paused = false
		net_hit_player.stop()
		net_hit_player.stream = null

func _notification(what: int) -> void :
	if what != NOTIFICATION_PAUSED and what != NOTIFICATION_APPLICATION_PAUSED and what != NOTIFICATION_APPLICATION_FOCUS_OUT: return
	if is_instance_valid(paddle_hit_player): paddle_hit_player.stop()
	if is_instance_valid(bounce_player): bounce_player.stop()
	if is_instance_valid(net_hit_player): net_hit_player.stop()

func _setup_audio() -> void :

	var bus_index: = AudioServer.get_bus_index("SFX")
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, "SFX")
		AudioServer.set_bus_send(bus_index, "Master")
	var settings: = get_node_or_null("/root/Settings")
	if settings != null:
		var level: float = float(settings.get_value("audio.sfx", 1.0))
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(level, 0.0001)))


	paddle_hit_player = AudioStreamPlayer.new()
	paddle_hit_player.process_mode = Node.PROCESS_MODE_ALWAYS
	paddle_hit_player.name = "PaddleHitAudio"
	paddle_hit_player.bus = "SFX"
	paddle_hit_player.max_polyphony = 2
	paddle_hit_player.volume_db = 0.0
	add_child(paddle_hit_player)

	bounce_player = AudioStreamPlayer3D.new()
	bounce_player.process_mode = Node.PROCESS_MODE_ALWAYS
	bounce_player.name = "BounceAudio"
	bounce_player.bus = "SFX"
	bounce_player.volume_db = -6.0
	bounce_player.max_db = -8.0
	bounce_player.unit_size = 8.0
	bounce_player.max_distance = 50.0
	bounce_player.panning_strength = 0.65
	bounce_player.attenuation_filter_cutoff_hz = 12000.0
	bounce_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(bounce_player)

	net_hit_player = AudioStreamPlayer3D.new()
	net_hit_player.process_mode = Node.PROCESS_MODE_ALWAYS
	net_hit_player.name = "NetHitAudio"
	net_hit_player.bus = "SFX"
	net_hit_player.volume_db = -8.0
	net_hit_player.max_db = -10.0
	net_hit_player.unit_size = 8.0
	net_hit_player.max_distance = 50.0
	net_hit_player.panning_strength = 0.65
	net_hit_player.attenuation_filter_cutoff_hz = 10000.0
	net_hit_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(net_hit_player)


	_create_procedural_sounds()

func _create_procedural_sounds() -> void :



	_thock_pool.clear()
	_volley_pool.clear()
	_smash_pool.clear()
	_dink_pool.clear()
	_rim_pool.clear()
	_frame_pool.clear()
	_court_pool.clear()
	_net_tape_pool.clear()
	_net_mesh_pool.clear()
	var qualities: = [0.44, 0.5, 0.56, 0.62, 0.68, 0.74, 0.8, 0.86]
	for q in qualities:
		_thock_pool.append(_create_thock_sound_at(8.0, q))
		_volley_pool.append(_create_volley_sound_at(q))
		_smash_pool.append(_create_smash_sound_at(q))

	for q in [0.3, 0.5, 0.7, 0.9]:
		_dink_pool.append(_create_dink_sound_at(q))

	var edge_qualities: = [0.1, 0.38, 0.65, 0.9]
	for q in edge_qualities:
		_rim_pool.append(_create_rim_hit_sound_at(q))
		_frame_pool.append(_create_frame_hit_sound_at(q))

	var saved_seed: = _audio_rng.seed
	var saved_state: = _audio_rng.state
	_audio_rng.seed = 170921
	for speed in COURT_SPEEDS:
		_court_pool.append(_create_court_bounce_sound(speed))
	for speed in NET_SPEEDS:
		_net_tape_pool.append(_create_net_tape_sound(speed))
		_net_mesh_pool.append(_create_net_mesh_sound(speed))
	_audio_rng.seed = saved_seed
	_audio_rng.state = saved_state
	bounce_player.stream = _court_pool[3]

func play_serve_sound(speed: float = 8.0) -> void :

	on_paddle_hit(speed)

func play_test_paddle_sound(test_index: int) -> void :
	var sound_wave: AudioStreamWAV
	match test_index:
		0: sound_wave = _create_volley_sound()
		1: sound_wave = _create_thock_sound(8.0)
		2: sound_wave = _create_smash_sound()
		3: sound_wave = _create_rim_hit_sound_at(_audio_rng.randf_range(0.3, 0.8))
		4: sound_wave = _create_frame_hit_sound_at(_audio_rng.randf_range(0.2, 0.9))
		_: return
	paddle_hit_player.stream = sound_wave
	paddle_hit_player.volume_db = 0.0
	paddle_hit_player.pitch_scale = 1.0
	paddle_hit_player.play()

func play_test_court_sound(test_index: int) -> void :
	var speed: = 5.0
	var volume_db: = -8.5

	match test_index:
		0:
			speed = 3.5
			volume_db = -9.0 + court_weight_tune * 1.2
		1:
			speed = 6.0
			volume_db = -6.0 + court_weight_tune * 1.2
		2:
			speed = 9.5
			volume_db = -3.5 + court_weight_tune * 1.2
		_:
			return

	bounce_player.stream = _court_pool[_court_speed_bucket(speed)]
	bounce_player.volume_db = volume_db
	bounce_player.pitch_scale = 1.0
	bounce_player.play()

func set_sound_tuning(setting: String, value: float) -> void :
	var clamped_value = clamp(value, -1.0, 1.0)
	match setting:
		"paddle_attack":
			paddle_attack_tune = clamped_value
		"paddle_metallic":
			paddle_metallic_tune = clamped_value
		"paddle_pitch":
			paddle_pitch_tune = clamped_value
		"paddle_sub_pitch":
			paddle_sub_pitch_tune = clamped_value
		"paddle_pitch_blend":
			paddle_pitch_blend_tune = clamped_value
		"paddle_upper_pitch":
			paddle_upper_pitch_tune = clamped_value
		"paddle_body_pitch":
			paddle_body_pitch_tune = clamped_value
		"paddle_hollow_pitch":
			paddle_hollow_pitch_tune = clamped_value
		"paddle_ring":
			paddle_ring_tune = clamped_value
		"paddle_body":
			paddle_body_tune = clamped_value
		"paddle_tail":
			paddle_tail_tune = clamped_value
		"paddle_wood":
			paddle_wood_tune = clamped_value
		"paddle_echo":
			paddle_echo_tune = clamped_value
		"paddle_damp":
			paddle_damp_tune = clamped_value
		"paddle_noise":
			paddle_noise_tune = clamped_value
		"paddle_hollow":
			paddle_hollow_tune = clamped_value
		"paddle_clack":
			paddle_clack_tune = clamped_value
		"paddle_compress":
			paddle_compress_tune = clamped_value
		"paddle_dead":
			paddle_dead_tune = clamped_value
		"paddle_presence":
			paddle_presence_tune = clamped_value
		"paddle_rumble":
			paddle_rumble_tune = clamped_value
		"paddle_crackle":
			paddle_crackle_tune = clamped_value
		"paddle_reflection":
			paddle_reflection_tune = clamped_value
		"paddle_sweet_spot":
			paddle_sweet_spot_tune = clamped_value
		"paddle_core_softness":
			paddle_core_softness_tune = clamped_value
		"paddle_variation":
			paddle_variation_tune = clamped_value
		"court_weight":
			court_weight_tune = clamped_value
		"court_snap":
			court_snap_tune = clamped_value
		"court_decay":
			court_decay_tune = clamped_value
		"court_hardness":
			court_hardness_tune = clamped_value
		"court_surface":
			court_surface_tune = clamped_value
		"paddle_chirp":
			paddle_chirp_tune = clamped_value
		"paddle_helmholtz":
			paddle_helmholtz_tune = clamped_value

func get_sound_tunings() -> Dictionary:
	return {
		"paddle_attack": paddle_attack_tune, 
		"paddle_metallic": paddle_metallic_tune, 
		"paddle_pitch": paddle_pitch_tune, 
		"paddle_sub_pitch": paddle_sub_pitch_tune, 
		"paddle_pitch_blend": paddle_pitch_blend_tune, 
		"paddle_upper_pitch": paddle_upper_pitch_tune, 
		"paddle_body_pitch": paddle_body_pitch_tune, 
		"paddle_hollow_pitch": paddle_hollow_pitch_tune, 
		"paddle_ring": paddle_ring_tune, 
		"paddle_body": paddle_body_tune, 
		"paddle_tail": paddle_tail_tune, 
		"paddle_wood": paddle_wood_tune, 
		"paddle_echo": paddle_echo_tune, 
		"paddle_damp": paddle_damp_tune, 
		"paddle_noise": paddle_noise_tune, 
		"paddle_hollow": paddle_hollow_tune, 
		"paddle_clack": paddle_clack_tune, 
		"paddle_compress": paddle_compress_tune, 
		"paddle_dead": paddle_dead_tune, 
		"paddle_presence": paddle_presence_tune, 
		"paddle_rumble": paddle_rumble_tune, 
		"paddle_crackle": paddle_crackle_tune, 
		"paddle_reflection": paddle_reflection_tune, 
		"paddle_sweet_spot": paddle_sweet_spot_tune, 
		"paddle_core_softness": paddle_core_softness_tune, 
		"paddle_variation": paddle_variation_tune, 
		"court_weight": court_weight_tune, 
		"court_snap": court_snap_tune, 
		"court_decay": court_decay_tune, 
		"court_hardness": court_hardness_tune, 
		"court_surface": court_surface_tune, 
		"paddle_chirp": paddle_chirp_tune, 
		"paddle_helmholtz": paddle_helmholtz_tune
	}

func get_paddle_pitch_frequency() -> float:
	return PADDLE_MODE_FREQ * (1.0 + paddle_pitch_tune * 0.24 - max(paddle_sub_pitch_tune, 0.0) * 0.1)

func get_paddle_pitch_note() -> String:
	var frequency: = get_paddle_pitch_frequency()
	var midi: = int(round(69.0 + 12.0 * (log(frequency / 440.0) / log(2.0))))
	var note_names: = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
	var note_index: = posmod(midi, 12)
	var octave: = int(floor(float(midi) / 12.0)) - 1
	return note_names[note_index] + str(octave)



func on_paddle_hit(speed: float) -> void :
	if not is_finite(speed) or speed <= 0.0 or not can_process():
		return


	var hit_type: = 0

	var pool: Array[AudioStreamWAV]
	var last_idx: = 0

	match hit_type:
		1:
			pool = _rim_pool
			last_idx = _last_rim_idx
		2:
			pool = _frame_pool
			last_idx = _last_frame_idx
		_:
			if speed < DINK_SPEED and not _dink_pool.is_empty():
				pool = _dink_pool
				last_idx = _last_dink_idx
			elif speed < 5.0:
				pool = _volley_pool
				last_idx = _last_volley_idx
			elif speed < 12.0:
				pool = _thock_pool
				last_idx = _last_thock_idx
			else:
				pool = _smash_pool
				last_idx = _last_smash_idx

	if pool.is_empty():
		return


	var idx: = last_idx
	if pool.size() > 1:
		while idx == last_idx:
			idx = _audio_rng.randi() % pool.size()
	else:
		idx = 0


	match hit_type:
		1: _last_rim_idx = idx
		2: _last_frame_idx = idx
		_:
			if pool == _dink_pool: _last_dink_idx = idx
			elif speed < 5.0: _last_volley_idx = idx
			elif speed < 12.0: _last_thock_idx = idx
			else: _last_smash_idx = idx


	var vol_offset: = 0.0
	if hit_type == 2: vol_offset = -3.5
	elif hit_type == 1: vol_offset = -1.5

	paddle_hit_player.stream = pool[idx]
	paddle_hit_player.volume_db = clampf(impact_volume_db(speed) + vol_offset, -25.0, -7.0)
	# Pitch rises with shot power: a soft dink sits low, a smash rings high.
	paddle_hit_player.pitch_scale = hit_pitch_scale(speed) * _audio_rng.randf_range(0.985, 1.015)
	paddle_hit_player.play()

static func hit_pitch_scale(speed: float) -> float:
	return lerpf(0.90, 1.16, pow(clampf(speed / 22.0, 0.0, 1.0), 0.8))

## Dink: short, hollow, low-energy tick (a quick sine knock plus a breath of filtered noise).
func _create_dink_sound_at(quality: float) -> AudioStreamWAV:
	var rng: = RandomNumberGenerator.new()
	rng.seed = 9100 + int(quality * 100.0)
	var samples: = PackedByteArray()
	var frames: = int(AUDIO_SAMPLE_RATE * 0.085)
	var lp: = 0.0
	var base: = lerpf(760.0, 980.0, quality)
	for i in frames:
		var t: = float(i) / AUDIO_SAMPLE_RATE
		var tone: = sin(TAU * base * t) * exp(-t * 85.0) + 0.45 * sin(TAU * base * 1.52 * t) * exp(-t * 130.0)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.35)
		var tick: = lp * exp(-t * 260.0) * 0.5
		_append_sample(samples, clampf((tone * 0.55 + tick) * minf(t / 0.0006, 1.0), -1.0, 1.0) * 0.8)
	_fade_short_tail(samples)
	var wave: = _new_wave()
	wave.data = samples
	return wave

static func impact_volume_db(speed: float) -> float:

	return lerpf(-19.0, -7.0, pow(clampf(speed / 18.0, 0.0, 1.0), 0.62))

func on_floor_bounce(speed: float) -> void :

	if not is_finite(speed) or speed <= 0.0 or not can_process(): return
	if bounce_player and not _court_pool.is_empty():
		var volume = clamp(-8.0 + (speed / 15.0) * 8.0 + court_weight_tune * 1.2, -12.0, 2.0)
		bounce_player.stream = _court_pool[_court_speed_bucket(speed)]
		bounce_player.volume_db = volume
		bounce_player.pitch_scale = _audio_rng.randf_range(0.995, 1.005)
		_place_impact_player(bounce_player)
		bounce_player.play()

static func _court_speed_bucket(speed: float) -> int:
	if speed < 2.0: return 0
	if speed < 4.0: return 1
	if speed < 6.0: return 2
	if speed < 8.5: return 3
	if speed < 12.0: return 4
	return 5

func on_body_entered(body: Node, ball_position_y: float, ball_velocity: Vector3) -> void :
	if net_audio_cooldown > 0.0 or not can_process():
		return
	if body == null or not (body is Node3D):
		return
	if not _is_net_body(body):
		return

	var speed = ball_velocity.length()
	if not is_finite(speed) or speed <= 0.0: return
	var is_tape_hit = ball_position_y >= 0.82
	var bucket: = 0 if speed < 4.5 else (1 if speed < 10.5 else 2)
	var pool: = _net_tape_pool if is_tape_hit else _net_mesh_pool
	if pool.is_empty(): return
	net_hit_player.stream = pool[bucket]
	net_hit_player.volume_db = clamp(-11.0 + speed * 0.55, -12.0, -3.0)
	net_hit_player.pitch_scale = _audio_rng.randf_range(0.995, 1.005)
	_place_impact_player(net_hit_player)
	net_hit_player.play()
	net_audio_cooldown = NET_AUDIO_COOLDOWN

func _place_impact_player(player: AudioStreamPlayer3D) -> void :


	var ball: = get_parent() as Node3D
	if ball: player.global_position = ball.global_position

func update_cooldown(delta: float) -> void :
	if net_audio_cooldown > 0.0:
		net_audio_cooldown = max(net_audio_cooldown - delta, 0.0)

func _is_net_body(body: Node) -> bool:
	return body.name == "Net" or body.name.to_lower().contains("net")



func _new_wave() -> AudioStreamWAV:
	var wave = AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.stereo = false
	wave.mix_rate = int(AUDIO_SAMPLE_RATE)
	return wave

func _append_sample(samples: PackedByteArray, value: float) -> void :
	var sample = int(clamp(value * 32767.0, -32768.0, 32767.0))
	samples.append(sample & 255)
	samples.append((sample >> 8) & 255)

func _fade_short_tail(samples: PackedByteArray) -> void :


	var frames: = samples.size() / 2
	var release: = mini(int(AUDIO_SAMPLE_RATE * 0.004), frames)
	for index in range(release):
		var offset: = (frames - release + index) * 2
		var gain: = 1.0 - float(index) / maxf(float(release - 1), 1.0)
		samples.encode_s16(offset, roundi(float(samples.decode_s16(offset)) * gain))

func _exp_env(t: float, attack: float, decay_start: float, decay_rate: float) -> float:
	if t < attack:
		return t / max(attack, 0.0001)
	if t < decay_start:
		return 1.0
	return exp( - (t - decay_start) * decay_rate)



func _create_impact_sound(
	duration: float, 
	amplitude: float, 
	pop_gain: float, 
	body_gain: float, 
	noise_gain: float, 
	pop_decay: float, 
	body_decay: float, 
	attack: float, 
	pitch_scale: float, 
	body_pitch_scale: float
) -> AudioStreamWAV:
	var wave = _new_wave()
	var samples = PackedByteArray()
	var num_samples = int(duration * AUDIO_SAMPLE_RATE)
	var transient_end = attack + 0.002

	for i in range(num_samples):
		var t = float(i) / AUDIO_SAMPLE_RATE

		var pop_env = _exp_env(t, attack, attack, pop_decay)
		var body_env = _exp_env(t, attack * 0.6, transient_end, body_decay)
		var click_env = exp( - t * (pop_decay * 1.8))

		var pop = sin(t * POP_FREQ * pitch_scale * TAU) * 0.72
		var pop_upper = sin(t * POP_UPPER_FREQ * pitch_scale * TAU) * 0.28
		var body = sin(t * BODY_FREQ * body_pitch_scale * TAU) * 0.55
		var body_low = sin(t * BODY_LOW_FREQ * body_pitch_scale * TAU) * 0.25
		var body_high = sin(t * BODY_HIGH_FREQ * body_pitch_scale * TAU) * 0.2
		var click = (_audio_rng.randf() * 2.0 - 1.0) * click_env


		var combined = (
			(pop + pop_upper) * pop_gain * pop_env + 
			(body + body_low + body_high) * body_gain * body_env + 
			click * noise_gain
		)
		_append_sample(samples, combined * amplitude)

	wave.data = samples
	return wave

func _create_paddle_sound(
	duration: float, 
	amplitude: float, 
	_mode_gain: float, 
	_body_gain: float, 
	_click_gain: float, 
	_ring_gain: float, 
	mode_decay: float, 
	body_decay: float, 
	attack: float, 
	mode_pitch_scale: float, 
	body_pitch_scale: float
) -> AudioStreamWAV:
	var wave = _new_wave()
	var samples = PackedByteArray()
	var metallic_scale = 1.0 + paddle_metallic_tune * 0.9
	var anti_metallic_scale = 1.0 - paddle_metallic_tune * 0.45
	var _pitch_scale = 1.0 + paddle_pitch_tune * 0.24 - max(paddle_sub_pitch_tune, 0.0) * 0.1
	var _sub_pitch_scale = 0.78 + paddle_sub_pitch_tune * 0.18
	var _pitch_blend = max(paddle_pitch_blend_tune, 0.0)
	var _low_pitch_blend = max( - paddle_pitch_blend_tune, 0.0)
	var _upper_pitch_scale = 1.0 + paddle_upper_pitch_tune * 0.22
	var _body_pitch_scale_tune = 1.0 + paddle_body_pitch_tune * 0.2
	var _hollow_pitch_scale = 1.0 + paddle_hollow_pitch_tune * 0.24
	var _ring_scale = (1.0 + paddle_ring_tune * 0.8) * metallic_scale
	var _body_scale = (1.0 + paddle_body_tune * 0.7 + paddle_wood_tune * 0.35) * anti_metallic_scale
	var tail_scale = 1.0 + paddle_tail_tune * 0.75
	var _attack_scale = 1.0 + paddle_attack_tune * 0.55
	var _compress_scale = 1.0 + paddle_compress_tune * 0.28
	var _presence_scale = (1.0 + paddle_presence_tune * 0.55) * (1.0 + paddle_metallic_tune * 0.45)
	var dead_scale = 1.0 + paddle_dead_tune * 0.9
	var tuned_amplitude = amplitude
	var echo_mix = max(paddle_echo_tune, 0.0)
	var echo_delay_a = 0.032 + echo_mix * 0.016
	var echo_delay_b = 0.057 + echo_mix * 0.026

	var tail_extra = 0.012 if echo_mix <= 0.0 else (0.028 * tail_scale + echo_delay_b + 0.04)
	var num_samples = int((duration + tail_extra) * AUDIO_SAMPLE_RATE)
	var _peak_window = 0.0045
	var _wood_scale = (1.0 + paddle_wood_tune * 0.45) * anti_metallic_scale
	var _damp_scale = (1.0 + paddle_damp_tune * 0.85) * dead_scale
	var _noise_scale = (1.0 + paddle_noise_tune * 0.9) / dead_scale
	var _hollow_scale = 1.0 + paddle_hollow_tune * 0.9
	var _clack_scale = (1.0 + paddle_clack_tune * 0.9) * (1.0 + paddle_metallic_tune * 0.35)
	var _rumble_scale = 1.0 + paddle_rumble_tune * 0.95
	var _crackle_scale = (1.0 + paddle_crackle_tune * 1.1) * (1.0 + paddle_metallic_tune * 0.55)
	var _reflection_scale = ((1.0 + paddle_reflection_tune * 0.7) * (1.0 + paddle_metallic_tune * 0.25)) / dead_scale
	var _sweet_spot_scale = 1.0 + paddle_sweet_spot_tune * 0.8
	var _off_center_scale = 1.0 - paddle_sweet_spot_tune * 0.55
	var _core_softness_scale = 1.0 + paddle_core_softness_tune * 0.8
	var variation_scale = 1.0 + paddle_variation_tune * 0.8
	var reflection_a_delay = 0.0075 + paddle_reflection_tune * 0.0015
	var reflection_b_delay = 0.014 + paddle_reflection_tune * 0.003
	var _hit_variation = (_audio_rng.randf() * 2.0 - 1.0) * 0.018 * variation_scale
	var click_noise_state = 0.0
	var crackle_noise_state = 0.0
	var dry_signal: PackedFloat32Array = PackedFloat32Array()
	dry_signal.resize(num_samples)

	var chirp_scale = max(paddle_chirp_tune, 0.0) * 0.8 + 0.15
	var _helmholtz_scale = 1.0 + paddle_helmholtz_tune * 0.6
	var contact_duration = 0.002





	var strike_decay = mode_decay
	var helmholtz_decay = mode_decay * 1.4

	for i in range(num_samples):
		var t = float(i) / AUDIO_SAMPLE_RATE
		click_noise_state = lerp(click_noise_state, _audio_rng.randf() * 2.0 - 1.0, 0.18)
		crackle_noise_state = lerp(crackle_noise_state, _audio_rng.randf() * 2.0 - 1.0, 0.32)


		var strike_env_val = _exp_env(t, attack, attack, strike_decay)
		var mode_env_val = _exp_env(t, attack, attack, mode_decay)
		var body_env_val = _exp_env(t, attack * 0.7, attack * 0.7, body_decay)
		var helmholtz_env_val = _exp_env(t, attack * 0.5, attack * 0.5, helmholtz_decay)
		var click_env_val = exp( - t * strike_decay * 2.5)


		var chirp_factor = 1.0
		if t < contact_duration:
			var contact_phase = t / contact_duration
			chirp_factor = 1.0 + (1.0 - contact_phase) * (CONTACT_CHIRP_RANGE / BALL_STRIKE_FREQ) * chirp_scale


		var pitch_delta = 1.0 + paddle_pitch_tune * 0.12
		var body_pitch_delta = 1.0 + paddle_body_pitch_tune * 0.1


		var sf = mode_pitch_scale * pitch_delta * chirp_factor

		var strike = sin(t * BALL_STRIKE_FREQ * sf * TAU) * 0.381
		var strike_harm = sin(t * BALL_STRIKE_FREQ * 1.5 * sf * TAU) * 0.011


		var mf = mode_pitch_scale * pitch_delta * chirp_factor
		var pmode = sin(t * PADDLE_MODE_FREQ * mf * TAU) * 0.138
		var pmode_sub = sin(t * PADDLE_MODE_FREQ * 0.92 * mf * TAU) * 0.035
		var pmode_upper = sin(t * PADDLE_MODE_FREQ * 1.12 * mf * TAU) * 0.027
		var ring = sin(t * PADDLE_RING_FREQ * mf * TAU) * 0.04


		var bf = body_pitch_scale * body_pitch_delta
		var body_total = (
			sin(t * BODY_LOW_FREQ * bf * TAU) * 0.187 + 
			sin(t * BODY_FREQ * bf * TAU) * 0.226 + 
			sin(t * BODY_MID_FREQ * bf * TAU) * 0.226 + 
			sin(t * BODY_UPPER_FREQ * bf * TAU) * 0.187
		)


		var helmholtz = sin(t * BALL_HELMHOLTZ_FREQ * 0.9 * mf * TAU) * 0.558
		var helmholtz_sub = sin(t * BALL_HELMHOLTZ_FREQ * 0.79 * mf * TAU) * 0.222
		var shell_vib = sin(t * BALL_SHELL_FREQ * 0.9 * mf * TAU) * 0.14


		var foam = sin(t * 886.0 * pitch_delta * TAU) * exp( - t * 140.0) * 0.257


		var hi_burst = sin(t * 2500.0 * sf * TAU) * exp( - t * 200.0) * 0.33



		var broad_click = click_noise_state * click_env_val * 0.36


		var combined = (
			(strike + strike_harm) * strike_env_val * _mode_gain + 
			(pmode + pmode_sub + pmode_upper) * mode_env_val * _mode_gain + 
			body_total * body_env_val * _body_gain + 
			(helmholtz + helmholtz_sub + shell_vib) * helmholtz_env_val + 
			ring * exp( - t * mode_decay * 1.2) * minf(_ring_gain * 6.0, 0.3) + 
			foam + 
			broad_click * (0.65 + _click_gain * 2.0) + 
			hi_burst * (0.7 + _click_gain)
		)




		if t > reflection_a_delay:
			var ta = t - reflection_a_delay
			var reflect_a_env = exp( - ta * 120.0)
			var reflect_a = (
				sin(ta * BALL_STRIKE_FREQ * sf * TAU) * 0.12 + 
				sin(ta * PADDLE_MODE_FREQ * mf * TAU) * 0.04 + 
				sin(ta * BODY_MID_FREQ * bf * TAU) * 0.05
			) * reflect_a_env
			combined += reflect_a * 0.04

		if t > reflection_b_delay:
			var tb = t - reflection_b_delay
			var reflect_b_env = exp( - tb * 150.0)
			var reflect_b = (
				sin(tb * BALL_STRIKE_FREQ * sf * TAU) * 0.1 + 
				sin(tb * BALL_HELMHOLTZ_FREQ * mf * TAU) * 0.03
			) * reflect_b_env
			combined += reflect_b * 0.02

		dry_signal[i] = combined * tuned_amplitude

	var echo_samples_a = int(echo_delay_a * AUDIO_SAMPLE_RATE)
	var echo_samples_b = int(echo_delay_b * AUDIO_SAMPLE_RATE)
	var echo_gain_a = echo_mix * 0.16
	var echo_gain_b = echo_mix * 0.1
	var room_gain = max(paddle_reflection_tune, 0.0) * 0.035
	for i in range(num_samples):
		var sample_value = dry_signal[i]
		if room_gain > 0.0:
			var room_index = i - int(0.028 * AUDIO_SAMPLE_RATE)
			if room_index >= 0:
				sample_value += dry_signal[room_index] * room_gain
		if echo_gain_a > 0.0:
			var delayed_a = i - echo_samples_a
			if delayed_a >= 0:
				var echo_env_a = exp( - float(delayed_a) / AUDIO_SAMPLE_RATE * 18.0)
				var echo_a = dry_signal[delayed_a]
				if delayed_a > 0:
					echo_a = (echo_a + dry_signal[delayed_a - 1]) * 0.5
				sample_value += echo_a * echo_gain_a * echo_env_a
		if echo_gain_b > 0.0:
			var delayed_b = i - echo_samples_b
			if delayed_b >= 0:
				var echo_env_b = exp( - float(delayed_b) / AUDIO_SAMPLE_RATE * 24.0)
				var echo_b = dry_signal[delayed_b]
				if delayed_b > 1:
					echo_b = (echo_b + dry_signal[delayed_b - 1] + dry_signal[delayed_b - 2]) / 3.0
				sample_value += echo_b * echo_gain_b * echo_env_b
		var fade_out: = clampf(float(num_samples - 1 - i) / (AUDIO_SAMPLE_RATE * 0.004), 0.0, 1.0)
		_append_sample(samples, tanh(sample_value * 0.92) * 0.82 * fade_out)

	wave.data = samples
	return wave



func _create_thock_sound_at(speed: float, hit_quality: float) -> AudioStreamWAV:
	var speed_ratio: float = clamp(speed / 12.0, 0.0, 1.0)
	var pitch_var: float = lerp(-0.18, 0.03, hit_quality) * (1.0 - hit_quality * 0.75)
	var body_decay_v: float = lerp(22.0 + hit_quality * 58.0, 60.0 + hit_quality * 97.0, 0.5)
	var body_pitch_v: float = lerp(0.75, 1.0, hit_quality)
	var dur_v: float = lerp(0.032 + hit_quality * 0.008, 0.05 + hit_quality * 0.022, 0.5)
	return _create_paddle_sound(
		dur_v, 0.56, 1.0, 1.0, 0.12, 0.025, 68.5, body_decay_v, 0.0002, 
		1.0 + speed_ratio * 0.02 + pitch_var, body_pitch_v
	)

func _create_volley_sound_at(hit_quality: float) -> AudioStreamWAV:
	var pitch_var: float = lerp(-0.2, 0.02, hit_quality) * (1.0 - hit_quality * 0.65)
	var body_decay_v: float = lerp(18.0 + hit_quality * 45.0, 50.0 + hit_quality * 93.0, 0.5)
	var body_pitch_v: float = lerp(0.7, 0.97, hit_quality)
	var dur_v: float = lerp(0.032 + hit_quality * 0.004, 0.052 + hit_quality * 0.016, 0.5)
	return _create_paddle_sound(
		dur_v, 0.44, 0.85, 0.95, 0.06, 0.008, 61.3, body_decay_v, 0.00035, 
		0.96 + pitch_var, body_pitch_v
	)

func _create_smash_sound_at(hit_quality: float) -> AudioStreamWAV:
	var pitch_var: float = lerp(-0.1, 0.04, hit_quality) * (1.0 - hit_quality * 0.7)
	var body_decay_v: float = lerp(35.0 + hit_quality * 65.0, 80.0 + hit_quality * 77.0, 0.5)
	var body_pitch_v: float = lerp(0.8, 1.01, hit_quality)
	var dur_v: float = lerp(0.022 + hit_quality * 0.005, 0.034 + hit_quality * 0.014, 0.5)
	return _create_paddle_sound(
		dur_v, 0.68, 1.1, 0.9, 0.18, 0.05, 50.0, body_decay_v, 0.00015, 
		1.03 + pitch_var, body_pitch_v
	)



func _create_rim_hit_sound_at(hit_quality: float) -> AudioStreamWAV:


	var wave: = _new_wave()
	var samples: = PackedByteArray()
	var duration: float = lerp(0.025, 0.04, hit_quality)
	var num_samples: = int(duration * AUDIO_SAMPLE_RATE)
	var pitch_var: float = lerp(0.76, 0.94, hit_quality)
	var body_pitch_v: float = lerp(0.7, 0.9, hit_quality)
	var mode_decay: float = lerp(42.0, 70.0, hit_quality)
	var body_decay: float = lerp(22.0, 52.0, hit_quality)

	for i in range(num_samples):
		var t: float = float(i) / AUDIO_SAMPLE_RATE
		var strike_env: = exp( - t * 88.0)
		var mode_env: = exp( - t * mode_decay)
		var body_env: = exp( - t * body_decay)
		var rim_env: = exp( - t * 125.0)
		var helm_env: = exp( - t * 105.0)
		var click_env: = exp( - t * 420.0)


		var strike: = sin(t * BALL_STRIKE_FREQ * pitch_var * TAU) * 0.26


		var pmode: = sin(t * PADDLE_MODE_FREQ * pitch_var * 0.88 * TAU) * 0.09
		var pmode_s: = sin(t * PADDLE_MODE_FREQ * pitch_var * 0.44 * TAU) * 0.04


		var body1: = sin(t * 250.0 * body_pitch_v * TAU) * 0.16
		var body2: = sin(t * 185.0 * body_pitch_v * TAU) * 0.1


		var rim_ring: = sin(t * 2050.0 * pitch_var * TAU) * 0.18
		var rim_harm: = sin(t * 3100.0 * pitch_var * TAU) * 0.06


		var helmholtz: = sin(t * BALL_HELMHOLTZ_FREQ * pitch_var * TAU) * 0.2


		var click: = (_audio_rng.randf() * 2.0 - 1.0) * 0.1 * click_env

		var combined: = (
			strike * strike_env + 
			(pmode + pmode_s) * mode_env + 
			(body1 + body2) * body_env + 
			(rim_ring + rim_harm) * rim_env + 
			helmholtz * helm_env + 
			click
		)
		_append_sample(samples, combined * 0.5)

	wave.data = samples
	return wave



func _create_frame_hit_sound_at(hit_quality: float) -> AudioStreamWAV:


	var wave: = _new_wave()
	var samples: = PackedByteArray()
	var duration: float = lerp(0.018, 0.032, hit_quality)
	var num_samples: = int(duration * AUDIO_SAMPLE_RATE)
	var pitch_var: float = lerp(0.8, 1.06, hit_quality)
	var ring_decay: float = lerp(165.0, 115.0, hit_quality)

	for i in range(num_samples):
		var t: float = float(i) / AUDIO_SAMPLE_RATE
		var ring_env: = exp( - t * ring_decay)
		var body_env: = exp( - t * 130.0)
		var click_env: = exp( - t * 520.0)


		var frame_primary: = sin(t * 2800.0 * pitch_var * TAU) * 0.55
		var frame_harm2: = sin(t * 4200.0 * pitch_var * TAU) * 0.14
		var frame_harm3: = sin(t * 5600.0 * pitch_var * TAU) * 0.07


		var body_thud: = sin(t * 310.0 * TAU) * 0.11


		var click: = (_audio_rng.randf() * 2.0 - 1.0) * 0.2 * click_env

		var combined: = (
			(frame_primary + frame_harm2 + frame_harm3) * ring_env + 
			body_thud * body_env * 0.38 + 
			click
		)
		_append_sample(samples, combined * 0.46)

	wave.data = samples
	return wave



func _create_thock_sound(speed: float) -> AudioStreamWAV:
	return _create_thock_sound_at(speed, sqrt(_audio_rng.randf()))

func _create_volley_sound() -> AudioStreamWAV:
	return _create_volley_sound_at(_audio_rng.randf())

func _create_smash_sound() -> AudioStreamWAV:
	var hit_quality: float = pow(_audio_rng.randf(), 0.4)
	var pitch_var: float = _audio_rng.randf_range(-0.1, 0.04) * (1.0 - hit_quality * 0.7)
	var body_decay_v: float = _audio_rng.randf_range(35.0 + hit_quality * 65.0, 80.0 + hit_quality * 77.0)
	var body_pitch_v: float = lerp(0.8, 1.01, hit_quality) + _audio_rng.randf_range(-0.02, 0.02)
	var dur_v: float = _audio_rng.randf_range(0.022 + hit_quality * 0.005, 0.034 + hit_quality * 0.014)
	return _create_paddle_sound(
		dur_v, 
		0.68, 
		1.1, 
		0.9, 
		0.18, 
		0.05, 
		50.0, 
		body_decay_v, 
		0.00015, 
		1.03 + pitch_var, 
		body_pitch_v
	)

func _create_serve_sound() -> AudioStreamWAV:

	return _create_paddle_sound(
		0.028, 
		0.62, 
		1.0, 
		1.0, 
		0.1, 
		0.03, 
		205.0, 
		112.0, 
		0.0002, 
		1.0, 
		1.0
	)

func _create_court_bounce_sound(speed: float) -> AudioStreamWAV:



	var speed_ratio = clamp(speed / 10.0, 0.0, 1.0)
	var wave = _new_wave()
	var samples = PackedByteArray()
	var court_tone_scale = 1.0 + court_snap_tune * 0.12
	var court_weight_scale = 1.0 + court_weight_tune * 0.55
	var court_amp_scale = 1.0 + court_weight_tune * 0.12
	var court_decay_scale = 1.0 + court_decay_tune * 0.8
	var court_hardness_scale = 1.0 + court_hardness_tune * 0.65
	var court_surface_scale = 1.0 + court_surface_tune * 0.35
	var duration = 0.02 + speed_ratio * 0.008 + max(court_decay_tune, 0.0) * 0.006
	var num_samples = int(duration * AUDIO_SAMPLE_RATE)

	for i in range(num_samples):
		var t = float(i) / AUDIO_SAMPLE_RATE

		var thwack_env = _exp_env(t, max(0.0006 - court_snap_tune * 0.0002, 0.0002), 0.0006, (125.0 + court_snap_tune * 18.0) / court_decay_scale)
		var weight_env = _exp_env(t, 0.0004, 0.0016 * court_decay_scale, 48.0 / court_decay_scale)
		var click_env = exp( - t * (180.0 + court_snap_tune * 35.0 + court_hardness_tune * 40.0))


		var thwack = sin(t * COURT_BOUNCE_FREQ * court_tone_scale * court_hardness_scale * court_surface_scale * TAU) * 0.65
		var thwack_upper = sin(t * COURT_BOUNCE_UPPER_FREQ * court_tone_scale * court_hardness_scale * court_surface_scale * TAU) * 0.22

		var weight = sin(t * COURT_BOUNCE_BODY_FREQ * TAU) * 0.55
		var weight_sub = sin(t * (COURT_BOUNCE_BODY_FREQ * 0.72) * TAU) * 0.18

		var slap = sin(t * 920.0 * court_hardness_scale * court_surface_scale * TAU) * 0.1

		var ball_ring = sin(t * BALL_HELMHOLTZ_FREQ * 0.85 * TAU) * 0.06
		var click = (_audio_rng.randf() * 2.0 - 1.0) * click_env
		var combined = (
			(thwack + thwack_upper) * 0.52 * thwack_env + 
			(weight + weight_sub) * 0.32 * court_weight_scale * weight_env + 
			ball_ring * 0.15 * thwack_env + 
			slap * max(court_hardness_tune, 0.0) * 0.3 * thwack_env + 
			click * (0.035 + court_snap_tune * 0.015 + court_hardness_tune * 0.008)
		)
		_append_sample(samples, combined * (0.45 + speed_ratio * 0.12) * court_amp_scale)

	_fade_short_tail(samples)
	wave.data = samples
	return wave

func _create_net_tape_sound(speed: float) -> AudioStreamWAV:
	var speed_ratio = clamp(speed / 10.0, 0.0, 1.0)
	var wave = _new_wave()
	var samples = PackedByteArray()
	var duration = 0.045 + speed_ratio * 0.012
	var num_samples = int(duration * AUDIO_SAMPLE_RATE)

	for i in range(num_samples):
		var t = float(i) / AUDIO_SAMPLE_RATE
		var attack_env = _exp_env(t, 0.0015, 0.0035, 42.0)
		var tape = sin(t * NET_TAPE_FREQ * TAU) * 0.58
		var tape_low = sin(t * 430.0 * TAU) * 0.24
		var flap = (_audio_rng.randf() * 2.0 - 1.0) * exp( - t * 34.0)
		var combined = (tape + tape_low) * 0.52 * attack_env + flap * 0.1
		_append_sample(samples, combined * (0.42 + speed_ratio * 0.1))

	_fade_short_tail(samples)
	wave.data = samples
	return wave

func _create_net_mesh_sound(speed: float) -> AudioStreamWAV:
	var speed_ratio = clamp(speed / 10.0, 0.0, 1.0)
	var wave = _new_wave()
	var samples = PackedByteArray()
	var duration = 0.07 + speed_ratio * 0.02
	var num_samples = int(duration * AUDIO_SAMPLE_RATE)

	for i in range(num_samples):
		var t = float(i) / AUDIO_SAMPLE_RATE
		var stretch_env = _exp_env(t, 0.0025, 0.006, 28.0)
		var rustle_env = exp( - t * 18.0)
		var rustle = (_audio_rng.randf() * 2.0 - 1.0) * (
			0.6 * sin(t * NET_MESH_FREQ * TAU) + 
			0.4 * sin(t * 5400.0 * TAU)
		)
		var body = sin(t * 320.0 * TAU) * 0.14
		var combined = rustle * 0.22 * rustle_env + body * 0.18 * stretch_env
		_append_sample(samples, combined * (0.34 + speed_ratio * 0.08))

	_fade_short_tail(samples)
	wave.data = samples
	return wave
