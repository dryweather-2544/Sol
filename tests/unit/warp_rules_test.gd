extends "res://tests/test_case.gd"
## Warp gear follows Rodina's limnal drive rules (EGVehicle.lua:1437-1441, 1576-1653; EGDataShipPlayer.lua:45, 211-231)
## and never carries the ship into a body's air at warp speed.

const DELTA := 1.0 / 60.0


func _warp_command(thrust: Vector3 = Vector3.ZERO) -> PilotCommand:
	var command := PilotCommand.new()
	command.gear = PilotCommand.GEAR_WARP
	command.thrust = thrust
	return command


func _open_space(cruise_limit: float, clearance: float = INF) -> FlightEnvironment:
	var environment := FlightEnvironment.new()
	environment.max_gear = PilotCommand.GEAR_WARP
	environment.cruise_speed_limit = cruise_limit
	environment.warp_clearance = clearance
	return environment


func test_warp_drives_forward_by_itself_and_ignores_strafe() -> void:
	var state := ShipState.new()
	var tuning := ShipTuning.new()
	var environment := _open_space(5000.0)
	for tick in 60:
		FlightModel.step(state, _warp_command(Vector3(1, 1, 0)), tuning, environment, DELTA) # strafe and up, no forward
	var local := state.basis.transposed() * state.velocity
	assert_true(local.z < -100.0, "moves forward with no forward input: %s" % str(local))
	assert_near(local.x, 0.0, 1e-6, "no sideways (MoveStrengths 0)")
	assert_near(local.y, 0.0, 1e-6, "no vertical")


func test_warp_spins_up_for_1_8_seconds_before_its_speed_applies() -> void:
	var state := ShipState.new()
	var tuning := ShipTuning.new()
	var environment := _open_space(5000.0)
	var top_during_spin_up := 0.0
	for tick in 100: # 1.67 s
		FlightModel.step(state, _warp_command(), tuning, environment, DELTA)
		top_during_spin_up = maxf(top_during_spin_up, state.speed())
	assert_true(top_during_spin_up <= 5000.0 + 1e-3, "no faster than cruise before LimnalStartTime: %f" % top_during_spin_up)
	for tick in 600:
		FlightModel.step(state, _warp_command(), tuning, environment, DELTA)
	assert_near(state.speed(), 5000.0 * tuning.warp_speed_multiplier, 1.0, "full warp speed after spin-up")
	assert_true(state.limnal_timer > 1.8)


func test_leaving_warp_snaps_speed_to_the_cruise_limit() -> void:
	var state := ShipState.new()
	var tuning := ShipTuning.new()
	var environment := _open_space(5000.0)
	for tick in 600:
		FlightModel.step(state, _warp_command(), tuning, environment, DELTA)
	assert_true(state.speed() > 30000.0)
	environment.max_gear = PilotCommand.GEAR_CRUISE # e.g. crossing into a planet's sphere of influence
	FlightModel.step(state, _warp_command(), tuning, environment, DELTA)
	assert_eq(state.gear, PilotCommand.GEAR_CRUISE)
	assert_true(state.speed() <= 5000.0 + 1e-3, "CancelLimnalDrive: relative time snaps back (%f m/s)" % state.speed())
	assert_eq(state.limnal_timer, 0.0)


func test_warp_is_refused_when_it_would_reach_the_air_within_the_lookahead() -> void:
	var state := ShipState.new()
	var tuning := ShipTuning.new()
	var environment := _open_space(5000.0)
	for tick in 600:
		FlightModel.step(state, _warp_command(), tuning, environment, DELTA)
	var speed := state.speed()
	environment.warp_clearance = speed * FlightModel.WARP_LOOKAHEAD_SECONDS * 0.9
	FlightModel.step(state, _warp_command(), tuning, environment, DELTA)
	assert_eq(state.gear, PilotCommand.GEAR_CRUISE, "not viable: dropped to cruise")
	assert_true(state.speed() <= 5000.0 + 1e-3)


func test_approach_in_warp_never_enters_the_air_at_warp_speed() -> void:
	# Straight at a body from 1e9 m with the pilot holding WARP, under Sol's open-space rules (cruise limit
	# 0.3 x distance, clearance = distance). Before this fix the ship arrived at millions of m/s (DeepSeek review).
	var state := ShipState.new()
	var tuning := ShipTuning.new()
	var distance := 1.0e9
	var environment := _open_space(0.3 * distance, distance)
	var worst_warp_ratio := 0.0
	var cancel_distance := -1.0
	for tick in 60 * 900:
		environment.cruise_speed_limit = clampf(distance * 0.3, 500.0, 2.0e7)
		environment.warp_clearance = distance
		FlightModel.step(state, _warp_command(), tuning, environment, DELTA)
		if state.gear == PilotCommand.GEAR_WARP:
			worst_warp_ratio = maxf(worst_warp_ratio, state.speed() * FlightModel.WARP_LOOKAHEAD_SECONDS / distance)
		elif cancel_distance < 0.0:
			cancel_distance = distance
		distance -= state.speed() * DELTA
		if distance <= 1.0e5:
			break
	assert_true(cancel_distance > 0.0, "the drive was cancelled before the air")
	assert_true(worst_warp_ratio < 1.0, "while in warp the air is always more than half a second away: %f" % worst_warp_ratio)
	assert_true(state.warp_cancelled and state.gear == PilotCommand.GEAR_CRUISE, "and it stays cancelled while WARP is held")
	# Cruise itself trails its shrinking limit by ~0.3/2 (its excess decays at 2/s while the limit falls at 0.3/s).
	assert_true(state.speed() <= environment.cruise_speed_limit * 1.5, "near the air the ship is at cruise speed (%f m/s)" % state.speed())


func test_shifting_down_and_up_again_re_engages_a_cancelled_warp() -> void:
	var state := ShipState.new()
	var tuning := ShipTuning.new()
	var environment := _open_space(5000.0)
	for tick in 10:
		FlightModel.step(state, _warp_command(), tuning, environment, DELTA)
	assert_eq(state.gear, PilotCommand.GEAR_WARP)
	environment.warp_clearance = 1.0 # not viable: cancelled
	FlightModel.step(state, _warp_command(), tuning, environment, DELTA)
	environment.warp_clearance = INF
	FlightModel.step(state, _warp_command(), tuning, environment, DELTA)
	assert_eq(state.gear, PilotCommand.GEAR_CRUISE, "still cancelled while WARP stays selected")
	var cruise := PilotCommand.new()
	cruise.gear = PilotCommand.GEAR_CRUISE
	FlightModel.step(state, cruise, tuning, environment, DELTA)
	FlightModel.step(state, _warp_command(), tuning, environment, DELTA)
	assert_eq(state.gear, PilotCommand.GEAR_WARP, "re-engaged after shifting down and up")


func test_warp_has_rodina_rotation_friction_in_space() -> void:
	var tuning := ShipTuning.new()
	var environment := _open_space(5000.0)
	assert_near(FlightModel.rotation_friction(tuning, PilotCommand.GEAR_WARP, environment), 2.0, 1e-9)
	assert_near(FlightModel.rotation_friction(tuning, PilotCommand.GEAR_CRUISE, environment), 0.0, 1e-9)


func test_warp_works_from_orbit_above_the_air_but_not_toward_it() -> void:
	var planet := PlanetBody.new()
	planet.frame_id = &"planet"
	planet.warp_allowed = true
	var altitude := planet.atmosphere_height + 100000.0 # 100 km above the air
	var state := ShipState.new()
	state.position = WorldPos.new(&"planet", 0.0, 0.0, planet.radius + altitude)
	var environment := FlightEnvironment.new()
	state.velocity = Vector3(0, 0, 50000.0) # climbing straight away from the planet
	planet.fill_environment(state, environment)
	assert_eq(environment.max_gear, PilotCommand.GEAR_WARP, "above the air with the drive: warp allowed (Rodina: anywhere outside the atmosphere)")
	assert_eq(environment.warp_clearance, INF, "flying away, the path misses the air")
	state.velocity = Vector3(0, 0, -50000.0) # diving at the planet
	planet.fill_environment(state, environment)
	assert_near(environment.warp_clearance, 100000.0, 1.0, "the path reaches the air's top 100 km ahead")
	state.position = WorldPos.new(&"planet", 0.0, 0.0, planet.radius + planet.atmosphere_height * 0.5)
	planet.fill_environment(state, environment)
	assert_eq(environment.max_gear, PilotCommand.GEAR_CRUISE, "inside the air: no warp")
	planet.warp_allowed = false
	state.position = WorldPos.new(&"planet", 0.0, 0.0, planet.radius + altitude)
	planet.fill_environment(state, environment)
	assert_eq(environment.max_gear, PilotCommand.GEAR_CRUISE, "no drive installed: no warp")


func test_ray_to_sphere() -> void:
	assert_near(FlightEnvironment.ray_to_sphere(0, 0, 10, Vector3(0, 0, -1), 0, 0, 0, 2), 8.0, 1e-9)
	assert_eq(FlightEnvironment.ray_to_sphere(0, 0, 10, Vector3(0, 0, 1), 0, 0, 0, 2), INF, "pointing away")
	assert_eq(FlightEnvironment.ray_to_sphere(0, 5, 10, Vector3(0, 0, -1), 0, 0, 0, 2), INF, "passes beside")
	assert_eq(FlightEnvironment.ray_to_sphere(0, 0, 1, Vector3(0, 0, 1), 0, 0, 0, 2), 0.0, "inside")
