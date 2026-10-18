extends "res://tests/test_case.gd"
## N5: crew walk the ship, open doors, sit in seats, never end up in a wall, and survive saves.

const TICK := 1.0 / 60.0
const SAVE_DIRECTORY := "user://test_saves_crew"
const WORK_STATIONS := [&"reactor_panel", &"engine_station", &"extinguisher_locker", &"gunner_seat"]
const START_ROOMS := {&"cockpit": Vector2(0.0, -5.0), &"cabin": Vector2(0.0, -1.8), &"engineering": Vector2(0.0, 1.6), &"turret_room": Vector2(0.0, 4.5), &"cargo": Vector2(0.0, 6.8)}


func _systems_and_crew() -> Array:
	return [ShipSystems.new(), ShipCrew.new()]


func _place(systems: ShipSystems, crew: ShipCrew, member_id: StringName, spot: Vector2) -> CrewMember:
	var person := CrewMember.new(member_id, &"engineer")
	person.body.place(Vector3(spot.x, systems.layout.floor_y, spot.y), 0.0)
	crew.members.append(person)
	return person


func _tick(systems: ShipSystems, crew: ShipCrew) -> void:
	for portal_id in systems.layout.portals:
		systems.occupied_portals[portal_id] = false
	crew.mark_occupied(systems)
	systems.update(TICK, ShipState.new())
	crew.update(TICK, systems)


func _seconds_to_arrive(systems: ShipSystems, crew: ShipCrew, person: CrewMember, limit_seconds: float) -> float:
	for tick in int(limit_seconds * 60.0):
		_tick(systems, crew)
		var position_ok := systems.layout.is_position_walkable(person.body.position.x, person.body.position.z, 0.0)
		if not position_ok and person.seat_id == &"":
			return -2.0
		if person.arrived and person.path.is_empty():
			return tick * TICK
	return -1.0


func test_route_goes_through_each_door_in_order() -> void:
	var layout := InteriorLayout.player_ship()
	var route := CrewNavigator.route(layout, Vector2(0, -5.0), Vector2(0, 4.5))
	var doors: Array = []
	for waypoint in route:
		if waypoint["door"] != &"":
			doors.append(waypoint["door"])
	assert_eq(doors, [&"cockpit_door", &"engineering_door", &"turret_door"], "cockpit to turret room")
	assert_eq(route[-1]["position"], Vector2(0, 4.5))
	assert_eq(CrewNavigator.route(layout, Vector2(0, 1.6), Vector2(0, 9.3)), [], "crew never route through the airlock")
	assert_true(CrewNavigator.route(layout, Vector2(0, 1.6), Vector2(0.2, 2.0)).size() == 1, "same room: just the goal")


func test_crew_reach_every_work_station_from_every_room_with_doors_closed() -> void:
	for start_room in START_ROOMS:
		for station_id in WORK_STATIONS:
			var parts := _systems_and_crew()
			var systems: ShipSystems = parts[0]
			var crew: ShipCrew = parts[1]
			var person := _place(systems, crew, &"ada", START_ROOMS[start_room])
			assert_eq(crew.order_to_station(systems, &"ada", station_id), "", "%s -> %s accepted" % [start_room, station_id])
			var seconds := _seconds_to_arrive(systems, crew, person, 60.0)
			assert_true(seconds >= 0.0, "%s -> %s arrived (result %f)" % [start_room, station_id, seconds])
			assert_true(seconds <= 40.0, "%s -> %s within 40 s: %f" % [start_room, station_id, seconds])
			if systems.layout.seats.has(station_id):
				assert_eq(person.seat_id, station_id, "sat in the seat")
				assert_true(systems.seats.is_seated(&"ada") or systems.seats.seat_of(&"ada") == station_id)
			else:
				var spot := systems.layout.standing_spot_for(station_id)
				assert_true(Vector2(person.body.position.x, person.body.position.z).distance_to(spot) < 0.5, "stands at the station")
				assert_eq(systems.layout.nearest_interaction(person.body.position), station_id, "close enough to use it")


func test_doors_never_close_on_crew_while_random_requests_hammer_them() -> void:
	var parts := _systems_and_crew()
	var systems: ShipSystems = parts[0]
	var crew: ShipCrew = parts[1]
	var rng := SeedRng.new(5)
	var first := _place(systems, crew, &"ada", Vector2(0, -5.0))
	var second := _place(systems, crew, &"bo", Vector2(0, 6.8))
	var stations := [&"reactor_panel", &"gunner_seat", &"extinguisher_locker", &"engine_station"]
	var bad := ""
	for tick in 60 * 240:
		if tick % 600 == 0:
			crew.order_to_station(systems, &"ada", stations[rng.next_int_in_range(0, 3)])
			crew.order_to_station(systems, &"bo", stations[rng.next_int_in_range(0, 3)])
		if tick % 7 == 0:
			var door_id: StringName = [&"cockpit_door", &"engineering_door", &"turret_door", &"cargo_door"][rng.next_int_in_range(0, 3)]
			if (systems.layout.portals[door_id] as Portal).target_open and rng.next_float() < 0.5:
				systems.toggle_door(door_id) # someone tries to shut a door, which must refuse on a person
		_tick(systems, crew)
		for person in [first, second]:
			if person.seat_id == &"" and not systems.layout.is_position_walkable(person.body.position.x, person.body.position.z, 0.0) and bad == "":
				bad = "%s in a wall at tick %d: %s" % [person.id, tick, str(person.body.position)]
	assert_eq(bad, "")


func test_airlock_invariant_holds_with_crew_walking_and_random_airlock_requests() -> void:
	var parts := _systems_and_crew()
	var systems: ShipSystems = parts[0]
	var crew: ShipCrew = parts[1]
	var rng := SeedRng.new(9)
	_place(systems, crew, &"ada", Vector2(0, 1.6))
	var ship_state := ShipState.new()
	ship_state.landed = true
	for tick in 60 * 120:
		if tick % 500 == 0:
			crew.order_to_station(systems, &"ada", [&"reactor_panel", &"gunner_seat"][rng.next_int_in_range(0, 1)])
		match rng.next_int_in_range(0, 5):
			0: systems.toggle_inner_door()
			1: systems.toggle_outer_door(ship_state)
		_tick(systems, crew)
		assert_true(systems.airlock.is_invariant_ok(), "both airlock doors open at tick %d" % tick)


func test_player_and_crew_contend_for_one_seat_and_exactly_one_wins() -> void:
	var parts := _systems_and_crew()
	var systems: ShipSystems = parts[0]
	var crew: ShipCrew = parts[1]
	var person := _place(systems, crew, &"ada", Vector2(0, 4.1))
	assert_eq(crew.order_to_station(systems, &"ada", &"gunner_seat"), "")
	assert_true(systems.seats.try_sit(&"player", &"gunner_seat"), "the player got there first")
	for tick in 60 * 5:
		_tick(systems, crew)
	assert_eq(person.seat_id, &"", "the crew member did not get a seat that was taken")
	assert_eq(systems.seats.occupant_of(&"gunner_seat"), &"player")
	assert_eq(crew.order_to_station(systems, &"ada", &"gunner_seat"), "seat is taken")


func test_new_order_stands_a_seated_crew_member_up() -> void:
	var parts := _systems_and_crew()
	var systems: ShipSystems = parts[0]
	var crew: ShipCrew = parts[1]
	var person := crew.add_member(systems, &"kit", &"gunner", &"gunner_seat")
	systems.seats.update(1.0)
	assert_eq(person.seat_id, &"gunner_seat")
	assert_eq(crew.order_to_station(systems, &"kit", &"reactor_panel"), "")
	assert_eq(systems.seats.occupant_of(&"gunner_seat"), &"", "seat freed")
	assert_true(_seconds_to_arrive(systems, crew, person, 60.0) > 0.0)
	assert_eq(systems.layout.nearest_interaction(person.body.position), &"reactor_panel")


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


func test_crew_positions_and_seats_survive_a_save_round_trip_and_session_stays_legal() -> void:
	var session := _session()
	session.crew.add_member(session.systems, &"mara", &"engineer", &"reactor_panel")
	session.crew.add_member(session.systems, &"kit", &"gunner", &"gunner_seat")
	session.systems.seats.update(1.0)
	session.crew.order_to_station(session.systems, &"mara", &"extinguisher_locker")
	for tick in 60 * 3:
		session.tick(TICK, OnFootCommand.new())
		assert_eq(session.validate(), "")
	var manager := SaveManager.new(SAVE_DIRECTORY)
	assert_eq(manager.save("crew", SaveGame.capture(session, 42)), "")
	var loaded := manager.load_slot("crew")
	assert_true(loaded["ok"], loaded["error"])
	var fresh := _session()
	assert_eq(SaveGame.restore(fresh, loaded["data"]), "")
	assert_eq(fresh.crew.members.size(), 2)
	for original in session.crew.members:
		var restored := fresh.crew.member(original.id)
		assert_true(restored != null)
		assert_true(restored.body.position.distance_to(original.body.position) < 0.01, "%s in the same place" % original.id)
		assert_eq(restored.seat_id, original.seat_id)
	assert_eq(fresh.systems.seats.occupant_of(&"gunner_seat"), &"kit")
	assert_eq(fresh.validate(), "")
	session.ship.free()
	fresh.ship.free()


func test_v10_saves_without_a_crew_section_keep_the_crew_the_game_started_with() -> void:
	var session := _session()
	session.crew.add_member(session.systems, &"mara", &"engineer", &"reactor_panel")
	var data := SaveGame.capture(session, 42)
	data.erase("crew")
	assert_eq(SaveGame.restore(session, data), "")
	assert_eq(session.crew.members.size(), 1)
	session.ship.free()
