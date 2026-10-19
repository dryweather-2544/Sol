class_name GameSettings
extends RefCounted
## Player preferences (not part of saves): stored in user://settings.cfg. One shared instance via
## GameSettings.instance(); tests make their own with a different path.

const DEFAULT_PATH := "user://settings.cfg"
## N9 wrote art kill switches into settings. A file without this version may contain the all-off
## tooling state; migrate it once so a normal player sees the integrated art. Later saves keep
## whatever the player chooses.
const SETTINGS_VERSION := 2

static var _shared: GameSettings

var path := DEFAULT_PATH
## Multiplier on all mouse look (1 = default feel).
var mouse_sensitivity := 1.0
## Pull the mouse back to pitch the nose up.
var invert_pitch := false
var field_of_view := 75.0
var master_volume := 0.8
var sfx_volume := 1.0
var ambience_volume := 1.0
## N9 kill switches for the integrated art and audio (assets/sol). Each one off, or its file missing, means the original
## placeholder is used (code materials, the old terrain/sky shaders, SoundSynth). Settings only, never saved in game saves.
var asset_materials := true
var decals := true
var terrain_detail := true
var starfield := true
var sample_audio := true


static func instance() -> GameSettings:
	if _shared == null:
		_shared = GameSettings.new()
		_shared.load_from_file()
	return _shared


func pitch_sign() -> float:
	return -1.0 if invert_pitch else 1.0


## Returns "" on success or an error message.
func save_to_file() -> String:
	var config := ConfigFile.new()
	config.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("input", "invert_pitch", invert_pitch)
	config.set_value("video", "field_of_view", field_of_view)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "ambience_volume", ambience_volume)
	config.set_value("assets", "asset_materials", asset_materials)
	config.set_value("assets", "decals", decals)
	config.set_value("assets", "terrain_detail", terrain_detail)
	config.set_value("assets", "starfield", starfield)
	config.set_value("assets", "sample_audio", sample_audio)
	config.set_value("meta", "version", SETTINGS_VERSION)
	var error := config.save(path)
	return "" if error == OK else "could not save settings (error %d)" % error


## Missing file or keys keep the defaults; out-of-range values are clamped.
func load_from_file() -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	var version := int(config.get_value("meta", "version", 0))
	mouse_sensitivity = clampf(float(config.get_value("input", "mouse_sensitivity", mouse_sensitivity)), 0.2, 3.0)
	invert_pitch = bool(config.get_value("input", "invert_pitch", invert_pitch))
	field_of_view = clampf(float(config.get_value("video", "field_of_view", field_of_view)), 50.0, 110.0)
	master_volume = clampf(float(config.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
	ambience_volume = clampf(float(config.get_value("audio", "ambience_volume", ambience_volume)), 0.0, 1.0)
	asset_materials = bool(config.get_value("assets", "asset_materials", asset_materials))
	decals = bool(config.get_value("assets", "decals", decals))
	terrain_detail = bool(config.get_value("assets", "terrain_detail", terrain_detail))
	starfield = bool(config.get_value("assets", "starfield", starfield))
	sample_audio = bool(config.get_value("assets", "sample_audio", sample_audio))
	if version < SETTINGS_VERSION:
		# One-time migration from the N9 tooling file. Apply it after reading the old keys so the
		# explicit all-off state cannot override the repaired values. A file missing these keys
		# already keeps the true defaults; this branch repairs an old explicit off.
		asset_materials = true
		decals = true
		terrain_detail = true
		starfield = true
		sample_audio = true
