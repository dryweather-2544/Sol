class_name LodPlanner
extends RefCounted
## Decides which chunks should exist for a viewer position: a chunk is split into four while
## the viewer is closer than split_ratio chunk-edges to it. Pure logic, no nodes.

var planet: PlanetBody
var max_level := 18 # set from the planet's size in _init
var split_ratio := 2.0
var _center_cache := {}


func _init(planet_body: PlanetBody) -> void:
	planet = planet_body
	max_level = planet_body.finest_lod_level()


## Approximate edge length in metres of a chunk at this level.
func chunk_edge_metres(level: int) -> float:
	return (PI * 0.5 * planet.radius) / float(1 << level)


func chunk_center(key: int) -> Vector3:
	if _center_cache.has(key):
		return _center_cache[key]
	var level := ChunkKey.level_of(key)
	var span := 2.0 / float(1 << level)
	var face_u := -1.0 + (ChunkKey.column_of(key) + 0.5) * span
	var face_v := -1.0 + (ChunkKey.row_of(key) + 0.5) * span
	var direction := CubeSphere.direction_xyz(ChunkKey.face_of(key), face_u, face_v)
	var center := Vector3(direction[0], direction[1], direction[2]) * planet.surface_radius_xyz(direction[0], direction[1], direction[2])
	if _center_cache.size() > 100000:
		_center_cache.clear()
	_center_cache[key] = center
	return center


## Returns the leaf chunk keys (a Dictionary used as a set) covering the whole planet.
func select_leaves(viewer: WorldPos) -> Dictionary:
	var viewer_point := Vector3(viewer.x, viewer.y, viewer.z)
	var leaves := {}
	var pending: Array[int] = []
	for face in 6:
		pending.append(ChunkKey.make(face, 0, 0, 0))
	while not pending.is_empty():
		var key: int = pending.pop_back()
		var level := ChunkKey.level_of(key)
		if level < max_level and viewer_point.distance_to(chunk_center(key)) < chunk_edge_metres(level) * split_ratio:
			for child_column in 2:
				for child_row in 2:
					pending.append(ChunkKey.child_of(key, child_column, child_row))
		else:
			leaves[key] = true
	return leaves
