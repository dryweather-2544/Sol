extends "res://tests/test_case.gd"
## No hidden attitude corrections: flying the real Ship over Aurelia through the old 400 m levelling band, the middle of
## the atmosphere (ratio 0.5) and its top (ratio 1), at different attitudes and speeds, the nose's pitch only changes by
## the ship's own spin, and the spin never jumps from one tick to the next. Roll may be eased level in the air (Rodina's
## roll-only levelling) but never pitch. Attitude is measured against the local horizon.

const DELTA := 1.0 / 60.0
## Largest believable change of spin in one tick, rad/s: the strongest real push (player roll 0.7 x 3 x 2.5 = 5.25 rad/s^2,
## levelling up to ~5.7 rad/s^2) is under 0.1 rad/s per tick; a forced attitude would be far larger.
const MAX_SPIN_STEP := 0.1


class Hold extends PilotSource:
	var command: PilotCommand

	func _init(held: PilotCommand) -> void:
		source_id = &"boundary_test"
		command = held

	func poll(_ship_state: ShipState, _delta: float) -> PilotCommand:
		return command


var _planet := PlanetBody.new()


func _ship(altitude: float, pitch_degrees: float, roll_degrees: float, vertical_speed: float, command: PilotCommand) -> Ship:
	var ship := Ship.new()
	ship.planet = _planet
	ship.render_origin = WorldPos.new(_planet.frame_id)
	var up := Vector3(0.3, 0.5, 0.8).normalized()
	var ground := _planet.surface_radius_xyz(up.x, up.y, up.z)
	ship.state.position = WorldPos.new(_planet.frame_id, up.x * (ground + altitude), up.y * (ground + altitude), up.z * (ground + altitude))
	ship.state.basis = Basis.looking_at(Vector3.UP.cross(up).normalized(), up) * Basis(Vector3(1, 0, 0), deg_to_rad(pitch_degrees)) * Basis(Vector3(0, 0, 1), deg_to_rad(roll_degrees))
	ship.state.velocity = up * vertical_speed
	ship.state.gear = command.gear
	ship.controller.request_control(Hold.new(command), &"pilot_seat")
	return ship


func _pitch(ship: Ship) -> float:
	var up := _planet.up_at(ship.state.position)
	return asin(clampf(-ship.state.basis.z.dot(up), -1.0, 1.0))


## Flies until the altitude passes `through` (either way), checking the spin never jumps. Returns [pitch before, pitch
## after, worst spin step, crossed].
func _cross(ship: Ship, through: float, max_ticks: int) -> Array:
	var start_pitch := _pitch(ship)
	var worst := 0.0
	var previous := ship.state.angular_velocity
	var above := ship.state.altitude_above_ground > through if ship.state.altitude_above_ground < INF else true
	var crossed := false
	for tick in max_ticks:
		ship.simulate_tick(DELTA)
		worst = maxf(worst, ship.state.angular_velocity.distance_to(previous))
		previous = ship.state.angular_velocity
		if (ship.state.altitude_above_ground > through) != above:
			crossed = true
			for after in 30: # and a little beyond
				ship.simulate_tick(DELTA)
				worst = maxf(worst, ship.state.angular_velocity.distance_to(previous))
				previous = ship.state.angular_velocity
			break
	return [start_pitch, _pitch(ship), worst, crossed]


func _command(gear: int, thrust := Vector3.ZERO, turn := Vector3.ZERO) -> PilotCommand:
	var command := PilotCommand.new()
	command.gear = gear
	command.thrust = thrust
	command.turn = turn
	return command


func test_climbing_pitched_up_through_the_old_400_m_band_keeps_the_pitch() -> void:
	# Combat gear, full upward thrust (0.3 x 500 = 150 m/s target), nose 25 degrees up, wings level.
	var ship := _ship(250.0, 25.0, 0.0, 0.0, _command(PilotCommand.GEAR_COMBAT, Vector3(0, 1, 0)))
	var result := _cross(ship, 400.0, 600)
	assert_true(result[3], "crossed 400 m")
	assert_near(result[1], result[0], 1e-4, "pitch unchanged: %.4f -> %.4f rad" % [result[0], result[1]])
	assert_true(result[2] < MAX_SPIN_STEP, "no spin jump: %.4f rad/s" % result[2])
	ship.free()


func test_descending_nose_down_and_rolled_through_400_m_keeps_the_pitch() -> void:
	var ship := _ship(700.0, -15.0, 30.0, -60.0, _command(PilotCommand.GEAR_COMBAT))
	var result := _cross(ship, 400.0, 600)
	assert_true(result[3], "crossed 400 m going down")
	assert_true(absf(result[1] - result[0]) < deg_to_rad(1.0), "pitch only drifts with the roll easing (< 1 degree): %.4f -> %.4f" % [result[0], result[1]])
	assert_true(result[2] < MAX_SPIN_STEP, "no spin jump: %.4f rad/s" % result[2])
	ship.free()


func test_rolling_by_hand_through_the_middle_of_the_atmosphere_is_continuous() -> void:
	# Holding roll while dropping through ratio 0.5 (100 km), where "in the atmosphere" and the 4 s entry timer start.
	var ship := _ship(101500.0, 0.0, 0.0, -1500.0, _command(PilotCommand.GEAR_COMBAT, Vector3.ZERO, Vector3(0, 0, 1)))
	var result := _cross(ship, 100000.0, 600)
	assert_true(result[3], "crossed ratio 0.5")
	assert_true(result[2] < MAX_SPIN_STEP, "roll rate continuous across the boundary: %.4f rad/s" % result[2])
	ship.free()


func test_entering_the_atmosphere_at_different_angles_and_speeds_never_jumps() -> void:
	for case in [[0.0, -1000.0], [-30.0, -3000.0], [-60.0, -6000.0], [20.0, -500.0]]:
		var ship := _ship(201000.0, case[0], 0.0, case[1], _command(PilotCommand.GEAR_COMBAT))
		var result := _cross(ship, 200000.0, 600)
		assert_true(result[3], "crossed the top of the air (pitch %d, %d m/s)" % [int(case[0]), int(case[1])])
		assert_true(result[2] < MAX_SPIN_STEP, "no spin jump entering at pitch %d, %d m/s: %.4f" % [int(case[0]), int(case[1]), result[2]])
		ship.free()


func test_a_spinning_ship_in_vacuum_keeps_spinning() -> void:
	var ship := _ship(400000.0, 0.0, 0.0, 0.0, _command(PilotCommand.GEAR_COMBAT))
	ship.state.angular_velocity = Vector3(0.4, -0.2, 0.7)
	for tick in 300:
		ship.simulate_tick(DELTA)
	assert_near(ship.state.angular_velocity.distance_to(Vector3(0.4, -0.2, 0.7)), 0.0, 1e-6, "no friction, no levelling, no assist above the air")
	ship.free()
