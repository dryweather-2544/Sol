extends SceneTree
## Where does one Jarilo/Perun height sample spend its time? Times each grammar building block
## on N random directions. Usage: godot --headless --path . -s res://tools/n14_height_breakdown.gd

const N := 2000

func _time(label: String, directions: Array[Vector3], fn: Callable) -> float:
	var started := Time.get_ticks_usec()
	var sink := 0.0
	for p in directions:
		sink += fn.call(p)
	var us := float(Time.get_ticks_usec() - started) / directions.size()
	print("%-42s %7.2f us  (%s)" % [label, us, str(snappedf(sink, 0.1)).left(6)])
	return us


func _init() -> void:
	var profile := TerrainProfile.new()
	profile.grammar = TerrainProfile.Grammar.JARILO
	var h := HeightFunction.new(profile)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var dirs: Array[Vector3] = []
	for i in N:
		dirs.append(Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized())
	_time("full jarilo height_xyz", dirs, func(p: Vector3) -> float: return h.height_xyz(p.x, p.y, p.z))
	_time("empty callable", dirs, func(p: Vector3) -> float: return p.x)
	_time("raw get_noise_3d (1 octave perlin)", dirs, func(p: Vector3) -> float: return h._grammar_noise(0, 1.0, 1, 1.0, 2.0).get_noise_3d(p.x, p.y, p.z))
	_time("_grammar_noise lookup only", dirs, func(p: Vector3) -> float: return h._grammar_noise(0, 1.0, 9, 1.0, 2.0).frequency)
	_time("_fractal 9 oct", dirs, func(p: Vector3) -> float: return h._fractal(0, p, 1.0, 1.0, 2.0, 9))
	_time("_fractal 16 oct", dirs, func(p: Vector3) -> float: return h._fractal(10, p, 2.0, 0.5, 2.0, 16))
	_time("_warp 9 oct (4 fractals)", dirs, func(p: Vector3) -> float: return h._warp(0, p, 1.0, 1.0, 2.0, 9).x)
	_time("_warp 2 oct", dirs, func(p: Vector3) -> float: return h._warp(10, p, 1.0, 1.0, 2.0, 2).x)
	_time("_special 12 oct gain0", dirs, func(p: Vector3) -> float: return h._special(0, p, 0.0, 500.0, 2.0, 12))
	_time("_special 9 oct", dirs, func(p: Vector3) -> float: return h._special(153, p, 0.5, 4000.0, 2.0, 9))
	_time("_voronoi_base", dirs, func(p: Vector3) -> float: return h._voronoi_base(p, 0.5, 0.5, 0.25))
	quit()
