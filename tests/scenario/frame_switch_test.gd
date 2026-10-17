extends "res://tests/test_case.gd"
## Fly from the home planet to its moon through the system frame and land there. At every frame
## switch the ship's position and velocity must be continuous in the system frame, and the ship
## must never end up inside terrain.

const DELTA := 1.0 / 60.0


class TravelPilot extends PilotSource:
	var runtime: WorldRuntime
	var session: GameSession
	var target_body: StringName
	var landing := false

	func _init() -> void:
		source_id = &"travel_test"

	func poll(ship_state: ShipState, _delta: float) -> PilotCommand:
		var command := PilotCommand.new()
		var system := runtime.system
		var target_center := system.convert_position(WorldPos.new(target_body, 0.0, 0.0, 0.0), runtime.active_frame, runtime.time_seconds)
		var to_target := Vector3(target_center.x - ship_state.position.x, target_center.y - ship_state.position.y, target_center.z - ship_state.position.z)
		if landing:
			# Belly toward the ground, descend gently.
			var up := Vector3(ship_state.position.x, ship_state.position.y, ship_state.position.z).normalized()
			ship_state.basis = Basis.looking_at(Vector3.UP.cross(up).normalized(), up)
			command.gear = PilotCommand.GEAR_CRUISE if ship_state.altitude_above_ground > 4000.0 else PilotCommand.GEAR_DOCK
			command.thrust = Vector3(0, -clampf(ship_state.altitude_above_ground / 80.0, 0.04, 1.0), 0)
		else:
			ship_state.basis = Basis.looking_at(to_target.normalized(), Vector3.UP)
			command.gear = PilotCommand.GEAR_CRUISE
			command.thrust = Vector3(0, 0, -1)
		return command


func test_fly_home_planet_to_moon_through_system_frame_and_land() -> void:
	var system := StarSystem.default_system()
	var home := system.build_planet_body(&"planet")
	var ship := Ship.new()
	ship.render_origin = WorldPos.new(&"planet")
	ship.state.position = WorldPos.new(&"planet", 0.0, 0.0, home.radius + 300000.0)
	var pilot := TravelPilot.new()
	pilot.target_body = &"selene"
	var session := GameSession.new(home, ship, pilot)
	var runtime := WorldRuntime.new(system, session, &"planet")
	pilot.runtime = runtime
	pilot.session = session
	var frames_seen: Array[StringName] = [&"planet"]
	var worst_position_jump := 0.0
	var worst_velocity_jump := 0.0
	var landed := false
	var deepest := INF
	for tick in 60 * 900:
		var before_position := system.convert_position(ship.state.position, StarSystem.SYSTEM_FRAME, runtime.time_seconds)
		var before_velocity := system.convert_velocity(ship.state.velocity, runtime.active_frame, StarSystem.SYSTEM_FRAME, runtime.time_seconds)
		runtime.advance(DELTA)
		if runtime.update_frame():
			frames_seen.append(runtime.active_frame)
			# The same instant, expressed in the new frame, must be the same point and velocity.
			var after_position := system.convert_position(ship.state.position, StarSystem.SYSTEM_FRAME, runtime.time_seconds)
			var after_velocity := system.convert_velocity(ship.state.velocity, runtime.active_frame, StarSystem.SYSTEM_FRAME, runtime.time_seconds)
			worst_position_jump = maxf(worst_position_jump, after_position.distance_to(before_position) - before_velocity.length() * DELTA * 2.0 - 1.0)
			worst_velocity_jump = maxf(worst_velocity_jump, after_velocity.distance_to(before_velocity))
		if runtime.active_frame == &"selene":
			pilot.landing = true
		session.tick(DELTA, OnFootCommand.new())
		if runtime.session.planet != null:
			deepest = minf(deepest, runtime.session.planet.altitude_above_ground(ship.state.position))
		if ship.state.landed:
			landed = true
			break
	assert_eq(frames_seen, [&"planet", StarSystem.SYSTEM_FRAME, &"selene"] as Array[StringName], "frames visited in order")
	assert_true(worst_position_jump <= 0.0, "position jumped at a frame switch by %f m beyond one tick of motion" % worst_position_jump)
	assert_true(worst_velocity_jump < 1.0, "velocity jumped at a frame switch: %f m/s" % worst_velocity_jump)
	assert_true(landed, "landed on the moon (frame %s, altitude %f)" % [runtime.active_frame, ship.state.altitude_above_ground])
	assert_true(deepest > -3.0, "never far below terrain: %f" % deepest)
	assert_eq(session.validate(), "")
	ship.free()
