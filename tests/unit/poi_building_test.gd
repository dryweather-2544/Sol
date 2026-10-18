extends "res://tests/test_case.gd"


func test_generation_is_deterministic_connected_and_non_overlapping() -> void:
	var different := 0
	var previous_hash := -1
	for seed_value in 200:
		var building := PoiBuilding.generate(seed_value)
		var again := PoiBuilding.generate(seed_value)
		assert_eq(building.rooms.size(), again.rooms.size())
		assert_eq(building.walls.size(), again.walls.size())
		assert_true(building.rooms.size() >= 2 and building.rooms.size() <= 6, "room count %d" % building.rooms.size())
		assert_eq(building.reachable_room_count(), building.rooms.size(), "every room reachable from the entrance (seed %d)" % seed_value)
		for first_index in building.rooms.size():
			assert_true(building.rooms[first_index].rect.end.y <= 0.0, "rooms are inside, behind the entrance wall")
			for second_index in range(first_index + 1, building.rooms.size()):
				assert_true(not building.rooms[first_index].rect.intersects(building.rooms[second_index].rect), "rooms overlap (seed %d)" % seed_value)
		var signature := building.rooms.size() * 1000 + building.walls.size()
		if signature != previous_hash:
			different += 1
		previous_hash = signature
	assert_true(different > 20, "seeds give varied buildings: %d" % different)


func test_every_doorway_is_open_and_every_room_has_walls_elsewhere() -> void:
	for seed_value in 60:
		var building := PoiBuilding.generate(seed_value)
		for door in building.doorways:
			var door_rect: Rect2 = door["rect"]
			var centre := door_rect.get_center()
			for wall in building.walls:
				assert_true(not wall.has_point(centre), "a wall blocks a doorway centre (seed %d)" % seed_value)
		var blocked := building.push_out_of_walls(Vector2(0.0, 5.0), 0.4)
		assert_true(blocked.distance_to(Vector2(0.0, 5.0)) < 1e-6, "outside, away from walls, nothing moves")
		var in_wall := building.walls[0].get_center()
		var pushed := building.push_out_of_walls(in_wall, 0.4)
		assert_true(pushed.distance_to(in_wall) > 0.1, "a point inside a wall is pushed out")


func test_a_walker_can_pass_every_doorway_but_not_walls() -> void:
	var building := PoiBuilding.generate(11)
	# Through the entrance: walk from outside (z = +3) to the middle of the hall.
	var position := Vector2(0.0, 3.0)
	for step in 200:
		position += Vector2(0.0, -0.05)
		position = building.push_out_of_walls(position, 0.4)
	assert_true(position.y < -2.0, "walked in through the entrance: %s" % str(position))
	# Straight at a wall far from the door: stopped.
	var blocked := Vector2(3.5, 3.0)
	for step in 200:
		blocked += Vector2(0.0, -0.05)
		blocked = building.push_out_of_walls(blocked, 0.4)
	assert_true(blocked.y > 0.3, "stopped by the front wall beside the entrance: %s" % str(blocked))
	# Every doorway lets a walker through between its two rooms.
	for door in building.doorways:
		if door["room_b"] < 0:
			continue
		var door_rect: Rect2 = door["rect"]
		var room_a: PoiBuilding.Room = building.rooms[door["room_a"]]
		var room_b: PoiBuilding.Room = building.rooms[door["room_b"]]
		var start: Vector2 = room_a.rect.get_center()
		var goal: Vector2 = room_b.rect.get_center()
		var via := door_rect.get_center()
		var walker := start
		for leg in [via, goal]:
			for step in 600:
				var to_leg: Vector2 = leg - walker
				if to_leg.length() < 0.1:
					break
				walker += to_leg.normalized() * minf(0.05, to_leg.length())
				walker = building.push_out_of_walls(walker, 0.4)
		assert_true(walker.distance_to(goal) < 0.6, "could not walk through a doorway: %s to %s" % [str(start), str(goal)])


const DELTA := 1.0 / 60.0


func _depot_session() -> Array:
	var planet := PlanetBody.new()
	planet.breathable = false
	planet.atmosphere_height = 0.0
	planet.height_override = func(_dx: float, _dy: float, _dz: float) -> float: return 0.0
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	ship.state.position = WorldPos.new(planet.frame_id, 0.0, 0.0, planet.radius + 2.1)
	ship.state.basis = Basis(Vector3.RIGHT, PI / 2.0)
	var session := GameSession.new(planet, ship, PilotSource.new())
	for tick in 120:
		session.tick(DELTA, OnFootCommand.new())
	session.interact()
	var poi := PoiInstance.new()
	poi.id = &"poi_depot_test"
	poi.type = PoiDefinition.Type.OUTPOST
	poi.seed_value = 321
	poi.position = WorldPos.new(planet.frame_id, 400.0, 0.0, planet.radius)
	session.nearby_pois = [poi]
	return [session, poi, planet]


func _walk_in_poi_local(session: GameSession, poi: PoiInstance, local_target: Vector2, ticks: int) -> void:
	var frame := PoiBuilder.frame_basis(poi)
	var walk := OnFootCommand.new()
	walk.move = Vector2(0, 1)
	for tick in ticks:
		var offset := session.exterior_body.position.vector_from(poi.position)
		var here := Vector2(offset.dot(frame.x), offset.dot(frame.z))
		var to_target := local_target - here
		if to_target.length() < 0.3:
			break
		var heading := frame.x * to_target.x + frame.z * to_target.y
		session.exterior_body.heading = heading.normalized()
		session.exterior_body.step(walk, session.planet, DELTA)
		session.apply_building_walls()
		session._update_suit(DELTA)


func test_walking_into_a_depot_gives_a_flat_floor_air_and_working_walls() -> void:
	var setup := _depot_session()
	var session: GameSession = setup[0]
	var poi: PoiInstance = setup[1]
	var planet: PlanetBody = setup[2]
	var building := poi.building()
	var frame := PoiBuilder.frame_basis(poi)
	var door_outside := PoiBuilder.DEPOT_ORIGIN + Vector2(0.0, 8.0)
	session.exterior_body.place_on_ground(planet, poi.position.offset_by(frame.x * door_outside.x + frame.z * door_outside.y), -frame.z)
	session.restore_mode(GameSession.Mode.OUTSIDE)
	assert_true(not session.in_building)
	_walk_in_poi_local(session, poi, PoiBuilder.DEPOT_ORIGIN + Vector2(0.0, -4.0), 600)
	assert_true(session.in_building, "inside the depot")
	var floor_distance := planet.distance_from_center(poi.position) + PoiBuilder.depot_floor_height(planet, poi)
	assert_near(planet.distance_from_center(session.exterior_body.position), floor_distance, 0.02, "standing on the depot floor, not the terrain")
	session.suit.oxygen = 0.5
	for tick in 600:
		session._update_suit(DELTA)
	assert_true(session.suit.oxygen > 0.5, "indoors the air is breathable even on a vacuum world")
	# Walk back out and through the front wall beside the door: the wall stops the walker.
	_walk_in_poi_local(session, poi, PoiBuilder.DEPOT_ORIGIN + Vector2(0.0, 8.0), 900)
	assert_true(not session.in_building, "back outside")
	_walk_in_poi_local(session, poi, PoiBuilder.DEPOT_ORIGIN + Vector2(3.5, -4.0), 400)
	var offset := session.exterior_body.position.vector_from(poi.position)
	var local_z := offset.dot(frame.z) - PoiBuilder.DEPOT_ORIGIN.y
	assert_true(local_z > 0.3, "the front wall beside the door held: z=%f" % local_z)
	# Every room can be reached by following doorways from the entrance on foot.
	session.exterior_body.place_on_ground(planet, poi.position.offset_by(frame.x * door_outside.x + frame.z * door_outside.y), -frame.z)
	var route: Array[Vector2] = [PoiBuilder.DEPOT_ORIGIN + Vector2(0.0, 3.0), PoiBuilder.DEPOT_ORIGIN + Vector2(0.0, -3.5)]
	var visited := {0: true}
	var current_room := 0
	var queue := [0]
	while not queue.is_empty():
		var room_index: int = queue.pop_front()
		for door in building.doorways:
			var other := -1
			if door["room_a"] == room_index:
				other = door["room_b"]
			elif door["room_b"] == room_index:
				other = door["room_a"]
			if other >= 0 and not visited.has(other):
				visited[other] = true
				queue.append(other)
				var door_centre: Vector2 = PoiBuilder.DEPOT_ORIGIN + (door["rect"] as Rect2).get_center()
				var target_room: PoiBuilding.Room = building.rooms[other]
				_walk_in_poi_local(session, poi, PoiBuilder.DEPOT_ORIGIN + (building.rooms[room_index] as PoiBuilding.Room).rect.get_center(), 600)
				_walk_in_poi_local(session, poi, door_centre, 600)
				_walk_in_poi_local(session, poi, PoiBuilder.DEPOT_ORIGIN + target_room.rect.get_center(), 600)
				var here := session.exterior_body.position.vector_from(poi.position)
				var local_here := Vector2(here.dot(frame.x), here.dot(frame.z)) - PoiBuilder.DEPOT_ORIGIN
				assert_true(building.room_index_at(local_here) == other, "reached room %d (at %s)" % [other, str(local_here)])
	assert_eq(visited.size(), building.rooms.size())
	session.ship.free()


func test_depot_crates_hold_loot_inside_rooms() -> void:
	var poi := PoiInstance.new()
	poi.id = &"poi_depot_crates"
	poi.type = PoiDefinition.Type.OUTPOST
	poi.seed_value = 777
	var building := poi.building()
	var crates := PoiBuilder.crate_positions(poi)
	assert_eq(crates.size(), 3 + building.crate_positions().size(), "3 outdoor crates plus the depot's")
	for crate in building.crate_positions():
		assert_true(building.room_index_at(crate) >= 0, "crate inside a room")
