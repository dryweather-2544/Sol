extends "res://tests/test_case.gd"
## N9 S8: the sky uses the starfield panorama when the switch is on and the texture loads, and the original hash stars otherwise.


func _built_environment() -> SpaceEnvironment:
	var environment := SpaceEnvironment.new()
	environment._ready()
	return environment


func test_starfield_is_used_when_on() -> void:
	var settings := GameSettings.instance()
	var original := settings.starfield
	settings.starfield = true
	var environment := _built_environment()
	assert_eq(environment._sky_material.get_shader_parameter("starfield_amount"), 1.0, "panorama on")
	assert_true(environment._sky_material.get_shader_parameter("starfield") is Texture2D, "with its texture")
	environment.free()
	settings.starfield = original


func test_hash_stars_remain_when_off() -> void:
	var settings := GameSettings.instance()
	var original := settings.starfield
	settings.starfield = false
	var environment := _built_environment()
	assert_eq(environment._sky_material.get_shader_parameter("starfield_amount"), 0.0, "panorama off")
	environment.free()
	settings.starfield = original


func test_shader_keeps_its_original_interface_and_the_hash_fallback() -> void:
	var source := FileAccess.get_file_as_string("res://data/shaders/space_sky.gdshader")
	for expected in ["uniform float daylight", "uniform vec3 sun_direction", "hash13(cell)", "textureLod(starfield"]:
		assert_true(source.contains(expected), "space_sky.gdshader still contains '%s'" % expected)


func test_starfield_texture_has_no_mipmaps() -> void:
	var import_text := FileAccess.get_file_as_string("res://assets/sol/sky/tex_sky_starfield.png.import")
	assert_true(import_text.contains("mipmaps/generate=false"), "imported without mipmaps (the sky shader samples level 0 and the atan seam would show)")
