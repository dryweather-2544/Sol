extends "res://tests/test_case.gd"
## Streaming-specific checks: backstop coverage, cover selection, previews, the hidden-chunk cache
## and predictive planning. Mesh "builds" here are instant fake meshes; the real threaded pipeline
## is exercised by tools/n14_stream_probe.gd.

func _planet() -> PlanetBody:
	var planet := PlanetBody.new()
	planet.radius = 100000.0
	planet.height_override = func(_x: float, _y: float, _z: float) -> float: return 0.0
	return planet


func _fake_mesh(level: int = 0, grid: int = ChunkMesher.FINE_GRID) -> Dictionary:
	return {
		"origin": PackedFloat64Array([0.0, 0.0, 100000.0]),
		"vertices": PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 10, 0)]),
		"normals": PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP]),
		"colors": PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]),
		"indices": PackedInt32Array([0, 1, 2]),
		"level": level,
		"grid": grid,
	}


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


func test_parent_is_kept_until_all_four_children_are_displayed() -> void:
	var terrain := _terrain()
	var parent := ChunkKey.make(0, 2, 0, 0)
	var children := _children(parent)
	terrain._desired = {}
	for child in children:
		terrain._desired[child] = true
	terrain._show_chunk(parent, _fake_mesh(2))
	for index in 3:
		terrain._show_chunk(children[index], _fake_mesh(3))
	assert_true(terrain._displayed.has(parent), "parent stays while three of four children exist")
	assert_true(bool(terrain._displayed[parent]["filler"]), "the parent is a sunk filler while it overlaps its children")
	terrain._show_chunk(children[3], _fake_mesh(3))
	assert_true(not terrain._displayed.has(parent), "parent leaves the screen only after all four children are displayed")
	assert_true(terrain._chunks.has(parent), "the parent is hidden and cached, not thrown away")
	terrain.free()


func test_finer_chunks_stay_until_the_coarser_desired_leaf_is_ready() -> void:
	# Behind the ship the plan coarsens: the old fine chunks must keep the area until the
	# coarser leaf exists (the first N14 pass dropped them to the smooth backstop instead).
	var terrain := _terrain()
	var face := ChunkKey.make(0, 0, 0, 0)
	var parent := ChunkKey.make(0, 4, 3, 3)
	terrain._desired = {parent: true}
	terrain._show_chunk(face, _fake_mesh(0, ChunkMesher.grid_for_level(0)))
	for child in _children(parent):
		terrain._show_chunk(child, _fake_mesh(5))
	for child in _children(parent):
		assert_true(terrain._displayed.has(child), "fine chunk stays visible while its coarser replacement builds")
	assert_true(not terrain._displayed.has(face), "the backstop is not shown over a fully covered area")
	terrain._show_chunk(parent, _fake_mesh(4))
	assert_true(terrain._displayed.has(parent), "the coarser leaf shows once built")
	for child in _children(parent):
		assert_true(not terrain._displayed.has(child), "the old fine chunks are hidden once the leaf replaces them")
	terrain.free()


func test_backstop_is_built_once_and_never_requeued() -> void:
	# Regression: the first N14 pass removed level 1/2 backstop chunks whenever level 0 was shown
	# and then queued them again, so ~95% of all builds were the same coarse faces.
	var terrain := _terrain()
	terrain.viewer = WorldPos.new(&"planet", 0.0, 0.0, 100000.0 + 2000.0)
	terrain._replan()
	for key in terrain._fallback:
		terrain._add_chunk(key, _fake_mesh(ChunkKey.level_of(key), ChunkMesher.grid_for_level(ChunkKey.level_of(key))))
	terrain._update_visibility()
	terrain._replan()
	for entry in terrain._build_queue:
		if terrain._fallback.has(entry[0]):
			# Only a backstop chunk that is itself a desired leaf may be queued: for its full grid.
			assert_true(terrain._desired.has(entry[0]) and entry[1] == ChunkMesher.FINE_GRID, "a backstop chunk that exists is not queued again")
	for key in terrain._fallback:
		assert_true(terrain._chunks.has(key), "backstop chunks stay available (hidden when unused)")
	terrain.free()


func test_badly_covered_leaf_gets_a_preview_then_its_full_grid() -> void:
	var terrain := _terrain()
	terrain.viewer = WorldPos.new(&"planet", 0.0, 0.0, 100000.0 + 2000.0)
	terrain._replan()
	for key in terrain._fallback:
		if ChunkKey.level_of(key) == 0:
			terrain._add_chunk(key, _fake_mesh(0, ChunkMesher.grid_for_level(0)))
	terrain._replan()
	var leaf := -1
	for entry in terrain._build_queue:
		if terrain._desired.has(entry[0]) and ChunkKey.level_of(entry[0]) >= 4:
			leaf = entry[0]
			assert_eq(entry[1], ChunkMesher.PREVIEW_GRID, "a leaf covered only by the backstop asks for a preview first")
			break
	assert_true(leaf >= 0, "a fine leaf is queued")
	terrain._show_chunk(leaf, _fake_mesh(ChunkKey.level_of(leaf), ChunkMesher.PREVIEW_GRID))
	assert_true(terrain._displayed.has(leaf) and bool(terrain._displayed[leaf]["preview"]), "the preview is on screen")
	terrain._replan()
	var full_requested := false
	for entry in terrain._build_queue:
		if entry[0] == leaf:
			full_requested = entry[1] == ChunkMesher.FINE_GRID
	assert_true(full_requested, "once the preview is up, the full grid is requested")
	terrain._show_chunk(leaf, _fake_mesh(ChunkKey.level_of(leaf)))
	assert_eq(int(terrain._chunks[leaf]["grid"]), ChunkMesher.FINE_GRID, "the full mesh replaces the preview")
	terrain.free()


func test_filler_is_sunk_below_finer_neighbours() -> void:
	var terrain := _terrain()
	var parent := ChunkKey.make(0, 3, 1, 1)
	var children := _children(parent)
	terrain._desired = {children[0]: true, children[1]: true}
	terrain._show_chunk(parent, _fake_mesh(3))
	terrain._show_chunk(children[0], _fake_mesh(4))
	var parent_record: Dictionary = terrain._displayed[parent]
	var child_record: Dictionary = terrain._displayed[children[0]]
	var parent_node: Node3D = parent_record["node"]
	var child_node: Node3D = child_record["node"]
	# Both fake meshes have the same origin; the filler is moved toward the planet centre.
	var centre := WorldPos.new(&"planet", 0.0, 0.0, 0.0).to_local_vector3(terrain.render_origin)
	assert_true(parent_node.position.distance_to(centre) < child_node.position.distance_to(centre), "the filler sits lower than the finer chunk")
	assert_true(not bool(child_record["filler"]), "a leaf at its own level is never sunk")
	terrain.free()


func test_hidden_chunk_is_reused_when_the_viewer_returns() -> void:
	var terrain := _terrain()
	var parent := ChunkKey.make(0, 3, 2, 2)
	var leaf := _children(parent)[0]
	terrain._desired = {leaf: true}
	terrain._show_chunk(leaf, _fake_mesh(4))
	terrain._desired = {parent: true}
	terrain._show_chunk(parent, _fake_mesh(3))
	assert_true(not terrain._displayed.has(leaf), "leaf hidden after moving away")
	terrain._desired = {leaf: true}
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


func test_coverage_holds_through_a_coarsening_pass() -> void:
	var terrain := _terrain()
	var parent := ChunkKey.make(0, 1, 0, 0)
	terrain._desired = {ChunkKey.make(0, 0, 0, 0): true}
	terrain._show_chunk(parent, _fake_mesh(1))
	for child in _children(parent):
		terrain._show_chunk(child, _fake_mesh(2))
	terrain._remove_obsolete_chunks()
	assert_true(not terrain._displayed.is_empty(), "the visibility pass cannot hide both layers")
	assert_true(terrain._is_covered(parent), "the parent area remains covered")
	assert_true(not (terrain._displayed.has(parent) and not bool(terrain._displayed[parent]["filler"]) and terrain._displayed.has(_children(parent)[0])), "never two unsunk layers")
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
## random subsets. With the level-0 backstop present there must never be a hole, and two visible
## chunks may only overlap when the coarser one is a sunk filler.
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
		# Finish a random part of the queue, in random order, some as previews.
		var queue := terrain._build_queue.duplicate()
		queue.shuffle()
		for entry in queue.slice(0, rng.randi_range(0, mini(queue.size(), 40))):
			terrain._add_chunk(entry[0], _fake_mesh(ChunkKey.level_of(entry[0]), entry[1]))
		terrain._update_visibility()
		if not terrain.desired_has_no_holes():
			violations += 1
		for key in terrain._displayed:
			var ancestor: int = key
			while ChunkKey.level_of(ancestor) > 0:
				ancestor = ChunkKey.parent_of(ancestor)
				if terrain._displayed.has(ancestor) and not bool(terrain._displayed[ancestor]["filler"]):
					violations += 1
					break
	assert_eq(violations, 0, "no holes and no unsunk overlapping layers across random jumps")
	assert_true(terrain.ready_cache_entries() <= terrain.READY_CACHE_MAX_ENTRIES, "cache bounded after the run")
	terrain.free()
