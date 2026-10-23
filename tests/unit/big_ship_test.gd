extends "res://tests/test_case.gd"
## The five big ships: each its own hull, name, numbers and interior; every interior has a bridge with seated crew, a captain's bay, corridors and an airlock,
## and everything in it can be walked to. The interiors are data generated and checked by tools/gen_big_ships.py (which also checks reachability on a fine grid);
## these tests read the generated data through the real loader and InteriorLayout, so they catch a loader or data-format slip. The hull model files are git-ignored,
## so nothing here needs them.

const Catalog := preload("res://src/bigship/big_ship_catalog.gd")
const Plan := preload("res://src/bigship/big_ship_plan.gd")
const Interior := preload("res://src/bigship/big_ship_interior.gd")

const IDS := ["meridian", "talon", "argent", "halo", "kestrel"]


func _plan(ship_id: String) -> Plan:
	var plan := Plan.new()
	assert_true(plan.load_ship(ship_id), "%s: the interior loads" % ship_id)
	return plan


func test_there_are_five_ships_and_none_repeats_another() -> void:
	var defs := Catalog.all()
	assert_eq(defs.size(), 5, "five big ships")
	var names := {}
	var hulls := {}
	var blurbs := {}
	var accents := {}
	for def in defs:
		assert_true(def.id in IDS, "%s: a known id" % def.id)
		assert_true(not names.has(def.display_name), "%s: name used once" % def.id)
		names[def.display_name] = true
		assert_true(not hulls.has(def.hull_path), "%s: hull model used once" % def.id)
		hulls[def.hull_path] = true
		assert_true(def.blurb != "" and not blurbs.has(def.blurb), "%s: its own line of character" % def.id)
		blurbs[def.blurb] = true
		assert_true(not accents.has(def.accent.to_html()), "%s: its own menu colour" % def.id)
		accents[def.accent.to_html()] = true
		assert_true(def.hull_extent >= 40.0 and def.crew >= 8, "%s: a big ship with a crew" % def.id)
		assert_eq(Catalog.by_id(def.id), def, "%s: found by id" % def.id)
	assert_eq(Catalog.by_id("nope"), null, "an unknown id finds nothing")


func test_every_hull_that_needs_a_credit_carries_it() -> void:
	for def in Catalog.all():
		if def.hull_path.begins_with("res://assets/ships/hulls/"):
			assert_true("CC-BY-4.0" in def.credit and "by " in def.credit, "%s: its CC-BY credit line" % def.id)


func test_every_ship_has_its_own_floor_plan() -> void:
	var signatures := {}
	for ship_id in IDS:
		var plan := _plan(ship_id)
		var rects: Array[String] = []
		for room in plan.layout.rooms.values():
			rects.append(str(room))
		rects.sort()
		var signature := "|".join(rects)
		assert_true(not signatures.has(signature), "%s: a floor plan no other ship has" % ship_id)
		signatures[signature] = true
		assert_true(plan.layout.rooms.size() >= 11, "%s: at least eleven rooms" % ship_id)
		assert_true(plan.length() >= 30.0, "%s: a long ship" % ship_id)


func test_every_ship_has_a_bridge_with_seated_crew_and_a_captains_chair() -> void:
	for ship_id in IDS:
		var plan := _plan(ship_id)
		assert_true(plan.seats_in(&"bridge") >= 7, "%s: seven or more bridge stations" % ship_id)
		assert_true(not plan.seat(&"captain").is_empty(), "%s: a captain's chair" % ship_id)
		assert_eq(plan.seat(&"captain")["room"], &"bridge", "%s: the captain sits on the bridge" % ship_id)
		var roles := {}
		for entry in plan.seat_list:
			roles[entry["role"]] = true
		for role in [&"pilot", &"captain", &"engineer"]:
			assert_true(roles.has(role), "%s: a %s on the bridge or about the ship" % [ship_id, role])
		assert_true(plan.crew.size() >= 8, "%s: crew standing about the ship" % ship_id)


func test_every_ship_has_a_captains_bay_corridors_and_an_airlock() -> void:
	for ship_id in IDS:
		var plan := _plan(ship_id)
		var kinds := {}
		for room_id in plan.layout.rooms:
			kinds[plan.kinds[room_id]] = int(kinds.get(plan.kinds[room_id], 0)) + 1
		assert_true(kinds.has(&"captain"), "%s: a captain's bay" % ship_id)
		assert_true(kinds.has(&"corridor"), "%s: corridors" % ship_id)
		assert_true(kinds.has(&"airlock"), "%s: an airlock" % ship_id)
		var outer := 0
		var inner := 0
		for portal_id in plan.layout.portals:
			var portal: Portal = plan.layout.portals[portal_id]
			if portal.kind == Portal.Kind.AIRLOCK_OUTER:
				outer += 1
			elif portal.kind == Portal.Kind.AIRLOCK_INNER:
				inner += 1
		assert_true(outer >= 1 and inner >= 1, "%s: an airlock with an inner and an outer door" % ship_id)


func test_rooms_keep_a_wall_apart_and_every_door_joins_two_rooms() -> void:
	for ship_id in IDS:
		var layout := _plan(ship_id).layout
		var ids := layout.rooms.keys()
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				var a: Rect2 = layout.rooms[ids[i]]
				var b: Rect2 = layout.rooms[ids[j]]
				assert_true(not a.grow(0.19).intersects(b), "%s: %s and %s keep a wall between them" % [ship_id, ids[i], ids[j]])
		for portal_id in layout.portals:
			var portal: Portal = layout.portals[portal_id]
			var joined := layout.portal_rooms(portal_id)
			var wanted := 1 if portal.kind == Portal.Kind.AIRLOCK_OUTER else 2
			assert_eq(joined.size(), wanted, "%s: door %s joins %d room(s)" % [ship_id, portal_id, wanted])


func test_every_room_is_reached_through_doors_from_the_spawn_room() -> void:
	for ship_id in IDS:
		var plan := _plan(ship_id)
		var layout := plan.layout
		var start := layout.room_at(plan.spawn.x, plan.spawn.z)
		assert_true(start != &"", "%s: the player starts in a room" % ship_id)
		var seen := {start: true}
		var queue: Array = [start]
		while not queue.is_empty():
			var here: StringName = queue.pop_front()
			for portal_id in layout.portals:
				var joined := layout.portal_rooms(portal_id)
				if joined.size() == 2 and here in joined:
					var other: StringName = joined[1] if joined[0] == here else joined[0]
					if not seen.has(other):
						seen[other] = true
						queue.append(other)
		assert_eq(seen.size(), layout.rooms.size(), "%s: every room can be reached" % ship_id)


func test_furniture_stays_in_its_room_and_seats_are_in_the_room_they_name() -> void:
	for ship_id in IDS:
		var plan := _plan(ship_id)
		var layout := plan.layout
		for piece in layout.furniture:
			var at: Vector2 = piece["at"]
			assert_true(layout.room_at(at.x, at.y) != &"", "%s: %s stands in a room" % [ship_id, piece["name"]])
		for entry in plan.seat_list:
			var seat_position: Vector3 = entry["position"]
			assert_eq(layout.room_at(seat_position.x, seat_position.z), entry["room"], "%s: seat %s is in %s" % [ship_id, entry["id"], entry["room"]])
			var exit_position: Vector3 = entry["exit"]
			assert_true(layout.is_position_walkable(exit_position.x, exit_position.z, InteriorBody.RADIUS), "%s: you can stand up from seat %s" % [ship_id, entry["id"]])
		for member in plan.crew:
			var spot: Vector3 = member["position"]
			assert_true(layout.is_position_walkable(spot.x, spot.z, InteriorBody.RADIUS), "%s: the %s stands on open floor" % [ship_id, member["role"]])
		assert_true(layout.is_position_walkable(plan.spawn.x, plan.spawn.z, InteriorBody.RADIUS), "%s: the player starts on open floor" % ship_id)


func test_inside_each_room_every_door_and_seat_can_be_walked_to() -> void:
	for ship_id in IDS:
		var plan := _plan(ship_id)
		var layout := plan.layout
		for portal_id in layout.portals:
			var portal: Portal = layout.portals[portal_id]
			portal.open_factor = 1.0
		for room_id in layout.rooms:
			var room: Rect2 = layout.rooms[room_id]
			var points: Array[Vector2] = []
			for portal_id in layout.portals:
				var portal: Portal = layout.portals[portal_id]
				if not room_id in layout.portal_rooms(portal_id):
					continue
				points.append(_door_point(room, portal.opening))
			for entry in plan.seat_list:
				if entry["room"] == room_id:
					var exit_position: Vector3 = entry["exit"]
					points.append(Vector2(exit_position.x, exit_position.z))
			if points.size() < 2:
				continue
			assert_true(_all_reachable(layout, room, points), "%s: inside %s every door and seat can be reached" % [ship_id, room_id])


## A spot 0.5 m inside `room` from the middle of a doorway.
func _door_point(room: Rect2, opening: Rect2) -> Vector2:
	var middle := opening.get_center()
	if opening.size.x > opening.size.y: # a door in a wall that runs along x: step in along z
		return Vector2(middle.x, room.position.y + 0.5 if middle.y < room.get_center().y else room.end.y - 0.5)
	return Vector2(room.position.x + 0.5 if middle.x < room.get_center().x else room.end.x - 0.5, middle.y)


## Flood fill over a 0.2 m lattice of one room, with the real walkability rules, from the first point; true when it reaches every other point.
func _all_reachable(layout: InteriorLayout, room: Rect2, points: Array[Vector2]) -> bool:
	var step := 0.2
	var origin := room.position
	var columns := int(room.size.x / step) + 1
	var rows := int(room.size.y / step) + 1
	var seen := {}
	var queue: Array[Vector2i] = [_cell(points[0], origin, step)]
	seen[queue[0]] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + offset
			if next.x < 0 or next.y < 0 or next.x >= columns or next.y >= rows or seen.has(next):
				continue
			var spot := origin + Vector2(next) * step
			if layout.is_position_walkable(spot.x, spot.y, InteriorBody.RADIUS):
				seen[next] = true
				queue.append(next)
	for point in points:
		var target := _cell(point, origin, step)
		var found := false
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if seen.has(target + Vector2i(dx, dz)):
					found = true
		if not found:
			return false
	return true


func _cell(point: Vector2, origin: Vector2, step: float) -> Vector2i:
	return Vector2i(int(roundf((point.x - origin.x) / step)), int(roundf((point.y - origin.y) / step)))


func test_the_interior_builds_and_its_doors_open_and_close() -> void:
	for ship_id in IDS:
		var plan := _plan(ship_id)
		var interior := Interior.new()
		interior.build(plan)
		assert_true(interior.get_child_count() > 20, "%s: floors, walls, furniture, lamps and doors were made" % ship_id)
		var door_id: StringName = &""
		for portal_id in plan.layout.portals:
			if (plan.layout.portals[portal_id] as Portal).kind == Portal.Kind.DOOR:
				door_id = portal_id
				break
		var door: Portal = plan.layout.portals[door_id]
		var middle := door.opening.get_center()
		assert_true(not door.is_passable(), "%s: doors start shut" % ship_id)
		for i in 20:
			interior.update(Vector3(middle.x, 0.0, middle.y), 0.1)
		assert_true(door.is_passable(), "%s: a door opens for someone standing at it" % ship_id)
		for i in 20:
			interior.update(Vector3(middle.x + 30.0, 0.0, middle.y + 30.0), 0.1)
		assert_true(door.is_fully_closed(), "%s: and shuts again when they leave" % ship_id)
		interior.free()


func test_each_big_ship_lists_its_engine_nozzles_at_the_tail_with_a_radius_apiece() -> void:
	for def in Catalog.all():
		assert_true(def.engines.size() >= 2, "%s has engine nozzles" % def.display_name)
		assert_eq(def.engine_radii.size(), def.engines.size(), "%s: a radius per nozzle" % def.display_name)
		for nozzle in def.engines:
			assert_true(absf(nozzle.x) <= def.hull_extent * 0.5 and nozzle.z <= def.hull_extent * 0.55, "%s: nozzle %s sits on the hull" % [def.display_name, nozzle])
