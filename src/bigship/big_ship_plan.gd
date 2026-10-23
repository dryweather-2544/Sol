extends RefCounted
## One big ship's interior as the game uses it: an InteriorLayout (rooms, doors, seats, furniture, windows) built from the generated data
## (big_ship_data.gd), plus what the walkable view needs on top: what each room is, where the player starts, who sits where and who stands where.
## Usage: var plan := Plan.new(); plan.load_ship("meridian")

const Data := preload("res://src/bigship/big_ship_data.gd")
const CAPTAIN_ROLE := &"captain"
## The control-room model that dresses every bridge (see ATTRIBUTION.md): files under assets/ships/kit/, cut to the front 6.7 or 7.7 m. Model space:
## the nose wall is at z -19.78 and the middle of the room at x 0.525; the room is 12.05 m wide.
const BRIDGE_DIR := "res://assets/ships/kit/"
const BRIDGE_MODEL_NOSE_Z := -19.78
const BRIDGE_MODEL_CENTRE_X := 0.525
const BRIDGE_MODEL_WIDTH := 12.05
## Seats on the model's own chairs: [x, z, yaw, exit x, exit z] in model space. The first three are the pilot, copilot and captain, the rest are the
## side stations, left and right alternating.
const BRIDGE_SEAT_SLOTS := [
	[-1.08, -15.55, 0.0, -1.08, -14.55], [2.1, -15.55, 0.0, 2.1, -14.55], [0.52, -15.28, 0.0, 0.52, -14.2],
	[-3.9, -16.4, 1.5708, -3.0, -16.4], [5.1, -16.2, -1.5708, 4.2, -16.2], [-3.9, -15.5, 1.5708, -3.0, -15.5], [5.1, -15.2, -1.5708, 4.2, -15.2],
	[-3.9, -14.5, 1.5708, -3.0, -14.5], [5.1, -14.2, -1.5708, 4.2, -14.2]]

var id := ""
var display_name := ""
var layout := InteriorLayout.new()
## Room id (StringName) -> what it is (StringName: bridge, captain, corridor, quarters ...).
var kinds := {}
## Room id (StringName) -> name to show (String).
var names := {}
var spawn := Vector3.ZERO
var spawn_yaw := 0.0
## Seats in the order authored: {id, role, room, position (the floor point under the seat), yaw, exit (the floor point to stand at)}.
var seat_list: Array = []
## Standing crew: {role, room, position, yaw}.
var crew: Array = []
## Bridges dressed with the control-room model: room id -> {room (Rect2), file, scale_x}. Empty when the model files are not on this machine.
var bridges := {}


## Builds everything from the data; false when there is no ship of that id.
func load_ship(ship_id: String) -> bool:
	if not Data.SHIPS.has(ship_id):
		return false
	var data: Dictionary = Data.SHIPS[ship_id]
	id = ship_id
	display_name = str(data["name"])
	layout = InteriorLayout.new()
	layout.floor_y = float(data["floor_y"])
	layout.ceiling_y = float(data["ceiling_y"])
	var floor_y := layout.floor_y
	var rooms: Dictionary = data["rooms"]
	for room_key in rooms:
		var r: Array = rooms[room_key]
		layout.rooms[StringName(room_key)] = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	var kind_data: Dictionary = data["kinds"]
	for room_key in kind_data:
		kinds[StringName(room_key)] = StringName(str(kind_data[room_key]))
	var name_data: Dictionary = data["names"]
	for room_key in name_data:
		names[StringName(room_key)] = str(name_data[room_key])
	for entry in data["portals"]:
		var kind := Portal.Kind.DOOR
		if entry[1] == "airlock_inner":
			kind = Portal.Kind.AIRLOCK_INNER
		elif entry[1] == "airlock_outer":
			kind = Portal.Kind.AIRLOCK_OUTER
		var opening := Rect2(float(entry[2]), float(entry[3]), float(entry[4]), float(entry[5]))
		var portal_id := StringName(str(entry[0]))
		layout.portals[portal_id] = Portal.new(portal_id, kind, opening)
		var middle := opening.get_center()
		layout.interact_points.append({"id": portal_id, "position": Vector3(middle.x, floor_y, middle.y), "radius": 1.2})
	for entry in data["seats"]:
		var seat_id := StringName(str(entry[0]))
		var seat_position := Vector3(float(entry[3]), floor_y, float(entry[4]))
		var exit_position := Vector3(float(entry[6]), floor_y, float(entry[7]))
		layout.seats[seat_id] = {"position": seat_position, "exit_position": exit_position, "facing_yaw": float(entry[5])}
		layout.interact_points.append({"id": seat_id, "position": seat_position, "radius": 1.2})
		layout.stations[seat_id] = {"role": StringName(str(entry[1])), "room": StringName(str(entry[2]))}
		seat_list.append({"id": seat_id, "role": StringName(str(entry[1])), "room": StringName(str(entry[2])), "position": seat_position, "yaw": float(entry[5]), "exit": exit_position})
	for entry in data["furniture"]:
		layout.add_piece(StringName(str(entry[0])), Vector2(float(entry[1]), float(entry[2])), Vector3(float(entry[3]), float(entry[4]), float(entry[5])),
				StringName(str(entry[7])), bool(entry[8]), float(entry[6]))
	for entry in data["windows"]:
		layout.windows.append({"room": StringName(str(entry[0])), "side": str(entry[1]), "center": float(entry[2]), "width": float(entry[3]),
				"sill": float(entry[4]), "height": float(entry[5])})
	for entry in data["npcs"]:
		crew.append({"role": StringName(str(entry[0])), "room": StringName(str(entry[1])), "position": Vector3(float(entry[2]), floor_y, float(entry[3])), "yaw": float(entry[4])})
	var start: Array = data["spawn"]
	spawn = Vector3(float(start[0]), floor_y, float(start[1]))
	spawn_yaw = float(start[2])
	_dress_bridges()
	return true


## The seat with this id, or an empty Dictionary.
func seat(seat_id: StringName) -> Dictionary:
	for entry in seat_list:
		if entry["id"] == seat_id:
			return entry
	return {}


## The seat nearest to a floor point within `reach` metres, or &"".
func nearest_seat(floor_point: Vector3, reach: float) -> StringName:
	var best := &""
	var best_distance := reach
	for entry in seat_list:
		var seat_position: Vector3 = entry["position"]
		var distance := Vector2(floor_point.x - seat_position.x, floor_point.z - seat_position.z).length()
		if distance <= best_distance:
			best = entry["id"]
			best_distance = distance
	return best


## How many seats a room has.
func seats_in(room_id: StringName) -> int:
	var count := 0
	for entry in seat_list:
		if entry["room"] == room_id:
			count += 1
	return count


func room_name(room_id: StringName) -> String:
	return str(names.get(room_id, ""))


## The nose-to-tail length of the interior in metres (first to last room).
func length() -> float:
	var low := INF
	var high := -INF
	for room in layout.rooms.values():
		low = minf(low, (room as Rect2).position.y)
		high = maxf(high, (room as Rect2).end.y)
	return high - low


## A point of the control-room model (x, z) as a ship-local point in a dressed bridge.
func bridge_point(room_id: StringName, model_x: float, model_z: float) -> Vector2:
	var info: Dictionary = bridges[room_id]
	var room: Rect2 = info["room"]
	return Vector2(room.get_center().x + (model_x - BRIDGE_MODEL_CENTRE_X) * float(info["scale_x"]), room.position.y + (model_z - BRIDGE_MODEL_NOSE_Z) * float(info["scale_z"]))


## Swaps the generated bridge furniture, windows and seats for the control-room model's: its own consoles, chairs and nose window.
func _dress_bridges() -> void:
	bridges.clear()
	for room_id in layout.rooms:
		if str(kinds.get(room_id, "")) != "bridge":
			continue
		var room: Rect2 = layout.rooms[room_id]
		var file := "bridge_7.7.glb" if room.size.y >= 7.9 else "bridge_6.7.glb"
		if not FileAccess.file_exists(ProjectSettings.globalize_path(BRIDGE_DIR + file)):
			continue
		var scale_x := minf(1.35, (room.size.x - 0.2) / BRIDGE_MODEL_WIDTH)
		var model_depth := 6.58 if file == "bridge_6.7.glb" else 7.58
		bridges[room_id] = {"room": room, "file": file, "scale_x": scale_x, "scale_z": clampf((room.size.y - 0.36) / model_depth, 0.9, 1.15)}
		# the generated furniture goes, and with it its solid footprints
		var kept: Array = []
		for piece in layout.furniture:
			if not room.has_point(piece["at"]):
				kept.append(piece)
		layout.furniture = kept
		layout.obstacles.clear()
		for piece in kept:
			if bool(piece["solid"]):
				var at: Vector2 = piece["at"]
				var size: Vector3 = piece["size"]
				layout.obstacles.append(Rect2(at.x - size.x * 0.5, at.y - size.z * 0.5, size.x, size.z))
		# one big nose window where the model has its glass; the side windows would be behind its walls
		var kept_windows: Array = []
		for window in layout.windows:
			if window["room"] != room_id:
				kept_windows.append(window)
		layout.windows = kept_windows
		var glass := bridge_point(room_id, 1.0, BRIDGE_MODEL_NOSE_Z)
		layout.windows.append({"room": room_id, "side": "nose", "center": glass.x, "width": 4.0 * scale_x, "sill": 0.7, "height": 1.4})
		# solid: the two window desks, and the room beside the model's side walls when the model is narrower than the room
		_bridge_block(room_id, -1.95, -17.3, -0.2, -16.0)
		_bridge_block(room_id, 1.2, -17.3, 2.95, -16.0)
		var left_wall := bridge_point(room_id, -5.5, 0.0).x
		var right_wall := bridge_point(room_id, 6.55, 0.0).x
		if left_wall > room.position.x + 0.05:
			layout.obstacles.append(Rect2(room.position.x, room.position.y, left_wall - room.position.x, room.size.y))
		if right_wall < room.end.x - 0.05:
			layout.obstacles.append(Rect2(right_wall, room.position.y, room.end.x - right_wall, room.size.y))
		_seat_bridge(room_id)


func _bridge_block(room_id: StringName, x0: float, z0: float, x1: float, z1: float) -> void:
	var a := bridge_point(room_id, x0, z0)
	var b := bridge_point(room_id, x1, z1)
	layout.obstacles.append(Rect2(a, b - a).abs())


## Moves the bridge's seats onto the model's chairs: pilot, copilot and captain first, the others at the side stations. Any seat the model has no chair
## for gets a generated chair.
func _seat_bridge(room_id: StringName) -> void:
	var mine: Array = []
	for entry in seat_list:
		if entry["room"] == room_id:
			mine.append(entry)
	var ordered: Array = []
	for role in [&"pilot", &"copilot", &"captain"]:
		for entry in mine:
			if entry["role"] == role and not ordered.has(entry):
				ordered.append(entry)
	for entry in mine:
		if not ordered.has(entry):
			ordered.append(entry)
	for index in ordered.size():
		var slot: Array = BRIDGE_SEAT_SLOTS[mini(index, BRIDGE_SEAT_SLOTS.size() - 1)]
		var seat_xz := bridge_point(room_id, float(slot[0]), float(slot[1]))
		var exit_xz := bridge_point(room_id, float(slot[3]), float(slot[4]))
		var entry: Dictionary = ordered[index]
		var seat_position := Vector3(seat_xz.x, layout.floor_y, seat_xz.y)
		var exit_position := Vector3(exit_xz.x, layout.floor_y, exit_xz.y)
		entry["position"] = seat_position
		entry["yaw"] = float(slot[2])
		entry["exit"] = exit_position
		var seat_id: StringName = entry["id"]
		layout.seats[seat_id] = {"position": seat_position, "exit_position": exit_position, "facing_yaw": float(slot[2])}
		for point in layout.interact_points:
			if point["id"] == seat_id:
				point["position"] = seat_position
		# the model's own chairs are at the captain's and the four side stations; the window desks and any extra seat need one
		if index >= 7:
			_add_bridge_chair(seat_xz, float(slot[2]))


func _add_bridge_chair(at: Vector2, yaw: float) -> void:
	var back := Vector2(sin(yaw), cos(yaw)) * 0.24
	var wide := absf(sin(yaw)) > 0.5
	layout.add_piece(&"chair_base", at, Vector3(0.55, 0.42, 0.55), &"steel")
	layout.add_piece(&"chair_seat", at, Vector3(0.52, 0.1, 0.52), &"fabric", false, 0.42)
	layout.add_piece(&"chair_back", at + back, Vector3(0.1 if wide else 0.5, 0.6, 0.5 if wide else 0.1), &"fabric", false, 0.5)
