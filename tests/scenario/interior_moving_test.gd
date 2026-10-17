extends "res://tests/test_case.gd"
## Walking inside while the ship flies at 500 m/s and rolls: interior coordinates are ship-local, so
## nothing about the ship's motion may leak into where the person is or what they can walk through.

const DELTA := 1.0 / 60.0


func _flying_session() -> GameSession:
	var planet := PlanetBody.new()
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	var direction := Vector3(0.3, 0.5, 0.8).normalized()
	var radius := planet.radius + 300000.0
	ship.state.position = WorldPos.new(planet.frame_id, direction.x * radius, direction.y * radius, direction.z * radius)
	ship.state.velocity = Vector3(0, 0, -500).rotated(Vector3.UP, 0.3)
	return GameSession.new(planet, ship, PilotSource.new())


func _fly_tick(session: GameSession, command: OnFootCommand) -> void:
	session.ship.state.angular_velocity = Vector3(0.2, 0.1, 1.2) # keep rolling and tumbling gently
	session.tick(DELTA, command)


func test_standing_still_inside_a_rolling_500_mps_ship_does_not_move() -> void:
	var session := _flying_session()
	session.interact() # stand up in flight
	assert_eq(session.mode, GameSession.Mode.INSIDE)
	var before := session.interior_body.position
	var ship_start := session.ship.state.position.duplicate_position()
	for tick in 600:
		_fly_tick(session, OnFootCommand.new())
	assert_true(session.ship.state.position.distance_to(ship_start) > 4000.0, "the ship really flew")
	assert_true(session.interior_body.position.distance_to(before) < 1e-6, "ship-local position unchanged")
	assert_eq(session.validate(), "")
	session.ship.free()


func test_walking_inside_a_moving_ship_never_clips_through_walls() -> void:
	var session := _flying_session()
	session.interact()
	var layout := session.systems.layout
	var rng := SeedRng.new(11)
	var worst_step := 0.0
	var previous := session.interior_body.position
	for tick in 3000:
		var command := OnFootCommand.new()
		command.move = Vector2(rng.next_float() * 2.0 - 1.0, rng.next_float() * 2.0 - 1.0)
		command.yaw_delta = (rng.next_float() - 0.5) * 0.2
		command.run = rng.next_float() < 0.3
		_fly_tick(session, command)
		var position := session.interior_body.position
		assert_true(layout.is_position_walkable(position.x, position.z, 0.0), "outside the walkable area at tick %d: %s" % [tick, str(position)])
		worst_step = maxf(worst_step, position.distance_to(previous))
		previous = position
	assert_true(worst_step < InteriorBody.RUN_SPEED * DELTA + 0.01, "no jumps: %f" % worst_step)
	session.ship.free()
