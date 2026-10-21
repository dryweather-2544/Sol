extends SceneTree
## N14 terrain micro-benchmark: per-sample height cost and per-level chunk build cost for one world.
## Usage: godot --headless --path . -s res://tools/n14_terrain_bench.gd -- [planet_id] [samples]
## Single-threaded on purpose: it measures the work one worker does. See tools/n14_stream_probe.gd
## for the threaded streaming scenarios.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var planet_id := StringName(args[0]) if args.size() > 0 else &"planet"
	var samples := int(args[1]) if args.size() > 1 else 2000
	var system := StarSystem.default_system()
	var body = system.bodies[planet_id]
	var planet: PlanetBody = body.make_planet_body() if body.has_method("make_planet_body") else null
	if planet == null:
		planet = PlanetBody.new(body.terrain_profile)
	var profile := planet.profile_or_default()
	print("planet=%s grammar=%d radius=%.0f finest_level=%d" % [planet_id, profile.grammar, planet.radius, planet.finest_lod_level()])

	var height_function := HeightFunction.new(profile)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var directions: Array[Vector3] = []
	for i in samples:
		directions.append(Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized())
	var started := Time.get_ticks_usec()
	var checksum := 0.0
	for direction in directions:
		checksum += height_function.height_xyz(direction.x, direction.y, direction.z)
	var per_sample := float(Time.get_ticks_usec() - started) / samples
	print("height_xyz: %.1f us/sample (checksum %.1f)" % [per_sample, checksum])

	for level in [0, 1, 2, 4, 6, 8, 10, 12, 14, planet.finest_lod_level()]:
		var key := ChunkKey.make(0, level, (1 << level) / 2, (1 << level) / 2)
		var t0 := Time.get_ticks_usec()
		var mesh_data := ChunkMesher.build(key, planet)
		var total_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		var grid: int = mesh_data.get("grid", ChunkMesher.GRID)
		var lattice_samples := (grid + 3) * (grid + 3)
		var t1 := Time.get_ticks_usec()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = mesh_data["vertices"]
		arrays[Mesh.ARRAY_NORMAL] = mesh_data["normals"]
		arrays[Mesh.ARRAY_COLOR] = mesh_data["colors"]
		arrays[Mesh.ARRAY_INDEX] = mesh_data["indices"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var upload_ms := float(Time.get_ticks_usec() - t1) / 1000.0
		print("level %2d grid %2d samples %4d build %7.1f ms (%.1f us/sample all-in) upload %.2f ms" % [level, grid, lattice_samples, total_ms, total_ms * 1000.0 / lattice_samples, upload_ms])
	quit()
