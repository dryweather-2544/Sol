extends "res://tests/test_case.gd"
## Scripted descent from 300 km to touchdown on the real terrain function. The pilot is a small
## rule-based PilotSource (not a recorded stream) so the test keeps working if tuning changes.

const DELTA := 1.0 / 60.0
const SPAWN_ALTITUDE := 300000.0


class DescentPilot extends PilotSource:
	func _init() -> void:
		source_id = &"descent_test"

	func poll(ship_state: ShipState, _delta: float) -> PilotCommand:
		var command := PilotCommand.new()
		var altitude := ship_state.altitude_above_ground
		command.gear = PilotCommand.GEAR_CRUISE if altitude > 4000.0 else PilotCommand.GEAR_DOCK
		# Ship is oriented belly-down (ship up = planet up), so descending means thrusting along -y.
		command.thrust = Vector3(0, -clampf(altitude / 80.0, 0.04, 1.0), 0)
		return command


func _spawn_ship(planet: PlanetBody, direction: Vector3) -> Ship:
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	var spawn_radius := planet.radius + SPAWN_ALTITUDE
	ship.state.position = WorldPos.new(planet.frame_id, direction.x * spawn_radius, direction.y * spawn_radius, direction.z * spawn_radius)
	ship.state.basis = Basis.looking_at(Vector3.UP.cross(direction).normalized() if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT, direction)
	return ship


func test_descent_from_orbit_reaches_landed_and_never_goes_below_terrain() -> void:
	var planet := PlanetBody.new()
	var ship := _spawn_ship(planet, Vector3(0.3, 0.5, 0.8).normalized())
	ship.controller.request_control(DescentPilot.new(), &"pilot_seat")
	var landed_tick := -1
	var lowest_clearance := INF
	for tick in 60 * 600:
		ship.simulate_tick(DELTA)
		var support_clearance := planet.altitude_above_ground(ship.state.position) - 0.6 * 1.0
		lowest_clearance = minf(lowest_clearance, support_clearance)
		if ship.state.landed:
			landed_tick = tick
			break
	assert_true(landed_tick > 0, "never landed; altitude %f, regime %s" % [ship.state.altitude_above_ground, FlightRegime.label(ship.state.regime)])
	assert_true(landed_tick < 60 * 400, "landing took %d s" % int(landed_tick / 60.0))
	assert_true(lowest_clearance > -1.5, "ship centre went %f m below terrain level - 0.6 m support offset" % lowest_clearance)
	assert_eq(ship.state.regime, FlightRegime.LANDED)
	ship.free()


func test_cruise_straight_at_terrain_is_clamped_and_never_inside() -> void:
	var planet := PlanetBody.new()
	var ship := _spawn_ship(planet, Vector3(0.0, 1.0, 0.0))
	var cruise_into_ground := PilotCommand.new()
	cruise_into_ground.gear = PilotCommand.GEAR_CRUISE
	cruise_into_ground.boost = true
	cruise_into_ground.thrust = Vector3(0, -1, 0)
	var commands: Array[PilotCommand] = []
	for tick in 60 * 120:
		commands.append(cruise_into_ground)
	ship.controller.request_control(ScriptedPilotSource.new(commands), &"pilot_seat")
	var deepest := INF
	var fastest := 0.0
	for tick in 60 * 120:
		ship.simulate_tick(DELTA)
		deepest = minf(deepest, planet.altitude_above_ground(ship.state.position))
		fastest = maxf(fastest, ship.state.speed())
	assert_true(fastest > 3000.0, "cruise reached real speed: %f" % fastest)
	assert_true(deepest > 0.0, "ship centre went below the terrain: %f" % deepest)
	ship.free()
