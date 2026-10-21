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
	assert_true(on_ground.size() < 3000, "ground chunk count %d" % on_ground.size())
	var in_orbit := planner.select_leaves(WorldPos.new(&"planet", 0.0, 0.0, _planet.radius + 300000.0))
	var orbit_deepest := 0
	for key in in_orbit:
		orbit_deepest = maxi(orbit_deepest, ChunkKey.level_of(key))
	assert_true(orbit_deepest < 10, "orbit needs only coarse chunks, deepest %d" % orbit_deepest)
	assert_true(in_orbit.size() < 1000, "orbit chunk count %d" % in_orbit.size())


func test_preload_viewer_requests_detail_ahead_without_overlap() -> void:
	var planner := _planner()
	var current := WorldPos.new(&"planet", 0.0, 0.0, _planet.radius + 3000.0)
	var ahead := WorldPos.new(&"planet", 0.0, 0.0, _planet.radius + 3000.0)
	ahead.x = 6000.0
	var normal := planner.select_leaves(current)
	var preloaded := planner.select_leaves(current, ahead)
	var covered := 0.0
	for key in preloaded:
		var span := 2.0 / float(1 << ChunkKey.level_of(key))
		covered += span * span
	assert_near(covered, 24.0, 1e-9, "preload leaves still tile the planet without overlap")
	assert_true(preloaded.size() >= normal.size(), "preload adds ahead detail rather than removing current detail")
	var deepest := 0
	for key in preloaded:
		deepest = maxi(deepest, ChunkKey.level_of(key))
	assert_true(deepest >= 1, "preload point is actually subdivided")


func test_a_split_chunk_stays_split_a_little_past_its_split_distance() -> void:
	var planner := _planner()
	var key := ChunkKey.make(0, 3, 4, 4)
	var centre := planner.chunk_center(key)
	var outward := centre.normalized()
	var split := planner.chunk_edge_metres(3) * planner.split_ratio
	var inside := centre + outward * split * 0.95
	planner.plan(WorldPos.new(&"planet", inside.x, inside.y, inside.z))
	assert_true(planner.last_internal.has(key), "split while the viewer is inside the split distance")
	var just_outside := centre + outward * split * 1.05
	planner.plan(WorldPos.new(&"planet", just_outside.x, just_outside.y, just_outside.z))
	assert_true(planner.last_internal.has(key), "still split just outside it (hysteresis)")
	var well_outside := centre + outward * split * 1.3
	planner.plan(WorldPos.new(&"planet", well_outside.x, well_outside.y, well_outside.z))
	assert_true(not planner.last_internal.has(key), "merged once the viewer is clearly farther")
	var fresh := _planner()
	fresh.plan(WorldPos.new(&"planet", just_outside.x, just_outside.y, just_outside.z))
	assert_true(not fresh.last_internal.has(key), "without history the same position does not split")


func test_centres_use_built_chunk_heights_instead_of_height_queries() -> void:
	var planner := _planner()
	var key := ChunkKey.make(2, 6, 10, 10)
	var plain := planner.chunk_center(key).length()
	assert_near(plain, _planet.radius, 1.0, "no hint: the planet radius")
	planner.note_height(ChunkKey.parent_of(key), 1500.0)
	assert_near(planner.chunk_center(key).length(), _planet.radius + 1500.0, 1.0, "an unbuilt chunk borrows its parent's height")
	planner.note_height(key, 2200.0)
	assert_near(planner.chunk_center(key).length(), _planet.radius + 2200.0, 1.0, "a built chunk uses its own")


func test_the_finest_level_is_about_a_hundred_metres_across() -> void:
	var edge := _planet.radius * PI * 0.5 / float(1 << _planet.finest_lod_level())
	assert_true(edge <= PlanetBody.FINEST_CHUNK_EDGE_METRES and edge > PlanetBody.FINEST_CHUNK_EDGE_METRES * 0.5, "finest chunk edge %f m" % edge)
