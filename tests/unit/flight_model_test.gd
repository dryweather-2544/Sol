extends "res://tests/test_case.gd"
## Flight maths with hand-computed expectations (ShipTuning; docs/RODINA_PHYSICS_AUDIT.md).
## Combat (gear 1), Rodina's numbers: MoveSpeed 500, Acceleration 2.0 (1000 m/s^2), Deceleration 0.75, DragSpeed 1500,
## strengths lateral 0.3 / vertical 0.3 / reverse 0.6, hardness 0.7. Precision (gear 0, Sol's scaled dock gear):
## MoveSpeed 30, Acceleration 0.66 (19.8 m/s^2), Deceleration 0.9, DragSpeed 450, lateral 0.3 / vertical 0.4 /
## reverse 0.3, station keeping (stops and hovers, engines hold up to 60 m/s^2 of gravity), hardness 0.35.
## RotationSpeed 2.5 rad/s, roll cap 5; player pitch/yaw push x 1.25 (ShipLookSpeed).

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


# --- Linear (Rodina rules, combat gear) ----------------------------------------------------------------------------

func test_forward_thrust_accelerates_at_acceleration_times_move_speed() -> void:
	var combat := ShipState.new()
	_fly(combat, _thrust(Vector3(0, 0, -1), PilotCommand.GEAR_COMBAT), 15)
	assert_near(combat.velocity.z, -250.0, 1e-3, "combat: 2 x 500 = 1000 m/s^2 for 0.25 s")
	assert_near(combat.velocity.x, 0.0, 1e-6)
	# semi-implicit Euler: position = accel * dt^2 * N(N+1)/2
	assert_near(combat.position.z, -1000.0 * DELTA * DELTA * 15.0 * 16.0 / 2.0, 1e-3)
	var precision := ShipState.new()
	_fly(precision, _thrust(Vector3(0, 0, -1)), 30)
	assert_near(precision.velocity.z, -9.9, 1e-3, "precision: 0.66 x 30 = 19.8 m/s^2 for 0.5 s")


func test_speed_is_driven_to_the_gear_move_speed() -> void:
	var combat := ShipState.new()
	_fly(combat, _thrust(Vector3(0, 0, -1), PilotCommand.GEAR_COMBAT), 600)
	assert_near(combat.speed(), 500.0, 1e-4)
	var precision := ShipState.new()
	_fly(precision, _thrust(Vector3(0, 0, -1)), 300)
	assert_near(precision.speed(), 30.0, 1e-4)


func test_sideways_vertical_and_reverse_are_weaker_per_gear() -> void:
	var cases := [
		[Vector3(1, 0, 0), PilotCommand.GEAR_DOCK, Vector3(9, 0, 0), "precision sideways 0.3"],
		[Vector3(0, 1, 0), PilotCommand.GEAR_DOCK, Vector3(0, 12, 0), "precision vertical 0.4 (under the 15 m/s touchdown limit)"],
		[Vector3(0, 0, 1), PilotCommand.GEAR_DOCK, Vector3(0, 0, 9), "precision reverse 0.3"],
		[Vector3(1, 0, 0), PilotCommand.GEAR_COMBAT, Vector3(150, 0, 0), "combat sideways 0.3"],
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
	_fly(ship_state, _thrust(Vector3(1, 1, -1), PilotCommand.GEAR_COMBAT), 600)
	var expected := Vector3(1, 1, -1).limit_length(1.0) * Vector3(0.3, 0.3, 1.0) * 500.0
	assert_near(ship_state.velocity.distance_to(expected), 0.0, 1e-3)


func test_thrust_follows_ship_orientation() -> void:
	var ship_state := ShipState.new()
	ship_state.basis = Basis(Vector3.UP, PI / 2.0) # yaw 90 degrees left: forward (-z) now points at -x
	_fly(ship_state, _thrust(Vector3(0, 0, -1), PilotCommand.GEAR_COMBAT), 15)
	assert_near(ship_state.velocity.x, -250.0, 1e-3)
	assert_near(ship_state.velocity.z, 0.0, 1e-3)


func test_no_thrust_keeps_momentum() -> void:
	var ship_state := ShipState.new()
	ship_state.velocity = Vector3(5, -2, -40)
	_fly(ship_state, _thrust(Vector3.ZERO, PilotCommand.GEAR_COMBAT), 90)
	assert_eq(ship_state.velocity, Vector3(5, -2, -40), "no input applies nothing: the ship coasts")


func test_drag_only_above_drag_speed() -> void:
	var ship_state := ShipState.new()
	ship_state.velocity = Vector3(0, 0, -2000.0) # over combat's 1500 m/s
	_fly(ship_state, _thrust(Vector3.ZERO, PilotCommand.GEAR_COMBAT), 60)
	# Each tick over 1500 m/s keeps (1 - 0.75 / 60) of the velocity; 23 ticks bring it under, then it coasts.
	var expected := 2000.0 * pow(1.0 - 0.75 / 60.0, 23)
	assert_near(ship_state.speed(), expected, 1e-2, "drag down to just under DragSpeed, then momentum is kept")
	var fast := ShipState.new()
	fast.velocity = Vector3(0, 0, -1000.0)
	_fly(fast, _thrust(Vector3.ZERO, PilotCommand.GEAR_COMBAT), 60)
	assert_near(fast.speed(), 1000.0, 1e-4, "1000 m/s in combat is over MoveSpeed but under DragSpeed: no drag")


func test_reverse_input_over_move_speed_brakes_in_proportion_to_speed() -> void:
	var ship_state := ShipState.new()
	ship_state.velocity = Vector3(0, 0, -1000.0)
	_fly(ship_state, _thrust(Vector3(0, 0, 1), PilotCommand.GEAR_COMBAT), 1)
	# Braking over MoveSpeed: max(Acceleration, Deceleration) x speed = 2 x 1000 m/s^2, no strength scaling.
	assert_near(ship_state.velocity.z, -1000.0 + 2000.0 * DELTA, 1e-3)


func test_brake_drives_velocity_to_zero_at_the_reverse_thrust_rate() -> void:
	var braking_state := ShipState.new()
	braking_state.velocity = Vector3(0, 0, -400)
	var brake_command := _thrust(Vector3.ZERO, PilotCommand.GEAR_COMBAT)
	brake_command.brake = true
	_fly(braking_state, brake_command, 15)
	assert_near(braking_state.velocity.z, -400.0 + 1000.0 * 0.25, 1e-3, "combat: 1000 m/s^2 toward zero")
	_fly(braking_state, brake_command, 60)
	assert_eq(braking_state.velocity, Vector3.ZERO, "and stops without reversing")


func test_lock_linear_coasts_and_ignores_thrust() -> void:
	var ship_state := ShipState.new()
	ship_state.velocity = Vector3(3, 0, -40)
	_fly(ship_state, PilotCommand.parked(0), 120)
	assert_eq(ship_state.velocity, Vector3(3, 0, -40), "parked: no station keeping either")
	assert_near(ship_state.position.z, -80.0, 1e-3, "40 m/s for 2 s")
	var clutch := _thrust(Vector3(0, 0, -1), PilotCommand.GEAR_COMBAT)
	clutch.lock_linear = true
	_fly(ship_state, clutch, 60)
	assert_eq(ship_state.velocity, Vector3(3, 0, -40), "clutch: thrust does nothing")


func test_move_lock_matches_the_target_velocity_exactly() -> void:
	var ship_state := ShipState.new()
	var command := _thrust(Vector3(0, 0, -1), PilotCommand.GEAR_COMBAT)
	command.move_lock = 1.0
	_fly(ship_state, command, 1)
	assert_near(ship_state.velocity.z, -500.0, 1e-4)
	command.thrust = Vector3.ZERO
	_fly(ship_state, command, 1)
	assert_eq(ship_state.velocity, Vector3.ZERO, "and holds zero when asked for nothing")


func test_boost_raises_the_move_speed() -> void:
	var combat := ShipState.new()
	var boost_command := _thrust(Vector3(0, 0, -1), PilotCommand.GEAR_COMBAT)
	boost_command.boost = true
	_fly(combat, boost_command, 600)
	assert_near(combat.speed(), 750.0, 1e-3)
	var precision := ShipState.new()
	boost_command.gear = PilotCommand.GEAR_DOCK
	_fly(precision, boost_command, 600)
	assert_near(precision.speed(), 45.0, 1e-3)


func test_gravity_pulls_a_coasting_or_hands_off_ship() -> void:
	var environment := FlightEnvironment.new()
	environment.gravity = Vector3(0, -10, 0)
	var parked := ShipState.new()
	_fly(parked, PilotCommand.parked(0), 60, environment)
	assert_near(parked.velocity.y, -10.0, 1e-4)
	var hands_off := ShipState.new()
	_fly(hands_off, _thrust(Vector3.ZERO, PilotCommand.GEAR_COMBAT), 60, environment)
	assert_near(hands_off.velocity.y, -10.0, 1e-4, "combat: no input does not hold the ship up")


# --- Gears: selection, switching -------------------------------------------------------------------------------------

func test_gear_selection_is_clamped_to_what_is_allowed_and_comes_back() -> void:
	var ship_state := ShipState.new()
	var environment := FlightEnvironment.new()
	var cruise := _thrust(Vector3.ZERO, PilotCommand.GEAR_CRUISE)
	environment.max_gear = PilotCommand.GEAR_COMBAT # e.g. an empty tank
	_fly(ship_state, cruise, 1, environment)
	assert_eq(ship_state.gear, PilotCommand.GEAR_COMBAT, "only combat allowed")
	assert_eq(ship_state.selected_gear, PilotCommand.GEAR_CRUISE, "the choice is kept")
	assert_eq(PilotController.new().poll_command(ship_state, DELTA).gear, PilotCommand.GEAR_CRUISE, "an unpiloted ship keeps the choice")
	environment.max_gear = 99
	_fly(ship_state, PilotController.new().poll_command(ship_state, DELTA), 1, environment)
	assert_eq(ship_state.gear, PilotCommand.GEAR_CRUISE, "cruise again once allowed, without a new shift")
	cruise.gear = 99
	_fly(ship_state, cruise, 1)
	assert_eq(ship_state.gear, 3, "99 clamps to the highest gear (warp)")


func test_shifting_down_at_speed_changes_velocity_smoothly() -> void:
	var ship_state := ShipState.new()
	ship_state.gear = PilotCommand.GEAR_CRUISE
	ship_state.velocity = Vector3(0, 0, -5000.0)
	var worst := 0.0
	for gear in [PilotCommand.GEAR_COMBAT, PilotCommand.GEAR_DOCK]:
		for tick in 60:
			var before := ship_state.velocity
			_fly(ship_state, _thrust(Vector3.ZERO, gear), 1)
			worst = maxf(worst, (ship_state.velocity - before).length())
	# Every change is in proportion to the speed, never a jump to the new gear's speed. Combat's drag at 5000 m/s takes
	# 0.75 / 60 of it (62.5 m/s); a second later precision's drag plus its hands-off brake take 2 x 0.9 / 60 of what is
	# left after 60 combat ticks (5000 x (1 - 0.75/60)^60 = 2351 m/s, so 70.5 m/s).
	var after_combat := 5000.0 * pow(1.0 - 0.75 / 60.0, 60)
	assert_near(worst, maxf(62.5, 2.0 * 0.9 / 60.0 * after_combat), 0.05, "worst one-tick change")
	assert_true(ship_state.speed() > 30.0, "still faster than precision's speed after 2 s: speed is shed, not snapped")


# --- Precision gear (Sol): station keeping ---------------------------------------------------------------------------

func test_precision_tap_moves_a_little_and_stops_by_itself() -> void:
	var ship_state := ShipState.new()
	_fly(ship_state, _thrust(Vector3(0, 0, -1)), 15)
	assert_near(ship_state.velocity.z, -4.95, 1e-3, "a quarter-second tap: 19.8 m/s^2 x 0.25 s")
	_fly(ship_state, _thrust(Vector3.ZERO), 15)
	assert_true(ship_state.velocity.length() < 1e-4, "let go: stopped a quarter-second later (%s)" % ship_state.velocity)
	assert_true(absf(ship_state.position.z) < 1.3, "about a metre travelled in all: %f" % ship_state.position.z)


func test_precision_hovers_against_gravity_up_to_the_engines_limit() -> void:
	var environment := FlightEnvironment.new()
	environment.gravity = Vector3(0, -42, 0) # Aurelia's ship gravity
	var hovering := ShipState.new()
	_fly(hovering, _thrust(Vector3.ZERO), 300, environment)
	assert_eq(hovering.velocity, Vector3.ZERO, "hands off: hovers")
	var heavy := FlightEnvironment.new()
	heavy.gravity = Vector3(0, -100, 0) # more than the 60 m/s^2 the engines can hold
	var sinking := ShipState.new()
	_fly(sinking, _thrust(Vector3.ZERO), 60, heavy)
	assert_near(sinking.velocity.y, -(40.0 - 19.8) * (59.0 / 60.0) - 40.0 / 60.0, 0.5, "the excess 40 m/s^2 less the 19.8 m/s^2 brake")


func test_precision_hands_off_at_speed_brakes_in_proportion() -> void:
	var ship_state := ShipState.new()
	ship_state.velocity = Vector3(0, 0, -100.0)
	_fly(ship_state, _thrust(Vector3.ZERO), 1)
	assert_near(ship_state.velocity.z, -100.0 + 0.9 * 100.0 * DELTA, 1e-3, "over MoveSpeed: Deceleration 0.9 x speed")
	_fly(ship_state, _thrust(Vector3.ZERO), 600)
	assert_eq(ship_state.velocity, Vector3.ZERO)


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


func test_warp_gear_has_a_higher_cap_than_cruise() -> void:
	var cruise := ShipState.new()
	var warp := ShipState.new()
	var cruise_command := PilotCommand.new()
	cruise_command.gear = PilotCommand.GEAR_CRUISE
	cruise_command.thrust = Vector3(0, 0, -1)
	var warp_command := PilotCommand.new()
	warp_command.gear = PilotCommand.GEAR_WARP
	warp_command.thrust = Vector3(0, 0, -1)
	var environment := FlightEnvironment.new()
	environment.cruise_speed_limit = 5000.0
	var tuning := ShipTuning.new()
	for tick in 600:
		FlightModel.step(cruise, cruise_command, tuning, environment, 1.0 / 60.0)
		FlightModel.step(warp, warp_command, tuning, environment, 1.0 / 60.0)
	assert_near(cruise.speed(), 5000.0, 1e-3)
	assert_near(warp.speed(), 5000.0 * tuning.warp_speed_multiplier, 1e-3)


func test_control_authority_ramps_after_a_collision() -> void:
	var ship_state := ShipState.new()
	ship_state.control_timer = 0.0
	var command := _thrust(Vector3(0, 0, -1), PilotCommand.GEAR_COMBAT)
	_fly(ship_state, command, 1)
	assert_true(ship_state.control_authority < 0.01, "no drive authority immediately after contact")
	assert_near(ship_state.velocity.length(), 0.0, 1e-6, "the engine does not accelerate while control is low")
	_fly(ship_state, command, 60)
	assert_true(ship_state.control_authority > 0.99, "authority returns within Rodina's 0.5-1.5 s window")
	assert_true(ship_state.velocity.length() > 100.0, "the ship accelerates once control returns")


func test_warp_steering_drift_only_after_full_spin_up() -> void:
	var state := ShipState.new()
	state.gear = PilotCommand.GEAR_WARP
	state.selected_gear = PilotCommand.GEAR_WARP
	state.limnal_timer = 2.0
	var environment := FlightEnvironment.new()
	environment.max_gear = PilotCommand.GEAR_WARP
	var command := PilotCommand.new()
	command.gear = PilotCommand.GEAR_WARP
	FlightModel.step(state, command, ShipTuning.new(), environment, DELTA)
	assert_true(state.limnal_drift.length() > 0.0, "drift accumulates after LimnalActivation reaches 1")
	assert_true(state.angular_velocity.length() > 0.0, "drift is applied to the pilot's rotation")
	state.limnal_timer = 0.2
	state.limnal_drift = Vector2.ZERO
	state.angular_velocity = Vector3.ZERO
	FlightModel.step(state, command, ShipTuning.new(), environment, DELTA)
	assert_eq(state.limnal_drift, Vector2.ZERO, "no drift during the 1.8 s warm-up")
