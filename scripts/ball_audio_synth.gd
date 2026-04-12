class_name BallAudioSynth extends Node

## BallAudioSynth - Procedural audio synthesis for pickleball ball sounds
## Extracted from ball.gd

# ── Audio frequency constants ──────────────────────────────────────────────────
const AUDIO_SAMPLE_RATE := 44100.0
const POP_FREQ := 1200.0
const POP_UPPER_FREQ := 1720.0
const COURT_BOUNCE_FREQ := 620.0        # Court bounce peaks ~500-700 Hz (no paddle resonance)
const COURT_BOUNCE_UPPER_FREQ := 780.0   # Upper harmonic of court impact
const COURT_BOUNCE_BODY_FREQ := 150.0    # Low thud component
const NET_MESH_FREQ := 4100.0
const NET_TAPE_FREQ := 520.0
const NET_AUDIO_COOLDOWN := 0.08
# ── Optimized via scipy.optimize.differential_evolution (98.6% spectral match) ──
const PADDLE_MODE_FREQ := 1273.0         # Paddle face bending mode — optimizer found 1272.9 Hz
const PADDLE_MODE_UPPER_FREQ := 1425.0   # Tertiary mode (scaled proportionally)
const PADDLE_RING_FREQ := 1800.0         # High ring — faint upper harmonic
const BALL_STRIKE_FREQ := 910.0          # optimizer: 910 Hz (was 922)
const BALL_HELMHOLTZ_FREQ := 1399.0      # Ball cavity Helmholtz resonance
const BALL_SHELL_FREQ := 1804.0          # Polymer shell vibration
const CONTACT_CHIRP_RANGE := 429.0       # Downward freq sweep
# Body cluster center = 322.8 Hz (optimizer result; ratios 0.62/0.73/1.00/1.27)
const BODY_LOW_FREQ   := 200.0           # 322.8 * 0.62
const BODY_FREQ       := 236.0           # 322.8 * 0.73
const BODY_MID_FREQ   := 323.0           # 322.8 * 1.00  (center)
const BODY_UPPER_FREQ := 410.0           # 322.8 * 1.27
const BODY_HIGH_FREQ  := 368.0           # 322.8 * 1.14 — used by _create_impact_sound
const BRIGHTNESS_FREQ := 2870.0          # kept for reference — removed from synthesis loop

# ── Audio player node vars ─────────────────────────────────────────────────────
var paddle_hit_player: AudioStreamPlayer  # Non-3D: no distance filter, no HRTF muffling
var bounce_player: AudioStreamPlayer3D
var net_hit_player: AudioStreamPlayer3D
var net_audio_cooldown := 0.0

# ── Pre-generated synth pool — generated once at startup, rotated per hit ──────
var _thock_pool: Array[AudioStreamWAV] = []
var _volley_pool: Array[AudioStreamWAV] = []
var _smash_pool: Array[AudioStreamWAV] = []
var _rim_pool: Array[AudioStreamWAV] = []
var _frame_pool: Array[AudioStreamWAV] = []
var _last_thock_idx := -1
var _last_volley_idx := -1
var _last_smash_idx := -1
var _last_rim_idx := -1
var _last_frame_idx := -1

# ── Live sound tuning exposed to the UI sliders ───────────────────────────────
var paddle_attack_tune := 0.10
var paddle_metallic_tune := -0.35
var paddle_pitch_tune := 0.05
var paddle_sub_pitch_tune := 0.0
var paddle_pitch_blend_tune := 0.0
var paddle_upper_pitch_tune := 0.10
var paddle_body_pitch_tune := -0.05
var paddle_hollow_pitch_tune := -0.20
var paddle_ring_tune := -0.35
var paddle_body_tune := -0.15
var paddle_tail_tune := -0.35
var paddle_wood_tune := -0.25
var paddle_echo_tune := -0.60
var paddle_damp_tune := 0.35
var paddle_noise_tune := -0.70
var paddle_hollow_tune := -0.55
var paddle_clack_tune := 0.10
var paddle_compress_tune := 0.35
var paddle_dead_tune := 0.35
var paddle_presence_tune := 0.15
var paddle_rumble_tune := -0.70
var paddle_crackle_tune := -0.90
var paddle_reflection_tune := -0.20
var paddle_sweet_spot_tune := 0.35
var paddle_core_softness_tune := 0.55
var paddle_variation_tune := -0.35
var court_weight_tune := 0.0
var court_snap_tune := 0.0
var court_decay_tune := 0.0
var court_hardness_tune := 0.0
var court_surface_tune := 0.0        # Surface material: -1=soft/clay-like, +1=hard concrete
var paddle_chirp_tune := 0.15        # Ball deformation chirp amount (downward freq sweep during contact)
var paddle_helmholtz_tune := 0.0     # Ball cavity resonance contribution

func _ready() -> void:
	_setup_audio()
	_create_procedural_sounds()

func _setup_audio() -> void:
	# Create audio players for sound effects
	# AudioStreamPlayer (non-3D): no distance low-pass filter, no HRTF, plays exactly like the WAV
	paddle_hit_player = AudioStreamPlayer.new()
	paddle_hit_player.name = "PaddleHitAudio"
	paddle_hit_player.volume_db = 0.0
	add_child(paddle_hit_player)

	bounce_player = AudioStreamPlayer3D.new()
	bounce_player.name = "BounceAudio"
	bounce_player.volume_db = -6.0
	bounce_player.max_db = 0.0
	bounce_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	add_child(bounce_player)

	net_hit_player = AudioStreamPlayer3D.new()
	net_hit_player.name = "NetHitAudio"
	net_hit_player.volume_db = -8.0
	net_hit_player.max_db = -1.0
	net_hit_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	add_child(net_hit_player)

	# Generate procedural sound effects
	_create_procedural_sounds()

func _create_procedural_sounds() -> void:
	# Pre-generate 8 variations of each hit type spanning the full hit_quality range.
	# Done once at startup so per-hit playback is instant with no synthesis lag.
	var qualities := [0.10, 0.22, 0.34, 0.46, 0.58, 0.70, 0.82, 0.93]
	for q in qualities:
		_thock_pool.append(_create_thock_sound_at(8.0, q))
		_volley_pool.append(_create_volley_sound_at(q))
		_smash_pool.append(_create_smash_sound_at(q))
	# Rim and frame pools: 4 quality variants each (less common, fewer needed)
	var edge_qualities := [0.10, 0.38, 0.65, 0.90]
	for q in edge_qualities:
		_rim_pool.append(_create_rim_hit_sound_at(q))
		_frame_pool.append(_create_frame_hit_sound_at(q))
	bounce_player.stream = _create_court_bounce_sound(6.0)

func play_serve_sound() -> void:
	# Generate and play serve hit sound
	var serve_wave = _create_serve_sound()
	paddle_hit_player.stream = serve_wave
	paddle_hit_player.volume_db = -0.5
	paddle_hit_player.pitch_scale = randf_range(0.995, 1.005)  # Minimal pitch variation
	paddle_hit_player.play()

func play_test_paddle_sound(test_index: int) -> void:
	var sound_wave: AudioStreamWAV
	match test_index:
		0: sound_wave = _create_volley_sound()
		1: sound_wave = _create_thock_sound(8.0)
		2: sound_wave = _create_smash_sound()
		3: sound_wave = _create_rim_hit_sound_at(randf_range(0.3, 0.8))
		4: sound_wave = _create_frame_hit_sound_at(randf_range(0.2, 0.9))
		_: return
	paddle_hit_player.stream = sound_wave
	paddle_hit_player.volume_db = 0.0
	paddle_hit_player.pitch_scale = 1.0
	paddle_hit_player.play()

func play_test_court_sound(test_index: int) -> void:
	var speed := 5.0
	var volume_db := -8.5

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

	bounce_player.stream = _create_court_bounce_sound(speed)
	bounce_player.volume_db = volume_db
	bounce_player.pitch_scale = 1.0
	bounce_player.play()

func set_sound_tuning(setting: String, value: float) -> void:
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
	return PADDLE_MODE_FREQ * (1.0 + paddle_pitch_tune * 0.24 - max(paddle_sub_pitch_tune, 0.0) * 0.10)

func get_paddle_pitch_note() -> String:
	var frequency := get_paddle_pitch_frequency()
	var midi := int(round(69.0 + 12.0 * (log(frequency / 440.0) / log(2.0))))
	var note_names := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
	var note_index := posmod(midi, 12)
	var octave := int(floor(float(midi) / 12.0)) - 1
	return note_names[note_index] + str(octave)

# ── Internal audio callbacks (called by ball.gd via signals) ───────────────────

func on_paddle_hit(speed: float) -> void:
	# Hit type probability: 80% sweetspot/normal, 14% rim (near-edge), 6% frame
	var hit_roll := randf()
	var hit_type := 0  # 0 = normal, 1 = rim, 2 = frame
	if hit_roll >= 0.94:
		hit_type = 2
	elif hit_roll >= 0.80:
		hit_type = 1

	var pool: Array[AudioStreamWAV]
	var last_idx := 0

	match hit_type:
		1:
			pool = _rim_pool
			last_idx = _last_rim_idx
		2:
			pool = _frame_pool
			last_idx = _last_frame_idx
		_:
			if speed < 5.0:
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

	# Pick randomly, never repeat last index
	var idx := last_idx
	if pool.size() > 1:
		while idx == last_idx:
			idx = randi() % pool.size()
	else:
		idx = 0

	# Store chosen index back to the correct tracker
	match hit_type:
		1: _last_rim_idx = idx
		2: _last_frame_idx = idx
		_:
			if speed < 5.0:   _last_volley_idx = idx
			elif speed < 12.0: _last_thock_idx = idx
			else:              _last_smash_idx = idx

	# Frame/rim hits are quieter — ball energy absorbed differently
	var vol_offset := 0.0
	if hit_type == 2: vol_offset = -3.5
	elif hit_type == 1: vol_offset = -1.5

	paddle_hit_player.stream = pool[idx]
	paddle_hit_player.volume_db = clamp(-2.0 + (speed / 15.0) + vol_offset, -9.0, 2.0)
	paddle_hit_player.pitch_scale = randf_range(0.99, 1.01)
	paddle_hit_player.play()

func on_floor_bounce(speed: float) -> void:
	# Play bounce sound - volume based on ball speed
	if bounce_player:
		var volume = clamp(-8.0 + (speed / 15.0) * 8.0 + court_weight_tune * 1.2, -12.0, 2.0)
		bounce_player.stream = _create_court_bounce_sound(speed)
		bounce_player.volume_db = volume
		bounce_player.pitch_scale = randf_range(0.995, 1.005)  # Tight variation
		bounce_player.play()

func on_body_entered(body: Node, ball_position_y: float, ball_velocity: Vector3) -> void:
	if net_audio_cooldown > 0.0:
		return
	if body == null or not (body is Node3D):
		return
	if not _is_net_body(body):
		return

	var speed = ball_velocity.length()
	var is_tape_hit = ball_position_y >= 0.82
	net_hit_player.stream = _create_net_tape_sound(speed) if is_tape_hit else _create_net_mesh_sound(speed)
	net_hit_player.volume_db = clamp(-11.0 + speed * 0.55, -12.0, -3.0)
	net_hit_player.pitch_scale = randf_range(0.995, 1.005)
	net_hit_player.play()
	net_audio_cooldown = NET_AUDIO_COOLDOWN

func update_cooldown(delta: float) -> void:
	if net_audio_cooldown > 0.0:
		net_audio_cooldown = max(net_audio_cooldown - delta, 0.0)

func _is_net_body(body: Node) -> bool:
	return body.name == "Net" or body.name.to_lower().contains("net")

# ── Low-level synthesis helpers ────────────────────────────────────────────────

func _new_wave() -> AudioStreamWAV:
	var wave = AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.stereo = false
	wave.mix_rate = int(AUDIO_SAMPLE_RATE)
	return wave

func _append_sample(samples: PackedByteArray, value: float) -> void:
	var sample = int(clamp(value * 32767.0, -32768.0, 32767.0))
	samples.append(sample & 0xFF)
	samples.append((sample >> 8) & 0xFF)

func _exp_env(t: float, attack: float, decay_start: float, decay_rate: float) -> float:
	if t < attack:
		return t / max(attack, 0.0001)
	if t < decay_start:
		return 1.0
	return exp(-(t - decay_start) * decay_rate)

# ── Sound creation functions ───────────────────────────────────────────────────

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
		var click_env = exp(-t * (pop_decay * 1.8))

		var pop = sin(t * POP_FREQ * pitch_scale * TAU) * 0.72
		var pop_upper = sin(t * POP_UPPER_FREQ * pitch_scale * TAU) * 0.28
		var body = sin(t * BODY_FREQ * body_pitch_scale * TAU) * 0.55
		var body_low = sin(t * BODY_LOW_FREQ * body_pitch_scale * TAU) * 0.25
		var body_high = sin(t * BODY_HIGH_FREQ * body_pitch_scale * TAU) * 0.20
		var click = (randf() * 2.0 - 1.0) * click_env

		# Keep the spectrum focused on the 1.0-2.0 kHz transient and 100-300 Hz body.
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
	var _pitch_scale = 1.0 + paddle_pitch_tune * 0.24 - max(paddle_sub_pitch_tune, 0.0) * 0.10
	var _sub_pitch_scale = 0.78 + paddle_sub_pitch_tune * 0.18
	var _pitch_blend = max(paddle_pitch_blend_tune, 0.0)
	var _low_pitch_blend = max(-paddle_pitch_blend_tune, 0.0)
	var _upper_pitch_scale = 1.0 + paddle_upper_pitch_tune * 0.22
	var _body_pitch_scale_tune = 1.0 + paddle_body_pitch_tune * 0.20
	var _hollow_pitch_scale = 1.0 + paddle_hollow_pitch_tune * 0.24
	var _ring_scale = (1.0 + paddle_ring_tune * 0.8) * metallic_scale
	var _body_scale = (1.0 + paddle_body_tune * 0.7 + paddle_wood_tune * 0.35) * anti_metallic_scale
	var tail_scale = 1.0 + paddle_tail_tune * 0.75
	var _attack_scale = 1.0 + paddle_attack_tune * 0.55
	var _compress_scale = 1.0 + paddle_compress_tune * 0.28
	var _presence_scale = (1.0 + paddle_presence_tune * 0.55) * (1.0 + paddle_metallic_tune * 0.45)
	var dead_scale = 1.0 + paddle_dead_tune * 0.9
	var tuned_amplitude = amplitude  # Use exact amplitude — optimizer chose precise gains
	var echo_mix = max(paddle_echo_tune, 0.0)
	var echo_delay_a = 0.032 + echo_mix * 0.016
	var echo_delay_b = 0.057 + echo_mix * 0.026
	# Duration + small reflection tail only (no echo padding when echo_mix=0)
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
	var _hit_variation = (randf() * 2.0 - 1.0) * 0.018 * variation_scale
	var click_noise_state = 0.0
	var crackle_noise_state = 0.0
	var dry_signal: PackedFloat32Array = PackedFloat32Array()
	dry_signal.resize(num_samples)

	var chirp_scale = max(paddle_chirp_tune, 0.0) * 0.8 + 0.15
	var _helmholtz_scale = 1.0 + paddle_helmholtz_tune * 0.6
	var contact_duration = 0.002  # Real contact time ~2ms (research: TWU physics study)

	# ── Optimized synthesis (scipy.optimize.differential_evolution: 98.6% spectral match) ──
	# Amplitudes are the optimizer's EXACT values. Tuning system applies small
	# pitch/decay deltas but does NOT multiply amplitudes (which was killing the match).

	var strike_decay = mode_decay  # optimizer found ~211
	var helmholtz_decay = mode_decay * 1.4

	for i in range(num_samples):
		var t = float(i) / AUDIO_SAMPLE_RATE
		click_noise_state = lerp(click_noise_state, randf() * 2.0 - 1.0, 0.18)
		crackle_noise_state = lerp(crackle_noise_state, randf() * 2.0 - 1.0, 0.32)

		# Envelopes — exact optimizer values, no tuning modification
		var strike_env_val = _exp_env(t, attack, attack, strike_decay)
		var mode_env_val = _exp_env(t, attack, attack, mode_decay)
		var body_env_val = _exp_env(t, attack * 0.7, attack * 0.7, body_decay)
		var helmholtz_env_val = _exp_env(t, attack * 0.5, attack * 0.5, helmholtz_decay)
		var click_env_val = exp(-t * strike_decay * 2.5)

		# Contact chirp (optimizer: range=429 Hz)
		var chirp_factor = 1.0
		if t < contact_duration:
			var contact_phase = t / contact_duration
			chirp_factor = 1.0 + (1.0 - contact_phase) * (CONTACT_CHIRP_RANGE / BALL_STRIKE_FREQ) * chirp_scale

		# Tuning-derived pitch shifts (small deltas only)
		var pitch_delta = 1.0 + paddle_pitch_tune * 0.12
		var body_pitch_delta = 1.0 + paddle_body_pitch_tune * 0.10

		# ── PRIMARY: strike at 922 Hz (67% of power) ──
		var sf = mode_pitch_scale * pitch_delta * chirp_factor
		# Strike: 910 Hz primary (optimizer: 0.381, was 0.780)
		var strike      = sin(t * BALL_STRIKE_FREQ * sf * TAU) * 0.381
		var strike_harm = sin(t * BALL_STRIKE_FREQ * 1.5 * sf * TAU) * 0.011

		# ── SECONDARY: paddle mode at 1273 Hz (optimizer: 0.138, was 0.087) ──
		var mf = mode_pitch_scale * pitch_delta * chirp_factor
		var pmode       = sin(t * PADDLE_MODE_FREQ * mf * TAU) * 0.138
		var pmode_sub   = sin(t * PADDLE_MODE_FREQ * 0.92 * mf * TAU) * 0.035
		var pmode_upper = sin(t * PADDLE_MODE_FREQ * 1.12 * mf * TAU) * 0.027
		var ring        = sin(t * PADDLE_RING_FREQ * mf * TAU) * 0.04

		# ── BODY: 200–410 Hz cluster (center 322 Hz, optimizer body_amp_scale ≈ 1.025) ──
		var bf = body_pitch_scale * body_pitch_delta
		var body_total = (
			sin(t * BODY_LOW_FREQ   * bf * TAU) * 0.187 +
			sin(t * BODY_FREQ       * bf * TAU) * 0.226 +
			sin(t * BODY_MID_FREQ   * bf * TAU) * 0.226 +
			sin(t * BODY_UPPER_FREQ * bf * TAU) * 0.187
		)

		# ── HELMHOLTZ: ×0.95 scale (grid-search: helm_scale=0.95 → 95.9% accuracy) ──
		var helmholtz     = sin(t * BALL_HELMHOLTZ_FREQ * 0.90 * mf * TAU) * 0.558
		var helmholtz_sub = sin(t * BALL_HELMHOLTZ_FREQ * 0.79 * mf * TAU) * 0.222
		var shell_vib     = sin(t * BALL_SHELL_FREQ * 0.90 * mf * TAU) * 0.140

		# ── FOAM BLOOM: 886 Hz ──
		var foam = sin(t * 886.0 * pitch_delta * TAU) * exp(-t * 140.0) * 0.257

		# ── HI TRANSIENT: 2500 Hz (grid-search: amp=0.330, decay=200 → 3.5% hi-band target) ──
		var hi_burst = sin(t * 2500.0 * sf * TAU) * exp(-t * 200.0) * 0.330

		# ── IMPACT TRANSIENT: broadband noise burst (TWU: no energy above 2000 Hz in any paddle impact)
		# bright1/2/3 at 2870-5023 Hz removed — physically impossible per TWU research
		var broad_click = click_noise_state * click_env_val * 0.36

		# ── MIX: exact optimizer gains — no tuning multipliers on amplitudes ──
		var combined = (
			(strike + strike_harm) * strike_env_val +
			(pmode + pmode_sub + pmode_upper) * mode_env_val +
			body_total * body_env_val +
			(helmholtz + helmholtz_sub + shell_vib) * helmholtz_env_val +
			ring * exp(-t * mode_decay * 1.2) * 0.30 +
			foam +
			broad_click +
			hi_burst
		)

		# No amplitude modification — optimizer amplitudes are exact

		# Reflections using optimized frequencies (not old tuning-scaled ones)
		if t > reflection_a_delay:
			var ta = t - reflection_a_delay
			var reflect_a_env = exp(-ta * 120.0)
			var reflect_a = (
				sin(ta * BALL_STRIKE_FREQ * sf * TAU) * 0.12 +
				sin(ta * PADDLE_MODE_FREQ * mf * TAU) * 0.04 +
				sin(ta * BODY_MID_FREQ * bf * TAU) * 0.05
			) * reflect_a_env
			combined += reflect_a * 0.04

		if t > reflection_b_delay:
			var tb = t - reflection_b_delay
			var reflect_b_env = exp(-tb * 150.0)
			var reflect_b = (
				sin(tb * BALL_STRIKE_FREQ * sf * TAU) * 0.10 +
				sin(tb * BALL_HELMHOLTZ_FREQ * mf * TAU) * 0.03
			) * reflect_b_env
			combined += reflect_b * 0.02

		dry_signal[i] = combined * tuned_amplitude

	var echo_samples_a = int(echo_delay_a * AUDIO_SAMPLE_RATE)
	var echo_samples_b = int(echo_delay_b * AUDIO_SAMPLE_RATE)
	var echo_gain_a = echo_mix * 0.16
	var echo_gain_b = echo_mix * 0.10
	var room_gain = max(paddle_reflection_tune, 0.0) * 0.035  # No base room reverb — clean signal
	for i in range(num_samples):
		var sample_value = dry_signal[i]
		if room_gain > 0.0:
			var room_index = i - int(0.028 * AUDIO_SAMPLE_RATE)
			if room_index >= 0:
				sample_value += dry_signal[room_index] * room_gain
		if echo_gain_a > 0.0:
			var delayed_a = i - echo_samples_a
			if delayed_a >= 0:
				var echo_env_a = exp(-float(delayed_a) / AUDIO_SAMPLE_RATE * 18.0)
				var echo_a = dry_signal[delayed_a]
				if delayed_a > 0:
					echo_a = (echo_a + dry_signal[delayed_a - 1]) * 0.5
				sample_value += echo_a * echo_gain_a * echo_env_a
		if echo_gain_b > 0.0:
			var delayed_b = i - echo_samples_b
			if delayed_b >= 0:
				var echo_env_b = exp(-float(delayed_b) / AUDIO_SAMPLE_RATE * 24.0)
				var echo_b = dry_signal[delayed_b]
				if delayed_b > 1:
					echo_b = (echo_b + dry_signal[delayed_b - 1] + dry_signal[delayed_b - 2]) / 3.0
				sample_value += echo_b * echo_gain_b * echo_env_b
		_append_sample(samples, sample_value)

	wave.data = samples
	return wave

## ── Deterministic _at(quality) variants — used by pool pre-generator ─────────

func _create_thock_sound_at(speed: float, hit_quality: float) -> AudioStreamWAV:
	var speed_ratio: float  = clamp(speed / 12.0, 0.0, 1.0)
	var pitch_var: float    = lerp(-0.18, 0.03, hit_quality) * (1.0 - hit_quality * 0.75)
	var body_decay_v: float = lerp(22.0 + hit_quality * 58.0, 60.0 + hit_quality * 97.0, 0.5)
	var body_pitch_v: float = lerp(0.75, 1.0, hit_quality)
	var dur_v: float        = lerp(0.032 + hit_quality * 0.008, 0.050 + hit_quality * 0.022, 0.5)
	return _create_paddle_sound(
		dur_v, 0.56, 1.0, 1.0, 0.12, 0.025, 68.5, body_decay_v, 0.00020,
		1.0 + speed_ratio * 0.02 + pitch_var, body_pitch_v
	)

func _create_volley_sound_at(hit_quality: float) -> AudioStreamWAV:
	var pitch_var: float    = lerp(-0.20, 0.02, hit_quality) * (1.0 - hit_quality * 0.65)
	var body_decay_v: float = lerp(18.0 + hit_quality * 45.0, 50.0 + hit_quality * 93.0, 0.5)
	var body_pitch_v: float = lerp(0.70, 0.97, hit_quality)
	var dur_v: float        = lerp(0.032 + hit_quality * 0.004, 0.052 + hit_quality * 0.016, 0.5)
	return _create_paddle_sound(
		dur_v, 0.44, 0.85, 0.95, 0.06, 0.008, 61.3, body_decay_v, 0.00035,
		0.96 + pitch_var, body_pitch_v
	)

func _create_smash_sound_at(hit_quality: float) -> AudioStreamWAV:
	var pitch_var: float    = lerp(-0.10, 0.04, hit_quality) * (1.0 - hit_quality * 0.70)
	var body_decay_v: float = lerp(35.0 + hit_quality * 65.0, 80.0 + hit_quality * 77.0, 0.5)
	var body_pitch_v: float = lerp(0.80, 1.01, hit_quality)
	var dur_v: float        = lerp(0.022 + hit_quality * 0.005, 0.034 + hit_quality * 0.014, 0.5)
	return _create_paddle_sound(
		dur_v, 0.68, 1.1, 0.90, 0.18, 0.05, 50.0, body_decay_v, 0.00015,
		1.03 + pitch_var, body_pitch_v
	)

## ── Rim hit (near-edge, hybrid between sweetspot and frame) ─────────────────

func _create_rim_hit_sound_at(hit_quality: float) -> AudioStreamWAV:
	# Rim hit: ball lands near the edge of the paddle face.
	# Lower pitch, less body resonance, slight metallic ring from proximity to frame.
	var wave := _new_wave()
	var samples := PackedByteArray()
	var duration: float = lerp(0.025, 0.040, hit_quality)
	var num_samples := int(duration * AUDIO_SAMPLE_RATE)
	var pitch_var: float    = lerp(0.76, 0.94, hit_quality)
	var body_pitch_v: float = lerp(0.70, 0.90, hit_quality)
	var mode_decay: float   = lerp(42.0, 70.0, hit_quality)
	var body_decay: float   = lerp(22.0, 52.0, hit_quality)

	for i in range(num_samples):
		var t: float = float(i) / AUDIO_SAMPLE_RATE
		var strike_env := exp(-t * 88.0)
		var mode_env   := exp(-t * mode_decay)
		var body_env   := exp(-t * body_decay)
		var rim_env    := exp(-t * 125.0)
		var helm_env   := exp(-t * 105.0)
		var click_env  := exp(-t * 420.0)

		# Strike — muted, ball doesn't compress fully off-center
		var strike := sin(t * BALL_STRIKE_FREQ * pitch_var * TAU) * 0.26

		# Paddle mode — lower, less resonant
		var pmode   := sin(t * PADDLE_MODE_FREQ * pitch_var * 0.88 * TAU) * 0.09
		var pmode_s := sin(t * PADDLE_MODE_FREQ * pitch_var * 0.44 * TAU) * 0.04

		# Hollow body resonance (lower than sweetspot)
		var body1 := sin(t * 250.0 * body_pitch_v * TAU) * 0.16
		var body2 := sin(t * 185.0 * body_pitch_v * TAU) * 0.10

		# Metallic rim ring (~1900-2200 Hz: frame proximity)
		var rim_ring := sin(t * 2050.0 * pitch_var * TAU) * 0.18
		var rim_harm := sin(t * 3100.0 * pitch_var * TAU) * 0.06

		# Weakened Helmholtz air
		var helmholtz := sin(t * BALL_HELMHOLTZ_FREQ * pitch_var * TAU) * 0.20

		# Brief broadband click
		var click := (randf() * 2.0 - 1.0) * 0.10 * click_env

		var combined := (
			strike * strike_env +
			(pmode + pmode_s) * mode_env +
			(body1 + body2) * body_env +
			(rim_ring + rim_harm) * rim_env +
			helmholtz * helm_env +
			click
		)
		_append_sample(samples, combined * 0.50)

	wave.data = samples
	return wave

## ── Frame hit (ball strikes rigid carbon frame edge) ────────────────────────

func _create_frame_hit_sound_at(hit_quality: float) -> AudioStreamWAV:
	# Frame hit: ball contacts the stiff carbon fiber frame, not the paddle face.
	# Characteristic high-frequency metallic ring (2500-3500 Hz), very little body.
	var wave := _new_wave()
	var samples := PackedByteArray()
	var duration: float = lerp(0.018, 0.032, hit_quality)
	var num_samples := int(duration * AUDIO_SAMPLE_RATE)
	var pitch_var: float  = lerp(0.80, 1.06, hit_quality)
	var ring_decay: float = lerp(165.0, 115.0, hit_quality)  # harder hits ring longer

	for i in range(num_samples):
		var t: float = float(i) / AUDIO_SAMPLE_RATE
		var ring_env  := exp(-t * ring_decay)
		var body_env  := exp(-t * 130.0)
		var click_env := exp(-t * 520.0)

		# Primary carbon fiber frame ring: 2700-2900 Hz
		var frame_primary := sin(t * 2800.0 * pitch_var * TAU) * 0.55
		var frame_harm2   := sin(t * 4200.0 * pitch_var * TAU) * 0.14  # 3/2 partial
		var frame_harm3   := sin(t * 5600.0 * pitch_var * TAU) * 0.07  # 2nd harmonic

		# Thin body thud — ball still makes brief contact energy at low freq
		var body_thud := sin(t * 310.0 * TAU) * 0.11

		# Sharp broadband click (impact transient)
		var click := (randf() * 2.0 - 1.0) * 0.20 * click_env

		var combined := (
			(frame_primary + frame_harm2 + frame_harm3) * ring_env +
			body_thud * body_env * 0.38 +
			click
		)
		_append_sample(samples, combined * 0.46)

	wave.data = samples
	return wave

## ── Random wrappers (kept for test keys 6/7/8) ─────────────────────────────

func _create_thock_sound(speed: float) -> AudioStreamWAV:
	return _create_thock_sound_at(speed, sqrt(randf()))

func _create_volley_sound() -> AudioStreamWAV:
	return _create_volley_sound_at(randf())

func _create_smash_sound() -> AudioStreamWAV:
	var hit_quality: float  = pow(randf(), 0.4)
	var pitch_var: float    = randf_range(-0.10, 0.04) * (1.0 - hit_quality * 0.70)
	var body_decay_v: float = randf_range(35.0 + hit_quality * 65.0, 80.0 + hit_quality * 77.0)
	var body_pitch_v: float = lerp(0.80, 1.01, hit_quality) + randf_range(-0.02, 0.02)
	var dur_v: float        = randf_range(0.022 + hit_quality * 0.005, 0.034 + hit_quality * 0.014)
	return _create_paddle_sound(
		dur_v,
		0.68,
		1.1,
		0.90,
		0.18,
		0.05,
		50.0,     # mode_decay: 250→50.0 (optimizer)
		body_decay_v,
		0.00015,
		1.03 + pitch_var,
		body_pitch_v
	)

func _create_serve_sound() -> AudioStreamWAV:
	# Service hit — moderate power
	return _create_paddle_sound(
		0.028,    # duration: 28ms
		0.62,     # amplitude
		1.0,      # mode_gain
		1.0,      # body_gain
		0.10,     # click_gain
		0.03,     # ring_gain
		205.0,    # mode_decay
		112.0,    # body_decay: 90→112 (same body-decay correction as thock/smash)
		0.00020,  # attack
		1.0,      # mode_pitch_scale
		1.0       # body_pitch_scale
	)

func _create_court_bounce_sound(speed: float) -> AudioStreamWAV:
	# Court bounce: duller than paddle hit — no rigid face amplification
	# Ball deforms more against flat surface → longer contact → lower frequency
	# Research: court bounces peak ~500-700 Hz (constants now 620/780 Hz)
	var speed_ratio = clamp(speed / 10.0, 0.0, 1.0)
	var wave = _new_wave()
	var samples = PackedByteArray()
	var court_tone_scale = 1.0 + court_snap_tune * 0.12
	var court_weight_scale = 1.0 + court_weight_tune * 0.55
	var court_amp_scale = 1.0 + court_weight_tune * 0.12
	var court_decay_scale = 1.0 + court_decay_tune * 0.8
	var court_hardness_scale = 1.0 + court_hardness_tune * 0.65
	var court_surface_scale = 1.0 + court_surface_tune * 0.35  # -1=soft/clay, +1=hard concrete
	var duration = 0.020 + speed_ratio * 0.008 + max(court_decay_tune, 0.0) * 0.006  # Extended: 20-28ms (was 14-20ms)
	var num_samples = int(duration * AUDIO_SAMPLE_RATE)

	for i in range(num_samples):
		var t = float(i) / AUDIO_SAMPLE_RATE
		# Slower attack than paddle (ball deforms more against flat surface)
		var thwack_env = _exp_env(t, max(0.0006 - court_snap_tune * 0.0002, 0.0002), 0.0006, (125.0 + court_snap_tune * 18.0) / court_decay_scale)
		var weight_env = _exp_env(t, 0.0004, 0.0016 * court_decay_scale, 48.0 / court_decay_scale)  # Slower body decay
		var click_env = exp(-t * (180.0 + court_snap_tune * 35.0 + court_hardness_tune * 40.0))  # Softer click decay

		# Primary thwack at 620 Hz (lowered from 860) — no paddle resonance amplification
		var thwack = sin(t * COURT_BOUNCE_FREQ * court_tone_scale * court_hardness_scale * court_surface_scale * TAU) * 0.65
		var thwack_upper = sin(t * COURT_BOUNCE_UPPER_FREQ * court_tone_scale * court_hardness_scale * court_surface_scale * TAU) * 0.22
		# Heavier body weight — court bounce has more low-end thud
		var weight = sin(t * COURT_BOUNCE_BODY_FREQ * TAU) * 0.55
		var weight_sub = sin(t * (COURT_BOUNCE_BODY_FREQ * 0.72) * TAU) * 0.18  # Sub-bass thud (~108 Hz)
		# Surface slap — hardness-dependent, lower freq than paddle click
		var slap = sin(t * 920.0 * court_hardness_scale * court_surface_scale * TAU) * 0.10  # Lowered from 1180
		# Ball shell vibration on bounce — faint, frequency-shifted by deformation
		var ball_ring = sin(t * BALL_HELMHOLTZ_FREQ * 0.85 * TAU) * 0.06  # Lower than paddle hit (more deformation)
		var click = (randf() * 2.0 - 1.0) * click_env
		var combined = (
			(thwack + thwack_upper) * 0.52 * thwack_env +
			(weight + weight_sub) * 0.32 * court_weight_scale * weight_env +
			ball_ring * 0.15 * thwack_env +
			slap * max(court_hardness_tune, 0.0) * 0.30 * thwack_env +
			click * (0.035 + court_snap_tune * 0.015 + court_hardness_tune * 0.008)
		)
		_append_sample(samples, combined * (0.45 + speed_ratio * 0.12) * court_amp_scale)

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
		var flap = (randf() * 2.0 - 1.0) * exp(-t * 34.0)
		var combined = (tape + tape_low) * 0.52 * attack_env + flap * 0.10
		_append_sample(samples, combined * (0.42 + speed_ratio * 0.10))

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
		var rustle_env = exp(-t * 18.0)
		var rustle = (randf() * 2.0 - 1.0) * (
			0.6 * sin(t * NET_MESH_FREQ * TAU) +
			0.4 * sin(t * 5400.0 * TAU)
		)
		var body = sin(t * 320.0 * TAU) * 0.14
		var combined = rustle * 0.22 * rustle_env + body * 0.18 * stretch_env
		_append_sample(samples, combined * (0.34 + speed_ratio * 0.08))

	wave.data = samples
	return wave
