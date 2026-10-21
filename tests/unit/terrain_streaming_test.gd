extends "res://tests/test_case.gd"
## Streaming-specific checks: backstop coverage, one-layer cover selection, top-down build order, the hidden-chunk
## cache, geomorphing and predictive planning. Mesh "builds" here are instant fake meshes; the real threaded pipeline
## is exercised by tools/n14_stream_probe.gd.

func _planet() -> PlanetBody:
	var planet := PlanetBody.new()
	planet.radius = 100000.0
	planet.height_override = func(_x: float, _y: float, _z: float) -> float: return 0.0
	return planet


func _fake_mesh(level: int = 0, grid: int = ChunkMesher.FINE_GRID, with_morph: bool = false) -> Dictionary:
	var data := {
		"origin": PackedFloat64Array([0.0, 0.0, 100000.0]),
		"vertices": PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 10, 0)]),
		"normals": PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP]),
		"colors": PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]),
		"indices": PackedInt32Array([0, 1, 2]),
		"level": level,
		"grid": grid,
	}
	if with_morph:
		data["morph"] = PackedVector3Array([Vector3.ZERO, Vector3(0, 1, 0), Vector3.ZERO])
	return data


## A terrain that never starts worker builds, so tests drive it with fake meshes.
func _terrain() -> PlanetTerrain:
	var terrain := PlanetTerrain.new(_planet())
	terrain.max_builds_in_flight = 0
	return terrain


func _children(key: int) -> Array[int]:
	var result: Array[int] = []
	for child_column in 2:
		for child_row in 2:
			result.append(ChunkKey.child_of(key, child_column, child_row))
	return result


func _has_level(keys: Dictionary, level: int) -> bool:
	for key in keys:
		if ChunkKey.level_of(key) == level:
			return true
	return false


func test_hierarchical_fallback_covers_a_desired_fine_chunk() -> void:
	var terrain := _terrain()
	var fine := ChunkKey.make(0, 10, 100, 100)
	var fallback: Dictionary = terrain._fallback_ancestors({fine: true})
	for level in [0, 1, 2]:
		assert_true(_has_level(fallback, level), "fallback includes level %d" % level)
	terrain.free()


func test_parent_is_kept_until_all_four_children_are_available() -> void:
	var terrain := _terrain()
	var parent := ChunkKey.make(0, 2, 0, 0)
	var children := _children(parent)
	terrain.set_plan_for_test(children)
	terrain._show_chunk(parent, _fake_mesh(2))
	for index in 3:
		terrain._show_chunk(children[index], _fake_mesh(3))
	assert_true(terrain._displayed.has(parent), "the parent stays while three of four children exist")
	for index in 3:
		assert_true(not terrain._displayed.has(children[index]), "no child is shown next to its parent (one layer only)")
	terrain._show_chunk(children[3], _fake_mesh(3))
	assert_true(not terrain._displayed.has(parent), "the parent leaves the screen when the fourth child arrives")
	for child in children:
		assert_true(terrain._displayed.has(child), "all four children are shown together")
	assert_true(terrain._chunks.has(parent), "the parent is hidden and cached, not thrown away")
	terrain.free()


func test_coarsening_swaps_to_the_parent_that_was_already_built() -> void:
	# Behind the ship the plan coarsens. The parent was a split node, so it was built, and it takes over at once.
	var terrain := _terrain()
	var parent := ChunkKey.make(0, 4, 3, 3)
	terrain.set_plan_for_test(_children(parent))
	terrain._show_chunk(parent, _fake_mesh(4))
	for child in _children(parent):
		terrain._show_chunk(child, _fake_mesh(5))
	for child in _children(parent):
		assert_true(terrain._displayed.has(child), "the fine chunks show while the plan wants them")
	terrain.set_plan_for_test([parent])
	terrain._update_visibility()
	assert_true(terrain._displayed.has(parent), "the coarser leaf shows as soon as the plan wants it")
	for child in _children(parent):
		assert_true(not terrain._displayed.has(child), "the fine chunks are hidden and cached")
	terrain.free()


func test_backstop_is_built_once_and_never_requeued() -> void:
	# Regression: the first N14 pass removed level 1/2 backstop chunks whenever level 0 was shown
	# and then queued them again, so ~95% of all builds were the same coarse faces.
	var terrain := _terrain()
	terrain.viewer = WorldPos.new(&"planet", 0.0, 0.0, 100000.0 + 2000.0)
	terrain._replan()
	var first_wave := terrain._build_order.duplicate()
	assert_true(first_wave.size() > 0, "a cold start queues builds")
	for key in terrain._fallback:
		terrain._add_chunk(key, _fake_mesh(ChunkKey.level_of(key), PlanetTerrain._required_grid(key, terrain._desired.has(key))))
	terrain._update_visibility()
	terrain._replan()
	for key in terrain._build_order:
		if terrain._fallback.has(key):
			assert_true(int(terrain._available_grids.get(key, 0)) < PlanetTerrain._required_grid(key, terrain._desired.has(key)), "a backstop chunk that exists is not queued again")
	for key in terrain._fallback:
		assert_true(terrain._chunks.has(key), "backstop chunks stay available (hidden when unused)")
	terrain.free()


func test_backstop_is_queued_first_and_the_tree_is_built_top_down() -> void:
	var terrain := _terrain()
	terrain.viewer = WorldPos.new(&"planet", 0.0, 0.0, 100000.0 + 2000.0)
	terrain._replan()
	var position_of := {}
	for index in terrain._build_order.size():
		position_of[terrain._build_order[index]] = index
	var last_backstop := -1
	var first_other := terrain._build_order.size()
	for key in terrain._build_order:
		if ChunkKey.level_of(key) in PlanetTerrain.FALLBACK_LEVELS:
			last_backstop = maxi(last_backstop, position_of[key])
		else:
			first_other = mini(first_other, position_of[key])
	assert_true(last_backstop < first_other, "every backstop chunk is queued before any finer one")
	var misordered := 0
	for key in terrain._build_order:
		if ChunkKey.level_of(key) <= 3:
			continue
		var parent := ChunkKey.parent_of(key)
		if position_of.has(parent) and int(position_of[parent]) > int(position_of[key]):
			misordered += 1
	assert_eq(misordered, 0, "a chunk is never queued before its parent")
	terrain.free()


func test_a_new_plan_shows_the_deepest_complete_level_and_one_layer() -> void:
	var terrain := _terrain()
	terrain.viewer = WorldPos.new(&"planet", 0.0, 0.0, 100000.0 + 300.0)
	terrain._replan()
	# Build only the levels down to 5 anywhere they are wanted.
	for key in terrain._desired.keys() + terrain._internal.keys():
		if ChunkKey.level_of(key) <= 5:
			terrain._add_chunk(key, _fake_mesh(ChunkKey.level_of(key), PlanetTerrain._required_grid(key, terrain._desired.has(key))))
	terrain._update_visibility()
	var deepest := 0
	for key in terrain._displayed:
		deepest = maxi(deepest, ChunkKey.level_of(key))
		var ancestor: int = key
		while ChunkKey.level_of(ancestor) > 0:
			ancestor = ChunkKey.parent_of(ancestor)
			assert_true(not terrain._displayed.has(ancestor), "no chunk is shown over its own ancestor")
	assert_eq(deepest, 5, "the planet is shown at the deepest level that is complete")
	assert_true(terrain.desired_has_no_holes(), "no holes while finer levels are still building")
	terrain.free()


func test_replacing_a_parent_starts_a_geomorph_and_it_finishes() -> void:
	var terrain := _terrain()
	var material := ShaderMaterial.new()
	material.shader = load(TerrainDetail.SHADER_PATH) as Shader
	terrain._detail_material = material
	var parent := ChunkKey.make(0, 2, 0, 0)
	var children := _children(parent)
	terrain.set_plan_for_test(children)
	terrain._show_chunk(parent, _fake_mesh(2, ChunkMesher.FINE_GRID, true))
	assert_true(terrain._morphing.is_empty(), "a chunk with nothing to replace does not morph")
	for child in children:
		terrain._show_chunk(child, _fake_mesh(3, ChunkMesher.FINE_GRID, true))
	for child in children:
		assert_true(terrain._morphing.has(child), "a child that replaces its parent starts in the parent's shape")
		assert_near(float(terrain._chunks[child]["morph_t"]), 0.0, 1e-6, "the morph starts at the beginning")
	terrain._update_morphs(PlanetTerrain.MORPH_SECONDS * 0.5)
	assert_true(terrain._morphing.size() == 4 and float(terrain._chunks[children[0]]["morph_t"]) > 0.4, "the morph advances with time")
	terrain._update_morphs(PlanetTerrain.MORPH_SECONDS)
	assert_true(terrain._morphing.is_empty(), "and ends in the chunk's own shape")
	terrain.free()


func test_planning_on_a_thread_gives_the_same_kind_of_plan() -> void:
	var terrain := _terrain()
	terrain.threaded_planning = true
	terrain.viewer = WorldPos.new(&"planet", 0.0, 0.0, 100000.0 + 2000.0)
	terrain._post_plan_request()
	var waited := 0
	while terrain._plan_in_flight and waited < 5000:
		OS.delay_msec(5)
		waited += 5
		terrain._collect_plan_result()
	assert_true(not terrain._plan_in_flight, "the planning thread answered")
	assert_true(not terrain._desired.is_empty() and not terrain._internal.is_empty(), "the plan has leaves and split nodes")
	terrain._exit_tree() # joins the thread (the terrain is not in a scene tree here)
	terrain.free()


func test_hidden_chunk_is_reused_when_the_viewer_returns() -> void:
	var terrain := _terrain()
	var parent := ChunkKey.make(0, 3, 2, 2)
	var leaf := _children(parent)[0]
	terrain.set_plan_for_test(_children(parent))
	terrain._show_chunk(parent, _fake_mesh(3))
	for child in _children(parent):
		terrain._show_chunk(child, _fake_mesh(4))
	assert_true(terrain._displayed.has(leaf), "the leaf is shown")
	terrain.set_plan_for_test([parent])
	terrain._update_visibility()
	assert_true(not terrain._displayed.has(leaf), "leaf hidden after moving away")
	terrain.set_plan_for_test(_children(parent))
	terrain._update_visibility()
	assert_true(terrain._displayed.has(leaf), "leaf is shown again from the cache without a rebuild")
	assert_true(int(terrain.stream_stats()["cache_hits"]) >= 1, "the reuse is counted")
	terrain.free()


func test_ready_cache_reuses_entries_and_stays_bounded() -> void:
	var terrain := _terrain()
	var first := ChunkKey.make(0, 8, 1, 1)
	var data := _fake_mesh(8)
	terrain.cache_mesh_for_test(first, data)
	var after_first := terrain.ready_cache_bytes()
	terrain.cache_mesh_for_test(first, data)
	assert_eq(terrain.ready_cache_entries(), 1, "the same key is not cached twice")
	assert_eq(terrain.ready_cache_bytes(), after_first, "duplicate cache insert does not double memory")
	for index in terrain.READY_CACHE_MAX_ENTRIES + 50:
		terrain.cache_mesh_for_test(ChunkKey.make(0, 10, 10 + index, 10), _fake_mesh(10))
	assert_true(terrain.ready_cache_bytes() <= terrain.READY_CACHE_BUDGET_BYTES, "ready cache stays inside its budget")
	assert_true(terrain.ready_cache_entries() <= terrain.READY_CACHE_MAX_ENTRIES, "ready cache stays inside its entry cap")
	assert_true(int(terrain.stream_stats()["cache_evicted"]) > 0, "eviction actually ran")
	terrain.free()


func test_preload_is_directional_and_bounded() -> void:
	var terrain := _terrain()
	terrain.viewer = WorldPos.new(&"planet", 0.0, 0.0, 100000.0)
	terrain.viewer_velocity = Vector3.ZERO
	assert_true(terrain._preload_viewer() == null, "a stationary viewer has no speculative point")
	terrain.viewer_velocity = Vector3(0.0, 0.0, 100000.0)
	var ahead := terrain._preload_viewer()
	assert_true(ahead != null, "moving viewer has a speculative point")
	var distance := Vector3(ahead.x, ahead.y, ahead.z).distance_to(Vector3(0.0, 0.0, 100000.0))
	assert_true(distance > 0.0 and distance <= terrain.PRELOAD_MAX_METRES + 0.01, "lookahead is bounded")
	assert_true(ahead.z > terrain.viewer.z, "lookahead is in the velocity direction")
	var corridor := terrain._preload_points()
	assert_eq(corridor.size(), terrain.PRELOAD_CORRIDOR_POINTS, "the corridor has its sample points")
	assert_true(corridor[0].z < corridor[corridor.size() - 1].z, "corridor points run along the velocity")
	terrain.free()


func test_coarse_face_meshes_cover_the_planet_without_high_detail() -> void:
	var planet := _planet()
	for face in 6:
		var mesh_data := ChunkMesher.build(ChunkKey.make(face, 0, 0, 0), planet, ChunkMesher.grid_for_level(0))
		var vertices: PackedVector3Array = mesh_data["vertices"]
		assert_true(vertices.size() > 0, "coarse face %d has geometry" % face)
		assert_true(int(mesh_data["grid"]) <= 12, "the backstop face uses the cheap grid")
		assert_true(vertices.size() < 250, "the backstop face is cheap to generate")
	var leaf := ChunkMesher.build(ChunkKey.make(0, 0, 0, 0), planet)
	assert_eq(int(leaf["grid"]), ChunkMesher.FINE_GRID, "a desired leaf always gets the full grid, even at level 0")


func test_coarsening_never_leaves_the_area_uncovered() -> void:
	var terrain := _terrain()
	var parent := ChunkKey.make(0, 1, 0, 0)
	terrain.set_plan_for_test(_children(parent))
	terrain._show_chunk(parent, _fake_mesh(1))
	for child in _children(parent):
		terrain._show_chunk(child, _fake_mesh(2))
	terrain.set_plan_for_test([parent])
	terrain._update_visibility()
	assert_true(not terrain._displayed.is_empty(), "the visibility pass cannot hide both layers")
	assert_true(terrain._is_covered(parent), "the parent area remains covered")
	for child in _children(parent):
		assert_true(not (terrain._displayed.has(parent) and terrain._displayed.has(child)), "never two layers")
	terrain.free()


func test_coarse_mesh_vertices_still_sample_the_height_function() -> void:
	var planet := _planet()
	for grid in [ChunkMesher.grid_for_level(0), ChunkMesher.PREVIEW_GRID, ChunkMesher.FINE_GRID]:
		var data := ChunkMesher.build(ChunkKey.make(0, 0, 0, 0), planet, grid)
		var vertices: PackedVector3Array = data["vertices"]
		var origin: PackedFloat64Array = data["origin"]
		var surface_count := (int(data["grid"]) + 1) * (int(data["grid"]) + 1)
		var worst := 0.0
		for i in surface_count:
			var world := vertices[i] + Vector3(origin[0], origin[1], origin[2])
			var direction := world.normalized()
			var expected := planet.surface_radius_xyz(direction.x, direction.y, direction.z)
			worst = maxf(worst, absf(world.length() - expected))
		assert_true(worst < 0.05, "grid %d mesh still follows the height source: %f m" % [grid, worst])


func test_coarse_grid_normals_are_finite_at_face_edges() -> void:
	# Regression: the normal ring of a coarse face reached u = -1.5, where the spherified-cube
	# mapping took the square root of a negative number and fed NaN into the height noise.
	var planet := _planet()
	for face in 6:
		var data := ChunkMesher.build(ChunkKey.make(face, 0, 0, 0), planet, 4)
		for normal in (data["normals"] as PackedVector3Array):
			assert_true(normal.is_finite() and absf(normal.length() - 1.0) < 1e-3, "face %d normal is a finite unit vector" % face)
	for u in [-1.5, -1.25, 1.3]:
		var direction := CubeSphere.direction(0, u, 0.9)
		assert_true(direction.is_finite() and absf(direction.length() - 1.0) < 1e-6, "off-face direction is a finite unit vector")
	assert_true(CubeSphere.direction(2, 0.25, -0.5).is_equal_approx(CubeSphere.direction(2, 0.25, -0.5)), "on-face mapping unchanged")


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
	var terrain := _terrain()
	for face in 6:
		terrain._desired[ChunkKey.make(face, 0, 0, 0)] = true
	for face in 6:
		terrain._show_chunk(ChunkKey.make(face, 0, 0, 0), _fake_mesh(0))
	assert_true(terrain.displayed_coverage_is_complete(), "six face chunks cover every root face")
	terrain.free()


## Violent movement: random teleports and turns, with builds finishing in random order and
## random subsets. With the level-0 backstop present there must never be a hole, and no visible chunk may
## have a visible ancestor (one layer only).
func test_random_viewer_jumps_never_leave_holes_or_double_layers() -> void:
	var terrain := _terrain()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1414
	terrain.viewer = WorldPos.new(&"planet", 0.0, 0.0, 100000.0 + 5000.0)
	terrain._replan()
	for key in terrain._fallback:
		if ChunkKey.level_of(key) == 0:
			terrain._add_chunk(key, _fake_mesh(0, ChunkMesher.grid_for_level(0)))
	var violations := 0
	for step in 60:
		var direction := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		if step % 3 != 0:
			# Short hops along the surface (fast flight), sometimes back again.
			var previous := Vector3(terrain.viewer.x, terrain.viewer.y, terrain.viewer.z).normalized()
			direction = (previous + Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.05, 0.05), rng.randf_range(-0.05, 0.05))).normalized()
		var altitude := rng.randf_range(10.0, 20000.0)
		var position := direction * (100000.0 + altitude)
		terrain.viewer = WorldPos.new(&"planet", position.x, position.y, position.z)
		terrain.viewer_velocity = Vector3(rng.randfn(), rng.randfn(), rng.randfn()) * rng.randf_range(0.0, 8000.0)
		terrain._replan()
		# Finish a random part of the queue, in random order.
		var queue := terrain._build_order.duplicate()
		queue.shuffle()
		for key in queue.slice(0, rng.randi_range(0, mini(queue.size(), 40))):
			terrain._add_chunk(key, _fake_mesh(ChunkKey.level_of(key), PlanetTerrain._required_grid(key, terrain._desired.has(key))))
		terrain._update_visibility()
		if not terrain.desired_has_no_holes():
			violations += 1
		for key in terrain._displayed:
			var ancestor: int = key
			while ChunkKey.level_of(ancestor) > 0:
				ancestor = ChunkKey.parent_of(ancestor)
				if terrain._displayed.has(ancestor):
					violations += 1
					break
	assert_eq(violations, 0, "no holes and no overlapping layers across random jumps")
	assert_true(terrain.ready_cache_entries() <= terrain.READY_CACHE_MAX_ENTRIES, "cache bounded after the run")
	terrain.free()
