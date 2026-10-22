extends "res://tests/test_case.gd"
## Rodina's exact planet functions (RodinaPlanets) and the plumbing around them. The GPU shader itself can only be
## checked on a machine with a GPU: tools/gpu_height_check.gd.


func _random_direction(rng: SeedRng) -> Vector3:
	return Vector3(rng.next_float() - 0.5, rng.next_float() - 0.5, rng.next_float() - 0.5).normalized()


func test_voronoi_points_are_a_fixed_set_of_unit_vectors() -> void:
	var points := RodinaPlanets.points()
	assert_eq(points.size(), RodinaPlanets.VORONOI_COUNT)
	for index in points.size():
		assert_near(points[index].length(), 1.0, 1e-5, "point %d is on the unit sphere" % index)
	assert_eq(RodinaPlanets.points_as_floats().size(), RodinaPlanets.VORONOI_COUNT * 4)


func test_grid_search_matches_brute_force_nearest_two() -> void:
	var points := RodinaPlanets.points()
	var rng := SeedRng.new(77)
	for sample in 150:
		var p := _random_direction(rng)
		var best1 := INF
		for point in points:
			best1 = minf(best1, p.distance_to(point))
		var best2 := INF
		for point in points:
			var distance := p.distance_to(point)
			if distance > best1 and distance < best2:
				best2 = distance
		var fast := RodinaPlanets.nearest_two(p)
		assert_near(fast.x, best1, 1e-6, "nearest")
		assert_near(fast.y, best2, 1e-6, "second nearest")


func test_hlsl_analogue_handles_reversed_and_zero_width_ranges() -> void:
	assert_near(RodinaPlanets.analogue(0.0, 1.0, -1.0, 0.0, 1.0), 0.5, 1e-9, "reversed source range")
	assert_near(RodinaPlanets.analogue(1.0, 1.0, -1.0, 0.0, 1.0), 0.0, 1e-9)
	assert_near(RodinaPlanets.analogue(-1.0, 1.0, -1.0, 0.0, 1.0), 1.0, 1e-9)
	assert_near(RodinaPlanets.analogue(0.0, -1.0, -1.0, 0.0, 1.0), 1.0, 1e-9, "zero width above the edge saturates to 1")
	assert_near(RodinaPlanets.analogue(-2.0, -1.0, -1.0, 0.0, 1.0), 0.0, 1e-9, "zero width below the edge is 0")
	assert_near(RodinaPlanets.hsmooth(0.55, 0.375, 0.4), 0.8571 * 0.8571 * (3.0 - 2.0 * 0.8571), 1e-3, "reversed smoothstep edges")


func test_every_grammar_makes_finite_varied_terrain_and_is_deterministic() -> void:
	for grammar in [TerrainProfile.Grammar.PERUN, TerrainProfile.Grammar.JARILO, TerrainProfile.Grammar.VELES, TerrainProfile.Grammar.MORENA, TerrainProfile.Grammar.ASTEROID]:
		var rng := SeedRng.new(900 + grammar)
		var lowest := INF
		var highest := -INF
		for sample in 30:
			var direction := _random_direction(rng)
			var height := RodinaPlanets.height(grammar, direction, 6000000.0)
			assert_true(is_finite(height), "grammar %d finite" % grammar)
			assert_eq(height, RodinaPlanets.height(grammar, direction, 6000000.0), "grammar %d deterministic" % grammar)
			lowest = minf(lowest, height)
			highest = maxf(highest, height)
		assert_true(highest - lowest > 100.0, "grammar %d should make relief, got %f..%f" % [grammar, lowest, highest])
		assert_true(lowest > -100000.0 and highest < 150000.0, "grammar %d range %f..%f" % [grammar, lowest, highest])


func test_exact_height_function_uses_the_rodina_planets() -> void:
	var profile := TerrainProfile.new()
	profile.grammar = TerrainProfile.Grammar.JARILO
	var function := HeightFunction.new(profile)
	function.exact = true
	var rng := SeedRng.new(31)
	for sample in 10:
		var direction := _random_direction(rng)
		assert_eq(function.height_xyz(direction.x, direction.y, direction.z), RodinaPlanets.height(TerrainProfile.Grammar.JARILO, direction, profile.radius))


func test_legacy_grammar_is_never_exact() -> void:
	var function := HeightFunction.new(TerrainProfile.new())
	assert_true(not function.exact)


func test_without_a_gpu_the_mesher_still_builds_chunks() -> void:
	GpuHeights.set_enabled(false)
	var planet := PlanetBody.new()
	planet.height_function.profile.grammar = TerrainProfile.Grammar.JARILO
	var mesh := ChunkMesher.build(ChunkKey.make(4, 3, 1, 1), planet, 8)
	assert_true(mesh["vertices"].size() > 80, "a chunk is built on the CPU path")


func test_rodina_feature_colours_reach_the_mesh_vertices() -> void:
	GpuHeights.set_enabled(false)
	var planet := PlanetBody.new()
	planet.height_function.profile.grammar = TerrainProfile.Grammar.PERUN
	var look := PlanetLook.new()
	look.rodina_feature_colors = true
	look.rodina_terrain_gates = false # plain feature colour: the gated colour also depends on height and slope
	planet.look = look
	var mesh := ChunkMesher.build(ChunkKey.make(4, 3, 1, 1), planet, 8)
	var vertices: PackedVector3Array = mesh["vertices"]
	var colors: PackedColorArray = mesh["colors"]
	var origin: PackedFloat64Array = mesh["origin"]
	assert_eq(colors.size(), vertices.size(), "one colour per vertex")
	var checked := 0
	for index in mini(vertices.size(), 40):
		var world := vertices[index] + Vector3(origin[0], origin[1], origin[2])
		var expected := look.rodina_surface_color(TerrainProfile.Grammar.PERUN, world)
		assert_near(colors[index].r, expected.r, 1e-3, "vertex %d red" % index)
		assert_near(colors[index].g, expected.g, 1e-3, "vertex %d green" % index)
		checked += 1
	assert_true(checked > 10, "checked some vertices")


# --- Feature texture and colours ------------------------------------------------------------------------------

const _GRAMMARS := [TerrainProfile.Grammar.PERUN, TerrainProfile.Grammar.JARILO, TerrainProfile.Grammar.VELES, TerrainProfile.Grammar.MORENA, TerrainProfile.Grammar.ASTEROID]


func test_hue_saturate_value_matches_hand_computed_lua_colours() -> void:
	var jarilo_1a := RodinaPlanets.hue_saturate_value(45.0, 0.5, 0.61)
	assert_near(jarilo_1a.r, 0.61, 1e-6, "high is v")
	assert_near(jarilo_1a.g, 0.305 + 0.305 * 0.75, 1e-6, "45 degrees is 3/4 of the way up the first sector")
	assert_near(jarilo_1a.b, 0.305, 1e-6, "low is v*(1-s)")
	var grey := RodinaPlanets.hue_saturate_value(0.0, 0.0, -0.8)
	assert_near(grey.r, -0.8, 1e-6, "negative values are kept")
	assert_near(grey.g, -0.8, 1e-6)
	var blue := RodinaPlanets.hue_saturate_value(230.0, 0.4, 1.2)
	assert_true(blue.b > blue.g and blue.g > blue.r, "hue 230 is blue-leaning")
	assert_near(RodinaPlanets.hue_saturate_value(360.0, 1.0, 1.0).r, 1.0, 1e-9, "360 wraps to red")


func test_feature_colours_exist_for_every_grammar_and_follow_the_material_formula() -> void:
	for grammar in _GRAMMARS:
		assert_eq(RodinaPlanets.feature_colors(grammar).size(), 5, "grammar %d has Color1a/1b/2/3/4" % grammar)
	assert_true(RodinaPlanets.feature_colors(TerrainProfile.Grammar.LEGACY).is_empty())
	var colors := RodinaPlanets.feature_colors(TerrainProfile.Grammar.PERUN)
	var plain := RodinaPlanets.feature_color(TerrainProfile.Grammar.PERUN, Vector4(0.0, 0.0, 0.0, 0.0))
	assert_near(plain.r, 0.25, 1e-9, "base 0 gives Color1a")
	var full := RodinaPlanets.feature_color(TerrainProfile.Grammar.PERUN, Vector4(1.0, 1.0, 1.0, 1.0))
	var c2: Color = colors["c2"]
	var c3: Color = colors["c3"]
	var c4: Color = colors["c4"]
	assert_near(full.r, 0.125 + c2.r + c3.r + c4.r, 1e-6, "all four features add up, base 1 gives Color1b")


func test_features_are_finite_deterministic_in_range_and_varied_for_every_grammar() -> void:
	for grammar in _GRAMMARS:
		var rng := SeedRng.new(4100 + grammar)
		var seen := [INF, INF, INF, INF]
		var peak := [-INF, -INF, -INF, -INF]
		for sample in 60:
			var direction := _random_direction(rng)
			var feature := RodinaPlanets.features(grammar, direction)
			assert_true(is_finite(feature.x) and is_finite(feature.y) and is_finite(feature.z) and is_finite(feature.w), "grammar %d finite" % grammar)
			assert_eq(feature, RodinaPlanets.features(grammar, direction), "grammar %d deterministic" % grammar)
			for channel in 4:
				seen[channel] = minf(seen[channel], feature[channel])
				peak[channel] = maxf(peak[channel], feature[channel])
		# Perun/Jarilo/Veles/Asteroid features are all 0..1 (Veles plateau can dip below 0 by its crack term); Morena base is raw noise.
		for channel in [2, 3]:
			assert_true(seen[channel] >= -1e-6 and peak[channel] <= 1.0 + 1e-6, "grammar %d channel %d in 0..1, got %f..%f" % [grammar, channel, seen[channel], peak[channel]])
	# Perun must actually use more than one feature across the planet, or the colour would be flat.
	var rng := SeedRng.new(31)
	var plateau_total := 0.0
	var mountain_total := 0.0
	for sample in 120:
		var feature := RodinaPlanets.features(TerrainProfile.Grammar.PERUN, _random_direction(rng))
		plateau_total += feature.y
		mountain_total += feature.z
	assert_true(plateau_total > 1.0 and mountain_total > 0.1, "Perun has plateaus and mountains somewhere (%f, %f)" % [plateau_total, mountain_total])


func test_features_agree_with_the_height_functions_about_where_things_are() -> void:
	# Perun: wherever the feature texture says there is no plateau, no mountain and no hole, only the base term makes height.
	var rng := SeedRng.new(515)
	var checked := 0
	for sample in 200:
		var direction := _random_direction(rng)
		var feature := RodinaPlanets.perun_features(direction)
		if feature.y <= 0.0 and feature.z <= 0.0:
			assert_true(RodinaPlanets.perun(direction) <= 500.0 + 1e-3, "flat-feature ground is at most the base term's 500 m")
			checked += 1
	assert_true(checked > 0, "found at least one lowland sample")


func test_planet_look_feature_colours_are_valid_linear_vertex_colours_and_off_by_default() -> void:
	var look := PlanetLook.new()
	var profile := TerrainProfile.new()
	profile.grammar = TerrainProfile.Grammar.PERUN
	var palette := look.surface_color(profile, 100.0, 0.0, 0.2, Vector3(6000000.0, 0.0, 0.0))
	look.rodina_feature_colors = true
	var rng := SeedRng.new(8)
	var distinct := {}
	for sample in 40:
		var world := _random_direction(rng) * 6000000.0
		var color := look.surface_color(profile, 100.0, 0.0, 0.2, world)
		assert_true(color.r >= 0.0 and color.r <= 1.0 and color.g >= 0.0 and color.g <= 1.0 and color.b >= 0.0 and color.b <= 1.0, "colour within 0..1")
		distinct[snappedf(color.r, 0.002)] = true
	assert_true(distinct.size() > 2, "feature colour varies across the planet")
	profile.grammar = TerrainProfile.Grammar.LEGACY
	assert_eq(look.surface_color(profile, 100.0, 0.0, 0.2, Vector3(6000000.0, 0.0, 0.0)), palette, "LEGACY worlds keep the palette even with the flag on")


func test_negative_feature_channels_are_clamped_before_colouring() -> void:
	var look := PlanetLook.new()
	var negative := look.rodina_feature_to_color(TerrainProfile.Grammar.VELES, Vector4(0.8, -0.4, 0.0, 0.0))
	var zero := look.rodina_feature_to_color(TerrainProfile.Grammar.VELES, Vector4(0.8, 0.0, 0.0, 0.0))
	assert_eq(negative, zero, "a negative plateau counts as none, not as darkening")


func test_terrain_sets_exist_for_every_grammar_and_are_well_formed() -> void:
	var expected_counts := {TerrainProfile.Grammar.PERUN: 5, TerrainProfile.Grammar.JARILO: 6, TerrainProfile.Grammar.VELES: 5, TerrainProfile.Grammar.MORENA: 5, TerrainProfile.Grammar.ASTEROID: 3}
	for grammar in _GRAMMARS:
		var terrains := RodinaTerrainSets.features_for(grammar)
		assert_eq(terrains.size(), expected_counts[grammar], "grammar %d terrain feature count" % grammar)
		for terrain in terrains:
			assert_true(terrain.has("diffuse") and terrain.has("features_edge") and terrain.has("features_used"), "terrain feature has its fields")
	assert_true(RodinaTerrainSets.features_for(TerrainProfile.Grammar.LEGACY).is_empty())


func test_jarilo_ice_caps_sit_on_flat_polar_land_and_not_on_the_equator() -> void:
	var feature := Vector4(0.5, 0.0, 0.5, 0.0) # the ice cap needs the mountains mask (0.13 +- 0.025)
	var pole_direction := Vector3(0.1, 0.98, 0.1).normalized()
	var equator_direction := Vector3(1.0, 0.02, 0.1).normalized()
	var pole := RodinaTerrainBlend.color(TerrainProfile.Grammar.JARILO, feature, 12000.0, pole_direction, 1.0, pole_direction * 6.0e6)
	var equator := RodinaTerrainBlend.color(TerrainProfile.Grammar.JARILO, feature, 12000.0, equator_direction, 1.0, equator_direction * 6.0e6)
	assert_true(pole.get_luminance() > equator.get_luminance() + 0.1, "the pole is much whiter (%f vs %f)" % [pole.get_luminance(), equator.get_luminance()])


func test_morena_cliff_wall_appears_on_steep_ground_only() -> void:
	var direction := Vector3(0.3, 0.2, 0.9).normalized()
	var feature := Vector4(0.5, 0.0, 0.0, 0.0)
	var flat := RodinaTerrainBlend.color(TerrainProfile.Grammar.MORENA, feature, 1000.0, direction, 1.0, direction * 6.0e6)
	var cliff := RodinaTerrainBlend.color(TerrainProfile.Grammar.MORENA, feature, 1000.0, direction, cos(deg_to_rad(60.0)), direction * 6.0e6)
	assert_true(absf(flat.r - cliff.r) + absf(flat.g - cliff.g) + absf(flat.b - cliff.b) > 0.1, "flat and cliff ground are different colours")


func test_terrain_blend_is_finite_and_leaves_legacy_alone() -> void:
	var rng := SeedRng.new(61)
	for grammar in _GRAMMARS:
		for sample in 40:
			var direction := _random_direction(rng)
			var color := RodinaTerrainBlend.color(grammar, RodinaPlanets.features(grammar, direction), 2000.0, direction, 0.5 + 0.5 * rng.next_float(), direction * 6.0e6)
			assert_true(is_finite(color.r) and is_finite(color.g) and is_finite(color.b), "grammar %d finite" % grammar)
	var plain := RodinaTerrainBlend.color(TerrainProfile.Grammar.LEGACY, Vector4(0.5, 0.5, 0.5, 0.5), 0.0, Vector3.UP, 1.0, Vector3.UP * 6.0e6)
	assert_eq(plain, Color(0.5, 0.5, 0.5), "no terrain set means the plain colour")


func test_asteroid_scale_keeps_authored_relief_for_rodina_sized_rocks() -> void:
	assert_eq(RodinaPlanets.asteroid_scale(15000.0), 1.0, "a 15 km rock keeps the full authored relief")
	assert_eq(RodinaPlanets.asteroid_scale(10000.0 * 1000.0), 1.0, "bigger bodies are never scaled up")
	assert_true(RodinaPlanets.asteroid_scale(1000.0) < 0.2, "a 1 km rock is shrunk")
	var highest := -1.0e30
	var lowest := 1.0e30
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 600:
		var p := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var height := RodinaPlanets.height(TerrainProfile.Grammar.ASTEROID, p, 15000.0)
		highest = maxf(highest, height)
		lowest = minf(lowest, height)
	assert_true(highest - lowest > 600.0, "Pebble has real relief (%f m)" % (highest - lowest))


func test_albedo_gain_brightens_rodina_colours_and_defaults_to_rodina_exact() -> void:
	var look := PlanetLook.new()
	look.rodina_terrain_gates = false
	var feature := Vector4(0.5, 0.0, 0.0, 0.0)
	var plain := look.rodina_feature_to_color(TerrainProfile.Grammar.PERUN, feature)
	assert_eq(look.rodina_albedo_gain, 1.0, "the gain defaults to Rodina's colours exactly")
	look.rodina_albedo_gain = 1.8
	var lifted := look.rodina_feature_to_color(TerrainProfile.Grammar.PERUN, feature)
	assert_true(lifted.get_luminance() > plain.get_luminance() * 1.5, "gain lifts dark Perun ground")
	look.rodina_albedo_gain = 100.0
	var clipped := look.rodina_feature_to_color(TerrainProfile.Grammar.PERUN, feature)
	assert_true(clipped.r <= 1.0 and clipped.g <= 1.0 and clipped.b <= 1.0, "colours stay in range")


func test_world_gains_lift_cinder_and_pebble_only() -> void:
	assert_true(VisualStyle.RODINA_ALBEDO_GAIN.get(&"cinder", 1.0) > 1.0, "Cinder is lifted")
	assert_true(VisualStyle.RODINA_ALBEDO_GAIN.get(&"pebble", 1.0) > 1.0, "Pebble is lifted")
	assert_true(not VisualStyle.RODINA_ALBEDO_GAIN.has(&"planet"), "Aurelia keeps Rodina's colours")


func test_pebble_is_craggy_not_just_rolling() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var total := 0.0
	for i in 300:
		var p := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var q := (p + Vector3(50.0 / 15000.0, 0.0, 0.0)).normalized()
		total += absf(RodinaPlanets.height(TerrainProfile.Grammar.ASTEROID, p, 15000.0) - RodinaPlanets.height(TerrainProfile.Grammar.ASTEROID, q, 15000.0))
	assert_true(total / 300.0 > 5.0, "Pebble's ground changes sharply over 50 m (mean %f m)" % (total / 300.0))


func test_colour_variation_patches_the_ground_and_is_off_by_default() -> void:
	var look := PlanetLook.new()
	look.prepare()
	var feature := Vector4(0.5, 0.0, 0.0, 0.0)
	var direction := Vector3(0.3, 0.8, 0.5).normalized()
	var flat := look.rodina_terrain_to_color(TerrainProfile.Grammar.PERUN, feature, 100.0, direction, 1.0, direction * 4.2e6)
	var other := look.rodina_terrain_to_color(TerrainProfile.Grammar.PERUN, feature, 100.0, direction, 1.0, direction * 4.2e6 + Vector3(40000.0, 0.0, 0.0))
	assert_eq(look.rodina_color_variation, 0.0, "variation defaults to off")
	look.rodina_color_variation = 0.5
	var patched_a := look.rodina_terrain_to_color(TerrainProfile.Grammar.PERUN, feature, 100.0, direction, 1.0, direction * 4.2e6)
	var patched_b := look.rodina_terrain_to_color(TerrainProfile.Grammar.PERUN, feature, 100.0, direction, 1.0, direction * 4.2e6 + Vector3(40000.0, 0.0, 0.0))
	assert_true(absf(patched_a.get_luminance() - patched_b.get_luminance()) > absf(flat.get_luminance() - other.get_luminance()) + 0.001, "variation makes nearby ground differ")
	assert_true(VisualStyle.RODINA_COLOR_VARIATION.get(&"cinder", 0.0) > 0.0 and VisualStyle.RODINA_COLOR_VARIATION.get(&"pebble", 0.0) > 0.0, "Cinder and Pebble get patchy colour")


func test_cinder_fog_is_thinned_and_others_keep_rodinas_fog() -> void:
	assert_true(VisualStyle.RODINA_FOG_SCALE.get(&"cinder", 1.0) < 1.0, "Cinder's haze is thinned")
	assert_true(not VisualStyle.RODINA_FOG_SCALE.has(&"verdant") and not VisualStyle.RODINA_FOG_SCALE.has(&"planet"), "Aurelia and Verdant keep their fog")


func test_orbit_glow_is_brightened_for_air_worlds_and_shell_only() -> void:
	var system := StarSystem.default_system()
	for id in [&"planet", &"cinder", &"verdant", &"selene"]:
		var look := VisualStyle.look_for(system.bodies[id])
		assert_true(look.rodina_atmosphere.has("shell_glow_gain"), "%s has an orbit glow gain" % id)
		assert_true(float(look.rodina_atmosphere["shell_glow_gain"]) > 1.0)
	var cinder := VisualStyle.look_for(system.bodies[&"cinder"])
	assert_true(cinder.rodina_atmosphere.has("shell_scatter1"), "Cinder's rim has its own bright colour")
	assert_true(system.bodies[&"cinder"].atmosphere_height >= 150000.0, "Cinder's air is Rodina-thick relative to its size")


func test_morena_big_plate_cracks_are_off_so_selene_has_no_black_line() -> void:
	assert_near(RodinaPlanets.MORENA_BIG_CRACK_SCALE, 0.0, 1e-9)
	# along the old trench the ground is no longer cut 11 km down: sample many points, none dips far below the plateau
	var lowest := INF
	for i in 400:
		var angle := float(i) * 0.0157
		var p := Vector3(cos(angle) * 0.6, 0.3, sin(angle) * 0.7).normalized()
		lowest = minf(lowest, RodinaPlanets.morena(p))
	assert_true(lowest > -9000.0, "no 11 km trench in the sampled ring")


func test_terminator_dims_the_light_only_inside_air() -> void:
	var environment := SpaceEnvironment.new()
	var look := VisualStyle.look_for(StarSystem.default_system().bodies[&"planet"])
	environment.apply_look(look)
	environment.set_sun_elevation(-0.4, 0.0)
	var in_space: float = environment._sun.light_energy
	environment.set_sun_elevation(-0.4, 1.0)
	var in_air: float = environment._sun.light_energy
	assert_true(in_space > in_air, "night side dims the light in air but not in open space")
	assert_near(in_space, look.sun_energy, 1e-6)
