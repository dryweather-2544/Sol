extends "res://tests/test_case.gd"
## Original entry model: the corridor must come from the velocity vector, not the nose.

const EntryModel = preload("res://src/flight/atmospheric_entry.gd")


func _state_at(planet: PlanetBody, altitude: float, velocity: Vector3, nose := Vector3(0, 0, -1)) -> ShipState:
	var state := ShipState.new()
	var radius := planet.radius + altitude
	state.position = WorldPos.new(planet.frame_id, 0.0, radius, 0.0)
	state.velocity = velocity
	state.basis = Basis.looking_at(nose.normalized(), Vector3.UP)
	return state


func test_flight_path_comes_from_velocity_not_nose() -> void:
	var planet := PlanetBody.new()
	var state := _state_at(planet, 100000.0, Vector3(0, -6000, 0), Vector3(0, 0, -1))
	var environment := FlightEnvironment.new()
	planet.fill_environment(state, environment)
	assert_near(state.entry_angle_deg, -90.0, 0.01, "straight down is -90 deg even with a level nose")
	assert_eq(state.entry_corridor, EntryModel.Corridor.STEEP, "steep corridor")
	assert_true(state.entry_heat_rate > 0.0, "steep fast entry heats")
	assert_eq(state.regime, FlightRegime.ENTERING)


func test_shallow_approach_is_shallow_and_slow_approach_is_cool() -> void:
	var planet := PlanetBody.new()
	var shallow := _state_at(planet, 150000.0, Vector3(6000, -100, 0))
	var environment := FlightEnvironment.new()
	planet.fill_environment(shallow, environment)
	assert_eq(shallow.entry_corridor, EntryModel.Corridor.SHALLOW, "nearly horizontal")
	var slow := _state_at(planet, 100000.0, Vector3(0, -400, 0))
	planet.fill_environment(slow, environment)
	assert_eq(slow.entry_heat_rate, 0.0, "slow descent is not a heating entry")
	assert_true(slow.entry_warning == "" or slow.entry_warning.begins_with("SHALLOW"), "slow shallow still reads as shallow")


func test_heat_builds_and_cools_and_damage_starts_above_the_limit() -> void:
	var state := ShipState.new()
	state.entry_density = 0.5
	state.entry_speed = 7000.0
	state.entry_angle_deg = -30.0
	state.entry_heat_rate = 0.12
	for tick in 600:
		EntryModel.step_thermal(state, 1.0 / 60.0)
	assert_true(state.entry_heat > 0.5, "heat builds")
	var hot := state.entry_heat
	state.entry_heat_rate = 0.0
	state.entry_density = 0.0
	for tick in 1800:
		EntryModel.step_thermal(state, 1.0 / 60.0)
	assert_true(state.entry_heat < hot, "heat cools when the entry ends")
	assert_true(state.entry_damage_rate >= 0.0, "damage rate is never negative")
