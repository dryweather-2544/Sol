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
## Rooms that may be larger than the exterior hull (ADR 0012, "bigger on the inside"): drawn only while the camera is
## inside the ship. The others (cockpit, airlock) are the threshold: they fit in the hull and are always drawn.
var pocket_rooms: Array[StringName] = []
## Furniture pieces, the single source for both what is drawn and what is solid: {name, at (x, z centre), size (x, height, z),
## lift (above the floor), material (a key ShipVisuals maps to a material), solid}. Solid pieces also become `obstacles`.
var furniture: Array = []
var obstacles: Array[Rect2] = []
## Windows cut into a room's outside wall: {room, side ("nose" = -z, "tail" = +z, "left" = -x, "right" = +x), center (along the
## wall, x or z), width, sill (height above the floor), height}. Only in pocket rooms, where the hull is hidden and the world shows.
var windows: Array = []
## Wall screens on the machines: id -> {"position": Vector3, "size": Vector3}. ShipVisuals lights them from the ship's state.
var machine_screens := {}
const WALL_THICKNESS := 0.2
## Walkway (ramp) footprint behind the outer door; only walkable while the walkway is deployed.
var ramp_rect := Rect2()
var ramp_walkable := false
## Ship-local y at the far end of the ramp (set when the walkway deploys onto the ground).
var ramp_end_y := -2.0


## The player ship used by the game, nose at -z, six rooms in a line (about 18 m long):
## cockpit - cabin - engineering - turret room - cargo - airlock, a door between each pair.
## Bigger on the inside (ADR 0012): the cabin, engineering and cargo are 11 m wide and the turret room 8 m, in a hull
## 7.6 m wide (ShipHullCollision.HULL_HALF_WIDTH); the cockpit and airlock fit inside the hull.
## Numbers are placeholder-scale.
const POCKET_HALF_WIDTH := 5.5
## Wall panels stand this far in from a side wall's inner face.
const PANEL_INSET := 0.3

static func player_ship() -> InteriorLayout:
	var layout := InteriorLayout.new()
	var wide := POCKET_HALF_WIDTH
	layout.rooms[&"cockpit"] = Rect2(-2.0, -7.0, 4.0, 3.4)
	layout.rooms[&"cabin"] = Rect2(-wide, -3.4, wide * 2.0, 3.2)
	layout.rooms[&"engineering"] = Rect2(-wide, 0.0, wide * 2.0, 3.2)
	layout.rooms[&"turret_room"] = Rect2(-4.0, 3.4, 8.0, 2.2)
	layout.rooms[&"cargo"] = Rect2(-wide, 5.8, wide * 2.0, 2.2)
	layout.rooms[&"airlock"] = Rect2(-1.4, 8.2, 2.8, 2.4)
	# The living area and the med bay sit east of the cabin and engineering, reached by a side door (x 5.5..5.7) and a door
	# between them. Pocket rooms: bigger on the inside, drawn only while the camera is inside the ship.
	layout.rooms[&"living_area"] = Rect2(5.7, -3.4, 5.0, 3.2)
	layout.rooms[&"medical"] = Rect2(5.7, 0.0, 5.0, 3.2)
	layout.rooms[&"bathroom"] = Rect2(7.0, -5.6, 3.7, 2.0)
	layout.pocket_rooms = [&"cabin", &"engineering", &"turret_room", &"cargo", &"living_area", &"medical", &"bathroom"]
	var panel_x := wide - PANEL_INSET
	_add_furniture(layout)
	_add_machines(layout)
	layout.windows = [
		{"room": &"cabin", "side": "nose", "center": -4.6, "width": 1.4, "sill": 0.8, "height": 0.9},
		{"room": &"cabin", "side": "nose", "center": 4.6, "width": 1.4, "sill": 0.8, "height": 0.9},
		{"room": &"living_area", "side": "right", "center": -1.5, "width": 2.0, "sill": 0.9, "height": 0.8},
		{"room": &"medical", "side": "tail", "center": 8.2, "width": 2.0, "sill": 0.9, "height": 0.9},
		{"room": &"medical", "side": "right", "center": 2.75, "width": 0.7, "sill": 0.9, "height": 0.9},
		{"room": &"bathroom", "side": "nose", "center": 8.85, "width": 0.9, "sill": 1.1, "height": 0.6}]
	layout.portals[&"cockpit_door"] = Portal.new(&"cockpit_door", Portal.Kind.DOOR, Rect2(-0.7, -3.6, 1.4, 0.2))
	layout.portals[&"engineering_door"] = Portal.new(&"engineering_door", Portal.Kind.DOOR, Rect2(-0.7, -0.2, 1.4, 0.2))
	layout.portals[&"turret_door"] = Portal.new(&"turret_door", Portal.Kind.DOOR, Rect2(-0.7, 3.2, 1.4, 0.2))
	layout.portals[&"cargo_door"] = Portal.new(&"cargo_door", Portal.Kind.DOOR, Rect2(-0.7, 5.6, 1.4, 0.2))
	layout.portals[&"living_door"] = Portal.new(&"living_door", Portal.Kind.DOOR, Rect2(5.5, -2.3, 0.2, 1.4))
	layout.portals[&"medical_door"] = Portal.new(&"medical_door", Portal.Kind.DOOR, Rect2(7.5, -0.2, 1.4, 0.2))
	layout.portals[&"bathroom_door"] = Portal.new(&"bathroom_door", Portal.Kind.DOOR, Rect2(8.8, -3.6, 1.4, 0.2))
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
		{"id": &"living_door", "position": Vector3(5.0, floor_level, -1.9), "radius": 1.0},
		{"id": &"living_door", "position": Vector3(6.3, floor_level, -1.9), "radius": 1.0},
		{"id": &"medical_door", "position": Vector3(8.2, floor_level, -0.6), "radius": 0.8},
		{"id": &"medical_door", "position": Vector3(8.2, floor_level, 0.4), "radius": 0.8},
		{"id": &"bathroom_door", "position": Vector3(9.5, floor_level, -2.9), "radius": 0.8},
		{"id": &"bathroom_door", "position": Vector3(9.5, floor_level, -4.3), "radius": 0.8},
		{"id": &"bed", "position": Vector3(10.0, floor_level, -1.5), "radius": 1.8, "look_half": Vector3(0.8, 0.5, 1.2)},
		{"id": &"medbed", "position": Vector3(8.9, floor_level, 1.7), "radius": 1.6, "look_half": Vector3(0.7, 0.5, 1.1)},
		{"id": &"airlock_inner", "position": Vector3(1.0, floor_level, 7.6), "radius": 1.0},
		{"id": &"airlock_inner", "position": Vector3(1.2, floor_level, 8.5), "radius": 0.7},
		{"id": &"airlock_outer", "position": Vector3(1.2, floor_level, 10.0), "radius": 0.9},
		{"id": &"airlock_computer", "position": Vector3(-1.1, floor_level, 9.4), "radius": 0.7},
		{"id": &"ops_computer", "position": Vector3(3.0, floor_level, -1.15), "radius": 0.9},
		{"id": &"scanners", "position": Vector3(4.5, floor_level, -1.15), "radius": 0.9},
		{"id": &"ftl_radio", "position": Vector3(2.5, floor_level, -2.5), "radius": 0.9},
		{"id": &"battery_array", "position": Vector3(-4.5, floor_level, 6.9), "radius": 1.0},
		{"id": &"limnal_drive", "position": Vector3(4.4, floor_level, 6.9), "radius": 1.0},
		{"id": &"repair_panel", "position": Vector3(-panel_x, floor_level, -1.0), "radius": 1.0},
		{"id": &"workbench", "position": Vector3(-panel_x, floor_level, -2.5), "radius": 0.9},
		{"id": &"reactor_panel", "position": Vector3(-panel_x, floor_level, 1.2), "radius": 1.1},
		{"id": &"engine_station", "position": Vector3(panel_x, floor_level, 1.2), "radius": 1.1},
		{"id": &"extinguisher_locker", "position": Vector3(-panel_x, floor_level, 2.7), "radius": 0.9},
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


func add_piece(piece_name: StringName, at: Vector2, size: Vector3, material: StringName, solid := false, lift := 0.0) -> void:
	furniture.append({"name": piece_name, "at": at, "size": size, "lift": lift, "material": material, "solid": solid})
	if solid:
		obstacles.append(Rect2(at.x - size.x * 0.5, at.y - size.z * 0.5, size.x, size.z))


## The living area (x 5.7..10.7, z -3.4..-0.2), the med bay (x 5.7..10.7, z 0..3.2) and the bathroom (x 7..10.7, z -5.6..-3.6).
## The big pieces stand against the walls and are solid; a test checks every doorway and station can still be reached.
static func _add_furniture(layout: InteriorLayout) -> void:
	# Living area: the bed along the east wall, the locker and desk along the north wall either side of the bathroom door.
	layout.add_piece(&"bed_frame", Vector2(10.0, -1.5), Vector3(1.2, 0.45, 2.1), &"wood", true)
	layout.add_piece(&"bed_mattress", Vector2(10.0, -1.5), Vector3(1.1, 0.12, 2.0), &"linen", false, 0.45)
	layout.add_piece(&"pillow", Vector2(10.0, -2.25), Vector3(0.8, 0.12, 0.4), &"white", false, 0.57)
	layout.add_piece(&"desk_top", Vector2(7.7, -3.05), Vector3(1.6, 0.06, 0.6), &"wood", true, 0.74)
	layout.add_piece(&"desk_leg_a", Vector2(6.95, -3.05), Vector3(0.06, 0.74, 0.5), &"steel")
	layout.add_piece(&"desk_leg_b", Vector2(8.45, -3.05), Vector3(0.06, 0.74, 0.5), &"steel")
	layout.add_piece(&"chair_seat", Vector2(7.7, -2.45), Vector3(0.5, 0.08, 0.5), &"console", false, 0.42)
	layout.add_piece(&"chair_stem", Vector2(7.7, -2.45), Vector3(0.06, 0.42, 0.06), &"steel")
	layout.add_piece(&"desk_monitor", Vector2(7.7, -3.3), Vector3(0.6, 0.38, 0.05), &"screen", false, 1.0)
	layout.add_piece(&"locker", Vector2(6.3, -3.1), Vector3(0.7, 1.8, 0.5), &"console", true)
	# Med bay: the bed under a scanner arch, the cabinet on the east wall.
	layout.add_piece(&"medbed_frame", Vector2(8.9, 1.7), Vector3(1.0, 0.45, 2.0), &"white", true)
	layout.add_piece(&"medbed_pad", Vector2(8.9, 1.7), Vector3(0.9, 0.1, 1.9), &"glow_pad", false, 0.45)
	layout.add_piece(&"scanner_post_a", Vector2(8.25, 1.7), Vector3(0.08, 1.5, 0.08), &"steel")
	layout.add_piece(&"scanner_post_b", Vector2(9.55, 1.7), Vector3(0.08, 1.5, 0.08), &"steel")
	layout.add_piece(&"scanner_bar", Vector2(8.9, 1.7), Vector3(1.4, 0.08, 0.14), &"glow_teal", false, 1.5)
	layout.add_piece(&"med_cabinet", Vector2(10.4, 1.6), Vector3(0.5, 1.6, 1.4), &"white", true)
	layout.add_piece(&"cabinet_strip", Vector2(10.14, 1.6), Vector3(0.03, 0.5, 0.5), &"glow_green", false, 0.7)
	# Bathroom: sink with mirror and a toilet along the north wall, a shower stall in the west corner.
	layout.add_piece(&"sink_counter", Vector2(7.8, -5.35), Vector3(0.9, 0.85, 0.45), &"steel", true)
	layout.add_piece(&"sink_basin", Vector2(7.8, -5.35), Vector3(0.4, 0.04, 0.3), &"console", false, 0.85)
	layout.add_piece(&"mirror", Vector2(7.8, -5.58), Vector3(0.8, 0.6, 0.03), &"mirror", false, 1.2)
	layout.add_piece(&"toilet_bowl", Vector2(10.2, -5.3), Vector3(0.45, 0.4, 0.55), &"white", true)
	layout.add_piece(&"toilet_tank", Vector2(10.2, -5.5), Vector3(0.45, 0.35, 0.2), &"white", false, 0.4)
	layout.add_piece(&"shower_tray", Vector2(7.7, -4.3), Vector3(1.2, 0.08, 1.2), &"white")
	layout.add_piece(&"shower_glass", Vector2(8.32, -4.3), Vector3(0.04, 1.9, 1.2), &"glass", false, 0.08)
	layout.add_piece(&"shower_head", Vector2(7.2, -4.3), Vector3(0.05, 0.05, 0.35), &"steel", false, 2.0)


## Rodina's Machines (Items.ShipStatus / Scanners / FTL_Radio / BatteryArray / LimnalDrive) as solid wall units with a screen each.
## The generator is the reactor panel in engineering, so it has no unit of its own.
static func _add_machines(layout: InteriorLayout) -> void:
	var floor_level := layout.floor_y
	# The cabin's west wall already holds the repair panel and the workbench, and its nose windows end at x = +-3.9, so the cabin
	# machines stand on the tail wall (east of the engineering door) and on the nose wall between the cockpit door and the window.
	layout.add_piece(&"ops_computer_body", Vector2(3.0, -0.45), Vector3(1.2, 1.5, 0.5), &"console", true)
	layout.machine_screens[&"ops_computer"] = {"position": Vector3(3.0, floor_level + 1.1, -0.72), "size": Vector3(0.9, 0.45, 0.04)}
	layout.add_piece(&"scanners_body", Vector2(4.5, -0.45), Vector3(1.0, 1.6, 0.5), &"console", true)
	layout.add_piece(&"scanners_dish", Vector2(4.5, -0.45), Vector3(0.5, 0.1, 0.1), &"glow_teal", false, 1.6)
	layout.machine_screens[&"scanners"] = {"position": Vector3(4.5, floor_level + 1.1, -0.72), "size": Vector3(0.7, 0.4, 0.04)}
	layout.add_piece(&"ftl_radio_body", Vector2(2.5, -3.15), Vector3(0.9, 1.4, 0.5), &"console", true)
	layout.add_piece(&"ftl_radio_mast", Vector2(2.5, -3.15), Vector3(0.05, 0.6, 0.05), &"steel", false, 1.4)
	layout.machine_screens[&"ftl_radio"] = {"position": Vector3(2.5, floor_level + 1.0, -2.88), "size": Vector3(0.6, 0.35, 0.04)}
	layout.add_piece(&"battery_array_body", Vector2(-5.1, 6.9), Vector3(0.7, 1.2, 1.6), &"steel", true)
	layout.machine_screens[&"battery_array"] = {"position": Vector3(-4.73, floor_level + 0.8, 6.9), "size": Vector3(0.04, 0.3, 1.2)}
	layout.add_piece(&"limnal_drive_body", Vector2(5.0, 6.9), Vector3(1.0, 1.8, 1.6), &"console", true)
	layout.add_piece(&"limnal_drive_ring", Vector2(5.0, 6.9), Vector3(1.0, 0.12, 1.7), &"glow_teal", false, 1.2)
	layout.machine_screens[&"limnal_drive"] = {"position": Vector3(4.48, floor_level + 0.8, 6.9), "size": Vector3(0.04, 0.35, 0.8)}


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


## The 0.2 m wall skin just outside a room rectangle on one side, and whether it runs along x ("nose"/"tail") or z.
func wall_rect(room_id: StringName, side: String) -> Rect2:
	var room: Rect2 = rooms[room_id]
	var t := WALL_THICKNESS
	match side:
		"nose": return Rect2(room.position.x - t, room.position.y - t, room.size.x + 2.0 * t, t)
		"tail": return Rect2(room.position.x - t, room.end.y, room.size.x + 2.0 * t, t)
		"left": return Rect2(room.position.x - t, room.position.y, t, room.size.y)
	return Rect2(room.end.x, room.position.y, t, room.size.y)


static func wall_runs_along_x(side: String) -> bool:
	return side == "nose" or side == "tail"


## The windows cut into one wall of one room.
func windows_in(room_id: StringName, side: String) -> Array:
	return windows.filter(func(window): return window["room"] == room_id and window["side"] == side)


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
	# Furniture is solid: no part of the person may overlap a footprint.
	for obstacle in obstacles:
		if obstacle.grow(radius).has_point(Vector2(x, z)):
			return false
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


func is_pocket(room_id: StringName) -> bool:
	return room_id in pocket_rooms


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


## How far you can reach what you are looking at (Rodina: GetActivateEntity, 3 m).
const LOOK_REACH := 3.0
const DOOR_HEIGHT := 2.1
## Half-sizes of the box you can aim at for a station or seat, around its interaction point (x, y, z).
const STATION_HALF := Vector3(0.6, 1.0, 0.6)


## What the player is looking at: a door (the portal id) or a station/seat (the interaction point id), by casting a ray from
## the eye along the view direction (ship-local) up to `reach`. Only things in the room you stand in, or the doors of that room,
## can be targeted, so nothing is picked through a wall. Returns &"" when nothing is in reach.
func look_target(origin: Vector3, direction: Vector3, reach: float = LOOK_REACH) -> StringName:
	var best := &""
	var best_distance := INF
	var here := room_at(origin.x, origin.z)
	for portal_id in portals:
		var opening := (portals[portal_id] as Portal).opening
		if here == &"" or not here in portal_rooms(portal_id):
			if not opening.grow(0.6).has_point(Vector2(origin.x, origin.z)):
				continue
		var box_min := Vector3(opening.position.x, floor_y, opening.position.y - 0.25)
		var box_max := Vector3(opening.end.x, floor_y + DOOR_HEIGHT, opening.end.y + 0.25)
		var distance := _ray_box_distance(origin, direction, box_min, box_max)
		if distance >= 0.0 and distance <= reach and distance < best_distance:
			best = portal_id
			best_distance = distance
	for point in interact_points:
		var point_id: StringName = point["id"]
		if portals.has(point_id):
			continue
		var position: Vector3 = point["position"]
		if here == &"" or room_at(position.x, position.z) != here:
			continue
		var half: Vector3 = point.get("look_half", STATION_HALF)
		var centre := position + Vector3(0.0, half.y, 0.0)
		var distance := _ray_box_distance(origin, direction, centre - half, centre + half)
		if distance >= 0.0 and distance <= reach and distance < best_distance:
			best = point_id
			best_distance = distance
	return best


## Distance along a ray to an axis-aligned box (0 when the origin is inside it), or -1 for a miss.
static func _ray_box_distance(origin: Vector3, direction: Vector3, box_min: Vector3, box_max: Vector3) -> float:
	var near := 0.0
	var far := INF
	for axis in 3:
		if absf(direction[axis]) < 1e-9:
			if origin[axis] < box_min[axis] or origin[axis] > box_max[axis]:
				return -1.0
			continue
		var t1: float = (box_min[axis] - origin[axis]) / direction[axis]
		var t2: float = (box_max[axis] - origin[axis]) / direction[axis]
		near = maxf(near, minf(t1, t2))
		far = minf(far, maxf(t1, t2))
		if near > far:
			return -1.0
	return near
