extends "res://tests/test_case.gd"


func test_v1_fixture_migrates_to_v2_with_empty_discoveries() -> void:
	var manager := SaveManager.new(ProjectSettings.globalize_path("res://tests/fixtures/saves"))
	var loaded := manager.load_slot("v1_landed_seated")
	assert_true(loaded["ok"], loaded["error"])
	var data: Dictionary = loaded["data"]
	assert_eq(int(data["save_version"]), SaveGame.SAVE_VERSION, "migrated up to the current version")
	assert_true(data.has("pois"))
	assert_eq((data["pois"]["discovered"] as Array).size(), 0)


func test_discoveries_survive_save_and_load() -> void:
	var planet := PlanetBody.new()
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	var session := GameSession.new(planet, ship, PilotSource.new())
	for poi_name in ["Wreck 01-001", "Beacon 02-002"]:
		var instance := PoiInstance.new()
		instance.id = StringName("poi_" + poi_name)
		instance.display_name = poi_name
		session.discovery_log.try_discover(instance)
	var data := SaveGame.capture(session, 42)
	var directory := "user://test_saves_v2"
	var manager := SaveManager.new(directory)
	assert_eq(manager.save("pois", data), "")
	var loaded := manager.load_slot("pois")
	assert_true(loaded["ok"])
	var fresh_ship := Ship.new()
	fresh_ship.planet = planet
	fresh_ship.render_origin = WorldPos.new(planet.frame_id)
	var fresh := GameSession.new(planet, fresh_ship, PilotSource.new())
	assert_eq(SaveGame.restore(fresh, loaded["data"]), "")
	assert_eq(fresh.discovery_log.count(), 2)
	assert_true(fresh.discovery_log.is_discovered(&"poi_Wreck 01-001"))
	assert_eq(fresh.discovery_log.order, session.discovery_log.order)
	ship.free()
	fresh_ship.free()
