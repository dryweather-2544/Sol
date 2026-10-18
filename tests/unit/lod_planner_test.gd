extends "res://tests/test_case.gd"

var _planet := PlanetBody.new()


func _planner() -> LodPlanner:
	return LodPlanner.new(_planet)


func test_chunk_key_round_trip_and_ancestry() -> void:
	var key := ChunkKey.make(4, 9, 300, 77)
	assert_eq(ChunkKey.face_of(key), 4)
	assert_eq(ChunkKey.level_of(key), 9)
	assert_eq(ChunkKey.column_of(key), 300)
	assert_eq(ChunkKey.row_of(key), 77)
	var parent := ChunkKey.parent_of(key)
	assert_eq(ChunkKey.level_of(parent), 8)
	assert_true(ChunkKey.is_ancestor(parent, key))
	assert_true(ChunkKey.is_ancestor(ChunkKey.parent_of(parent), key))
	assert_true(not ChunkKey.is_ancestor(key, parent))
	assert_true(not ChunkKey.is_ancestor(key, key))
	assert_eq(ChunkKey.child_of(parent, 300 & 1, 77 & 1), key)


func test_leaves_tile_the_whole_planet_without_overlap() -> void:
	var planner := _planner()
	var viewer := WorldPos.new(&"planet", 0.0, 0.0, _planet.radius + 50.0)
	var leaves := planner.select_leaves(viewer)
	var covered_area := 0.0
	for key in leaves:
		var span := 2.0 / float(1 << ChunkKey.level_of(key))
		covered_area += span * span
		var ancestor: int = key
		while ChunkKey.level_of(ancestor) > 0:
			ancestor = ChunkKey.parent_of(ancestor)
			assert_true(not leaves.has(ancestor), "leaf %d has a leaf ancestor" % key)
	assert_near(covered_area, 24.0, 1e-9, "six faces of area 4")


func test_detail_concentrates_near_the_viewer_and_counts_stay_bounded() -> void:
	var planner := _planner()
	var on_ground := planner.select_leaves(WorldPos.new(&"planet", 0.0, 0.0, _planet.radius + 3.0))
	var deepest := 0
	for key in on_ground:
		deepest = maxi(deepest, ChunkKey.level_of(key))
	assert_eq(deepest, planner.max_level, "standing on the ground reaches the finest level")
	assert_true(on_ground.size() < 1500, "ground chunk count %d" % on_ground.size())
	var in_orbit := planner.select_leaves(WorldPos.new(&"planet", 0.0, 0.0, _planet.radius + 300000.0))
	var orbit_deepest := 0
	for key in in_orbit:
		orbit_deepest = maxi(orbit_deepest, ChunkKey.level_of(key))
	assert_true(orbit_deepest < 10, "orbit needs only coarse chunks, deepest %d" % orbit_deepest)
	assert_true(in_orbit.size() < 400, "orbit chunk count %d" % in_orbit.size())
