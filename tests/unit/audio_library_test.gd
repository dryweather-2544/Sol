extends "res://tests/test_case.gd"
## N9 S4: the sound table, loops, variants, switch-off fallback, and the pure helpers behind engine fade, alarms and threshold sounds.
## Needs the WAVs imported (tools/run_tests.sh imports first).


func test_every_table_entry_has_files_that_load() -> void:
	AudioLibrary.reset_cache()
	var settings := GameSettings.instance()
	var original := settings.sample_audio
	settings.sample_audio = true
	for sound_id in AudioLibrary.SOUNDS:
		assert_true(not AudioLibrary.file_paths(sound_id).is_empty(), "%s has at least one file under assets/sol/audio" % sound_id)
		assert_true(AudioLibrary.stream(sound_id) != null, "%s loads as a stream" % sound_id)
	settings.sample_audio = original
	AudioLibrary.reset_cache()


func test_variants_become_one_randomizer() -> void:
	AudioLibrary.reset_cache()
	GameSettings.instance().sample_audio = true
	var door := AudioLibrary.stream("sfx_int_door_open")
	assert_true(door is AudioStreamRandomizer, "three door files -> a randomizer")
	if door is AudioStreamRandomizer:
		assert_eq((door as AudioStreamRandomizer).streams_count, 3, "all three variants are in it")
	assert_true(AudioLibrary.stream("sfx_int_alarm_fire") is AudioStreamWAV, "a single file stays a plain stream")
	AudioLibrary.reset_cache()


func test_loops_loop_over_the_whole_sample() -> void:
	AudioLibrary.reset_cache()
	GameSettings.instance().sample_audio = true
	var idle := AudioLibrary.stream("amb_ship_engine_idle_loop") as AudioStreamWAV
	assert_true(idle != null, "the idle loop loads")
	if idle != null:
		assert_eq(idle.loop_mode, AudioStreamWAV.LOOP_FORWARD, "forward loop")
		assert_eq(idle.loop_begin, 0, "from the start")
		assert_true(idle.loop_end > 44100 * 9, "to the end (10 s file at 44.1 kHz), got %d" % idle.loop_end)
		assert_eq(idle.loop_end, AudioLibrary.frame_count(idle), "exactly the frame count")
	var one_shot := AudioLibrary.stream("sfx_int_alarm_fire") as AudioStreamWAV
	assert_true(one_shot != null and one_shot.loop_mode == AudioStreamWAV.LOOP_DISABLED, "one-shots do not loop")
	AudioLibrary.reset_cache()


func test_switch_off_and_unknown_ids_give_null() -> void:
	AudioLibrary.reset_cache()
	var settings := GameSettings.instance()
	var original := settings.sample_audio
	settings.sample_audio = false
	assert_true(AudioLibrary.stream("sfx_int_door_open") == null, "switch off -> the synth fallback")
	settings.sample_audio = true
	AudioLibrary.reset_warnings()
	assert_true(AudioLibrary.stream("sfx_does_not_exist") == null, "unknown id")
	assert_true(AudioLibrary.stream("sfx_does_not_exist") == null, "and again")
	assert_eq(AssetLibrary.warnings.size(), 1, "logged once")
	AudioLibrary.reset_cache()
	AssetLibrary.reset_warnings()
	settings.sample_audio = original


func test_buses_are_known_names() -> void:
	for sound_id in AudioLibrary.SOUNDS:
		assert_true(AudioLibrary.bus_for(sound_id) in [&"Interior", &"Ship", &"Suit", &"UI", &"SFX", &"Radio", &"Ambience"], "%s has a known bus" % sound_id)


func test_engine_mix_crossfades_and_is_silent_when_stopped() -> void:
	assert_eq(AudioLibrary.engine_mix(0.7, false), Vector2.ZERO, "parked or landed: silent")
	var idle := AudioLibrary.engine_mix(0.0, true)
	assert_near(idle.x, 1.0, 0.001, "zero throttle is all idle")
	assert_near(idle.y, 0.0, 0.001, "and no thrust")
	var full := AudioLibrary.engine_mix(1.0, true)
	assert_near(full.x, 0.0, 0.001, "full throttle has no idle")
	assert_near(full.y, 1.0, 0.001, "all thrust")
	var middle := AudioLibrary.engine_mix(0.5, true)
	assert_near(middle.x * middle.x + middle.y * middle.y, 1.0, 0.001, "equal power through the fade")
	assert_near(AudioLibrary.engine_mix(5.0, true).y, 1.0, 0.001, "throttle above 1 is clamped")


func test_latch_has_hysteresis() -> void:
	assert_true(not AudioLibrary.next_latch(false, 0.5, 0.25, 0.75), "healthy stays not-low")
	assert_true(AudioLibrary.next_latch(false, 0.2, 0.25, 0.75), "below the low mark latches")
	assert_true(AudioLibrary.next_latch(true, 0.5, 0.25, 0.75), "stays low in between (no chatter)")
	assert_true(not AudioLibrary.next_latch(true, 0.8, 0.25, 0.75), "above the high mark releases")


func test_alarm_picks_by_priority() -> void:
	assert_eq(AlarmSchedule.pick(true, true, true), AlarmSchedule.Kind.FIRE, "fire beats everything")
	assert_eq(AlarmSchedule.pick(false, true, true), AlarmSchedule.Kind.REACTOR, "reactor beats hull")
	assert_eq(AlarmSchedule.pick(false, false, true), AlarmSchedule.Kind.HULL, "hull alone")
	assert_eq(AlarmSchedule.pick(false, false, false), AlarmSchedule.Kind.NONE, "nothing")


func test_alarm_repeats_fast_three_times_then_slowly() -> void:
	var schedule := AlarmSchedule.new()
	var play_times: Array[float] = []
	var clock := 0.0
	while clock < 30.0:
		if schedule.step(AlarmSchedule.Kind.FIRE, 0.5):
			play_times.append(clock)
		clock += 0.5
	# step() subtracts before checking, so the first play is on the first step (clock 0.0)
	assert_eq(play_times.slice(0, 5), [0.0, 2.0, 4.0, 12.0, 20.0] as Array[float], "2 s, 2 s, then every 8 s; got %s" % str(play_times))


func test_alarm_restarts_when_the_kind_changes_and_stops_when_cleared() -> void:
	var schedule := AlarmSchedule.new()
	assert_true(schedule.step(AlarmSchedule.Kind.REACTOR, 0.1), "a new alarm sounds at once")
	assert_true(not schedule.step(AlarmSchedule.Kind.REACTOR, 0.1), "then waits")
	assert_true(schedule.step(AlarmSchedule.Kind.FIRE, 0.1), "a higher-priority alarm cuts in at once")
	assert_true(not schedule.step(AlarmSchedule.Kind.NONE, 5.0), "cleared: silent")
	assert_true(schedule.step(AlarmSchedule.Kind.FIRE, 0.1), "and it starts afresh next time")


func test_audio_service_emits_cue_started_and_steals_by_priority() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var service := AudioService.new()
	tree.root.add_child(service)
	# The test runner executes in SceneTree._initialize, before the root window itself has entered
	# the tree; a child can still be attached. Check the attachment, not a notification that has not run.
	assert_eq(service.get_parent(), tree.root, "the service could be added to the tree")
	# _initialize runs before the root window gets its ENTER_TREE notification, so run the
	# service's own setup explicitly; this is the same _ready() the real scene calls.
	service._ready()
	if service.get_parent() != tree.root:
		service.free()
		return
	var started: Array = []
	service.cue_started.connect(func(cue_id: String, bus: StringName): started.append([cue_id, bus]))
	GameSettings.instance().sample_audio = true
	assert_true(service.play_sample("sfx_int_door_open"), "the sample plays")
	assert_eq(started.size(), 1, "one cue_started")
	if started.size() == 1:
		assert_eq(started[0][0], "sfx_int_door_open", "with the sound id")
		assert_eq(started[0][1], &"Ship", "and its bus")
	GameSettings.instance().sample_audio = false
	assert_true(not service.play_sample("sfx_int_door_open"), "switch off -> false, so the caller plays the synth cue")
	GameSettings.instance().sample_audio = true
	service.play_cue("door", "sfx_does_not_exist")
	assert_eq(started.back()[0], "door", "a missing sample falls back to the synth cue")
	for index in AudioService.ONE_SHOT_VOICES + 4:
		service.play_sample("sfx_int_alarm_fire", 0)
	var playing := 0
	for child in service.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).playing and (child as AudioStreamPlayer).bus == &"Ship":
			playing += 1
	assert_true(playing <= AudioService.ONE_SHOT_VOICES, "never more one-shot voices than the cap (got %d)" % playing)
	tree.root.remove_child(service)
	service.free()


func test_crossfade_is_equal_power_and_clamped() -> void:
	assert_eq(AudioLibrary.crossfade(-1.0).x, 1.0, "below 0 is all first")
	assert_near(AudioLibrary.crossfade(2.0).y, 1.0, 0.001, "above 1 is all second")
	var middle := AudioLibrary.crossfade(0.5)
	assert_near(middle.x * middle.x + middle.y * middle.y, 1.0, 0.001, "constant power")


func test_proximity_gain_falls_with_distance() -> void:
	assert_near(AudioLibrary.proximity_gain(0.0), 1.0, 0.001, "at the source")
	assert_near(AudioLibrary.proximity_gain(12.0), 0.0, 0.001, "at the max distance with no floor")
	assert_near(AudioLibrary.proximity_gain(30.0, 12.0, 0.3), 0.3, 0.001, "never below the floor")
	assert_true(AudioLibrary.proximity_gain(3.0) > AudioLibrary.proximity_gain(6.0), "nearer is louder")
	assert_true(AudioLibrary.proximity_gain(6.0) > AudioLibrary.proximity_gain(9.0), "monotonic")


func test_gear_shift_files_are_one_per_gear() -> void:
	AudioLibrary.reset_cache()
	GameSettings.instance().sample_audio = true
	for gear in 3:
		assert_true(AudioLibrary.variant_stream("sfx_ship_gear_shift", gear + 1) is AudioStreamWAV, "gear %d has its own file" % gear)
	assert_true(AudioLibrary.variant_stream("sfx_ship_gear_shift", 9) == null, "no file 9")
	AssetLibrary.reset_warnings()
	AudioLibrary.reset_cache()


func test_weapon_counts_shots_for_the_audio_service() -> void:
	var weapon := Weapon.ship_gun()
	var sim := ProjectileSim.new()
	assert_eq(weapon.shots_fired, 0, "none yet")
	assert_true(weapon.try_fire(sim, WorldPos.new(&"space"), Vector3.FORWARD, Vector3.ZERO, 0, null), "first shot fires")
	assert_eq(weapon.shots_fired, 1, "counted")
	assert_true(not weapon.try_fire(sim, WorldPos.new(&"space"), Vector3.FORWARD, Vector3.ZERO, 0, null), "cooldown blocks the second")
	assert_eq(weapon.shots_fired, 1, "a blocked shot is not counted")


func test_reference_samples_play_through_the_service_and_loop_players_restart() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var service := AudioService.new()
	tree.root.add_child(service)
	service._ready()
	GameSettings.instance().sample_audio = true
	assert_true(service.play_sample("rod_gun_fire"), "the reference gun sample is available")
	assert_true(service._set_loop_gain("rod_engine_dock_loop", 1.0, &"Interior"), "the reference dock engine loop is available")
	var loop_player: AudioStreamPlayer = service._sample_loops.get("rod_engine_dock_loop")
	assert_true(loop_player != null, "the loop has one reusable player")
	if loop_player != null:
		loop_player.stop()
		assert_true(service._set_loop_gain("rod_engine_dock_loop", 1.0, &"Interior"), "restarting an existing loop succeeds")
		assert_eq(service._sample_loops.get("rod_engine_dock_loop"), loop_player, "the existing player is reused")
	assert_true(AudioLibrary.stream("rod_engine_warp_loop") != null, "the actual warp loop loads")
	tree.root.remove_child(service)
	service.free()


func test_reference_engine_loops_follow_the_gear_table() -> void:
	assert_eq(AudioService.engine_loop_for_gear(PilotCommand.GEAR_DOCK), "rod_engine_dock_loop")
	assert_eq(AudioService.engine_loop_for_gear(PilotCommand.GEAR_COMBAT), "rod_engine_combat_loop")
	assert_eq(AudioService.engine_loop_for_gear(PilotCommand.GEAR_CRUISE), "rod_engine_cruise_loop")
	assert_eq(AudioService.engine_loop_for_gear(PilotCommand.GEAR_WARP), "rod_engine_warp_loop")
	for gear in [PilotCommand.GEAR_DOCK, PilotCommand.GEAR_COMBAT, PilotCommand.GEAR_CRUISE, PilotCommand.GEAR_WARP]:
		var stream := AudioLibrary.stream(AudioService.engine_loop_for_gear(gear)) as AudioStreamWAV
		assert_true(stream != null, "gear %d reference loop loads" % gear)
		if stream != null:
			assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "gear %d loop is forward" % gear)
	assert_true(AudioLibrary.stream("rod_atmos_entry_loop") is AudioStreamWAV, "atmosphere entry loop loads")
	assert_true(AudioLibrary.stream("rod_gun_hit") != null, "reference impact loads")
	assert_true(AudioLibrary.stream("rod_menu_highlight") != null, "reference UI highlight loads")


func test_paused_gameplay_audio_is_muted_but_ui_one_shots_remain_available() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var service := AudioService.new()
	tree.root.add_child(service)
	service._ready()
	var loop := AudioStreamPlayer.new()
	service.add_child(loop)
	service._sample_loops["test_loop"] = loop
	loop.volume_db = 0.0
	service._engine_player.volume_db = 0.0
	service._wind_player.volume_db = 0.0
	service._mute_gameplay_loops_for_pause()
	assert_eq(loop.volume_db, -80.0, "gameplay loop muted while paused")
	assert_eq(service._engine_player.volume_db, -80.0, "engine loop muted while paused")
	assert_eq(service._wind_player.volume_db, -80.0, "wind loop muted while paused")
	assert_true(service.play_sample("rod_menu_highlight"), "UI one-shot still allowed while paused")
	tree.root.remove_child(service)
	service.free()
