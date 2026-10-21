extends "res://tests/test_case.gd"
## Rodina's exact planet functions (RodinaPlanets) and the plumbing around them. The GPU shader itself can only be
## checked on a machine with a GPU: tools/gpu_height_check.gd.


func _random_direction(rng: SeedRng) -> Vector3:
	return Vector3(rng.next_float() - 0.5, rng.next_float() - 0.5, rng.next_float() - 0.5).normalized()


func test_voronoi_points_are_a_fixed_set_of_unit_vectors() -> void:
	var points := RodinaPlanets.points()
	assert_eq(points.size(), RodinaPlanets.VORONOI_COUNT)
	for index in points.size():
		assert_near(points[index].length(), 1.0, 1e-5, "point %d is on the unit sphere" % index)
	assert_eq(RodinaPlanets.points_as_floats().size(), RodinaPlanets.VORONOI_COUNT * 4)


func test_grid_search_matches_brute_force_nearest_two() -> void:
	var points := RodinaPlanets.points()
	var rng := SeedRng.new(77)
	for sample in 150:
		var p := _random_direction(rng)
		var best1 := INF
		for point in points:
			best1 = minf(best1, p.distance_to(point))
		var best2 := INF
		for point in points:
			var distance := p.distance_to(point)
			if distance > best1 and distance < best2:
				best2 = distance
		var fast := RodinaPlanets.nearest_two(p)
		assert_near(fast.x, best1, 1e-6, "nearest")
		assert_near(fast.y, best2, 1e-6, "second nearest")


func test_hlsl_analogue_handles_reversed_and_zero_width_ranges() -> void:
	assert_near(RodinaPlanets.analogue(0.0, 1.0, -1.0, 0.0, 1.0), 0.5, 1e-9, "reversed source range")
	assert_near(RodinaPlanets.analogue(1.0, 1.0, -1.0, 0.0, 1.0), 0.0, 1e-9)
	assert_near(RodinaPlanets.analogue(-1.0, 1.0, -1.0, 0.0, 1.0), 1.0, 1e-9)
	assert_near(RodinaPlanets.analogue(0.0, -1.0, -1.0, 0.0, 1.0), 1.0, 1e-9, "zero width above the edge saturates to 1")
	assert_near(RodinaPlanets.analogue(-2.0, -1.0, -1.0, 0.0, 1.0), 0.0, 1e-9, "zero width below the edge is 0")
	assert_near(RodinaPlanets.hsmooth(0.55, 0.375, 0.4), 0.8571 * 0.8571 * (3.0 - 2.0 * 0.8571), 1e-3, "reversed smoothstep edges")


func test_every_grammar_makes_finite_varied_terrain_and_is_deterministic() -> void:
	for grammar in [TerrainProfile.Grammar.PERUN, TerrainProfile.Grammar.JARILO, TerrainProfile.Grammar.VELES, TerrainProfile.Grammar.MORENA, TerrainProfile.Grammar.ASTEROID]:
		var rng := SeedRng.new(900 + grammar)
		var lowest := INF
		var highest := -INF
		for sample in 30:
			var direction := _random_direction(rng)
			var height := RodinaPlanets.height(grammar, direction, 6000000.0)
			assert_true(is_finite(height), "grammar %d finite" % grammar)
			assert_eq(height, RodinaPlanets.height(grammar, direction, 6000000.0), "grammar %d deterministic" % grammar)
			lowest = minf(lowest, height)
			highest = maxf(highest, height)
		assert_true(highest - lowest > 100.0, "grammar %d should make relief, got %f..%f" % [grammar, lowest, highest])
		assert_true(lowest > -100000.0 and highest < 150000.0, "grammar %d range %f..%f" % [grammar, lowest, highest])


func test_exact_height_function_uses_the_rodina_planets() -> void:
	var profile := TerrainProfile.new()
	profile.grammar = TerrainProfile.Grammar.JARILO
	var function := HeightFunction.new(profile)
	function.exact = true
	var rng := SeedRng.new(31)
	for sample in 10:
		var direction := _random_direction(rng)
		assert_eq(function.height_xyz(direction.x, direction.y, direction.z), RodinaPlanets.height(TerrainProfile.Grammar.JARILO, direction, profile.radius))


func test_legacy_grammar_is_never_exact() -> void:
	var function := HeightFunction.new(TerrainProfile.new())
	assert_true(not function.exact)


func test_without_a_gpu_the_mesher_still_builds_chunks() -> void:
	GpuHeights.set_enabled(false)
	var planet := PlanetBody.new()
	planet.height_function.profile.grammar = TerrainProfile.Grammar.JARILO
	var mesh := ChunkMesher.build(ChunkKey.make(4, 3, 1, 1), planet, 8)
	assert_true(mesh["vertices"].size() > 80, "a chunk is built on the CPU path")
