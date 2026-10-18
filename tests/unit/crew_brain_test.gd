extends "res://tests/test_case.gd"
## N6: the crew choose sensible work on their own, obey captain's orders, and fight with the turret.

const TICK := 1.0 / 60.0


class FakeEnemy extends ProjectileSim.Target:
	var position: WorldPos
	var health := 1.0

	func _init(at: WorldPos) -> void:
		position = at

	func combat_position() -> WorldPos:
		return position

	func combat_radius() -> float:
		return 20.0

	func team_id() -> int:
		return 1

	func apply_damage(amount: float, _source: Object) -> void:
		health = maxf(0.0, health - amount)

	func is_alive() -> bool:
		return health > 0.0


func _session() -> GameSession:
	var planet := PlanetBody.new()
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	var direction := Vector3(0.3, 0.5, 0.8).normalized()
	var radius := planet.surface_radius_xyz(direction.x, direction.y, direction.z) + 2.1
	ship.state.position = WorldPos.new(planet.frame_id, direction.x * radius, direction.y * radius, direction.z * radius)
	ship.state.basis = Basis.looking_at(Vector3.UP.cross(direction).normalized(), direction)
	var session := GameSession.new(planet, ship, PilotSource.new())
	session.crew.add_member(session.systems, &"mara", &"engineer", &"reactor_panel")
	session.crew.add_member(session.systems, &"kit", &"gunner", &"gunner_seat")
	for tick in 120:
		session.tick(TICK, OnFootCommand.new())
	return session


func _run(session: GameSession, seconds: float, stop: Callable = Callable()) -> float:
	for tick in int(seconds * 60.0):
		session.tick(TICK, OnFootCommand.new())
		if stop.is_valid() and stop.call():
			return tick * TICK
	return -1.0


func _enemy_ahead(session: GameSession, distance: float) -> FakeEnemy:
	var enemy := FakeEnemy.new(session.ship.state.position.offset_by(session.ship.state.basis.y * 150.0 - session.ship.state.basis.z * distance))
	session.enemy_targets.append(enemy)
	return enemy


func test_engineer_puts_out_a_fire_in_their_own_room() -> void:
	var session := _session()
	session.systems.hazards.ignite(&"engineering")
	var seconds := _run(session, 90.0, func(): return not session.systems.hazards.any_fire())
	assert_true(seconds >= 0.0, "fire out within 90 s")
	assert_eq(session.validate(), "")
	session.ship.free()


func test_engineer_goes_through_doors_to_a_fire_in_another_room() -> void:
	var session := _session()
	session.systems.hazards.ignite(&"cargo")
	var seconds := _run(session, 120.0, func(): return not session.systems.hazards.any_fire())
	assert_true(seconds >= 0.0, "cargo fire out within 120 s (engineer had to open two doors)")
	assert_true((session.systems.layout.portals[&"turret_door"] as Portal).target_open or (session.systems.layout.portals[&"cargo_door"] as Portal).target_open, "the doors were opened")
	session.ship.free()


func test_engineer_repairs_a_damaged_engine_until_it_is_fully_fixed() -> void:
	var session := _session()
	session.systems.subsystems.health[ShipSubsystems.Id.ENGINES] = 0.3
	var seconds := _run(session, 120.0, func(): return session.systems.subsystems.value(ShipSubsystems.Id.ENGINES) >= 0.999)
	assert_true(seconds >= 0.0, "engines fully repaired within 120 s")
	session.ship.free()


func test_engineer_restarts_a_tripped_reactor_before_the_automatic_restart() -> void:
	var session := _session()
	session.systems.power.temperature = 0.999
	session.systems.set_demand(_full_demand())
	session.systems.power.update(1.0)
	assert_true(session.systems.power.is_shut_down())
	session.systems.power.temperature = 0.4
	var seconds := _run(session, 10.0, func(): return not session.systems.power.is_shut_down())
	assert_true(seconds >= 0.0 and seconds < 4.0, "restarted promptly: %f" % seconds)
	session.ship.free()


func _full_demand() -> PilotCommand:
	var demand := PilotCommand.new()
	demand.thrust = Vector3(0, 0, -1)
	demand.boost = true
	demand.fire = true
	return demand


func test_engineer_vents_coolant_when_the_core_runs_hot() -> void:
	var session := _session()
	session.systems.power.temperature = 0.9
	var coolant_before := session.systems.power.coolant
	_run(session, 4.0)
	assert_true(session.systems.power.coolant < coolant_before, "coolant was vented")
	session.ship.free()


func test_gunner_destroys_a_hostile_with_the_turret() -> void:
	var session := _session()
	var enemy := _enemy_ahead(session, 600.0)
	var seconds := _run(session, 40.0, func(): return not enemy.is_alive())
	assert_true(seconds >= 0.0, "hostile destroyed within 40 s (health %f)" % enemy.health)
	assert_eq(session.crew_brain.goals[&"kit"], CrewBrain.Goal.FIGHT)
	session.ship.free()


func test_no_gunner_in_the_seat_means_the_turret_stays_silent() -> void:
	var session := _session()
	session.systems.seats.stand(&"kit")
	session.crew.member(&"kit").seat_id = &""
	session.crew.member(&"kit").body.place(Vector3(0, -0.9, 3.8), 0.0)
	var enemy := _enemy_ahead(session, 600.0)
	session.crew.members.erase(session.crew.member(&"kit")) # nobody to man it
	_run(session, 10.0)
	assert_eq(enemy.health, 1.0, "unmanned turret did not fire")
	session.ship.free()


func test_captains_order_outranks_scores_until_done() -> void:
	var session := _session()
	for id in 4:
		session.systems.subsystems.health[id] = 0.5
	session.systems.hazards.ignite(&"engineering")
	session.order_crew_fix()
	_run(session, 3.0)
	assert_eq(session.crew_brain.goals[&"mara"], CrewBrain.Goal.ORDER_FIX, "obeys the order despite the fire")
	assert_eq(session.crew.member(&"mara").extinguisher_charges, 0, "did not go for the extinguisher")
	session.systems.hazards.extinguish(&"engineering", 1.0)
	var seconds := _run(session, 90.0, func(): return session.crew_brain.orders.is_empty())
	assert_true(seconds >= 0.0, "order completed when everything was repaired")
	assert_true(session.systems.subsystems.is_undamaged())
	_run(session, 2.0)
	assert_true(session.crew_brain.goals[&"mara"] != CrewBrain.Goal.ORDER_FIX, "back to their own judgement")
	session.ship.free()


func test_turret_order_toggles_and_power_presets_cycle() -> void:
	var session := _session()
	session.order_crew_turret()
	_run(session, 1.0)
	assert_eq(session.crew_brain.goals[&"kit"], CrewBrain.Goal.ORDER_TURRET)
	session.order_crew_turret()
	_run(session, 1.0)
	assert_true(session.crew_brain.goals[&"kit"] != CrewBrain.Goal.ORDER_TURRET, "second press cancels")
	session.cycle_power_preset()
	assert_near(session.systems.power.limit(ShipPower.Conduit.WEAPONS), 0.5, 1e-9, "engines preset throttles weapons")
	session.cycle_power_preset()
	assert_near(session.systems.power.limit(ShipPower.Conduit.ENGINES), 0.6, 1e-9, "weapons preset throttles engines")
	session.cycle_power_preset()
	assert_near(session.systems.power.limit(ShipPower.Conduit.WEAPONS), 1.0, 1e-9, "back to balanced")
	session.ship.free()


func test_crew_do_not_flip_flop_over_a_ten_minute_run_of_trouble() -> void:
	var session := _session()
	var rng := SeedRng.new(77)
	var rooms := [&"engineering", &"cabin", &"turret_room", &"cargo"]
	var enemies: Array = []
	var problem := ""
	for tick in 60 * 600:
		if tick % (60 * 20) == 0:
			session.systems.hazards.ignite(rooms[rng.next_int_in_range(0, 3)])
		if tick % (60 * 45) == 0:
			enemies.append(_enemy_ahead(session, 700.0))
		if tick % (60 * 90) == 0:
			session.systems.subsystems.health[rng.next_int_in_range(0, 3)] = 0.4
		session.tick(TICK, OnFootCommand.new())
		if tick % 60 == 0 and problem == "":
			problem = session.validate()
	assert_eq(problem, "", "state stayed legal")
	for person in session.crew.members:
		var changes: int = session.crew_brain.goal_changes.get(person.id, 0)
		assert_true(changes <= 100, "%s changed goals %d times in 10 minutes" % [person.id, changes])
	session.ship.free()
