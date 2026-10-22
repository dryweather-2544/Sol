extends "res://tests/test_case.gd"
## VisualStyle / PlanetLook: the sol style is the original look, the rodina style only changes colours, never geometry.

const SETTINGS_PATH := "user://test_settings_visual_style.cfg"


func _after() -> void:
	VisualStyle.set_active(VisualStyle.SOL)


func test_sol_style_keeps_the_original_rules() -> void:
	VisualStyle.set_active(VisualStyle.SOL)
	var system := StarSystem.default_system()
	for body_id in system.bodies:
		var body: BodyDef = system.bodies[body_id]
		var look := VisualStyle.look_for(body)
		assert_true(look.features.is_empty(), "%s: sol uses the TerrainProfile palette rule" % body_id)
		assert_eq(look.rim_color, body.atmosphere_color, "%s: sol rim colour is the body's" % body_id)
		assert_eq(look.impostor_color, body.color, "%s: sol impostor colour is the body's" % body_id)
		if not body.is_star:
			assert_true(system.build_planet_body(body_id).look == null, "%s: no look on sol planets, so ChunkMesher runs its original code" % body_id)
	assert_eq(VisualStyle.tonemap_mode(), Environment.TONE_MAPPER_FILMIC)
	assert_true(not VisualStyle.glow_enabled())
	assert_eq(VisualStyle.hull_tint(), Color.WHITE)
	_after()


func test_rodina_gives_each_world_its_own_family() -> void:
	VisualStyle.set_active(VisualStyle.RODINA)
	var system := StarSystem.default_system()
	var families := {}
	for body_id in system.bodies:
		var body: BodyDef = system.bodies[body_id]
		if body.is_star:
			continue
		var look := VisualStyle.look_for(body)
		assert_true(not look.features.is_empty(), "%s has terrain features" % body_id)
		assert_true(not families.has(look.family), "%s family %s is not shared" % [body_id, look.family])
		families[look.family] = true
		# Seam-free detail: chunk texture offsets wrap at the period, so every tile size must divide it.
		for tile in [look.detail_flat_tile, look.detail_steep_tile, look.detail_far_tile]:
			assert_near(fposmod(look.detail_tile_period, tile), 0.0, 1e-6, "%s: period %.1f is a multiple of tile %.1f" % [body_id, look.detail_tile_period, tile])
	assert_eq(families.size(), 5)
	assert_eq(VisualStyle.tonemap_mode(), Environment.TONE_MAPPER_LINEAR)
	var params := VisualStyle.space_parameters()
	assert_true(float(params["galaxy_amount"]) > 0.0, "Rodina has a galaxy/dust band")
	assert_true((params["galaxy_normal"] as Vector3).is_normalized(), "galaxy band orientation is normalized")
	VisualStyle.set_active(VisualStyle.SOL)
	assert_near(float(VisualStyle.space_parameters()["galaxy_amount"]), 0.0, 1e-9, "Sol keeps its original star sky")
	_after()


func test_style_changes_colours_but_never_terrain_geometry() -> void:
	var system := StarSystem.default_system()
	VisualStyle.set_active(VisualStyle.SOL)
	var sol_planet := system.build_planet_body(system.home_id)
	VisualStyle.set_active(VisualStyle.RODINA)
	var rodina_planet := system.build_planet_body(system.home_id)
	assert_true(rodina_planet.look != null)
	for sample in 50:
		var direction := Vector3(sin(sample * 1.7), cos(sample * 0.9), sin(sample * 0.41 + 1.0)).normalized()
		assert_eq(rodina_planet.terrain_height_xyz(direction.x, direction.y, direction.z), sol_planet.terrain_height_xyz(direction.x, direction.y, direction.z), "height is identical in both styles")
	var key := ChunkKey.make(2, 9, 140, 77)
	var sol_mesh := ChunkMesher.build(key, sol_planet)
	var rodina_mesh := ChunkMesher.build(key, rodina_planet)
	assert_eq(rodina_mesh["vertices"], sol_mesh["vertices"], "mesh positions are identical in both styles")
	assert_eq(rodina_mesh["indices"], sol_mesh["indices"])
	assert_true(rodina_mesh["colors"] != sol_mesh["colors"], "only the colours differ")
	_after()


func test_rodina_feature_gates_pick_rock_on_cliffs_and_ice_at_the_poles() -> void:
	VisualStyle.set_active(VisualStyle.RODINA)
	var system := StarSystem.default_system()
	var look := VisualStyle._rodina_look_palette(system.bodies[system.home_id]) # uncached: this checks the hand-made palette gates, which Rodina feature colours replace
	var profile: TerrainProfile = system.bodies[system.home_id].terrain_profile
	var flat_equator := look.surface_color(profile, 800.0, 0.0, 0.1, Vector3(1000, 0, 0))
	var cliff := look.surface_color(profile, 800.0, 0.3, 0.1, Vector3(1000, 0, 0))
	var pole := look.surface_color(profile, 800.0, 0.0, 0.97, Vector3(1000, 0, 0))
	assert_true(cliff.get_luminance() < flat_equator.get_luminance(), "cliffs are dark rock")
	assert_true(pole.get_luminance() > flat_equator.get_luminance(), "poles are frosted")
	_after()


func test_rodina_style_colours_grammar_worlds_from_the_feature_texture() -> void:
	VisualStyle.set_active(VisualStyle.RODINA)
	var system := StarSystem.default_system()
	for body_id in VisualStyle.RODINA_FEATURE_COLOR_BODIES:
		if not system.bodies.has(body_id):
			continue
		var body: BodyDef = system.bodies[body_id]
		var look := VisualStyle.look_for(body)
		assert_true(look.rodina_feature_colors, "%s uses Rodina feature colours" % body_id)
		if body.terrain_profile != null and body.terrain_profile.grammar != TerrainProfile.Grammar.LEGACY:
			var color := look.surface_color(body.terrain_profile, 500.0, 0.0, 0.3, Vector3(0.3, 0.5, 0.8) * 6000000.0)
			assert_true(is_finite(color.r) and is_finite(color.g) and is_finite(color.b), "%s colour is finite" % body_id)
	VisualStyle.set_active(VisualStyle.SOL)
	var sol_look := VisualStyle.look_for(system.bodies[system.home_id])
	assert_true(not sol_look.rodina_feature_colors, "the Sol style never uses them")
	_after()


func test_rodina_high_speed_presentation_is_darker_and_wider() -> void:
	VisualStyle.set_active(VisualStyle.RODINA)
	assert_true(VisualStyle.hull_tint().get_luminance() < 0.5, "Rodina hull reads dark")
	assert_true(VisualStyle.chase_camera_offset().z > 40.0, "Rodina chase framing leaves negative space")
	_after()


func test_setting_survives_save_and_load_and_rejects_unknown_values() -> void:
	DirAccess.remove_absolute(SETTINGS_PATH)
	var settings := GameSettings.new()
	settings.path = SETTINGS_PATH
	settings.visual_style = "rodina"
	assert_eq(settings.save_to_file(), "")
	var loaded := GameSettings.new()
	loaded.path = SETTINGS_PATH
	loaded.load_from_file()
	assert_eq(loaded.visual_style, "rodina")
	var config := ConfigFile.new()
	config.set_value("video", "visual_style", "neon")
	config.save(SETTINGS_PATH)
	loaded.load_from_file()
	assert_eq(loaded.visual_style, "rodina", "unknown styles fall back to the default, rodina")
	DirAccess.remove_absolute(SETTINGS_PATH)


func test_set_active_bumps_the_revision_the_scene_watches() -> void:
	var before := VisualStyle.revision
	VisualStyle.set_active(VisualStyle.RODINA)
	assert_true(VisualStyle.revision > before)
	assert_true(VisualStyle.is_rodina())
	_after()
	assert_true(not VisualStyle.is_rodina())


func test_rodina_air_worlds_use_rodina_atmosphere_colours() -> void:
	var before := VisualStyle.active()
	VisualStyle.set_active(VisualStyle.RODINA)
	var system := StarSystem.default_system()
	# Aurelia takes Jarilo's: ScatterColor1 = EGHueSaturateValue(20, .6, 1) = (1, .6, .4), FilterColor2 = (210, .5, 1) = (.5, .75, 1).
	var look := VisualStyle.look_for(system.bodies[&"planet"])
	# Laid over Rodina's space base (.025, 0, .05) at Jarilo's tint strength saturate(AtmosphereDensity .75).
	var zenith := Color(0.025, 0.0, 0.05).srgb_to_linear().lerp(Color(1.0, 0.6, 0.4).srgb_to_linear(), 0.75)
	assert_near(look.sky_zenith.r, zenith.r, 1e-5)
	assert_near(look.sky_zenith.g, zenith.g, 1e-5)
	assert_near(look.sky_zenith.b, zenith.b, 1e-5)
	var sunset := Color(0.5, 0.75, 1.0).srgb_to_linear()
	assert_near(look.sunset_color.g, sunset.g, 1e-5, "Jarilo's blue sunset")
	# Verdant takes Zosia's teal: hue 167 -> green and blue above red.
	var verdant := VisualStyle.look_for(system.bodies[&"verdant"])
	assert_true(verdant.sky_zenith.g > verdant.sky_zenith.r and verdant.sky_zenith.b > verdant.sky_zenith.r)
	# Cinder takes Veles's dark red.
	var cinder := VisualStyle.look_for(system.bodies[&"cinder"])
	assert_true(cinder.sky_zenith.r > cinder.sky_zenith.g * 2.0)
	VisualStyle.set_active(before)
func test_speed_streaks_are_off_in_every_style_and_gear() -> void:
	VisualStyle.set_active(VisualStyle.SOL)
	assert_near(SpeedEffects.intensity_for(5000.0, PilotCommand.GEAR_CRUISE), 0.0, 1e-9, "Sol style has no streak field")
	VisualStyle.set_active(VisualStyle.RODINA)
	assert_near(SpeedEffects.intensity_for(100.0, PilotCommand.GEAR_COMBAT), 0.0, 1e-9, "precision/slow flight has no streaks")
	assert_near(SpeedEffects.intensity_for(500.0, PilotCommand.GEAR_DOCK), 0.0, 1e-9, "dock gear never streaks")
	assert_near(SpeedEffects.intensity_for(5000.0, PilotCommand.GEAR_CRUISE), 0.0, 1e-9, "cruise keeps trails, not the combat streak field")
	assert_near(SpeedEffects.intensity_for(5000.0, PilotCommand.GEAR_WARP), 0.0, 1e-9, "WARP uses its own trail; no invented combat streaks")
	assert_near(SpeedEffects.intensity_for(450.0, PilotCommand.GEAR_COMBAT), 0.0, 1e-9, "no streak field in combat: it was added by mistake")
	assert_near(SpeedEffects.intensity_for(5000.0, PilotCommand.GEAR_COMBAT), 0.0, 1e-9, "nor at high combat speed")
	_after()


func test_entry_tint_is_rodina_only_and_tracks_resistance() -> void:
	VisualStyle.set_active(VisualStyle.RODINA)
	assert_near(EntryEffects.intensity_for(0.0), 0.0, 1e-9)
	assert_true(EntryEffects.intensity_for(ShipDamage.ENTRY_DAMAGE_START * 0.5) > 0.4)
	assert_near(EntryEffects.intensity_for(ShipDamage.ENTRY_DAMAGE_START * 2.0), 1.0, 1e-9)
	VisualStyle.set_active(VisualStyle.SOL)
	assert_near(EntryEffects.intensity_for(ShipDamage.ENTRY_DAMAGE_START), 0.0, 1e-9, "Sol entry has no purple wash")
	_after()
