extends "res://tests/test_case.gd"
## Flight maths with hand-computed expectations from the Rodina rules (ShipTuning; docs/RODINA_PHYSICS_AUDIT.md).
## Dock (gear 0): MoveSpeed 100, Acceleration 0.66 (66 m/s^2), Deceleration 0.9, DragSpeed 1500, strengths
## lateral 0.3 / vertical 1.0 / reverse 0.3, hardness 0.35. Combat (gear 1): 500, 2.0 (1000 m/s^2), 0.75, 1500,
## 0.3 / 0.3 / 0.6, hardness 0.7. RotationSpeed 2.5 rad/s, roll cap 5; player pitch/yaw push x 1.25 (ShipLookSpeed).

const DELTA := 1.0 / 60.0


func _fly(ship_state: ShipState, command: PilotCommand, ticks: int, environment: FlightEnvironment = null) -> void:
	var tuning := ShipTuning.new()
	var flight_environment := environment if environment != null else FlightEnvironment.new()
	for tick in ticks:
		FlightModel.step(ship_state, command, tuning, flight_environment, DELTA)


func _thrust(thrust_vector: Vector3, gear := PilotCommand.GEAR_DOCK) -> PilotCommand:
	var command := PilotCommand.new()
	command.thrust = thrust_vector
	command.gear = gear
	return command


func _turn(turn_vector: Vector3, gear := PilotCommand.GEAR_COMBAT) -> PilotCommand:
	var command := PilotCommand.new()
	command.turn = turn_vector
	command.gear = gear
	return command


## Air like Aurelia's, low down: friction 1 and the ship counted as inside the atmosphere.
func _air(ratio := 0.2) -> FlightEnvironment:
	var environment := FlightEnvironment.new()
	environment.atmosphere_ratio = ratio
	environment.atmosphere_friction = 1.0
	environment.surface_gravity_g = 12.0 / 9.8
	return environment


func _pitch_and_roll(ship_state: ShipState, up := Vector3.UP) -> Vector2:
	return Vector2(asin(clampf(-ship_state.basis.z.dot(up), -1.0, 1.0)), atan2(ship_state.basis.x.dot(up), ship_state.basis.y.dot(up)))


# --- Linear ---------------------------------------------------------------------------------------------------------

func test_forward_thrust_accelerates_at_acceleration_times_move_speed() -> void:
	var ship_state := ShipState.new()
	_fly(ship_state, _thrust(Vector3(0, 0, -1)), 30)
	assert_near(ship_state.velocity.z, -33.0, 1e-3, "0.66 x 100 = 66 m/s^2 for 0.5 s")
	assert_near(ship_state.velocity.x, 0.0, 1e-6)
	# semi-implicit Euler: position = accel * dt^2 * N(N+1)/2
	assert_near(ship_state.position.z, -66.0 * DELTA * DELTA * 30.0 * 31.0 / 2.0, 1e-3)
	var combat := ShipState.new()
	_fly(combat, _thrust(Vector3(0, 0, -1), PilotCommand.GEAR_COMBAT), 15)
	assert_near(combat.velocity.z, -250.0, 1e-3, "combat: 2 x 500 = 1000 m/s^2 for 0.25 s")


func test_speed_is_driven_to_the_gear_move_speed() -> void:
	var ship_state := ShipState.new()
	_fly(ship_state, _thrust(Vector3(0, 0, -1)), 300)
	assert_near(ship_state.speed(), 100.0, 1e-4)


func test_sideways_vertical_and_reverse_are_weaker_per_gear() -> void:
	var cases := [
		[Vector3(1, 0, 0), PilotCommand.GEAR_DOCK, Vector3(30, 0, 0), "dock sideways 0.3"],
		[Vector3(0, 1, 0), PilotCommand.GEAR_DOCK, Vector3(0, 100, 0), "dock vertical 1.0 (landing gear)"],
		[Vector3(0, 0, 1), PilotCommand.GEAR_DOCK, Vector3(0, 0, 30), "dock reverse 0.3"],
		[Vector3(0, 1, 0), PilotCommand.GEAR_COMBAT, Vector3(0, 150, 0), "combat vertical 0.3"],
		[Vector3(0, 0, 1), PilotCommand.GEAR_COMBAT, Vector3(0, 0, 300), "combat reverse 0.6"],
		[Vector3(0, 0, -1), PilotCommand.GEAR_COMBAT, Vector3(0, 0, -500), "forward is always full"],
	]
	for case in cases:
		var ship_state := ShipState.new()
		_fly(ship_state, _thrust(case[0], case[1]), 600)
		assert_near(ship_state.velocity.distance_to(case[2]), 0.0, 1e-3, case[3])


func test_diagonal_thrust_is_limited_to_unit_demand_then_scaled_per_axis() -> void:
	var ship_state := ShipState.new()
	_fly(ship_state, _thrust(Vector3(1, 1, -1)), 600)
	var expected := Vector3(1, 1, -1).limit_length(1.0) * Vector3(0.3, 1.0, 1.0) * 100.0
	assert_near(ship_state.velocity.distance_to(expected), 0.0, 1e-3)


func test_thrust_follows_ship_orientation() -> void:
	var ship_state := ShipState.new()
	ship_state.basis = Basis(Vector3.UP, PI / 2.0) # yaw 90 degrees left: forward (-z) now points at -x
	_fly(ship_state, _thrust(Vector3(0, 0, -1)), 30)
	assert_near(ship_state.velocity.x, -33.0, 1e-3)
	assert_near(ship_state.velocity.z, 0.0, 1e-3)


func test_no_thrust_keeps_momentum() -> void:
	var ship_state := ShipState.new()
	ship_state.velocity = Vector3(5, -2, -40)
	_fly(ship_state, PilotCommand.new(), 90)
	assert_eq(ship_state.velocity, Vector3(5, -2, -40), "no input applies nothing: the ship coasts")


func test_drag_only_above_drag_speed() -> void:
	var ship_state := ShipState.new()
	ship_state.velocity = Vector3(0, 0, -2000.0) # over combat's 1500 m/s
	_fly(ship_state, _thrust(Vector3.ZERO, PilotCommand.GEAR_COMBAT), 60)
	# Each tick over 1500 m/s keeps (1 - 2 x 0.75 / 60) of the velocity; 12 ticks bring it under, then it coasts.
	var expected := 2000.0 * pow(1.0 - 1.5 / 60.0, 12)
	assert_near(ship_state.speed(), expected, 1e-2, "drag down to just under DragSpeed, then momentum is kept")
	var slow := ShipState.new()
	slow.velocity = Vector3(0, 0, -300.0)
	_fly(slow, _thrust(Vector3.ZERO, PilotCommand.GEAR_DOCK), 60)
	assert_near(slow.speed(), 300.0, 1e-4, "300 m/s in dock gear is over MoveSpeed but under DragSpeed: no drag")


func test_reverse_input_over_move_speed_brakes_in_proportion_to_speed() -> void:
	var ship_state := ShipState.new()
	ship_state.velocity = Vector3(0, 0, -1000.0)
	_fly(ship_state, _thrust(Vector3(0, 0, 1), PilotCommand.GEAR_COMBAT), 1)
	# Braking over MoveSpeed: max(Acceleration, Deceleration) x speed = 2 x 1000 m/s^2, no strength scaling.
	assert_near(ship_state.velocity.z, -1000.0 + 2000.0 * DELTA, 1e-3)


func test_brake_drives_velocity_to_zero_at_the_reverse_thrust_rate() -> void:
	var braking_state := ShipState.new()
	braking_state.velocity = Vector3(0, 0, -40)
	var brake_command := PilotCommand.new()
	brake_command.brake = true
	_fly(braking_state, brake_command, 15)
	assert_near(braking_state.velocity.z, -40.0 + 66.0 * 0.25, 1e-3, "dock: 66 m/s^2 toward zero")
	_fly(braking_state, brake_command, 60)
	assert_eq(braking_state.velocity, Vector3.ZERO, "and stops without reversing")


func test_lock_linear_coasts_and_ignores_thrust() -> void:
	var ship_state := ShipState.new()
	ship_state.velocity = Vector3(3, 0, -40)
	_fly(ship_state, PilotCommand.parked(0), 120)
	assert_eq(ship_state.velocity, Vector3(3, 0, -40))
	assert_near(ship_state.position.z, -80.0, 1e-3, "40 m/s for 2 s")
	var clutch := _thrust(Vector3(0, 0, -1))
	clutch.lock_linear = true
	_fly(ship_state, clutch, 60)
	assert_eq(ship_state.velocity, Vector3(3, 0, -40), "clutch: thrust does nothing")


func test_move_lock_matches_the_target_velocity_exactly() -> void:
	var ship_state := ShipState.new()
	var command := _thrust(Vector3(0, 0, -1))
	command.move_lock = 1.0
	_fly(ship_state, command, 1)
	assert_near(ship_state.velocity.z, -100.0, 1e-4)
	command.thrust = Vector3.ZERO
	_fly(ship_state, command, 1)
	assert_eq(ship_state.velocity, Vector3.ZERO, "and holds zero when asked for nothing")


func test_boost_raises_the_move_speed() -> void:
	var ship_state := ShipState.new()
	var boost_command := _thrust(Vector3(0, 0, -1))
	boost_command.boost = true
	_fly(ship_state, boost_command, 300)
	assert_near(ship_state.speed(), 150.0, 1e-4)


func test_gear_changes_the_move_speed_and_is_clamped_to_available_gears() -> void:
	var ship_state := ShipState.new()
	var combat_command := _thrust(Vector3(0, 0, -1), PilotCommand.GEAR_COMBAT)
	_fly(ship_state, combat_command, 600)
	assert_near(ship_state.speed(), 500.0, 1e-3)
	combat_command.gear = 99
	_fly(ship_state, combat_command, 1)
	assert_eq(ship_state.gear, 2, "99 clamps to the highest gear (cruise)")


func test_gravity_accelerates_a_coasting_ship_and_a_hands_off_one() -> void:
	var environment := FlightEnvironment.new()
	environment.gravity = Vector3(0, -10, 0)
	var parked := ShipState.new()
	_fly(parked, PilotCommand.parked(0), 60, environment)
	assert_near(parked.velocity.y, -10.0, 1e-4)
	var hands_off := ShipState.new()
	_fly(hands_off, PilotCommand.new(), 60, environment)
	assert_near(hands_off.velocity.y, -10.0, 1e-4, "no input does not hold the ship up")


# --- Rotation -------------------------------------------------------------------------------------------------------

func test_turn_input_accelerates_the_spin_up_to_the_rotation_speed() -> void:
	var ship_state := ShipState.new()
	_fly(ship_state, _turn(Vector3(0, 1, 0)), 30)
	assert_near(ship_state.angular_velocity.y, 1.25 * 0.7 * 2.5 * 0.5, 1e-4, "2.1875 rad/s^2 for 0.5 s")
	var forward: Vector3 = -ship_state.basis.z
	assert_true(forward.x < 0.0, "positive yaw turns the nose to -x (left)")
	_fly(ship_state, _turn(Vector3(0, 1, 0)), 90)
	assert_near(ship_state.angular_velocity.y, 2.5, 1e-6, "capped at RotationSpeed")
	var pitch_state := ShipState.new()
	_fly(pitch_state, _turn(Vector3(1, 0, 0)), 30)
	assert_true((-pitch_state.basis.z).y > 0.0, "positive pitch raises the nose")
	var both := ShipState.new()
	_fly(both, _turn(Vector3(1, 1, 0).normalized()), 300)
	assert_near(Vector2(both.angular_velocity.x, both.angular_velocity.y).length(), 2.5, 1e-4, "the cap is on pitch and yaw together")


func test_small_input_is_squared_for_precision() -> void:
	var ship_state := ShipState.new()
	_fly(ship_state, _turn(Vector3(0, 0.5, 0)), 30)
	assert_near(ship_state.angular_velocity.y, 0.25 * 1.25 * 0.7 * 2.5 * 0.5, 1e-4, "half input pushes a quarter as hard")


func test_spin_continues_in_space_after_release() -> void:
	var ship_state := ShipState.new()
	ship_state.angular_velocity = Vector3(0.3, 1.5, 1.0)
	_fly(ship_state, _turn(Vector3.ZERO), 120)
	assert_near(ship_state.angular_velocity.distance_to(Vector3(0.3, 1.5, 1.0)), 0.0, 1e-6, "no rotation friction in space")


func test_air_friction_slows_a_coasting_spin_but_not_a_driven_one() -> void:
	var coasting := ShipState.new()
	coasting.angular_velocity = Vector3(0, 1.5, 0)
	_fly(coasting, _turn(Vector3.ZERO), 60, _air())
	assert_near(coasting.angular_velocity.y, 1.5 * pow(1.0 - 1.0 / 60.0, 60), 1e-4, "friction 1/s deep in the air")
	var high := ShipState.new()
	high.angular_velocity = Vector3(0, 1.5, 0)
	_fly(high, _turn(Vector3.ZERO, PilotCommand.GEAR_DOCK), 60, _air(0.75))
	assert_near(high.angular_velocity.y, 1.5 * pow(1.0 - 0.5 / 60.0, 60), 1e-4, "half way between ratio 0.5 and 1: friction 0.5/s")
	var driven := ShipState.new()
	driven.angular_velocity = Vector3(0, 2.5, 0)
	_fly(driven, _turn(Vector3(0, 1, 0)), 60, _air())
	assert_near(driven.angular_velocity.y, 2.5, 1e-6, "no friction at full input")


func test_roll_input_is_smoothed_in_and_capped_at_twice_the_rotation_speed() -> void:
	var ship_state := ShipState.new()
	_fly(ship_state, _turn(Vector3(0, 0, 1)), 1)
	assert_near(ship_state.angular_velocity.z, 0.7 * (1.0 / 60.0) * 3.0 * 2.5 * DELTA, 1e-7, "first tick: smoothing factor 1/60")
	_fly(ship_state, _turn(Vector3(0, 0, 1)), 600)
	assert_near(ship_state.angular_velocity.z, 5.0, 1e-6)


func test_ai_facing_sets_the_turn_rate_directly() -> void:
	var ship_state := ShipState.new()
	var command := PilotCommand.new()
	command.gear = PilotCommand.GEAR_COMBAT
	command.face_direction = Vector3(-1, 0, 0) # 90 degrees to the left
	_fly(ship_state, command, 1)
	assert_near(ship_state.angular_velocity.y, 2.5, 1e-6, "full rate from the first tick (no inertia on the AI path)")
	_fly(ship_state, command, 240)
	assert_true((-ship_state.basis.z).dot(Vector3(-1, 0, 0)) > 0.999, "and it settles on the target")


func test_parked_ship_stops_rotating() -> void:
	var ship_state := ShipState.new()
	ship_state.angular_velocity = Vector3(0.2, 1.0, 0.5)
	_fly(ship_state, PilotCommand.parked(0), 120)
	assert_eq(ship_state.angular_velocity, Vector3.ZERO)


func test_orientation_stays_orthonormal_over_a_long_mixed_turn() -> void:
	var ship_state := ShipState.new()
	var command := PilotCommand.new()
	command.turn = Vector3(0.7, -0.4, 1.0)
	_fly(ship_state, command, 6000)
	assert_true(ship_state.basis.is_equal_approx(ship_state.basis.orthonormalized()), "basis drifted")
	assert_near(ship_state.basis.determinant(), 1.0, 1e-5)


# --- Roll levelling (never pitch) ----------------------------------------------------------------------------------

func test_levelling_never_changes_pitch() -> void:
	var ship_state := ShipState.new()
	ship_state.basis = Basis(Vector3(1, 0, 0), 0.5) # nose 0.5 rad up
	_fly(ship_state, _turn(Vector3.ZERO), 300, _air(0.001)) # just above the ground
	assert_near(_pitch_and_roll(ship_state).x, 0.5, 1e-5, "nose still 0.5 rad up after 5 s: no altitude levelling")
	assert_near(ship_state.angular_velocity.x, 0.0, 1e-9)


func test_levelling_eases_the_roll_level_in_the_atmosphere() -> void:
	var ship_state := ShipState.new()
	ship_state.basis = Basis(Vector3(0, 0, 1), 0.6) # right wing up 0.6 rad
	_fly(ship_state, _turn(Vector3.ZERO), 180, _air())
	assert_true(absf(_pitch_and_roll(ship_state).y) < 0.06, "roll eased toward level: %f" % _pitch_and_roll(ship_state).y)
	var mirrored := ShipState.new()
	mirrored.basis = Basis(Vector3(0, 0, 1), -0.6)
	_fly(mirrored, _turn(Vector3.ZERO), 180, _air())
	assert_true(absf(_pitch_and_roll(mirrored).y) < 0.06, "from the other side too: %f" % _pitch_and_roll(mirrored).y)


func test_levelling_is_off_in_space_when_the_setting_is_zero_and_while_the_pilot_rolls() -> void:
	var in_space := ShipState.new()
	in_space.basis = Basis(Vector3(0, 0, 1), 0.6)
	_fly(in_space, _turn(Vector3.ZERO), 180, _air(2.0))
	assert_near(_pitch_and_roll(in_space).y, 0.6, 1e-6, "above the air: no levelling")
	var switched_off := ShipState.new()
	switched_off.basis = Basis(Vector3(0, 0, 1), 0.6)
	var environment := _air()
	environment.horizon_levelling = 0.0
	_fly(switched_off, _turn(Vector3.ZERO), 180, environment)
	assert_near(_pitch_and_roll(switched_off).y, 0.6, 1e-6, "setting 0: no levelling")
	var rolling := ShipState.new()
	_fly(rolling, _turn(Vector3(0, 0, 1)), 30, _air())
	var rate_with_levelling_blocked := rolling.angular_velocity.z
	var free := ShipState.new()
	_fly(free, _turn(Vector3(0, 0, 1)), 30)
	assert_near(rate_with_levelling_blocked, free.angular_velocity.z, 1e-3, "rolling by hand is not fought by the levelling (friction aside: full input)")


func test_levelling_fades_out_as_the_nose_points_steeply() -> void:
	var ship_state := ShipState.new()
	ship_state.basis = Basis(Vector3(1, 0, 0), 1.25) * Basis(Vector3(0, 0, 1), 0.6) # nose 1.25 rad up, rolled
	var roll_before := _pitch_and_roll(ship_state).y
	_fly(ship_state, _turn(Vector3.ZERO), 60, _air(0.25))
	assert_near(_pitch_and_roll(ship_state).y, roll_before, 1e-4, "beyond the 1.2 rad pitch limit deep in the air: no levelling")
