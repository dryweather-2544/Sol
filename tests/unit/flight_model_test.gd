extends "res://tests/test_case.gd"
## Flight maths with hand-computed expectations (gear 0: max 100 m/s, accel 60, decel 80).

const DELTA := 1.0 / 60.0


func _fly(ship_state: ShipState, command: PilotCommand, ticks: int, environment: FlightEnvironment = null) -> void:
	var tuning := ShipTuning.new()
	var flight_environment := environment if environment != null else FlightEnvironment.new()
	for tick in ticks:
		FlightModel.step(ship_state, command, tuning, flight_environment, DELTA)


func _thrust(thrust_vector: Vector3) -> PilotCommand:
	var command := PilotCommand.new()
	command.thrust = thrust_vector
	return command


func test_forward_thrust_accelerates_at_gear_acceleration_along_minus_z() -> void:
	var ship_state := ShipState.new()
	_fly(ship_state, _thrust(Vector3(0, 0, -1)), 30)
	assert_near(ship_state.velocity.z, -30.0, 1e-4, "60 m/s^2 for 0.5 s")
	assert_near(ship_state.velocity.x, 0.0, 1e-6)
	# semi-implicit Euler: position = accel * dt^2 * N(N+1)/2
	assert_near(ship_state.position.z, -60.0 * DELTA * DELTA * 30.0 * 31.0 / 2.0, 1e-3)


func test_speed_is_capped_at_gear_max() -> void:
	var ship_state := ShipState.new()
	_fly(ship_state, _thrust(Vector3(0, 0, -1)), 300)
	assert_near(ship_state.speed(), 100.0, 1e-4)


func test_sideways_and_vertical_are_weaker_than_forward() -> void:
	var ship_state := ShipState.new()
	_fly(ship_state, _thrust(Vector3(1, 0, 0)), 300)
	assert_near(ship_state.velocity.x, 50.0, 1e-4, "axis_strength x = 0.5")


func test_diagonal_thrust_is_limited_to_unit_demand() -> void:
	var ship_state := ShipState.new()
	_fly(ship_state, _thrust(Vector3(1, 1, -1)), 400)
	var expected := Vector3(1, 1, -1).limit_length(1.0) * Vector3(0.5, 0.5, 1.0) * 100.0
	assert_near(ship_state.velocity.distance_to(expected), 0.0, 1e-3)


func test_thrust_follows_ship_orientation() -> void:
	var ship_state := ShipState.new()
	ship_state.basis = Basis(Vector3.UP, PI / 2.0) # yaw 90 degrees left: forward (-z) now points at -x
	_fly(ship_state, _thrust(Vector3(0, 0, -1)), 30)
	assert_near(ship_state.velocity.x, -30.0, 1e-3)
	assert_near(ship_state.velocity.z, 0.0, 1e-3)


func test_no_thrust_damps_to_rest_with_assist() -> void:
	var ship_state := ShipState.new()
	ship_state.velocity = Vector3(0, 0, -40)
	_fly(ship_state, PilotCommand.new(), 30)
	assert_near(ship_state.velocity.z, -40.0 + 80.0 * 0.5, 1e-4, "decel 80 for 0.5 s")
	_fly(ship_state, PilotCommand.new(), 60)
	assert_eq(ship_state.velocity, Vector3.ZERO)


func test_lock_linear_coasts_and_ignores_damping() -> void:
	var ship_state := ShipState.new()
	ship_state.velocity = Vector3(3, 0, -40)
	_fly(ship_state, PilotCommand.parked(0), 120)
	assert_eq(ship_state.velocity, Vector3(3, 0, -40))
	assert_near(ship_state.position.z, -80.0, 1e-3, "40 m/s for 2 s")


func test_brake_stops_faster_than_assist_damping() -> void:
	var braking_state := ShipState.new()
	braking_state.velocity = Vector3(0, 0, -40)
	var brake_command := PilotCommand.new()
	brake_command.brake = true
	_fly(braking_state, brake_command, 15)
	assert_near(braking_state.velocity.z, -40.0 + 160.0 * 0.25, 1e-4, "brake decel = 80 * 2")


func test_boost_raises_the_speed_cap() -> void:
	var ship_state := ShipState.new()
	var boost_command := _thrust(Vector3(0, 0, -1))
	boost_command.boost = true
	_fly(ship_state, boost_command, 300)
	assert_near(ship_state.speed(), 150.0, 1e-4)


func test_gear_changes_the_cap_and_is_clamped_to_available_gears() -> void:
	var ship_state := ShipState.new()
	var combat_command := _thrust(Vector3(0, 0, -1))
	combat_command.gear = PilotCommand.GEAR_COMBAT
	_fly(ship_state, combat_command, 600)
	assert_near(ship_state.speed(), 500.0, 1e-3)
	combat_command.gear = 99
	_fly(ship_state, combat_command, 1)
	assert_eq(ship_state.gear, 2, "99 clamps to the highest gear (cruise)")


func test_gravity_accelerates_a_coasting_ship() -> void:
	var ship_state := ShipState.new()
	var environment := FlightEnvironment.new()
	environment.gravity = Vector3(0, -10, 0)
	_fly(ship_state, PilotCommand.parked(0), 60, environment)
	assert_near(ship_state.velocity.y, -10.0, 1e-4)


func test_turn_rate_reaches_max_and_orientation_rotates_the_right_way() -> void:
	var ship_state := ShipState.new()
	var yaw_command := PilotCommand.new()
	yaw_command.turn = Vector3(0, 1, 0)
	_fly(ship_state, yaw_command, 120)
	assert_near(ship_state.angular_velocity.y, 1.5, 1e-6)
	var forward: Vector3 = -ship_state.basis.z
	assert_true(forward.x < 0.0, "positive yaw turns the nose to -x (left)")
	var pitch_state := ShipState.new()
	var pitch_command := PilotCommand.new()
	pitch_command.turn = Vector3(1, 0, 0)
	_fly(pitch_state, pitch_command, 30)
	assert_true((-pitch_state.basis.z).y > 0.0, "positive pitch raises the nose")


func test_turning_stops_when_demand_released() -> void:
	var ship_state := ShipState.new()
	ship_state.angular_velocity = Vector3(0, 1.5, 1.0)
	_fly(ship_state, PilotCommand.new(), 60)
	assert_eq(ship_state.angular_velocity, Vector3.ZERO)


func test_orientation_stays_orthonormal_over_a_long_mixed_turn() -> void:
	var ship_state := ShipState.new()
	var command := PilotCommand.new()
	command.turn = Vector3(0.7, -0.4, 1.0)
	_fly(ship_state, command, 6000)
	assert_true(ship_state.basis.is_equal_approx(ship_state.basis.orthonormalized()), "basis drifted")
	assert_near(ship_state.basis.determinant(), 1.0, 1e-5)
