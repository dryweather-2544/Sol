extends "res://tests/test_case.gd"
## N4: room air and fire, the extinguisher, and the reactor panel requests.

const TICK := 1.0 / 60.0
const SAVE_DIRECTORY := "user://test_saves_hazards"


func _run(hazards: ShipHazards, layout: InteriorLayout, seconds: float, life_support := 1.0) -> void:
	for tick in int(seconds * 60.0):
		hazards.update(TICK, layout, life_support)


func _open(layout: InteriorLayout, portal_id: StringName) -> void:
	(layout.portals[portal_id] as Portal).target_open = true
	(layout.portals[portal_id] as Portal).open_factor = 1.0


func test_fire_behind_closed_doors_stays_in_its_room() -> void:
	var layout := InteriorLayout.player_ship()
	var hazards := ShipHazards.new(layout)
	assert_true(hazards.ignite(&"engineering"))
	_run(hazards, layout, 300.0)
	for room_id in [&"cabin", &"turret_room", &"cockpit", &"cargo"]:
		assert_eq(hazards.fire_in(room_id), 0.0, "%s stayed clear behind closed doors" % room_id)


func test_fire_spreads_through_an_open_door() -> void:
	var layout := InteriorLayout.player_ship()
	_open(layout, &"engineering_door")
	var hazards := ShipHazards.new(layout)
	hazards.ignite(&"engineering")
	_run(hazards, layout, 90.0)
	assert_true(hazards.fire_in(&"cabin") > 0.0, "the cabin caught fire through the open door")
	assert_eq(hazards.fire_in(&"turret_room"), 0.0, "but not through the closed door beyond")


func test_fire_in_a_sealed_room_starves_when_air_runs_low_and_goes_out() -> void:
	var layout := InteriorLayout.player_ship()
	var hazards := ShipHazards.new(layout)
	hazards.ignite(&"turret_room")
	_run(hazards, layout, 600.0, 0.0) # life support off
	assert_eq(hazards.fire_in(&"turret_room"), 0.0, "burned itself out")
	assert_true(hazards.oxygen_in(&"turret_room") < ShipHazards.LOW_OXYGEN, "and left the room without air: %f" % hazards.oxygen_in(&"turret_room"))
	assert_true(not hazards.is_breathable(&"turret_room"))


func test_life_support_refills_a_thin_room() -> void:
	var layout := InteriorLayout.player_ship()
	var hazards := ShipHazards.new(layout)
	hazards.oxygen[&"cabin"] = 0.1
	_run(hazards, layout, 60.0, 1.0)
	assert_true(hazards.oxygen_in(&"cabin") > 0.1, "life support refills a thin room: %f" % hazards.oxygen_in(&"cabin"))


func test_open_door_equalises_air_between_rooms() -> void:
	var layout := InteriorLayout.player_ship()
	_open(layout, &"engineering_door")
	var hazards := ShipHazards.new(layout)
	hazards.oxygen[&"cabin"] = 0.0
	_run(hazards, layout, 20.0, 0.0)
	assert_true(hazards.oxygen_in(&"cabin") > 0.3, "air flowed in: %f" % hazards.oxygen_in(&"cabin"))
	assert_true(hazards.oxygen_in(&"engineering") < 0.8, "and left the other room: %f" % hazards.oxygen_in(&"engineering"))
	assert_near(hazards.oxygen_in(&"cabin") + hazards.oxygen_in(&"engineering"), 1.0, 1e-6, "air is conserved without life support or fire")


func test_extinguisher_sprays_put_the_fire_out() -> void:
	var layout := InteriorLayout.player_ship()
	var hazards := ShipHazards.new(layout)
	hazards.ignite(&"cabin")
	_run(hazards, layout, 30.0)
	var sprays := 0
	while hazards.fire_in(&"cabin") > 0.0 and sprays < 10:
		assert_true(hazards.extinguish(&"cabin", 0.35))
		sprays += 1
	assert_true(sprays <= 4, "a few sprays do it: %d" % sprays)
	assert_true(not hazards.extinguish(&"cabin", 0.35), "nothing left to put out")


func test_fire_burns_the_subsystems_in_its_room() -> void:
	var layout := InteriorLayout.player_ship()
	var hazards := ShipHazards.new(layout)
	hazards.ignite(&"engineering")
	var total := {}
	for tick in 60 * 60:
		var burn := hazards.update(TICK, layout, 1.0)
		for id in burn:
			total[id] = total.get(id, 0.0) + burn[id]
	assert_true(total.get(ShipSubsystems.Id.REACTOR, 0.0) > 0.1, "reactor burned: %s" % str(total))
	assert_true(total.get(ShipSubsystems.Id.ENGINES, 0.0) > 0.1, "engines burned")
	assert_true(not total.has(ShipSubsystems.Id.WEAPONS), "weapons are in another room")


func test_enough_subsystem_damage_starts_a_fire_deterministically() -> void:
	var first := ShipSystems.new()
	var second := ShipSystems.new()
	for systems in [first, second]:
		systems.damage_subsystem(ShipSubsystems.Id.ENGINES, 0.06)
		systems.damage_subsystem(ShipSubsystems.Id.REACTOR, 0.05)
		assert_true(not systems.hazards.any_fire(), "not yet")
		systems.damage_subsystem(ShipSubsystems.Id.ENGINES, 0.05)
		assert_true(systems.hazards.fire_in(&"engineering") > 0.0, "third hit starts a fire in engineering")
	for tick in 600:
		first.update(TICK, ShipState.new())
		second.update(TICK, ShipState.new())
	assert_eq(first.hazards.to_dictionary(), second.hazards.to_dictionary(), "same inputs, same state")
	assert_eq(first.subsystems.to_array(), second.subsystems.to_array())


func test_reactor_panel_requests_go_through_the_actor_seam() -> void:
	var systems := ShipSystems.new()
	assert_eq(systems.request_set_limit(&"engineer_bot", ShipPower.Conduit.WEAPONS, 0.4), "")
	assert_near(systems.power.limit(ShipPower.Conduit.WEAPONS), 0.4, 1e-9)
	assert_eq(systems.request_restart_reactor(&"engineer_bot"), "Reactor is already running")
	for vent in 4:
		assert_eq(systems.request_vent_coolant(&"engineer_bot"), "")
	assert_eq(systems.request_vent_coolant(&"engineer_bot"), "No coolant left")


func test_panel_can_restart_a_cooling_reactor_before_the_automatic_restart() -> void:
	var systems := ShipSystems.new()
	systems.power.temperature = 0.999
	var demand := PilotCommand.new()
	demand.thrust = Vector3(0, 0, -1)
	demand.boost = true
	demand.fire = true
	systems.set_demand(demand)
	systems.update(1.0, ShipState.new())
	if not systems.power.is_shut_down():
		systems.power.temperature = 1.0
		systems.update(TICK, ShipState.new())
	assert_true(systems.power.is_shut_down(), "tripped")
	systems.power.temperature = 0.4 # cool enough for the panel, not yet for the automatic restart
	systems.update(0.0, ShipState.new())
	assert_true(systems.power.is_shut_down(), "automatic restart waits for 0.2")
	assert_eq(systems.request_restart_reactor(&"engineer_bot"), "")
	assert_true(not systems.power.is_shut_down())


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
	for tick in 120:
		session.tick(TICK, OnFootCommand.new())
	return session


func test_player_takes_the_extinguisher_and_fights_a_fire_in_their_room() -> void:
	var session := _session()
	session.interact() # stand up
	_open(session.systems.layout, &"engineering_door")
	var locker := session.systems.layout.standing_spot_for(&"extinguisher_locker")
	session.interior_body.place(Vector3(locker.x, -0.9, locker.y), 0.0) # at the locker in engineering
	assert_eq(session.systems.layout.nearest_interaction(session.interior_body.position), &"extinguisher_locker")
	session.interact()
	assert_eq(session.extinguisher_charges, GameSession.EXTINGUISHER_CHARGES)
	session.interior_body.place(Vector3(0.0, -0.9, 1.5), 0.0)
	session.systems.hazards.ignite(&"engineering")
	session.tick(TICK, OnFootCommand.new())
	assert_true(session.alert_text().begins_with("FIRE in engineering"), session.alert_text())
	assert_eq(session.prompt(), "FIRE in the engineering!", "the alert message shows first")
	for tick in 60 * 6:
		session.tick(TICK, OnFootCommand.new())
	assert_true(session.prompt().begins_with("F: spray"), session.prompt())
	var sprays := 0
	while session.systems.hazards.fire_in(&"engineering") > 0.0 and sprays < 10:
		session.interact()
		sprays += 1
	assert_eq(session.systems.hazards.fire_in(&"engineering"), 0.0, "fire out")
	assert_eq(session.extinguisher_charges, GameSession.EXTINGUISHER_CHARGES - sprays)
	session.ship.free()


func test_breathing_in_a_room_without_air_uses_the_suit_tank() -> void:
	var session := _session()
	session.interact()
	session.interior_body.place(Vector3(0.0, -0.9, 1.5), 0.0)
	session.systems.hazards.oxygen[&"engineering"] = 0.0
	var before := session.suit.oxygen
	for tick in 60 * 10:
		session.systems.hazards.oxygen[&"engineering"] = 0.0
		session.tick(TICK, OnFootCommand.new())
	assert_true(session.suit.oxygen < before, "suit tank drained in the airless room")
	session.ship.free()


func test_fire_and_extinguisher_survive_a_save_round_trip() -> void:
	var session := _session()
	session.systems.hazards.ignite(&"cabin")
	session.systems.hazards.oxygen[&"cargo"] = 0.42
	session.extinguisher_charges = 3
	var manager := SaveManager.new(SAVE_DIRECTORY)
	assert_eq(manager.save("hazards", SaveGame.capture(session, 42)), "")
	var loaded := manager.load_slot("hazards")
	assert_true(loaded["ok"], loaded["error"])
	var fresh := _session()
	assert_eq(SaveGame.restore(fresh, loaded["data"]), "")
	assert_near(fresh.systems.hazards.fire_in(&"cabin"), ShipHazards.FIRE_START_INTENSITY, 1e-9)
	assert_near(fresh.systems.hazards.oxygen_in(&"cargo"), 0.42, 1e-9)
	assert_eq(fresh.extinguisher_charges, 3)
	session.ship.free()
	fresh.ship.free()
