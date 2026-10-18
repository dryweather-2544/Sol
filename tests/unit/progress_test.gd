extends "res://tests/test_case.gd"

const DELTA := 1.0 / 60.0


func _session() -> GameSession:
	var planet := PlanetBody.new()
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	return GameSession.new(planet, ship, PilotSource.new())


func _poi(poi_name: String) -> PoiInstance:
	var instance := PoiInstance.new()
	instance.id = StringName("poi_" + poi_name)
	instance.display_name = poi_name
	return instance


func test_objectives_advance_in_order_one_at_a_time() -> void:
	var session := _session()
	var progress := session.progress
	assert_eq(progress.current, 0)
	for index in 3:
		session.discovery_log.try_discover(_poi("p%d" % index))
	progress.update(session, &"planet")
	assert_eq(progress.current, 1, "three discoveries complete the first objective")
	progress.update(session, &"planet")
	assert_eq(progress.current, 1, "the next one needs a cleared outpost")
	session.cleared_log.mark_looted(&"poi_outpost_1")
	progress.update(session, &"planet")
	assert_eq(progress.current, 2)
	progress.update(session, &"planet")
	assert_eq(progress.current, 2, "installing the coil is its own step")
	session.ship.free()


func test_warp_coil_install_flow_and_gating_factor() -> void:
	var session := _session()
	var progress := session.progress
	assert_near(progress.warp_speed_factor(), 0.0005, 1e-12, "dead drive")
	assert_true(progress.install_warp_coil(session).contains("need"))
	session.inventory.add(ItemDefinition.WARP_COIL, 1)
	session.ship.state.landed = true
	var message := session.use_item(ItemDefinition.WARP_COIL)
	assert_true(message.contains("installed"), message)
	assert_true(progress.warp_installed)
	assert_eq(session.inventory.count(ItemDefinition.WARP_COIL), 0, "the coil is consumed")
	assert_eq(progress.warp_speed_factor(), 1.0)
	assert_true(progress.install_warp_coil(session).contains("already"))
	session.ship.free()


func test_open_space_cruise_is_crippled_without_the_warp_drive() -> void:
	var system := StarSystem.default_system()
	var navigator := SystemNavigator.new(system)
	var ship_state := ShipState.new()
	ship_state.position = WorldPos.new(StarSystem.SYSTEM_FRAME, 4.0e8, 0.0, 0.0)
	var environment := FlightEnvironment.new()
	navigator.warp_factor = 0.0005
	navigator.fill_environment(ship_state, environment)
	var crippled := environment.cruise_speed_limit
	navigator.warp_factor = 1.0
	navigator.fill_environment(ship_state, environment)
	assert_true(crippled < 20000.0 and environment.cruise_speed_limit > 1.0e6, "without drive %f m/s, with %f m/s" % [crippled, environment.cruise_speed_limit])


func test_story_objectives_complete_by_landing_on_the_target_worlds() -> void:
	var session := _session()
	var progress := session.progress
	progress.current = 3
	session.ship.state.landed = true
	progress.update(session, &"planet")
	assert_eq(progress.current, 3, "landing on the home world is not Selene")
	progress.update(session, &"selene")
	assert_eq(progress.current, 4, "landing on Selene starts the Mayday errand")
	progress.current = 7
	progress.update(session, &"verdant")
	assert_true(progress.is_finished())
	assert_true(progress.current_text().contains("complete"))
	session.ship.free()


func test_progress_survives_a_save_and_old_saves_keep_open_space() -> void:
	var session := _session()
	session.progress.current = 2
	session.progress.warp_installed = true
	var data := SaveGame.capture(session, 42)
	assert_eq(data["progress"]["objective"], 2)
	var migrated := SaveMigrations.migrate({"save_version": 6, "ship": {}, "player": {}, "pois": {"generation_version": 1, "discovered": []}})
	assert_true(migrated["ok"])
	assert_eq(migrated["data"]["progress"]["warp_installed"], true, "players of older saves are not locked out of open space")
	session.ship.free()
