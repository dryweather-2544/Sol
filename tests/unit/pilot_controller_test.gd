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
	ship_state.selected_gear = 1 # the gear the pilot chose is the one a parked ship keeps
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


func test_player_gear_shift_can_reach_warp() -> void:
	var source := PlayerPilotSource.new()
	var state := ShipState.new()
	state.selected_gear = PilotCommand.GEAR_CRUISE
	Input.action_press("gear_up")
	var command := source.poll(state, 1.0 / 60.0)
	Input.action_release("gear_up")
	assert_eq(command.gear, PilotCommand.GEAR_WARP, "the player can select warp above cruise")


func _release_all_shift_inputs() -> void:
	for action in ["clutch", "thrust_forward", "thrust_back", "gear_up", "gear_down"]:
		Input.action_release(action)


func test_clutch_then_w_shifts_up_on_release_and_disconnects_the_drive() -> void:
	var source := PlayerPilotSource.new()
	var state := ShipState.new()
	state.selected_gear = PilotCommand.GEAR_COMBAT
	state.allowed_gear = PilotCommand.GEAR_WARP
	Input.action_press("clutch")
	var held := source.poll(state, 1.0 / 60.0)
	assert_true(held.lock_linear and held.clutch, "clutch held: the drive is disconnected")
	Input.action_press("thrust_forward")
	held = source.poll(state, 1.0 / 60.0)
	assert_eq(held.gear, PilotCommand.GEAR_COMBAT, "the shift is pending, not committed, while W is held")
	assert_eq(state.shift_pending, PilotCommand.GEAR_CRUISE, "the HUD sees the gear being shifted to")
	assert_eq(held.thrust, Vector3.ZERO, "W is a shift key, not thrust, under the clutch")
	Input.action_release("thrust_forward")
	var committed := source.poll(state, 1.0 / 60.0)
	assert_eq(committed.gear, PilotCommand.GEAR_CRUISE, "releasing W commits the shift")
	_release_all_shift_inputs()
	source.poll(state, 1.0 / 60.0)


func test_clutch_s_shifts_down_and_one_shift_per_press() -> void:
	var source := PlayerPilotSource.new()
	var state := ShipState.new()
	state.selected_gear = PilotCommand.GEAR_CRUISE
	state.allowed_gear = PilotCommand.GEAR_WARP
	Input.action_press("clutch")
	Input.action_press("thrust_back")
	for tick in 10:
		source.poll(state, 1.0 / 60.0)
	assert_eq(state.shift_pending, PilotCommand.GEAR_COMBAT, "holding S does not run on to a second gear")
	Input.action_release("thrust_back")
	assert_eq(source.poll(state, 1.0 / 60.0).gear, PilotCommand.GEAR_COMBAT)
	_release_all_shift_inputs()
	source.poll(state, 1.0 / 60.0)


func test_clutch_shift_to_an_unavailable_gear_is_refused() -> void:
	var source := PlayerPilotSource.new()
	var state := ShipState.new()
	state.selected_gear = PilotCommand.GEAR_CRUISE
	state.allowed_gear = PilotCommand.GEAR_CRUISE # no warp drive / near a planet
	Input.action_press("clutch")
	Input.action_press("thrust_forward")
	for tick in 5:
		source.poll(state, 1.0 / 60.0)
	assert_eq(state.shift_refusals, 1, "one refusal (the grind), not one per tick")
	assert_eq(state.shift_pending, -1)
	Input.action_release("thrust_forward")
	assert_eq(source.poll(state, 1.0 / 60.0).gear, PilotCommand.GEAR_CRUISE)
	_release_all_shift_inputs()
	source.poll(state, 1.0 / 60.0)


func test_without_the_clutch_w_still_thrusts_and_gear_is_unchanged() -> void:
	var source := PlayerPilotSource.new()
	var state := ShipState.new()
	state.selected_gear = PilotCommand.GEAR_COMBAT
	_release_all_shift_inputs()
	Input.action_press("thrust_forward")
	var command := source.poll(state, 1.0 / 60.0)
	Input.action_release("thrust_forward")
	assert_true(not command.lock_linear and not command.clutch)
	assert_eq(state.shift_pending, -1, "no clutch, no pending shift")
	assert_true(command.thrust.z != 0.0, "W is forward thrust")
