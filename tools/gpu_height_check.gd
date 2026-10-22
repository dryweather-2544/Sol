extends SceneTree
## Compares the GPU height shader with the CPU copy of Rodina's planets and times both, then times a real
## chunk build. Run on a machine with a GPU (not --headless):
##   Godot --path . -s res://tools/gpu_height_check.gd
## Needs the shader imported once (tools/run_tests.sh does that).

const GRAMMARS := {1: "Perun", 2: "Jarilo", 3: "Veles", 4: "Morena", 5: "Asteroid"}


func _init() -> void:
	GpuHeights.warm_up()
	if not GpuHeights.is_ready():
		print("GPU heights are NOT available (no local rendering device, or the shader did not compile; see warnings above).")
		GpuHeights.shutdown()
		quit(1)
		return
	var gpu := GpuHeights.instance()
	var worst_overall := 0.0
	for grammar in GRAMMARS:
		var profile := TerrainProfile.new()
		profile.grammar = grammar
		profile.radius = 1700000.0 if grammar == 5 else 6000000.0
		var rng := SeedRng.new(4000 + grammar)
		var count := 1225
		var floats := PackedFloat32Array()
		floats.resize(count * 4)
		var directions: Array[Vector3] = []
		for index in count:
			var direction := Vector3(rng.next_float() - 0.5, rng.next_float() - 0.5, rng.next_float() - 0.5).normalized()
			directions.append(direction)
			floats[index * 4] = direction.x
			floats[index * 4 + 1] = direction.y
			floats[index * 4 + 2] = direction.z
		var scale := RodinaPlanets.asteroid_scale(profile.radius)
		gpu.heights(floats, count, grammar, scale) # warm-up dispatch
		var gpu_started := Time.get_ticks_usec()
		var gpu_heights := PackedFloat32Array()
		for repeat in 10:
			gpu_heights = gpu.heights(floats, count, grammar, scale)
		var gpu_ms := float(Time.get_ticks_usec() - gpu_started) / 10000.0
		var cpu_started := Time.get_ticks_usec()
		var cpu_heights := PackedFloat64Array()
		for direction in directions:
			cpu_heights.append(RodinaPlanets.height(grammar, direction, profile.radius))
		var cpu_us := float(Time.get_ticks_usec() - cpu_started) / count
		var total := 0.0
		var worst := 0.0
		var over_one := 0
		var lowest := INF
		var highest := -INF
		for index in count:
			var difference := absf(gpu_heights[index] - cpu_heights[index])
			total += difference
			worst = maxf(worst, difference)
			if difference > 1.0:
				over_one += 1
			lowest = minf(lowest, cpu_heights[index])
			highest = maxf(highest, cpu_heights[index])
		worst_overall = maxf(worst_overall, worst)
		# Feature texture (base, plateau, mountains, holes): GPU against the CPU functions, and what asking for it costs.
		var both := gpu.heights_and_features(floats, count, grammar, scale)
		var feature_started := Time.get_ticks_usec()
		for repeat in 10:
			both = gpu.heights_and_features(floats, count, grammar, scale)
		var feature_ms := float(Time.get_ticks_usec() - feature_started) / 10000.0
		var feature_worst := [0.0, 0.0, 0.0, 0.0]
		var feature_total := 0.0
		var features: PackedFloat32Array = both["features"]
		for index in count:
			var expected := RodinaPlanets.features(grammar, directions[index])
			for channel in 4:
				var channel_difference := absf(features[index * 4 + channel] - expected[channel])
				feature_total += channel_difference
				feature_worst[channel] = maxf(feature_worst[channel], channel_difference)
		print("%-8s features GPU-CPU mean %.4f worst (base %.3f plateau %.3f mountains %.3f holes %.3f) | GPU heights+features %.2f ms per %d points" % [GRAMMARS[grammar], feature_total / (count * 4), feature_worst[0], feature_worst[1], feature_worst[2], feature_worst[3], feature_ms, count])
		print("%-8s heights %9.0f..%9.0f m | GPU-CPU mean %.3f m worst %.2f m, %d of %d differ by >1 m | CPU %.0f us/sample, GPU %.2f ms per %d points" % [GRAMMARS[grammar], lowest, highest, total / count, worst, over_one, count, cpu_us, gpu_ms, count])
	# One real chunk, GPU against CPU only.
	var planet := PlanetBody.new()
	planet.height_function.profile.grammar = TerrainProfile.Grammar.JARILO
	planet.height_function.exact = true
	var key := ChunkKey.make(4, 12, 3000, 3000)
	var gpu_started := Time.get_ticks_usec()
	var mesh := ChunkMesher.build(key, planet)
	print("chunk (level 12, grid %d) built in %.1f ms with %d vertices" % [mesh["grid"], float(Time.get_ticks_usec() - gpu_started) / 1000.0, mesh["vertices"].size()])
	GpuHeights.set_enabled(false)
	var cpu_started := Time.get_ticks_usec()
	var cpu_mesh := ChunkMesher.build(key, planet)
	print("same chunk on the CPU in %.1f ms (%d vertices)" % [float(Time.get_ticks_usec() - cpu_started) / 1000.0, cpu_mesh["vertices"].size()])
	GpuHeights.set_enabled(true)
	print("RESULT: worst GPU-CPU height difference %.2f m" % worst_overall)
	GpuHeights.shutdown()
	quit(0)
