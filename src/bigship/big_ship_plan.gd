extends RefCounted
## One big ship's interior as the game uses it: an InteriorLayout (rooms, doors, seats, furniture, windows) built from the generated data
## (big_ship_data.gd), plus what the walkable view needs on top: what each room is, where the player starts, who sits where and who stands where.
## Usage: var plan := Plan.new(); plan.load_ship("meridian")

const Data := preload("res://src/bigship/big_ship_data.gd")
const CAPTAIN_ROLE := &"captain"

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
