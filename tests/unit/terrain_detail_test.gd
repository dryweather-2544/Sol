extends "res://tests/test_case.gd"
## N9 S6: the terrain detail shader inputs. Needs the terrain textures imported (tools/run_tests.sh imports first).


func test_world_to_layer_rule() -> void:
	assert_eq(TerrainDetail.flat_layer_id(0.0), "mat_terrain_regolith", "airless worlds (Selene, Pebble) get regolith")
	assert_eq(TerrainDetail.flat_layer_id(200000.0), "mat_terrain_soil_dry", "worlds with an atmosphere get dry soil")


func test_tile_offset_repeats_every_348_metres_and_handles_negatives() -> void:
	var origin := PackedFloat64Array([1234567.891, -987654.321, 5.5])
	var shifted := PackedFloat64Array([origin[0] + 348.0 * 4000.0, origin[1] - 348.0 * 123.0, origin[2] + 348.0])
	var first := TerrainDetail.tile_offset(origin)
	var second := TerrainDetail.tile_offset(shifted)
	assert_true(first.distance_to(second) < 0.01, "a shift by whole periods changes nothing (%s vs %s)" % [str(first), str(second)])
	for axis in 3:
		assert_true(first[axis] >= 0.0 and first[axis] < 348.0, "axis %d is inside one period" % axis)


func test_tile_period_divides_every_texture_scale() -> void:
	for tile_metres in [4.0, 6.0, 29.0]:
		assert_near(fposmod(TerrainDetail.TILE_PERIOD, tile_metres), 0.0, 0.0001, "%s m tiles repeat inside 348 m" % str(tile_metres))


func test_material_has_all_layers_and_the_right_means() -> void:
	var settings := GameSettings.instance()
	var original := settings.terrain_detail
	settings.terrain_detail = true
	var airless := TerrainDetail.build_material(0.0)
	var airy := TerrainDetail.build_material(200000.0)
	assert_true(airless != null and airy != null, "both materials build (textures copied and imported)")
	if airless != null and airy != null:
		for uniform_name in ["flat_albedo", "flat_normal", "flat_orm", "steep_albedo", "steep_normal", "steep_orm"]:
			assert_true(airless.get_shader_parameter(uniform_name) is Texture2D, "%s is set" % uniform_name)
		assert_near(airless.get_shader_parameter("flat_mean_linear"), 0.2148, 0.00001, "regolith mean")
		assert_near(airy.get_shader_parameter("flat_mean_linear"), 0.2066, 0.00001, "soil mean")
		assert_near(airy.get_shader_parameter("steep_mean_linear"), 0.1515, 0.00001, "rock mean")
	settings.terrain_detail = original


func test_means_match_the_asset_notes() -> void:
	for layer_id in TerrainDetail.MEAN_LINEAR_LUMINANCE:
		var notes_path := "res://assets/sol/materials/%s/SOURCE.md" % layer_id
		if not FileAccess.file_exists(notes_path):
			assert_true(false, "%s exists" % notes_path)
			continue
		var notes := FileAccess.get_file_as_string(notes_path)
		assert_true(notes.contains(str(TerrainDetail.MEAN_LINEAR_LUMINANCE[layer_id])), "%s notes state the mean %s" % [layer_id, str(TerrainDetail.MEAN_LINEAR_LUMINANCE[layer_id])])


func test_switch_off_gives_the_plain_material() -> void:
	var settings := GameSettings.instance()
	var original := settings.terrain_detail
	settings.terrain_detail = false
	assert_true(TerrainDetail.build_material(0.0) == null, "no detail material")
	var terrain := PlanetTerrain.new(PlanetBody.new())
	assert_true(terrain._detail_material == null, "the terrain keeps its plain vertex-colour material")
	terrain.free()
	settings.terrain_detail = original


func test_terrain_uses_the_detail_material_when_on() -> void:
	var settings := GameSettings.instance()
	var original := settings.terrain_detail
	settings.terrain_detail = true
	var terrain := PlanetTerrain.new(PlanetBody.new())
	assert_true(terrain._detail_material != null, "the detail material is built")
	terrain.free()
	settings.terrain_detail = original


func test_steep_weight_curve() -> void:
	assert_near(ChunkMesher.steep_weight(0.0), 0.0, 0.0001, "flat ground")
	assert_near(ChunkMesher.steep_weight(0.1), 0.5, 0.0001, "the mid point is at steepness 0.1 (about 26 degrees)")
	assert_near(ChunkMesher.steep_weight(0.3), 1.0, 0.0001, "a 45 degree slope is fully rock")
	assert_true(ChunkMesher.steep_weight(0.08) < ChunkMesher.steep_weight(0.12), "monotonic")


func test_flat_chunk_has_zero_steep_weight_and_unchanged_geometry_arrays() -> void:
	var planet := PlanetBody.new()
	planet.height_override = func(_dx: float, _dy: float, _dz: float) -> float: return 0.0
	var mesh_data := ChunkMesher.build(ChunkKey.make(1, 10, 300, 400), planet)
	var colors: PackedColorArray = mesh_data["colors"]
	var largest_alpha := 0.0
	for color in colors:
		largest_alpha = maxf(largest_alpha, color.a)
	assert_true(largest_alpha < 0.01, "a perfectly round planet has no steep ground (largest alpha %f)" % largest_alpha)
	assert_eq(colors.size(), (mesh_data["vertices"] as PackedVector3Array).size(), "one colour per vertex")
