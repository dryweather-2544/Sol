extends "res://tests/test_case.gd"


func test_chunk_vertices_lie_on_the_height_function_and_arrays_are_consistent() -> void:
	var planet := PlanetBody.new()
	var key := ChunkKey.make(2, 12, 1000, 2000)
	var mesh_data := ChunkMesher.build(key, planet)
	var vertices: PackedVector3Array = mesh_data["vertices"]
	var normals: PackedVector3Array = mesh_data["normals"]
	var indices: PackedInt32Array = mesh_data["indices"]
	var origin: PackedFloat64Array = mesh_data["origin"]
	var surface_vertex_count := (ChunkMesher.GRID + 1) * (ChunkMesher.GRID + 1)
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
