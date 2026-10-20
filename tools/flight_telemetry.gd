extends SceneTree
## Flight telemetry: flies fixed manoeuvres through the real Ship + FlightModel + PlanetBody (headless, no rendering)
## and prints what happened, so a change to the flight model can be compared before and after on identical inputs.
##   godot --headless --path . -s res://tools/flight_telemetry.gd [-- scenario_name]
## Each scenario prints a header, then "t=<seconds> key=value ..." rows at the sample times, then a summary line.
## Angles are degrees: pitch = nose above the local horizon, roll = right wing above it. Rates are deg/s, ship-local
## (pitch, yaw, roll). altitude = metres above the ground. Starts at Aurelia (the default PlanetBody).

const DELTA := 1.0 / 60.0


## Plays a function of time as the pilot: Callable(t: float, state: ShipState) -> PilotCommand.
class TimedPilot extends PilotSource:
	var script_function: Callable
	var started_ticks := 0

	func _init(function: Callable) -> void:
		source_id = &"telemetry"
		script_function = function

	func poll(ship_state: ShipState, _delta: float) -> PilotCommand:
		started_ticks += 1
		var command: PilotCommand = script_function.call(started_ticks * DELTA, ship_state)
		return command


var _planet := PlanetBody.new()


func _initialize() -> void:
	var only := "" if OS.get_cmdline_user_args().is_empty() else OS.get_cmdline_user_args()[0]
	var scenarios := {
		"thrust_release_space": _thrust_release_space,
		"yaw_release_space": _yaw_release_space,
		"yaw_release_atmosphere": _yaw_release_atmosphere,
		"pitched_descent_through_400m": _pitched_descent,
		"pitched_up_hands_off_300m": _pitched_low,
		"rolled_no_input_atmosphere": _rolled_no_input,
		"hands_off_hover_1000m": _hands_off_hover,
		"brake_from_combat_speed": _brake,
		"gear_down_from_cruise": _gear_down,
		"strafe_space": _strafe,
	}
	for scenario_name in scenarios:
		if only == "" or scenario_name.contains(only):
			print("== ", scenario_name)
			scenarios[scenario_name].call()
	quit(0)


func _command(gear: int, thrust := Vector3.ZERO, turn := Vector3.ZERO) -> PilotCommand:
	var command := PilotCommand.new()
	command.gear = gear
	command.thrust = thrust
	command.turn = turn
	return command


## A ship above Aurelia at `altitude` metres over the ground, level, nose along the local east.
func _ship_at(altitude: float, pitch_degrees := 0.0, roll_degrees := 0.0) -> Ship:
	var ship := Ship.new()
	ship.planet = _planet
	ship.render_origin = WorldPos.new(_planet.frame_id)
	var up := Vector3(0.3, 0.5, 0.8).normalized()
	var ground := _planet.surface_radius_xyz(up.x, up.y, up.z)
	ship.state.position = WorldPos.new(_planet.frame_id, up.x * (ground + altitude), up.y * (ground + altitude), up.z * (ground + altitude))
	var east := Vector3.UP.cross(up).normalized()
	var basis := Basis.looking_at(east, up)
	basis = basis * Basis(Vector3(1, 0, 0), deg_to_rad(pitch_degrees)) * Basis(Vector3(0, 0, 1), deg_to_rad(roll_degrees))
	ship.state.basis = basis
	ship.state.gear = PilotCommand.GEAR_COMBAT
	return ship


## Deep space: no planet at all.
func _ship_in_space() -> Ship:
	var ship := Ship.new()
	ship.state.gear = PilotCommand.GEAR_COMBAT
	return ship


func _angles(ship: Ship) -> Vector2:
	if ship.planet == null:
		return Vector2.ZERO
	var up := ship.planet.up_at(ship.state.position)
	var forward := -ship.state.basis.z
	var pitch := rad_to_deg(asin(clampf(forward.dot(up), -1.0, 1.0)))
	var roll := rad_to_deg(atan2(ship.state.basis.x.dot(up), ship.state.basis.y.dot(up)))
	return Vector2(pitch, roll)


func _row(t: float, ship: Ship) -> String:
	var angles := _angles(ship)
	var rate := ship.state.angular_velocity * (180.0 / PI)
	var local_velocity := ship.state.basis.transposed() * ship.state.velocity
	var altitude := ship.state.altitude_above_ground if ship.planet != null else 0.0
	return "t=%5.2f speed=%8.2f v_local=(%7.2f %7.2f %7.2f) alt=%9.1f pitch=%6.2f roll=%7.2f rate=(%6.2f %6.2f %6.2f) gear=%d landed=%s" % [
		t, ship.state.speed(), local_velocity.x, local_velocity.y, local_velocity.z, altitude, angles.x, angles.y, rate.x, rate.y, rate.z, ship.state.gear, ship.state.landed]


## Runs `seconds`, printing a row at each sample time.
func _run(ship: Ship, function: Callable, seconds: float, samples: Array) -> void:
	ship.controller.request_control(TimedPilot.new(function), &"pilot_seat")
	var ticks := int(round(seconds / DELTA))
	var next := 0
	print(_row(0.0, ship))
	for tick in range(1, ticks + 1):
		ship.simulate_tick(DELTA)
		var t := tick * DELTA
		while next < samples.size() and t >= samples[next] - 1e-6:
			print(_row(t, ship))
			next += 1


func _thrust_release_space() -> void:
	var ship := _ship_in_space()
	_run(ship, func(t, _s): return _command(PilotCommand.GEAR_COMBAT, Vector3(0, 0, -1) if t <= 3.0 else Vector3.ZERO), 8.0, [0.25, 0.5, 1.0, 2.0, 3.0, 3.5, 4.0, 5.0, 8.0])


func _yaw_release_space() -> void:
	var ship := _ship_in_space()
	_run(ship, func(t, _s): return _command(PilotCommand.GEAR_COMBAT, Vector3.ZERO, Vector3(0, 1, 0) if t <= 1.0 else Vector3.ZERO), 5.0, [0.1, 0.25, 0.5, 1.0, 1.1, 1.25, 1.5, 2.0, 3.0, 5.0])


func _yaw_release_atmosphere() -> void:
	var ship := _ship_at(5000.0)
	_run(ship, func(t, _s): return _command(PilotCommand.GEAR_COMBAT, Vector3.ZERO, Vector3(0, 1, 0) if t <= 1.0 else Vector3.ZERO), 5.0, [0.1, 0.25, 0.5, 1.0, 1.1, 1.25, 1.5, 2.0, 3.0, 5.0])


## Pitched 30 degrees nose-up, combat gear, no input, sinking from 800 m through the old 400 m levelling band.
func _pitched_descent() -> void:
	var ship := _ship_at(800.0, 30.0)
	ship.state.velocity = -_planet.up_at(ship.state.position) * 40.0
	_run(ship, func(_t, _s): return _command(PilotCommand.GEAR_COMBAT), 12.0, [1.0, 2.0, 4.0, 6.0, 8.0, 10.0, 12.0])


## Pitched 30 degrees nose-up and rolled 20 degrees, already inside the old levelling band, no input.
func _pitched_low() -> void:
	var ship := _ship_at(300.0, 30.0, 20.0)
	_run(ship, func(_t, _s): return _command(PilotCommand.GEAR_COMBAT), 4.0, [0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0])


func _rolled_no_input() -> void:
	var ship := _ship_at(20000.0, 0.0, 45.0)
	_run(ship, func(_t, _s): return _command(PilotCommand.GEAR_COMBAT), 8.0, [0.5, 1.0, 2.0, 3.0, 4.0, 6.0, 8.0])


func _hands_off_hover() -> void:
	var ship := _ship_at(1000.0)
	_run(ship, func(_t, _s): return _command(PilotCommand.GEAR_DOCK), 6.0, [0.5, 1.0, 2.0, 3.0, 4.0, 6.0])


func _brake() -> void:
	var ship := _ship_in_space()
	ship.state.velocity = -ship.state.basis.z * 500.0
	_run(ship, func(_t, _s):
		var command := _command(PilotCommand.GEAR_COMBAT)
		command.brake = true
		return command, 4.0, [0.25, 0.5, 1.0, 2.0, 3.0, 4.0])


func _gear_down() -> void:
	var ship := _ship_in_space()
	ship.state.gear = PilotCommand.GEAR_COMBAT
	ship.state.velocity = -ship.state.basis.z * 5000.0
	_run(ship, func(_t, _s): return _command(PilotCommand.GEAR_COMBAT), 6.0, [0.5, 1.0, 2.0, 3.0, 4.0, 6.0])


func _strafe() -> void:
	var ship := _ship_in_space()
	_run(ship, func(t, _s): return _command(PilotCommand.GEAR_COMBAT, Vector3(1, 0, 0) if t <= 3.0 else Vector3.ZERO), 6.0, [0.5, 1.0, 2.0, 3.0, 4.0, 6.0])
