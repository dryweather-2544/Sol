extends "res://tests/test_case.gd"

const PATH := "user://test_settings.cfg"


func _fresh() -> GameSettings:
	DirAccess.remove_absolute(PATH)
	var settings := GameSettings.new()
	settings.path = PATH
	return settings


func test_defaults_when_no_file() -> void:
	var settings := _fresh()
	settings.load_from_file()
	assert_near(settings.mouse_sensitivity, 1.0, 1e-9)
	assert_true(not settings.invert_pitch)
	assert_near(settings.field_of_view, 75.0, 1e-9)


func test_values_survive_save_and_load() -> void:
	var settings := _fresh()
	settings.mouse_sensitivity = 1.7
	settings.invert_pitch = true
	settings.field_of_view = 90.0
	settings.master_volume = 0.3
	assert_eq(settings.save_to_file(), "")
	var loaded := GameSettings.new()
	loaded.path = PATH
	loaded.load_from_file()
	assert_near(loaded.mouse_sensitivity, 1.7, 1e-9)
	assert_true(loaded.invert_pitch)
	assert_near(loaded.field_of_view, 90.0, 1e-9)
	assert_near(loaded.master_volume, 0.3, 1e-9)
	assert_eq(loaded.pitch_sign(), -1.0)


func test_out_of_range_values_are_clamped() -> void:
	var config := ConfigFile.new()
	config.set_value("input", "mouse_sensitivity", 99.0)
	config.set_value("video", "field_of_view", 5.0)
	config.set_value("audio", "master_volume", -2.0)
	config.save(PATH)
	var loaded := GameSettings.new()
	loaded.path = PATH
	loaded.load_from_file()
	assert_near(loaded.mouse_sensitivity, 3.0, 1e-9)
	assert_near(loaded.field_of_view, 50.0, 1e-9)
	assert_near(loaded.master_volume, 0.0, 1e-9)


func test_asset_switches_default_on_and_survive_save_and_load() -> void:
	var settings := _fresh()
	assert_true(settings.asset_materials and settings.decals and settings.terrain_detail and settings.starfield and settings.sample_audio, "all N9 switches default on")
	settings.decals = false
	settings.sample_audio = false
	assert_eq(settings.save_to_file(), "")
	var loaded := GameSettings.new()
	loaded.path = PATH
	loaded.load_from_file()
	assert_true(not loaded.decals and not loaded.sample_audio, "switched-off values survive")
	assert_true(loaded.asset_materials and loaded.terrain_detail and loaded.starfield, "the others stay on")


func test_old_settings_file_without_asset_section_keeps_defaults() -> void:
	DirAccess.remove_absolute(PATH)
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", 0.5)
	config.save(PATH)
	var loaded := GameSettings.new()
	loaded.path = PATH
	loaded.load_from_file()
	assert_near(loaded.master_volume, 0.5, 1e-9)
	assert_true(loaded.asset_materials and loaded.decals and loaded.terrain_detail and loaded.starfield and loaded.sample_audio, "missing keys keep the defaults")

