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
	ship.state.velocity = Vector3(0, 0, -3) # a slow settling descent; the 30 m/s impact case is the restitution test
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


func test_landed_on_a_slope_in_precision_gear_stays_landed_hands_off() -> void:
	# Precision gear hovers when hands off; a landed ship must stay seated while it tilts to the slope (it turns about
	# its centre, which used to lift one end's feet more than LIFTOFF_DISTANCE and leave it hovering just off the ground).
	for slope_degrees in [10.0, 20.0, 30.0]:
		var planet := _sloped_planet(slope_degrees)
		var ship := _ship_above_pole(planet, 4.0)
		ship.controller.request_control(GentleDescent.new(), &"pilot_seat")
		_settle(ship, 360)
		assert_true(ship.state.landed, "%d degrees: landed" % int(slope_degrees))
		var landed_ticks := 0
		for tick in 600:
			ship.simulate_tick(DELTA)
			landed_ticks += 1 if ship.state.landed else 0
		assert_eq(landed_ticks, 600, "%d degrees: stayed landed for 10 s hands off" % int(slope_degrees))
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


func test_hull_impact_restitution_matches_rodina() -> void:
	var planet := _sloped_planet(0.0)
	var ship := _ship_above_pole(planet, 3.0)
	ship.state.velocity = Vector3(0, 0, -30)
	var bounced := 0.0
	for tick in 30:
		ship.simulate_tick(DELTA)
		if ship.state.last_impact_speed > 20.0:
			bounced = maxf(bounced, ship.state.velocity.z)
	if bounced == 0.0:
		# The first contact may already be the only contact in this short window; a fresh drop
		# records its outgoing normal speed on the impact tick.
		for tick in 30:
			ship.simulate_tick(DELTA)
			bounced = maxf(bounced, ship.state.velocity.z)
	assert_true(bounced > 10.0, "30 m/s impact should bounce upward at about 0.8 restitution, got %f" % bounced)
	ship.free()
