extends "res://tests/test_case.gd"

const DELTA := 1.0 / 60.0


func test_inventory_slots_stacks_and_all_or_nothing_adds() -> void:
	var inventory := Inventory.new()
	inventory.slot_limit = 2
	assert_true(inventory.add(ItemDefinition.FUEL_CELL, 5), "one full stack = one slot")
	assert_eq(inventory.slots_used(), 1)
	assert_true(inventory.add(ItemDefinition.FUEL_CELL, 1), "sixth cell opens a second slot")
	assert_eq(inventory.slots_used(), 2)
	assert_true(not inventory.add(ItemDefinition.SCRAP, 1), "no slot left")
	assert_eq(inventory.count(ItemDefinition.SCRAP), 0, "failed add changes nothing")
	assert_true(inventory.remove(ItemDefinition.FUEL_CELL, 6))
	assert_eq(inventory.slots_used(), 0)
	assert_true(not inventory.remove(ItemDefinition.FUEL_CELL, 1))
	assert_true(not inventory.add(&"not_an_item", 1))


func test_inventory_round_trips_through_a_dictionary() -> void:
	var inventory := Inventory.new()
	inventory.add(ItemDefinition.SCRAP, 17)
	inventory.add(ItemDefinition.DATA_CHIP, 2)
	var copy := Inventory.new()
	copy.restore(inventory.to_dictionary())
	assert_eq(copy.count(ItemDefinition.SCRAP), 17)
	assert_eq(copy.count(ItemDefinition.DATA_CHIP), 2)


func test_loot_is_deterministic_and_varies_by_seed_crate_and_type() -> void:
	var first := LootTable.roll(1234, PoiDefinition.Type.OUTPOST, 0)
	assert_eq(first, LootTable.roll(1234, PoiDefinition.Type.OUTPOST, 0))
	assert_true(first.size() >= 1)
	var different := 0
	for seed_value in 40:
		if LootTable.roll(seed_value, PoiDefinition.Type.WRECK, 0) != first:
			different += 1
	assert_true(different > 25, "loot varies across POIs: %d" % different)
	for entry in first:
		assert_true(ItemDefinition.exists(entry["item"]) and entry["count"] >= 1)


func _session_outside_next_to_a_poi() -> Array:
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
	poi.id = &"poi_items_test"
	poi.type = PoiDefinition.Type.OUTPOST
	poi.seed_value = 4242
	poi.position = WorldPos.new(planet.frame_id, 60.0, 0.0, planet.radius)
	var frame := PoiBuilder.frame_basis(poi)
	var crate := PoiBuilder.crate_positions(poi)[0]
	var crate_world := poi.position.offset_by(frame.x * crate.x + frame.z * crate.y)
	session.exterior_body.place_on_ground(planet, crate_world.offset_by(frame.x * 1.0), Vector3(1, 0, 0))
	session.restore_mode(GameSession.Mode.OUTSIDE)
	session.nearby_pois = [poi]
	return [session, poi]


func test_opening_a_crate_gives_its_seeded_loot_once() -> void:
	var setup := _session_outside_next_to_a_poi()
	var session: GameSession = setup[0]
	var poi: PoiInstance = setup[1]
	var expected := LootTable.roll(poi.seed_value, poi.type, 0)
	assert_eq(session.prompt(), "F: open crate")
	var before := session.inventory.slots_used()
	session.interact()
	for entry in expected:
		assert_true(session.inventory.count(entry["item"]) >= entry["count"], "got %s" % entry["item"])
	assert_true(session.loot_log.is_looted(PoiBuilder.crate_id(poi, 0)))
	var counts_after := session.inventory.to_dictionary()
	session.interact()
	assert_eq(session.inventory.to_dictionary(), counts_after, "an emptied crate gives nothing more")
	session.ship.free()


func test_full_inventory_keeps_the_crate_closed() -> void:
	var setup := _session_outside_next_to_a_poi()
	var session: GameSession = setup[0]
	var poi: PoiInstance = setup[1]
	session.inventory.slot_limit = session.inventory.slots_used()
	session.interact()
	assert_true(not session.loot_log.is_looted(PoiBuilder.crate_id(poi, 0)), "nothing taken, crate stays full")
	assert_true(session.message.contains("full"))
	session.ship.free()


func test_using_items_changes_the_right_state() -> void:
	var setup := _session_outside_next_to_a_poi()
	var session: GameSession = setup[0]
	session.suit.oxygen = 0.2
	session.inventory.add(ItemDefinition.FUEL_CELL, 2)
	session.ship.state.fuel = 0.1
	session.ship.state.hull = 0.3
	session.use_item(ItemDefinition.OXYGEN_TANK)
	assert_eq(session.suit.oxygen, 1.0)
	assert_eq(session.inventory.count(ItemDefinition.OXYGEN_TANK), 0)
	session.exterior_body.place_on_ground(session.planet, session.ship.state.position.offset_by(session.ship.state.basis.x * 40.0), Vector3(1, 0, 0))
	assert_true(session.use_item(ItemDefinition.FUEL_CELL).contains("closer"), "too far from the ship")
	session.exterior_body.place_on_ground(session.planet, session.ship.state.position.offset_by(session.ship.state.basis.x * 8.0), Vector3(1, 0, 0))
	session.use_item(ItemDefinition.FUEL_CELL)
	assert_near(session.ship.state.fuel, 0.6, 1e-9)
	session.use_item(ItemDefinition.REPAIR_KIT)
	assert_near(session.ship.state.hull, 0.8, 1e-9)
	session.ship.free()


func test_empty_tank_blocks_cruise_and_boost_and_cruise_burns_fuel() -> void:
	var ship := Ship.new()
	ship.state.position = WorldPos.new(&"space", 0.0, 0.0, 0.0)
	var cruise := PilotCommand.new()
	cruise.gear = PilotCommand.GEAR_CRUISE
	cruise.thrust = Vector3(0, 0, -1)
	cruise.boost = true
	var commands: Array[PilotCommand] = []
	for tick in 600:
		commands.append(cruise)
	ship.controller.request_control(ScriptedPilotSource.new(commands), &"pilot_seat")
	for tick in 60:
		ship.simulate_tick(DELTA)
	assert_near(ship.state.fuel, 1.0 - 60.0 / 60.0 * (Ship.FUEL_CRUISE_PER_SECOND + Ship.FUEL_BOOST_PER_SECOND), 1e-6, "1 s of cruise+boost")
	assert_eq(ship.state.gear, PilotCommand.GEAR_CRUISE)
	ship.state.fuel = 0.0
	for tick in 300:
		ship.simulate_tick(DELTA)
	assert_eq(ship.state.gear, PilotCommand.GEAR_COMBAT, "no fuel: combat gear only")
	# Momentum is kept (drag only acts above the gear's DragSpeed), so check the drive itself: from a standstill,
	# full thrust with boost held gets combat speed (500 m/s) and no more, never boosted (750).
	ship.state.velocity = Vector3.ZERO
	for tick in 120:
		ship.simulate_tick(DELTA)
	assert_near(ship.state.speed(), 500.0, 0.5, "and no boost: %f" % ship.state.speed())
	ship.free()


func test_warp_gear_burns_more_fuel_than_cruise() -> void:
	var cruise := Ship.new()
	var cruise_command := PilotCommand.new()
	cruise_command.gear = PilotCommand.GEAR_CRUISE
	cruise_command.thrust = Vector3(0, 0, -1)
	var cruise_commands: Array[PilotCommand] = []
	for tick in 60:
		cruise_commands.append(cruise_command)
	cruise.controller.request_control(ScriptedPilotSource.new(cruise_commands), &"pilot_seat")
	for tick in 60:
		cruise.simulate_tick(DELTA)
	var warp := Ship.new()
	var warp_command := PilotCommand.new()
	warp_command.gear = PilotCommand.GEAR_WARP
	warp_command.thrust = Vector3(0, 0, -1)
	var warp_commands: Array[PilotCommand] = []
	for tick in 60:
		warp_commands.append(warp_command)
	warp.controller.request_control(ScriptedPilotSource.new(warp_commands), &"pilot_seat")
	for tick in 60:
		warp.simulate_tick(DELTA)
	assert_near(cruise.state.fuel, 1.0 - Ship.FUEL_CRUISE_PER_SECOND, 1e-6)
	assert_near(warp.state.fuel, 1.0 - Ship.FUEL_WARP_PER_SECOND, 1e-6)
	assert_true(warp.state.fuel < cruise.state.fuel, "warp is the thirstier drive")
	cruise.free()
	warp.free()
