extends SceneTree
## Pure flight feel numbers, no rendering. Prints acceleration, cruise, coast and brake times so
## the report can state what was actually changed rather than only showing screenshots.

func _initialize() -> void:
	var state := ShipState.new()
	var tuning := ShipTuning.new()
	var env := FlightEnvironment.new()
	env.cruise_speed_limit = 12000.0
	var command := PilotCommand.new()
	command.gear = PilotCommand.GEAR_CRUISE
	command.thrust = Vector3(0, 0, -1)
	var dt := 1.0 / 60.0
	var marks := {60: "1s", 180: "3s", 300: "5s", 480: "8s"}
	for tick in 600:
		FlightModel.step(state, command, tuning, env, dt)
		if marks.has(tick + 1):
			print("accelerate %s: %.0f m/s (%.1f km/s)" % [marks[tick + 1], state.speed(), state.speed() / 1000.0])
	print("cruise cap: %.0f m/s" % env.cruise_speed_limit)
	var coast := command
	coast.thrust = Vector3.ZERO
	for tick in 600:
		FlightModel.step(state, coast, tuning, env, dt)
	print("coast 10s from cap: %.0f m/s" % state.speed())
	var brake := PilotCommand.new()
	brake.gear = PilotCommand.GEAR_CRUISE
	brake.brake = true
	var brake_ticks := 0
	while state.speed() > 1.0 and brake_ticks < 600:
		FlightModel.step(state, brake, tuning, env, dt)
		brake_ticks += 1
	print("brake to 1 m/s: %.2f s" % (brake_ticks * dt))
	quit()
