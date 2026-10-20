extends "res://tests/test_case.gd"
## "Mayday on Selene", headless: the ambush at Selene, a damaged landing with the crew fighting the fire and the
## turret killing the raider, the coupling from the beacon's crate, installing it, and taking off again. Frame
## changes are fed in by the test (the transfer is covered by frame_switch_test), and the walk to the crate is a
## placement (walking is covered by the full loop test). Checks the state stays legal and saves resume at each beat.

const DELTA := 1.0 / 60.0
const SAVE_DIRECTORY := "user://test_saves_slice"


class Bot extends PilotSource:
	var takeoff := false

	func _init() -> void:
		source_id = &"slice_bot"

	func poll(ship_state: ShipState, _delta: float) -> PilotCommand:
		var command := PilotCommand.new()
		command.move_lock = 1.0 # scripted pilot: holds the velocity it asks for (Rodina AI mover MoveLock)
		command.stop_rotation = true # and holds its attitude (Rodina AI sets its turn rate directly)
		var altitude := ship_state.altitude_above_ground
		var up := Vector3(ship_state.position.x, ship_state.position.y, ship_state.position.z).normalized()
		if takeoff:
			command.gear = PilotCommand.GEAR_CRUISE if altitude > 2500.0 else PilotCommand.GEAR_COMBAT
			command.thrust = Vector3(0, 1, 0)
			return command
		ship_state.basis = Basis.looking_at(Vector3.UP.cross(up).normalized(), up)
		command.gear = PilotCommand.GEAR_COMBAT if altitude > 250.0 else PilotCommand.GEAR_DOCK
		command.thrust = Vector3(0, -clampf(altitude / 80.0, 0.04, 1.0), 0)
		return command


var _session: GameSession
var _bot := Bot.new()
var _raider: Ship
var _legal_failure := ""
var _ticks := 0
var _turret_fired := false
var _saw_fire := false


func _spawn_raider(_beacon_direction: Vector3) -> void:
	var player_ship := _session.ship.state
	_raider = Ship.new()
	_raider.name = "Raider"
	_raider.planet = _session.planet
	_raider.team_id = 1
	_raider.render_origin = WorldPos.new(_session.planet.frame_id)
	_raider.weapon.damage = 0.012
	_raider.projectiles = _session.projectiles
	_raider.state.position = player_ship.position.offset_by(-player_ship.basis.z * 700.0 + player_ship.basis.y * 100.0)
	_raider.state.basis = Basis.looking_at(player_ship.basis.z, player_ship.basis.y)
	var ai := AIPilotSource.new(AIPilotSource.Mode.ATTACK)
	ai.target_provider = func(): return _session.ship.state.position
	ai.target_velocity_provider = func(): return _session.ship.state.velocity
	_raider.controller.request_control(ai, &"raider_ai")
	_session.enemy_targets.append(ShipCombatant.new(_raider, 1))


func _tick(frame: StringName, foot_command: OnFootCommand = null) -> void:
	_session.progress.update(_session, frame)
	_session.tick(DELTA, foot_command if foot_command != null else OnFootCommand.new())
	if _raider != null and _raider.state.hull > 0.0:
		_raider.simulate_tick(DELTA)
	_ticks += 1
	_turret_fired = _turret_fired or _session.systems.turret.firing
	_saw_fire = _saw_fire or _session.systems.hazards.any_fire()
	if _ticks % 30 == 0 and _legal_failure == "":
		var problem := _session.validate()
		if problem != "":
			_legal_failure = "tick %d: %s" % [_ticks, problem]


## restore_mode is for loading saves and frees every seat, so put the crew back in theirs.
func _set_mode(mode: int) -> void:
	var crew_state := _session.crew.to_array()
	_session.restore_mode(mode)
	_session.crew.restore(_session.systems, crew_state)


func _save_and_reload(slot: String) -> GameSession:
	var manager := SaveManager.new(SAVE_DIRECTORY)
	assert_eq(manager.save(slot, SaveGame.capture(_session, 42)), "")
	var loaded := manager.load_slot(slot)
	assert_true(loaded["ok"], loaded["error"])
	var ship := Ship.new()
	ship.planet = _session.planet
	ship.render_origin = WorldPos.new(_session.planet.frame_id)
	var fresh := GameSession.new(_session.planet, ship, PilotSource.new())
	assert_eq(SaveGame.restore(fresh, loaded["data"]), "")
	return fresh


func test_mayday_on_selene_from_ambush_to_takeoff() -> void:
	var planet := PlanetBody.new()
	planet.height_override = func(_dx: float, _dy: float, _dz: float) -> float: return 0.0
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	var direction := Vector3(0.3, 0.5, 0.8).normalized()
	var spawn_radius := planet.radius + 1200.0
	ship.state.position = WorldPos.new(planet.frame_id, direction.x * spawn_radius, direction.y * spawn_radius, direction.z * spawn_radius)
	ship.state.basis = Basis.looking_at(Vector3.UP.cross(direction).normalized(), direction)
	_session = GameSession.new(planet, ship, _bot)
	_session.crew.add_member(_session.systems, &"mara", &"engineer", &"reactor_panel")
	_session.crew.add_member(_session.systems, &"kit", &"gunner", &"gunner_seat")
	_session.ambush_requested.connect(_spawn_raider)
	_session.progress.current = 3 # the warp is installed; the Mayday call has come in
	_session.progress.warp_installed = true

	# 1. Arriving at Selene springs the ambush: a raider, and the next hit is a guaranteed engine hit and fire.
	_tick(&"selene")
	assert_true(_session.progress.ambush_started)
	assert_true(_raider != null, "raider spawned")
	assert_true(_session.systems.ambush_armed)
	assert_true(_session.progress.beacon_direction.length() > 0.99, "beacon direction fixed")
	for tick in 60 * 400:
		_tick(&"selene")
		if ship.state.landed and _raider.state.hull <= 0.0 and not _session.systems.hazards.any_fire() and _session.progress.current >= 4:
			break
	assert_true(ship.state.landed, "landed on Selene (altitude %f)" % ship.state.altitude_above_ground)
	assert_true(_raider.state.hull <= 0.0, "raider destroyed")
	assert_true(_turret_fired, "the gunner's turret fired")
	assert_true(_saw_fire, "the ambush started a fire")
	assert_true(not _session.systems.hazards.any_fire(), "the engineer put it out")
	assert_near(_session.systems.subsystems.cap[ShipSubsystems.Id.ENGINES], 0.6, 1e-9, "engines capped by the burnt coupling")
	assert_true(_session.systems.subsystems.value(ShipSubsystems.Id.ENGINES) <= 0.6 + 1e-9)
	assert_eq(_session.progress.current, 4, "landing on Selene advanced the mission")

	# 2. Save and resume at the beat.
	var resumed := _save_and_reload("beat_landed")
	assert_eq(resumed.progress.current, 4)
	assert_true(resumed.progress.ambush_started)
	assert_near(resumed.systems.subsystems.cap[ShipSubsystems.Id.ENGINES], 0.6, 1e-9)
	assert_true(not resumed.systems.ambush_armed, "the ambush hit already happened")
	resumed.ship.free()

	# 3. Stand up, go to the beacon's crate, take the coupling.
	_session.interact()
	assert_eq(_session.mode, GameSession.Mode.INSIDE)
	var beacon := PoiInstance.new()
	beacon.id = ProgressTracker.BEACON_ID
	beacon.type = PoiDefinition.Type.BEACON
	beacon.seed_value = 99
	var up := _session.ship.state.position
	var up_unit := Vector3(up.x, up.y, up.z).normalized()
	beacon.position = _session.ship.state.position.offset_by(_session.ship.state.basis.x * 40.0)
	beacon.position = WorldPos.new(planet.frame_id, beacon.position.x, beacon.position.y, beacon.position.z)
	var frame := PoiBuilder.frame_basis(beacon)
	var crate := PoiBuilder.crate_positions(beacon)[0]
	_session.nearby_pois = [beacon]
	_session.exterior_body.place_on_ground(planet, beacon.position.offset_by(frame.x * (crate.x + 1.0) + frame.z * crate.y), Vector3(1, 0, 0))
	_set_mode(GameSession.Mode.OUTSIDE)
	_tick(&"selene")
	assert_eq(_session.prompt(), "F: open crate")
	_session.interact()
	assert_eq(_session.inventory.count(ItemDefinition.ENGINE_COUPLING), 1, "the beacon's crate held the coupling")
	_tick(&"selene")
	assert_eq(_session.progress.current, 5)
	assert_true(up_unit.length() > 0.5)

	# 4. Back aboard, install it at the engine station.
	_set_mode(GameSession.Mode.INSIDE)
	var spot := _session.systems.layout.standing_spot_for(&"engine_station")
	_session.interior_body.place(Vector3(spot.x, _session.systems.layout.floor_y, spot.y), 0.0)
	_tick(&"selene")
	assert_eq(_session.prompt(), "F: engine station (install a part)")
	_session.interact()
	_tick(&"selene")
	assert_eq(_session.progress.current, 6)
	assert_near(_session.systems.subsystems.value(ShipSubsystems.Id.ENGINES), 1.0, 1e-9)
	assert_near(_session.systems.subsystems.cap[ShipSubsystems.Id.ENGINES], 1.0, 1e-9)
	assert_eq(_session.inventory.count(ItemDefinition.ENGINE_COUPLING), 0)
	var resumed_again := _save_and_reload("beat_installed")
	assert_eq(resumed_again.progress.current, 6)
	assert_true(resumed_again.progress.coupling_installed)
	resumed_again.ship.free()

	# 5. Sit, take off, and reach orbit; back at Aurelia the mission is done.
	_set_mode(GameSession.Mode.SEATED)
	_bot.takeoff = true
	var reached_space := false
	for tick in 60 * 200:
		_tick(&"selene")
		if ship.state.regime == FlightRegime.SPACE:
			reached_space = true
			break
	assert_true(reached_space, "took off to space (altitude %f)" % ship.state.altitude_above_ground)
	_tick(&"planet")
	assert_eq(_session.progress.current, 7, "orbit above Aurelia completes the errand")
	assert_eq(_legal_failure, "", "state stayed legal")
	ship.free()
	if _raider != null:
		_raider.free()
