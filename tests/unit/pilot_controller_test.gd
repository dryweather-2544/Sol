extends "res://tests/test_case.gd"


func test_first_request_is_granted_and_second_source_is_denied_with_reason() -> void:
	var controller := PilotController.new()
	var player := PlayerPilotSource.new()
	var intruder := ScriptedPilotSource.new()
	assert_true(controller.request_control(player, &"pilot_seat").granted)
	var denied := controller.request_control(intruder, &"co_pilot_seat")
	assert_true(not denied.granted)
	assert_true(denied.reason.contains("player"), "reason names the current pilot: %s" % denied.reason)
	assert_true(controller.current_source == player, "denied request must not steal control")
	controller.free()


func test_same_source_can_request_again() -> void:
	var controller := PilotController.new()
	var player := PlayerPilotSource.new()
	controller.request_control(player, &"pilot_seat")
	assert_true(controller.request_control(player, &"pilot_seat").granted)
	controller.free()


func test_release_returns_to_parked_and_only_holder_can_release() -> void:
	var controller := PilotController.new()
	var player := PlayerPilotSource.new()
	var other := ScriptedPilotSource.new()
	assert_true(controller.is_parked(), "no pilot at start")
	controller.request_control(player, &"pilot_seat")
	assert_true(not controller.is_parked())
	controller.release_control(other)
	assert_true(not controller.is_parked(), "non-holder cannot release")
	controller.release_control(player)
	assert_true(controller.is_parked())
	assert_true(controller.request_control(other, &"pilot_seat").granted, "free again after release")
	controller.free()


func test_control_changed_signal_reports_old_and_new_source() -> void:
	var controller := PilotController.new()
	var player := PlayerPilotSource.new()
	var events: Array = []
	controller.control_changed.connect(func(previous_source, new_source): events.append([previous_source, new_source]))
	controller.request_control(player, &"pilot_seat")
	controller.release_control(player)
	assert_eq(events.size(), 2)
	assert_true(events[0][0] == null and events[0][1] == player)
	assert_true(events[1][0] == player and events[1][1] == null)
	controller.free()


func test_parked_ship_holds_velocity_and_keeps_gear() -> void:
	var controller := PilotController.new()
	var ship_state := ShipState.new()
	ship_state.gear = 1
	var command := controller.poll_command(ship_state, 0.016)
	assert_true(command.lock_linear)
	assert_eq(command.gear, 1)
	assert_eq(command.thrust, Vector3.ZERO)
	controller.free()


func test_scripted_source_plays_commands_in_order_then_goes_neutral() -> void:
	var commands: Array[PilotCommand] = []
	for tick in 3:
		var command := PilotCommand.new()
		command.thrust = Vector3(0, 0, -float(tick + 1) / 3.0)
		commands.append(command)
	var source := ScriptedPilotSource.new(commands)
	var ship_state := ShipState.new()
	assert_near(source.poll(ship_state, 0.0).thrust.z, -1.0 / 3.0, 1e-6)
	assert_near(source.poll(ship_state, 0.0).thrust.z, -2.0 / 3.0, 1e-6)
	assert_near(source.poll(ship_state, 0.0).thrust.z, -1.0, 1e-9)
	assert_eq(source.poll(ship_state, 0.0).thrust, Vector3.ZERO)


func test_poll_command_stamps_source_id() -> void:
	var controller := PilotController.new()
	controller.request_control(ScriptedPilotSource.new(), &"pilot_seat")
	assert_eq(controller.poll_command(ShipState.new(), 0.016).source_id, &"scripted")
	controller.free()
