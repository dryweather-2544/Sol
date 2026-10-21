extends "res://tests/test_case.gd"
## The Rodina skybox generator port (RodinaSkyBake): cube layout, Rodina's helper functions and the star splat. The full bake
## (tools/bake_rodina_skybox.sh) is too slow for the suite.


func test_cube_map_texels_round_trip_on_every_face() -> void:
	var face_size := 64
	for face in 6:
		for texel in [Vector2i(0, 0), Vector2i(63, 63), Vector2i(31, 5), Vector2i(7, 50)]:
			var direction := RodinaSkyBake.texel_direction(face, texel.x, texel.y, face_size)
			var back := RodinaSkyBake.direction_texel(direction, face_size)
			assert_eq(back, Vector3i(face, texel.x, texel.y), "face %d texel %s" % [face, str(texel)])


func test_axis_mapping_and_star_swizzles_invert() -> void:
	var d := Vector3(0.3, 0.5, -0.8).normalized()
	assert_near(RodinaSkyBake.from_rodina(RodinaSkyBake.to_rodina(d)).distance_to(d), 0.0, 1e-9)
	for group in 4:
		assert_near(RodinaSkyBake.unswizzle(group, RodinaSkyBake.swizzle(group, d)).distance_to(d), 0.0, 1e-9, "swizzle group %d" % group)


func test_analogue_gaussian_and_the_zero_width_range_follow_the_hlsl() -> void:
	assert_near(RodinaSkyBake.analogue(0.5, 0.0, 1.0, 10.0, 20.0), 15.0, 1e-9)
	assert_near(RodinaSkyBake.analogue(5.0, 0.0, 1.0, 10.0, 20.0), 20.0, 1e-9, "clamped")
	assert_near(RodinaSkyBake.analogue(0.3, -1.0, -1.0, 0.0, 1.0), 1.0, 1e-9, "[10] = {-1, -1, 0, 1} saturates to 1, as HLSL divides by zero")
	assert_near(RodinaSkyBake.gaussian2(0.0, 1.0, 0.8, 0.0, 0.3), 0.8, 1e-9, "bell height at the centre")
	assert_true(RodinaSkyBake.gaussian2(0.6, 1.0, 1.0, 0.0, 0.3) < RodinaSkyBake.gaussian2(0.3, 1.0, 1.0, 0.0, 0.3))
	var grain := RodinaSkyBake.hlsl_random(Vector3(0.2, 0.4, 0.6))
	assert_true(grain >= 0.0 and grain < 1.0, "random() is a fraction")


func test_a_star_splat_is_a_small_disc_with_the_linear_falloff_at_the_right_place() -> void:
	var baker := RodinaSkyBake.new(1024)
	assert_eq(baker.points.size(), RodinaSkyBake.STAR_COUNT)
	for point in baker.points:
		assert_near(point.length(), 1.0, 1e-5, "star points are unit vectors")
	baker.splat(0, 0, 0) # group 0, no offset: the point itself seen straight on
	var expected := RodinaSkyBake.from_rodina(baker.points[0])
	var lit := 0
	var peak := 0.0
	for face in 6:
		for y in 1024:
			for x in 1024:
				var value := baker.stars[(face * 1024 + y) * 1024 + x]
				if value <= 0.0:
					continue
				lit += 1
				peak = maxf(peak, value)
				var direction := RodinaSkyBake.texel_direction(face, x, y, 1024)
				assert_true(direction.angle_to(expected) < RodinaSkyBake.STAR_MAX_DISTANCE * 1.1, "lit texels sit within the star radius")
	assert_true(lit >= 1 and lit < 80, "a star is a few texels (got %d)" % lit)
	assert_true(peak <= baker.strengths[0] + 1e-6, "never brighter than the point's strength")
