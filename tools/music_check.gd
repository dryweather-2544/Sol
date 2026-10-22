extends SceneTree
## Real-scene check of the adaptive soundtrack: boots main.tscn and drives it through title -> landed at home ->
## pause -> a jump to Selene (a new world: arrival cue) -> the Mayday ambush there (a fight), printing every music context
## change and every piece that starts. Exits 1 if the expected contexts did not happen.
##   godot --headless --fixed-fps 60 --path . -s res://tools/music_check.gd
var _main: Node
var _frames := 0
var _log: Array[String] = []
var _contexts: Array[String] = []
var _tracks: Array[String] = []
var _max_voices := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _music() -> MusicDirector:
	return _main.audio.music if _main != null and _main.audio != null else null


func _process(_delta: float) -> bool:
	_frames += 1
	var music := _music()
	if _frames == 1 and music != null:
		music.context_changed.connect(func(old_context: String, new_context: String):
			_contexts.append(new_context)
			_log.append("%6.1f s  context %s -> %s" % [_frames / 60.0, old_context if old_context != "" else "(start)", new_context]))
		music.track_started.connect(func(track_id: String, context_name: String):
			_tracks.append(track_id)
			_log.append("%6.1f s  start %s (%s)" % [_frames / 60.0, track_id, context_name]))
	if music != null:
		_max_voices = maxi(_max_voices, music.voice_gains().size())
	if _frames == 60 * 8:
		_main.menu._close(_main.menu.resume_requested) # New game
	if _frames == 60 * 20:
		_main.menu.open_pause()
	if _frames == 60 * 24:
		_main.menu._close(_main.menu.resume_requested)
	if _frames == 60 * 30:
		var session: GameSession = _main.session
		var moon: PlanetBody = _main.runtime.planet_for(&"selene")
		var state := session.ship.state
		state.position = WorldPos.new(&"selene", 0.0, 0.0, moon.radius + 3000.0)
		state.velocity = Vector3.ZERO
		state.basis = Basis.looking_at(Vector3.RIGHT, Vector3(0, 0, 1))
		state.landed = false
		_main.runtime.force_frame(&"selene")
		_main.runtime.recentre_ship_after_restore()
	if _frames == 60 * 75: # the Mayday call comes in while at Selene: the ambush starts
		_main.session.progress.current = 3
		_main.session.progress.warp_installed = true
	if _frames == 60 * 120:
		for line in _log:
			print(line)
		var ok := _contexts.size() > 0 and _contexts[0] == MusicDirector.MENU and _tracks.size() > 0 and _tracks[0] == "orion"
		ok = ok and MusicDirector.SURFACE in _contexts and MusicDirector.COMBAT in _contexts and "space_echo" in _tracks
		ok = ok and _max_voices <= 3
		print("most voices at once (two music + cue): %d" % _max_voices)
		print("MUSIC CHECK: %s" % ("PASSED" if ok else "FAILED"))
		quit(0 if ok else 1)
	return false
