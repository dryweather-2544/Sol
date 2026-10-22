class_name GpuHeights
extends RefCounted
## Runs data/shaders/rodina_heights.glsl (Rodina's planet height functions, see RodinaPlanets) on the GPU
## for a batch of unit directions. This is how Rodina builds terrain: the GPU renders GetPlanetHeight into
## height textures. Terrain chunks ask it for their whole lattice at once.
##
## A RenderingDevice may only be used from the thread that created it, so one dedicated thread creates a private
## local device and does every dispatch; any number of other threads queue requests and wait for the answer.
## warm_up() starts it (main thread, once, waits for it to finish setting up); is_ready() is false when there is
## no GPU device (headless runs, tests, a failed shader compile) and callers then keep the CPU path.

const SHADER_PATH := "res://data/shaders/rodina_heights.glsl"
const CAPACITY := 2048 ## points per dispatch (a 32-quad chunk lattice is 35 x 35 = 1225)
const GROUP_SIZE := 64

static var _state := 0 ## 0 not tried, 1 ready, 2 unavailable
static var _instance: GpuHeights = null

var _thread: Thread
var _work := Semaphore.new()
var _setup_done := Semaphore.new()
var _queue_mutex := Mutex.new()
var _queue: Array = []
var _stop := false
var _setup_ok := false
var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _directions_buffer: RID
var _heights_buffer: RID
var _features_buffer: RID
var _points_buffer: RID
var _uniform_set: RID
var dispatch_count := 0


## Main thread, once. Safe to call again.
static func warm_up() -> void:
	if _state != 0:
		return
	_state = 2
	if DisplayServer.get_name() == "headless" or not ResourceLoader.exists(SHADER_PATH):
		return
	var gpu := GpuHeights.new()
	RodinaPlanets.points() # build the shared point set before the thread reads it
	gpu._thread = Thread.new()
	gpu._thread.start(gpu._run)
	gpu._setup_done.wait()
	if gpu._setup_ok:
		_instance = gpu
		_state = 1
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null and tree.root != null:
			tree.root.tree_exiting.connect(GpuHeights.shutdown)
	else:
		gpu._thread.wait_to_finish()


static func is_ready() -> bool:
	return _state == 1


static func instance() -> GpuHeights:
	return _instance


## Stops the GPU thread (called when the scene tree exits; tools call it before quitting).
static func shutdown() -> void:
	if _instance == null:
		return
	var gpu := _instance
	_instance = null
	_state = 2
	gpu._stop = true
	gpu._work.post()
	gpu._thread.wait_to_finish()


## Test/benchmark hook: pretend there is no GPU (so callers fall back), or restore it.
static func set_enabled(enabled: bool) -> void:
	if _instance != null:
		_state = 1 if enabled else 2


## The GPU thread.
func _run() -> void:
	_setup_ok = _setup()
	_setup_done.post()
	if not _setup_ok:
		return
	while true:
		_work.wait()
		if _stop:
			break
		_queue_mutex.lock()
		var request: Dictionary = _queue.pop_front() if not _queue.is_empty() else {}
		_queue_mutex.unlock()
		if request.is_empty():
			continue
		var outcome := _dispatch(request["directions"], request["count"], request["grammar"], request["scale"], request["want_features"])
		request["result"] = outcome["heights"]
		request["features"] = outcome["features"]
		(request["done"] as Semaphore).post()
	_rd.free_rid(_uniform_set)
	_rd.free_rid(_pipeline)
	_rd.free_rid(_shader)
	_rd.free_rid(_directions_buffer)
	_rd.free_rid(_heights_buffer)
	_rd.free_rid(_features_buffer)
	_rd.free_rid(_points_buffer)
	_rd.free()


func _setup() -> bool:
	var shader_file := load(SHADER_PATH) as RDShaderFile
	if shader_file == null:
		return false
	var spirv := shader_file.get_spirv()
	if spirv == null or spirv.compile_error_compute != "":
		push_warning("GpuHeights: shader did not compile: %s" % (spirv.compile_error_compute if spirv != null else "no SPIR-V"))
		return false
	_rd = RenderingServer.create_local_rendering_device()
	if _rd == null:
		push_warning("GpuHeights: no local rendering device on the GPU thread")
		return false
	_shader = _rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		return false
	_pipeline = _rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():
		return false
	_directions_buffer = _rd.storage_buffer_create(CAPACITY * 16)
	_heights_buffer = _rd.storage_buffer_create(CAPACITY * 4)
	_features_buffer = _rd.storage_buffer_create(CAPACITY * 16)
	_points_buffer = _rd.storage_buffer_create(RodinaPlanets.VORONOI_COUNT * 16, RodinaPlanets.points_as_floats().to_byte_array())
	var uniforms: Array[RDUniform] = []
	for pair in [[0, _directions_buffer], [1, _heights_buffer], [2, _points_buffer], [3, _features_buffer]]:
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = pair[0]
		uniform.add_id(pair[1])
		uniforms.append(uniform)
	_uniform_set = _rd.uniform_set_create(uniforms, _shader, 0)
	return _uniform_set.is_valid()


## directions: count x (x, y, z, 0) float32 unit vectors. Returns count heights (metres above the planet
## radius), or an empty array if the GPU failed (callers fall back to the CPU). Any thread.
func heights(directions: PackedFloat32Array, count: int, grammar: int, asteroid_scale: float) -> PackedFloat32Array:
	return _request(directions, count, grammar, asteroid_scale, false)["heights"]


## Same dispatch, plus the planet feature texture per point: {heights: count floats, features: count x (base, plateau,
## mountains, holes) floats}. Both arrays are empty if the GPU failed. Any thread.
func heights_and_features(directions: PackedFloat32Array, count: int, grammar: int, asteroid_scale: float) -> Dictionary:
	return _request(directions, count, grammar, asteroid_scale, true)


func _request(directions: PackedFloat32Array, count: int, grammar: int, asteroid_scale: float, want_features: bool) -> Dictionary:
	var request := {"directions": directions, "count": count, "grammar": grammar, "scale": asteroid_scale, "want_features": want_features,
		"done": Semaphore.new(), "result": PackedFloat32Array(), "features": PackedFloat32Array()}
	_queue_mutex.lock()
	_queue.append(request)
	_queue_mutex.unlock()
	_work.post()
	(request["done"] as Semaphore).wait()
	return {"heights": request["result"], "features": request["features"]}


## GPU thread only.
func _dispatch(directions: PackedFloat32Array, count: int, grammar: int, asteroid_scale: float, want_features: bool) -> Dictionary:
	var result := PackedFloat32Array()
	var feature_result := PackedFloat32Array()
	var done := 0
	while done < count:
		var batch := mini(CAPACITY, count - done)
		var slice := directions.slice(done * 4, (done + batch) * 4)
		_rd.buffer_update(_directions_buffer, 0, slice.size() * 4, slice.to_byte_array())
		var push := PackedByteArray()
		push.resize(16)
		push.encode_u32(0, batch)
		push.encode_u32(4, grammar)
		push.encode_float(8, asteroid_scale)
		push.encode_u32(12, 1 if want_features else 0)
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _pipeline)
		_rd.compute_list_bind_uniform_set(list, _uniform_set, 0)
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, ceili(float(batch) / GROUP_SIZE), 1, 1)
		_rd.compute_list_end()
		_rd.submit()
		_rd.sync()
		var data := _rd.buffer_get_data(_heights_buffer, 0, batch * 4).to_float32_array()
		if data.size() != batch:
			return {"heights": PackedFloat32Array(), "features": PackedFloat32Array()}
		result.append_array(data)
		if want_features:
			var feature_data := _rd.buffer_get_data(_features_buffer, 0, batch * 16).to_float32_array()
			if feature_data.size() != batch * 4:
				return {"heights": PackedFloat32Array(), "features": PackedFloat32Array()}
			feature_result.append_array(feature_data)
		done += batch
		dispatch_count += 1
	return {"heights": result, "features": feature_result}
