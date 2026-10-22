extends "res://tests/test_case.gd"
## The exploration loop: minor sites, the scanner, investigation, the exploration log and saving.

const DELTA := 1.0 / 60.0


func _planner(minor_density: float) -> PoiPlanner:
	var planner := PoiPlanner.new(PlanetBody.new(), 99, 0.22)
	planner.minor_density = minor_density
	return planner


func _center() -> WorldPos:
	var planet := PlanetBody.new()
	var direction := Vector3(0.3, 0.5, 0.8).normalized()
	var ground := planet.surface_radius_xyz(direction.x, direction.y, direction.z)
	return WorldPos.new(&"planet", direction.x * ground, direction.y * ground, direction.z * ground)


func _minor_instances(planner: PoiPlanner) -> Array[PoiInstance]:
	var result: Array[PoiInstance] = []
	for instance in planner.plan_region(_center(), 20000.0):
		if PoiDefinition.is_minor(instance.type):
			result.append(instance)
	return result


func _flat_session_beside(type: int, seed_value: int = 777) -> Array:
	var planet := PlanetBody.new()
	planet.height_override = func(_dx: float, _dy: float, _dz: float) -> float: return 0.0
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	ship.state.position = WorldPos.new(planet.frame_id, 0.0, 0.0, planet.radius + 2.1)
	ship.state.basis = Basis(Vector3.RIGHT, PI / 2.0)
	var session := GameSession.new(planet, ship, PilotSource.new())
	for tick in 120:
		session.tick(DELTA, OnFootCommand.new())
	var poi := PoiInstance.new()
	poi.id = &"site_exploration_test"
	poi.type = type
	poi.seed_value = seed_value
	poi.position = WorldPos.new(planet.frame_id, 60.0, 0.0, planet.radius)
	poi.display_name = "%s 4F-221" % PoiDefinition.TYPE_NAMES[type]
	var frame := PoiBuilder.frame_basis(poi)
	var spot := PoiBuilder.crate_positions(poi)[0]
	session.exterior_body.place_on_ground(planet, poi.position.offset_by(frame.x * (spot.x + 1.0) + frame.z * spot.y), Vector3(1, 0, 0))
	session.restore_mode(GameSession.Mode.OUTSIDE)
	session.nearby_pois = [poi]
	return [session, poi]


func test_minor_sites_have_stable_identities_and_valid_places() -> void:
	var first := _planner(0.6)
	var second := _planner(0.6)
	second.plan_region(_center().offset_by(Vector3(9000, 0, 0)), 8000.0) # plan other cells first
	var sites := _minor_instances(first)
	assert_true(sites.size() > 3, "minor sites exist: %d" % sites.size())
	var again := _minor_instances(second)
	assert_eq(again.size(), sites.size())
	var by_id := {}
	for site in again:
		by_id[site.id] = site
	var types := {}
	for site in sites:
		assert_true(String(site.id).begins_with("site_"), "own id family")
		assert_true(by_id.has(site.id), "same id in another planner")
		assert_eq(by_id[site.id].data_hash(), site.data_hash(), "same type, seed and place")
		assert_near(first.planet.altitude_above_ground(site.position), 0.0, 1e-6, "on the ground")
		types[site.type] = true
	assert_eq(by_id.size(), sites.size(), "ids are unique")
	assert_true(types.size() == 3, "probe, deposit and anomaly all occur: %s" % str(types.keys()))


func test_minor_sites_do_not_move_the_large_pois() -> void:
	var plain := _planner(0.0)
	var with_minor := _planner(0.6)
	var plain_ids := {}
	for instance in plain.plan_region(_center(), 20000.0):
		plain_ids[instance.id] = instance.data_hash()
	var large_with_minor := {}
	for instance in with_minor.plan_region(_center(), 20000.0):
		if not PoiDefinition.is_minor(instance.type):
			large_with_minor[instance.id] = instance.data_hash()
	assert_eq(large_with_minor, plain_ids, "enabling minor sites leaves every original POI exactly as it was")


func test_minor_sites_build_without_beams_or_crate_boxes() -> void:
	var planner := _planner(0.6)
	for site in _minor_instances(planner):
		assert_true(PoiBuilder.build_marker(site) == null, "no beam: the scanner finds it")
		assert_eq(PoiBuilder.crate_positions(site).size(), 1)
		assert_true(PoiBuilder.blockers(site).size() > 0)
		var content := PoiBuilder.build_content(site, planner.planet)
		assert_true(content.get_child_count() > 2, "has props")
		content.free()
		break


func test_bearing_and_direction_words() -> void:
	var viewer := WorldPos.new(&"planet", 0.0, 0.0, 1000.0)
	var forward := Vector3(1, 0, 0)
	assert_near(PoiScanner.bearing_degrees(viewer, forward, Vector3(100, 0, 0)), 0.0, 0.5)
	assert_near(PoiScanner.bearing_degrees(viewer, forward, Vector3(0, -100, 0)), 90.0, 0.5, "right")
	assert_near(PoiScanner.bearing_degrees(viewer, forward, Vector3(0, 100, 0)), -90.0, 0.5, "left")
	assert_eq(PoiScanner.direction_text(0.0), "ahead")
	assert_eq(PoiScanner.direction_text(90.0), "right")
	assert_eq(PoiScanner.direction_text(-135.0), "behind left")
	assert_eq(PoiScanner.direction_text(180.0), "behind")
	assert_eq(PoiScanner.distance_text(640.0), "640 m")
	assert_eq(PoiScanner.distance_text(1450.0), "1.4 km" if "%.1f" % 1.45 == "1.4" else "1.5 km")


func test_scan_pulse_finds_only_sites_in_range_and_hides_what_they_are() -> void:
	var setup := _flat_session_beside(PoiDefinition.Type.DEPOSIT)
	var session: GameSession = setup[0]
	var near_site: PoiInstance = setup[1]
	var far_site := PoiInstance.new()
	far_site.id = &"site_far"
	far_site.type = PoiDefinition.Type.ANOMALY
	far_site.seed_value = 5
	far_site.display_name = "Anomaly 00-000"
	far_site.position = WorldPos.new(near_site.position.frame_id, 6000.0, 0.0, session.planet.radius)
	session.nearby_pois = [near_site, far_site]
	var contacts := session.scan_pulse()
	assert_eq(contacts.size(), 1, "the far site is out of range")
	assert_eq(contacts[0]["id"], near_site.id)
	assert_eq(contacts[0]["status"], PoiScanner.Status.UNKNOWN)
	assert_eq(contacts[0]["label"], PoiDefinition.SIGNAL_NAMES[PoiDefinition.Type.DEPOSIT], "only the class of signal until discovered")
	assert_true(session.discovery_log.is_contact(near_site.id))
	assert_true(not session.discovery_log.is_contact(far_site.id))
	assert_true(not session.discovery_log.is_discovered(near_site.id), "scanning is not discovering")
	assert_true(session.scan_text().contains("mineral"), "readout names the signal class")
	assert_eq(session.scan_pulse().size(), 0, "recharging")
	assert_true(session.message.contains("recharging"))
	for tick in int(PoiScanner.COOLDOWN_SECONDS / DELTA) + 2:
		session.tick(DELTA, OnFootCommand.new())
	assert_eq(session.scan_pulse().size(), 1, "ready again")
	session.ship.free()


func test_the_whole_loop_discover_investigate_reward_once() -> void:
	var setup := _flat_session_beside(PoiDefinition.Type.DEPOSIT)
	var session: GameSession = setup[0]
	var poi: PoiInstance = setup[1]
	session.scan_pulse()
	session.check_discovery(session.nearby_pois)
	assert_true(session.discovery_log.is_discovered(poi.id), "walking up identifies it")
	assert_eq(PoiScanner.status_of(poi, session.discovery_log, session.loot_log), PoiScanner.Status.DISCOVERED)
	session.message_seconds_left = 0.0
	assert_eq(session.prompt().split("\n")[0], "F: survey the deposit")
	var expected := LootTable.roll(poi.seed_value, poi.type, 0)
	var scrap_before := session.inventory.count(ItemDefinition.SCRAP)
	session.interact()
	var scrap_expected := scrap_before
	for entry in expected:
		if entry["item"] == ItemDefinition.SCRAP:
			scrap_expected += entry["count"]
	assert_eq(session.inventory.count(ItemDefinition.SCRAP), scrap_expected, "exactly the seeded reward")
	assert_true(session.loot_log.is_looted(PoiBuilder.crate_id(poi, 0)))
	assert_eq(PoiScanner.status_of(poi, session.discovery_log, session.loot_log), PoiScanner.Status.INVESTIGATED)
	assert_true(session.message.contains("Deposit surveyed"))
	assert_true(session.message.contains(PoiDefinition.finding_text(poi.type, poi.seed_value)))
	var after := session.inventory.to_dictionary()
	session.interact()
	assert_eq(session.inventory.to_dictionary(), after, "investigating twice pays nothing more")
	assert_eq(session.scan_pulse().size(), 0 if session.scan_cooldown > 0.0 else 1)
	session.ship.free()


func test_a_full_inventory_leaves_the_site_uninvestigated() -> void:
	var setup := _flat_session_beside(PoiDefinition.Type.PROBE)
	var session: GameSession = setup[0]
	var poi: PoiInstance = setup[1]
	session.inventory.slot_limit = session.inventory.slots_used()
	session.interact()
	assert_true(not session.loot_log.is_looted(PoiBuilder.crate_id(poi, 0)))
	assert_true(session.message.contains("full"))
	session.ship.free()


func test_every_reward_is_a_real_inventory_item() -> void:
	for type in [PoiDefinition.Type.PROBE, PoiDefinition.Type.DEPOSIT, PoiDefinition.Type.ANOMALY]:
		for seed_value in 30:
			var contents := LootTable.roll(seed_value, type, 0)
			assert_true(contents.size() >= 1)
			for entry in contents:
				assert_true(ItemDefinition.exists(entry["item"]) and entry["count"] >= 1)


func test_save_and_load_keep_discovery_investigation_and_contacts_without_duplicates() -> void:
	var setup := _flat_session_beside(PoiDefinition.Type.PROBE, 31337)
	var session: GameSession = setup[0]
	var poi: PoiInstance = setup[1]
	var other := PoiInstance.new()
	other.id = &"site_other"
	other.type = PoiDefinition.Type.ANOMALY
	other.seed_value = 9
	other.display_name = "Anomaly 09-000"
	other.position = WorldPos.new(poi.position.frame_id, 1500.0, 0.0, session.planet.radius)
	session.nearby_pois = [poi, other]
	session.scan_pulse() # picks up both
	session.check_discovery(session.nearby_pois)
	session.interact()
	var inventory_before := session.inventory.to_dictionary()
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.capture(session, 42))) # as written to disk
	var fresh_setup := _flat_session_beside(PoiDefinition.Type.PROBE, 31337)
	var fresh: GameSession = fresh_setup[0]
	assert_eq(SaveGame.restore(fresh, data), "")
	assert_true(fresh.discovery_log.is_discovered(poi.id))
	assert_true(not fresh.discovery_log.is_discovered(other.id))
	assert_true(fresh.discovery_log.is_contact(other.id), "the unreached contact is remembered")
	assert_true(fresh.loot_log.is_looted(PoiBuilder.crate_id(poi, 0)))
	assert_eq(fresh.inventory.to_dictionary(), inventory_before)
	# Revisit: the same planned site (same id) is not discovered again and pays nothing.
	var revisit: PoiInstance = fresh_setup[1]
	fresh.nearby_pois = [revisit, other]
	var discoveries := []
	fresh.discovery_log.poi_discovered.connect(func(instance: PoiInstance): discoveries.append(instance.id))
	fresh.check_discovery(fresh.nearby_pois)
	assert_eq(discoveries.size(), 0, "no second discovery")
	assert_eq(fresh.discovery_log.count(), 1)
	fresh.message_seconds_left = 0.0
	assert_true(not fresh.prompt().contains("download"), "nothing left to take")
	fresh.interact()
	assert_eq(fresh.inventory.to_dictionary(), inventory_before, "no duplicate reward after loading")
	var rows := ExplorationLog.rows(fresh.discovery_log, fresh.loot_log)
	assert_eq(rows.size(), 1)
	assert_eq(rows[0]["status"], "investigated")
	assert_eq(rows[0]["type_name"], "Research Probe")
	assert_eq(rows[0]["detail"], PoiDefinition.finding_text(PoiDefinition.Type.PROBE, 31337))
	assert_true(rows[0]["reward"] != "", "the recovered items are listed")
	assert_true(rows[0]["location"].begins_with("Planet"))
	assert_true(ExplorationLog.summary(fresh.discovery_log, fresh.loot_log).contains("Signals not yet identified 1"))
	session.ship.free()
	fresh.ship.free()


func test_saves_from_before_the_exploration_log_still_load() -> void:
	var log := DiscoveryLog.new()
	log.restore([{"id": "poi_old_1_2_3", "name": "Wreck 01-002"}])
	assert_true(log.is_discovered(&"poi_old_1_2_3"))
	var rows := ExplorationLog.rows(log, LootLog.new())
	assert_eq(rows.size(), 1)
	assert_eq(rows[0]["status"], "visited", "old entries know nothing about their crates")
	var setup := _flat_session_beside(PoiDefinition.Type.DEPOSIT)
	var session: GameSession = setup[0]
	var data := SaveGame.capture(session, 42)
	data["pois"].erase("scanned")
	assert_eq(SaveGame.restore(session, data), "", "a save with no scanner section loads")
	assert_eq(session.discovery_log.unidentified_contact_count(), 0)
	session.ship.free()


func test_large_sites_report_how_many_crates_are_searched() -> void:
	var wreck := PoiInstance.new()
	wreck.id = &"poi_log_wreck"
	wreck.type = PoiDefinition.Type.WRECK
	wreck.seed_value = 12
	wreck.display_name = "Wreck 0C-001"
	wreck.position = WorldPos.new(&"planet", 0.0, 0.0, 1000.0)
	var log := DiscoveryLog.new()
	var loot := LootLog.new()
	assert_true(log.try_discover(wreck))
	assert_true(not log.try_discover(wreck), "discovery fires once")
	var row := ExplorationLog.rows(log, loot)[0]
	assert_eq(row["status"], "not investigated")
	assert_eq(row["detail"], "0 of 2 crates searched")
	loot.mark_looted(PoiBuilder.crate_id(wreck, 0))
	assert_eq(ExplorationLog.rows(log, loot)[0]["detail"], "1 of 2 crates searched")
	loot.mark_looted(PoiBuilder.crate_id(wreck, 1))
	assert_eq(ExplorationLog.rows(log, loot)[0]["status"], "investigated")
