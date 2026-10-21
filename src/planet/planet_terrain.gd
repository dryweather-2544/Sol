class_name PlanetTerrain
extends Node3D
## The visible planet: keeps the set of chunk meshes matching the viewer position. Chunk meshes are
## built on worker threads. Collision is not meshes: ship and player query the same HeightFunction
## directly (see docs/decisions/0002-height-query-collision.md).
##
## N14 streaming model (docs/N14_TERRAIN_STREAMING.md):
## - The planner picks the desired leaves around the viewer and a short predicted corridor ahead.
## - Every built chunk is "available" (an uploaded mesh). Each pass picks, per desired leaf, the
##   best available cover and shows exactly those chunks: the leaf itself at full grid, else finer
##   chunks that fully cover it, else the leaf's quick preview mesh, else the nearest available
##   ancestor as a filler (sunk slightly so finer neighbours win the depth test). Everything else
##   is hidden, not freed: hidden chunks are a bounded LRU cache that is reused on return.
## - Levels 0-2 are a pinned, cheap whole-planet backstop, so there is never a hole, and they are
##   built once (never rebuilt: hidden when unused).
## - A leaf that is badly covered first gets a preview mesh (~1/10 of the samples), then its full
##   grid. Current-view work is ordered ahead of speculative work along the predicted path.

## Shared with worker threads. Lives on its own (not on the node) so a task that finishes after the
## terrain was freed - for example when the ship leaves this world - touches nothing that is gone.
class BuildState extends RefCounted:
	var mutex := Mutex.new()
	var results: Array[Dictionary] = []
	var cancelled := false
	## Reused per-thread height functions (HeightFunction caches noise objects, so one instance
	## must never run on two threads at once; a worker takes one, builds, and returns it).
	var height_pool: Array[HeightFunction] = []


const PLAN_INTERVAL_SECONDS := 0.2
## Uploaded chunks are swapped in by the visibility pass at most this often (it walks every chunk).
const VISIBILITY_INTERVAL_SECONDS := 0.1
const CHUNKS_ADDED_PER_FRAME := 12
## Main-thread time allowed for uploading finished meshes in one frame.
const UPLOAD_BUDGET_USEC := 4000
## Hierarchical backstop: 6 + 24 + 96 small-grid chunks that together always cover the planet.
const FALLBACK_LEVELS := [0, 1, 2]
## A desired leaf whose best cover is this many levels coarser (or a hole) gets a preview first.
const PREVIEW_DEFICIT_LEVELS := 2
## Hidden (cached) chunks. A full chunk is about 76 KB of mesh, so 48 MiB holds ~640 of them.
const READY_CACHE_BUDGET_BYTES := 48 * 1024 * 1024
const READY_CACHE_MAX_ENTRIES := 768
## Predicted corridor: how far ahead the planner refines. The lookahead time grows with the
## measured request-to-screen latency, within these bounds, and is capped in metres.
const PRELOAD_MIN_SECONDS := 3.0
const PRELOAD_MAX_SECONDS := 8.0
const PRELOAD_MAX_METRES := 60000.0
const PRELOAD_MIN_METRES := 2000.0
const PRELOAD_CORRIDOR_POINTS := 3
## Speculative (ahead-of-ship) work is ranked as if it were this much farther away than it is.
const AHEAD_DISTANCE_WEIGHT := 1.35
## Kept for tools/tests that read it; the live limit is max_builds_in_flight (scaled to the CPU).
const MAX_BUILDS_IN_FLIGHT := 8
## Tier order of the build queue (lower first).
const TIER_BACKSTOP := 0
const TIER_PREVIEW := 1
const TIER_FULL := 2
const TIER_REFINE_COVERED := 3

var planet: PlanetBody
var planner: LodPlanner
## Same meaning as Ship.render_origin: where Vector3 zero is in the planet frame (kept in doubles).
var render_origin := WorldPos.new(&"planet")
var viewer := WorldPos.new(&"planet")
## Planet-frame velocity of the viewer, used to plan high-detail chunks ahead of the ship.
var viewer_velocity := Vector3.ZERO
## Worker tasks in flight. Defaults to the core count minus two (rendering and the main thread).
var max_builds_in_flight := MAX_BUILDS_IN_FLIGHT

var _material := StandardMaterial3D.new()
var _detail_material: ShaderMaterial ## null = plain vertex-colour material (switch off, or an asset missing)
var _chunks := {}             # key -> record: every uploaded chunk, visible or hidden
var _available_prefixes := {} # key -> count of available descendants (cheap coverage queries)
var _displayed := {}          # key -> record: the visible subset of _chunks
var _displayed_prefixes := {} # key -> count of visible descendants
var _desired := {}
var _fallback := {}           # pinned backstop keys (levels in FALLBACK_LEVELS)
var _pending := {}            # key -> grid being built
var _build_queue: Array = []  # [key, grid] still to build, in priority order
var _first_wanted := {}       # key -> usec the key was first queued (for the latency estimate)
var _build_state := BuildState.new()
var _task_ids: Array[int] = []
var _seconds_since_plan := PLAN_INTERVAL_SECONDS
var _visibility_dirty := false
var _seconds_since_visibility := 0.0
var _tick := 0
var _hidden_bytes := 0
var _hidden_count := 0
var _latency_ema_seconds := 0.5
var _lookahead_seconds := PRELOAD_MIN_SECONDS
## Debug/measurement counters, cheap and read-only for tests and probes.
var _stats := {
	"desired_by_level": {},
	"build_times_by_level": {},
	"completed": 0,
	"preview_builds": 0,
	"full_builds": 0,
	"shown": 0,
	"discarded": 0,
	"peak_queue": 0,
	"plan_count": 0,
	"cache_stored": 0,
	"cache_hits": 0,
	"cache_evicted": 0,
	"cache_peak_bytes": 0,
	"fillers": 0,
	"upload_usec_max": 0,
	"visibility_usec_max": 0,
	"plan_usec_max": 0,
	"plan_usec_sum": 0,
	"visibility_usec_sum": 0,
	"visibility_passes": 0,
}


func _init(planet_body: PlanetBody = null) -> void:
	name = "PlanetTerrain"
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps loading chunks behind the title screen / pause menu
	planet = planet_body
	planner = LodPlanner.new(planet_body)
	max_builds_in_flight = clampi(OS.get_processor_count() - 2, 2, 10)
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
	_seconds_since_visibility += delta
	if _seconds_since_plan >= PLAN_INTERVAL_SECONDS:
		_seconds_since_plan = 0.0
		_replan() # schedules a visibility pass for the next frame
		_collect_finished_builds()
		return
	_collect_finished_builds()
	if _visibility_dirty and _seconds_since_visibility >= VISIBILITY_INTERVAL_SECONDS:
		_update_visibility()


func apply_origin_shift(shift: Vector3) -> void:
	render_origin = render_origin.offset_by(shift)
	for chunk_record in _chunks.values():
		_place(chunk_record)


func displayed_chunk_count() -> int:
	return _displayed.size()


## True once every desired chunk is on screen at its full grid (tests and the loading gate).
func is_settled() -> bool:
	if _desired.is_empty():
		return false # nothing planned yet
	for key in _desired:
		var record: Dictionary = _displayed.get(key, {})
		if record.is_empty() or int(record["grid"]) < ChunkMesher.FINE_GRID:
			return false
	return true


# --- planning -------------------------------------------------------------------------------

func _replan() -> void:
	var started := Time.get_ticks_usec()
	_tick += 1
	var corridor := _preload_points()
	_desired = planner.select_leaves(viewer, corridor)
	_stats["plan_count"] = int(_stats["plan_count"]) + 1
	_count_desired_by_level()
	if _fallback.is_empty():
		_fallback = _fallback_ancestors(_desired)
	var viewer_point := Vector3(viewer.x, viewer.y, viewer.z)
	var corridor_points: Array[Vector3] = []
	for point in corridor:
		corridor_points.append(Vector3(point.x, point.y, point.z))
	# Candidates as Vector4i(tier, distance in metres, key high bits, key low bits) so the native
	# sort orders them (tier first, then distance) without a script comparator.
	var candidates: Array[Vector4i] = []
	var grids := {} # key -> grid to build
	for key in _fallback:
		if not _chunks.has(key) and not _pending.has(key):
			var tier := TIER_BACKSTOP if ChunkKey.level_of(key) == 0 else TIER_PREVIEW
			candidates.append(_candidate(tier, viewer_point.distance_to(planner.chunk_center(key)), key))
			grids[key] = ChunkMesher.grid_for_level(ChunkKey.level_of(key))
	for key in _desired:
		if _pending.has(key):
			continue
		var record: Dictionary = _chunks.get(key, {})
		var have_grid: int = 0 if record.is_empty() else int(record["grid"])
		if have_grid >= ChunkMesher.FINE_GRID:
			continue
		var center := planner.chunk_center(key)
		var score := viewer_point.distance_to(center)
		for point in corridor_points:
			score = minf(score, point.distance_to(center) * AHEAD_DISTANCE_WEIGHT)
		var tier := TIER_FULL
		var grid := ChunkMesher.FINE_GRID
		if have_grid == 0:
			if _available_prefixes.has(key) and _available_descendants_cover(key):
				tier = TIER_REFINE_COVERED
			elif _cover_deficit(key) >= PREVIEW_DEFICIT_LEVELS:
				tier = TIER_PREVIEW
				grid = ChunkMesher.PREVIEW_GRID
		candidates.append(_candidate(tier, score, key))
		grids[key] = grid
	candidates.sort()
	var now := Time.get_ticks_usec()
	_build_queue.clear()
	for candidate in candidates:
		var key: int = (candidate.z << 32) | (candidate.w & 0xFFFFFFFF)
		_build_queue.append([key, grids[key]])
		if not _first_wanted.has(key):
			_first_wanted[key] = now
	if _first_wanted.size() > 4096:
		_first_wanted.clear()
	_stats["peak_queue"] = maxi(int(_stats["peak_queue"]), _build_queue.size())
	_start_queued_builds()
	# The visibility pass runs on the next frame (from _process), not in this one, so the two
	# main-thread costs never add up into one long frame.
	_visibility_dirty = true
	_seconds_since_visibility = VISIBILITY_INTERVAL_SECONDS
	var spent := Time.get_ticks_usec() - started
	_stats["plan_usec_max"] = maxi(int(_stats["plan_usec_max"]), spent)
	_stats["plan_usec_sum"] = int(_stats["plan_usec_sum"]) + spent


static func _candidate(tier: int, score: float, key: int) -> Vector4i:
	return Vector4i(tier, mini(int(score), 0x7FFFFFFF), key >> 32, key & 0xFFFFFFFF)


## Levels more coarse than the leaf that its best current cover is (99 = nothing covers it).
func _cover_deficit(key: int) -> int:
	var ancestor := key
	while ChunkKey.level_of(ancestor) > 0:
		ancestor = ChunkKey.parent_of(ancestor)
		if _chunks.has(ancestor):
			return ChunkKey.level_of(key) - ChunkKey.level_of(ancestor)
	return 99


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


## The predicted corridor ahead of the viewer: PRELOAD_CORRIDOR_POINTS points spaced along the
## velocity up to the lookahead distance. Capped in metres so an orbital speed cannot flood the
## planner. Empty when the viewer is (nearly) still.
func _preload_points() -> Array[WorldPos]:
	var points: Array[WorldPos] = []
	var speed := viewer_velocity.length()
	if speed < 1.0:
		return points
	_lookahead_seconds = clampf(1.5 + 2.0 * _latency_ema_seconds, PRELOAD_MIN_SECONDS, PRELOAD_MAX_SECONDS)
	var distance := minf(speed * _lookahead_seconds, PRELOAD_MAX_METRES)
	if distance < PRELOAD_MIN_METRES:
		return points
	var direction := viewer_velocity / speed
	for index in PRELOAD_CORRIDOR_POINTS:
		var along := distance * float(index + 1) / float(PRELOAD_CORRIDOR_POINTS)
		points.append(WorldPos.new(viewer.frame_id, viewer.x + direction.x * along, viewer.y + direction.y * along, viewer.z + direction.z * along))
	return points


## Compatibility: the farthest corridor point (null when still).
func _preload_viewer() -> WorldPos:
	var points := _preload_points()
	return null if points.is_empty() else points[points.size() - 1]


# --- building -------------------------------------------------------------------------------

func _start_queued_builds() -> void:
	while _pending.size() < max_builds_in_flight and not _build_queue.is_empty():
		var entry: Array = _build_queue.pop_front()
		var key: int = entry[0]
		var grid: int = entry[1]
		if _pending.has(key):
			continue
		var record: Dictionary = _chunks.get(key, {})
		if not record.is_empty() and int(record["grid"]) >= grid:
			continue
		if not _desired.has(key) and not _fallback.has(key):
			continue
		_pending[key] = grid
		_task_ids.append(WorkerThreadPool.add_task(PlanetTerrain._build_in_background.bind(key, grid, planet, _build_state)))
	# Forget finished task ids so the list does not grow without bound.
	if _task_ids.size() > 256:
		var still_running: Array[int] = []
		for task_id in _task_ids:
			if not WorkerThreadPool.is_task_completed(task_id):
				still_running.append(task_id)
			else:
				WorkerThreadPool.wait_for_task_completion(task_id)
		_task_ids = still_running


static func _build_in_background(key: int, grid: int, planet_body: PlanetBody, state: BuildState) -> void:
	if state.cancelled:
		return
	var started := Time.get_ticks_usec()
	var height_function: HeightFunction = null
	if not planet_body.height_override.is_valid():
		state.mutex.lock()
		if not state.height_pool.is_empty():
			height_function = state.height_pool.pop_back()
		state.mutex.unlock()
		if height_function == null:
			height_function = HeightFunction.new(planet_body.profile_or_default())
	var mesh_data := ChunkMesher.build(key, planet_body, grid, height_function)
	mesh_data["key"] = key
	mesh_data["build_microseconds"] = Time.get_ticks_usec() - started
	state.mutex.lock()
	if height_function != null:
		state.height_pool.append(height_function)
	state.results.append(mesh_data)
	state.mutex.unlock()


func _exit_tree() -> void:
	# Tasks skip their work once cancelled; wait for them so nothing runs against torn-down engine state.
	_build_state.cancelled = true
	for task_id in _task_ids:
		WorkerThreadPool.wait_for_task_completion(task_id)
	_task_ids.clear()


func _collect_finished_builds() -> void:
	var started := Time.get_ticks_usec()
	var uploaded := 0
	while uploaded < CHUNKS_ADDED_PER_FRAME and Time.get_ticks_usec() - started < UPLOAD_BUDGET_USEC:
		_build_state.mutex.lock()
		var mesh_data: Dictionary = {} if _build_state.results.is_empty() else _build_state.results.pop_front()
		_build_state.mutex.unlock()
		if mesh_data.is_empty():
			break
		uploaded += 1
		var key: int = mesh_data["key"]
		var grid: int = int(mesh_data.get("grid", ChunkMesher.FINE_GRID))
		_pending.erase(key)
		_stats["completed"] = int(_stats["completed"]) + 1
		_stats["preview_builds" if grid == ChunkMesher.PREVIEW_GRID else "full_builds"] = int(_stats["preview_builds" if grid == ChunkMesher.PREVIEW_GRID else "full_builds"]) + 1
		var level := ChunkKey.level_of(key)
		var by_level: Dictionary = _stats["build_times_by_level"]
		var times: Array = by_level.get(level, [])
		times.append(float(mesh_data.get("build_microseconds", 0)) / 1000.0)
		if times.size() > 256:
			times.pop_front()
		by_level[level] = times
		if grid >= ChunkMesher.FINE_GRID and _first_wanted.has(key):
			var latency := float(Time.get_ticks_usec() - int(_first_wanted[key])) / 1000000.0
			_latency_ema_seconds = lerpf(_latency_ema_seconds, latency, 0.1)
		if grid >= ChunkMesher.FINE_GRID or ChunkKey.level_of(key) in FALLBACK_LEVELS:
			_first_wanted.erase(key)
		_add_chunk(key, mesh_data)
	if uploaded > 0:
		_stats["upload_usec_max"] = maxi(int(_stats["upload_usec_max"]), Time.get_ticks_usec() - started)
	_start_queued_builds()


## Uploads a finished mesh as an available chunk (hidden until the visibility pass picks it).
## A better-grid mesh for a key replaces the old one.
func _add_chunk(key: int, mesh_data: Dictionary) -> void:
	var grid: int = int(mesh_data.get("grid", ChunkMesher.FINE_GRID))
	var existing: Dictionary = _chunks.get(key, {})
	var was_visible := false
	var was_filler := false
	if not existing.is_empty():
		if int(existing["grid"]) >= grid:
			_stats["discarded"] = int(_stats["discarded"]) + 1
			return
		# A better mesh for a chunk on screen takes its place in the same frame (no gap until
		# the next visibility pass).
		was_visible = bool(existing["visible"])
		was_filler = bool(existing["filler"])
		_free_chunk(key)
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
	instance.visible = false
	add_child(instance)
	var level := ChunkKey.level_of(key)
	var record := {
		"key": key,
		"node": instance,
		"origin": WorldPos.new(planet.frame_id, origin_components[0], origin_components[1], origin_components[2]),
		"grid": grid,
		"bytes": _mesh_memory_bytes(mesh_data),
		"used": _tick,
		"visible": false,
		"filler": false,
		"preview": grid < ChunkMesher.FINE_GRID and not (level in FALLBACK_LEVELS),
		"sink": clampf(planner.chunk_edge_metres(level) / float(grid) * 0.5, 2.0, 3000.0),
	}
	_chunks[key] = record
	_hidden_bytes += int(record["bytes"])
	_hidden_count += 1
	_place(record)
	_adjust_prefixes(_available_prefixes, key, 1)
	if was_visible:
		record["filler"] = was_filler
		_set_visible(record, true)
		_place(record)
	_visibility_dirty = true


func _free_chunk(key: int) -> void:
	var record: Dictionary = _chunks.get(key, {})
	if record.is_empty():
		return
	if bool(record["visible"]):
		_set_visible(record, false)
	_hidden_bytes -= int(record["bytes"])
	_hidden_count -= 1
	(record["node"] as Node).queue_free()
	_chunks.erase(key)
	_adjust_prefixes(_available_prefixes, key, -1)


func _adjust_prefixes(prefixes: Dictionary, key: int, amount: int) -> void:
	var ancestor := key
	while ChunkKey.level_of(ancestor) > 0:
		ancestor = ChunkKey.parent_of(ancestor)
		var count: int = int(prefixes.get(ancestor, 0)) + amount
		if count <= 0:
			prefixes.erase(ancestor)
		else:
			prefixes[ancestor] = count


func _mesh_memory_bytes(mesh_data: Dictionary) -> int:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var colors: PackedColorArray = mesh_data.get("colors", PackedColorArray())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	return vertices.size() * 12 + normals.size() * 12 + colors.size() * 16 + indices.size() * 4 + 64


# --- visibility -----------------------------------------------------------------------------

## Picks the cover for every desired leaf and shows exactly those chunks (see the class comment).
func _update_visibility() -> void:
	var started := Time.get_ticks_usec()
	_visibility_dirty = false
	_seconds_since_visibility = 0.0
	var keep := {} # key -> true when shown as a sunk filler
	for key in _desired:
		_choose_cover(key, keep)
	var fillers := 0
	for key in _chunks.keys():
		var record: Dictionary = _chunks[key]
		var show := keep.has(key)
		if show != bool(record["visible"]):
			_set_visible(record, show)
		if show:
			record["used"] = _tick
			var filler: bool = keep[key]
			if filler:
				fillers += 1
			if filler != bool(record["filler"]):
				record["filler"] = filler
				_place(record)
	_stats["fillers"] = fillers
	_evict_hidden()
	var spent := Time.get_ticks_usec() - started
	_stats["visibility_usec_max"] = maxi(int(_stats["visibility_usec_max"]), spent)
	_stats["visibility_usec_sum"] = int(_stats["visibility_usec_sum"]) + spent
	_stats["visibility_passes"] = int(_stats["visibility_passes"]) + 1


func _choose_cover(key: int, keep: Dictionary) -> void:
	var record: Dictionary = _chunks.get(key, {})
	if not record.is_empty() and int(record["grid"]) >= ChunkMesher.FINE_GRID:
		keep[key] = false
		return
	var partial: Array[int] = []
	var full := _collect_available_cover(key, partial)
	for covered in partial:
		keep[covered] = false
	if full:
		return
	if not record.is_empty():
		# The leaf's own preview: sunk only if finer leftovers overlap it.
		keep[key] = not partial.is_empty()
		return
	var ancestor := key
	while ChunkKey.level_of(ancestor) > 0:
		ancestor = ChunkKey.parent_of(ancestor)
		if _chunks.has(ancestor):
			keep[ancestor] = true # a filler always overlaps finer chunks of its other children
			return


## Collects the coarsest available chunks strictly below key. Returns true when they cover key
## fully. A full-grid child is used as is; a preview child is used unless full finer chunks
## completely cover it.
func _collect_available_cover(key: int, out: Array[int]) -> bool:
	if ChunkKey.level_of(key) >= planner.max_level or not _available_prefixes.has(key):
		return false
	var full := true
	for child_column in 2:
		for child_row in 2:
			var child := ChunkKey.child_of(key, child_column, child_row)
			var record: Dictionary = _chunks.get(child, {})
			if not record.is_empty() and int(record["grid"]) >= ChunkMesher.FINE_GRID:
				out.append(child)
				continue
			var below: Array[int] = []
			var below_full := _collect_available_cover(child, below)
			if below_full:
				out.append_array(below)
			elif not record.is_empty():
				out.append(child) # the preview child covers its whole area; finer scraps stay hidden
			else:
				out.append_array(below)
				full = false
	return full


func _available_descendants_cover(key: int) -> bool:
	var scratch: Array[int] = []
	return _collect_available_cover(key, scratch)


func _set_visible(record: Dictionary, show: bool) -> void:
	var key: int = record["key"]
	record["visible"] = show
	(record["node"] as MeshInstance3D).visible = show
	if show:
		if bool(record.get("was_shown", false)):
			_stats["cache_hits"] = int(_stats["cache_hits"]) + 1
		record["was_shown"] = true
		_displayed[key] = record
		_adjust_prefixes(_displayed_prefixes, key, 1)
		_hidden_bytes -= int(record["bytes"])
		_hidden_count -= 1
	else:
		_displayed.erase(key)
		_adjust_prefixes(_displayed_prefixes, key, -1)
		_hidden_bytes += int(record["bytes"])
		_hidden_count += 1
		_stats["cache_stored"] = int(_stats["cache_stored"]) + 1
	_stats["cache_peak_bytes"] = maxi(int(_stats["cache_peak_bytes"]), _hidden_bytes)


## Bounded LRU over hidden chunks. The pinned backstop is never evicted, nor anything wanted now.
func _evict_hidden() -> void:
	if _hidden_bytes <= READY_CACHE_BUDGET_BYTES and _hidden_count <= READY_CACHE_MAX_ENTRIES:
		return
	var hidden: Array = []
	for key in _chunks:
		var record: Dictionary = _chunks[key]
		if bool(record["visible"]) or _fallback.has(key) or _desired.has(key) or _pending.has(key):
			continue
		hidden.append([int(record["used"]), key])
	hidden.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for entry in hidden:
		if _hidden_bytes <= READY_CACHE_BUDGET_BYTES and _hidden_count <= READY_CACHE_MAX_ENTRIES:
			break
		_free_chunk(entry[1])
		_stats["cache_evicted"] = int(_stats["cache_evicted"]) + 1


func _place(chunk_record: Dictionary) -> void:
	var instance: MeshInstance3D = chunk_record["node"]
	var position := (chunk_record["origin"] as WorldPos).to_local_vector3(render_origin)
	if bool(chunk_record.get("filler", false)):
		# A filler overlaps finer chunks; sink it by about half its quad spacing (its own
		# approximation error) toward the planet centre so the finer surface wins the depth test.
		var centre := WorldPos.new(planet.frame_id, 0.0, 0.0, 0.0).to_local_vector3(render_origin)
		var outward := (position - centre).normalized()
		position -= outward * float(chunk_record.get("sink", 50.0))
	instance.position = position
	instance.reset_physics_interpolation()


# --- queries, stats and test hooks ----------------------------------------------------------

func _is_covered(key: int) -> bool:
	if _displayed.has(key):
		return true
	if not _displayed_prefixes.has(key):
		return false
	return _children_covered(key)


func _children_covered(key: int) -> bool:
	if ChunkKey.level_of(key) >= planner.max_level:
		return false
	for child_column in 2:
		for child_row in 2:
			if not _is_covered(ChunkKey.child_of(key, child_column, child_row)):
				return false
	return true


## True when every root face is covered by visible chunks.
func displayed_coverage_is_complete() -> bool:
	for face in 6:
		if not _is_covered(ChunkKey.make(face, 0, 0, 0)):
			return false
	return true


## True when the point of every desired leaf has some visible cover (itself, finer, or a filler).
func desired_has_no_holes() -> bool:
	for key in _desired:
		if _displayed.has(key) or _is_covered(key):
			continue
		var ancestor: int = key
		var found := false
		while ChunkKey.level_of(ancestor) > 0:
			ancestor = ChunkKey.parent_of(ancestor)
			if _displayed.has(ancestor):
				found = true
				break
		if not found:
			return false
	return true


func ready_cache_bytes() -> int:
	return _hidden_bytes


func ready_cache_entries() -> int:
	return _hidden_count


func lookahead_seconds() -> float:
	return _lookahead_seconds


## Test hook: uploads a finished mesh as an available (hidden) chunk without a worker build.
func cache_mesh_for_test(key: int, mesh_data: Dictionary) -> void:
	_add_chunk(key, mesh_data)
	_evict_hidden()


## Test hook kept from the first N14 pass: upload and re-run the visibility pass.
func _show_chunk(key: int, mesh_data: Dictionary) -> void:
	_add_chunk(key, mesh_data)
	_update_visibility()


## Test hook kept from the first N14 pass: re-run the visibility pass.
func _remove_obsolete_chunks() -> void:
	_update_visibility()


func _count_desired_by_level() -> void:
	var counts := {}
	for key in _desired:
		var level := ChunkKey.level_of(key)
		counts[level] = int(counts.get(level, 0)) + 1
	_stats["desired_by_level"] = counts


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
	copy["available_count"] = _chunks.size()
	copy["pending_count"] = _pending.size()
	copy["queued_count"] = _build_queue.size()
	copy["cache_entries"] = _hidden_count
	copy["cache_bytes"] = _hidden_bytes
	copy["latency_ema_s"] = _latency_ema_seconds
	copy["lookahead_s"] = _lookahead_seconds
	copy["max_builds_in_flight"] = max_builds_in_flight
	return copy
