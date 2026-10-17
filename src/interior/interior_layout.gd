class_name InteriorLayout
extends RefCounted
## Authored shape of one ship interior, in ship-local metres (x right, y up, -z forward): room
## rectangles on a single deck, portals between them, seats and interaction points. IDs are
## authored strings so saves can refer to them. Pure data plus walkability queries.

var floor_y := -0.9
var ceiling_y := 1.7
var rooms := {}    # StringName -> Rect2 (x, z)
var portals := {}  # StringName -> Portal
var seats := {}    # StringName -> {position: Vector3, exit_position: Vector3, facing_yaw: float}
var interact_points := [] # {id, position: Vector3, radius: float}
## Walkway (ramp) footprint behind the outer door; only walkable while the walkway is deployed.
var ramp_rect := Rect2()
var ramp_walkable := false
## Ship-local y at the far end of the ramp (set when the walkway deploys onto the ground).
var ramp_end_y := -2.0


## The player ship used by the game. Numbers are placeholder-scale (about 13 m long).
static func player_ship() -> InteriorLayout:
	var layout := InteriorLayout.new()
	layout.rooms[&"cockpit"] = Rect2(-2.0, -7.0, 4.0, 3.4)
	layout.rooms[&"cabin"] = Rect2(-3.0, -3.4, 6.0, 6.8)
	layout.rooms[&"airlock"] = Rect2(-1.4, 3.6, 2.8, 2.4)
	layout.portals[&"cockpit_door"] = Portal.new(&"cockpit_door", Portal.Kind.DOOR, Rect2(-0.7, -3.6, 1.4, 0.2))
	layout.portals[&"airlock_inner"] = Portal.new(&"airlock_inner", Portal.Kind.AIRLOCK_INNER, Rect2(-0.7, 3.4, 1.4, 0.2))
	layout.portals[&"airlock_outer"] = Portal.new(&"airlock_outer", Portal.Kind.AIRLOCK_OUTER, Rect2(-0.7, 6.0, 1.4, 0.2))
	layout.ramp_rect = Rect2(-0.9, 6.2, 1.8, 4.2)
	layout.seats[&"pilot_seat"] = {"position": Vector3(0, layout.floor_y, -5.4), "exit_position": Vector3(0, layout.floor_y, -4.95), "facing_yaw": 0.0}
	# Panels on both sides of each door; radii chosen so neighbouring panels do not overlap much.
	layout.interact_points = [
		{"id": &"cockpit_door", "position": Vector3(1.0, layout.floor_y, -3.8), "radius": 1.0},
		{"id": &"cockpit_door", "position": Vector3(1.0, layout.floor_y, -3.2), "radius": 1.0},
		{"id": &"airlock_inner", "position": Vector3(1.0, layout.floor_y, 3.0), "radius": 1.0},
		{"id": &"airlock_inner", "position": Vector3(1.2, layout.floor_y, 3.9), "radius": 0.7},
		{"id": &"airlock_outer", "position": Vector3(1.2, layout.floor_y, 5.4), "radius": 0.9},
		{"id": &"pilot_seat", "position": Vector3(0, layout.floor_y, -5.4), "radius": 1.2}]
	return layout


## True when a person of this radius standing at (x, z) is entirely on walkable floor.
func is_position_walkable(x: float, z: float, radius: float) -> bool:
	# The centre is checked too: walls are thinner than a person, so all four corners can be in
	# rooms on opposite sides of a wall while the centre is inside it.
	return _is_point_walkable(x, z) and _is_point_walkable(x - radius, z - radius) and _is_point_walkable(x + radius, z - radius) \
		and _is_point_walkable(x - radius, z + radius) and _is_point_walkable(x + radius, z + radius)


func _is_point_walkable(x: float, z: float) -> bool:
	var point := Vector2(x, z)
	for room in rooms.values():
		if (room as Rect2).has_point(point):
			return true
	for portal in portals.values():
		if (portal as Portal).opening.has_point(point):
			return (portal as Portal).is_passable()
	return ramp_walkable and ramp_rect.has_point(point)


## Floor height (ship-local y) under (x, z): flat deck, sloping down along the ramp.
func floor_height_at(x: float, z: float) -> float:
	if ramp_rect.has_point(Vector2(x, z)):
		return lerpf(floor_y, ramp_end_y, clampf((z - ramp_rect.position.y) / ramp_rect.size.y, 0.0, 1.0))
	return floor_y


func room_at(x: float, z: float) -> StringName:
	for room_id in rooms:
		if (rooms[room_id] as Rect2).has_point(Vector2(x, z)):
			return room_id
	return &""


## Nearest interaction point within its radius of a ship-local position, or &"" if none.
func nearest_interaction(local_position: Vector3) -> StringName:
	var best := &""
	var best_distance := INF
	for point in interact_points:
		var distance := Vector2(local_position.x - point["position"].x, local_position.z - point["position"].z).length()
		if distance <= point["radius"] and distance < best_distance:
			best = point["id"]
			best_distance = distance
	return best
