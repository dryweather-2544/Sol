extends "res://tests/test_case.gd"
## The height function decides what every saved position means, so its output is pinned.
## Golden values were recorded from this implementation (Godot 4.7.2); a failure means terrain
## changed: either an intended change (re-record, expect saved landings to move) or a bug.


func _planet() -> PlanetBody:
	return PlanetBody.new()


func test_same_profile_gives_same_heights_across_instances() -> void:
	var first := HeightFunction.new(TerrainProfile.new())
	var second := HeightFunction.new(TerrainProfile.new())
	for sample in 50:
		var direction := Vector3(sin(sample * 1.3), cos(sample * 0.7), sin(sample * 0.37 + 1.0)).normalized()
		assert_eq(first.height(direction), second.height(direction))


func test_heights_stay_within_plausible_bounds() -> void:
	var height_function := HeightFunction.new(TerrainProfile.new())
	var lowest := INF
	var highest := -INF
	var rng := SeedRng.new(5)
	for sample in 2000:
		var direction := Vector3(rng.next_float() - 0.5, rng.next_float() - 0.5, rng.next_float() - 0.5).normalized()
		var height := height_function.height(direction)
		lowest = minf(lowest, height)
		highest = maxf(highest, height)
	assert_true(lowest > -6000.0 and highest < 9000.0, "range %f .. %f" % [lowest, highest])
	assert_true(highest - lowest > 1000.0, "terrain should not be flat: %f" % (highest - lowest))


func test_golden_hash_of_1000_samples() -> void:
	var height_function := HeightFunction.new(TerrainProfile.new())
	var rng := SeedRng.new(2024)
	var running_hash := 0
	for sample in 1000:
		var direction := Vector3(rng.next_float() - 0.5, rng.next_float() - 0.5, rng.next_float() - 0.5).normalized()
		var height_millimetres := int(round(height_function.height(direction) * 1000.0))
		running_hash = SeedHash.combine(running_hash, height_millimetres & 0xFFFFFFFF)
	assert_eq(running_hash, GOLDEN_HASH, "height golden hash (re-record only for intended terrain changes)")


const GOLDEN_HASH := 619230855


func test_rodina_height_grammars_are_deterministic_finite_and_not_flat() -> void:
	for grammar in [TerrainProfile.Grammar.PERUN, TerrainProfile.Grammar.JARILO, TerrainProfile.Grammar.VELES, TerrainProfile.Grammar.MORENA, TerrainProfile.Grammar.ASTEROID]:
		var profile := TerrainProfile.new()
		profile.grammar = grammar
		var a := HeightFunction.new(profile)
		var b := HeightFunction.new(profile)
		var lowest := INF
		var highest := -INF
		var rng := SeedRng.new(91 + grammar)
		for sample in 40:
			var direction := Vector3(rng.next_float() - 0.5, rng.next_float() - 0.5, rng.next_float() - 0.5).normalized()
			var height := a.height(direction)
			assert_true(is_finite(height), "grammar %d produced a non-finite height" % grammar)
			assert_eq(height, b.height(direction), "grammar %d is deterministic" % grammar)
			lowest = minf(lowest, height)
			highest = maxf(highest, height)
		assert_true(highest - lowest > 100.0, "grammar %d should make terrain, range %f..%f" % [grammar, lowest, highest])
		assert_true(highest < 100000.0 and lowest > -100000.0, "grammar %d height range %f..%f" % [grammar, lowest, highest])


func test_world_resources_choose_the_recovered_grammars() -> void:
	var system := StarSystem.default_system()
	assert_eq(system.bodies[&"planet"].terrain_profile.grammar, TerrainProfile.Grammar.JARILO, "Aurelia maps to Jarilo")
	assert_eq(system.bodies[&"cinder"].terrain_profile.grammar, TerrainProfile.Grammar.PERUN, "Cinder maps to Perun")
	assert_eq(system.bodies[&"verdant"].terrain_profile.grammar, TerrainProfile.Grammar.VELES, "Verdant maps to Veles")
	assert_eq(system.bodies[&"selene"].terrain_profile.grammar, TerrainProfile.Grammar.ASTEROID, "Selene uses the airless asteroid grammar")
	assert_eq(system.bodies[&"pebble"].terrain_profile.grammar, TerrainProfile.Grammar.ASTEROID, "Pebble uses the airless asteroid grammar")


func test_grammar_heights_are_continuous_at_small_offsets() -> void:
	for grammar in [TerrainProfile.Grammar.PERUN, TerrainProfile.Grammar.JARILO, TerrainProfile.Grammar.VELES, TerrainProfile.Grammar.MORENA, TerrainProfile.Grammar.ASTEROID]:
		var profile := TerrainProfile.new()
		profile.grammar = grammar
		var function := HeightFunction.new(profile)
		var rng := SeedRng.new(700 + grammar)
		for sample in 80:
			var direction := Vector3(rng.next_float() - 0.5, rng.next_float() - 0.5, rng.next_float() - 0.5).normalized()
			var nearby := (direction + Vector3(1e-4, 0.0, 0.0)).normalized()
			var delta := absf(function.height(direction) - function.height(nearby))
			# These grammars include deliberately high-frequency mountains/dunes; the check is for a
			# non-finite/teleporting field, not for smoothness at metre scale.
			assert_true(delta < 25000.0, "grammar %d has a cliff-like discontinuity: %f m" % [grammar, delta])
