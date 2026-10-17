class_name AudioService
extends Node
## Plays Sol's synthesised sound: engine rumble from throttle, wind from speed in air, door and
## airlock cues, footsteps, landing thud, discovery chime. Builds its own buses (Master, SFX,
## Ambience, Interior with a low-pass) so volumes come from GameSettings. Reads game state; owns none.

const BUFFER_SECONDS := 0.12

var session: GameSession
var ship: Ship
var _engine_player := AudioStreamPlayer.new()
var _wind_player := AudioStreamPlayer.new()
var _engine_voice := SoundSynth.EngineVoice.new()
var _wind_voice := SoundSynth.WindVoice.new()
var _sfx_players: Array[AudioStreamPlayer] = []
var _cues := {}
var _previous_door_targets := {}
var _previous_landed := false
var _previous_walkway_state := -1
var _footstep_clock := 0.0
var _smoothed_throttle := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_cues = {
		"door": SoundSynth.to_stream(SoundSynth.join(SoundSynth.noise_burst(0.12, 11, 0.6, 0.5, 5.0), SoundSynth.sweep(300.0, 160.0, 0.35, 0.25))),
		"panel": SoundSynth.to_stream(SoundSynth.tone(880.0, 0.08, 0.4)),
		"airlock": SoundSynth.to_stream(SoundSynth.join(SoundSynth.tone(520.0, 0.18, 0.4), SoundSynth.tone(390.0, 0.28, 0.4))),
		"footstep": SoundSynth.to_stream(SoundSynth.noise_burst(0.09, 21, 0.85, 0.7, 7.0)),
		"thud": SoundSynth.to_stream(SoundSynth.noise_burst(0.35, 31, 0.93, 0.9, 5.0)),
		"seat": SoundSynth.to_stream(SoundSynth.join(SoundSynth.tone(300.0, 0.05, 0.5), SoundSynth.tone(200.0, 0.07, 0.5))),
		"chime": SoundSynth.to_stream(SoundSynth.join(SoundSynth.tone(660.0, 0.15, 0.4), SoundSynth.join(SoundSynth.tone(880.0, 0.15, 0.4), SoundSynth.tone(1320.0, 0.35, 0.4)))),
		"ramp": SoundSynth.to_stream(SoundSynth.sweep(120.0, 90.0, 0.8, 0.3)),
	}
	for player_index in 6:
		var sfx := AudioStreamPlayer.new()
		sfx.bus = &"SFX"
		add_child(sfx)
		_sfx_players.append(sfx)
	for generator_player in [_engine_player, _wind_player]:
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = SoundSynth.SAMPLE_RATE
		generator.buffer_length = 0.25
		(generator_player as AudioStreamPlayer).stream = generator
		(generator_player as AudioStreamPlayer).bus = &"Ambience"
		add_child(generator_player)
		(generator_player as AudioStreamPlayer).play()
	if session != null:
		session.discovery_log.poi_discovered.connect(func(_instance): play_cue("chime"))


func _process(delta: float) -> void:
	if session == null:
		return
	_apply_volumes()
	var inside := session.mode == GameSession.Mode.INSIDE or session.mode == GameSession.Mode.SEATED or session.mode == GameSession.Mode.SITTING
	var engine_bus: StringName = &"Interior" if inside else &"Ambience"
	_engine_player.bus = engine_bus
	_wind_player.bus = engine_bus
	var throttle := ship.last_command.thrust.length() * (1.4 if ship.last_command.boost else 1.0)
	if ship.controller.is_parked() or ship.state.landed:
		throttle = 0.0
	_smoothed_throttle = move_toward(_smoothed_throttle, clampf(throttle, 0.0, 1.0), delta * 2.0)
	_feed(_engine_player, func(count): return _engine_voice.fill(count, _smoothed_throttle, 0.8))
	var in_air := ship.state.atmosphere_ratio < 1.0
	var wind_strength := clampf(ship.state.speed() / 250.0, 0.0, 1.0) * (1.0 - smoothstep(0.3, 1.0, ship.state.atmosphere_ratio)) if in_air else 0.0
	if session.mode == GameSession.Mode.OUTSIDE:
		wind_strength = maxf(wind_strength, 0.12 if in_air else 0.0)
	_feed(_wind_player, func(count): return _wind_voice.fill(count, wind_strength, 0.7))
	_play_event_cues(delta)


func play_cue(cue_name: String) -> void:
	for player in _sfx_players:
		if not player.playing:
			player.stream = _cues[cue_name]
			player.pitch_scale = 1.0
			player.play()
			return


func _play_event_cues(delta: float) -> void:
	for portal_id in session.systems.layout.portals:
		var target: bool = (session.systems.layout.portals[portal_id] as Portal).target_open
		if _previous_door_targets.has(portal_id) and _previous_door_targets[portal_id] != target:
			play_cue("door")
		_previous_door_targets[portal_id] = target
	var walkway_state := session.systems.walkway.state
	if _previous_walkway_state != -1 and walkway_state != _previous_walkway_state and (walkway_state == WalkwayController.State.DEPLOYING or walkway_state == WalkwayController.State.RETRACTING):
		play_cue("ramp")
	_previous_walkway_state = walkway_state
	if ship.state.landed and not _previous_landed:
		play_cue("thud")
	_previous_landed = ship.state.landed
	var walking_speed := 0.0
	var grounded := true
	if session.mode == GameSession.Mode.OUTSIDE:
		walking_speed = session.exterior_body.velocity.length()
		grounded = session.exterior_body.grounded
	elif session.mode == GameSession.Mode.INSIDE:
		walking_speed = session.interior_body.velocity.length()
	if walking_speed > 0.5 and grounded:
		_footstep_clock -= delta
		if _footstep_clock <= 0.0:
			play_cue("footstep")
			_footstep_clock = clampf(1.5 / walking_speed, 0.25, 0.6)
	else:
		_footstep_clock = 0.0


func _feed(player: AudioStreamPlayer, producer: Callable) -> void:
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var count := playback.get_frames_available()
	if count <= 0:
		return
	var samples: PackedFloat32Array = producer.call(count)
	var frames := PackedVector2Array()
	frames.resize(count)
	for index in count:
		frames[index] = Vector2(samples[index], samples[index])
	playback.push_buffer(frames)


func _apply_volumes() -> void:
	var settings := GameSettings.instance()
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(settings.master_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(settings.sfx_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"), linear_to_db(maxf(settings.ambience_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Interior"), linear_to_db(maxf(settings.ambience_volume, 0.0001)))


func _ensure_buses() -> void:
	for bus_name in ["SFX", "Ambience", "Interior"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")
			if bus_name == "Interior":
				var low_pass := AudioEffectLowPassFilter.new()
				low_pass.cutoff_hz = 700.0
				AudioServer.add_bus_effect(index, low_pass)
