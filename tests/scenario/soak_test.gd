extends "res://tests/test_case.gd"
## A long randomised play session (two simulated hours) on a landed ship: walking, doors, seat,
## shooting, items, repairs, plus a save -> restore of the live session every few simulated seconds.
## After every tick the state must be legal and every number finite. Finds NaNs, drift and state that
## only breaks after many transitions; it does not judge fun.

const DELTA := 1.0 / 60.0
const TOTAL_TICKS := 60 * 60 * 120
const SAVE_EVERY_TICKS := 60 * 20


func _is_finite_vector(vector: Vector3) -> bool:
	return is_finite(vector.x) and is_finite(vector.y) and is_finite(vector.z)


func _session_on_ground() -> GameSession:
	var planet := PlanetBody.new()
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	var direction := Vector3(0.3, 0.5, 0.8).normalized()
	var ground := planet.surface_radius_xyz(direction.x, direction.y, direction.z)
	ship.state.position = WorldPos.new(planet.frame_id, direction.x * (ground + 2.1), direction.y * (ground + 2.1), direction.z * (ground + 2.1))
	ship.state.basis = Basis.looking_at(Vector3.UP.cross(direction).normalized(), direction)
	var session := GameSession.new(planet, ship, PilotSource.new())
	for tick in 120:
		session.tick(DELTA, OnFootCommand.new())
	return session


func test_two_hours_of_random_play_stays_legal_and_finite() -> void:
	var rng := SeedRng.new(31337)
	var session := _session_on_ground()
	var command := OnFootCommand.new()
	var problem := ""
	var saves := 0
	var modes_seen := {}
	var manager := SaveManager.new("user://test_saves_soak")
	for tick in TOTAL_TICKS:
		if tick % 90 == 0:
			command = OnFootCommand.new()
			command.move = Vector2(rng.next_float() * 2.0 - 1.0, rng.next_float() * 2.0 - 1.0)
			command.run = rng.next_float() < 0.2
			command.jump = rng.next_float() < 0.05
			command.jetpack = command.jump
			var roll := rng.next_float()
			if roll < 0.25:
				session.interact()
			elif roll < 0.35:
				session.player_fire(Vector3(rng.next_float() - 0.5, rng.next_float() - 0.5, rng.next_float() - 0.5).normalized())
			elif roll < 0.4:
				session.use_item(ItemDefinition.OXYGEN_TANK)
			elif roll < 0.42:
				session.suit.oxygen = rng.next_float()
				session.ship.state.hull = clampf(session.ship.state.hull - rng.next_float() * 0.3, 0.05, 1.0)
				session.ship.state.fuel = rng.next_float()
		command.yaw_delta = (rng.next_float() - 0.5) * 0.1
		session.tick(DELTA, command)
		modes_seen[session.mode] = true
		if tick % 60 == 0 and problem == "":
			var found := session.validate()
			if found != "":
				problem = "tick %d: %s" % [tick, found]
			elif not (_is_finite_vector(session.ship.state.velocity) and is_finite(session.ship.state.position.x) and is_finite(session.interior_body.position.x) and is_finite(session.exterior_body.position.x) and is_finite(session.suit.oxygen)):
				problem = "tick %d: a number went NaN or infinite" % tick
		if tick % SAVE_EVERY_TICKS == 0 and tick > 0 and session.mode != GameSession.Mode.SITTING and problem == "":
			if manager.save("soak", SaveGame.capture(session, 42)) != "":
				problem = "tick %d: save failed" % tick
			else:
				var loaded := manager.load_slot("soak")
				if not loaded["ok"] or SaveGame.restore(session, loaded["data"]) != "":
					problem = "tick %d: restore failed (%s)" % [tick, loaded["error"]]
				saves += 1
		if problem != "":
			break
	assert_eq(problem, "", "first problem")
	assert_true(saves > 50, "saved and restored %d times" % saves)
	assert_true(modes_seen.size() >= 3, "visited modes %s" % str(modes_seen.keys()))
	session.ship.free()
