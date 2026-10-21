extends "res://tests/test_case.gd"


func test_chunk_vertices_lie_on_the_height_function_and_arrays_are_consistent() -> void:
	var planet := PlanetBody.new()
	var key := ChunkKey.make(2, 12, 1000, 2000)
	var mesh_data := ChunkMesher.build(key, planet)
	var vertices: PackedVector3Array = mesh_data["vertices"]
	var normals: PackedVector3Array = mesh_data["normals"]
	var indices: PackedInt32Array = mesh_data["indices"]
	var origin: PackedFloat64Array = mesh_data["origin"]
	var grid: int = mesh_data["grid"]
	var surface_vertex_count := (grid + 1) * (grid + 1)
	assert_true(vertices.size() > surface_vertex_count, "skirt vertices exist")
	assert_eq(normals.size(), vertices.size())
	assert_eq((mesh_data["colors"] as PackedColorArray).size(), vertices.size())
	var largest_index := 0
	for index in indices:
		largest_index = maxi(largest_index, index)
	assert_eq(largest_index, vertices.size() - 1)
	assert_eq(indices.size() % 3, 0)
	var worst_height_error := 0.0
	var worst_normal_length_error := 0.0
	for vertex_index in surface_vertex_count:
		var world_x: float = vertices[vertex_index].x + origin[0]
		var world_y: float = vertices[vertex_index].y + origin[1]
		var world_z: float = vertices[vertex_index].z + origin[2]
		var distance := sqrt(world_x * world_x + world_y * world_y + world_z * world_z)
		var expected := planet.surface_radius_xyz(world_x / distance, world_y / distance, world_z / distance)
		worst_height_error = maxf(worst_height_error, absf(distance - expected))
		worst_normal_length_error = maxf(worst_normal_length_error, absf(normals[vertex_index].length() - 1.0))
		assert_true(normals[vertex_index].dot(Vector3(world_x, world_y, world_z).normalized()) > 0.0, "normal points outward")
	assert_true(worst_height_error < 0.05, "vertex vs height function: %f m" % worst_height_error)
	assert_true(worst_normal_length_error < 1e-4)
	for vertex_index in range(surface_vertex_count, vertices.size()):
		var surface_neighbour := vertices[vertex_index]
		assert_true(surface_neighbour.length() < 1.0e6, "skirt vertices are chunk-local")


func test_triangles_wind_clockwise_seen_from_outside() -> void:
	var planet := PlanetBody.new()
	for face in 6:
		var mesh_data := ChunkMesher.build(ChunkKey.make(face, 8, 100, 100), planet)
		var vertices: PackedVector3Array = mesh_data["vertices"]
		var indices: PackedInt32Array = mesh_data["indices"]
		var origin: PackedFloat64Array = mesh_data["origin"]
		var outward := Vector3(origin[0], origin[1], origin[2]).normalized()
		var triangle_normal := (vertices[indices[1]] - vertices[indices[0]]).cross(vertices[indices[2]] - vertices[indices[0]])
		assert_true(triangle_normal.dot(outward) < 0.0, "face %d: Godot front faces are clockwise, so geometric normal points inward" % face)


func test_colour_masks_poles_snow_steepness_and_airless_palette() -> void:
	var profile := TerrainProfile.new()
	var equator_low := ChunkMesher._color_for(profile, 100.0, 0.0, 0.0)
	var pole_low := ChunkMesher._color_for(profile, 100.0, 0.0, 0.97)
	assert_true(pole_low.get_luminance() > equator_low.get_luminance() + 0.3, "polar caps are white even at low height")
	var high_equator := ChunkMesher._color_for(profile, 4000.0, 0.0, 0.0)
	var peak := ChunkMesher._color_for(profile, 5200.0, 0.0, 0.0)
	assert_true(peak.get_luminance() > high_equator.get_luminance(), "snow above the snow line")
	var flat := ChunkMesher._color_for(profile, 800.0, 0.0, 0.2)
	var cliff := ChunkMesher._color_for(profile, 800.0, 0.2, 0.2)
	var rock := Vector3(profile.palette_rock.r, profile.palette_rock.g, profile.palette_rock.b)
	assert_true(Vector3(cliff.r, cliff.g, cliff.b).distance_to(rock) < Vector3(flat.r, flat.g, flat.b).distance_to(rock), "steep ground shows bare rock")
	var moon := StarSystem.default_system().bodies[&"selene"].terrain_profile as TerrainProfile
	assert_true(ChunkMesher._color_for(moon, 5000.0, 0.0, 0.98).get_luminance() < 0.9, "the airless moon has no snow caps")


func test_lod_grids_are_progressive_and_preserve_coarse_shape() -> void:
	var planet := PlanetBody.new()
	var previous_grid := 0
	for level in [2, 1, 0]:
		assert_true(ChunkMesher.grid_for_level(level) > previous_grid, "backstop grids get finer toward level 0 (the biggest face)")
		previous_grid = ChunkMesher.grid_for_level(level)
	for level in [0, 1, 2, 3, 6, 10]:
		for grid in [ChunkMesher.grid_for_level(level), ChunkMesher.PREVIEW_GRID, ChunkMesher.FINE_GRID]:
			var mesh_data := ChunkMesher.build(ChunkKey.make(0, level, 0, 0), planet, grid)
			assert_eq(int(mesh_data["grid"]), grid)
			var vertices: PackedVector3Array = mesh_data["vertices"]
			assert_true(vertices.size() > (grid + 1) * (grid + 1), "skirt vertices exist at level %d grid %d" % [level, grid])
			var normals: PackedVector3Array = mesh_data["normals"]
			for i in mini(vertices.size(), 64):
				assert_true(normals[i].length() > 0.99 and normals[i].length() < 1.01, "normal is unit length")
	assert_eq(int(ChunkMesher.build(ChunkKey.make(0, 10, 0, 0), planet)["grid"]), ChunkMesher.FINE_GRID, "the default build is the full grid")


func test_geomorph_offsets_lead_to_the_parent_shape() -> void:
	var planet := PlanetBody.new()
	planet.height_override = func(dx: float, dy: float, dz: float) -> float: return 40.0 * sin(dx * 900.0) * cos(dz * 700.0)
	var mesh_data := ChunkMesher.build(ChunkKey.make(2, 12, 1000, 2000), planet)
	var vertices: PackedVector3Array = mesh_data["vertices"]
	var morph: PackedVector3Array = mesh_data["morph"]
	var grid: int = mesh_data["grid"]
	var per_edge := grid + 1
	assert_eq(morph.size(), vertices.size(), "one offset per vertex, skirts included")
	for row in per_edge:
		for column in per_edge:
			var index := row * per_edge + column
			if row % 2 == 0 and column % 2 == 0:
				assert_true(morph[index] == Vector3.ZERO, "vertices shared with the parent do not move")
			elif row % 2 == 1 and column % 2 == 1:
				var target := (vertices[index + per_edge - 1] + vertices[index - per_edge + 1]) * 0.5
				assert_true((vertices[index] + morph[index]).is_equal_approx(target), "a cell centre goes to the midpoint of the shared diagonal")
			elif row % 2 == 1:
				var target := (vertices[index - per_edge] + vertices[index + per_edge]) * 0.5
				assert_true((vertices[index] + morph[index]).is_equal_approx(target), "an odd row goes to the midpoint along its column")
			else:
				var target := (vertices[index - 1] + vertices[index + 1]) * 0.5
				assert_true((vertices[index] + morph[index]).is_equal_approx(target), "an odd column goes to the midpoint along its row")
	for skirt_index in range(per_edge * per_edge, vertices.size()):
		assert_true(morph[skirt_index].length() < 1.0e4, "skirt offsets are finite and local")


func test_chunk_reports_its_centre_height_and_makes_a_mesh() -> void:
	var planet := PlanetBody.new()
	planet.height_override = func(_dx: float, _dy: float, _dz: float) -> float: return 123.0
	var mesh_data := ChunkMesher.build(ChunkKey.make(0, 9, 100, 100), planet)
	assert_near(float(mesh_data["centre_height"]), 123.0, 1e-3, "the centre height")
	var mesh := ChunkMesher.make_mesh(mesh_data)
	assert_eq(mesh.get_surface_count(), 1, "one surface")
