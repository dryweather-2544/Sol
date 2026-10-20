extends "res://tests/test_case.gd"

const DELTA := 1.0 / 60.0


## Planet whose terrain is a plane tilted by slope_degrees about the pole at +z (x rises).
func _sloped_planet(slope_degrees: float) -> PlanetBody:
	var planet := PlanetBody.new()
	planet.frame_id = &"planet"
	var slope := tan(deg_to_rad(slope_degrees))
	var planet_radius := planet.radius # captured by value: capturing `planet` would leak a reference cycle
	planet.height_override = func(dx: float, _dy: float, _dz: float) -> float: return slope * dx * planet_radius
	return planet


func _ship_above_pole(planet: PlanetBody, height_above_surface: float) -> Ship:
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(&"planet")
	ship.state.position = WorldPos.new(&"planet", 0.0, 0.0, planet.radius + height_above_surface)
	ship.state.basis = Basis(Vector3.RIGHT, PI / 2.0) # rotating +90 deg about x sends ship up (+y) to planet up (+z)
	return ship


func _settle(ship: Ship, ticks: int) -> void:
	for tick in ticks:
		ship.simulate_tick(DELTA)


func test_ship_never_ends_up_below_flat_ground_and_lands() -> void:
	var planet := _sloped_planet(0.0)
	var ship := _ship_above_pole(planet, 3.0)
	ship.state.velocity = Vector3(0, 0, -30) # falling toward the ground
	var coast := PilotCommand.parked(0)
	ship.controller.request_control(ScriptedPilotSource.new([coast, coast, coast]), &"pilot_seat")
	_settle(ship, 300)
	assert_true(ship.state.landed, "should be landed after a slow settle")
	var clearance := planet.altitude_above_ground(ship.state.position)
	assert_true(clearance > 1.7 and clearance < 2.4, "centre rests on its support points (2 m below it): %f" % clearance)
	assert_true(ship.state.speed() < 0.1)
	ship.free()


## Sinks at 2 m/s in dock gear, holding that velocity (a pilot feathering the vertical thrust for a soft touchdown).
class GentleDescent extends PilotSource:
	func _init() -> void:
		source_id = &"gentle_descent"

	func poll(ship_state: ShipState, _delta: float) -> PilotCommand:
		var command := PilotCommand.new()
		if not ship_state.landed: # hands off once down
			command.thrust = Vector3(0, -2.0 / 12.0, 0) # precision gear: full down is 0.4 x 30 = 12 m/s
			command.move_lock = 1.0
		return command


func test_gentle_slopes_land_and_ship_tilts_to_match() -> void:
	for slope_degrees in [15.0, 25.0]:
		var planet := _sloped_planet(slope_degrees)
		var ship := _ship_above_pole(planet, 5.0)
		ship.controller.request_control(GentleDescent.new(), &"pilot_seat")
		_settle(ship, 360)
		assert_true(ship.state.landed, "%d degree slope should land" % int(slope_degrees))
		var tilt_from_planet_up := rad_to_deg(acos(clampf(ship.state.basis.y.dot(Vector3(0, 0, 1)), -1.0, 1.0)))
		assert_near(tilt_from_planet_up, slope_degrees, 1.5, "ship up should follow the slope")
		var before := ship.state.position.duplicate_position()
		_settle(ship, 60)
		assert_true(ship.state.position.distance_to(before) < 0.01, "settled: no oscillation")
		ship.free()


func test_steep_slope_refuses_landing_with_message() -> void:
	var planet := _sloped_planet(40.0)
	var ship := _ship_above_pole(planet, 3.0)
	_settle(ship, 300)
	assert_true(not ship.state.landed, "40 degrees must not count as landed")
	assert_true(ship.state.status_message.begins_with("Too steep"), "message: '%s'" % ship.state.status_message)
	ship.free()


func test_landed_ship_holds_position_for_a_minute() -> void:
	var planet := _sloped_planet(10.0)
	var ship := _ship_above_pole(planet, 2.0)
	_settle(ship, 300)
	assert_true(ship.state.landed)
	var rest_position := ship.state.position.duplicate_position()
	_settle(ship, 3600)
	assert_true(ship.state.landed)
	assert_true(ship.state.position.distance_to(rest_position) < 0.01, "drift %f m" % ship.state.position.distance_to(rest_position))
	ship.free()


func test_thrust_up_lifts_off_and_clears_landed() -> void:
	var planet := _sloped_planet(0.0)
	var ship := _ship_above_pole(planet, 2.0)
	_settle(ship, 300)
	assert_true(ship.state.landed)
	var lift := PilotCommand.new()
	lift.thrust = Vector3(0, 1, 0)
	var commands: Array[PilotCommand] = []
	for tick in 120:
		commands.append(lift)
	ship.controller.request_control(ScriptedPilotSource.new(commands), &"pilot_seat")
	_settle(ship, 120)
	assert_true(not ship.state.landed, "left the ground")
	assert_true(planet.altitude_above_ground(ship.state.position) > 3.0)
	ship.free()
