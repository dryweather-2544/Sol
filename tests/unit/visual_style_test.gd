extends "res://tests/test_case.gd"
## The Sol/Rodina presentation switch must be real, reversible and presentation-only.

const VisualStyleScript = preload("res://src/world/visual_style.gd")


func _reset() -> void:
	GameSettings.instance().visual_style = VisualStyleScript.SOL
	VisualStyleScript.set_style(VisualStyleScript.SOL)


func test_style_names_normalize_and_round_trip() -> void:
	_reset()
	assert_eq(VisualStyleScript.normalize("rodina"), VisualStyleScript.RODINA)
	assert_eq(VisualStyleScript.normalize("RODINA"), VisualStyleScript.RODINA)
	assert_eq(VisualStyleScript.normalize("garbage"), VisualStyleScript.SOL)
	VisualStyleScript.set_style("rodina")
	assert_true(VisualStyleScript.is_rodina())
	VisualStyleScript.set_style("sol")
	assert_true(not VisualStyleScript.is_rodina())
	_reset()


func test_style_is_a_player_setting_not_a_save_field() -> void:
	_reset()
	var settings := GameSettings.new()
	settings.path = "user://test_visual_style_settings.cfg"
	settings.visual_style = "rodina"
	assert_eq(settings.save_to_file(), "")
	var loaded := GameSettings.new()
	loaded.path = settings.path
	loaded.load_from_file()
	assert_eq(loaded.visual_style, "rodina", "the profile is persisted as a preference")
	_reset()


func test_sol_profile_keeps_its_original_environment() -> void:
	_reset()
	var environment := SpaceEnvironment.new()
	environment._ready()
	assert_eq(environment._environment.tonemap_mode, Environment.TONE_MAPPER_ACES)
	assert_true(environment._environment.ssao_enabled)
	assert_eq(environment._sky_material.get_shader_parameter("rodina_mode"), 0.0)
	environment.free()
	_reset()


func test_rodina_body_palettes_are_distinct_and_authored() -> void:
	_reset()
	var system := StarSystem.default_system()
	var home: BodyDef = system.bodies[&"planet"]
	var hot: BodyDef = system.bodies[&"cinder"]
	var green: BodyDef = system.bodies[&"verdant"]
	assert_true(home.rodina_sky_horizon != hot.rodina_sky_horizon, "Aurelia and Cinder have different horizons")
	assert_true(home.rodina_sun_color != hot.rodina_sun_color, "their sun discs differ")
	assert_true(green.rodina_sky_zenith != home.rodina_sky_zenith, "Verdant has its own upper sky")
	assert_true(home.rodina_space_color.r < 0.1 and home.rodina_space_color.b > home.rodina_space_color.g, "space is near-black purple")
	_reset()


func test_atmosphere_shell_selects_the_rodina_limb_shader() -> void:
	_reset()
	GameSettings.instance().visual_style = VisualStyleScript.RODINA
	VisualStyleScript.set_style(VisualStyleScript.RODINA)
	var shell := AtmosphereShell.new()
	shell.update_shell(6.0e6, 2.0e5, Vector3.ZERO, Vector3(0, 0, -1), Color(0.3, 0.5, 1.0))
	assert_true((shell.material_override as ShaderMaterial).shader.resource_path.contains("rodina_atmosphere"), "Rodina profile uses its own simple limb shader")
	shell.free()
	_reset()


func test_style_can_switch_both_ways_at_runtime() -> void:
	_reset()
	var environment := SpaceEnvironment.new()
	environment._ready()
	GameSettings.instance().visual_style = VisualStyleScript.RODINA
	VisualStyleScript.set_style(VisualStyleScript.RODINA)
	environment.set_daylight(0.7, Vector3.UP, 1000.0)
	assert_eq(environment._environment.tonemap_mode, Environment.TONE_MAPPER_LINEAR)
	GameSettings.instance().visual_style = VisualStyleScript.SOL
	VisualStyleScript.set_style(VisualStyleScript.SOL)
	environment.set_daylight(0.7, Vector3.UP, 1000.0)
	assert_eq(environment._environment.tonemap_mode, Environment.TONE_MAPPER_ACES)
	assert_true(environment._environment.ssao_enabled)
	environment.free()
	_reset()


func test_atmosphere_shell_can_switch_back_from_rodina() -> void:
	_reset()
	GameSettings.instance().atmosphere_scattering = true
	GameSettings.instance().visual_style = VisualStyleScript.RODINA
	VisualStyleScript.set_style(VisualStyleScript.RODINA)
	var shell := AtmosphereShell.new()
	shell.update_shell(6.0e6, 2.0e5, Vector3.ZERO, Vector3(0, 0, -1), Color(0.3, 0.5, 1.0))
	assert_true((shell.material_override as ShaderMaterial).shader.resource_path.contains("rodina_atmosphere"))
	GameSettings.instance().visual_style = VisualStyleScript.SOL
	VisualStyleScript.set_style(VisualStyleScript.SOL)
	shell.update_shell(6.0e6, 2.0e5, Vector3.ZERO, Vector3(0, 0, -1), Color(0.3, 0.5, 1.0))
	assert_true((shell.material_override as ShaderMaterial).shader.resource_path.contains("atmosphere_scatter"))
	shell.free()
	_reset()


func test_rodina_profile_is_explicit_and_does_not_enter_flight_state() -> void:
	_reset()
	GameSettings.instance().visual_style = VisualStyleScript.RODINA
	VisualStyleScript.set_style(VisualStyleScript.RODINA)
	var environment := SpaceEnvironment.new()
	environment._ready()
	assert_eq(environment._environment.tonemap_mode, Environment.TONE_MAPPER_LINEAR)
	assert_true(not environment._environment.ssao_enabled)
	assert_eq(environment._sky_material.get_shader_parameter("rodina_mode"), 1.0)
	# Switching presentation must not change the flight model.
	var state := ShipState.new()
	var command := PilotCommand.new()
	command.thrust = Vector3(0, 0, -1)
	FlightModel.step(state, command, ShipTuning.new(), FlightEnvironment.new(), 1.0 / 60.0)
	assert_true(state.speed() > 0.0, "the ship still flies")
	environment.free()
	_reset()


func test_rodina_terrain_uses_its_own_palette_and_plain_material() -> void:
	_reset()
	var profile := TerrainProfile.new()
	var sol_color := ChunkMesher._color_for(profile, 0.0, 0.0, 0.0)
	GameSettings.instance().visual_style = VisualStyleScript.RODINA
	VisualStyleScript.set_style(VisualStyleScript.RODINA)
	var rodina_color := ChunkMesher._color_for(profile, 0.0, 0.0, 0.0)
	assert_true(not sol_color.is_equal_approx(rodina_color), "Rodina uses the separate terrain palette")
	var terrain := PlanetTerrain.new(PlanetBody.new())
	terrain.set_visual_style(true)
	assert_true(terrain._rodina_mode, "terrain records the alternate detail presentation")
	terrain.free()
	_reset()


func test_rodina_palette_values_are_not_a_global_tint() -> void:
	_reset()
	var system := StarSystem.default_system()
	var home: TerrainProfile = (system.bodies[&"planet"] as BodyDef).terrain_profile
	var verdant: TerrainProfile = (system.bodies[&"verdant"] as BodyDef).terrain_profile
	assert_true(home.rodina_palette_mid != verdant.rodina_palette_mid, "worlds have distinct terrain palettes")
	assert_true(home.rodina_palette_mid.r > home.rodina_palette_mid.b, "Aurelia's midland is warm")
	assert_true(verdant.rodina_palette_mid.g > verdant.rodina_palette_mid.r, "Verdant's midland is cool/teal")
	_reset()
