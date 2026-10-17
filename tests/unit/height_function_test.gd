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


const GOLDEN_HASH := 3890739618
