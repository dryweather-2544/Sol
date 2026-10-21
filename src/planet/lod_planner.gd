class_name LodPlanner
extends RefCounted
## Decides which chunks should exist for a viewer position: a chunk is split into four while the viewer is closer than
## split_ratio chunk-edges to its centre. Pure logic, no nodes, and it never queries the terrain height itself (that cost
## a 0.1 ms exact lookup per new node and made planning spike): chunk centres use the height of the nearest chunk that has
## already been built (note_height), else the planet radius.
##
## A chunk that was split by the previous plan stays split until the viewer is MERGE_HYSTERESIS times farther than
## the split distance, so a viewer hovering at a boundary does not flip chunks back and forth every plan.

## Chunk edges between the viewer and a chunk's centre below which the chunk splits. One chunk has 32 quads, so at 70 degrees
## of vertical view over 1080 px this is about 8 px per quad at the near end of a chunk's range and 4 px at the far end.
const SPLIT_RATIO := 3.0
const MERGE_HYSTERESIS := 1.15
const FAST_FLIGHT_EDGE_SECONDS := 0.25
const FAST_FLIGHT_MIN_LEVEL := 5

var planet: PlanetBody
var max_level := 18 # set from the planet's size in _init
var split_ratio := SPLIT_RATIO
## Internal (split) nodes of the most recent plan.
var last_internal := {}
## Viewer speed (m/s) for the next plan. Fast flight cannot use the finest chunks (they would be gone before they are
## built), so the finest level allowed is the one whose edge is still at least speed * FAST_FLIGHT_EDGE_SECONDS. Once
## the ship slows, the cap lifts and the planner refines (the geomorph blends it in).
var speed := 0.0
var _direction_cache := {} # key -> unit direction of the chunk centre
var _height_hints := {}    # key -> surface height above the radius at the chunk centre (from built chunks)
var _was_split := {}       # keys split by the previous plan


func _init(planet_body: PlanetBody) -> void:
	planet = planet_body
	max_level = planet_body.finest_lod_level()


## Approximate edge length in metres of a chunk at this level.
func chunk_edge_metres(level: int) -> float:
	return (PI * 0.5 * planet.radius) / float(1 << level)


## A built chunk reports the surface height at its centre; its descendants use it until they are built themselves.
func note_height(key: int, height: float) -> void:
	if _height_hints.size() > 200000:
		_height_hints.clear()
	_height_hints[key] = height


func chunk_center(key: int) -> Vector3:
	var direction: Vector3 = _direction_cache.get(key, Vector3.ZERO)
	if direction == Vector3.ZERO:
		var level := ChunkKey.level_of(key)
		var span := 2.0 / float(1 << level)
		var face_u := -1.0 + (ChunkKey.column_of(key) + 0.5) * span
		var face_v := -1.0 + (ChunkKey.row_of(key) + 0.5) * span
		var components := CubeSphere.direction_xyz(ChunkKey.face_of(key), face_u, face_v)
		direction = Vector3(components[0], components[1], components[2])
		if _direction_cache.size() > 100000:
			_direction_cache.clear()
		_direction_cache[key] = direction
	return direction * (planet.radius + _height_hint(key))


func _height_hint(key: int) -> float:
	var current := key
	while not _height_hints.has(current):
		if ChunkKey.level_of(current) == 0:
			return 0.0
		current = ChunkKey.parent_of(current)
	return float(_height_hints[current])


## The plan: {"leaves": Dictionary used as a set (the nodes to show), "internal": Dictionary (the split nodes above them)}.
## preload_points is the predicted path ahead of the ship: one WorldPos, or an Array of WorldPos sampled along a short
## corridor. The tree splits around the viewer or any preload point, so high-detail chunks are already being built before
## they enter the camera.
func plan(viewer: WorldPos, preload_points = null) -> Dictionary:
	var points: Array[Vector3] = [Vector3(viewer.x, viewer.y, viewer.z)]
	if preload_points is WorldPos:
		points.append(Vector3(preload_points.x, preload_points.y, preload_points.z))
	elif preload_points is Array:
		for point in preload_points:
			if point is WorldPos:
				points.append(Vector3(point.x, point.y, point.z))
	var level_limit := max_level
	while level_limit > FAST_FLIGHT_MIN_LEVEL and chunk_edge_metres(level_limit) < speed * FAST_FLIGHT_EDGE_SECONDS:
		level_limit -= 1
	var leaves := {}
	var internal := {}
	var pending: Array[int] = []
	for face in 6:
		pending.append(ChunkKey.make(face, 0, 0, 0))
	while not pending.is_empty():
		var key: int = pending.pop_back()
		var level := ChunkKey.level_of(key)
		var near := false
		if level < level_limit:
			var split_distance := chunk_edge_metres(level) * split_ratio
			if _was_split.has(key):
				split_distance *= MERGE_HYSTERESIS
			var split_squared := split_distance * split_distance
			var center := chunk_center(key)
			for point in points:
				if point.distance_squared_to(center) < split_squared:
					near = true
					break
		if near:
			internal[key] = true
			for child_column in 2:
				for child_row in 2:
					pending.append(ChunkKey.child_of(key, child_column, child_row))
		else:
			leaves[key] = true
	_was_split = internal
	last_internal = internal
	return {"leaves": leaves, "internal": internal}


## Returns the leaf chunk keys (a Dictionary used as a set) covering the whole planet.
func select_leaves(viewer: WorldPos, preload_points = null) -> Dictionary:
	return plan(viewer, preload_points)["leaves"]


## Build priority of a chunk: roughly how far its nearest part is from where the ship is, or will be (the path length to a
## corridor point plus the distance from that point, weighted). Lower is more urgent. A coarse ancestor is always at least
## as urgent as its descendants, so refinement goes top-down.
func urgency(key: int, viewer_point: Vector3, corridor_points: Array[Vector3], corridor_along: Array[float], ahead_weight: float) -> float:
	var center := chunk_center(key)
	var reach := chunk_edge_metres(ChunkKey.level_of(key)) * 0.75
	var score := maxf(0.0, viewer_point.distance_to(center) - reach)
	for index in corridor_points.size():
		score = minf(score, corridor_along[index] + maxf(0.0, corridor_points[index].distance_to(center) - reach) * ahead_weight)
	return score
