extends "res://tests/test_case.gd"
## The whole loop, headless and scripted through GameSession: orbit -> land -> stand up -> cockpit
## door -> inner door -> airlock -> outer door/walkway -> walk out -> walk 50 m -> walk back in ->
## close up -> sit -> take off -> back to space. A rule-based "player" drives it (it turns to face
## its target and walks), so nothing here is a recorded input stream.
## Checks every tick: the session state is legal, and the player never moves more than 0.5 m
## relative to the ship in one tick (no teleports).

const DELTA := 1.0 / 60.0
const MAX_STEP_PER_TICK := 0.5
const SPAWN_ALTITUDE := 300000.0


class LoopPilot extends PilotSource:
	enum Phase { DESCEND, HOLD, TAKEOFF }
	var phase := Phase.DESCEND

	func _init() -> void:
		source_id = &"loop_test"

	func poll(ship_state: ShipState, _delta: float) -> PilotCommand:
		var command := PilotCommand.new()
		command.move_lock = 1.0 # a scripted pilot holds the velocity it asks for, as Rodina's AI mover does
		command.stop_rotation = true # and holds its attitude (Rodina AI sets its turn rate directly)
		var altitude := ship_state.altitude_above_ground
		match phase:
			Phase.DESCEND:
				command.gear = PilotCommand.GEAR_CRUISE if altitude > 4000.0 else PilotCommand.GEAR_DOCK
				command.thrust = Vector3(0, -clampf(altitude / 80.0, 0.04, 1.0), 0)
			Phase.TAKEOFF:
				command.gear = PilotCommand.GEAR_CRUISE if altitude > 2500.0 else PilotCommand.GEAR_COMBAT
				command.thrust = Vector3(0, 1, 0)
			_:
				command.gear = ship_state.gear
		return command


var _session: GameSession
var _pilot: LoopPilot
var _ticks := 0
var _previous_local := Vector3.ZERO
var _worst_step := 0.0
var _legal_failure := ""


func _tick(foot_command: OnFootCommand = null) -> void:
	_session.tick(DELTA, foot_command if foot_command != null else OnFootCommand.new())
	_ticks += 1
	var problem := _session.validate()
	if problem != "" and _legal_failure == "":
		_legal_failure = "tick %d: %s" % [_ticks, problem]
	var local := ShipFrame.local_from_world(_session.ship.state, _session.player_world_position())
	if _ticks > 1:
		var step_length := local.distance_to(_previous_local)
		if step_length > MAX_STEP_PER_TICK:
			print("DEBUG jump ", step_length, " at tick ", _ticks, " mode ", _session.mode)
		_worst_step = maxf(_worst_step, step_length)
	_previous_local = local


func _wait(seconds: float) -> void:
	for tick in int(seconds * 60.0):
		_tick()


## Walk the inside body to a ship-local (x, z) point; returns false if it never arrives.
func _walk_inside_to(target_x: float, target_z: float, max_seconds: float = 20.0) -> bool:
	var body := _session.interior_body
	for tick in int(max_seconds * 60.0):
		var to_target := Vector2(target_x - body.position.x, target_z - body.position.z)
		if to_target.length() < 0.2:
			return true
		body.yaw = atan2(-to_target.x, -to_target.y) # face the target
		var command := OnFootCommand.new()
		command.move = Vector2(0, 1)
		_tick(command)
		if _session.mode != GameSession.Mode.INSIDE:
			return false
	return false


## Walk the outside body toward a ship-local point (converted to the world each tick).
func _walk_outside_to_local(target_local: Vector3, until_mode: int, max_seconds: float = 40.0) -> bool:
	for tick in int(max_seconds * 60.0):
		if _session.mode == until_mode:
			return true
		var target_world := ShipFrame.world_from_local(_session.ship.state, target_local)
		var to_target := target_world.vector_from(_session.exterior_body.position)
		var up := _session.planet.up_at(_session.exterior_body.position)
		to_target -= up * to_target.dot(up)
		if to_target.length() > 0.05:
			_session.exterior_body.heading = to_target.normalized()
		var command := OnFootCommand.new()
		command.move = Vector2(0, 1)
		_tick(command)
	return _session.mode == until_mode


func _walk_outside_away(distance_metres: float) -> bool:
	var start := _session.exterior_body.position.duplicate_position()
	var away_local := Vector3(0, 0, 1)
	var up := _session.planet.up_at(start)
	var away: Vector3 = _session.ship.state.basis * away_local
	away = (away - up * away.dot(up)).normalized()
	for tick in 60 * 40:
		if _session.exterior_body.position.distance_to(start) >= distance_metres:
			return true
		_session.exterior_body.heading = away
		var command := OnFootCommand.new()
		command.move = Vector2(0, 1)
		command.run = true
		_tick(command)
	return false


func test_full_loop_orbit_land_airlock_walk_return_takeoff() -> void:
	var planet := PlanetBody.new()
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	var direction := Vector3(0.3, 0.5, 0.8).normalized()
	var spawn_radius := planet.radius + SPAWN_ALTITUDE
	ship.state.position = WorldPos.new(planet.frame_id, direction.x * spawn_radius, direction.y * spawn_radius, direction.z * spawn_radius)
	ship.state.basis = Basis.looking_at(Vector3.UP.cross(direction).normalized(), direction)
	_pilot = LoopPilot.new()
	_session = GameSession.new(planet, ship, _pilot)
	assert_eq(_session.mode, GameSession.Mode.SEATED)

	# 1. Descend and land.
	for tick in 60 * 400:
		_tick()
		if ship.state.landed:
			break
	assert_true(ship.state.landed, "landed (altitude %f)" % ship.state.altitude_above_ground)
	_pilot.phase = LoopPilot.Phase.HOLD
	_wait(1.0)

	# 2. Stand up and walk the length of the ship, opening each door at its panel: cockpit, engineering,
	# turret room, cargo, then the airlock's inner door.
	_session.interact()
	assert_eq(_session.mode, GameSession.Mode.INSIDE, "stood up")
	assert_true(ship.controller.is_parked(), "ship parked once the pilot stands")
	assert_true(_walk_inside_to(0.8, -4.0), "reached the cockpit door panel")
	_session.interact()
	_wait(1.5)
	assert_true(_walk_inside_to(0.0, -3.9), "lined up with the cockpit door")
	for door in [[1.0, -0.5, -0.6, 0.6], [1.0, 2.9, 3.0, 3.9], [1.0, 5.3, 5.4, 6.4]]:
		assert_true(_walk_inside_to(door[0], door[1]), "to the door panel at z=%f" % door[1])
		_session.interact()
		_wait(1.5)
		assert_true(_walk_inside_to(0.0, door[2]), "lined up with the door at z=%f" % door[2])
		assert_true(_walk_inside_to(0.0, door[3]), "through the door at z=%f" % door[2])
	assert_true(_walk_inside_to(1.0, 7.6), "to the inner door panel")
	_session.interact()
	_wait(1.5)
	assert_true(_session.systems.airlock.inner.is_passable(), "inner door open")

	# 3. Into the airlock, close the inner door behind, open the outer door.
	assert_true(_walk_inside_to(0.0, 7.9), "lined up with the inner door")
	assert_true(_walk_inside_to(0.0, 9.3), "inside the airlock")
	assert_true(_walk_inside_to(1.2, 8.9), "at the airlock-side inner panel")
	_session.interact()
	_wait(1.5)
	assert_true(_session.systems.airlock.inner.is_fully_closed(), "inner door closed")
	_wait(AirlockController.CYCLE_SECONDS + 0.2)
	assert_true(_walk_inside_to(1.2, 9.8), "at the outer door panel")
	_session.interact()
	_wait(3.0)
	assert_true(_session.systems.airlock.outer.is_passable() and _session.systems.walkway.is_deployed(), "outer door open and walkway out")

	# 4. Walk out onto the ground, then 50 m away.
	assert_true(_walk_inside_to(0.0, 11.0), "through the outer door")
	for tick in 60 * 20:
		if _session.mode == GameSession.Mode.OUTSIDE:
			break
		_walk_inside_to(0.0, 16.6, 0.1)
	assert_eq(_session.mode, GameSession.Mode.OUTSIDE, "stepped off the ramp")
	assert_true(_walk_outside_away(50.0), "walked 50 m away")
	var farthest := ShipFrame.local_from_world(ship.state, _session.exterior_body.position).length()
	assert_true(farthest > 40.0, "really is far from the ship: %f" % farthest)

	# 5. Come back and walk up the ramp.
	assert_true(_walk_outside_to_local(Vector3(0, -1.0, 10.9), GameSession.Mode.INSIDE), "walked back up the ramp to the door (mode %d)" % _session.mode)
	assert_eq(_session.mode, GameSession.Mode.INSIDE)

	# 6. Close the outer door behind, open the inner door, walk to the cockpit (doors are still open) and sit.
	assert_true(_walk_inside_to(0.0, 11.2), "off the ramp")
	assert_true(_walk_inside_to(0.0, 9.6), "through the outer door")
	assert_true(_walk_inside_to(1.2, 9.8), "at the outer door panel")
	_session.interact()
	_wait(5.0)
	assert_true(_session.systems.airlock.outer.is_fully_closed() and _session.systems.walkway.is_stowed(), "outer door closed and walkway stowed")
	assert_true(_walk_inside_to(1.2, 8.9), "at the airlock-side inner panel")
	_wait(AirlockController.CYCLE_SECONDS + 0.2)
	_session.interact()
	_wait(1.5)
	assert_true(_session.systems.airlock.inner.is_passable(), "inner door open")
	for waypoint in [7.6, 5.0, 2.0, 0.0, -3.0, -4.4]:
		assert_true(_walk_inside_to(0.0, waypoint), "walking forward through the ship to z=%f" % waypoint)
	_session.interact()
	assert_eq(_session.mode, GameSession.Mode.SITTING)
	_wait(1.0)
	assert_eq(_session.mode, GameSession.Mode.SEATED, "seated")
	assert_true(ship.controller.current_source == _pilot, "pilot has control")

	# 7. Take off and fly back to space.
	_pilot.phase = LoopPilot.Phase.TAKEOFF
	for tick in 60 * 120:
		_tick()
		if ship.state.regime == FlightRegime.SPACE:
			break
	assert_eq(ship.state.regime, FlightRegime.SPACE, "back in space (altitude %f)" % ship.state.altitude_above_ground)

	assert_true(ship.state.hull > 0.8 and ship.state.hull <= 1.0, "a straight-down cruise descent only scorches the hull a little (re-entry heat): hull %f" % ship.state.hull)
	assert_true(_session.suit.health >= 1.0 and _session.suit.oxygen >= 0.99, "suit fine on a breathable world")
	assert_eq(_legal_failure, "", "state stayed legal")
	assert_true(_worst_step <= MAX_STEP_PER_TICK, "worst per-tick movement relative to the ship: %f m" % _worst_step)
	ship.free()
