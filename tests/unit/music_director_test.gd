extends "res://tests/test_case.gd"
## The adaptive soundtrack (MusicDirector + Soundtrack + data/music/soundtrack.json). The director is stepped with
## hand-built snapshots on its own clock (no frames tick in the headless runner), plus one check that the snapshot read
## from a real GameSession sees a real enemy.

const STEP := 0.25


func _director(seed_value: int = 7) -> MusicDirector:
	var director := MusicDirector.new(Soundtrack.load_default())
	director.rng.seed = seed_value
	return director


func _state(overrides: Dictionary = {}) -> Dictionary:
	var state := {
		"menu_title": false, "paused": false, "mode": GameSession.Mode.SEATED, "regime": FlightRegime.SPACE,
		"altitude": INF, "planet_frame": false, "body": &"", "engaged": false, "threat": false,
		"low_hull": false, "oxygen_critical": false,
	}
	state.merge(overrides, true)
	return state


func _run(director: MusicDirector, seconds: float, state: Dictionary) -> void:
	for tick in int(round(seconds / STEP)):
		director.step(STEP, state)


## Runs until a piece is playing (or gives up) and returns its id.
func _run_until_music(director: MusicDirector, state: Dictionary, limit_seconds: float = 900.0) -> String:
	var waited := 0.0
	while director.current_track() == "" and waited < limit_seconds:
		director.step(STEP, state)
		waited += STEP
	return director.current_track()


func test_soundtrack_data_is_valid_and_every_file_plays() -> void:
	var soundtrack := Soundtrack.load_default()
	var errors := soundtrack.validation_errors()
	assert_eq(errors.size(), 0, "soundtrack.json problems: %s" % [errors])
	for context_name in [MusicDirector.MENU, MusicDirector.DEEP_SPACE, MusicDirector.APPROACH, MusicDirector.ATMOSPHERE,
			MusicDirector.ASCENT, MusicDirector.SURFACE, MusicDirector.INTERIOR, MusicDirector.DISCOVERY,
			MusicDirector.DANGER, MusicDirector.COMBAT]:
		assert_true(not soundtrack.context(context_name).is_empty(), "context %s is defined" % context_name)
	for track_id: String in soundtrack.tracks:
		var track: Dictionary = soundtrack.tracks[track_id]
		assert_true(String(track.get("licence", "")) in ["CC0-1.0", "CC-BY-3.0", "CC-BY-4.0"], "%s has an allowed licence" % track_id)
		assert_true(String(track.get("author", "")) != "", "%s names its author" % track_id)
		assert_near(soundtrack.length(track_id), float(track["seconds"]), 1.0, "%s decodes to its measured length" % track_id)
	assert_true(soundtrack.stream("exploration_theme") is AudioStreamOggVorbis and (soundtrack.stream("exploration_theme") as AudioStreamOggVorbis).loop, "seamless-loop files are looped")
	assert_true(soundtrack.stream("one_g") is AudioStreamMP3 and not (soundtrack.stream("one_g") as AudioStreamMP3).loop, "full pieces are not")


func test_contexts_follow_the_real_game_states() -> void:
	var director := _director()
	assert_eq(director.classify(_state({"menu_title": true})), MusicDirector.MENU)
	assert_eq(director.classify(_state()), MusicDirector.DEEP_SPACE, "open space between worlds")
	assert_eq(director.classify(_state({"planet_frame": true, "body": &"verdant"})), MusicDirector.APPROACH, "in a world's frame, still in space")
	assert_eq(director.classify(_state({"regime": FlightRegime.ENTERING, "planet_frame": true})), MusicDirector.ATMOSPHERE, "coming down from space")
	assert_eq(director.classify(_state({"regime": FlightRegime.LANDED, "planet_frame": true})), MusicDirector.SURFACE)
	assert_eq(director.classify(_state({"regime": FlightRegime.NEAR_GROUND, "planet_frame": true})), MusicDirector.SURFACE)
	assert_eq(director.classify(_state({"mode": GameSession.Mode.OUTSIDE, "planet_frame": true})), MusicDirector.SURFACE, "walking on a planet")
	assert_eq(director.classify(_state({"mode": GameSession.Mode.INSIDE})), MusicDirector.INTERIOR, "walking inside the ship")
	assert_eq(director.classify(_state({"mode": GameSession.Mode.SITTING})), MusicDirector.INTERIOR)
	assert_eq(director.classify(_state({"threat": true})), MusicDirector.DANGER, "enemies about, not engaging")
	assert_eq(director.classify(_state({"low_hull": true})), MusicDirector.DANGER)
	director.step(STEP, _state({"engaged": true}))
	assert_eq(director.classify(_state()), MusicDirector.COMBAT, "combat holds after the last engagement")
	assert_eq(director.classify(_state({"menu_title": true})), MusicDirector.MENU, "the title page always wins")


func test_climbing_out_of_the_atmosphere_is_an_ascent_not_an_entry() -> void:
	var director := _director()
	_run(director, 10.0, _state({"regime": FlightRegime.LANDED, "planet_frame": true, "altitude": 0.0}))
	var altitude := 2500.0
	for tick in 40:
		altitude += 150.0 * STEP
		director.step(STEP, _state({"regime": FlightRegime.ATMOSPHERE, "planet_frame": true, "altitude": altitude}))
	assert_eq(director.context, MusicDirector.ASCENT, "taking off and climbing is the ascent context")
	_run(director, 10.0, _state({"planet_frame": true}))
	assert_eq(director.context, MusicDirector.APPROACH)
	altitude = 90000.0
	for tick in 60:
		altitude -= 300.0 * STEP
		director.step(STEP, _state({"regime": FlightRegime.ENTERING, "planet_frame": true, "altitude": altitude}))
	assert_eq(director.context, MusicDirector.ATMOSPHERE, "diving in from space is an entry")


func test_menu_theme_then_a_clean_hand_over_to_play() -> void:
	var director := _director()
	var started: Array = []
	director.track_started.connect(func(track_id: String, context_name: String): started.append([track_id, context_name]))
	_run(director, 2.0, _state({"menu_title": true}))
	assert_eq(director.context, MusicDirector.MENU)
	assert_eq(started.size(), 1, "the title theme starts at once")
	if started.size() == 1:
		assert_eq(started[0][0], "orion", "Sol's title theme")
	_run(director, 1.0, _state({"regime": FlightRegime.LANDED, "planet_frame": true}))
	assert_eq(director.context, MusicDirector.SURFACE, "leaving the title is immediate")
	assert_eq(director.current_track(), "", "the theme is fading, not carrying on into play")
	_run(director, 6.0, _state({"regime": FlightRegime.LANDED, "planet_frame": true}))
	assert_eq(director.playing_tracks().size(), 0, "faded out, then quiet before the first gameplay piece")


func test_flight_manoeuvres_and_flicker_never_restart_the_music() -> void:
	var director := _director()
	var starts := [0]
	director.track_started.connect(func(_t, _c): starts[0] += 1)
	var track := _run_until_music(director, _state())
	assert_true(track != "", "deep space eventually plays something")
	var starts_before: int = starts[0]
	# A minute of manoeuvring plus a regime flicker shorter than the dwell time.
	for tick in 240:
		var state := _state()
		if tick % 40 < 8: # 2 s blips into the atmosphere edge
			state = _state({"regime": FlightRegime.ENTERING, "planet_frame": true, "altitude": 150000.0})
		director.step(STEP, state)
		if director.current_track() == "":
			break
	assert_eq(director.context, MusicDirector.DEEP_SPACE, "2 s blips do not change the context")
	assert_eq(starts[0], starts_before, "nothing restarted")


func test_deep_space_music_carries_into_the_approach_and_inside_the_ship() -> void:
	var director := _director(3)
	var track := _run_until_music(director, _state())
	assert_true(track != "")
	_run(director, 8.0, _state({"planet_frame": true, "body": &"verdant"}))
	assert_eq(director.context, MusicDirector.APPROACH)
	assert_eq(director.current_track(), track, "the approach lets the deep-space piece finish")
	_run(director, 8.0, _state({"mode": GameSession.Mode.INSIDE, "planet_frame": true}))
	assert_eq(director.context, MusicDirector.INTERIOR)
	assert_eq(director.current_track(), track, "standing up and walking the ship does not cut it either")


func test_atmospheric_entry_crossfades_without_two_loud_pieces() -> void:
	var director := _director(5)
	var space_track := _run_until_music(director, _state({"planet_frame": true}))
	assert_true(space_track != "")
	var started: Array = []
	director.track_started.connect(func(track_id: String, _c): started.append(track_id))
	var most_voices := 0
	var loud_overlap := 0.0
	var altitude := 120000.0
	for tick in 120:
		altitude -= 200.0 * STEP
		director.step(STEP, _state({"regime": FlightRegime.ATMOSPHERE, "planet_frame": true, "altitude": altitude}))
		var gains := director.voice_gains()
		most_voices = maxi(most_voices, gains.size())
		if gains.size() == 2:
			loud_overlap = maxf(loud_overlap, minf(gains[0], gains[1]))
	assert_eq(director.context, MusicDirector.ATMOSPHERE)
	assert_eq(started.size(), 1, "one entry piece")
	if started.size() == 1:
		assert_true(started[0] in ["tricky_maneuver", "the_galaxy", "maneuvers"], "an entry piece (%s)" % started[0])
		assert_true(started[0] != space_track, "a different piece")
	assert_true(most_voices <= 2, "never more than two music voices (%d)" % most_voices)
	assert_true(loud_overlap < 0.75, "while crossfading, both pieces are never loud together (%.2f)" % loud_overlap)


func test_long_flights_avoid_repetition_and_leave_silence() -> void:
	var director := _director(11)
	var history: Array[String] = []
	director.track_started.connect(func(track_id: String, _c): history.append(track_id))
	var silent_steps := 0
	var steps := 0
	for tick in int(4.0 * 3600.0 / 1.0):
		director.step(1.0, _state())
		steps += 1
		if director.playing_tracks().is_empty():
			silent_steps += 1
	assert_true(history.size() >= 25, "four hours of flight play many pieces (%d)" % history.size())
	var pool_size := Soundtrack.load_default().weighted_pool(MusicDirector.DEEP_SPACE).size()
	var window := mini(6, pool_size - 1)
	for index in history.size():
		for back in range(1, window + 1):
			if index - back >= 0:
				assert_true(history[index] != history[index - back], "%s repeated after only %d pieces" % [history[index], back])
	var distinct := {}
	for track_id in history:
		distinct[track_id] = true
	assert_true(distinct.size() >= pool_size - 1, "the whole pool gets used (%d of %d)" % [distinct.size(), pool_size])
	var silence := float(silent_steps) / steps
	assert_true(silence > 0.15 and silence < 0.7, "quiet is part of it: %.0f%% silence" % (silence * 100.0))


func test_combat_starts_at_once_holds_then_falls_quiet() -> void:
	var director := _director()
	_run_until_music(director, _state())
	director.step(STEP, _state({"engaged": true, "threat": true}))
	assert_eq(director.context, MusicDirector.COMBAT, "combat is immediate")
	director.step(STEP, _state({"engaged": true, "threat": true}))
	var combat_track := director.current_track()
	assert_true(combat_track in ["pitch_black", "nightmare", "crash_landing", "dead"], "a combat piece (%s)" % combat_track)
	_run(director, 30.0, _state({"engaged": true, "threat": true}))
	_run(director, 8.0, _state())
	assert_eq(director.context, MusicDirector.COMBAT, "still combat inside the hold time")
	assert_eq(director.current_track(), combat_track, "and the same piece")
	_run(director, 3.0, _state())
	assert_true(director.context != MusicDirector.COMBAT, "the fight is over")
	_run(director, 7.0, _state())
	assert_eq(director.playing_tracks().size(), 0, "faded into silence after the fight")
	assert_true(director.seconds_until_next_piece() > 4.0, "a breath of silence before normal music")


func test_crash_landing_skips_its_long_intro_in_combat() -> void:
	var soundtrack := Soundtrack.load_default()
	var found := false
	for entry in soundtrack.weighted_pool(MusicDirector.COMBAT):
		if entry["track"] == "crash_landing":
			found = true
			assert_true(float(entry.get("start_s", 0.0)) > 60.0, "starts where the drums come in")
	assert_true(found)


func test_arrival_cue_once_per_new_world() -> void:
	var director := _director()
	_run_until_music(director, _state())
	assert_true(director.note_arrival(&"verdant"), "first time at Verdant")
	var cue_started := false
	for tick in 80:
		director.step(STEP, _state({"planet_frame": true, "body": &"verdant"}))
		cue_started = cue_started or director.playing_tracks().has("space_echo")
		assert_true(director.voice_gains().size() <= 2)
	assert_true(cue_started, "the arrival cue played")
	assert_true(not director.note_arrival(&"verdant"), "landing again or coming back is not a new arrival")
	director.step(STEP, _state({"engaged": true, "threat": true}))
	assert_true(director.note_arrival(&"cinder"))
	_run(director, 10.0, _state({"engaged": true, "threat": true}))
	assert_eq(director.context, MusicDirector.COMBAT)
	assert_true(not director.playing_tracks().has("space_echo"), "a fight cuts the arrival cue and none plays over it")
	assert_true(director.current_track() in ["pitch_black", "nightmare", "crash_landing", "dead"], "the fight's music plays at once (%s)" % director.current_track())


func test_strange_discoveries_get_one_piece_with_a_cooldown() -> void:
	var director := _director()
	_run(director, 10.0, _state({"mode": GameSession.Mode.OUTSIDE, "planet_frame": true}))
	assert_true(not director.note_discovery(PoiDefinition.Type.DEPOSIT), "a mineral deposit is not strange")
	assert_true(director.note_discovery(PoiDefinition.Type.ANOMALY))
	_run(director, 8.0, _state({"mode": GameSession.Mode.OUTSIDE, "planet_frame": true}))
	assert_eq(director.context, MusicDirector.DISCOVERY)
	assert_true(director.current_track() in ["pulse", "sector", "pleading", "abyss"], "a discovery piece (%s)" % director.current_track())
	assert_true(not director.note_discovery(PoiDefinition.Type.WRECK), "cooldown")
	_run(director, 300.0, _state({"mode": GameSession.Mode.OUTSIDE, "planet_frame": true}))
	assert_eq(director.context, MusicDirector.SURFACE, "back to the planet after the piece")


func test_pause_ducks_and_freezes_the_context() -> void:
	var director := _director()
	var track := _run_until_music(director, _state())
	_run(director, 10.0, _state({"paused": true, "engaged": false, "mode": GameSession.Mode.INSIDE}))
	assert_eq(director.context, MusicDirector.DEEP_SPACE, "nothing changes context under the pause menu")
	assert_eq(director.current_track(), track)


func test_loop_files_end_after_their_loops() -> void:
	var soundtrack := Soundtrack.load_default()
	soundtrack.contexts[MusicDirector.SURFACE]["pool"] = [{"track": "safe_space", "weight": 1.0}]
	soundtrack.contexts[MusicDirector.SURFACE]["start_chance"] = 1.0
	var director := MusicDirector.new(soundtrack)
	var state := _state({"mode": GameSession.Mode.OUTSIDE})
	assert_eq(_run_until_music(director, state), "safe_space")
	var length := soundtrack.length("safe_space")
	_run(director, length * 1.5, state)
	assert_eq(director.current_track(), "safe_space", "still looping")
	_run(director, length * 0.6, state)
	assert_eq(director.playing_tracks().size(), 0, "ended after %d loops" % int(soundtrack.rule("max_loops", 2)))


func test_missing_files_and_broken_data_mean_silence_not_errors() -> void:
	var soundtrack := Soundtrack.new()
	soundtrack.load_from_text("{\"tracks\": {\"ghost\": {\"file\": \"not_there.ogg\"}, \"zero_g\": {\"file\": \"mus_zero_g.ogg\"}}, \"contexts\": {\"deep_space\": {\"pool\": [{\"track\": \"ghost\", \"weight\": 100}, {\"track\": \"zero_g\", \"weight\": 1}], \"first_gap_s\": [0, 0], \"gap_s\": [1, 1]}}}")
	assert_true(soundtrack.validation_errors().size() == 1, "the missing file is reported")
	var director := MusicDirector.new(soundtrack)
	assert_eq(_run_until_music(director, _state(), 10.0), "zero_g", "the missing track is skipped")
	var broken := Soundtrack.new()
	broken.load_from_text("not json")
	assert_true(broken.load_error != "")
	var silent := MusicDirector.new(broken)
	_run(silent, 60.0, _state())
	assert_eq(silent.playing_tracks().size(), 0)


func test_snapshot_reads_real_enemies_and_damage() -> void:
	var planet := PlanetBody.new()
	planet.height_override = func(_dx: float, _dy: float, _dz: float) -> float: return 0.0
	var ship := Ship.new()
	ship.planet = planet
	var up := Vector3(0.3, 0.5, 0.8).normalized()
	ship.state.position = WorldPos.new(planet.frame_id, up.x * (planet.radius + 1200.0), up.y * (planet.radius + 1200.0), up.z * (planet.radius + 1200.0))
	var session := GameSession.new(planet, ship, PilotSource.new())
	var director := _director()
	director.session = session
	director.ship = ship
	assert_true(not director.snapshot()["threat"], "no enemies")
	var raider := Ship.new()
	raider.state.position = ship.state.position.offset_by(Vector3(0, 0, 3000.0))
	session.enemy_targets.append(ShipCombatant.new(raider, 1))
	var far := director.snapshot()
	assert_true(far["threat"] and not far["engaged"], "a raider 3 km out is danger, not combat yet")
	ship.state.hull -= 0.1
	assert_true(director.snapshot()["engaged"], "being hit while it is about is a fight")
	raider.state.position = ship.state.position.offset_by(Vector3(0, 0, 600.0))
	assert_true(director.snapshot()["engaged"], "a raider inside its alert range engages")
	raider.state.hull = 0.0
	assert_true(not director.snapshot()["threat"], "a dead raider is no threat")
	raider.free()
	ship.free()


func test_music_volume_setting_round_trips() -> void:
	var path := "user://test_music_settings.cfg"
	DirAccess.remove_absolute(path)
	var settings := GameSettings.new()
	settings.path = path
	settings.music_volume = 0.35
	assert_eq(settings.save_to_file(), "")
	var loaded := GameSettings.new()
	loaded.path = path
	loaded.load_from_file()
	assert_near(loaded.music_volume, 0.35, 1e-9)
