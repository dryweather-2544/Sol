extends SceneTree
## N11 live check for the integrated Rodina reference sounds. Needs a display and a real audio
## device (Godot's dummy audio driver cannot prove sound reaches a bus):
##   godot --path . -s res://tools/n11_audio_check.gd
## Boots the real main scene, stops its automatic audio updates, then starts each sound once and
## measures the playing state plus the loudest peak on its bus. It deliberately tests only sounds
## wired to real gameplay events, not the unused reference catalogue.

const SETTLE_MS := 320
const MIN_PEAK_DB := -60.0
const CASES := [
	{"id": "rod_engine_dock_loop", "loop": true},
	{"id": "rod_engine_combat_loop", "loop": true},
	{"id": "rod_engine_cruise_loop", "loop": true},
	{"id": "rod_engine_warp_loop", "loop": true},
	{"id": "rod_atmos_entry_loop", "loop": true},
	{"id": "rod_wind_light_loop", "loop": true},
	{"id": "rod_wind_strong_loop", "loop": true},
	{"id": "rod_rcs_loop", "loop": true},
	{"id": "rod_rcs_spurt_2", "loop": false},
	{"id": "rod_gear_up", "loop": false},
	{"id": "rod_gear_down", "loop": false},
	{"id": "rod_gear_grind", "loop": false},
	{"id": "rod_gun_fire", "loop": false},
	{"id": "rod_gun_hit", "loop": false},
	{"id": "rod_impact_rock", "loop": false},
	{"id": "rod_door_open", "loop": false},
	{"id": "rod_airlock_open", "loop": false},
	{"id": "rod_item_pickup", "loop": false},
	{"id": "rod_menu_highlight", "loop": false},
	{"id": "rod_gui_click", "loop": false},
	{"id": "rod_alarm_once", "loop": false},
]

var _main: Node
var _audio: AudioService
var _frames := 0
var _index := -1
var _started_ms := 0
var _peak_db := -200.0
var _failures := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_main.menu.dismiss()
	if _frames == 30:
		_audio = _main.audio
		_audio.set_process(false)
		GameSettings.instance().sample_audio = true
		print("N11 AUDIO output=%s driver=%s" % [AudioServer.output_device, AudioServer.get_driver_name() if AudioServer.has_method("get_driver_name") else "unknown"])
		_next()
		return false
	if _index < 0:
		return false
	var bus_index := AudioServer.get_bus_index(AudioLibrary.bus_for(_current_id()))
	_peak_db = maxf(_peak_db, maxf(AudioServer.get_bus_peak_volume_left_db(bus_index, 0), AudioServer.get_bus_peak_volume_right_db(bus_index, 0)))
	if Time.get_ticks_msec() - _started_ms >= SETTLE_MS:
		_finish()
		if not _next():
			print("N11 AUDIO RESULT: %s (%d of %d events passed)" % ["PASSED" if _failures == 0 else "FAILED", CASES.size() - _failures, CASES.size()])
			quit(1 if _failures > 0 else 0)
	return false


func _current_id() -> String:
	return CASES[_index]["id"]


func _next() -> bool:
	_stop_all()
	_index += 1
	if _index >= CASES.size():
		return false
	var sound_id := _current_id()
	var is_loop: bool = CASES[_index]["loop"]
	if is_loop:
		_audio._set_loop_gain(sound_id, 1.0, AudioLibrary.bus_for(sound_id))
	else:
		_audio.play_sample(sound_id)
	_peak_db = -200.0
	_started_ms = Time.get_ticks_msec()
	return true


func _finish() -> void:
	var sound_id := _current_id()
	var bus := AudioLibrary.bus_for(sound_id)
	var is_loop: bool = CASES[_index]["loop"]
	var playing := false
	if is_loop:
		var loop_player = _audio._sample_loops.get(sound_id)
		playing = loop_player != null and (loop_player as AudioStreamPlayer).playing
	else:
		for child in _audio.get_children():
			if child is AudioStreamPlayer and (child as AudioStreamPlayer).playing and (child as AudioStreamPlayer).bus == bus:
				playing = true
				break
	# Short UI one-shots can finish before the settle window; their peak is the proof that they
	# played. Loops must still be running at the end so a broken loop is caught.
	var passed := _peak_db > MIN_PEAK_DB and (playing or not is_loop)
	if not passed:
		_failures += 1
	print("N11 AUDIO %s %-24s bus=%-9s playing=%s peak_db=%.1f" % ["PASS" if passed else "FAIL", sound_id, str(bus), str(playing), _peak_db])


func _stop_all() -> void:
	if _audio == null:
		return
	for child in _audio.get_children():
		if child is AudioStreamPlayer:
			(child as AudioStreamPlayer).stop()
		elif child is AudioStreamPlayer3D:
			(child as AudioStreamPlayer3D).stop()
	for loop_player in _audio._sample_loops.values():
		(loop_player as AudioStreamPlayer).volume_db = -80.0
