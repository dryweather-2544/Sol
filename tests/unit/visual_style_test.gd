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
	var look := VisualStyle.look_for(system.bodies[system.home_id])
	var profile: TerrainProfile = system.bodies[system.home_id].terrain_profile
	var flat_equator := look.surface_color(profile, 800.0, 0.0, 0.1, Vector3(1000, 0, 0))
	var cliff := look.surface_color(profile, 800.0, 0.3, 0.1, Vector3(1000, 0, 0))
	var pole := look.surface_color(profile, 800.0, 0.0, 0.97, Vector3(1000, 0, 0))
	assert_true(cliff.get_luminance() < flat_equator.get_luminance(), "cliffs are dark rock")
	assert_true(pole.get_luminance() > flat_equator.get_luminance(), "poles are frosted")
	_after()


func test_rodina_high_speed_presentation_is_darker_and_wider() -> void:
	VisualStyle.set_active(VisualStyle.RODINA)
	assert_true(VisualStyle.hull_tint().get_luminance() < 0.5, "Rodina hull reads dark")
	assert_true(VisualStyle.chase_camera_offset().z > 40.0, "Rodina chase framing leaves negative space")
	assert_true(ShipEffects.trails_should_emit(500.0, PilotCommand.GEAR_CRUISE), "cruise speed emits trails")
	assert_true(ShipEffects.trails_should_emit(500.0, PilotCommand.GEAR_COMBAT), "combat speed emits trails")
	assert_true(not ShipEffects.trails_should_emit(100.0, PilotCommand.GEAR_DOCK), "low-speed precision has no trail")
	assert_true(not ShipEffects.trails_should_emit(500.0, PilotCommand.GEAR_DOCK), "precision never emits a speed trail")
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
	assert_eq(loaded.visual_style, "sol", "unknown styles fall back to sol")
	DirAccess.remove_absolute(SETTINGS_PATH)


func test_set_active_bumps_the_revision_the_scene_watches() -> void:
	var before := VisualStyle.revision
	VisualStyle.set_active(VisualStyle.RODINA)
	assert_true(VisualStyle.revision > before)
	assert_true(VisualStyle.is_rodina())
	_after()
	assert_true(not VisualStyle.is_rodina())
