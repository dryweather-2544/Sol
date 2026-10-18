extends "res://tests/test_case.gd"
## Hull damage, repair, suit oxygen, jetpack and airlock pressure.

const DELTA := 1.0 / 60.0


func _flat_planet(breathable: bool = true, atmosphere: float = 200000.0, gravity: float = 12.0) -> PlanetBody:
	var planet := PlanetBody.new()
	planet.breathable = breathable
	planet.atmosphere_height = atmosphere
	planet.surface_gravity = gravity
	planet.height_override = func(_dx: float, _dy: float, _dz: float) -> float: return 0.0
	return planet


func _session_on_ground(planet: PlanetBody) -> GameSession:
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	ship.state.position = WorldPos.new(planet.frame_id, 0.0, 0.0, planet.radius + 2.1)
	ship.state.basis = Basis(Vector3.RIGHT, PI / 2.0)
	var session := GameSession.new(planet, ship, PilotSource.new())
	for tick in 120:
		session.tick(DELTA, OnFootCommand.new())
	return session


func test_damage_curves() -> void:
	assert_eq(ShipDamage.impact_damage(10.0), 0.0, "gentle touchdown is free")
	assert_true(ShipDamage.impact_damage(50.0) > 0.1 and ShipDamage.impact_damage(50.0) < 0.9)
	assert_eq(ShipDamage.impact_damage(120.0), 1.0, "fast impact is fatal")
	assert_eq(ShipDamage.heating_rate(20000.0, 2.0), 0.0, "no heat in space")
	assert_eq(ShipDamage.heating_rate(1000.0, 0.5), 0.0, "slow in air is fine")
	assert_eq(ShipDamage.heating_rate(PlanetBody.CRUISE_SPEED_LIMIT_IN_ATMOSPHERE, 0.5), 0.0, "cruising at the atmosphere speed limit never burns the hull")
	assert_true(ShipDamage.heating_rate(18000.0, 0.5) > 0.0, "arriving faster than the limit does")


func test_hard_landing_hurts_the_hull_and_destruction_is_signalled_once() -> void:
	var planet := _flat_planet()
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	ship.state.position = WorldPos.new(planet.frame_id, 0.0, 0.0, planet.radius + 60.0)
	ship.state.basis = Basis(Vector3.RIGHT, PI / 2.0)
	ship.state.velocity = Vector3(0, 0, -45)
	var destroyed_count := [0]
	ship.destroyed.connect(func(): destroyed_count[0] += 1)
	for tick in 200:
		ship.simulate_tick(DELTA)
	assert_true(ship.state.hull < 0.95 and ship.state.hull > 0.0, "a 45 m/s impact damages but does not destroy: %f" % ship.state.hull)
	assert_eq(destroyed_count[0], 0)
	ship.state.velocity = Vector3(0, 0, -150)
	ship.state.position = WorldPos.new(planet.frame_id, 0.0, 0.0, planet.radius + 400.0)
	for tick in 200:
		ship.simulate_tick(DELTA)
	assert_eq(ship.state.hull, 0.0)
	assert_eq(destroyed_count[0], 1, "signalled exactly once")
	ship.free()


func test_repair_panel_restores_the_hull_only_when_landed() -> void:
	var session := _session_on_ground(_flat_planet())
	session.ship.state.hull = 0.4
	session.interact() # stand up
	session.interior_body.place(Vector3(-2.0, -0.9, -1.0), 0.0)
	session.interact()
	assert_true(session.repairing, "repair started")
	for tick in 60 * 6:
		session.tick(DELTA, OnFootCommand.new())
	assert_eq(session.ship.state.hull, 1.0)
	assert_true(not session.repairing, "stops by itself when full")
	session.ship.state.hull = 0.5
	session.ship.state.landed = false
	session.interact()
	assert_true(not session.repairing, "cannot repair in flight")
	session.ship.free()


func test_oxygen_drains_in_vacuum_refills_in_air_and_suffocation_kills() -> void:
	var suit := SuitState.new()
	var died := [false]
	suit.died.connect(func(): died[0] = true)
	for tick in 60 * 60:
		suit.update(DELTA, false, false, true)
	assert_true(suit.oxygen < 0.7 and suit.oxygen > 0.6, "a minute of a 3 minute tank: %f" % suit.oxygen)
	for tick in 60 * 15:
		suit.update(DELTA, true, false, true)
	assert_eq(suit.oxygen, 1.0)
	for tick in 60 * 400:
		suit.update(DELTA, false, false, true)
	assert_eq(suit.oxygen, 0.0)
	assert_true(died[0] and suit.health == 0.0)


func test_jetpack_lifts_in_air_burns_fuel_and_stops_without_fuel() -> void:
	var planet := _flat_planet(false, 0.0, 3.5)
	var body := OnFootBody.new()
	body.place_on_ground(planet, WorldPos.new(planet.frame_id, 0.0, 0.0, planet.radius), Vector3(1, 0, 0))
	var suit := SuitState.new()
	var hop := OnFootCommand.new()
	hop.jump = true
	hop.jetpack = true
	var highest := 0.0
	for tick in 240:
		body.jetpack_fuel_available = suit.has_fuel()
		body.step(hop, planet, DELTA)
		suit.update(DELTA, true, body.jetpack_burning, body.grounded)
		highest = maxf(highest, body.height_above_ground)
	assert_true(highest > 15.0, "jetpack climbs well above a plain jump (about 3.6 m here): %f" % highest)
	assert_true(suit.fuel < 0.5 or body.grounded, "fuel was spent")
	body.jetpack_fuel_available = false
	hop.jump = false # no more hopping, just the (empty) jetpack
	for tick in 1200:
		body.step(hop, planet, DELTA)
	assert_true(body.grounded, "falls back down once the fuel is gone")


func test_vacuum_world_airlock_vents_blocks_inner_door_and_costs_oxygen() -> void:
	var planet := _flat_planet(false, 0.0, 3.5)
	var session := _session_on_ground(planet)
	var systems := session.systems
	assert_near(systems.ambient_pressure, 0.0, 1e-9)
	session.interact()
	var ship_state := session.ship.state
	assert_eq(systems.toggle_outer_door(ship_state), "")
	for tick in 60 * 3:
		session.tick(DELTA, OnFootCommand.new())
	assert_true(systems.airlock_pressure < 0.05, "airlock vented: %f" % systems.airlock_pressure)
	assert_true(systems.toggle_inner_door() != "", "inner door refuses while the airlock is in vacuum")
	session.interior_body.place(Vector3(0, -0.9, 9.3), 0.0)
	var oxygen_before := session.suit.oxygen
	for tick in 60 * 20:
		session.tick(DELTA, OnFootCommand.new())
	assert_true(session.suit.oxygen < oxygen_before, "standing in the vented airlock uses the suit tank")
	# Close up and wait for the pressure to come back.
	session.interior_body.place(Vector3(0, -0.9, 9.3), 0.0)
	assert_eq(systems.toggle_outer_door(ship_state), "")
	for tick in 60 * 8:
		session.tick(DELTA, OnFootCommand.new())
	assert_true(systems.airlock_pressure > 0.99, "repressurised")
	session.ship.free()
