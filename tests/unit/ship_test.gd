extends "res://tests/test_case.gd"


func test_ship_follows_scripted_pilot_and_transform_matches_state() -> void:
	var ship := Ship.new()
	var commands: Array[PilotCommand] = []
	for tick in 60:
		var command := PilotCommand.new()
		command.thrust = Vector3(0, 0, -1)
		command.turn = Vector3(0, 0.5, 0)
		commands.append(command)
	assert_true(ship.controller.request_control(ScriptedPilotSource.new(commands), &"pilot_seat").granted)
	for tick in 60:
		ship.simulate_tick(1.0 / 60.0)
	assert_true(ship.state.speed() >= 30.0, "ship moved under scripted control")
	assert_near(ship.position.distance_to(ship.state.position.to_local_vector3(ship.render_origin)), 0.0, 1e-4)
	assert_true(ship.basis.is_equal_approx(ship.state.basis))
	ship.free()


func test_unpiloted_ship_coasts() -> void:
	var ship := Ship.new()
	ship.state.velocity = Vector3(0, 0, -20)
	for tick in 60:
		ship.simulate_tick(1.0 / 60.0)
	assert_near(ship.state.position.z, -20.0, 1e-3)
	ship.free()
