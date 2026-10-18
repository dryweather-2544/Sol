class_name PoiBuilding
extends RefCounted
## A walk-in depot at an outpost: rooms of different types joined by doorways, generated from the POI seed by
## a small graph expander (start with an entrance hall; repeatedly bolt a new room, picked from typed
## templates, onto a free side of an existing one and cut a doorway between them). Pure data and queries.
## Coordinates are building-local metres: x right, z toward the outside; the entrance faces +z at z = 0
## and the rooms lie at z < 0. Not EGSL (research 05 says its semantics cannot be reproduced).

enum RoomType { HALL, STORAGE, CONTROL, QUARTERS, VAULT }

const WALL_THICKNESS := 0.4
const WALL_HEIGHT := 3.4
const DOOR_WIDTH := 2.0
const MIN_SHARED_EDGE := 3.0
const MAX_HALF_WIDTH := 34.0
const MAX_DEPTH := 44.0

## Template per room type: [min width, max width, min depth, max depth, crate count]
const TEMPLATES := {
	RoomType.STORAGE: [8.0, 12.0, 6.0, 10.0, 2],
	RoomType.CONTROL: [6.0, 9.0, 6.0, 9.0, 0],
	RoomType.QUARTERS: [6.0, 8.0, 5.0, 8.0, 1],
	RoomType.VAULT: [5.0, 7.0, 5.0, 7.0, 3],
}

class Room extends RefCounted:
	var type: int
	var rect: Rect2 ## x, z of the minimum corner and size
	var crates: Array[Vector2] = []

var rooms: Array[Room] = []
## Doorways as thin rectangles spanning the wall(s) they cut: {rect, room_a, room_b}; room_b = -1 for the entrance.
var doorways: Array[Dictionary] = []
var walls: Array[Rect2] = []
var seed_value := 0


static func generate(building_seed: int) -> PoiBuilding:
	var building := PoiBuilding.new()
	building.seed_value = building_seed
	var rng := SeedRng.new(SeedHash.combine(building_seed, SeedHash.string_hash("depot")))
	var hall := Room.new()
	hall.type = RoomType.HALL
	hall.rect = Rect2(-4.0, -7.0, 8.0, 7.0)
	building.rooms.append(hall)
	building.doorways.append({"rect": Rect2(-DOOR_WIDTH * 0.5, -WALL_THICKNESS * 0.5 - 0.2, DOOR_WIDTH, WALL_THICKNESS + 0.4), "room_a": 0, "room_b": -1})
	var target_rooms := rng.next_int_in_range(4, 6)
	var attempts := 0
	var type_cycle: Array = [RoomType.STORAGE, RoomType.CONTROL, RoomType.QUARTERS, RoomType.VAULT]
	while building.rooms.size() < target_rooms and attempts < 200:
		attempts += 1
		var parent_index := rng.next_int_in_range(0, building.rooms.size() - 1)
		var parent: Room = building.rooms[parent_index]
		var room_type: int = type_cycle[rng.next_int_in_range(0, type_cycle.size() - 1)]
		var template: Array = TEMPLATES[room_type]
		var width := snappedf(lerpf(template[0], template[1], rng.next_float()), 1.0)
		var depth := snappedf(lerpf(template[2], template[3], rng.next_float()), 1.0)
		var side := rng.next_int_in_range(0, 2) # 0 = toward -z (north), 1 = +x (east), 2 = -x (west)
		var candidate := _place(parent.rect, side, width, depth, rng.next_float())
		if not building._fits(candidate):
			continue
		var door := _doorway_between(parent.rect, candidate, side)
		if door.size == Vector2.ZERO:
			continue
		var room := Room.new()
		room.type = room_type
		room.rect = candidate
		var crate_count: int = template[4]
		for crate_index in crate_count:
			room.crates.append(Vector2(candidate.position.x + 1.2 + rng.next_float() * (candidate.size.x - 2.4), candidate.position.y + 1.2 + rng.next_float() * (candidate.size.y - 2.4)))
		building.rooms.append(room)
		building.doorways.append({"rect": door, "room_a": parent_index, "room_b": building.rooms.size() - 1})
	building._build_walls()
	return building


## Where a room of the given size goes next to `parent` on one side, offset along the shared edge by `slide` (0..1).
static func _place(parent: Rect2, side: int, width: float, depth: float, slide: float) -> Rect2:
	var gap := WALL_THICKNESS
	match side:
		0:
			var x := parent.position.x - width + MIN_SHARED_EDGE + slide * (parent.size.x + width - 2.0 * MIN_SHARED_EDGE)
			return Rect2(snappedf(x, 1.0), parent.position.y - gap - depth, width, depth)
		1:
			var z := parent.position.y - depth + MIN_SHARED_EDGE + slide * (parent.size.y + depth - 2.0 * MIN_SHARED_EDGE)
			return Rect2(parent.end.x + gap, snappedf(z, 1.0), width, depth)
		_:
			var z_west := parent.position.y - depth + MIN_SHARED_EDGE + slide * (parent.size.y + depth - 2.0 * MIN_SHARED_EDGE)
			return Rect2(parent.position.x - gap - width, snappedf(z_west, 1.0), width, depth)


func _fits(candidate: Rect2) -> bool:
	if candidate.end.y > -0.5 or candidate.position.y < -MAX_DEPTH or candidate.position.x < -MAX_HALF_WIDTH or candidate.end.x > MAX_HALF_WIDTH:
		return false
	for room in rooms:
		if room.rect.grow(WALL_THICKNESS * 0.9).intersects(candidate):
			return false
	return true


## Thin rectangle for a doorway centred on the shared edge between parent and child.
static func _doorway_between(parent: Rect2, child: Rect2, side: int) -> Rect2:
	var gap := WALL_THICKNESS
	if side == 0:
		var low := maxf(parent.position.x, child.position.x)
		var high := minf(parent.end.x, child.end.x)
		if high - low < MIN_SHARED_EDGE:
			return Rect2()
		var center := (low + high) * 0.5
		return Rect2(center - DOOR_WIDTH * 0.5, parent.position.y - gap - 0.2, DOOR_WIDTH, gap + 0.4)
	var low_z := maxf(parent.position.y, child.position.y)
	var high_z := minf(parent.end.y, child.end.y)
	if high_z - low_z < MIN_SHARED_EDGE:
		return Rect2()
	var center_z := (low_z + high_z) * 0.5
	if side == 1:
		return Rect2(parent.end.x - 0.2, center_z - DOOR_WIDTH * 0.5, gap + 0.4, DOOR_WIDTH)
	return Rect2(parent.position.x - gap - 0.2, center_z - DOOR_WIDTH * 0.5, gap + 0.4, DOOR_WIDTH)


func _build_walls() -> void:
	walls.clear()
	for room in rooms:
		var rect := room.rect
		var half := WALL_THICKNESS * 0.5
		# Each edge is a long thin rectangle sitting just outside the room, cut where doorways cross it.
		_add_wall_run(Rect2(rect.position.x - WALL_THICKNESS, rect.position.y - WALL_THICKNESS, rect.size.x + 2.0 * WALL_THICKNESS, WALL_THICKNESS), true) # north
		_add_wall_run(Rect2(rect.position.x - WALL_THICKNESS, rect.end.y, rect.size.x + 2.0 * WALL_THICKNESS, WALL_THICKNESS), true) # south
		_add_wall_run(Rect2(rect.position.x - WALL_THICKNESS, rect.position.y, WALL_THICKNESS, rect.size.y), false) # west
		_add_wall_run(Rect2(rect.end.x, rect.position.y, WALL_THICKNESS, rect.size.y), false) # east


## Adds `run` as wall segments, removing the parts covered by doorways.
func _add_wall_run(run: Rect2, along_x: bool) -> void:
	var pieces: Array[Rect2] = [run]
	for door in doorways:
		var door_rect: Rect2 = door["rect"]
		var next_pieces: Array[Rect2] = []
		for piece in pieces:
			if not piece.intersects(door_rect):
				next_pieces.append(piece)
				continue
			if along_x:
				if door_rect.position.x > piece.position.x:
					next_pieces.append(Rect2(piece.position.x, piece.position.y, door_rect.position.x - piece.position.x, piece.size.y))
				if door_rect.end.x < piece.end.x:
					next_pieces.append(Rect2(door_rect.end.x, piece.position.y, piece.end.x - door_rect.end.x, piece.size.y))
			else:
				if door_rect.position.y > piece.position.y:
					next_pieces.append(Rect2(piece.position.x, piece.position.y, piece.size.x, door_rect.position.y - piece.position.y))
				if door_rect.end.y < piece.end.y:
					next_pieces.append(Rect2(piece.position.x, door_rect.end.y, piece.size.x, piece.end.y - door_rect.end.y))
		pieces = next_pieces
	for piece in pieces:
		if piece.size.x > 0.01 and piece.size.y > 0.01:
			walls.append(piece)


## Every crate position (building-local), in room order.
func crate_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for room in rooms:
		positions.append_array(room.crates)
	return positions


## Rectangle enclosing the whole building (floor override region), with a margin.
func footprint(margin: float = 0.0) -> Rect2:
	var bounds := rooms[0].rect
	for room in rooms:
		bounds = bounds.merge(room.rect)
	return bounds.grow(WALL_THICKNESS + margin)


func room_index_at(point: Vector2) -> int:
	for index in rooms.size():
		if rooms[index].rect.has_point(point):
			return index
	return -1


## Rooms reachable from the entrance hall through doorways (for validation).
func reachable_room_count() -> int:
	var seen := {0: true}
	var frontier := [0]
	while not frontier.is_empty():
		var current: int = frontier.pop_back()
		for door in doorways:
			var other := -1
			if door["room_a"] == current:
				other = door["room_b"]
			elif door["room_b"] == current:
				other = door["room_a"]
			if other >= 0 and not seen.has(other):
				seen[other] = true
				frontier.append(other)
	return seen.size()


## Push a circle of the given radius out of every wall. Returns the corrected point.
func push_out_of_walls(point: Vector2, radius: float) -> Vector2:
	var corrected := point
	for pass_index in 2: # two passes settle corners
		for wall in walls:
			var nearest := Vector2(clampf(corrected.x, wall.position.x, wall.end.x), clampf(corrected.y, wall.position.y, wall.end.y))
			var away := corrected - nearest
			var distance := away.length()
			if distance >= radius:
				continue
			if distance > 1e-6:
				corrected = nearest + away / distance * radius
			else:
				# Centre is inside the wall: leave through the closest face.
				var to_left := corrected.x - wall.position.x
				var to_right := wall.end.x - corrected.x
				var to_top := corrected.y - wall.position.y
				var to_bottom := wall.end.y - corrected.y
				var smallest := minf(minf(to_left, to_right), minf(to_top, to_bottom))
				if smallest == to_left:
					corrected.x = wall.position.x - radius
				elif smallest == to_right:
					corrected.x = wall.end.x + radius
				elif smallest == to_top:
					corrected.y = wall.position.y - radius
				else:
					corrected.y = wall.end.y + radius
	return corrected
