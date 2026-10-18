extends "res://tests/test_case.gd"
## The pieces of the Mayday mission: save v11, the repair cap, the one-shot ambush hit, the pinned beacon.

const TICK := 1.0 / 60.0


func _session() -> GameSession:
	var planet := PlanetBody.new()
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	var direction := Vector3(0.3, 0.5, 0.8).normalized()
	var radius := planet.surface_radius_xyz(direction.x, direction.y, direction.z) + 2.1
	ship.state.position = WorldPos.new(planet.frame_id, direction.x * radius, direction.y * radius, direction.z * radius)
	ship.state.basis = Basis.looking_at(Vector3.UP.cross(direction).normalized(), direction)
	return GameSession.new(planet, ship, PilotSource.new())


func test_v10_fixture_migrates_with_the_objective_shifted_past_the_new_mission() -> void:
	var manager := SaveManager.new(ProjectSettings.globalize_path("res://tests/fixtures/saves"))
	var loaded := manager.load_slot("v10_crew_hurt")
	assert_true(loaded["ok"], loaded["error"])
	var data: Dictionary = loaded["data"]
	assert_eq(int(data["save_version"]), SaveGame.SAVE_VERSION)
	assert_eq(int(data["progress"]["objective"]), 7, "old 'reach Verdant' (4) is now step 7")
	var session := _session()
	assert_eq(SaveGame.restore(session, data), "")
	assert_eq(session.progress.current_id(), "reach_far_world")
	assert_near(session.systems.subsystems.value(ShipSubsystems.Id.ENGINES), 0.5, 1e-9, "damage from the v10 save kept")
	assert_eq(session.crew.members.size(), 1, "the saved crew member kept")
	assert_eq(session.systems.subsystems.cap, [1.0, 1.0, 1.0, 1.0], "no caps in an old save")
	assert_true(not session.progress.ambush_started)
	session.ship.free()


func test_objectives_before_the_mission_are_not_shifted() -> void:
	var migrated: Dictionary = SaveMigrations.migrate({"save_version": 10, "progress": {"objective": 2}, "player": {}})["data"]
	assert_eq(int(migrated["progress"]["objective"]), 2)


func test_repairs_stop_at_the_cap_and_that_counts_as_fully_repaired() -> void:
	var subsystems := ShipSubsystems.new()
	subsystems.cap[ShipSubsystems.Id.ENGINES] = 0.6
	subsystems.health[ShipSubsystems.Id.ENGINES] = 0.2
	assert_true(not subsystems.is_undamaged())
	for step in 100:
		subsystems.repair_worst(0.1)
	assert_near(subsystems.value(ShipSubsystems.Id.ENGINES), 0.6, 1e-9)
	assert_true(subsystems.is_undamaged(), "at the cap nothing is left to repair")
	assert_eq(subsystems.repair_worst(0.1), "")


func test_the_ambush_hit_is_guaranteed_once_and_only_when_armed() -> void:
	var session := _session()
	var attacker := Ship.new()
	attacker.state.position = session.ship.state.position.offset_by(Vector3(0, 0, 300))
	var combatant := ShipCombatant.new(session.ship, 0)
	combatant.apply_damage(0.001, attacker)
	assert_true(not session.systems.hazards.any_fire(), "not armed: a tiny hit does nothing special")
	session.systems.ambush_armed = true
	combatant.apply_damage(0.001, attacker)
	assert_true(session.systems.hazards.fire_in(&"engineering") > 0.0, "armed: fire in engineering")
	assert_near(session.systems.subsystems.cap[ShipSubsystems.Id.ENGINES], ShipSystems.ENGINE_CAP_AFTER_AMBUSH, 1e-9)
	assert_true(session.systems.subsystems.value(ShipSubsystems.Id.ENGINES) <= 0.5)
	assert_true(not session.systems.ambush_armed)
	var engines_after := session.systems.subsystems.value(ShipSubsystems.Id.ENGINES)
	combatant.apply_damage(0.001, attacker)
	assert_true(session.systems.subsystems.value(ShipSubsystems.Id.ENGINES) >= engines_after - 0.01, "the second hit is an ordinary hit")
	session.ship.free()
	attacker.free()


func test_engine_station_refuses_without_a_coupling_and_explains() -> void:
	var session := _session()
	session.interact() # stand up
	var spot := session.systems.layout.standing_spot_for(&"engine_station")
	session.interior_body.place(Vector3(spot.x, session.systems.layout.floor_y, spot.y), 0.0)
	session.interact()
	assert_true(session.message.contains("nominal"), session.message)
	session.systems.subsystems.cap[ShipSubsystems.Id.ENGINES] = 0.6
	session.interact()
	assert_true(session.message.contains("need a new one"), session.message)
	session.inventory.add(ItemDefinition.ENGINE_COUPLING, 1)
	session.interact()
	assert_true(session.progress.coupling_installed)
	session.ship.free()


func test_pinned_beacon_is_planned_like_any_poi_and_sits_on_the_ground() -> void:
	var planet := PlanetBody.new()
	var planner := PoiPlanner.new(planet, 5)
	var direction := Vector3(0.3, 0.5, 0.8).normalized()
	var beacon := planner.pin_beacon(ProgressTracker.BEACON_ID, direction, 77)
	assert_eq(beacon.type, PoiDefinition.Type.BEACON)
	assert_eq(planner.pin_beacon(ProgressTracker.BEACON_ID, Vector3.UP, 1), beacon, "pinning twice keeps the first")
	var found := planner.plan_region(beacon.position, 1000.0)
	assert_true(found.has(beacon), "plan_region reports it")
	var ground := planet.surface_radius_xyz(direction.x, direction.y, direction.z)
	assert_near(Vector3(beacon.position.x, beacon.position.y, beacon.position.z).length(), ground, 1.0) # Vector3 is 32-bit


func test_arriving_at_selene_starts_the_ambush_once_and_points_at_a_beacon_below() -> void:
	var session := _session()
	session.progress.current = 3
	var emitted := []
	session.ambush_requested.connect(func(direction: Vector3): emitted.append(direction))
	session.progress.update(session, &"planet")
	assert_eq(emitted.size(), 0, "not at Selene yet")
	session.progress.update(session, &"selene")
	session.progress.update(session, &"selene")
	assert_eq(emitted.size(), 1, "once")
	var ship_up := Vector3(session.ship.state.position.x, session.ship.state.position.y, session.ship.state.position.z).normalized()
	var angle := rad_to_deg(emitted[0].angle_to(ship_up))
	assert_true(angle > 0.0 and emitted[0].length() > 0.99)
	assert_near(deg_to_rad(angle) * session.planet.radius, ProgressTracker.BEACON_DISTANCE_METRES, 50.0, "about 6 km from the arrival point")
	session.ship.free()
