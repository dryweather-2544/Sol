extends SceneTree
## N9 audio check (needs a display AND a real audio device; the headless dummy driver cannot prove sound reaches a bus):
##   godot --path . -s res://tools/audio_check.gd              recorded sounds: every id in AudioLibrary.SOUNDS
##   SOL_ASSETS=off godot --path . -s res://tools/audio_check.gd   fallback: every synthesised cue
## Boots main.tscn, freezes AudioService's own per-frame logic so only the test sound plays, then for each sound: starts it, waits
## 0.6 s, and reports whether a player is playing it, on which bus, and the loudest bus peak seen. A sound passes with a player
## playing it on the expected bus and a peak above -60 dB. Prints one "AUDIO" line per sound and "AUDIO RESULT: PASSED|FAILED".

const SETTLE_MILLISECONDS := 600
const MINIMUM_PEAK_DB := -60.0

var _main: Node
var _audio: AudioService
var _frames := 0
var _sound_ids: Array = []
var _index := -1
var _started_at_ms := 0
var _loudest_peak_db := -200.0
var _was_playing := false
var _bus_name: StringName = &"SFX"
var _fallback_mode := false
var _failures := 0
var _total := 0


func _initialize() -> void:
	_fallback_mode = OS.get_environment("SOL_ASSETS") == "off"
	if _fallback_mode:
		var settings := GameSettings.instance()
		settings.sample_audio = false
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_main.menu.dismiss()
	if _frames == 20:
		_audio = _main.audio
		_audio.set_process(false) # nothing else may change the buses while we measure
		for loop_player in _audio._sample_loops.values():
			(loop_player as AudioStreamPlayer).volume_db = -80.0
		_sound_ids = _audio._cues.keys() if _fallback_mode else AudioLibrary.SOUNDS.keys()
		print("AUDIO mode: %s, %d sounds, output device: %s, driver: %s" % ["synth fallback" if _fallback_mode else "recorded samples", _sound_ids.size(), AudioServer.output_device, AudioServer.get_driver_name() if AudioServer.has_method("get_driver_name") else "unknown"])
		_start_next()
		return false
	if _frames < 20 or _index < 0:
		return false
	_loudest_peak_db = maxf(_loudest_peak_db, maxf(AudioServer.get_bus_peak_volume_left_db(AudioServer.get_bus_index(_bus_name), 0), AudioServer.get_bus_peak_volume_right_db(AudioServer.get_bus_index(_bus_name), 0)))
	_was_playing = _was_playing or _someone_is_playing_on(_bus_name)
	if Time.get_ticks_msec() - _started_at_ms >= SETTLE_MILLISECONDS:
		_finish_current()
		if not _start_next():
			print("AUDIO RESULT: %s (%d of %d sounds passed)" % ["PASSED" if _failures == 0 else "FAILED", _total - _failures, _total])
			quit(1 if _failures > 0 else 0)
	return false


func _someone_is_playing_on(bus_name: StringName) -> bool:
	for child in _audio.get_children():
		if child == _audio._engine_player or child == _audio._wind_player:
			continue # the old generator voices always "play"; they must not count as the sound under test
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).playing and (child as AudioStreamPlayer).bus == bus_name and (child as AudioStreamPlayer).volume_db > -79.0:
			return true
	return false


func _start_next() -> bool:
	_stop_everything()
	_index += 1
	if _index >= _sound_ids.size():
		return false
	var sound_id: String = _sound_ids[_index]
	_loudest_peak_db = -200.0
	_was_playing = false
	if _fallback_mode:
		_bus_name = &"SFX"
		_audio.play_cue(sound_id)
	else:
		_bus_name = AudioLibrary.bus_for(sound_id)
		if AudioLibrary.is_loop(sound_id):
			_audio._set_loop_gain(sound_id, 1.0, _bus_name)
		elif sound_id == "sfx_ship_gear_shift":
			_audio._play_gear_shift(PilotCommand.GEAR_COMBAT)
		else:
			_audio.play_sample(sound_id)
	_started_at_ms = Time.get_ticks_msec()
	return true


func _finish_current() -> void:
	var sound_id: String = _sound_ids[_index]
	var passed := _was_playing and _loudest_peak_db > MINIMUM_PEAK_DB
	_total += 1
	if not passed:
		_failures += 1
	print("AUDIO %s %s bus=%s playing=%s peak_db=%.1f" % ["PASS" if passed else "FAIL", sound_id, _bus_name, str(_was_playing), _loudest_peak_db])


func _stop_everything() -> void:
	if _audio == null:
		return
	for child in _audio.get_children():
		if child is AudioStreamPlayer and child != _audio._engine_player and child != _audio._wind_player:
			(child as AudioStreamPlayer).stop()
	for loop_player in _audio._sample_loops.values():
		(loop_player as AudioStreamPlayer).volume_db = -80.0
