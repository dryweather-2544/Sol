extends "res://tests/test_case.gd"
## Streaming-specific checks: fallback coverage, cache bounds/reuse, and predictive planning.

func _planet() -> PlanetBody:
	var planet := PlanetBody.new()
	planet.radius = 100000.0
	planet.height_override = func(_x: float, _y: float, _z: float) -> float: return 0.0
	return planet


func _fake_mesh(level: int = 0) -> Dictionary:
	return {
		"origin": PackedFloat64Array([0.0, 0.0, 100000.0]),
		"vertices": PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 10, 0)]),
		"normals": PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP]),
		"colors": PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]),
		"indices": PackedInt32Array([0, 1, 2]),
		"level": level,
	}


func test_hierarchical_fallback_covers_a_desired_fine_chunk() -> void:
	var terrain := PlanetTerrain.new(_planet())
	var fine := ChunkKey.make(0, 10, 100, 100)
	var fallback: Dictionary = terrain._fallback_ancestors({fine: true})
	for level in [0, 1, 2]:
		assert_true(_has_level(fallback, level), "fallback includes level %d" % level)
	terrain.free()


func _has_level(keys: Dictionary, level: int) -> bool:
	for key in keys:
		if ChunkKey.level_of(key) == level:
			return true
	return false


func test_parent_is_kept_until_all_four_children_are_displayed() -> void:
	var terrain := PlanetTerrain.new(_planet())
	var parent := ChunkKey.make(0, 2, 0, 0)
	terrain._desired = {}
	for child_column in 2:
		for child_row in 2:
			terrain._desired[ChunkKey.child_of(parent, child_column, child_row)] = true
	terrain._show_chunk(parent, _fake_mesh(2))
	var children: Array[int] = []
	for key in terrain._desired:
		children.append(key)
	for index in 3:
		terrain._show_chunk(children[index], _fake_mesh(3))
	terrain._remove_obsolete_chunks()
	assert_true(terrain._displayed.has(parent), "parent stays while three of four children exist")
	terrain._show_chunk(children[3], _fake_mesh(3))
	terrain._remove_obsolete_chunks()
	assert_true(not terrain._displayed.has(parent), "parent leaves only after all four children are displayed")
	terrain.free()


func test_ready_cache_reuses_entries_and_stays_bounded() -> void:
	var terrain := PlanetTerrain.new(_planet())
	var first := ChunkKey.make(0, 8, 1, 1)
	var data := _fake_mesh(8)
	terrain.cache_mesh_for_test(first, data)
	var after_first := terrain.ready_cache_bytes()
	terrain.cache_mesh_for_test(first, data)
	assert_eq(terrain.ready_cache_entries(), 1, "the same key is not cached twice")
	assert_eq(terrain.ready_cache_bytes(), after_first, "duplicate cache insert does not double memory")
	for index in 600:
		terrain.cache_mesh_for_test(ChunkKey.make(0, 8, 10 + index, 10), _fake_mesh(8))
	assert_true(terrain.ready_cache_bytes() <= terrain.READY_CACHE_BUDGET_BYTES, "ready cache stays inside its budget")
	assert_true(terrain.ready_cache_entries() <= terrain.READY_CACHE_MAX_ENTRIES, "ready cache stays inside its entry cap")
	assert_true(int(terrain.stream_stats()["cache_evicted"]) > 0, "eviction actually ran")
	terrain.free()


func test_preload_is_directional_and_bounded() -> void:
	var terrain := PlanetTerrain.new(_planet())
	terrain.viewer = WorldPos.new(&"planet", 0.0, 0.0, 100000.0)
	terrain.viewer_velocity = Vector3.ZERO
	assert_true(terrain._preload_viewer() == null, "a stationary viewer has no speculative point")
	terrain.viewer_velocity = Vector3(0.0, 0.0, 100000.0)
	var ahead := terrain._preload_viewer()
	assert_true(ahead != null, "moving viewer has a speculative point")
	var distance := Vector3(ahead.x, ahead.y, ahead.z).distance_to(Vector3(0.0, 0.0, 100000.0))
	assert_true(distance > 0.0 and distance <= terrain.PRELOAD_MAX_METRES, "lookahead is bounded")
	assert_true(ahead.z > terrain.viewer.z, "lookahead is in the velocity direction")
	terrain.free()


func test_coarse_face_meshes_cover_the_planet_without_high_detail() -> void:
	var planet := _planet()
	for face in 6:
		var mesh_data := ChunkMesher.build(ChunkKey.make(face, 0, 0, 0), planet)
		var vertices: PackedVector3Array = mesh_data["vertices"]
		assert_true(vertices.size() > 0, "coarse face %d has geometry" % face)
		assert_true(int(mesh_data["grid"]) <= 6, "coarse face uses the cheap LOD grid")
		assert_true((mesh_data["vertices"] as PackedVector3Array).size() < 100, "coarse face is cheap to generate")


func test_simultaneous_parent_child_removal_leaves_a_surface() -> void:
	var terrain := PlanetTerrain.new(_planet())
	var parent := ChunkKey.make(0, 1, 0, 0)
	terrain._show_chunk(parent, _fake_mesh(1))
	var children: Array[int] = []
	for child_column in 2:
		for child_row in 2:
			var child := ChunkKey.child_of(parent, child_column, child_row)
			children.append(child)
			terrain._show_chunk(child, _fake_mesh(2))
	terrain._desired = {}
	terrain._remove_obsolete_chunks()
	assert_true(not terrain._displayed.is_empty(), "the removal pass cannot delete both layers")
	assert_true(terrain._is_covered(parent), "the parent area remains covered")
	terrain.free()


func test_coarse_mesh_vertices_still_sample_the_height_function() -> void:
	var planet := _planet()
	var data := ChunkMesher.build(ChunkKey.make(0, 0, 0, 0), planet)
	var vertices: PackedVector3Array = data["vertices"]
	var origin: PackedFloat64Array = data["origin"]
	var surface_count := (int(data["grid"]) + 1) * (int(data["grid"]) + 1)
	var worst := 0.0
	for i in surface_count:
		var world := vertices[i] + Vector3(origin[0], origin[1], origin[2])
		var direction := world.normalized()
		var expected := planet.surface_radius_xyz(direction.x, direction.y, direction.z)
		worst = maxf(worst, absf(world.length() - expected))
	assert_true(worst < 0.05, "coarse mesh still follows the height source: %f m" % worst)


func test_same_level_neighbour_chunks_share_their_edge() -> void:
	var planet := _planet()
	for level in [3, 6]:
		var left := ChunkMesher.build(ChunkKey.make(0, level, 4, 4), planet)
		var right := ChunkMesher.build(ChunkKey.make(0, level, 5, 4), planet)
		var grid: int = left["grid"]
		var left_vertices: PackedVector3Array = left["vertices"]
		var right_vertices: PackedVector3Array = right["vertices"]
		var left_origin: PackedFloat64Array = left["origin"]
		var right_origin: PackedFloat64Array = right["origin"]
		var worst := 0.0
		for row in grid + 1:
			var a := left_vertices[row * (grid + 1) + grid] + Vector3(left_origin[0], left_origin[1], left_origin[2])
			var b := right_vertices[row * (grid + 1)] + Vector3(right_origin[0], right_origin[1], right_origin[2])
			worst = maxf(worst, a.distance_to(b))
		assert_true(worst < 0.01, "level %d neighbour edge mismatch: %f m" % [level, worst])


func test_six_coarse_faces_cover_the_whole_planet() -> void:
	var planet := _planet()
	var terrain := PlanetTerrain.new(planet)
	for face in 6:
		terrain._show_chunk(ChunkKey.make(face, 0, 0, 0), _fake_mesh(0))
	assert_true(terrain.displayed_coverage_is_complete(), "six face chunks cover every root face")
	terrain.free()
