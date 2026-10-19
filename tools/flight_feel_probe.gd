extends SceneTree
## Pure flight-feel measurements, no rendering. The axis mapping is Sol's:
## local +X right, +Y up, -Z forward.

const DELTA := 1.0 / 60.0


func _initialize() -> void:
	var tuning := ShipTuning.new()
	print("axis strengths dock=%s combat=%s cruise=%s" % [
		tuning.axis_strength_for(PilotCommand.GEAR_DOCK),
		tuning.axis_strength_for(PilotCommand.GEAR_COMBAT),
		tuning.axis_strength_for(PilotCommand.GEAR_CRUISE)])
	for gear in 3:
		var state := ShipState.new()
		state.gear = gear
		var env := FlightEnvironment.new()
		env.cruise_speed_limit = 12000.0
		var command := PilotCommand.new()
		command.gear = gear
		command.thrust = Vector3(0, 0, -1)
		for tick in 300:
			FlightModel.step(state, command, tuning, env, DELTA)
		print("gear %d forward after 5s: %.0f m/s (%.1f km/s)" % [gear, state.speed(), state.speed() / 1000.0])
	# Lateral and vertical authority in combat gear.
	for axis_name in ["right", "up"]:
		var state := ShipState.new()
		state.gear = PilotCommand.GEAR_COMBAT
		var env := FlightEnvironment.new()
		var command := PilotCommand.new()
		command.gear = PilotCommand.GEAR_COMBAT
		command.thrust = Vector3.RIGHT if axis_name == "right" else Vector3.UP
		for tick in 180:
			FlightModel.step(state, command, tuning, env, DELTA)
		print("combat %s after 3s: %.0f m/s" % [axis_name, state.speed()])
	var cruise := ShipState.new()
	cruise.gear = PilotCommand.GEAR_CRUISE
	var cruise_env := FlightEnvironment.new()
	cruise_env.cruise_speed_limit = 12000.0
	var thrust := PilotCommand.new()
	thrust.gear = PilotCommand.GEAR_CRUISE
	thrust.thrust = Vector3(0, 0, -1)
	for tick in 300:
		FlightModel.step(cruise, thrust, tuning, cruise_env, DELTA)
	var coast := PilotCommand.new()
	coast.gear = PilotCommand.GEAR_CRUISE
	for tick in 600:
		FlightModel.step(cruise, coast, tuning, cruise_env, DELTA)
	print("cruise coast 10s: %.0f m/s" % cruise.speed())
	var brake := PilotCommand.new()
	brake.gear = PilotCommand.GEAR_CRUISE
	brake.brake = true
	var brake_ticks := 0
	while cruise.speed() > 1.0 and brake_ticks < 600:
		FlightModel.step(cruise, brake, tuning, cruise_env, DELTA)
		brake_ticks += 1
	print("cruise brake to 1 m/s: %.2f s" % (brake_ticks * DELTA))
	# Turn response: full yaw from rest.
	var turn_state := ShipState.new()
	turn_state.gear = PilotCommand.GEAR_CRUISE
	var turn_command := PilotCommand.new()
	turn_command.gear = PilotCommand.GEAR_CRUISE
	turn_command.turn = Vector3(0, 1, 0)
	for tick in 60:
		FlightModel.step(turn_state, turn_command, tuning, FlightEnvironment.new(), DELTA)
	print("yaw angular velocity after 1s: %.2f rad/s" % turn_state.angular_velocity.length())
	quit()
