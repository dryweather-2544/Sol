extends "res://tests/test_case.gd"

const DELTA := 1.0 / 60.0


func _walk(body: InteriorBody, layout: InteriorLayout, move: Vector2, ticks: int) -> void:
	var command := OnFootCommand.new()
	command.move = move
	for tick in ticks:
		body.step(command, layout, DELTA)


func test_closed_door_blocks_and_open_door_lets_you_through() -> void:
	var layout := InteriorLayout.player_ship()
	var door: Portal = layout.portals[&"cockpit_door"]
	var body := InteriorBody.new()
	body.place(Vector3(0, layout.floor_y, -4.4), PI) # facing +z toward the cabin door... yaw PI faces +z
	_walk(body, layout, Vector2(0, 1), 120)
	assert_true(body.position.z < -3.6, "closed door stops the walker: z=%f" % body.position.z)
	door.target_open = true
	for tick in 60:
		door.update(DELTA)
	_walk(body, layout, Vector2(0, 1), 120)
	assert_true(body.position.z > -3.0, "open door lets the walker into the cabin: z=%f" % body.position.z)


func test_walkers_stay_inside_the_rooms_and_slide_along_walls() -> void:
	var layout := InteriorLayout.player_ship()
	var body := InteriorBody.new()
	body.place(Vector3(0, layout.floor_y, 0), 0.0)
	_walk(body, layout, Vector2(1, 0), 300) # strafe right into the side wall
	assert_true(body.position.x <= 3.0 - InteriorBody.RADIUS + 1e-3, "stopped by the wall: x=%f" % body.position.x)
	assert_near(body.position.y, layout.floor_y, 1e-6)


func test_ramp_is_only_walkable_when_deployed_and_slopes_down() -> void:
	var layout := InteriorLayout.player_ship()
	var ramp_x := 0.0
	var ramp_z := layout.ramp_rect.position.y + 1.0
	assert_true(not layout.is_position_walkable(ramp_x, ramp_z, InteriorBody.RADIUS), "stowed")
	layout.ramp_walkable = true
	assert_true(layout.is_position_walkable(ramp_x, ramp_z, InteriorBody.RADIUS), "deployed")
	layout.ramp_end_y = -2.0
	assert_near(layout.floor_height_at(0.0, layout.ramp_rect.position.y), layout.floor_y, 1e-6)
	assert_near(layout.floor_height_at(0.0, layout.ramp_rect.end.y - 0.001), -2.0, 1e-2)
	assert_true(layout.floor_height_at(0.0, layout.ramp_rect.position.y + 2.0) < layout.floor_y)


func test_nearest_interaction_picks_the_closest_panel() -> void:
	var layout := InteriorLayout.player_ship()
	assert_eq(layout.nearest_interaction(Vector3(0, layout.floor_y, -5.0)), &"pilot_seat")
	assert_eq(layout.nearest_interaction(Vector3(1.2, layout.floor_y, 8.8)), &"airlock_inner")
	assert_eq(layout.nearest_interaction(Vector3(1.2, layout.floor_y, 9.8)), &"airlock_outer")
	assert_eq(layout.nearest_interaction(Vector3(-0.2, layout.floor_y, -1.8)), &"")


func test_exterior_walker_is_pushed_out_of_the_hull_but_not_off_the_ramp() -> void:
	var layout := InteriorLayout.player_ship()
	var inside_hull := Vector3(1.0, -2.0, 0.0) # standing under the cabin
	var pushed := ShipHullCollision.push_out(inside_hull, 0.4, layout.ramp_rect, false)
	assert_true(absf(pushed.x) >= ShipHullCollision.HULL_HALF_WIDTH, "moved out through the nearest side")
	var on_ramp := Vector3(0.0, -2.0, layout.ramp_rect.position.y + 1.0)
	assert_eq(ShipHullCollision.push_out(on_ramp, 0.4, layout.ramp_rect, true), on_ramp, "ramp mouth is open when deployed")


func test_every_portal_joins_two_rooms_and_all_rooms_are_connected() -> void:
	var layout := InteriorLayout.player_ship()
	assert_eq(layout.rooms.size(), 6)
	var neighbours := {}
	for portal_id in layout.portals:
		var joined := layout.portal_rooms(portal_id)
		if portal_id == &"airlock_outer":
			assert_eq(joined, [&"airlock"] as Array[StringName], "the outer door leads outside")
			continue
		assert_eq(joined.size(), 2, "%s joins two rooms" % portal_id)
		for room_id in joined:
			neighbours[room_id] = neighbours.get(room_id, []) + joined
	var reached := {&"cockpit": true}
	var queue: Array = [&"cockpit"]
	while not queue.is_empty():
		var current = queue.pop_back()
		for other in neighbours.get(current, []):
			if not reached.has(other):
				reached[other] = true
				queue.append(other)
	assert_eq(reached.size(), layout.rooms.size(), "walking through doors reaches every room: %s" % str(reached.keys()))


func test_every_station_is_walkable_and_reachable_from_the_pilot_seat_with_doors_open() -> void:
	var layout := InteriorLayout.player_ship()
	for portal in layout.portals.values():
		(portal as Portal).target_open = true
		(portal as Portal).open_factor = 1.0
	var cell := 0.1
	var start: Vector3 = layout.seats[&"pilot_seat"]["exit_position"]
	var start_cell := Vector2i(roundi(start.x / cell), roundi(start.z / cell))
	var seen := {start_cell: true}
	var queue: Array[Vector2i] = [start_cell]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_back()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = current + step
			if seen.has(next) or not layout.is_position_walkable(next.x * cell, next.y * cell, InteriorBody.RADIUS):
				continue
			seen[next] = true
			queue.append(next)
	for point in layout.interact_points:
		var position: Vector3 = point["position"]
		var standable_spot_in_reach := false
		for seen_cell in seen:
			var spot := Vector2(seen_cell.x * cell, seen_cell.y * cell)
			if spot.distance_to(Vector2(position.x, position.z)) <= float(point["radius"]) * 0.9 and layout.nearest_interaction(Vector3(spot.x, layout.floor_y, spot.y)) == point["id"]:
				standable_spot_in_reach = true
				break
		assert_true(standable_spot_in_reach, "%s can be used from somewhere reachable from the pilot seat" % point["id"])
	for station_id in layout.stations:
		assert_true(layout.rooms.has(layout.stations[station_id]["room"]), "%s names a real room" % station_id)


func test_gunner_seat_is_a_seat_with_an_interaction_point_in_the_turret_room() -> void:
	var layout := InteriorLayout.player_ship()
	assert_true(layout.seats.has(&"gunner_seat"))
	var seat_position: Vector3 = layout.seats[&"gunner_seat"]["position"]
	assert_eq(layout.room_at(seat_position.x, seat_position.z), &"turret_room")
	assert_eq(layout.nearest_interaction(seat_position), &"gunner_seat")
	var manager := SeatManager.new([&"pilot_seat", &"gunner_seat"])
	assert_true(manager.try_sit(&"alice", &"gunner_seat"))
	assert_true(not manager.try_sit(&"bob", &"gunner_seat"), "one occupant per seat")
	assert_true(manager.try_sit(&"bob", &"pilot_seat"))
