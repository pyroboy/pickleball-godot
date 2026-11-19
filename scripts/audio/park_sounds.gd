extends RefCounted
## Procedural park audio: bird chirps, a crowd murmur loop and shoe scuffs.
## Every generator uses its own fixed-seed RNG, so it never touches the match RNG streams.

const RATE: = 22050

static func _wave(samples: PackedByteArray, loop: bool = false) -> AudioStreamWAV:
	var wave: = AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.stereo = false
	wave.mix_rate = RATE
	wave.data = samples
	if loop:
		wave.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wave.loop_begin = 0
		wave.loop_end = samples.size() / 2
	return wave

static func _put(samples: PackedByteArray, index: int, value: float) -> void :
	samples.encode_s16(index * 2, int(clampf(value, -1.0, 1.0) * 32767.0))

## A short two-note chirp that slides in pitch.
static func chirp(variant: int) -> AudioStreamWAV:
	var frames: = int(RATE * 0.32)
	var samples: = PackedByteArray()
	samples.resize(frames * 2)
	var base: = 2600.0 + 380.0 * variant
	var phase: = 0.0
	for i in frames:
		var t: = float(i) / RATE
		var note: = 0.0 if t < 0.12 else (1.0 if t < 0.2 else -1.0)
		var gate: = 0.0
		if note == 0.0: gate = sin(PI * t / 0.12)
		elif note == 1.0: gate = sin(PI * (t - 0.12) / 0.08)
		var freq: = base * (1.0 + 0.35 * (t / 0.12) if note == 0.0 else 1.25 - 0.3 * (t - 0.12))
		phase += TAU * freq / RATE
		_put(samples, i, sin(phase) * gate * 0.5)
	return _wave(samples)

## Soft noise bed with a slow swell, looped; the caller scales its volume.
static func crowd_loop() -> AudioStreamWAV:
	var rng: = RandomNumberGenerator.new()
	rng.seed = 4242
	var frames: = RATE * 2
	var samples: = PackedByteArray()
	samples.resize(frames * 2)
	var a: = 0.0
	var b: = 0.0
	for i in frames:
		var t: = float(i) / RATE
		a = lerpf(a, rng.randf_range(-1.0, 1.0), 0.12)
		b = lerpf(b, a, 0.2)
		# whole periods of each swell fit the loop so it joins without a click
		var swell: = 0.7 + 0.2 * sin(TAU * t * 1.0) + 0.1 * sin(TAU * t * 3.0)
		_put(samples, i, b * swell * 1.6)
	return _wave(samples, true)

## A dry rubber scuff: band-limited noise with a quick attack and a short tail.
static func scuff(variant: int) -> AudioStreamWAV:
	var rng: = RandomNumberGenerator.new()
	rng.seed = 777 + variant
	var frames: = int(RATE * (0.09 + 0.02 * variant))
	var samples: = PackedByteArray()
	samples.resize(frames * 2)
	var lp: = 0.0
	for i in frames:
		var t: = float(i) / RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.55)
		var env: = minf(t / 0.004, 1.0) * exp(-t * 38.0)
		_put(samples, i, lp * env * 0.9)
	return _wave(samples)
