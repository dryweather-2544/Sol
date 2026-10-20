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
## interact point id -> {role, room} for the points a crew member works at (seats, panels, lockers).
var stations := {}
## Walkway (ramp) footprint behind the outer door; only walkable while the walkway is deployed.
var ramp_rect := Rect2()
var ramp_walkable := false
## Ship-local y at the far end of the ramp (set when the walkway deploys onto the ground).
var ramp_end_y := -2.0


## The player ship used by the game, nose at -z, six rooms in a line (about 18 m long):
## cockpit - cabin - engineering - turret room - cargo - airlock, a door between each pair.
## Numbers are placeholder-scale.
static func player_ship() -> InteriorLayout:
	var layout := InteriorLayout.new()
	layout.rooms[&"cockpit"] = Rect2(-2.0, -7.0, 4.0, 3.4)
	layout.rooms[&"cabin"] = Rect2(-3.0, -3.4, 6.0, 3.2)
	layout.rooms[&"engineering"] = Rect2(-3.0, 0.0, 6.0, 3.2)
	layout.rooms[&"turret_room"] = Rect2(-2.0, 3.4, 4.0, 2.2)
	layout.rooms[&"cargo"] = Rect2(-3.0, 5.8, 6.0, 2.2)
	layout.rooms[&"airlock"] = Rect2(-1.4, 8.2, 2.8, 2.4)
	layout.portals[&"cockpit_door"] = Portal.new(&"cockpit_door", Portal.Kind.DOOR, Rect2(-0.7, -3.6, 1.4, 0.2))
	layout.portals[&"engineering_door"] = Portal.new(&"engineering_door", Portal.Kind.DOOR, Rect2(-0.7, -0.2, 1.4, 0.2))
	layout.portals[&"turret_door"] = Portal.new(&"turret_door", Portal.Kind.DOOR, Rect2(-0.7, 3.2, 1.4, 0.2))
	layout.portals[&"cargo_door"] = Portal.new(&"cargo_door", Portal.Kind.DOOR, Rect2(-0.7, 5.6, 1.4, 0.2))
	layout.portals[&"airlock_inner"] = Portal.new(&"airlock_inner", Portal.Kind.AIRLOCK_INNER, Rect2(-0.7, 8.0, 1.4, 0.2))
	layout.portals[&"airlock_outer"] = Portal.new(&"airlock_outer", Portal.Kind.AIRLOCK_OUTER, Rect2(-0.7, 10.6, 1.4, 0.2))
	layout.ramp_rect = Rect2(-0.9, 10.8, 1.8, 4.2)
	layout.seats[&"pilot_seat"] = {"position": Vector3(0, layout.floor_y, -5.4), "exit_position": Vector3(0, layout.floor_y, -4.95), "facing_yaw": 0.0}
	layout.seats[&"gunner_seat"] = {"position": Vector3(0, layout.floor_y, 4.7), "exit_position": Vector3(0, layout.floor_y, 4.1), "facing_yaw": PI}
	# Panels on both sides of each door; radii chosen so neighbouring panels do not overlap much.
	var floor_level := layout.floor_y
	layout.interact_points = [
		{"id": &"cockpit_door", "position": Vector3(1.0, floor_level, -3.8), "radius": 1.0},
		{"id": &"cockpit_door", "position": Vector3(1.0, floor_level, -3.2), "radius": 1.0},
		{"id": &"engineering_door", "position": Vector3(1.0, floor_level, -0.5), "radius": 1.0},
		{"id": &"engineering_door", "position": Vector3(1.0, floor_level, 0.3), "radius": 1.0},
		{"id": &"turret_door", "position": Vector3(1.0, floor_level, 2.9), "radius": 1.0},
		{"id": &"turret_door", "position": Vector3(1.0, floor_level, 3.7), "radius": 1.0},
		{"id": &"cargo_door", "position": Vector3(1.0, floor_level, 5.3), "radius": 1.0},
		{"id": &"cargo_door", "position": Vector3(1.0, floor_level, 6.1), "radius": 1.0},
		{"id": &"airlock_inner", "position": Vector3(1.0, floor_level, 7.6), "radius": 1.0},
		{"id": &"airlock_inner", "position": Vector3(1.2, floor_level, 8.5), "radius": 0.7},
		{"id": &"airlock_outer", "position": Vector3(1.2, floor_level, 10.0), "radius": 0.9},
		{"id": &"repair_panel", "position": Vector3(-2.7, floor_level, -1.0), "radius": 1.0},
		{"id": &"workbench", "position": Vector3(-2.7, floor_level, -2.5), "radius": 0.9},
		{"id": &"reactor_panel", "position": Vector3(-2.7, floor_level, 1.2), "radius": 1.1},
		{"id": &"engine_station", "position": Vector3(2.7, floor_level, 1.2), "radius": 1.1},
		{"id": &"extinguisher_locker", "position": Vector3(-2.7, floor_level, 2.7), "radius": 0.9},
		{"id": &"gunner_seat", "position": Vector3(0, floor_level, 4.7), "radius": 1.0},
		{"id": &"pilot_seat", "position": Vector3(0, floor_level, -5.4), "radius": 1.2}]
	# Who works where (research PULSAR 06: roles own stations). Crew AI and the HUD read this.
	layout.stations = {
		&"pilot_seat": {"role": &"pilot", "room": &"cockpit"},
		&"reactor_panel": {"role": &"engineer", "room": &"engineering"},
		&"engine_station": {"role": &"engineer", "room": &"engineering"},
		&"extinguisher_locker": {"role": &"engineer", "room": &"engineering"},
		&"gunner_seat": {"role": &"gunner", "room": &"turret_room"}}
	return layout


## Where a person stands to use an interaction point: the closest floor spot (clear of walls) that still counts
## as that point. Returns Vector2.INF if there is none.
func standing_spot_for(point_id: StringName, radius: float = InteriorBody.RADIUS) -> Vector2:
	var best := Vector2.INF
	var best_distance := INF
	for point in interact_points:
		if point["id"] != point_id:
			continue
		var centre := Vector2(point["position"].x, point["position"].z)
		var reach: float = point["radius"]
		var offset_x := -reach
		while offset_x <= reach:
			var offset_z := -reach
			while offset_z <= reach:
				var spot := centre + Vector2(offset_x, offset_z)
				if centre.distance_to(spot) < best_distance and is_position_walkable(spot.x, spot.y, radius) \
						and nearest_interaction(Vector3(spot.x, floor_y, spot.y)) == point_id:
					best = spot
					best_distance = centre.distance_to(spot)
				offset_z += 0.1
			offset_x += 0.1
	return best


## The two rooms a portal joins (ids), found by which room rectangles its opening touches.
func portal_rooms(portal_id: StringName) -> Array[StringName]:
	var joined: Array[StringName] = []
	var opening := (portals[portal_id] as Portal).opening.grow(0.05)
	for room_id in rooms:
		if (rooms[room_id] as Rect2).intersects(opening):
			joined.append(room_id)
	return joined


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
		return ramp_height_at(z)
	return floor_y


## Height (ship-local y) of the ramp surface at distance z along it, whether or not (x, z) is on the ramp itself.
func ramp_height_at(z: float) -> float:
	return lerpf(floor_y, ramp_end_y, clampf((z - ramp_rect.position.y) / ramp_rect.size.y, 0.0, 1.0))


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
