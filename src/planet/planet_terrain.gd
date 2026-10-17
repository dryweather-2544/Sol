class_name PlanetTerrain
extends Node3D
## The visible planet: keeps the set of chunk meshes matching the viewer position. Chunk meshes are
## built on worker threads and swapped in without leaving holes (a coarse chunk stays until its
## replacements are all on screen). Collision is not meshes: ship and player query the same
## HeightFunction directly (see docs/decisions/0002-height-query-collision.md).

const CHUNKS_ADDED_PER_FRAME := 4
const MAX_BUILDS_IN_FLIGHT := 6
const PLAN_INTERVAL_SECONDS := 0.2

var planet: PlanetBody
var planner: LodPlanner
## Same meaning as Ship.render_origin: where Vector3 zero is in the planet frame (kept in doubles).
var render_origin := WorldPos.new(&"planet")
var viewer := WorldPos.new(&"planet")

var _material := StandardMaterial3D.new()
var _displayed := {}          # key -> {node, origin: WorldPos}
var _displayed_prefixes := {} # key -> count of displayed descendants (so coverage checks are cheap)
var _desired := {}
var _pending := {}            # keys currently being built
var _build_queue: Array[int] = [] # closest-first keys still to build
var _ready_results: Array[Dictionary] = []
var _results_mutex := Mutex.new()
var _seconds_since_plan := PLAN_INTERVAL_SECONDS


func _init(planet_body: PlanetBody = null) -> void:
	name = "PlanetTerrain"
	planet = planet_body
	planner = LodPlanner.new(planet_body)
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _ready() -> void:
	add_to_group("origin_shift")


func _process(delta: float) -> void:
	_seconds_since_plan += delta
	if _seconds_since_plan >= PLAN_INTERVAL_SECONDS:
		_seconds_since_plan = 0.0
		_replan()
	_collect_finished_builds()


func apply_origin_shift(shift: Vector3) -> void:
	render_origin = render_origin.offset_by(shift)
	for chunk_record in _displayed.values():
		_place(chunk_record)


func displayed_chunk_count() -> int:
	return _displayed.size()


## True once every desired chunk is on screen (used by tests and a loading gate).
func is_settled() -> bool:
	for key in _desired:
		if not _displayed.has(key):
			return false
	return true


func _replan() -> void:
	_desired = planner.select_leaves(viewer)
	var viewer_point := Vector3(viewer.x, viewer.y, viewer.z)
	var wanted: Array[int] = []
	for key in _desired:
		if not _displayed.has(key) and not _pending.has(key):
			wanted.append(key)
	wanted.sort_custom(func(key_a: int, key_b: int) -> bool:
		return viewer_point.distance_squared_to(planner.chunk_center(key_a)) < viewer_point.distance_squared_to(planner.chunk_center(key_b)))
	_build_queue = wanted
	_start_queued_builds()
	_remove_obsolete_chunks()


func _start_queued_builds() -> void:
	while _pending.size() < MAX_BUILDS_IN_FLIGHT and not _build_queue.is_empty():
		var key: int = _build_queue.pop_front()
		if _pending.has(key) or _displayed.has(key) or not _desired.has(key):
			continue
		_pending[key] = true
		WorkerThreadPool.add_task(_build_in_background.bind(key))


func _build_in_background(key: int) -> void:
	var mesh_data := ChunkMesher.build(key, planet)
	mesh_data["key"] = key
	_results_mutex.lock()
	_ready_results.append(mesh_data)
	_results_mutex.unlock()


func _collect_finished_builds() -> void:
	var finished: Array[Dictionary] = []
	_results_mutex.lock()
	for added in mini(CHUNKS_ADDED_PER_FRAME, _ready_results.size()):
		finished.append(_ready_results.pop_front())
	_results_mutex.unlock()
	for mesh_data in finished:
		var key: int = mesh_data["key"]
		_pending.erase(key)
		if _desired.has(key) and not _displayed.has(key):
			_show_chunk(key, mesh_data)
	if not finished.is_empty():
		_remove_obsolete_chunks()
	_start_queued_builds()


func _show_chunk(key: int, mesh_data: Dictionary) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh_data["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = mesh_data["normals"]
	arrays[Mesh.ARRAY_COLOR] = mesh_data["colors"]
	arrays[Mesh.ARRAY_INDEX] = mesh_data["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var origin_components: PackedFloat64Array = mesh_data["origin"]
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	var record := {"node": instance, "origin": WorldPos.new(planet.frame_id, origin_components[0], origin_components[1], origin_components[2])}
	_displayed[key] = record
	_place(record)
	var ancestor := key
	while ChunkKey.level_of(ancestor) > 0:
		ancestor = ChunkKey.parent_of(ancestor)
		_displayed_prefixes[ancestor] = _displayed_prefixes.get(ancestor, 0) + 1


func _place(chunk_record: Dictionary) -> void:
	var instance: MeshInstance3D = chunk_record["node"]
	instance.position = (chunk_record["origin"] as WorldPos).to_local_vector3(render_origin)
	instance.reset_physics_interpolation()


## A chunk that is no longer wanted is removed once the area it covers is fully displayed by
## other chunks, so the planet never shows holes while the replacements are still building.
func _remove_obsolete_chunks() -> void:
	var removable: Array[int] = []
	for key in _displayed:
		if _desired.has(key):
			continue
		if _has_displayed_ancestor(key) or _children_covered(key):
			removable.append(key)
	for key in removable:
		var record: Dictionary = _displayed[key]
		(record["node"] as Node).queue_free()
		_displayed.erase(key)
		var ancestor := key
		while ChunkKey.level_of(ancestor) > 0:
			ancestor = ChunkKey.parent_of(ancestor)
			var remaining: int = _displayed_prefixes.get(ancestor, 1) - 1
			if remaining <= 0:
				_displayed_prefixes.erase(ancestor)
			else:
				_displayed_prefixes[ancestor] = remaining


func _has_displayed_ancestor(key: int) -> bool:
	var ancestor := key
	while ChunkKey.level_of(ancestor) > 0:
		ancestor = ChunkKey.parent_of(ancestor)
		if _displayed.has(ancestor):
			return true
	return false


func _children_covered(key: int) -> bool:
	if ChunkKey.level_of(key) >= planner.max_level:
		return false
	for child_column in 2:
		for child_row in 2:
			if not _is_covered(ChunkKey.child_of(key, child_column, child_row)):
				return false
	return true


func _is_covered(key: int) -> bool:
	if _displayed.has(key):
		return true
	if not _displayed_prefixes.has(key):
		return false
	return _children_covered(key)
