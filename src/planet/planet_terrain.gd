class_name PlanetTerrain
extends Node3D
## The visible planet: keeps the set of chunk meshes matching the viewer position. Chunk meshes are
## built on worker threads and swapped in without leaving holes (a coarse chunk stays until its
## replacements are all on screen). Collision is not meshes: ship and player query the same
## HeightFunction directly (see docs/decisions/0002-height-query-collision.md).

## Shared with worker threads. Lives on its own (not on the node) so a task that finishes after the
## terrain was freed - for example when the ship leaves this world - touches nothing that is gone.
class BuildState extends RefCounted:
	var mutex := Mutex.new()
	var results: Array[Dictionary] = []
	var cancelled := false


const CHUNKS_ADDED_PER_FRAME := 8
const MAX_BUILDS_IN_FLIGHT := 8
const PLAN_INTERVAL_SECONDS := 0.2
## Hierarchical coarse coverage: six level-0 faces, 24 level-1 and 96 level-2 chunks. With the
## LOD-aware grid these coarse chunks are cheap (single-digit milliseconds), and each level is
## removed only once its children cover it. This gives the planet a continuously improving
## backing surface while the near-ground chunks are generated.
const FALLBACK_LEVELS := [0, 1, 2]
## Ready meshes are bounded. A 32x32 chunk is roughly 70 KB, so 32 MiB holds about 450 chunks.
const READY_CACHE_BUDGET_BYTES := 32 * 1024 * 1024
const READY_CACHE_MAX_ENTRIES := 512

var planet: PlanetBody
var planner: LodPlanner
## Same meaning as Ship.render_origin: where Vector3 zero is in the planet frame (kept in doubles).
var render_origin := WorldPos.new(&"planet")
var viewer := WorldPos.new(&"planet")
## Planet-frame velocity of the viewer, used to plan high-detail chunks ahead of the ship. The
## actual build is still worker-threaded; this only changes which chunks are requested.
var viewer_velocity := Vector3.ZERO
const PRELOAD_LOOKAHEAD_SECONDS := 5.0
const PRELOAD_MAX_METRES := 60000.0
const PRELOAD_MIN_METRES := 2000.0

var _material := StandardMaterial3D.new()
var _detail_material: ShaderMaterial ## null = plain vertex-colour material (switch off, or an asset missing)
var _displayed := {}          # key -> {node, origin: WorldPos}
var _displayed_prefixes := {} # key -> count of displayed descendants (so coverage checks are cheap)
var _desired := {}
var _fallback := {}           # coarse ancestors that must hold the planet until fine chunks arrive
var _pending := {}            # keys currently being built
var _build_queue: Array[int] = [] # closest-first keys still to build
var _build_state := BuildState.new()
var _task_ids: Array[int] = []
var _seconds_since_plan := PLAN_INTERVAL_SECONDS
## Speculative completed meshes, evicted by a bounded LRU-ish policy. This stops a chunk built
## just before the viewer moved from being thrown away.
var _ready_cache := {}       # key -> {data, bytes, used}
var _ready_cache_bytes := 0
var _cache_tick := 0
## Debug/measurement counters. They are intentionally cheap and read-only for tests/probes.
var _stats := {
	"desired_by_level": {},
	"displayed_by_level": {},
	"build_times_by_level": {},
	"completed": 0,
	"shown": 0,
	"discarded": 0,
	"peak_queue": 0,
	"plan_count": 0,
	"cache_stored": 0,
	"cache_hits": 0,
	"cache_evicted": 0,
	"cache_peak_bytes": 0,
}


func _init(planet_body: PlanetBody = null) -> void:
	name = "PlanetTerrain"
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps loading chunks behind the title screen / pause menu
	planet = planet_body
	planner = LodPlanner.new(planet_body)
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if planet_body != null:
		_detail_material = TerrainDetail.build_material(planet_body.atmosphere_height, planet_body.look)


func _ready() -> void:
	add_to_group("origin_shift")


## Rodina-style ground-to-orbit colour lean, from the viewer's height above the ground (no-op for the Sol style).
func set_viewer_altitude(altitude_metres: float) -> void:
	if _detail_material != null and planet != null and planet.look != null:
		_detail_material.set_shader_parameter("orbit_mix", planet.look.orbit_mix_at(altitude_metres))


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
	if _desired.is_empty():
		return false # nothing planned yet
	for key in _desired:
		if not _displayed.has(key):
			return false
	return true


func _replan() -> void:
	var preload_viewer := _preload_viewer()
	_desired = planner.select_leaves(viewer, preload_viewer)
	_stats["plan_count"] = int(_stats["plan_count"]) + 1
	_count_desired_by_level()
	_fallback = _fallback_ancestors(_desired)
	_cache_tick += 1
	_promote_cached_meshes()
	var viewer_point := Vector3(viewer.x, viewer.y, viewer.z)
	var preload_point := viewer_point
	if preload_viewer != null:
		preload_point = Vector3(preload_viewer.x, preload_viewer.y, preload_viewer.z)
	var current_wanted: Array[int] = []
	var ahead_wanted: Array[int] = []
	var other_wanted: Array[int] = []
	var focus_distance := _current_focus_distance()
	var ahead_distance := maxf(PRELOAD_MIN_METRES, preload_point.distance_to(viewer_point) + planner.chunk_edge_metres(planner.max_level))
	for key in _desired:
		if _displayed.has(key) or _pending.has(key) or _ready_cache.has(key):
			continue
		var center := planner.chunk_center(key)
		if center.distance_to(viewer_point) <= focus_distance:
			current_wanted.append(key)
		elif preload_viewer != null and center.distance_to(preload_point) <= ahead_distance:
			ahead_wanted.append(key)
		else:
			other_wanted.append(key)
	current_wanted.sort_custom(func(a: int, b: int) -> bool:
		return viewer_point.distance_squared_to(planner.chunk_center(a)) < viewer_point.distance_squared_to(planner.chunk_center(b)))
	ahead_wanted.sort_custom(func(a: int, b: int) -> bool:
		return preload_point.distance_squared_to(planner.chunk_center(a)) < preload_point.distance_squared_to(planner.chunk_center(b)))
	other_wanted.sort_custom(func(a: int, b: int) -> bool:
		return viewer_point.distance_squared_to(planner.chunk_center(a)) < viewer_point.distance_squared_to(planner.chunk_center(b)))
	var fallback_wanted: Array[int] = []
	for key in _fallback:
		if not _displayed.has(key) and not _pending.has(key) and not _ready_cache.has(key):
			fallback_wanted.append(key)
	fallback_wanted.sort_custom(func(a: int, b: int) -> bool:
		var level_a := ChunkKey.level_of(a)
		var level_b := ChunkKey.level_of(b)
		if level_a != level_b:
			return level_a < level_b
		return viewer_point.distance_squared_to(planner.chunk_center(a)) < viewer_point.distance_squared_to(planner.chunk_center(b)))
	var fine_wanted := _interleave_priority(current_wanted, ahead_wanted)
	_build_queue = fallback_wanted + fine_wanted + other_wanted
	_stats["peak_queue"] = maxi(int(_stats["peak_queue"]), _build_queue.size())
	_start_queued_builds()
	_remove_obsolete_chunks()


## Current-view work gets two slots for every speculative lookahead job, so preloading cannot
## starve the terrain immediately around the ship.
func _interleave_priority(current: Array[int], ahead: Array[int]) -> Array[int]:
	var result: Array[int] = []
	var current_index := 0
	var ahead_index := 0
	while current_index < current.size() or ahead_index < ahead.size():
		for _i in 2:
			if current_index < current.size():
				result.append(current[current_index])
				current_index += 1
		if ahead_index < ahead.size():
			result.append(ahead[ahead_index])
			ahead_index += 1
	return result


func _current_focus_distance() -> float:
	var altitude := maxf(0.0, planet.distance_from_center(viewer) - planet.radius)
	return clampf(altitude * 2.0 + 3000.0, 5000.0, 30000.0)


func _fallback_ancestors(leaves: Dictionary) -> Dictionary:
	var result := {}
	for key in leaves:
		var ancestor: int = key
		while ChunkKey.level_of(ancestor) >= 0:
			if ChunkKey.level_of(ancestor) in FALLBACK_LEVELS:
				result[ancestor] = true
			if ChunkKey.level_of(ancestor) == 0:
				break
			ancestor = ChunkKey.parent_of(ancestor)
	return result


func _covers_any_desired(key: int) -> bool:
	for desired_key in _desired:
		if desired_key == key or ChunkKey.is_ancestor(key, desired_key):
			return true
	return false


func _mesh_memory_bytes(mesh_data: Dictionary) -> int:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var colors: PackedColorArray = mesh_data.get("colors", PackedColorArray())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	return vertices.size() * 12 + normals.size() * 12 + colors.size() * 16 + indices.size() * 4 + 64


func _cache_mesh(key: int, mesh_data: Dictionary) -> void:
	if _ready_cache.has(key):
		return
	var bytes := _mesh_memory_bytes(mesh_data)
	if bytes > READY_CACHE_BUDGET_BYTES:
		_stats["discarded"] = int(_stats["discarded"]) + 1
		return
	if _ready_cache_bytes + bytes > READY_CACHE_BUDGET_BYTES or _ready_cache.size() >= READY_CACHE_MAX_ENTRIES:
		_evict_ready_cache(true)
	if _ready_cache_bytes + bytes > READY_CACHE_BUDGET_BYTES or _ready_cache.size() >= READY_CACHE_MAX_ENTRIES:
		_stats["discarded"] = int(_stats["discarded"]) + 1
		return
	_ready_cache[key] = {"data": mesh_data, "bytes": bytes, "used": _cache_tick}
	_ready_cache_bytes += bytes
	_stats["cache_stored"] = int(_stats["cache_stored"]) + 1
	_evict_ready_cache()
	_stats["cache_peak_bytes"] = maxi(int(_stats["cache_peak_bytes"]), _ready_cache_bytes)


func _evict_ready_cache(make_room := false) -> void:
	while _ready_cache_bytes > READY_CACHE_BUDGET_BYTES or _ready_cache.size() > READY_CACHE_MAX_ENTRIES or (make_room and _ready_cache.size() >= READY_CACHE_MAX_ENTRIES):
		var oldest_key := -1
		var oldest_used := 1 << 60
		for key in _ready_cache:
			if _desired.has(key) or _fallback.has(key) or _pending.has(key) or _displayed.has(key):
				continue
			var used: int = int(_ready_cache[key]["used"])
			if used < oldest_used:
				oldest_used = used
				oldest_key = key
		if oldest_key < 0:
			return
		_ready_cache_bytes -= int(_ready_cache[oldest_key]["bytes"])
		_ready_cache.erase(oldest_key)
		_stats["cache_evicted"] = int(_stats["cache_evicted"]) + 1


func _promote_cached_meshes() -> void:
	var promoted: Array[int] = []
	for key in _ready_cache:
		if (_desired.has(key) or _fallback.has(key)) and not _displayed.has(key):
			promoted.append(key)
	for key in promoted:
		var entry: Dictionary = _ready_cache[key]
		_ready_cache.erase(key)
		_ready_cache_bytes -= int(entry["bytes"])
		_show_chunk(key, entry["data"])
		_stats["cache_hits"] = int(_stats["cache_hits"]) + 1
		_stats["shown"] = int(_stats["shown"]) + 1


func ready_cache_bytes() -> int:
	return _ready_cache_bytes


func ready_cache_entries() -> int:
	return _ready_cache.size()


## True when every root face is covered by a displayed chunk or fully displayed descendants.
func displayed_coverage_is_complete() -> bool:
	for face in 6:
		if not _is_covered(ChunkKey.make(face, 0, 0, 0)):
			return false
	return true


## Test/tool hook: keep completed speculative data without needing a scene-tree upload.
func cache_mesh_for_test(key: int, mesh_data: Dictionary) -> void:
	_cache_mesh(key, mesh_data)


func _count_desired_by_level() -> void:
	var counts := {}
	for key in _desired:
		var level := ChunkKey.level_of(key)
		counts[level] = int(counts.get(level, 0)) + 1
	_stats["desired_by_level"] = counts
	var displayed_counts := {}
	for key in _displayed:
		var level := ChunkKey.level_of(key)
		displayed_counts[level] = int(displayed_counts.get(level, 0)) + 1
	_stats["displayed_by_level"] = displayed_counts


## A copy of the streaming counters, safe to read from tests and tools.
func stream_stats() -> Dictionary:
	var copy := _stats.duplicate(true)
	var displayed := {}
	for key in _displayed:
		var level := ChunkKey.level_of(key)
		displayed[level] = int(displayed.get(level, 0)) + 1
	copy["displayed_by_level"] = displayed
	copy["desired_count"] = _desired.size()
	copy["displayed_count"] = _displayed.size()
	copy["pending_count"] = _pending.size()
	copy["queued_count"] = _build_queue.size()
	return copy


## The predicted viewer point is capped so a high orbit speed cannot flood the planner with
## thousands of fine chunks; the point is still far enough ahead to cover a normal approach.
func _preload_viewer() -> WorldPos:
	var speed := viewer_velocity.length()
	if speed < 1.0:
		return null
	var distance := minf(speed * PRELOAD_LOOKAHEAD_SECONDS, PRELOAD_MAX_METRES)
	if distance < 1.0:
		return null
	var direction := viewer_velocity / speed
	return WorldPos.new(viewer.frame_id, viewer.x + direction.x * distance, viewer.y + direction.y * distance, viewer.z + direction.z * distance)


func _start_queued_builds() -> void:
	while _pending.size() < MAX_BUILDS_IN_FLIGHT and not _build_queue.is_empty():
		var key: int = _build_queue.pop_front()
		if _pending.has(key) or _displayed.has(key) or _ready_cache.has(key) or (not _desired.has(key) and not _fallback.has(key)):
			continue
		_pending[key] = true
		_task_ids.append(WorkerThreadPool.add_task(PlanetTerrain._build_in_background.bind(key, planet, _build_state)))


static func _build_in_background(key: int, planet_body: PlanetBody, state: BuildState) -> void:
	if state.cancelled:
		return
	var started := Time.get_ticks_usec()
	var mesh_data := ChunkMesher.build(key, planet_body)
	mesh_data["key"] = key
	mesh_data["level"] = ChunkKey.level_of(key)
	mesh_data["build_microseconds"] = Time.get_ticks_usec() - started
	state.mutex.lock()
	state.results.append(mesh_data)
	state.mutex.unlock()


func _exit_tree() -> void:
	# Tasks skip their work once cancelled; wait for them so nothing runs against torn-down engine state.
	_build_state.cancelled = true
	for task_id in _task_ids:
		WorkerThreadPool.wait_for_task_completion(task_id)
	_task_ids.clear()


func _collect_finished_builds() -> void:
	var finished: Array[Dictionary] = []
	_build_state.mutex.lock()
	for added in mini(CHUNKS_ADDED_PER_FRAME, _build_state.results.size()):
		finished.append(_build_state.results.pop_front())
	_build_state.mutex.unlock()
	for mesh_data in finished:
		var key: int = mesh_data["key"]
		_pending.erase(key)
		_stats["completed"] = int(_stats["completed"]) + 1
		var level: int = int(mesh_data.get("level", ChunkKey.level_of(key)))
		var times: Array = _stats["build_times_by_level"].get(level, [])
		times.append(float(mesh_data.get("build_microseconds", 0)) / 1000.0)
		if times.size() > 256:
			times.pop_front()
		_stats["build_times_by_level"][level] = times
		if (_desired.has(key) or _fallback.has(key)) and not _displayed.has(key):
			_show_chunk(key, mesh_data)
			_stats["shown"] = int(_stats["shown"]) + 1
		elif not _displayed.has(key):
			# The viewer moved while this chunk was building. Keep it for a possible return
			# instead of discarding finished work immediately.
			_cache_mesh(key, mesh_data)
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
	if _detail_material != null:
		instance.material_override = _detail_material
		instance.set_instance_shader_parameter("tile_offset", TerrainDetail.tile_offset(mesh_data["origin"], planet.look.detail_tile_period if planet.look != null else TerrainDetail.TILE_PERIOD))
	else:
		instance.material_override = _material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	var is_fallback := _fallback.has(key) and not _desired.has(key)
	var record := {
		"node": instance,
		"origin": WorldPos.new(planet.frame_id, origin_components[0], origin_components[1], origin_components[2]),
		"fallback": is_fallback,
	}
	_displayed[key] = record
	_place(record)
	var ancestor := key
	while ChunkKey.level_of(ancestor) > 0:
		ancestor = ChunkKey.parent_of(ancestor)
		_displayed_prefixes[ancestor] = _displayed_prefixes.get(ancestor, 0) + 1


func _place(chunk_record: Dictionary) -> void:
	var instance: MeshInstance3D = chunk_record["node"]
	var position := (chunk_record["origin"] as WorldPos).to_local_vector3(render_origin)
	# A fallback face can overlap its finer children. Sink it a little below the surface so the
	# finer mesh wins the depth test instead of z-fighting; gaps still show the fallback, not space.
	if bool(chunk_record.get("fallback", false)) and position.length_squared() > 1.0:
		position -= position.normalized() * 50.0
	instance.position = position
	instance.reset_physics_interpolation()


## A chunk that is no longer wanted is removed once the area it covers is fully displayed by
## other chunks, so the planet never shows holes while the replacements are still building.
func _remove_obsolete_chunks() -> void:
	var removable: Array[int] = []
	for key in _displayed:
		if _desired.has(key):
			continue
		# A desired ancestor is a request for coverage, not proof that coverage exists. Keep this
		# chunk until another displayed chunk or fully displayed descendants replace its area.
		if _has_displayed_ancestor(key) or _children_covered(key):
			removable.append(key)
	# Deepest first, and re-check right before freeing. Otherwise a parent and all of its
	# children can be marked removable in the same pass and then both disappear, leaving a hole.
	removable.sort_custom(func(a: int, b: int) -> bool: return ChunkKey.level_of(a) > ChunkKey.level_of(b))
	for key in removable:
		if not _displayed.has(key) or _desired.has(key):
			continue
		if not _has_displayed_ancestor(key) and not _children_covered(key):
			continue
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
