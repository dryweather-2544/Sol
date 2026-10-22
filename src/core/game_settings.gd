class_name GameSettings
extends RefCounted
## Player preferences (not part of saves): stored in user://settings.cfg. One shared instance via
## GameSettings.instance(); tests make their own with a different path.

const DEFAULT_PATH := "user://settings.cfg"

static var _shared: GameSettings

var path := DEFAULT_PATH
## Multiplier on all mouse look (1 = default feel).
var mouse_sensitivity := 1.0
## Pull the mouse back to pitch the nose up.
var invert_pitch := false
const DEFAULT_FIELD_OF_VIEW := 75.0
var field_of_view := DEFAULT_FIELD_OF_VIEW
var master_volume := 0.8
var sfx_volume := 1.0
## The adaptive soundtrack (MusicDirector, Music bus). 0 silences the music; nothing else changes.
var music_volume := 0.7
var ambience_volume := 1.0
## N9 kill switches for the integrated art and audio (assets/sol). Each one off, or its file missing, means the original
## placeholder is used (code materials, the old terrain/sky shaders, SoundSynth). Settings only, never saved in game saves.
var asset_materials := true
var decals := true
var terrain_detail := true
var starfield := true
var sample_audio := true
## The constant background beds (cabin air, suit room tone). Off by default: the ship is silent until the engines, machines or alarms make a sound.
var ambient_beds := false
## "sol" (original) or "rodina" (VisualStyle). The SOL_VISUAL_STYLE environment variable overrides it for a run.
var visual_style := "rodina"
## Strength of the in-atmosphere roll levelling (Rodina's "Ship Horizon Levelling" option, default 1.0; 0 = off).
## Roll only: it never touches pitch. See FlightModel._level_roll.
var ship_horizon_levelling := 1.0
## The warp drive works from the start, without the story's Warp coil (the coil objective then changes nothing).
## Off restores the story gate: open space is crawl-speed and WARP is locked until the coil is installed.
var warp_always_available := true


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
	config.set_value("input", "ship_horizon_levelling", ship_horizon_levelling)
	config.set_value("gameplay", "warp_always_available", warp_always_available)
	config.set_value("video", "field_of_view", field_of_view)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "ambience_volume", ambience_volume)
	config.set_value("assets", "asset_materials", asset_materials)
	config.set_value("assets", "decals", decals)
	config.set_value("assets", "terrain_detail", terrain_detail)
	config.set_value("assets", "starfield", starfield)
	config.set_value("assets", "sample_audio", sample_audio)
	config.set_value("audio", "ambient_beds", ambient_beds)
	config.set_value("video", "visual_style", visual_style)
	var error := config.save(path)
	return "" if error == OK else "could not save settings (error %d)" % error


## Missing file or keys keep the defaults; out-of-range values are clamped.
func load_from_file() -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	mouse_sensitivity = clampf(float(config.get_value("input", "mouse_sensitivity", mouse_sensitivity)), 0.2, 3.0)
	invert_pitch = bool(config.get_value("input", "invert_pitch", invert_pitch))
	ship_horizon_levelling = clampf(float(config.get_value("input", "ship_horizon_levelling", ship_horizon_levelling)), 0.0, 1.0)
	warp_always_available = bool(config.get_value("gameplay", "warp_always_available", warp_always_available))
	field_of_view = clampf(float(config.get_value("video", "field_of_view", field_of_view)), 50.0, 110.0)
	master_volume = clampf(float(config.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
	music_volume = clampf(float(config.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
	ambience_volume = clampf(float(config.get_value("audio", "ambience_volume", ambience_volume)), 0.0, 1.0)
	asset_materials = bool(config.get_value("assets", "asset_materials", asset_materials))
	decals = bool(config.get_value("assets", "decals", decals))
	terrain_detail = bool(config.get_value("assets", "terrain_detail", terrain_detail))
	starfield = bool(config.get_value("assets", "starfield", starfield))
	sample_audio = bool(config.get_value("assets", "sample_audio", sample_audio))
	ambient_beds = bool(config.get_value("audio", "ambient_beds", ambient_beds))
	var style := str(config.get_value("video", "visual_style", visual_style))
	visual_style = style if style in ["sol", "rodina"] else "rodina"
