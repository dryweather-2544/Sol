extends "res://tests/test_case.gd"
## The flight-speed gears across the whole loop, flown with player-style input (no velocity lock) through the real
## Ship over Aurelia: precision lift-off, hover and a small correction; pitch up; climb in combat; shift to cruise and
## leave the atmosphere; keep accelerating above it; brake; come back down and hover near the ground again.

const DELTA := 1.0 / 60.0


## Replays a function of (seconds, state) -> PilotCommand.
class ScriptPilot extends PilotSource:
	var function: Callable
	var t := 0.0

	func _init(script_function: Callable) -> void:
		source_id = &"modes_loop"
		function = script_function

	func poll(ship_state: ShipState, _delta: float) -> PilotCommand:
		t += DELTA
		return function.call(t, ship_state)


var _planet := PlanetBody.new()
var _ship: Ship


func _command(gear: int, thrust := Vector3.ZERO, turn := Vector3.ZERO) -> PilotCommand:
	var command := PilotCommand.new()
	command.gear = gear
	command.thrust = thrust
	command.turn = turn
	return command


func _fly(seconds: float, function: Callable, until := Callable()) -> float:
	_ship.controller.release_control(_ship.controller.current_source)
	_ship.controller.request_control(ScriptPilot.new(function), &"pilot_seat")
	var t := 0.0
	for tick in int(seconds * 60.0):
		_ship.simulate_tick(DELTA)
		t += DELTA
		if until.is_valid() and until.call(_ship.state):
			break
	return t


func _up() -> Vector3:
	return _planet.up_at(_ship.state.position)


func _vertical_speed() -> float:
	return _ship.state.velocity.dot(_up())


func _pitch_degrees() -> float:
	return rad_to_deg(asin(clampf(-_ship.state.basis.z.dot(_up()), -1.0, 1.0)))


func test_surface_to_space_and_back_with_the_gears() -> void:
	_ship = Ship.new()
	_ship.planet = _planet
	_ship.render_origin = WorldPos.new(_planet.frame_id)
	var up := Vector3(0.3, 0.5, 0.8).normalized()
	var ground := _planet.surface_radius_xyz(up.x, up.y, up.z)
	_ship.state.position = WorldPos.new(_planet.frame_id, up.x * (ground + 2.1), up.y * (ground + 2.1), up.z * (ground + 2.1))
	_ship.state.basis = Basis.looking_at(Vector3.UP.cross(up).normalized(), up)
	_fly(2.0, func(_t, _s): return _command(PilotCommand.GEAR_DOCK), func(s): return s.landed)
	assert_true(_ship.state.landed, "starts on the ground")

	# 1. Precision: lift off slowly, hover hands-off, nudge forward and stop.
	_fly(2.0, func(_t, _s): return _command(PilotCommand.GEAR_DOCK, Vector3(0, 1, 0)))
	assert_true(_vertical_speed() > 0.0 and _vertical_speed() <= 12.01, "precision lift-off at most 12 m/s: %f" % _vertical_speed())
	_fly(3.0, func(_t, _s): return _command(PilotCommand.GEAR_DOCK))
	var hover_altitude := _ship.state.altitude_above_ground
	_fly(2.0, func(_t, _s): return _command(PilotCommand.GEAR_DOCK))
	assert_true(absf(_ship.state.altitude_above_ground - hover_altitude) < 0.5 and _ship.state.speed() < 0.05, "hovers hands-off (%.2f m drift)" % (_ship.state.altitude_above_ground - hover_altitude))
	var before_nudge := _ship.state.position.duplicate_position()
	_fly(2.0, func(t, _s): return _command(PilotCommand.GEAR_DOCK, Vector3(0, 0, -1) if t <= 0.25 else Vector3.ZERO))
	var nudge := _ship.state.position.distance_to(before_nudge)
	assert_true(nudge > 0.8 and nudge < 1.6 and _ship.state.speed() < 0.05, "a quarter-second tap moves about a metre and stops: %.2f m" % nudge)

	# 2. Pitch the nose up (the air's friction helps stop the turn), then climb in combat gear.
	_fly(6.0, func(_t, s):
		var pitch := rad_to_deg(asin(clampf(-s.basis.z.dot(_planet.up_at(s.position)), -1.0, 1.0)))
		var command := _command(PilotCommand.GEAR_DOCK, Vector3.ZERO, Vector3(1, 0, 0) if pitch < 60.0 else Vector3.ZERO)
		command.stop_rotation = pitch >= 60.0 and s.angular_velocity.length() > 0.0
		return command, func(s): return rad_to_deg(asin(clampf(-s.basis.z.dot(_planet.up_at(s.position)), -1.0, 1.0))) > 75.0 and s.angular_velocity.length() < 1e-3)
	assert_true(_pitch_degrees() > 60.0, "nose up: %.1f degrees" % _pitch_degrees())
	_fly(3.0, func(_t, _s): return _command(PilotCommand.GEAR_COMBAT, Vector3(0, 0, -1)))
	assert_near(_ship.state.speed(), 500.0, 25.0, "combat climb at about 500 m/s")

	# 3. Cruise out of the atmosphere: well under a minute, and no ceiling above it.
	var climb := _fly(60.0, func(_t, _s): return _command(PilotCommand.GEAR_CRUISE, Vector3(0, 0, -1)), func(s): return s.atmosphere_ratio > 1.0)
	assert_true(_ship.state.atmosphere_ratio > 1.0, "reached space")
	assert_true(climb < 30.0, "atmosphere left %.1f s after shifting to cruise" % climb)
	if OS.get_environment("FLIGHT_DEBUG") != "":
		print("FLIGHT_DEBUG hover drift ok, nudge %.3f m, pitch %.1f, climb to space %.2f s" % [nudge, _pitch_degrees(), climb])
	assert_true(_ship.state.atmosphere_resistance == 0.0 and _ship.state.hull >= 1.0, "leaving the air does not burn")
	_fly(10.0, func(_t, _s): return _command(PilotCommand.GEAR_CRUISE, Vector3(0, 0, -1)), func(s): return s.altitude_above_ground > 2.0e6)
	if OS.get_environment("FLIGHT_DEBUG") != "":
		print("FLIGHT_DEBUG above the air: altitude %.0f m, speed %.0f m/s" % [_ship.state.altitude_above_ground, _ship.state.speed()])
	assert_true(_ship.state.speed() > 1.0e5, "cruise keeps building above the air (distance-scaled): %.0f m/s" % _ship.state.speed())

	# 4. Brake: the speed drops predictably (cruise brakes at its acceleration rate, 0.5 x the speed limit per second).
	var speed_before_brake := _ship.state.speed()
	_fly(1.0, func(_t, _s):
		var command := _command(PilotCommand.GEAR_CRUISE)
		command.brake = true
		return command)
	assert_true(_ship.state.speed() < speed_before_brake * 0.7, "braking sheds speed: %.0f -> %.0f m/s" % [speed_before_brake, _ship.state.speed()])

	# 5. Back near the ground, falling fast: combat brake, then precision hovers.
	_ship.state.position = WorldPos.new(_planet.frame_id, up.x * (ground + 3000.0), up.y * (ground + 3000.0), up.z * (ground + 3000.0))
	_ship.state.basis = Basis.looking_at(Vector3.UP.cross(up).normalized(), up)
	_ship.state.velocity = -up * 800.0
	_ship.state.angular_velocity = Vector3.ZERO
	_fly(10.0, func(_t, _s):
		var command := _command(PilotCommand.GEAR_COMBAT)
		command.brake = true
		return command, func(s): return s.speed() < 5.0)
	_fly(4.0, func(_t, _s): return _command(PilotCommand.GEAR_DOCK))
	if OS.get_environment("FLIGHT_DEBUG") != "":
		print("FLIGHT_DEBUG return: hovering at %.0f m, speed %.4f m/s" % [_ship.state.altitude_above_ground, _ship.state.speed()])
	assert_true(not _ship.state.landed and _ship.state.altitude_above_ground > 100.0, "stopped well above the ground: %.0f m" % _ship.state.altitude_above_ground)
	assert_true(_ship.state.speed() < 0.05, "and hovering in precision: %.3f m/s" % _ship.state.speed())
	_ship.free()
