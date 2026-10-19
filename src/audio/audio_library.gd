class_name AudioLibrary
extends RefCounted
## The recorded sounds from res://assets/sol/audio/ (copied from Sol-Assets by tools/import_assets.py), one row per sound id.
## Variant files (<id>_01.wav, _02 ...) become one AudioStreamRandomizer; ids ending in _loop are looped. Everything may fail:
## GameSettings.sample_audio off, a missing file or an unimported WAV gives null and the caller keeps the SoundSynth sound.
## Levels: the files are levelled by class (loops about -30 LUFS, one-shots peak -6 dBFS), so each use sets its own volume_db here.
## These dB offsets are first guesses, NOT tuned by ear (nobody has listened in the game yet).

const ROOT := "res://assets/sol/audio/"
const MAX_VARIANTS := 8
const LOOP_DEFAULT_DB := 6.0

## id -> {"folder": subfolder of ROOT, "bus": bus name, "db": volume offset in dB}
const SOUNDS := {
	"amb_ship_engine_idle_loop": {"folder": "amb", "bus": &"Interior", "db": 6.0},
	"amb_ship_engine_thrust_loop": {"folder": "amb", "bus": &"Interior", "db": 6.0},
	"amb_ship_structure_rumble_loop": {"folder": "amb", "bus": &"Interior", "db": 6.0},
	"amb_int_air_loop": {"folder": "amb", "bus": &"Ship", "db": 3.0},
	"amb_int_reactor_loop": {"folder": "amb", "bus": &"Ship", "db": 0.0},
	"amb_int_fire_loop": {"folder": "amb", "bus": &"Ship", "db": 3.0},
	"amb_suit_room_tone_loop": {"folder": "amb", "bus": &"Suit", "db": 3.0},
	"amb_suit_breath_calm_loop": {"folder": "amb", "bus": &"Suit", "db": 3.0},
	"sfx_ship_engine_startup": {"folder": "sfx/ship", "bus": &"Interior", "db": 0.0},
	"sfx_ship_engine_shutdown": {"folder": "sfx/ship", "bus": &"Interior", "db": 0.0},
	"sfx_ship_touchdown_soft": {"folder": "sfx/ship", "bus": &"Interior", "db": 0.0},
	"sfx_ship_touchdown_hard": {"folder": "sfx/ship", "bus": &"Interior", "db": 0.0},
	"sfx_int_door_open": {"folder": "sfx/int", "bus": &"Ship", "db": 0.0},
	"sfx_int_door_close": {"folder": "sfx/int", "bus": &"Ship", "db": 0.0},
	"sfx_int_airlock_cycle_pressurise": {"folder": "sfx/int", "bus": &"Ship", "db": 0.0},
	"sfx_int_airlock_cycle_vent": {"folder": "sfx/int", "bus": &"Ship", "db": 0.0},
	"sfx_int_power_down": {"folder": "sfx/int", "bus": &"Ship", "db": 0.0},
	"sfx_int_power_up": {"folder": "sfx/int", "bus": &"Ship", "db": 0.0},
	"sfx_int_alarm_fire": {"folder": "sfx/alarm", "bus": &"Ship", "db": 0.0},
	"sfx_int_alarm_reactor": {"folder": "sfx/alarm", "bus": &"Ship", "db": 0.0},
	"sfx_dmg_hull_hit": {"folder": "sfx/dmg", "bus": &"Interior", "db": 0.0},
	"sfx_dmg_subsystem_fail": {"folder": "sfx/dmg", "bus": &"Ship", "db": 0.0},
	"sfx_sys_restored": {"folder": "sfx/ui", "bus": &"Ship", "db": 0.0},
	"sfx_foot_metal": {"folder": "sfx/foot", "bus": &"SFX", "db": 0.0},
	"sfx_foot_regolith_suit": {"folder": "sfx/foot", "bus": &"Suit", "db": 0.0},
	"sfx_suit_o2_warning_low": {"folder": "sfx/suit", "bus": &"Suit", "db": 0.0},
	"sfx_suit_o2_warning_critical": {"folder": "sfx/suit", "bus": &"Suit", "db": 0.0},
	"sfx_item_pickup": {"folder": "sfx/item", "bus": &"UI", "db": 0.0},
	"sfx_ui_objective": {"folder": "sfx/ui", "bus": &"UI", "db": 0.0},
	"amb_ext_wind_light_loop": {"folder": "amb", "bus": &"Ambience", "db": 6.0},
	"amb_ext_wind_strong_loop": {"folder": "amb", "bus": &"Ambience", "db": 6.0},
	"amb_int_damaged_machine_loop": {"folder": "amb", "bus": &"Ship", "db": 3.0},
	"amb_int_electrical_hum_loop": {"folder": "amb", "bus": &"Ship", "db": 3.0},
	"amb_suit_breath_strained_loop": {"folder": "amb", "bus": &"Suit", "db": 3.0},
	"sfx_int_alarm_hull": {"folder": "sfx/alarm", "bus": &"Ship", "db": 0.0},
	"sfx_foot_rubber": {"folder": "sfx/foot", "bus": &"SFX", "db": 0.0},
	"sfx_foot_soil_air": {"folder": "sfx/foot", "bus": &"SFX", "db": 0.0},
	"sfx_int_airlock_seal": {"folder": "sfx/int", "bus": &"Ship", "db": 0.0},
	"sfx_int_door_deny": {"folder": "sfx/int", "bus": &"Ship", "db": 0.0},
	"sfx_int_ramp_motor_loop": {"folder": "sfx/int", "bus": &"Ship", "db": 3.0},
	"sfx_int_ramp_stop": {"folder": "sfx/int", "bus": &"Ship", "db": 0.0},
	"sfx_int_seat_sit": {"folder": "sfx/int", "bus": &"Ship", "db": 0.0},
	"sfx_int_seat_stand": {"folder": "sfx/int", "bus": &"Ship", "db": 0.0},
	"sfx_repair_loop": {"folder": "sfx/int", "bus": &"Ship", "db": 3.0},
	"sfx_ship_boost_start": {"folder": "sfx/ship", "bus": &"Interior", "db": 0.0},
	"sfx_ship_rcs_pulse": {"folder": "sfx/ship", "bus": &"Interior", "db": 0.0},
	"sfx_ship_gear_shift": {"folder": "sfx/ui", "bus": &"UI", "db": 0.0},
	"sfx_suit_helmet_seal": {"folder": "sfx/suit", "bus": &"Suit", "db": 0.0},
	"sfx_suit_helmet_unseal": {"folder": "sfx/suit", "bus": &"Suit", "db": 0.0},
	"sfx_suit_jetpack_loop": {"folder": "sfx/suit", "bus": &"Suit", "db": 3.0},
	"sfx_wpn_ship_gun_fire": {"folder": "sfx/wpn", "bus": &"Interior", "db": 0.0},
	"sfx_wpn_turret_fire": {"folder": "sfx/wpn", "bus": &"Ship", "db": 0.0},
	"mus_discovery_sting": {"folder": "mus", "bus": &"UI", "db": 0.0},
}

static var _streams := {}
static var _variant_streams := {}
static var _missing := {}


static func has_sound(sound_id: String) -> bool:
	return SOUNDS.has(sound_id)


static func bus_for(sound_id: String) -> StringName:
	return SOUNDS[sound_id]["bus"] if SOUNDS.has(sound_id) else &"SFX"


static func volume_db_for(sound_id: String) -> float:
	return SOUNDS[sound_id]["db"] if SOUNDS.has(sound_id) else 0.0


static func is_loop(sound_id: String) -> bool:
	return sound_id.ends_with("_loop")


## File paths for an id: the numbered variants that exist, or the single un-numbered file.
static func file_paths(sound_id: String) -> Array[String]:
	var found: Array[String] = []
	if not SOUNDS.has(sound_id):
		return found
	var base := "%s%s/%s" % [ROOT, SOUNDS[sound_id]["folder"], sound_id]
	for variant in range(1, MAX_VARIANTS + 1):
		var numbered := "%s_%02d.wav" % [base, variant]
		if ResourceLoader.exists(numbered):
			found.append(numbered)
	if found.is_empty() and ResourceLoader.exists(base + ".wav"):
		found.append(base + ".wav")
	return found


## A playable stream for the id, or null (switch off, no such id, no files, or not imported). Cached; null is remembered and logged once.
static func stream(sound_id: String) -> AudioStream:
	if not GameSettings.instance().sample_audio:
		return null
	if _streams.has(sound_id):
		return _streams[sound_id]
	if _missing.has(sound_id):
		return null
	var paths := file_paths(sound_id)
	var built: AudioStream = null
	if not paths.is_empty():
		var loaded: Array[AudioStream] = []
		for path in paths:
			var wav := ResourceLoader.load(path)
			if wav is AudioStreamWAV:
				loaded.append(_prepared(wav as AudioStreamWAV, is_loop(sound_id)))
		if loaded.size() == 1:
			built = loaded[0]
		elif loaded.size() > 1:
			var randomizer := AudioStreamRandomizer.new()
			randomizer.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
			randomizer.random_pitch = 1.04
			randomizer.random_volume_offset_db = 1.0
			for variant in loaded:
				randomizer.add_stream(-1, variant, 1.0)
			built = randomizer
	if built == null:
		_missing[sound_id] = true
		AssetLibrary.warn_once("audio:" + sound_id, "sound '%s' has no loadable file under %s (using the synthesised sound)" % [sound_id, ROOT])
		return null
	_streams[sound_id] = built
	return built


## One specific numbered file of an id (the gear-shift sounds are one file per gear, not random variants), or null.
static func variant_stream(sound_id: String, variant_number: int) -> AudioStream:
	if not GameSettings.instance().sample_audio or not SOUNDS.has(sound_id):
		return null
	var key := "%s#%d" % [sound_id, variant_number]
	if _variant_streams.has(key):
		return _variant_streams[key]
	var path := "%s%s/%s_%02d.wav" % [ROOT, SOUNDS[sound_id]["folder"], sound_id, variant_number]
	var wav := ResourceLoader.load(path) if ResourceLoader.exists(path) else null
	if not (wav is AudioStreamWAV):
		AssetLibrary.warn_once("audio:" + key, "sound file '%s' not found or not loadable" % path)
		return null
	_variant_streams[key] = wav
	return wav as AudioStreamWAV


## For tests: forget cached streams and missing-file memory.
static func reset_cache() -> void:
	_variant_streams.clear()
	_streams.clear()
	_missing.clear()


## Loops are made at runtime (the WAV files carry no loop chunk): forward loop over the whole sample, on a private copy.
static func _prepared(wav: AudioStreamWAV, looped: bool) -> AudioStreamWAV:
	if not looped:
		return wav
	var copy := wav.duplicate() as AudioStreamWAV
	copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
	copy.loop_begin = 0
	copy.loop_end = frame_count(copy)
	return copy


static func frame_count(wav: AudioStreamWAV) -> int:
	var bytes_per_sample := 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
	return wav.data.size() / (bytes_per_sample * (2 if wav.stereo else 1))


## Engine loops: idle fades into thrust with throttle (equal-power so the sum does not dip); silent when the ship is parked or landed.
## Forget the warnings logged through AssetLibrary (tests and a fresh audio session).
static func reset_warnings() -> void:
	AssetLibrary.reset_warnings()


## Returns Vector2(idle_gain, thrust_gain), each 0..1.
static func engine_mix(throttle: float, engine_running: bool) -> Vector2:
	if not engine_running:
		return Vector2.ZERO
	return crossfade(throttle)


## Equal-power crossfade: amount 0 = all first, 1 = all second. Returns Vector2(first_gain, second_gain).
static func crossfade(amount: float) -> Vector2:
	var angle := clampf(amount, 0.0, 1.0) * PI * 0.5
	return Vector2(cos(angle), sin(angle))


## Loudness of a source `distance` metres from the listener, for sounds placed in the ship (3D players need a listener set-up that nobody
## has run yet, so the position is applied as a plain volume: 1 at the source, falling smoothly to `floor_gain` at `max_distance` and beyond).
static func proximity_gain(distance: float, max_distance: float = 12.0, floor_gain: float = 0.0) -> float:
	var closeness := 1.0 - clampf(distance / max_distance, 0.0, 1.0)
	return lerpf(floor_gain, 1.0, closeness * closeness)


## Linear gain 0..1 to dB, with silence reported as -80 (so a "silent" loop player stays running but inaudible).
static func gain_to_db(gain: float) -> float:
	return -80.0 if gain <= 0.0001 else linear_to_db(gain)


## Hysteresis for threshold sounds: becomes true when `value` falls below `low`, back to false when it rises above `high`.
static func next_latch(was_low: bool, value: float, low: float, high: float) -> bool:
	if was_low:
		return value <= high
	return value < low
