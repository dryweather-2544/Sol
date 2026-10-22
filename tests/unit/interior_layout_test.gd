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
	body.place(Vector3(0, layout.floor_y, 1.6), 0.0) # mid-room, clear of the cabin machines beyond the tail wall
	_walk(body, layout, Vector2(1, 0), 300) # strafe right into the side wall
	var wall_x: float = (layout.rooms[&"engineering"] as Rect2).end.x
	assert_true(body.position.x <= wall_x - InteriorBody.RADIUS + 1e-3, "stopped by the wall: x=%f" % body.position.x)
	assert_true(body.position.x > wall_x - InteriorBody.RADIUS - 0.1, "and walked all the way to it: x=%f" % body.position.x)
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
	assert_eq(layout.rooms.size(), 9)
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


func test_looking_at_a_door_targets_it_from_either_side() -> void:
	var layout := InteriorLayout.player_ship()
	var eye := layout.floor_y + 1.6
	assert_eq(layout.look_target(Vector3(0, eye, -2.0), Vector3(0, 0, -1)), &"cockpit_door", "from the cabin, looking at the cockpit door")
	assert_eq(layout.look_target(Vector3(0, eye, -4.5), Vector3(0, 0, 1)), &"cockpit_door", "from the cockpit, looking back at it")
	assert_eq(layout.look_target(Vector3(-2.0, eye, -2.0), Vector3(0, 0, -1)), &"", "looking at the wall beside the door")
	assert_eq(layout.look_target(Vector3(0, eye, -0.6), Vector3(0, 0, -1)), &"cockpit_door", "2.5 m away is in reach")
	assert_eq(layout.look_target(Vector3(0, eye, 0.9), Vector3(0, 0, -1)), &"engineering_door", "from engineering, the door behind the near wall")
	assert_eq(layout.look_target(Vector3(0, eye, 0.9), Vector3(0, 0, -1), 0.3), &"", "too far for a short reach")


func test_looking_picks_stations_and_not_through_walls() -> void:
	var layout := InteriorLayout.player_ship()
	var eye := layout.floor_y + 1.6
	assert_eq(layout.look_target(Vector3(-3.0, eye, 1.2), Vector3(-1, 0, 0)), &"reactor_panel")
	assert_eq(layout.look_target(Vector3(0, eye, -4.6), Vector3(0, -0.3, -1).normalized()), &"pilot_seat")
	assert_eq(layout.look_target(Vector3(0, eye, -4.6), Vector3(1, 0, 0)), &"", "empty wall")
	assert_eq(layout.look_target(Vector3(1.0, eye, -1.0), Vector3(-1, 0, 0), 1.0), &"", "out of reach")


func test_plain_doors_close_by_themselves_but_never_on_a_person() -> void:
	var systems := ShipSystems.new()
	systems.toggle_door(&"cockpit_door")
	systems.occupied_portals[&"cockpit_door"] = true
	for tick in int((ShipSystems.DOOR_AUTO_CLOSE_SECONDS + 2.0) * 60.0):
		systems.update(DELTA, ShipState.new())
	assert_true((systems.layout.portals[&"cockpit_door"] as Portal).target_open, "stays open while someone is in the doorway")
	systems.occupied_portals[&"cockpit_door"] = false
	for tick in int((ShipSystems.DOOR_AUTO_CLOSE_SECONDS + 1.0) * 60.0):
		systems.update(DELTA, ShipState.new())
	assert_true(not (systems.layout.portals[&"cockpit_door"] as Portal).target_open, "closes after the delay")
	assert_eq((systems.layout.portals[&"cockpit_door"] as Portal).open_factor, 0.0, "and finishes closing")


func _landed_state() -> ShipState:
	var state := ShipState.new()
	state.landed = true
	return state


func _run_systems(systems: ShipSystems, state: ShipState, seconds: float) -> void:
	for tick in int(seconds * 60.0):
		systems.update(DELTA, state)


func test_airlock_computer_cycles_in_and_out_and_never_opens_both() -> void:
	var systems := ShipSystems.new()
	var state := _landed_state()
	assert_eq(systems.request_airlock(&"out", state), "", "start the trip out")
	for tick in 600:
		systems.update(DELTA, state)
		assert_true(systems.airlock.is_invariant_ok(), "doors never both open")
	assert_true(systems.airlock.outer.target_open, "outer door opened by itself")
	assert_eq(systems.airlock_goal, &"", "goal finished")
	assert_eq(systems.request_airlock(&"in", state), "", "start coming back in")
	for tick in 900:
		systems.update(DELTA, state)
		assert_true(systems.airlock.is_invariant_ok(), "doors never both open on the way in")
	assert_true(systems.airlock.inner.target_open and not systems.airlock.outer.target_open, "inner open, outer shut")


func test_airlock_computer_refuses_the_outer_door_when_flying() -> void:
	var systems := ShipSystems.new()
	var state := ShipState.new() # not landed
	var refused := systems.request_airlock(&"out", state)
	_run_systems(systems, state, 5.0)
	assert_true(not systems.airlock.outer.target_open, "outer stays shut in flight")
	assert_true(refused != "" or systems.airlock_status != "", "the computer says why")
	assert_eq(systems.airlock_goal, &"", "and gives up")


func test_airlock_computer_is_in_the_airlock_and_can_be_looked_at() -> void:
	var layout := InteriorLayout.player_ship()
	var eye := layout.floor_y + 1.6
	assert_eq(layout.look_target(Vector3(0.0, eye, 9.4), Vector3(-1, 0, 0)), &"airlock_computer")


func test_living_area_and_med_bay_are_reachable_and_walkable() -> void:
	var layout := InteriorLayout.player_ship()
	for room_id in [&"living_area", &"medical"]:
		assert_true(layout.rooms.has(room_id) and layout.is_pocket(room_id), "%s exists and is a pocket room" % room_id)
	# Every room can be reached from the cockpit through plain doors (the crew never use the airlock).
	var start := Vector2(0.0, -5.0)
	for station in [&"bed", &"medbed", &"bathroom_door"]:
		var spot := layout.standing_spot_for(station)
		assert_true(spot != Vector2.INF, "%s has a place to stand" % station)
		var route := CrewNavigator.route(layout, start, spot)
		assert_true(not route.is_empty(), "a route from the cockpit to the %s" % station)
		var doors := 0
		for waypoint in route:
			if waypoint["door"] != &"":
				doors += 1
		assert_true(doors >= 2, "through at least the cockpit and side doors")


func test_side_door_leads_to_the_living_area_when_open() -> void:
	var layout := InteriorLayout.player_ship()
	assert_true(not layout.is_position_walkable(5.6, -1.6, 0.2), "closed side door blocks")
	(layout.portals[&"living_door"] as Portal).open_factor = 1.0
	assert_true(layout.is_position_walkable(5.6, -1.6, 0.2), "open side door passes")
	assert_eq(layout.portal_rooms(&"living_door").size(), 2, "it joins two rooms")
	assert_eq(layout.room_at(8.0, -1.8), &"living_area")
	assert_eq(layout.room_at(8.0, 1.0), &"medical")
	assert_eq(layout.room_at(9.0, -4.6), &"bathroom")


func test_windows_sit_in_free_outside_walls() -> void:
	var layout := InteriorLayout.player_ship()
	assert_true(layout.windows.size() >= 4, "the ship has windows")
	for window in layout.windows:
		var room_id: StringName = window["room"]
		var side: String = window["side"]
		assert_true(layout.is_pocket(room_id), "%s is a pocket room, where the world shows through" % room_id)
		var wall := layout.wall_rect(room_id, side)
		var along_x := InteriorLayout.wall_runs_along_x(side)
		var from_value: float = float(window["center"]) - float(window["width"]) * 0.5
		var to_value: float = float(window["center"]) + float(window["width"]) * 0.5
		var wall_from := wall.position.x if along_x else wall.position.y
		var wall_to := wall.end.x if along_x else wall.end.y
		assert_true(from_value > wall_from + 0.1 and to_value < wall_to - 0.1, "%s %s window is inside its wall" % [room_id, side])
		assert_true(float(window["sill"]) + float(window["height"]) < layout.ceiling_y - layout.floor_y - 0.1, "window under the ceiling")
		for portal in layout.portals.values():
			var opening := (portal as Portal).opening
			if opening.intersects(wall):
				var door_from := opening.position.x if along_x else opening.position.y
				var door_to := opening.end.x if along_x else opening.end.y
				assert_true(to_value <= door_from or from_value >= door_to, "window does not overlap a door")
		for other_id in layout.rooms:
			if other_id == room_id:
				continue
			for other_side in ["nose", "tail", "left", "right"]:
				var other_wall := layout.wall_rect(other_id, other_side)
				var overlap := other_wall.intersection(wall)
				assert_true(not (overlap.has_area() and _window_in_overlap(window, overlap, along_x)), "%s %s window is not in a wall shared with %s" % [room_id, side, other_id])


func _window_in_overlap(window: Dictionary, overlap: Rect2, along_x: bool) -> bool:
	var from_value: float = float(window["center"]) - float(window["width"]) * 0.5
	var to_value: float = float(window["center"]) + float(window["width"]) * 0.5
	var overlap_from := overlap.position.x if along_x else overlap.position.y
	var overlap_to := overlap.end.x if along_x else overlap.end.y
	return from_value < overlap_to and to_value > overlap_from


func test_furniture_is_solid_but_doorways_and_stations_stay_clear() -> void:
	var layout := InteriorLayout.player_ship()
	assert_true(layout.obstacles.size() >= 6, "solid furniture exists")
	assert_true(not layout.is_position_walkable(10.0, -1.5, InteriorBody.RADIUS), "cannot stand in the bed")
	assert_true(not layout.is_position_walkable(7.7, -3.0, InteriorBody.RADIUS), "cannot stand in the desk")
	assert_true(layout.is_position_walkable(8.2, -1.6, InteriorBody.RADIUS), "the floor between is clear")
	# Every doorway can be walked up to from both sides (the crew's line-up points).
	for portal_id in layout.portals:
		var portal: Portal = layout.portals[portal_id]
		if portal.kind != Portal.Kind.DOOR:
			continue
		var centre := portal.opening.get_center()
		var along := Vector2(0.0, 1.0) if portal.opening.size.x >= portal.opening.size.y else Vector2(1.0, 0.0)
		for side in [-1.0, 1.0]:
			var spot: Vector2 = centre + along * side * CrewNavigator.DOORWAY_APPROACH
			assert_true(layout.is_position_walkable(spot.x, spot.y, InteriorBody.RADIUS) or layout.is_position_walkable(spot.x, spot.y, 0.0), "%s approach is not inside furniture" % portal_id)
	# A person can sidestep around the furniture to every station (spot exists) and every piece sits inside its room.
	for piece in layout.furniture:
		var at: Vector2 = piece["at"]
		assert_true(layout.room_at(at.x, at.y) != &"", "%s is inside a room" % piece["name"])


func test_machines_exist_are_solid_and_can_be_looked_at() -> void:
	var layout := InteriorLayout.player_ship()
	var eye := layout.floor_y + 1.4
	for machine in [&"ops_computer", &"scanners", &"ftl_radio", &"battery_array", &"limnal_drive"]:
		assert_true(layout.machine_screens.has(machine), "%s has a screen" % machine)
		assert_true(layout.standing_spot_for(machine) != Vector2.INF, "%s can be used from somewhere" % machine)
	assert_eq(layout.look_target(Vector3(3.3, eye, -1.6), Vector3(0, 0, 1)), &"ops_computer")
	assert_eq(layout.look_target(Vector3(4.5, eye, -1.6), Vector3(0, 0, 1)), &"scanners")
	assert_eq(layout.look_target(Vector3(1.6, eye, -2.5), Vector3(1, 0, 0)), &"ftl_radio")
	assert_eq(layout.look_target(Vector3(-3.6, eye, 6.9), Vector3(-1, 0, 0)), &"battery_array")
	assert_eq(layout.look_target(Vector3(3.4, eye, 6.9), Vector3(1, 0, 0)), &"limnal_drive")
	assert_true(not layout.is_position_walkable(3.0, -0.45, 0.2), "the ops computer is solid")


## Geometry audit: nothing may poke through a wall, stand on a doorway, sit on a station, or hide behind another solid piece.
func _piece_rect(piece: Dictionary) -> Rect2:
	var at: Vector2 = piece["at"]
	var size: Vector3 = piece["size"]
	return Rect2(at.x - size.x * 0.5, at.y - size.z * 0.5, size.x, size.z)


func test_every_piece_stays_inside_its_room() -> void:
	var layout := InteriorLayout.player_ship()
	for piece in layout.furniture:
		var rect := _piece_rect(piece)
		var room_id := layout.room_at(piece["at"].x, piece["at"].y)
		assert_true(room_id != &"", "%s stands in a room" % piece["name"])
		if room_id == &"":
			continue
		var room: Rect2 = layout.rooms[room_id]
		assert_true(room.grow(0.005).encloses(rect), "%s (%s) stays inside %s" % [piece["name"], rect, room_id])


func test_solid_pieces_do_not_overlap_each_other_or_block_doorways() -> void:
	var layout := InteriorLayout.player_ship()
	var solids: Array = layout.furniture.filter(func(piece): return piece["solid"])
	for i in solids.size():
		for j in range(i + 1, solids.size()):
			assert_true(not _piece_rect(solids[i]).grow(-0.01).intersects(_piece_rect(solids[j])), "%s and %s overlap" % [solids[i]["name"], solids[j]["name"]])
		for portal_id in layout.portals:
			var lane: Rect2 = (layout.portals[portal_id] as Portal).opening.grow(0.25)
			assert_true(not _piece_rect(solids[i]).intersects(lane), "%s blocks the %s doorway" % [solids[i]["name"], portal_id])


func test_machines_and_stations_are_not_buried_in_furniture() -> void:
	var layout := InteriorLayout.player_ship()
	for point in layout.interact_points:
		if layout.portals.has(point["id"]) or layout.seats.has(point["id"]):
			continue
		var spot := Vector2(point["position"].x, point["position"].z)
		for piece in layout.furniture:
			if piece["solid"] and not layout.machine_screens.has(point["id"]) and point["id"] not in [&"bed", &"medbed"]:
				assert_true(not _piece_rect(piece).has_point(spot), "the %s panel is inside %s" % [point["id"], piece["name"]])
	# Two machines or stations never share a spot: their points are far enough apart to pick between by looking.
	for i in layout.interact_points.size():
		for j in range(i + 1, layout.interact_points.size()):
			var a: Dictionary = layout.interact_points[i]
			var b: Dictionary = layout.interact_points[j]
			if a["id"] == b["id"] or layout.portals.has(a["id"]) or layout.portals.has(b["id"]):
				continue
			var gap := Vector2(a["position"].x - b["position"].x, a["position"].z - b["position"].z).length()
			assert_true(gap > 0.9, "%s and %s are %.2f m apart" % [a["id"], b["id"], gap])


func test_windows_fit_their_wall_and_are_not_covered() -> void:
	var layout := InteriorLayout.player_ship()
	var wall_height := layout.ceiling_y - layout.floor_y
	for window in layout.windows:
		var room: Rect2 = layout.rooms[window["room"]]
		var along_x := InteriorLayout.wall_runs_along_x(window["side"])
		var low: float = (room.position.x if along_x else room.position.y)
		var high: float = (room.end.x if along_x else room.end.y)
		var from: float = window["center"] - window["width"] * 0.5
		var to: float = window["center"] + window["width"] * 0.5
		assert_true(from >= low - 0.001 and to <= high + 0.001, "%s %s window fits its wall" % [window["room"], window["side"]])
		assert_true(window["sill"] + window["height"] <= wall_height - 0.1, "%s window is under the ceiling" % window["room"])
		var wall_line: float = {"nose": room.position.y, "tail": room.end.y, "left": room.position.x, "right": room.end.x}[window["side"]]
		for piece in layout.furniture:
			var rect := _piece_rect(piece)
			var top: float = piece["lift"] + piece["size"].y
			var touches := absf((rect.position.y if window["side"] == "nose" else (rect.end.y if window["side"] == "tail" else (rect.position.x if window["side"] == "left" else rect.end.x))) - wall_line) < 0.35
			var piece_from := rect.position.x if along_x else rect.position.y
			var piece_to := rect.end.x if along_x else rect.end.y
			if touches and top > window["sill"] and piece_to > from and piece_from < to:
				assert_true(false, "%s covers the %s %s window" % [piece["name"], window["room"], window["side"]])
		for portal_id in layout.portals:
			var opening := (layout.portals[portal_id] as Portal).opening
			if opening.grow(0.1).intersects(layout.wall_rect(window["room"], window["side"])):
				var open_from := opening.position.x if along_x else opening.position.y
				var open_to := opening.end.x if along_x else opening.end.y
				assert_true(open_to <= from or open_from >= to, "the %s door and the %s %s window do not overlap" % [portal_id, window["room"], window["side"]])


## The gunner seat used to stand in the walkway in front of the cargo door, so looking at the door picked the seat.
func test_turret_room_walkway_is_clear_and_the_cargo_door_can_be_looked_at() -> void:
	var layout := InteriorLayout.player_ship()
	var eye := layout.floor_y + InteriorBody.EYE_HEIGHT
	assert_eq(layout.look_target(Vector3(0, eye, 4.0), Vector3(0, -0.1, 1).normalized()), &"cargo_door", "the cargo door, not the gunner seat")
	assert_eq(layout.look_target(Vector3(0, eye, 4.0), Vector3(1, 0, 0)), &"", "nothing on the east side of the walkway")
	assert_eq(layout.look_target(Vector3(-2.4, eye, 3.9), Vector3(0, -0.4, 1).normalized()), &"gunner_seat", "the seat at the tactical console")
	for z in [3.8, 4.2, 4.6, 5.2]:
		assert_true(layout.is_position_walkable(0.0, z, InteriorBody.RADIUS), "walkway clear at z=%.1f" % z)


## Every plain door opens with F while you look at it, including the side rooms' doors (they used to say "Nothing to use here").
func test_f_opens_every_plain_door_you_look_at() -> void:
	var planet := PlanetBody.new()
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	var session := GameSession.new(planet, ship, PilotSource.new())
	session.mode = GameSession.Mode.INSIDE
	var layout := session.systems.layout
	var eye := layout.floor_y + InteriorBody.EYE_HEIGHT
	var looks := {&"living_door": [Vector3(4.6, eye, -2.0), Vector3(1, 0, 0)], &"medical_door": [Vector3(8.2, eye, -1.2), Vector3(0, 0, 1)],
		&"bathroom_door": [Vector3(9.5, eye, -2.6), Vector3(0, 0, -1)], &"cargo_door": [Vector3(0, eye, 4.4), Vector3(0, 0, 1)]}
	for door_id in looks:
		var look: Array = looks[door_id]
		session.interior_body.place(Vector3(look[0].x, layout.floor_y, look[0].z), 0.0)
		session.set_look(look[0], look[1])
		assert_eq(session.interaction_target(), door_id, "looking at %s" % door_id)
		assert_eq(session.prompt(), "F — Open door")
		session.interact()
		assert_true((layout.portals[door_id] as Portal).target_open, "%s opened with F" % door_id)
		assert_eq(session.prompt(), "F — Close door")


func test_reactor_core_is_solid_and_the_reactor_panel_still_reachable() -> void:
	var layout := InteriorLayout.player_ship()
	var at: Vector2 = layout.reactor_core["at"]
	assert_eq(layout.room_at(at.x, at.y), &"engineering")
	assert_true(not layout.is_position_walkable(at.x, at.y, InteriorBody.RADIUS), "nobody walks through the core")
	assert_true(layout.standing_spot_for(&"reactor_panel") != Vector2.INF)
	for portal_id in [&"engineering_door", &"turret_door"]:
		var lane: Rect2 = (layout.portals[portal_id] as Portal).opening.grow(0.25)
		assert_true(not lane.intersects(Rect2(at - Vector2.ONE, Vector2.ONE * 2.0)), "the core is clear of the %s lane" % portal_id)
	var room: Rect2 = layout.rooms[&"engineering"]
	assert_true(room.encloses(Rect2(at - Vector2.ONE * (InteriorLayout.REACTOR_RADIUS + 0.2), Vector2.ONE * (InteriorLayout.REACTOR_RADIUS + 0.2) * 2.0)),
		"the plinth stays inside engineering")
