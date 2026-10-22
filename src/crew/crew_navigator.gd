class_name CrewNavigator
extends RefCounted
## Routes through the ship's rooms: a breadth-first search over rooms joined by plain doors (crew never use the
## airlock), turned into waypoints that line up with each doorway. Inside a room any two points are connected by a
## straight line, because rooms are rectangles. Pure logic.

const DOORWAY_APPROACH := 0.5 ## how far either side of a door the line-up waypoints sit


## Waypoints ({position, door}) from one ship-local (x, z) to another; [] if there is no way (or no need).
static func route(layout: InteriorLayout, from_xz: Vector2, to_xz: Vector2) -> Array:
	var start_room := room_near(layout, from_xz)
	var goal_room := room_near(layout, to_xz)
	if start_room == &"" or goal_room == &"":
		return []
	var came_from := {start_room: null}
	var queue: Array = [start_room]
	while not queue.is_empty() and not came_from.has(goal_room):
		var current: StringName = queue.pop_front()
		for portal_id in layout.portals:
			if (layout.portals[portal_id] as Portal).kind != Portal.Kind.DOOR:
				continue
			var joined := layout.portal_rooms(portal_id)
			if joined.size() != 2 or not joined.has(current):
				continue
			var other: StringName = joined[1] if joined[0] == current else joined[0]
			if not came_from.has(other):
				came_from[other] = {"room": current, "portal": portal_id}
				queue.append(other)
	if not came_from.has(goal_room):
		return []
	var hops: Array = []
	var cursor: StringName = goal_room
	while came_from[cursor] != null:
		hops.push_front({"from": came_from[cursor]["room"], "to": cursor, "portal": came_from[cursor]["portal"]})
		cursor = came_from[cursor]["room"]
	var waypoints: Array = []
	for hop in hops:
		var opening: Rect2 = (layout.portals[hop["portal"]] as Portal).opening
		var centre := opening.get_center()
		var travel := (layout.rooms[hop["to"]] as Rect2).get_center() - (layout.rooms[hop["from"]] as Rect2).get_center()
		# A door in a wall running along x is crossed along z; a side-wall door is crossed along x.
		var along := Vector2(0.0, signf(travel.y)) if opening.size.x >= opening.size.y else Vector2(signf(travel.x), 0.0)
		waypoints.append({"position": centre - along * DOORWAY_APPROACH, "door": hop["portal"]})
		waypoints.append({"position": centre + along * DOORWAY_APPROACH, "door": &""})
	waypoints.append({"position": to_xz, "door": &""})
	return waypoints


## The room containing a point, or (for a point in a doorway or wall) the nearest room.
static func room_near(layout: InteriorLayout, point: Vector2) -> StringName:
	var inside := layout.room_at(point.x, point.y)
	if inside != &"":
		return inside
	var best := &""
	var best_distance := INF
	for room_id in layout.rooms:
		var rect: Rect2 = layout.rooms[room_id]
		var closest := Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))
		if closest.distance_to(point) < best_distance:
			best_distance = closest.distance_to(point)
			best = room_id
	return best
