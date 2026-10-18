extends "res://tests/test_case.gd"


func _landed_ship_state() -> ShipState:
	var ship_state := ShipState.new()
	ship_state.landed = true
	return ship_state


func _run(systems: ShipSystems, ship_state: ShipState, seconds: float) -> void:
	for tick in int(seconds * 60.0):
		systems.update(1.0 / 60.0, ship_state)


func test_takeoff_is_blocked_until_outer_door_is_closed_and_walkway_stowed() -> void:
	var systems := ShipSystems.new()
	var ship_state := _landed_ship_state()
	assert_eq(systems.takeoff_block_reason(), "", "sealed ship may lift off")
	assert_eq(systems.toggle_outer_door(ship_state), "")
	_run(systems, ship_state, 3.0)
	assert_true(systems.walkway.is_deployed() and systems.airlock.outer.is_passable())
	assert_true(systems.takeoff_block_reason() != "", "open door blocks takeoff")
	assert_eq(systems.toggle_outer_door(ship_state), "")
	_run(systems, ship_state, 4.0)
	assert_true(systems.walkway.is_stowed() and systems.airlock.outer.is_fully_closed())
	assert_eq(systems.takeoff_block_reason(), "")


func test_takeoff_is_blocked_while_someone_is_on_the_walkway_and_walkway_will_not_stow() -> void:
	var systems := ShipSystems.new()
	var ship_state := _landed_ship_state()
	systems.toggle_outer_door(ship_state)
	_run(systems, ship_state, 3.0)
	systems.walkway.occupied = true
	assert_eq(systems.takeoff_block_reason(), "Walkway occupied")
	assert_true(systems.toggle_outer_door(ship_state) != "", "cannot close with someone on the ramp")
	assert_true(not systems.walkway.request_retract())
	assert_true(systems.walkway.is_deployed())


func test_outer_door_is_denied_at_speed_and_in_flight() -> void:
	var systems := ShipSystems.new()
	var flying := ShipState.new()
	assert_true(systems.toggle_outer_door(flying) != "")
	var fast_landed := _landed_ship_state()
	fast_landed.velocity = Vector3(5, 0, 0)
	assert_true(systems.toggle_outer_door(fast_landed) != "")
	assert_true(systems.airlock.outer.is_fully_closed())


func test_walkway_stows_itself_when_ship_speeds_up() -> void:
	var systems := ShipSystems.new()
	var ship_state := _landed_ship_state()
	systems.toggle_outer_door(ship_state)
	_run(systems, ship_state, 3.0)
	ship_state.velocity = Vector3(30, 0, 0) # speed^2 = 900 > 500
	_run(systems, ship_state, 3.0)
	assert_true(systems.walkway.is_stowed())


func test_ship_holds_still_on_the_ground_while_takeoff_is_blocked() -> void:
	var planet := PlanetBody.new()
	var planet_radius := planet.radius
	planet.height_override = func(_dx: float, _dy: float, _dz: float) -> float: return 0.0
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(&"planet")
	ship.state.position = WorldPos.new(&"planet", 0.0, 0.0, planet_radius + 2.05)
	ship.state.basis = Basis(Vector3.RIGHT, PI / 2.0)
	ship.systems = ShipSystems.new()
	for tick in 60:
		ship.simulate_tick(1.0 / 60.0) # parked: settles onto its gear and lands
	assert_true(ship.state.landed)
	var lift := PilotCommand.new()
	lift.thrust = Vector3(0, 1, 0)
	var commands: Array[PilotCommand] = []
	for tick in 300:
		commands.append(lift)
	ship.controller.request_control(ScriptedPilotSource.new(commands), &"pilot_seat")
	ship.systems.walkway.occupied = true
	var altitude_before := planet.altitude_above_ground(ship.state.position)
	for tick in 120:
		ship.simulate_tick(1.0 / 60.0)
	assert_near(planet.altitude_above_ground(ship.state.position), altitude_before, 0.05, "did not lift off")
	assert_true(ship.state.status_message.begins_with("Takeoff blocked"), ship.state.status_message)
	ship.systems.walkway.occupied = false
	for tick in 120:
		ship.simulate_tick(1.0 / 60.0)
	assert_true(planet.altitude_above_ground(ship.state.position) > altitude_before + 1.0, "lifts off once clear")
	ship.free()
