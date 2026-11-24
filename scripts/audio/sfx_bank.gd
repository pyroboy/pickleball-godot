extends RefCounted
## Procedural interface, crowd and impact sounds.
## Every generator seeds its own RNG, so nothing here touches the match RNG streams.

const RATE: = 22050
const UI_RATE: = 44100

## Scales the buffer to `peak`, fades the last few milliseconds and packs it as 16-bit mono.
static func _wave(buf: PackedFloat32Array, rate: int, peak: float) -> AudioStreamWAV:
	var top: = 0.0001
	for value in buf: top = maxf(top, absf(value))
	var gain: = peak / top
	var count: = buf.size()
	var fade: = maxf(float(mini(int(rate * 0.004), count)), 1.0)
	var samples: = PackedByteArray()
	samples.resize(count * 2)
	for i in count:
		var edge: = minf(1.0, float(count - 1 - i) / fade)
		samples.encode_s16(i * 2, int(clampf(buf[i] * gain * edge, -1.0, 1.0) * 32767.0))
	var wave: = AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.stereo = false
	wave.mix_rate = rate
	wave.data = samples
	return wave

## Soft wooden "tock" for buttons. Variant 0 = plain, 1 = switch on (higher), 2 = switch off (lower).
static func ui_tap(variant: int) -> AudioStreamWAV:
	var base: float = [1250.0, 1520.0, 1020.0][clampi(variant, 0, 2)]
	var frames: = int(UI_RATE * 0.05)
	var buf: = PackedFloat32Array()
	buf.resize(frames)
	var phase: = 0.0
	for i in frames:
		var t: = float(i) / UI_RATE
		phase += TAU * base * (1.0 + 0.22 * exp(-t * 130.0)) / UI_RATE
		var tone: = sin(phase) * exp(-t * 95.0) + 0.28 * sin(phase * 2.01) * exp(-t * 170.0)
		buf[i] = tone * minf(t / 0.0008, 1.0)
	return _wave(buf, UI_RATE, 0.6)

## Hand claps from a small courtside crowd, each clapper with its own tempo and tone.
## `cheer` (0..1) mixes in a voiced murmur that rises and falls under the claps.
static func applause(seconds: float, clappers: int, cheer: float, rng_seed: int) -> AudioStreamWAV:
	var rng: = RandomNumberGenerator.new()
	rng.seed = rng_seed
	var frames: = int(RATE * seconds)
	var buf: = PackedFloat32Array()
	buf.resize(frames)
	var clap_frames: = int(RATE * 0.03)
	var decay: = exp(-210.0 / RATE)
	for clapper in clappers:
		var tempo: = rng.randf_range(3.4, 5.2)
		var t: = rng.randf_range(0.0, 0.45)
		var leave: = seconds * rng.randf_range(0.55, 0.95)
		var bright: = rng.randf_range(0.35, 0.7)
		var dull: = rng.randf_range(0.05, 0.12)
		var loud: = rng.randf_range(0.5, 1.0)
		while t < leave:
			var start: = int(t * RATE)
			# each person claps softer as they get close to stopping
			var level: = loud * clampf((leave - t) / (seconds * 0.35), 0.25, 1.0)
			var a: = 0.0
			var b: = 0.0
			for k in mini(clap_frames, frames - start):
				var noise: = rng.randf_range(-1.0, 1.0)
				a = lerpf(a, noise, bright)
				b = lerpf(b, noise, dull)
				buf[start + k] += (a - b) * level
				level *= decay
			t += rng.randf_range(0.9, 1.1) / tempo
			tempo *= 0.992
	if cheer > 0.0:
		var a2: = 0.0
		var b2: = 0.0
		for i in frames:
			var progress: = float(i) / float(frames)
			a2 = lerpf(a2, rng.randf_range(-1.0, 1.0), 0.1)
			b2 = lerpf(b2, a2, 0.25)
			buf[i] += b2 * sin(PI * minf(progress / 0.8, 1.0)) * cheer * 2.2
	return _wave(buf, RATE, 0.7)

## Air rush of a hard-hit ball: band-passed noise whose pitch climbs, then fades.
static func zip(variant: int) -> AudioStreamWAV:
	var rng: = RandomNumberGenerator.new()
	rng.seed = 3310 + variant
	var seconds: = 0.17 + 0.03 * variant
	var frames: = int(UI_RATE * seconds)
	var buf: = PackedFloat32Array()
	buf.resize(frames)
	var low: = 0.0
	var band: = 0.0
	var from_hz: = 1300.0 + 150.0 * variant
	var to_hz: = 3400.0 + 300.0 * variant
	for i in frames:
		var progress: = float(i) / float(frames)
		var f: = 2.0 * sin(PI * lerpf(from_hz, to_hz, progress) / UI_RATE)
		low += f * band
		var high: = rng.randf_range(-1.0, 1.0) - low - 0.4 * band
		band += f * high
		var env: = sin(PI * pow(progress, 0.6))
		buf[i] = band * env * env
	return _wave(buf, UI_RATE, 0.5)

## Dull thump of a ball hitting a body: a falling low tone plus a short slap.
static func thump() -> AudioStreamWAV:
	var rng: = RandomNumberGenerator.new()
	rng.seed = 6021
	var frames: = int(RATE * 0.15)
	var buf: = PackedFloat32Array()
	buf.resize(frames)
	var phase: = 0.0
	var lp: = 0.0
	for i in frames:
		var t: = float(i) / RATE
		phase += TAU * lerpf(165.0, 75.0, minf(t / 0.06, 1.0)) / RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.3)
		buf[i] = (sin(phase) * exp(-t * 36.0) + lp * exp(-t * 130.0) * 0.55) * minf(t / 0.0015, 1.0)
	return _wave(buf, RATE, 0.75)

## Bell-like notes played one after another (`step` seconds apart), each ringing out.
## Used for the confirm chime, the perfect-hit sparkle and the release tick.
static func chime(freqs: Array, step: float, seconds: float, decay: float) -> AudioStreamWAV:
	var frames: = int(UI_RATE * seconds)
	var buf: = PackedFloat32Array()
	buf.resize(frames)
	for index in freqs.size():
		var freq: float = freqs[index]
		var start: = int(index * step * UI_RATE)
		for i in range(start, frames):
			var t: = float(i - start) / UI_RATE
			var tone: = sin(TAU * freq * t) + 0.3 * sin(TAU * freq * 2.0 * t) * exp(-t * decay) + 0.1 * sin(TAU * freq * 3.0 * t) * exp(-t * decay * 2.0)
			buf[i] += tone * exp(-t * decay) * minf(t / 0.002, 1.0)
	return _wave(buf, UI_RATE, 0.6)

## Banner arriving: a short rising swoosh that lands on a chord (fuller when `big`).
static func stinger(big: bool) -> AudioStreamWAV:
	var rng: = RandomNumberGenerator.new()
	rng.seed = 4410
	var swoosh: = 0.16
	var frames: = int(UI_RATE * (0.75 if big else 0.55))
	var buf: = PackedFloat32Array()
	buf.resize(frames)
	var low: = 0.0
	var band: = 0.0
	var chord: Array = [523.25, 783.99, 1046.5, 1318.5] if big else [523.25, 783.99, 1046.5]
	for i in frames:
		var t: = float(i) / UI_RATE
		if t < swoosh:
			var progress: = t / swoosh
			var f: = 2.0 * sin(PI * lerpf(700.0, 3000.0, progress) / UI_RATE)
			low += f * band
			var high: = rng.randf_range(-1.0, 1.0) - low - 0.5 * band
			band += f * high
			buf[i] = band * progress * progress * 0.35
		else:
			var ring: = t - swoosh
			var hit: = 0.0
			for freq in chord:
				hit += sin(TAU * float(freq) * ring) + 0.25 * sin(TAU * float(freq) * 2.0 * ring) * exp(-ring * 14.0)
			buf[i] = hit / float(chord.size()) * exp(-ring * (5.0 if big else 8.0)) * minf(ring / 0.002, 1.0)
	return _wave(buf, UI_RATE, 0.6)

## Two paddles tapping: a dry, bright double knock.
static func clack() -> AudioStreamWAV:
	var rng: = RandomNumberGenerator.new()
	rng.seed = 2207
	var frames: = int(UI_RATE * 0.07)
	var buf: = PackedFloat32Array()
	buf.resize(frames)
	for i in frames:
		var t: = float(i) / UI_RATE
		var knock: = sin(TAU * 1273.0 * t) * 0.6 + sin(TAU * 1810.0 * t) * 0.4 + sin(TAU * 2950.0 * t) * 0.2
		buf[i] = (knock * exp(-t * 95.0) + rng.randf_range(-1.0, 1.0) * exp(-t * 500.0) * 0.4) * minf(t / 0.0004, 1.0)
	return _wave(buf, UI_RATE, 0.7)
