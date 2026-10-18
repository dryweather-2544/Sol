extends "res://tests/test_case.gd"
## The cloud shell: sized to the surface plus the cloud altitude, per-world weather, and which worlds have clouds at all.


func test_shell_is_sized_to_planet_plus_cloud_altitude() -> void:
	var body := BodyDef.new()
	body.id = &"planet"
	body.cloud_coverage = 0.5
	var shell := CloudShell.new()
	shell.update_shell(6.0e6, 10000.0, Vector3(1, 2, 3), Vector3(0, 0, -1), body, 0.0)
	assert_near(shell.scale.x, 6.01e6, 1.0, "radius = planet + cloud altitude")
	assert_eq(shell.position, Vector3(1, 2, 3), "centred on the planet")
	var material := shell.material_override as ShaderMaterial
	assert_near(material.get_shader_parameter("coverage"), 0.5, 1.0e-6, "the world's coverage reaches the shader")
	assert_near(material.get_shader_parameter("fade_band"), 2.0 * 10000.0 / 6.01e6, 1.0e-9, "fade band is two cloud altitudes, in shell units")
	shell.free()


func test_layer_radii_bracket_the_cloud_altitude() -> void:
	var radii := CloudShell.layer_radii(6.0e6, 10000.0)
	assert_near(radii.x, 6.0e6 + 10000.0 - 1250.0, 0.01, "bottom is half a thickness below the cloud altitude")
	assert_near(radii.y, 6.0e6 + 10000.0 + 1250.0, 0.01, "top is half a thickness above it (2.5 km thick at 10 km)")


func test_volume_pass_gets_the_layer_geometry_in_shell_units() -> void:
	var body := BodyDef.new()
	body.id = &"planet"
	body.cloud_coverage = 0.5
	var shell := CloudShell.new()
	shell.update_shell(6.0e6, 10000.0, Vector3.ZERO, Vector3(0, 0, -1), body, 0.0)
	var volume := shell.get_node("VolumePass") as MeshInstance3D
	var material := volume.material_override as ShaderMaterial
	var radii := CloudShell.layer_radii(6.0e6, 10000.0) / 6.01e6
	assert_near(material.get_shader_parameter("bottom_radius"), radii.x, 1.0e-9, "bottom radius in shell units")
	assert_near(material.get_shader_parameter("top_radius"), radii.y, 1.0e-9, "top radius in shell units")
	assert_near(material.get_shader_parameter("shell_metres"), 6.01e6, 1.0, "metres per shell unit")
	assert_true(material.get_shader_parameter("cloud_noise") != null, "the shared noise texture is attached")
	assert_true(CloudShell.shared_noise_texture() == (shell.material_override as ShaderMaterial).get_shader_parameter("cloud_noise"), "orbit shell and volume pass share one texture")
	shell.free()


func test_each_world_gets_its_own_stable_weather_seed() -> void:
	assert_eq(CloudShell.seed_for(&"planet"), CloudShell.seed_for(&"planet"), "the same world always gets the same seed")
	assert_true(CloudShell.seed_for(&"planet") != CloudShell.seed_for(&"cinder"), "different worlds differ")
	assert_true(CloudShell.seed_for(&"planet") != CloudShell.seed_for(&"verdant"), "different worlds differ")


func test_which_worlds_have_clouds() -> void:
	var system := StarSystem.default_system()
	assert_true((system.bodies[&"planet"] as BodyDef).cloud_coverage > 0.0, "Aurelia has clouds")
	assert_true((system.bodies[&"cinder"] as BodyDef).cloud_coverage > (system.bodies[&"planet"] as BodyDef).cloud_coverage, "Cinder's deck is thicker")
	assert_true((system.bodies[&"verdant"] as BodyDef).cloud_coverage > 0.0, "Verdant has clouds")
	for airless in [&"selene", &"pebble"]:
		assert_eq((system.bodies[airless] as BodyDef).cloud_coverage, 0.0, "%s is airless and cloudless" % airless)
		assert_eq((system.bodies[airless] as BodyDef).atmosphere_height, 0.0, "%s has no atmosphere" % airless)
