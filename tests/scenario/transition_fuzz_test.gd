extends "res://tests/test_case.gd"
## 100 random sequences of player actions on a landed ship. After every tick the session must be
## in a legal state (consistent mode/state, airlock invariant, walker on valid ground) and the
## player must never jump more than 0.5 m relative to the ship in one tick. This checks legality and
## continuity; it does not prove "no softlock" (that needs a planner), which the full-loop test covers
## for the intended path.

const DELTA := 1.0 / 60.0
const SEQUENCES := 100
const ACTIONS_PER_SEQUENCE := 60


func _landed_session() -> GameSession:
	var planet := PlanetBody.new()
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	var direction := Vector3(0.3, 0.5, 0.8).normalized()
	var ground := planet.surface_radius_xyz(direction.x, direction.y, direction.z)
	ship.state.position = WorldPos.new(planet.frame_id, direction.x * (ground + 2.1), direction.y * (ground + 2.1), direction.z * (ground + 2.1))
	ship.state.basis = Basis.looking_at(Vector3.UP.cross(direction).normalized(), direction)
	var session := GameSession.new(planet, ship, PilotSource.new())
	session.crew.add_member(session.systems, &"mara", &"engineer", &"reactor_panel") # two crew wander the ship throughout
	session.crew.add_member(session.systems, &"kit", &"gunner", &"gunner_seat")
	for tick in 120:
		session.tick(DELTA, OnFootCommand.new())
	return session


func test_random_action_sequences_stay_legal_and_continuous() -> void:
	var rng := SeedRng.new(2026)
	var modes_seen := {}
	var worst_step := 0.0
	var first_problem := ""
	for sequence in SEQUENCES:
		var session := _landed_session()
		if not session.ship.state.landed:
			session.ship.free()
			continue
		var previous := ShipFrame.local_from_world(session.ship.state, session.player_world_position())
		for action in ACTIONS_PER_SEQUENCE:
			if rng.next_float() < 0.3:
				session.interact()
			if rng.next_float() < 0.2:
				session.crew.order_to_station(session.systems, [&"mara", &"kit"][rng.next_int_in_range(0, 1)], [&"reactor_panel", &"gunner_seat", &"extinguisher_locker", &"engine_station"][rng.next_int_in_range(0, 3)])
			var command := OnFootCommand.new()
			command.move = Vector2(rng.next_float() * 2.0 - 1.0, rng.next_float() * 2.0 - 1.0)
			command.run = rng.next_float() < 0.3
			command.jump = rng.next_float() < 0.1
			var turn := (rng.next_float() - 0.5) * 0.3
			for tick in rng.next_int_in_range(5, 40):
				command.yaw_delta = turn
				session.tick(DELTA, command)
				modes_seen[session.mode] = true
				var problem := session.validate()
				if problem != "" and first_problem == "":
					first_problem = "sequence %d: %s | mode %d pos %s doors cockpit %.2f inner %.2f outer %.2f walkway %d ramp_walkable %s" % [sequence, problem, session.mode, str(session.interior_body.position), (session.systems.layout.portals[&"cockpit_door"] as Portal).open_factor, session.systems.airlock.inner.open_factor, session.systems.airlock.outer.open_factor, session.systems.walkway.state, str(session.systems.layout.ramp_walkable)]
				var local := ShipFrame.local_from_world(session.ship.state, session.player_world_position())
				worst_step = maxf(worst_step, local.distance_to(previous))
				previous = local
		session.ship.free()
	assert_eq(first_problem, "", "illegal state reached")
	assert_true(worst_step <= 0.5, "worst per-tick movement: %f m" % worst_step)
	assert_true(modes_seen.size() >= 3, "the fuzz visited several modes: %s" % str(modes_seen.keys()))
