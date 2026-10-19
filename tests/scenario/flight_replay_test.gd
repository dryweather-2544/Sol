extends "res://tests/test_case.gd"
## 600-tick scripted flight. The command stream is a pure function of the tick number, so the
## result must be identical on every run. The expected numbers are a REGRESSION SNAPSHOT of this
## implementation (recorded once; flight_model_test.gd holds the hand-computed physics checks).
## If you change flight tuning on purpose, re-record them; otherwise a failure here is a bug.

const DELTA := 1.0 / 60.0
const EXPECTED_X := -151.491250
const EXPECTED_Y := -105.653621
const EXPECTED_Z := -626.405983
const EXPECTED_VELOCITY := Vector3.ZERO


func _command_for_tick(tick: int) -> PilotCommand:
	var command := PilotCommand.new()
	if tick < 120:
		command.thrust = Vector3(0, 0, -1)
	elif tick < 240:
		command.thrust = Vector3(0.5, 0, -1)
		command.turn = Vector3(0, 0.6, 0)
	elif tick < 300:
		command.turn = Vector3(0.4, 0, 1.0)
		command.thrust = Vector3(0, 0.3, -0.2)
	elif tick < 420:
		command.thrust = Vector3(-1, 1, -1)
		command.boost = true
		command.gear = PilotCommand.GEAR_COMBAT
	else:
		command.brake = true
		command.gear = PilotCommand.GEAR_COMBAT
	return command


func _run_flight() -> ShipState:
	var ship_state := ShipState.new()
	var tuning := ShipTuning.new()
	var environment := FlightEnvironment.new()
	for tick in 600:
		FlightModel.step(ship_state, _command_for_tick(tick), tuning, environment, DELTA)
	return ship_state


func test_same_commands_give_identical_results_twice() -> void:
	var first_run := _run_flight()
	var second_run := _run_flight()
	assert_eq(first_run.velocity, second_run.velocity)
	assert_eq(first_run.basis, second_run.basis)
	assert_true(first_run.position.is_approximately_equal(second_run.position, 0.0))


func test_600_tick_flight_matches_recorded_snapshot() -> void:
	var final_state := _run_flight()
	assert_near(final_state.position.x, EXPECTED_X, 1e-3)
	assert_near(final_state.position.y, EXPECTED_Y, 1e-3)
	assert_near(final_state.position.z, EXPECTED_Z, 1e-3)
	assert_near(final_state.velocity.x, EXPECTED_VELOCITY.x, 1e-3)
	assert_near(final_state.velocity.y, EXPECTED_VELOCITY.y, 1e-3)
	assert_near(final_state.velocity.z, EXPECTED_VELOCITY.z, 1e-3)
