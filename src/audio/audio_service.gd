class_name AudioService
extends Node
## Plays Sol's synthesised sound: engine rumble from throttle, wind from speed in air, door and
## airlock cues, landing thud, discovery chime. Builds its own buses (Master, SFX,
## Ambience, Interior with a low-pass) so volumes come from GameSettings. Reads game state; owns none.

const BUFFER_SECONDS := 0.12
const ONE_SHOT_VOICES := 16
const HARD_TOUCHDOWN_SPEED := 6.0 ## m/s just before landing; at or above this the hard touchdown sound plays
const LOW_OXYGEN_WARNING := 0.25
const CRITICAL_OXYGEN_WARNING := 0.10
const TURRET_SOUND_SECONDS_BETWEEN_SHOTS := 0.2
const HULL_ALARM_BELOW := 0.25
const SUBSYSTEM_FAIL_BELOW := 0.25
const SUBSYSTEM_RESTORED_ABOVE := 0.75
## Reference audio is selected by the gear in effect, as Rodina's EGShipPlayer:SetMovementEffects does
## (EGDataShipPlayer.lua:419-430): DockEngine in gear 1, CruiseEngine in gears 2 and 3, WarpEngine in gear 4. One player
## per loop is created lazily and faded, so changing gear does not create a new player every frame.
const RODINA_ENGINE_LOOPS := {
	PilotCommand.GEAR_DOCK: "rod_engine_dock_loop",
	PilotCommand.GEAR_COMBAT: "rod_engine_cruise_loop",
	PilotCommand.GEAR_CRUISE: "rod_engine_cruise_loop",
	PilotCommand.GEAR_WARP: "rod_engine_warp_loop",
}
## Rodina's LoadSound Volume and UpSpeed/DownSpeed (gain per second) for the engine loops (Gameplay/EGAudio.lua:16-49).
const RODINA_ENGINE_SOUNDS := {
	"rod_engine_dock_loop": {"volume": 1.0, "up": 20.0, "down": 20.0},
	"rod_engine_cruise_loop": {"volume": 0.25, "up": 5.0, "down": 5.0},
	"rod_engine_warp_loop": {"volume": 1.0, "up": 5.0, "down": 1.0},
}
const ENGINE_FADE_PER_SECOND := 4.0
const WORLD_VOICES := 8
const WORLD_MAX_DISTANCE := 120.0

## Tests (and the Mac audio check) listen to this: every sound that actually starts, recorded sample or synthesised fallback.
signal cue_started(cue_id: String, bus: StringName)

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
var _smoothed_throttle := 0.0
var _sample_loops := {}        # sound id -> AudioStreamPlayer (looped, always running; gain moves its volume)
var _one_shot_priorities: Array[int] = []
var _alarm_schedule := AlarmSchedule.new()
var _previous_speed_in_flight := 0.0
var _previous_engine_stopped := true
var _previous_mode := -1
var _previous_power_down := false
var _previous_airlock_trend := 0
var _previous_airlock_pressure := 1.0
var _subsystem_low := {}
var _oxygen_low := false
var _oxygen_critical := false
var _previous_pickup_total := -1
var _previous_boost := false
var _previous_gear := -1
var _previous_shots_fired := 0
var _previous_turret_firing := false
var _turret_clock := 0.0
var _previous_walkway_moving := false
var _previous_outer_open_factor := 0.0
var _engine_layer_gains := {}
var _previous_selected_gear := -1
var _restoring := false
var _world_players: Array[AudioStreamPlayer3D] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_cues = {
		"door": SoundSynth.to_stream(SoundSynth.join(SoundSynth.noise_burst(0.12, 11, 0.6, 0.5, 5.0), SoundSynth.sweep(300.0, 160.0, 0.35, 0.25))),
		"panel": SoundSynth.to_stream(SoundSynth.tone(880.0, 0.08, 0.4)),
		"airlock": SoundSynth.to_stream(SoundSynth.join(SoundSynth.tone(520.0, 0.18, 0.4), SoundSynth.tone(390.0, 0.28, 0.4))),
		"thud": SoundSynth.to_stream(SoundSynth.noise_burst(0.35, 31, 0.93, 0.9, 5.0)),
		"seat": SoundSynth.to_stream(SoundSynth.join(SoundSynth.tone(300.0, 0.05, 0.5), SoundSynth.tone(200.0, 0.07, 0.5))),
		"chime": SoundSynth.to_stream(SoundSynth.join(SoundSynth.tone(660.0, 0.15, 0.4), SoundSynth.join(SoundSynth.tone(880.0, 0.15, 0.4), SoundSynth.tone(1320.0, 0.35, 0.4)))),
		"alarm": SoundSynth.to_stream(SoundSynth.join(SoundSynth.tone(880.0, 0.22, 0.35), SoundSynth.tone(620.0, 0.22, 0.35))),
		"ramp": SoundSynth.to_stream(SoundSynth.sweep(120.0, 90.0, 0.8, 0.3)),
	}
	for player_index in ONE_SHOT_VOICES:
		var sfx := AudioStreamPlayer.new()
		sfx.bus = &"SFX"
		add_child(sfx)
		_sfx_players.append(sfx)
		_one_shot_priorities.append(0)
	for world_index in WORLD_VOICES:
		var world_player := AudioStreamPlayer3D.new()
		world_player.bus = &"SFX"
		world_player.max_distance = WORLD_MAX_DISTANCE
		world_player.unit_size = 8.0
		world_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(world_player)
		_world_players.append(world_player)
	for generator_player in [_engine_player, _wind_player]:
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = SoundSynth.SAMPLE_RATE
		generator.buffer_length = 0.25
		(generator_player as AudioStreamPlayer).stream = generator
		(generator_player as AudioStreamPlayer).bus = &"Ambience"
		add_child(generator_player)
		(generator_player as AudioStreamPlayer).play()
	if session != null:
		session.discovery_log.poi_discovered.connect(func(_instance): play_cue("chime", "mus_discovery_sting"))
		session.progress.objective_completed.connect(func(_index): play_sample("sfx_ui_objective"))
		session.systems.ambush_hit.connect(func(): play_sample("sfx_dmg_hull_hit", 1))
		session.interaction_refused.connect(_on_interaction_refused)
		_previous_shots_fired = ship.weapon.shots_fired
		_previous_gear = ship.state.gear
		_previous_pickup_total = _inventory_total()
		session.inventory.changed.connect(_on_inventory_changed)
		session.projectiles.hit.connect(_on_projectile_hit)
		# Start from the loaded state so a save made in a damaged/depressurised ship does not announce it on the first frame.
		_previous_power_down = session.systems.power.is_shut_down()
		_previous_airlock_pressure = session.systems.airlock_pressure
		for subsystem_id in [ShipSubsystems.Id.ENGINES, ShipSubsystems.Id.WEAPONS, ShipSubsystems.Id.REACTOR, ShipSubsystems.Id.LIFE_SUPPORT]:
			_subsystem_low[subsystem_id] = session.systems.subsystems.value(subsystem_id) < SUBSYSTEM_FAIL_BELOW


func _process(delta: float) -> void:
	if session == null:
		return
	_apply_volumes()
	_play_alarm(delta)
	var inside := session.mode == GameSession.Mode.INSIDE or session.mode == GameSession.Mode.SEATED or session.mode == GameSession.Mode.SITTING
	var engine_bus: StringName = &"Interior" if inside else &"Ambience"
	_engine_player.bus = engine_bus
	_wind_player.bus = engine_bus
	var throttle := ship.last_command.thrust.length() * (1.4 if ship.last_command.boost else 1.0)
	if ship.controller.is_parked() or ship.state.landed:
		throttle = 0.0
	_smoothed_throttle = move_toward(_smoothed_throttle, clampf(throttle, 0.0, 1.0), delta * 2.0)
	var engine_running := not (ship.controller.is_parked() or ship.state.landed)
	var use_samples := _update_engine_loops(engine_bus, engine_running, delta)
	_engine_player.volume_db = -80.0 if use_samples else 0.0
	if not use_samples:
		_feed(_engine_player, func(count): return _engine_voice.fill(count, _smoothed_throttle, 0.8))
	var in_air := ship.state.atmosphere_ratio < 1.0
	var wind_strength := clampf(ship.state.speed() / 250.0, 0.0, 1.0) * (1.0 - smoothstep(0.3, 1.0, ship.state.atmosphere_ratio)) if in_air else 0.0
	if session.mode == GameSession.Mode.OUTSIDE:
		wind_strength = maxf(wind_strength, 0.12 if in_air else 0.0)
	var rumble_in_use := inside and _set_loop_gain("amb_ship_structure_rumble_loop", wind_strength, engine_bus)
	if not inside:
		_set_loop_gain("amb_ship_structure_rumble_loop", 0.0, engine_bus)
	# Outside (and in the atmosphere) the same strength drives the recorded wind: light fades into strong. Never on an airless world.
	var wind_mix := AudioLibrary.crossfade(wind_strength / 0.6)
	var wind_gain := clampf(wind_strength * 3.0, 0.0, 1.0)
	var light_ok := _fade_loop("rod_wind_light_loop", wind_mix.x * wind_gain if not inside else 0.0, &"Ambience", delta)
	var strong_ok := _fade_loop("rod_wind_strong_loop", wind_mix.y * wind_gain if not inside else 0.0, &"Ambience", delta)
	var wind_in_use := rumble_in_use or (not inside and light_ok and strong_ok)
	_wind_player.volume_db = -80.0 if wind_in_use else 0.0
	if not wind_in_use:
		_feed(_wind_player, func(count): return _wind_voice.fill(count, wind_strength, 0.7))
	# Re-entry fire is the authored Rodina atmosphere-entry loop, driven by the flight model's
	# resistance rather than by a timer of its own. It is never heard in vacuum.
	var entry_strength := clampf(ship.state.atmosphere_resistance / 0.35, 0.0, 1.0) if in_air else 0.0
	_fade_loop("rod_atmos_entry_loop", entry_strength, &"Interior" if inside else &"Ambience", delta)
	_update_cabin_and_suit_loops(inside)
	_play_event_cues(delta)
	_play_state_cues()
	_play_ship_control_cues(delta)


## Plays a synthesised cue by name, or the recorded sound `sample_id` when there is one (falling back to the synthesised cue).
func play_cue(cue_name: String, sample_id: String = "") -> void:
	if sample_id != "" and play_sample(sample_id):
		return
	var stream: AudioStream = _cues[cue_name]
	var player := _free_voice(0)
	if player == null:
		return
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = 0.0
	player.pitch_scale = 1.0
	player.play()
	cue_started.emit(cue_name, &"SFX")


## Plays a recorded one-shot. False when sample audio is off or the sound could not be loaded (the caller then uses the synth cue).
## `priority` decides who gets stolen when all voices are busy: a new sound replaces a playing one of lower or equal priority.
func play_sample(sound_id: String, priority: int = 0) -> bool:
	var stream := AudioLibrary.stream(sound_id)
	if stream == null:
		return false
	var player := _free_voice(priority)
	if player == null:
		return true # heard of, but every voice is busy with something more important: dropping it is the intended behaviour
	player.stream = stream
	player.bus = AudioLibrary.bus_for(sound_id)
	player.volume_db = AudioLibrary.volume_db_for(sound_id)
	player.pitch_scale = 1.0
	player.play()
	_one_shot_priorities[_sfx_players.find(player)] = priority
	cue_started.emit(sound_id, player.bus)
	return true


## An idle voice, else the quietest-priority playing one if the new sound outranks or equals it, else null.
func _free_voice(priority: int) -> AudioStreamPlayer:
	for player in _sfx_players:
		if not player.playing:
			return player
	var steal_index := -1
	for index in _sfx_players.size():
		if _one_shot_priorities[index] <= priority and (steal_index == -1 or _one_shot_priorities[index] < _one_shot_priorities[steal_index]):
			steal_index = index
	return _sfx_players[steal_index] if steal_index != -1 else null


## Starts the looped recorded sound once, then only moves its volume. False if it cannot be played (caller keeps the synth voice).
func _set_loop_gain(sound_id: String, gain: float, bus: StringName) -> bool:
	if not _sample_loops.has(sound_id):
		var stream := AudioLibrary.stream(sound_id)
		if stream == null:
			return false
		var loop_player := AudioStreamPlayer.new()
		loop_player.stream = stream
		loop_player.volume_db = -80.0
		add_child(loop_player)
		loop_player.bus = bus
		loop_player.play()
		_sample_loops[sound_id] = loop_player
	elif not GameSettings.instance().sample_audio:
		(_sample_loops[sound_id] as AudioStreamPlayer).volume_db = -80.0
		return false
	var player: AudioStreamPlayer = _sample_loops[sound_id]
	player.bus = bus
	player.volume_db = AudioLibrary.gain_to_db(gain) + AudioLibrary.volume_db_for(sound_id) if gain > 0.0001 else -80.0
	if gain > 0.0001 and not player.playing:
		player.play()
	return true


## Stable mapping used by tests and the service: the actual reference loop for a gear.
static func engine_loop_for_gear(gear: int) -> String:
	return RODINA_ENGINE_LOOPS.get(gear, "rod_engine_combat_loop")


## Rodina's rule: the engine plays at the movement strength (the pilot's thrust input; silent when coasting), the warp
## engine at 1 once the drive is active and LimnalActivation / 3 while it spins up; each at its LoadSound volume.
static func rodina_engine_gain(gear: int, thrust_strength: float, limnal_timer: float) -> float:
	var sound_id := engine_loop_for_gear(gear)
	var volume: float = RODINA_ENGINE_SOUNDS[sound_id]["volume"]
	if gear == PilotCommand.GEAR_WARP:
		var activation := clampf(limnal_timer / LimnalWarpView.LIMNAL_START_TIME, 0.0, 1.0)
		return volume * (1.0 if activation >= 1.0 else activation / 3.0)
	return volume * clampf(thrust_strength, 0.0, 1.0)


func _update_engine_loops(engine_bus: StringName, engine_running: bool, delta: float) -> bool:
	var selected := engine_loop_for_gear(ship.state.gear)
	var engine_factor := 1.0
	if session.systems != null:
		engine_factor = clampf(session.systems.engine_factor(), 0.15, 1.0)
	var selected_gain := rodina_engine_gain(ship.state.gear, ship.last_command.thrust.length(), ship.state.limnal_timer) * engine_factor
	var selected_ok := true
	for sound_id: String in RODINA_ENGINE_SOUNDS:
		var target := selected_gain if engine_running and sound_id == selected else 0.0
		var sound: Dictionary = RODINA_ENGINE_SOUNDS[sound_id]
		if not _fade_loop(sound_id, target, engine_bus, delta, sound["up"], sound["down"]):
			if sound_id == selected:
				selected_ok = false
	return selected_ok


## Moves one loop's gain toward `target` without ever creating a silent player. False means the
## loop's file is unavailable, so the caller can use the synthesised fallback.
func _fade_loop(sound_id: String, target: float, bus: StringName, delta: float, up_per_second: float = ENGINE_FADE_PER_SECOND, down_per_second: float = ENGINE_FADE_PER_SECOND) -> bool:
	var current := float(_engine_layer_gains.get(sound_id, 0.0))
	var next := move_toward(current, target, (up_per_second if target > current else down_per_second) * delta)
	_engine_layer_gains[sound_id] = next
	if next <= 0.0001 and not _sample_loops.has(sound_id):
		return true
	if next > 0.0001 or _sample_loops.has(sound_id):
		if not _set_loop_gain(sound_id, next, bus):
			return false
	return true


## Cabin and suit loops. Ship-placed sounds are scaled by how far the player is from their source (AudioLibrary.proximity_gain).
func _update_cabin_and_suit_loops(inside: bool) -> void:
	var systems := session.systems
	var player_position := session.interior_body.position
	var life_support := systems.power.delivered(ShipPower.Conduit.LIFE_SUPPORT)
	_set_loop_gain("amb_int_air_loop", 1.0 if inside and life_support > 0.05 else 0.0, &"Ship")
	var outside := session.mode == GameSession.Mode.OUTSIDE
	_set_loop_gain("amb_suit_room_tone_loop", 1.0 if outside else 0.0, &"Suit")
	var strained := session.suit.oxygen <= 0.3
	_set_loop_gain("amb_suit_breath_calm_loop", 1.0 if outside and not strained else 0.0, &"Suit")
	_set_loop_gain("amb_suit_breath_strained_loop", 1.0 if outside and strained else 0.0, &"Suit")
	_set_loop_gain("rod_air_blow_loop", 1.0 if outside and session.exterior_body.jetpack_burning else 0.0, &"Suit")
	_set_loop_gain("rod_air_blow_repair_loop", 1.0 if inside and session.repairing else 0.0, &"Ship")
	var reactor_gain := 0.0 if systems.power.is_shut_down() else lerpf(0.5, 1.0, clampf(systems.power.temperature, 0.0, 1.0))
	_set_loop_gain("amb_int_reactor_loop", reactor_gain * _proximity(&"reactor_panel", player_position, 0.3) if inside else 0.0, &"Ship")
	var hum_gain := 0.0 if systems.power.is_shut_down() else maxf(_proximity(&"pilot_seat", player_position, 0.15), maxf(_proximity(&"engine_station", player_position, 0.15), _proximity(&"reactor_panel", player_position, 0.15)))
	_set_loop_gain("amb_int_electrical_hum_loop", hum_gain if inside else 0.0, &"Ship")
	var engine_damage := clampf((0.5 - systems.subsystems.value(ShipSubsystems.Id.ENGINES)) / 0.5, 0.0, 1.0)
	_set_loop_gain("amb_int_damaged_machine_loop", engine_damage * _proximity(&"engine_station", player_position, 0.2) if inside else 0.0, &"Ship")
	var strongest_fire := 0.0
	for room_id in systems.hazards.burning_rooms():
		var room_center: Vector2 = systems.layout.rooms[room_id].get_center()
		var room_distance := Vector2(player_position.x, player_position.z).distance_to(room_center)
		strongest_fire = maxf(strongest_fire, systems.hazards.fire_in(room_id) * AudioLibrary.proximity_gain(room_distance, 12.0, 0.25))
	_set_loop_gain("rod_fire_loop", strongest_fire if inside else 0.0, &"Ship")


## Proximity gain from the player to a named interaction point of the ship layout (1.0 if the layout has no such point).
func _proximity(point_id: StringName, player_position: Vector3, floor_gain: float) -> float:
	for point in session.systems.layout.interact_points:
		if point["id"] == point_id:
			return AudioLibrary.proximity_gain(player_position.distance_to(point["position"]), 12.0, floor_gain)
	return 1.0


## One alarm voice: fire beats reactor beats hull, scheduled by AlarmSchedule.
func _play_alarm(delta: float) -> void:
	var wanted := AlarmSchedule.pick(session.systems.hazards.any_fire(), session.systems.power.is_shut_down(), ship.state.hull < HULL_ALARM_BELOW)
	if not _alarm_schedule.step(wanted, delta):
		return
	# The reference alarm loop is looped audio; play its authored one-shot variant here so the
	# shared one-shot voice cannot keep looping after the alarm schedule moves on.
	play_cue("alarm", "rod_alarm_once")


func _play_event_cues(delta: float) -> void:
	for portal_id in session.systems.layout.portals:
		var target: bool = (session.systems.layout.portals[portal_id] as Portal).target_open
		if _previous_door_targets.has(portal_id) and _previous_door_targets[portal_id] != target:
			var is_airlock := String(portal_id).contains("airlock")
			var door_sound := ("rod_airlock_open" if target else "rod_airlock_close") if is_airlock else ("rod_door_open" if target else "rod_door_close")
			play_cue("door", door_sound)
		_previous_door_targets[portal_id] = target
	var walkway_state := session.systems.walkway.state
	var walkway_moving := walkway_state == WalkwayController.State.DEPLOYING or walkway_state == WalkwayController.State.RETRACTING
	var motor_loop_playing := _set_loop_gain("sfx_int_ramp_motor_loop", 1.0 if walkway_moving else 0.0, &"Ship")
	if _previous_walkway_state != -1 and walkway_state != _previous_walkway_state and walkway_moving and not motor_loop_playing:
		play_cue("ramp")
	if _previous_walkway_moving and not walkway_moving:
		play_sample("sfx_int_ramp_stop")
	_previous_walkway_moving = walkway_moving
	_previous_walkway_state = walkway_state
	if ship.state.landed and not _previous_landed:
		play_cue("thud", "rod_impact_rock" if ship.planet != null else "rod_impact_metal")
	_previous_landed = ship.state.landed
	if not ship.state.landed:
		_previous_speed_in_flight = ship.state.speed()


## Edges of ship and suit state that make a sound: engine start/stop, power loss/return, airlock cycling, subsystem failure and
## recovery, suit oxygen warnings.
func _play_state_cues() -> void:
	var engine_stopped := ship.controller.is_parked() or ship.state.landed
	if engine_stopped and not _previous_engine_stopped:
		play_sample("sfx_ship_engine_shutdown")
	if session.mode == GameSession.Mode.SEATED and _previous_mode != GameSession.Mode.SEATED and _previous_mode != -1 and ship.state.landed:
		play_sample("sfx_ship_engine_startup")
	_previous_engine_stopped = engine_stopped
	var was_in_seat := _previous_mode == GameSession.Mode.SEATED or _previous_mode == GameSession.Mode.SITTING
	var in_seat := session.mode == GameSession.Mode.SEATED or session.mode == GameSession.Mode.SITTING
	if _previous_mode != -1:
		if in_seat and not was_in_seat:
			play_sample("sfx_int_seat_sit")
		elif was_in_seat and not in_seat:
			play_sample("sfx_int_seat_stand")
		if session.mode == GameSession.Mode.OUTSIDE and _previous_mode == GameSession.Mode.INSIDE:
			play_sample("sfx_suit_helmet_seal")
		elif session.mode == GameSession.Mode.INSIDE and _previous_mode == GameSession.Mode.OUTSIDE:
			play_sample("sfx_suit_helmet_unseal")
	_previous_mode = session.mode
	var outer_open_factor := session.systems.airlock.outer.open_factor
	if _previous_outer_open_factor > 0.0 and outer_open_factor <= 0.0:
		play_sample("rod_airlock_close")
	_previous_outer_open_factor = outer_open_factor
	var power_down := session.systems.power.is_shut_down()
	if power_down != _previous_power_down:
		play_sample("rod_gear_grind" if power_down else "rod_gui_click")
	_previous_power_down = power_down
	var pressure := session.systems.airlock_pressure
	var trend := 0
	if pressure > _previous_airlock_pressure + 0.0001:
		trend = 1
	elif pressure < _previous_airlock_pressure - 0.0001:
		trend = -1
	if trend != 0 and trend != _previous_airlock_trend:
		play_sample("sfx_int_airlock_cycle_pressurise" if trend > 0 else "sfx_int_airlock_cycle_vent")
	_previous_airlock_trend = trend
	_previous_airlock_pressure = pressure
	for subsystem_id in [ShipSubsystems.Id.ENGINES, ShipSubsystems.Id.WEAPONS, ShipSubsystems.Id.REACTOR, ShipSubsystems.Id.LIFE_SUPPORT]:
		var was_low: bool = _subsystem_low.get(subsystem_id, false)
		var is_low := AudioLibrary.next_latch(was_low, session.systems.subsystems.value(subsystem_id), SUBSYSTEM_FAIL_BELOW, SUBSYSTEM_RESTORED_ABOVE)
		if is_low != was_low:
			play_sample("sfx_dmg_subsystem_fail" if is_low else "sfx_sys_restored", 1)
		_subsystem_low[subsystem_id] = is_low
	if session.mode == GameSession.Mode.OUTSIDE:
		var low := AudioLibrary.next_latch(_oxygen_low, session.suit.oxygen, LOW_OXYGEN_WARNING, 0.3)
		var critical := AudioLibrary.next_latch(_oxygen_critical, session.suit.oxygen, CRITICAL_OXYGEN_WARNING, 0.3)
		if critical and not _oxygen_critical:
			play_sample("sfx_suit_o2_warning_critical", 2)
		elif low and not _oxygen_low:
			play_sample("sfx_suit_o2_warning_low", 2)
		_oxygen_low = low
		_oxygen_critical = critical
	else:
		_oxygen_low = false
		_oxygen_critical = false


## Ship controls: boost, gear change, the ship gun and the turret.
func _play_ship_control_cues(delta: float) -> void:
	_turret_clock = maxf(0.0, _turret_clock - delta)
	var command := ship.last_command
	if command.boost and not _previous_boost:
		play_sample("sfx_ship_boost_start")
	_previous_boost = command.boost
	# Rodina EGBehaviorPlayer:UpdateShiftGears (127-147): a shift the pilot asks for plays ShiftUp/ShiftDown, a refused
	# one ShiftGrind; a gear the game drops by itself (CancelLimnalDrive, an empty tank) plays nothing.
	var selected := ship.state.selected_gear
	if _previous_selected_gear != -1 and selected != _previous_selected_gear:
		if selected != ship.state.gear:
			play_sample("rod_gear_grind", 1)
		elif selected > _previous_selected_gear:
			play_sample("rod_gear_up")
		else:
			play_sample("rod_gear_down")
	_previous_selected_gear = selected
	_previous_gear = ship.state.gear
	var shots_fired := ship.weapon.shots_fired
	# The ship's guns are Rodina's EGWeaponBlaster, SoundName "Blaster" (EGDataWeapons.lua:16, EGAudio.lua:245).
	if shots_fired > _previous_shots_fired:
		play_sample("rod_ship_blaster_fire")
	_previous_shots_fired = shots_fired
	var turret_firing := session.systems.turret_firing
	if turret_firing and (not _previous_turret_firing or _turret_clock <= 0.0):
		play_sample("rod_ship_blaster_fire")
		_turret_clock = TURRET_SOUND_SECONDS_BETWEEN_SHOTS
	_previous_turret_firing = turret_firing


## Positional one-shot for world events. The service is a plain Node under the main scene, so
## convert the WorldPos into the ship's current render frame before handing it to a 3D player.
func play_world_sample(sound_id: String, world_position: WorldPos) -> bool:
	var stream := AudioLibrary.stream(sound_id)
	if stream == null or ship == null:
		return false
	var player: AudioStreamPlayer3D = null
	for candidate in _world_players:
		if not candidate.playing:
			player = candidate
			break
	if player == null:
		return false
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = AudioLibrary.volume_db_for(sound_id)
	player.position = world_position.to_local_vector3(ship.render_origin)
	player.play()
	cue_started.emit(sound_id, player.bus)
	return true


func _on_projectile_hit(projectile: ProjectileSim.Projectile, _target: ProjectileSim.Target) -> void:
	# Projectile hits happen away from the listener; use a fixed pool of 3D players positioned in
	# the current render frame rather than a non-positional cue.
	play_world_sample("rod_gun_hit", projectile.position)


func _on_interaction_refused(point_id: StringName, _reason: String) -> void:
	if point_id in [&"cockpit_door", &"engineering_door", &"turret_door", &"cargo_door", &"airlock_inner", &"airlock_outer"]:
		play_sample("sfx_int_door_deny")


func _inventory_total() -> int:
	var total := 0
	for item_id in session.inventory.item_ids():
		total += session.inventory.count(item_id)
	return total


## Before a save is restored: mute the state-change cues (the restore itself changes inventory, doors, gear...).
func begin_state_restore() -> void:
	_restoring = true


## After a save is restored: take the loaded state as the new "previous" state, so nothing is announced for it.
func resync_from_state() -> void:
	_restoring = false
	if session == null:
		return
	_previous_shots_fired = ship.weapon.shots_fired
	_previous_gear = ship.state.gear
	_previous_selected_gear = ship.state.selected_gear
	_previous_pickup_total = _inventory_total()
	_previous_landed = ship.state.landed
	_previous_mode = session.mode
	_previous_walkway_state = session.systems.walkway.state
	_previous_door_targets.clear()
	_previous_power_down = session.systems.power.is_shut_down()
	_previous_airlock_pressure = session.systems.airlock_pressure
	_previous_airlock_trend = 0
	_previous_engine_stopped = ship.controller.is_parked() or ship.state.landed
	_previous_boost = ship.last_command.boost
	_previous_outer_open_factor = session.systems.airlock.outer.open_factor
	for subsystem_id in [ShipSubsystems.Id.ENGINES, ShipSubsystems.Id.WEAPONS, ShipSubsystems.Id.REACTOR, ShipSubsystems.Id.LIFE_SUPPORT]:
		_subsystem_low[subsystem_id] = session.systems.subsystems.value(subsystem_id) < SUBSYSTEM_FAIL_BELOW


func _on_inventory_changed() -> void:
	var total := _inventory_total()
	if _restoring:
		_previous_pickup_total = total
		return
	if _previous_pickup_total != -1 and total > _previous_pickup_total:
		play_sample("rod_item_pickup")
	_previous_pickup_total = total


func _exit_tree() -> void:
	for player in _sfx_players:
		player.stop()
	for loop_player in _sample_loops.values():
		(loop_player as AudioStreamPlayer).stop()
	_sample_loops.clear()
	_engine_player.stop()
	_wind_player.stop()
	for world_player in _world_players:
		world_player.stop()


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
	for sfx_bus in ["SFX", "UI", "Ship", "Suit", "Radio"]:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(sfx_bus), linear_to_db(maxf(settings.sfx_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"), linear_to_db(maxf(settings.ambience_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Interior"), linear_to_db(maxf(settings.ambience_volume, 0.0001)))


func _ensure_buses() -> void:
	for bus_name in ["SFX", "Ambience", "Interior", "UI", "Ship", "Suit", "Radio"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")
			if bus_name == "Interior":
				var low_pass := AudioEffectLowPassFilter.new()
				low_pass.cutoff_hz = 1200.0 if GameSettings.instance().sample_audio else 700.0 # bible 3.3; the synth sounds were tuned for 700
				AudioServer.add_bus_effect(index, low_pass)
