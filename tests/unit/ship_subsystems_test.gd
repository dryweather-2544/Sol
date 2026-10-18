extends "res://tests/test_case.gd"
## N2: subsystem health and reactor power change how the player's ship flies and shoots, survive saves,
## and are fixed by the repair panel.

const TICK := 1.0 / 60.0
const SAVE_DIRECTORY := "user://test_saves_subsystems"


func _ship_flying_forward(seconds: float, engines_health: float) -> Ship:
	var ship := Ship.new()
	ship.systems = ShipSystems.new()
	ship.systems.subsystems.health[ShipSubsystems.Id.ENGINES] = engines_health
	var commands: Array[PilotCommand] = []
	for tick in int(seconds * 60.0):
		var command := PilotCommand.new()
		command.thrust = Vector3(0, 0, -1)
		commands.append(command)
	ship.controller.request_control(ScriptedPilotSource.new(commands), &"pilot_seat")
	for tick in commands.size():
		ship.simulate_tick(TICK)
		ship.systems.update(TICK, ship.state)
	return ship


func test_half_health_engines_reach_about_half_the_speed() -> void:
	var healthy := _ship_flying_forward(3.0, 1.0)
	var damaged := _ship_flying_forward(3.0, 0.5)
	assert_true(healthy.state.speed() > 10.0, "baseline moves: %f" % healthy.state.speed())
	assert_true(damaged.state.speed() <= healthy.state.speed() * 0.55, "damaged %f vs healthy %f" % [damaged.state.speed(), healthy.state.speed()])
	assert_true(damaged.state.speed() >= healthy.state.speed() * 0.4, "but not dead: %f" % damaged.state.speed())
	healthy.free()
	damaged.free()


func test_dead_engines_still_give_emergency_thrust() -> void:
	var crippled := _ship_flying_forward(3.0, 0.0)
	assert_true(crippled.state.speed() > 1.0, "emergency thrusters move the ship: %f" % crippled.state.speed())
	crippled.free()


func _shots_in_two_seconds(weapons_health: float, weapons_power_limit: float) -> int:
	var ship := Ship.new()
	ship.systems = ShipSystems.new()
	ship.systems.subsystems.health[ShipSubsystems.Id.WEAPONS] = weapons_health
	ship.systems.power.set_limit(ShipPower.Conduit.WEAPONS, weapons_power_limit)
	ship.projectiles = ProjectileSim.new()
	var commands: Array[PilotCommand] = []
	for tick in 120:
		var command := PilotCommand.new()
		command.fire = true
		commands.append(command)
	ship.controller.request_control(ScriptedPilotSource.new(commands), &"pilot_seat")
	var shots := 0
	for tick in 120:
		var before := ship.projectiles.projectiles.size()
		ship.simulate_tick(TICK)
		ship.systems.update(TICK, ship.state)
		if ship.projectiles.projectiles.size() > before:
			shots += 1
	ship.free()
	return shots


func test_dead_or_unpowered_weapons_never_fire_and_weak_ones_fire_slower() -> void:
	var full := _shots_in_two_seconds(1.0, 1.0)
	assert_true(full >= 8, "healthy guns fire: %d" % full)
	assert_eq(_shots_in_two_seconds(0.0, 1.0), 0, "dead weapons subsystem")
	assert_eq(_shots_in_two_seconds(1.0, 0.0), 0, "weapons conduit limited to zero")
	var half := _shots_in_two_seconds(0.5, 1.0)
	assert_true(half > 0 and half < full, "half health fires slower: %d vs %d" % [half, full])


func test_hit_direction_picks_the_subsystem() -> void:
	assert_eq(ShipSubsystems.subsystem_for_direction(Vector3(0, 0, 1)), ShipSubsystems.Id.ENGINES, "from behind")
	assert_eq(ShipSubsystems.subsystem_for_direction(Vector3(0, 0, -1)), ShipSubsystems.Id.WEAPONS, "from ahead")
	assert_eq(ShipSubsystems.subsystem_for_direction(Vector3(0, 1, 0)), ShipSubsystems.Id.REACTOR, "from above")
	assert_eq(ShipSubsystems.subsystem_for_direction(Vector3(1, 0, 0)), ShipSubsystems.Id.LIFE_SUPPORT, "from the side")


func test_shot_from_behind_damages_hull_and_engines() -> void:
	var ship := Ship.new()
	ship.systems = ShipSystems.new()
	var attacker := Ship.new()
	attacker.state.position = WorldPos.new(&"space", 0.0, 0.0, 500.0)
	var combatant := ShipCombatant.new(ship, 0)
	combatant.apply_damage(0.1, attacker)
	assert_near(ship.state.hull, 0.9, 1e-9)
	assert_near(ship.systems.subsystems.value(ShipSubsystems.Id.ENGINES), 1.0 - 0.1 * ShipSubsystems.SYSTEM_DAMAGE_SHARE, 1e-9)
	assert_eq(ship.systems.subsystems.value(ShipSubsystems.Id.WEAPONS), 1.0)
	ship.free()
	attacker.free()


func test_reactor_damage_lowers_available_power_so_heavy_draw_is_cut_back() -> void:
	var systems := ShipSystems.new()
	systems.subsystems.health[ShipSubsystems.Id.REACTOR] = 0.4
	var full_demand := PilotCommand.new()
	full_demand.thrust = Vector3(0, 0, -1)
	full_demand.boost = true
	full_demand.fire = true
	systems.set_demand(full_demand)
	systems.update(TICK, ShipState.new())
	assert_near(systems.power.output(), 40.0, 1e-9)
	assert_true(systems.power.total_delivered() <= 40.0 + 1e-6)
	assert_true(systems.engine_factor() < 1.0, "starved engines")
	assert_true(systems.weapon_factor() < 1.0, "starved guns")


func test_shut_down_reactor_comes_back_after_cooling() -> void:
	var systems := ShipSystems.new()
	systems.power.temperature = 0.999
	var demand := PilotCommand.new()
	demand.thrust = Vector3(0, 0, -1)
	demand.boost = true
	demand.fire = true
	systems.set_demand(demand)
	systems.update(1.0, ShipState.new())
	assert_true(systems.power.is_shut_down() or systems.power.temperature < 1.0)
	var ticks := 0
	systems.set_demand(PilotCommand.new())
	while systems.power.is_shut_down() and ticks < 60 * 120:
		systems.update(TICK, ShipState.new())
		ticks += 1
	assert_true(not systems.power.is_shut_down(), "reactor restarted by itself")


func test_repair_fixes_worst_subsystem_first_and_reports_when_done() -> void:
	var subsystems := ShipSubsystems.new()
	subsystems.health = [0.9, 0.2, 0.6, 1.0]
	assert_eq(subsystems.repair_worst(0.1), "weapons")
	assert_near(subsystems.value(ShipSubsystems.Id.WEAPONS), 0.3, 1e-9)
	for step in 100:
		subsystems.repair_worst(0.1)
	assert_true(subsystems.is_undamaged())
	assert_eq(subsystems.repair_worst(0.1), "")


func _session() -> GameSession:
	var planet := PlanetBody.new()
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	var direction := Vector3(0.3, 0.5, 0.8).normalized()
	var radius := planet.surface_radius_xyz(direction.x, direction.y, direction.z) + 2.1
	ship.state.position = WorldPos.new(planet.frame_id, direction.x * radius, direction.y * radius, direction.z * radius)
	ship.state.basis = Basis.looking_at(Vector3.UP.cross(direction).normalized(), direction)
	return GameSession.new(planet, ship, PilotSource.new())


func test_subsystems_and_reactor_survive_a_save_round_trip() -> void:
	var session := _session()
	session.systems.subsystems.health = [0.3, 0.6, 0.9, 0.1]
	session.systems.power.temperature = 0.7
	session.systems.power.coolant = 0.5
	session.systems.power.set_limit(ShipPower.Conduit.WEAPONS, 0.25)
	var manager := SaveManager.new(SAVE_DIRECTORY)
	assert_eq(manager.save("n2", SaveGame.capture(session, 42)), "")
	var loaded := manager.load_slot("n2")
	assert_true(loaded["ok"], loaded["error"])
	var fresh := _session()
	assert_eq(SaveGame.restore(fresh, loaded["data"]), "")
	assert_eq(fresh.systems.subsystems.to_array(), [0.3, 0.6, 0.9, 0.1])
	assert_near(fresh.systems.power.temperature, 0.7, 1e-9)
	assert_near(fresh.systems.power.coolant, 0.5, 1e-9)
	assert_near(fresh.systems.power.limit(ShipPower.Conduit.WEAPONS), 0.25, 1e-9)
	session.ship.free()
	fresh.ship.free()


func test_v8_fixture_migrates_to_v9_with_intact_ship_and_keeps_its_data() -> void:
	var manager := SaveManager.new(ProjectSettings.globalize_path("res://tests/fixtures/saves"))
	var loaded := manager.load_slot("v8_landed_damaged")
	assert_true(loaded["ok"], loaded["error"])
	var data: Dictionary = loaded["data"]
	assert_eq(int(data["save_version"]), SaveGame.SAVE_VERSION)
	assert_eq(data["systems"]["subsystems"], [1.0, 1.0, 1.0, 1.0])
	var session := _session()
	assert_eq(SaveGame.restore(session, data), "")
	assert_near(session.ship.state.hull, 0.7, 1e-9, "hull from the v8 save kept")
	assert_near(session.ship.state.fuel, 0.6, 1e-9)
	assert_eq(session.progress.current, 2)
	assert_true(session.systems.subsystems.is_undamaged())
	assert_true(not session.systems.power.is_shut_down())
	session.ship.free()


func test_v9_save_with_someone_in_the_old_airlock_moves_them_with_it() -> void:
	var v9 := {"save_version": 9, "player": {"interior_position": [0.0, -0.9, 4.7]}}
	var migrated: Dictionary = SaveMigrations.migrate(v9)["data"]
	assert_near(float(migrated["player"]["interior_position"][2]), 9.3, 1e-9, "old airlock z 4.7 is now 9.3")
	var cabin := {"save_version": 9, "player": {"interior_position": [0.0, -0.9, -2.0]}}
	assert_near(float((SaveMigrations.migrate(cabin)["data"] as Dictionary)["player"]["interior_position"][2]), -2.0, 1e-9, "cabin unchanged")


func test_restoring_a_position_inside_a_wall_puts_the_player_at_the_pilot_seat() -> void:
	var session := _session()
	var data := SaveGame.capture(session, 42)
	data["player"]["interior_position"] = [2.0, -0.9, -0.1] # in the wall between cabin and engineering
	var fresh := _session()
	assert_eq(SaveGame.restore(fresh, data), "")
	assert_true(fresh.systems.layout.is_position_walkable(fresh.interior_body.position.x, fresh.interior_body.position.z, 0.0), "safe place")
	session.ship.free()
	fresh.ship.free()
