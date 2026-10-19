class_name SoundSynth
extends RefCounted
## All Sol sounds are synthesised here from maths and a seeded noise source, so there are no audio
## files and no licences. Everything returns mono samples in -1..1 at SAMPLE_RATE.

const SAMPLE_RATE := 22050


## Sine tone with a short fade in/out (no clicks).
static func tone(frequency: float, seconds: float, volume: float = 0.5) -> PackedFloat32Array:
	var count := int(seconds * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for index in count:
		samples[index] = sin(TAU * frequency * float(index) / SAMPLE_RATE) * volume * _edge_fade(index, count)
	return samples


## Frequency glide from start to end over the duration.
static func sweep(start_frequency: float, end_frequency: float, seconds: float, volume: float = 0.5) -> PackedFloat32Array:
	var count := int(seconds * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for index in count:
		var fraction := float(index) / maxf(count - 1, 1)
		phase += TAU * lerpf(start_frequency, end_frequency, fraction) / SAMPLE_RATE
		samples[index] = sin(phase) * volume * _edge_fade(index, count)
	return samples


## Noise burst, optionally low-passed (smoothing 0 = white noise, towards 1 = darker) with a decaying envelope.
static func noise_burst(seconds: float, seed_value: int, smoothing: float = 0.0, volume: float = 0.5, decay: float = 4.0) -> PackedFloat32Array:
	var count := int(seconds * SAMPLE_RATE)
	var rng := SeedRng.new(seed_value)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var filtered := 0.0
	for index in count:
		var white := rng.next_float() * 2.0 - 1.0
		filtered = lerpf(white, filtered, smoothing)
		var envelope := exp(-decay * float(index) / maxf(count, 1)) * _edge_fade(index, count, 40)
		samples[index] = clampf(filtered * volume * envelope, -1.0, 1.0)
	return samples


static func join(first: PackedFloat32Array, second: PackedFloat32Array) -> PackedFloat32Array:
	var combined := first.duplicate()
	combined.append_array(second)
	return combined


## Wraps samples as a 16-bit mono stream that can be played once.
static func to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for index in samples.size():
		bytes.encode_s16(index * 2, int(clampf(samples[index], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream


## Engine rumble state: call fill() to get the next samples. throttle 0..1 raises pitch and volume.
class EngineVoice extends RefCounted:
	var phase_a := 0.0
	var phase_b := 0.0
	var noise_state := 0.0
	var rng := SeedRng.new(77)

	func fill(count: int, throttle: float, volume: float) -> PackedFloat32Array:
		var samples := PackedFloat32Array()
		samples.resize(count)
		var base_frequency := 38.0 + 70.0 * throttle
		var loudness := volume * (0.12 + 0.55 * throttle)
		for index in count:
			phase_a = fmod(phase_a + base_frequency / SAMPLE_RATE, 1.0)
			phase_b = fmod(phase_b + base_frequency * 1.505 / SAMPLE_RATE, 1.0)
			noise_state = lerpf(rng.next_float() * 2.0 - 1.0, noise_state, 0.92)
			var rumble := (phase_a * 2.0 - 1.0) * 0.5 + sin(TAU * phase_b) * 0.3 + noise_state * (0.6 + throttle)
			samples[index] = clampf(rumble * loudness, -1.0, 1.0)
		return samples


## Entry: a low, filtered roar with a sparse crackle layer. intensity 0..1 also opens the filter,
## so the same voice moves from a distant rumble to a tearing airflow without a sample file.
class EntryVoice extends RefCounted:
	var state := 0.0
	var phase := 0.0
	var rng := SeedRng.new(4242)

	func fill(count: int, intensity: float, volume: float) -> PackedFloat32Array:
		var samples := PackedFloat32Array()
		samples.resize(count)
		var strength := clampf(intensity, 0.0, 1.0)
		var smoothing := lerpf(0.985, 0.82, strength)
		var loudness := volume * strength * (0.18 + 0.6 * strength)
		for index in count:
			var white := rng.next_float() * 2.0 - 1.0
			state = lerpf(white, state, smoothing)
			phase = fmod(phase + (34.0 + 28.0 * strength) / SAMPLE_RATE, 1.0)
			var roar := sin(TAU * phase) * 0.45 + state * 2.2
			var crackle := 0.0
			if rng.next_float() > 0.996:
				crackle = (rng.next_float() * 2.0 - 1.0) * 1.4
			samples[index] = clampf((roar + crackle) * loudness, -1.0, 1.0)
		return samples


## Wind: low-passed noise whose brightness rises with strength 0..1.
class WindVoice extends RefCounted:
	var state := 0.0
	var rng := SeedRng.new(1234)

	func fill(count: int, strength: float, volume: float) -> PackedFloat32Array:
		var samples := PackedFloat32Array()
		samples.resize(count)
		var smoothing := lerpf(0.97, 0.7, clampf(strength, 0.0, 1.0))
		for index in count:
			state = lerpf(rng.next_float() * 2.0 - 1.0, state, smoothing)
			samples[index] = clampf(state * volume * strength * 2.5, -1.0, 1.0)
		return samples


static func _edge_fade(index: int, count: int, fade_samples: int = 200) -> float:
	var fade := mini(fade_samples, count / 2)
	if fade <= 0:
		return 1.0
	return minf(1.0, minf(float(index) / fade, float(count - 1 - index) / fade))
