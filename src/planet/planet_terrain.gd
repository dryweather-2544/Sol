class_name PlanetTerrain
extends Node3D
## The visible planet: keeps the set of chunk meshes matching the viewer position. Chunk meshes are
## built on worker threads. Collision is not meshes: ship and player query the same HeightFunction
## directly (see docs/decisions/0002-height-query-collision.md).
##
## Streaming model (docs/N14_TERRAIN_STREAMING.md, reworked after the first GPU-height flights):
## - The planner picks a quadtree around the viewer and a short predicted corridor ahead: leaves are the chunks to show,
##   internal nodes are the split chunks above them. Every node of that tree is built, coarse and near first, so a
##   region refines one level at a time instead of jumping from a huge block to the finest grid.
## - Exactly one layer is ever shown. A node shows its four children only once all four can be shown (themselves or
##   through their own children); until then the node itself covers the area. Chunks never overlap, so there is no
##   depth fighting and no sunk "filler" layer. Levels 0-2 are a pinned, cheap whole-planet backstop that is built
##   first and never evicted, so there is never a hole.
## - A chunk that replaces its parent starts in the parent's shape and eases into its own (geomorph, the "morph"
##   instance uniform of the terrain shader), so refining does not pop.
## - Hidden chunks stay a bounded LRU cache and are reused on return.
## - Planning (the tree, the build order and the choice of what to show) runs on its own thread; the main thread only
##   starts builds, uploads finished meshes (already built into ArrayMeshes by the workers) and applies the small
##   difference in what is visible. Chunk nodes live under one root node, so a floating-origin shift moves one node, not
##   every chunk.

## Shared with worker threads. Lives on its own (not on the node) so a task that finishes after the
## terrain was freed - for example when the ship leaves this world - touches nothing that is gone.
class BuildState extends RefCounted:
	var mutex := Mutex.new()
	var results: Array[Dictionary] = []
	var cancelled := false
	## Reused per-thread height functions (HeightFunction caches noise objects, so one instance
	## must never run on two threads at once; a worker takes one, builds, and returns it).
	var height_pool: Array[HeightFunction] = []


## What one planning pass decided.
class PlanResult extends RefCounted:
	var leaves := {}   # key -> true: the chunks to show
	var internal := {} # key -> true: the split chunks above them
	var order: Array[int] = [] # keys still to build, most urgent first
	var tiles := {}    # key -> true: the chunks that should be visible, given what was built when the plan was made
	var compute_usec := 0


## Minimum time between planning passes (a pass starts as soon as the previous one has been applied after this).
const PLAN_INTERVAL_SECONDS := 0.1
## Uploads per frame and the main-thread time allowed for them.
const CHUNKS_ADDED_PER_FRAME := 16
const UPLOAD_BUDGET_USEC := 3000
## Hierarchical backstop: 6 + 24 + 96 small-grid chunks that together always cover the planet.
const FALLBACK_LEVELS := [0, 1, 2]
## Hidden (cached) chunks. A full chunk is about 90 KB of mesh.
const READY_CACHE_BUDGET_BYTES := 160 * 1024 * 1024
const READY_CACHE_MAX_ENTRIES := 2048
const EVICT_TARGET := 0.9
const EVICT_PER_PASS := 40
## Seconds a chunk takes to ease from its parent's shape to its own.
const MORPH_SECONDS := 0.7
## Chunk nodes are placed relative to an anchor; when the render origin has moved this far from it they are re-placed.
const REANCHOR_METRES := 30000.0
## Predicted corridor: how far ahead the planner refines. The lookahead time grows with the
## measured build backlog, within these bounds, and is capped in metres.
const PRELOAD_MIN_SECONDS := 3.0
const PRELOAD_MAX_SECONDS := 8.0
const PRELOAD_MAX_METRES := 60000.0
const PRELOAD_MIN_METRES := 2000.0
const PRELOAD_CORRIDOR_POINTS := 3
## Speculative (ahead-of-ship) work is ranked as if it were this much farther away than it is.
const AHEAD_DISTANCE_WEIGHT := 1.35
## Kept for tools/tests that read it; the live limit is max_builds_in_flight (scaled to the CPU).
const MAX_BUILDS_IN_FLIGHT := 8

var planet: PlanetBody
var planner: LodPlanner
## Same meaning as Ship.render_origin: where Vector3 zero is in the planet frame (kept in doubles).
var render_origin := WorldPos.new(&"planet")
var viewer := WorldPos.new(&"planet")
## Planet-frame velocity of the viewer, used to plan high-detail chunks ahead of the ship.
var viewer_velocity := Vector3.ZERO
## Worker tasks in flight. Defaults to the core count minus two (rendering and the main thread).
var max_builds_in_flight := MAX_BUILDS_IN_FLIGHT
var _evicting := false
var _frame_added := 0
var _frame_freed := 0
var _frame_applied := 0
var _last_added := 0
var _last_freed := 0
var _last_applied := 0
var _prev_process_usec := 0
var _last_process_usec := 0
var _measuring := false
var _render_cpu_max := 0.0 ## longest measured render CPU time (ms) since the last report
var _render_gpu_max := 0.0 ## longest measured GPU time (ms) since the last report
var _frame_max := 0.0 ## longest frame (s) since the last report
var _slow_frames := 0 ## frames over 25 ms since the last report
var _process_usec_max := 0 ## longest terrain _process since the last report
## Plan on a background thread (the game sets this; tests plan on the calling thread so they are deterministic).
var threaded_planning := false

var _material := StandardMaterial3D.new()
var _detail_material: ShaderMaterial ## null = plain vertex-colour material (switch off, or an asset missing)
var _root := Node3D.new()      # parent of every chunk node
var _anchor: WorldPos = null   # chunk nodes are positioned relative to this; _root is offset from the render origin
var _chunks := {}              # key -> record: every uploaded chunk, visible or hidden
var _available_grids := {}     # key -> grid of the uploaded chunk
var _displayed := {}           # key -> record: the visible subset of _chunks
var _displayed_prefixes := {}  # key -> count of visible descendants
var _desired := {}             # leaf keys of the latest plan
var _internal := {}            # split keys of the latest plan
var _fallback := {}            # backstop keys (levels in FALLBACK_LEVELS) seen at the first plan
var _pending := {}             # key -> grid being built
var _build_order: Array[int] = [] # keys to build, most urgent first (the latest plan)
var _order_cursor := 0
var _new_hints := {}           # key -> centre height of chunks built since the last plan request
var _morphing := {}            # key -> true while the chunk eases from its parent's shape
var _build_state := BuildState.new()
var _task_ids: Array[int] = []
var _seconds_since_plan := PLAN_INTERVAL_SECONDS
var _tick := 0
var _hidden_bytes := 0
var _hidden_count := 0
var _build_seconds_ema := 0.01
var _lookahead_seconds := PRELOAD_MIN_SECONDS
var _plan_thread: Thread
var _plan_semaphore := Semaphore.new()
var _plan_mutex := Mutex.new()
var _plan_request = null
var _plan_result = null
var _plan_in_flight := false
var _plan_stop := false
var _stats_report_timer := 0.0
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
	"plan_compute_usec_max": 0,
	"visibility_usec_sum": 0,
	"visibility_passes": 0,
}


func _init(planet_body: PlanetBody = null) -> void:
	name = "PlanetTerrain"
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps loading chunks behind the title screen / pause menu
	planet = planet_body
	planner = LodPlanner.new(planet_body)
	# Half the cores, not all but two: on Apple silicon (4 fast + 6 slow cores) eight busy builders starve the main, render and
	# physics threads and the frame time collapses to 40-120 ms whenever a burst of chunks is wanted.
	max_builds_in_flight = clampi(int(OS.get_processor_count() * 0.5), 2, 6)
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_root.name = "Chunks"
	add_child(_root)
	if planet_body != null:
		_detail_material = TerrainDetail.build_material(planet_body.atmosphere_height, planet_body.look)


func _ready() -> void:
	add_to_group("origin_shift")


## Rodina-style ground-to-orbit colour lean, from the viewer's height above the ground (no-op for the Sol style).
func set_viewer_altitude(altitude_metres: float) -> void:
	if _detail_material != null and planet != null and planet.look != null:
		_detail_material.set_shader_parameter("orbit_mix", planet.look.orbit_mix_at(altitude_metres))


func _process(delta: float) -> void:
	var process_started := Time.get_ticks_usec()
	_frame_max = maxf(_frame_max, delta)
	if threaded_planning and OS.is_debug_build() and is_inside_tree():
		var viewport_rid := get_viewport().get_viewport_rid()
		if not _measuring:
			RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
			_measuring = true
		_render_cpu_max = maxf(_render_cpu_max, RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid))
		_render_gpu_max = maxf(_render_gpu_max, RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid))
	if delta > 0.025:
		_slow_frames += 1
	if delta > 0.03 and threaded_planning and OS.is_debug_build():
		# The frame that just ended took `delta`; the counters below are what this node did in it.
		print("slow frame %.0f ms | engine process %.1f ms  physics %.1f ms | this frame: chunks added %d  freed %d  plans applied %d  builds running %d | frame total %.1f ms in terrain" % [
			delta * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			_last_added, _last_freed, _last_applied, _pending.size(), float(_last_process_usec) / 1000.0])
	_last_added = _frame_added
	_last_freed = _frame_freed
	_last_applied = _frame_applied
	_last_process_usec = _prev_process_usec
	_frame_added = 0
	_frame_freed = 0
	_frame_applied = 0
	_seconds_since_plan += delta
	_collect_finished_builds()
	if threaded_planning:
		_collect_plan_result()
		if not _plan_in_flight and _seconds_since_plan >= PLAN_INTERVAL_SECONDS:
			_seconds_since_plan = 0.0
			_post_plan_request()
	elif _seconds_since_plan >= PLAN_INTERVAL_SECONDS * 2.0:
		_seconds_since_plan = 0.0
		_replan()
	_update_morphs(delta)
	_prev_process_usec = Time.get_ticks_usec() - process_started
	_process_usec_max = maxi(_process_usec_max, _prev_process_usec)
	_stats_report_timer += delta
	if _stats_report_timer >= 5.0 and threaded_planning and OS.is_debug_build():
		_stats_report_timer = 0.0
		_print_stream_report()


## One line every five seconds in debug runs, so a stutter can be matched to the step that caused it (worst case since the
## last line, in milliseconds on the main thread unless stated).
func _print_stream_report() -> void:
	print("terrain: shown %d  built %d  wanted %d  queued %d  building %d  | plan thread %.1f  plan main %.1f  show/hide %.1f  upload %.1f ms" % [
		_displayed.size(), _chunks.size(), _desired.size() + _internal.size(), maxi(0, _build_order.size() - _order_cursor), _pending.size(),
		float(_stats["plan_compute_usec_max"]) / 1000.0, float(_stats["plan_usec_max"]) / 1000.0,
		float(_stats["visibility_usec_max"]) / 1000.0, float(_stats["upload_usec_max"]) / 1000.0])
	print("frames: longest %.1f ms  over 25 ms: %d  | terrain _process longest %.1f ms" % [_frame_max * 1000.0, _slow_frames, float(_process_usec_max) / 1000.0])
	print("render: cpu %.1f ms  gpu %.1f ms  draw calls %d  objects %d  triangles %d  refresh %.0f Hz" % [
		_render_cpu_max, _render_gpu_max,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		DisplayServer.screen_get_refresh_rate()])
	_render_cpu_max = 0.0
	_render_gpu_max = 0.0
	_frame_max = 0.0
	_slow_frames = 0
	_process_usec_max = 0
	for stat in ["plan_compute_usec_max", "plan_usec_max", "visibility_usec_max", "upload_usec_max"]:
		_stats[stat] = 0


func apply_origin_shift(shift: Vector3) -> void:
	render_origin = render_origin.offset_by(shift)
	if _anchor == null:
		return
	if _anchor.to_local_vector3(render_origin).length() > REANCHOR_METRES:
		_anchor = render_origin.duplicate_position()
		for chunk_record in _chunks.values():
			_place(chunk_record)
	_update_root()


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

## One planning pass on the calling thread (what tests drive; the game uses the planning thread).
func _replan() -> void:
	var started := Time.get_ticks_usec()
	_apply_plan(_compute_plan(_make_plan_request()))
	_record_plan_cost(Time.get_ticks_usec() - started)


func _make_plan_request() -> Dictionary:
	var request := {
		"viewer": viewer.duplicate_position(),
		"corridor": _preload_points(),
		"available": _available_grids.duplicate(),
		"hints": _new_hints,
		"speed": viewer_velocity.length(),
	}
	_new_hints = {}
	return request


func _post_plan_request() -> void:
	var started := Time.get_ticks_usec()
	if _plan_thread == null:
		_plan_thread = Thread.new()
		_plan_thread.start(_plan_thread_loop)
	var request := _make_plan_request()
	_plan_mutex.lock()
	_plan_request = request
	_plan_mutex.unlock()
	_plan_in_flight = true
	_plan_semaphore.post()
	_record_plan_cost(Time.get_ticks_usec() - started)


func _plan_thread_loop() -> void:
	while true:
		_plan_semaphore.wait()
		if _plan_stop:
			return
		_plan_mutex.lock()
		var request = _plan_request
		_plan_request = null
		_plan_mutex.unlock()
		if request == null:
			continue
		var result := _compute_plan(request)
		_plan_mutex.lock()
		_plan_result = result
		_plan_mutex.unlock()


func _collect_plan_result() -> void:
	_plan_mutex.lock()
	var result = _plan_result
	_plan_result = null
	_plan_mutex.unlock()
	if result == null:
		return
	_plan_in_flight = false
	var started := Time.get_ticks_usec()
	_apply_plan(result)
	_record_plan_cost(Time.get_ticks_usec() - started)


func _record_plan_cost(spent: int) -> void:
	_stats["plan_usec_max"] = maxi(int(_stats["plan_usec_max"]), spent)
	_stats["plan_usec_sum"] = int(_stats["plan_usec_sum"]) + spent


## The pure part of a pass, safe on the planning thread: reads only the request and the planner.
func _compute_plan(request: Dictionary) -> PlanResult:
	var started := Time.get_ticks_usec()
	var hints: Dictionary = request["hints"]
	for key in hints:
		planner.note_height(key, float(hints[key]))
	var corridor: Array = request["corridor"]
	planner.speed = float(request.get("speed", 0.0))
	var tree := planner.plan(request["viewer"], corridor)
	var result := PlanResult.new()
	result.leaves = tree["leaves"]
	result.internal = tree["internal"]
	var available: Dictionary = request["available"]
	var viewer_position: WorldPos = request["viewer"]
	var viewer_point := Vector3(viewer_position.x, viewer_position.y, viewer_position.z)
	var corridor_points: Array[Vector3] = []
	var corridor_along: Array[float] = [] # path distance from the viewer to each corridor point
	for point in corridor:
		var corridor_point := Vector3(point.x, point.y, point.z)
		corridor_points.append(corridor_point)
		corridor_along.append(viewer_point.distance_to(corridor_point))
	# Candidates as Vector4i(urgency in metres, level, key high bits, key low bits) so the native sort orders them
	# without a script comparator. The backstop levels are first of all.
	var candidates: Array[Vector4i] = []
	for key in result.leaves:
		_add_candidate(candidates, key, true, available, viewer_point, corridor_points, corridor_along)
	for key in result.internal:
		_add_candidate(candidates, key, false, available, viewer_point, corridor_points, corridor_along)
	candidates.sort()
	for candidate in candidates:
		result.order.append((candidate.z << 32) | (candidate.w & 0xFFFFFFFF))
	result.tiles = _resolve_all(result.internal, available)
	result.compute_usec = Time.get_ticks_usec() - started
	return result


func _add_candidate(candidates: Array[Vector4i], key: int, is_leaf: bool, available: Dictionary, viewer_point: Vector3, corridor_points: Array[Vector3], corridor_along: Array[float]) -> void:
	if int(available.get(key, 0)) >= _required_grid(key, is_leaf):
		return
	var level := ChunkKey.level_of(key)
	var score := -1000000.0 + float(level) if level in FALLBACK_LEVELS else planner.urgency(key, viewer_point, corridor_points, corridor_along, AHEAD_DISTANCE_WEIGHT)
	candidates.append(Vector4i(clampi(int(score), -0x7FFFFFFF, 0x7FFFFFFF), level, key >> 32, key & 0xFFFFFFFF))


## Grid a node is built at. The backstop levels use cheap grids unless they are themselves what is shown.
static func _required_grid(key: int, is_leaf: bool) -> int:
	var level := ChunkKey.level_of(key)
	if level in FALLBACK_LEVELS and not is_leaf:
		return ChunkMesher.grid_for_level(level)
	return ChunkMesher.FINE_GRID


## The chunks to show for the six faces. A split node shows its four children only when all four can be shown; otherwise
## it shows itself when it exists; otherwise whatever its children can show (an ancestor then covers the rest).
static func _resolve_all(internal: Dictionary, available: Dictionary) -> Dictionary:
	var shown: Array[int] = []
	for face in 6:
		_resolve_tiles(ChunkKey.make(face, 0, 0, 0), internal, available, shown)
	var tiles := {}
	for key in shown:
		tiles[key] = true
	return tiles


static func _resolve_tiles(key: int, internal: Dictionary, available: Dictionary, out: Array[int]) -> bool:
	if internal.has(key):
		var start := out.size()
		var complete := true
		for child_column in 2:
			for child_row in 2:
				if not _resolve_tiles(ChunkKey.child_of(key, child_column, child_row), internal, available, out):
					complete = false
		if complete:
			return true
		if available.has(key):
			out.resize(start)
			out.append(key)
			return true
		return false
	if available.has(key):
		out.append(key)
		return true
	return false


func _apply_plan(result: PlanResult) -> void:
	_frame_applied += 1
	_tick += 1
	_desired = result.leaves
	_internal = result.internal
	_stats["plan_count"] = int(_stats["plan_count"]) + 1
	_stats["plan_compute_usec_max"] = maxi(int(_stats["plan_compute_usec_max"]), result.compute_usec)
	_count_desired_by_level()
	if _fallback.is_empty():
		_fallback = _fallback_ancestors(_desired)
	_build_order = result.order
	_order_cursor = 0
	_stats["peak_queue"] = maxi(int(_stats["peak_queue"]), _build_order.size())
	_update_lookahead()
	_start_queued_builds()
	_apply_tiles(result.tiles)


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


func _update_lookahead() -> void:
	var remaining := maxi(0, _build_order.size() - _order_cursor) + _pending.size()
	var backlog_seconds := float(remaining) * _build_seconds_ema / float(maxi(1, max_builds_in_flight))
	_lookahead_seconds = clampf(2.0 + 2.0 * backlog_seconds, PRELOAD_MIN_SECONDS, PRELOAD_MAX_SECONDS)


## The predicted corridor ahead of the viewer: PRELOAD_CORRIDOR_POINTS points spaced along the
## velocity up to the lookahead distance. Capped in metres so an orbital speed cannot flood the
## planner. Empty when the viewer is (nearly) still.
func _preload_points() -> Array[WorldPos]:
	var points: Array[WorldPos] = []
	var speed := viewer_velocity.length()
	if speed < 1.0:
		return points
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
	while _pending.size() < max_builds_in_flight and _order_cursor < _build_order.size():
		var key: int = _build_order[_order_cursor]
		_order_cursor += 1
		if _pending.has(key):
			continue
		var is_leaf := _desired.has(key)
		if not is_leaf and not _internal.has(key):
			continue
		var grid := _required_grid(key, is_leaf)
		if int(_available_grids.get(key, 0)) >= grid:
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
	mesh_data["mesh"] = ChunkMesher.make_mesh(mesh_data) # the main thread only has to add a node
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
	if _plan_thread != null:
		_plan_stop = true
		_plan_semaphore.post()
		_plan_thread.wait_to_finish()
		_plan_thread = null


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
		var build_ms := float(mesh_data.get("build_microseconds", 0)) / 1000.0
		times.append(build_ms)
		if times.size() > 256:
			times.pop_front()
		by_level[level] = times
		_build_seconds_ema = lerpf(_build_seconds_ema, build_ms / 1000.0, 0.1)
		if mesh_data.has("centre_height"):
			_new_hints[key] = float(mesh_data["centre_height"])
		_add_chunk(key, mesh_data)
	if uploaded > 0:
		_stats["upload_usec_max"] = maxi(int(_stats["upload_usec_max"]), Time.get_ticks_usec() - started)
	_start_queued_builds()


## Uploads a finished mesh as an available (hidden) chunk; a plan pass decides when it is shown. A better-grid mesh
## for a chunk on screen takes its place in the same frame.
func _add_chunk(key: int, mesh_data: Dictionary) -> void:
	_frame_added += 1
	var grid: int = int(mesh_data.get("grid", ChunkMesher.FINE_GRID))
	var existing: Dictionary = _chunks.get(key, {})
	var was_visible := false
	if not existing.is_empty():
		if int(existing["grid"]) >= grid:
			_stats["discarded"] = int(_stats["discarded"]) + 1
			return
		was_visible = bool(existing["visible"])
		_free_chunk(key)
	if _anchor == null:
		_anchor = render_origin.duplicate_position()
		_update_root()
	var mesh: ArrayMesh = mesh_data["mesh"] if mesh_data.has("mesh") else ChunkMesher.make_mesh(mesh_data)
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
	_root.add_child(instance)
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
		"morphs": _detail_material != null and mesh_data.has("morph"),
		"morph_t": 1.0,
	}
	_chunks[key] = record
	_available_grids[key] = grid
	_hidden_bytes += int(record["bytes"])
	_hidden_count += 1
	_place(record)
	if was_visible:
		_set_visible(record, true)


func _free_chunk(key: int) -> void:
	_frame_freed += 1
	var record: Dictionary = _chunks.get(key, {})
	if record.is_empty():
		return
	if bool(record["visible"]):
		_set_visible(record, false)
	_hidden_bytes -= int(record["bytes"])
	_hidden_count -= 1
	(record["node"] as Node).queue_free()
	_chunks.erase(key)
	_available_grids.erase(key)
	_morphing.erase(key)


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
	var colors: PackedColorArray = mesh_data.get("colors", PackedColorArray())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	return vertices.size() * 36 + colors.size() * 16 + indices.size() * 4 + 64 # position, normal and geomorph offset: 12 bytes each


# --- visibility -----------------------------------------------------------------------------

## Re-decides what is shown from the chunks available now, on the calling thread (tests, and tools that drive a terrain by
## hand; the game gets the same decision from each planning pass).
func _update_visibility() -> void:
	_apply_tiles(_resolve_all(_internal, _available_grids))


## Makes exactly `tiles` visible: shows what is new (a chunk replacing its parent starts in the parent's shape), hides the
## rest. Chunks that were freed since the plan was made are skipped.
func _apply_tiles(tiles: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	var to_show: Array[int] = []
	for key in tiles:
		if _chunks.has(key) and not _displayed.has(key):
			to_show.append(key)
	var to_hide: Array[int] = []
	for key in _displayed:
		if not tiles.has(key):
			to_hide.append(key)
	for key in to_show:
		var record: Dictionary = _chunks[key]
		var replaces_parent := ChunkKey.level_of(key) > 0 and _displayed.has(ChunkKey.parent_of(key)) and not _displayed_prefixes.has(key)
		_set_visible(record, true)
		record["used"] = _tick
		_begin_morph(record, replaces_parent)
	for key in to_hide:
		_set_visible(_chunks[key], false)
	_evict_hidden()
	var spent := Time.get_ticks_usec() - started
	_stats["visibility_usec_max"] = maxi(int(_stats["visibility_usec_max"]), spent)
	_stats["visibility_usec_sum"] = int(_stats["visibility_usec_sum"]) + spent
	_stats["visibility_passes"] = int(_stats["visibility_passes"]) + 1


func _begin_morph(record: Dictionary, from_parent: bool) -> void:
	if not bool(record.get("morphs", false)):
		return
	var node := record["node"] as MeshInstance3D
	var key: int = record["key"]
	if from_parent:
		record["morph_t"] = 0.0
		node.set_instance_shader_parameter("morph", 1.0)
		_morphing[key] = true
	else:
		if float(record["morph_t"]) < 1.0:
			node.set_instance_shader_parameter("morph", 0.0)
		record["morph_t"] = 1.0
		_morphing.erase(key)


func _update_morphs(delta: float) -> void:
	if _morphing.is_empty():
		return
	for key in _morphing.keys():
		var record: Dictionary = _chunks.get(key, {})
		if record.is_empty() or not bool(record["visible"]):
			_morphing.erase(key)
			continue
		var progress := float(record["morph_t"]) + delta / MORPH_SECONDS
		var node := record["node"] as MeshInstance3D
		if progress >= 1.0:
			record["morph_t"] = 1.0
			node.set_instance_shader_parameter("morph", 0.0)
			_morphing.erase(key)
		else:
			record["morph_t"] = progress
			node.set_instance_shader_parameter("morph", 1.0 - smoothstep(0.0, 1.0, progress))


func _set_visible(record: Dictionary, show: bool) -> void:
	var key: int = record["key"]
	record["visible"] = show
	(record["node"] as MeshInstance3D).visible = show
	if show:
		if bool(record.get("was_shown", false)):
			_stats["cache_hits"] = int(_stats["cache_hits"]) + 1
		record["was_shown"] = true
		_stats["shown"] = int(_stats["shown"]) + 1
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
## Frees the least recently used hidden chunks once the cache is over budget. It frees down to EVICT_TARGET of the
## budget in small steps (EVICT_PER_PASS per plan pass) so a big overshoot never becomes one long frame, and it only
## scans while over budget.
func _evict_hidden() -> void:
	if not _evicting and _hidden_bytes <= READY_CACHE_BUDGET_BYTES and _hidden_count <= READY_CACHE_MAX_ENTRIES:
		return
	_evicting = true
	var hidden: Array = []
	for key in _chunks:
		var record: Dictionary = _chunks[key]
		if bool(record["visible"]) or _fallback.has(key) or _desired.has(key) or _internal.has(key) or _pending.has(key) or ChunkKey.level_of(key) in FALLBACK_LEVELS:
			continue
		hidden.append([int(record["used"]), key])
	hidden.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var freed := 0
	for entry in hidden:
		if freed >= EVICT_PER_PASS:
			break
		if _hidden_bytes <= READY_CACHE_BUDGET_BYTES * EVICT_TARGET and _hidden_count <= int(READY_CACHE_MAX_ENTRIES * EVICT_TARGET):
			_evicting = false
			break
		_free_chunk(entry[1])
		_stats["cache_evicted"] = int(_stats["cache_evicted"]) + 1
		freed += 1


## Chunk nodes sit under _root at positions relative to the anchor; the root is offset from the render origin, so an
## origin shift moves one node.
func _place(chunk_record: Dictionary) -> void:
	var instance: MeshInstance3D = chunk_record["node"]
	instance.position = (chunk_record["origin"] as WorldPos).to_local_vector3(_anchor)
	instance.reset_physics_interpolation()


func _update_root() -> void:
	if _anchor == null:
		return
	_root.position = _anchor.to_local_vector3(render_origin)
	_root.reset_physics_interpolation()


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


## True when the point of every desired leaf has some visible cover (itself, finer, or an ancestor).
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


## Test hook: upload and re-run the visibility decision.
func _show_chunk(key: int, mesh_data: Dictionary) -> void:
	_add_chunk(key, mesh_data)
	_update_visibility()


## Test hook: re-run the visibility decision.
func _remove_obsolete_chunks() -> void:
	_update_visibility()


## Test hook: sets the plan by hand from a set of leaf keys: the leaves, every ancestor as a split node, and every
## sibling of those that is not itself split as a leaf too, so the leaves tile the planet.
func set_plan_for_test(leaves: Array) -> void:
	_desired = {}
	_internal = {}
	for leaf in leaves:
		var ancestor: int = leaf
		while ChunkKey.level_of(ancestor) > 0:
			ancestor = ChunkKey.parent_of(ancestor)
			_internal[ancestor] = true
	for leaf in leaves:
		_desired[leaf] = true
	for face in 6:
		var root := ChunkKey.make(face, 0, 0, 0)
		if not _desired.has(root) and not _internal.has(root):
			_desired[root] = true
	for key in _internal.keys():
		for child_column in 2:
			for child_row in 2:
				var child := ChunkKey.child_of(key, child_column, child_row)
				if not _internal.has(child):
					_desired[child] = true


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
	copy["internal_count"] = _internal.size()
	copy["displayed_count"] = _displayed.size()
	copy["available_count"] = _chunks.size()
	copy["pending_count"] = _pending.size()
	copy["queued_count"] = maxi(0, _build_order.size() - _order_cursor)
	copy["cache_entries"] = _hidden_count
	copy["cache_bytes"] = _hidden_bytes
	copy["latency_ema_s"] = _build_seconds_ema
	copy["lookahead_s"] = _lookahead_seconds
	copy["max_builds_in_flight"] = max_builds_in_flight
	return copy
