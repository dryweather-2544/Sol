extends "res://tests/test_case.gd"
## The scattering atmosphere shell: sized to the real atmosphere (not the old 1.6x rim), world colour -> scattering wavelengths,
## and the switch that brings back the original rim glow.


func test_aurelia_blue_gives_roughly_earth_wavelengths() -> void:
	var wavelengths := AtmosphereShell.wavelengths_for(Color(0.35, 0.6, 1.0))
	assert_near(wavelengths.z, 0.475, 0.01, "the strongest channel scatters like Earth's blue")
	assert_true(wavelengths.x > wavelengths.y and wavelengths.y > wavelengths.z, "red is the longest wavelength, blue the shortest")
	assert_near(wavelengths.x, 0.62, 0.04, "red near Earth's 0.65 um")


func test_orange_world_scatters_red_most() -> void:
	var wavelengths := AtmosphereShell.wavelengths_for(Color(0.95, 0.5, 0.22))
	assert_true(wavelengths.x < wavelengths.y and wavelengths.y < wavelengths.z, "an orange atmosphere scatters red strongest (shortest wavelength)")


func test_black_color_does_not_blow_up() -> void:
	var wavelengths := AtmosphereShell.wavelengths_for(Color(0, 0, 0))
	assert_true(is_finite(wavelengths.x) and is_finite(wavelengths.y) and is_finite(wavelengths.z), "finite wavelengths for a black colour")


func test_scattering_shell_is_sized_to_the_atmosphere_and_rim_keeps_the_old_size() -> void:
	var settings := GameSettings.instance()
	var original := settings.atmosphere_scattering
	settings.atmosphere_scattering = true
	var shell := AtmosphereShell.new()
	shell.update_shell(6.0e6, 2.0e5, Vector3(1, 2, 3), Vector3(0, 0, -1), Color(0.35, 0.6, 1.0))
	assert_near(shell.scale.x, 6.2e6, 1.0, "outer radius = planet + atmosphere height")
	assert_eq(shell.position, Vector3(1, 2, 3), "centred on the planet")
	var ratio: float = (shell.material_override as ShaderMaterial).get_shader_parameter("inner_ratio")
	assert_near(ratio, 6.0e6 / 6.2e6, 1.0e-6, "planet radius as a fraction of the shell")
	shell.free()
	settings.atmosphere_scattering = false
	var rim := AtmosphereShell.new()
	rim.update_shell(6.0e6, 2.0e5, Vector3.ZERO, Vector3(0, 0, -1), Color(0.35, 0.6, 1.0))
	assert_near(rim.scale.x, 6.0e6 + 1.6 * 2.0e5, 1.0, "the rim fallback keeps its original 1.6 heights")
	rim.free()
	settings.atmosphere_scattering = original
