extends "res://tests/test_case.gd"


func _zero_crossings(samples: PackedFloat32Array, from_index: int, to_index: int) -> int:
	var crossings := 0
	for index in range(from_index + 1, to_index):
		if (samples[index - 1] < 0.0) != (samples[index] < 0.0):
			crossings += 1
	return crossings


func test_tone_has_the_requested_length_frequency_and_stays_in_range() -> void:
	var samples := SoundSynth.tone(440.0, 0.5, 0.6)
	assert_eq(samples.size(), SoundSynth.SAMPLE_RATE / 2)
	var peak := 0.0
	for sample in samples:
		peak = maxf(peak, absf(sample))
	assert_true(peak <= 0.6 + 1e-6 and peak > 0.5, "peak %f" % peak)
	var crossings := _zero_crossings(samples, 0, samples.size())
	assert_near(float(crossings) / 2.0, 440.0 * 0.5, 3.0, "about 220 cycles in half a second")


func test_sweep_rises_in_pitch() -> void:
	var samples := SoundSynth.sweep(200.0, 800.0, 1.0)
	var quarter := samples.size() / 4
	var early := _zero_crossings(samples, 0, quarter)
	var late := _zero_crossings(samples, samples.size() - quarter, samples.size())
	assert_true(late > early * 2, "late %d vs early %d crossings" % [late, early])


func test_noise_is_deterministic_bounded_and_decays() -> void:
	var first := SoundSynth.noise_burst(0.3, 5, 0.5, 0.8)
	var second := SoundSynth.noise_burst(0.3, 5, 0.5, 0.8)
	assert_eq(first, second)
	assert_true(SoundSynth.noise_burst(0.3, 6, 0.5, 0.8) != first, "different seed differs")
	var start_energy := 0.0
	var end_energy := 0.0
	var window := first.size() / 5
	for index in window:
		start_energy += absf(first[index + 100])
		end_energy += absf(first[first.size() - window + index - 100])
	assert_true(start_energy > end_energy * 3.0, "burst fades out")


func test_stream_conversion_keeps_sample_count_and_clamps() -> void:
	var samples := PackedFloat32Array([0.0, 1.5, -1.5, 0.5])
	var stream := SoundSynth.to_stream(samples)
	assert_eq(stream.data.size(), 8)
	assert_eq(stream.data.decode_s16(2), 32767, "over-range samples are clamped")
	assert_eq(stream.data.decode_s16(4), -32767)


func test_engine_gets_louder_and_higher_with_throttle_and_wind_is_silent_at_zero() -> void:
	var idle := SoundSynth.EngineVoice.new().fill(4000, 0.0, 1.0)
	var full := SoundSynth.EngineVoice.new().fill(4000, 1.0, 1.0)
	var idle_level := 0.0
	var full_level := 0.0
	for index in 4000:
		idle_level += absf(idle[index])
		full_level += absf(full[index])
		assert_true(absf(idle[index]) <= 1.0 and absf(full[index]) <= 1.0)
	assert_true(full_level > idle_level * 2.0, "louder at full throttle")
	var calm := SoundSynth.WindVoice.new().fill(1000, 0.0, 1.0)
	for sample in calm:
		assert_eq(sample, 0.0)
