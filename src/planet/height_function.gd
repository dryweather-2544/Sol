class_name HeightFunction
extends RefCounted
## The single source of truth for terrain height: the mesh, ground contact and walking all
## ask this. Height is metres above profile.radius for a point given as a direction from the
## planet centre (passed as three doubles so nothing is rounded to 32 bits before the noise).
##
## Precision note: FastNoiseLite takes 32-bit coordinates. Macro noise uses unit-sphere
## directions (fine). Metre-scale detail uses position / wavelength and goes through
## _smooth_noise so the 32-bit rounding cannot make terraces.

const LATTICE_STEPS_PER_UNIT := 64.0

var profile: TerrainProfile
var _macro: FastNoiseLite
var _ridge: FastNoiseLite
var _hills: FastNoiseLite
var _rough: FastNoiseLite
var _mid: FastNoiseLite
var _large: FastNoiseLite
var _grammar_noises := {}
## Chunk terrain is generated on worker threads; the cache must not be mutated concurrently.
var _noise_mutex := Mutex.new()


func _init(terrain_profile: TerrainProfile) -> void:
	profile = terrain_profile
	_macro = _make_noise("macro", 6, FastNoiseLite.FRACTAL_FBM)
	_ridge = _make_noise("ridge", 4, FastNoiseLite.FRACTAL_NONE)
	_hills = _make_noise("hills", 3, FastNoiseLite.FRACTAL_FBM)
	_rough = _make_noise("rough", 2, FastNoiseLite.FRACTAL_FBM)
	_mid = _make_noise("mid", 3, FastNoiseLite.FRACTAL_FBM)
	_large = _make_noise("large", 2, FastNoiseLite.FRACTAL_FBM)


func _make_noise(label: String, octaves: int, fractal: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = SeedHash.derive(profile.terrain_seed, label) & 0x7FFFFFFF
	noise.frequency = 1.0
	noise.fractal_type = fractal
	if fractal != FastNoiseLite.FRACTAL_NONE:
		noise.fractal_octaves = octaves
		noise.fractal_gain = 0.5
		noise.fractal_lacunarity = 2.0
	return noise


## (dx, dy, dz) must be a unit direction.
func height_xyz(dx: float, dy: float, dz: float) -> float:
	var direction := Vector3(dx, dy, dz)
	match profile.grammar:
		TerrainProfile.Grammar.PERUN:
			return _perun_height(direction)
		TerrainProfile.Grammar.JARILO:
			return _jarilo_height(direction)
		TerrainProfile.Grammar.VELES:
			return _veles_height(direction)
		TerrainProfile.Grammar.MORENA:
			return _morena_height(direction)
		TerrainProfile.Grammar.ASTEROID:
			return _asteroid_height(direction)
	var macro := _macro.get_noise_3d(dx * profile.macro_scale, dy * profile.macro_scale, dz * profile.macro_scale)
	var ridged := 1.0 - absf(_ridge.get_noise_3d(dx * profile.mountain_scale, dy * profile.mountain_scale, dz * profile.mountain_scale))
	var mountain_mask := smoothstep(0.05, 0.5, macro)
	var height := profile.macro_amplitude * macro + profile.mountain_amplitude * ridged * ridged * mountain_mask
	var to_hills := profile.radius / profile.hill_wavelength
	var to_rough := profile.radius / profile.rough_wavelength
	var to_mid := profile.radius / profile.mid_wavelength
	var to_large := profile.radius / profile.large_wavelength
	height += profile.large_amplitude * _smooth_noise(_large, dx * to_large, dy * to_large, dz * to_large)
	height += profile.mid_amplitude * _smooth_noise(_mid, dx * to_mid, dy * to_mid, dz * to_mid)
	height += profile.hill_amplitude * _smooth_noise(_hills, dx * to_hills, dy * to_hills, dz * to_hills)
	height += profile.rough_amplitude * _smooth_noise(_rough, dx * to_rough, dy * to_rough, dz * to_rough)
	return height


## FastNoiseLite rounds its input to 32 bits, which at these coordinate sizes (tens of thousands)
## turns smooth ground into 0.5 m wide steps. Instead sample it only at exactly representable
## lattice points (1/64 unit apart) and blend linearly in 64-bit, so height is continuous.
func _smooth_noise(noise: FastNoiseLite, x: float, y: float, z: float) -> float:
	var lattice_x := floorf(x * LATTICE_STEPS_PER_UNIT)
	var lattice_y := floorf(y * LATTICE_STEPS_PER_UNIT)
	var lattice_z := floorf(z * LATTICE_STEPS_PER_UNIT)
	var blend_x := x * LATTICE_STEPS_PER_UNIT - lattice_x
	var blend_y := y * LATTICE_STEPS_PER_UNIT - lattice_y
	var blend_z := z * LATTICE_STEPS_PER_UNIT - lattice_z
	var x0 := lattice_x / LATTICE_STEPS_PER_UNIT
	var y0 := lattice_y / LATTICE_STEPS_PER_UNIT
	var z0 := lattice_z / LATTICE_STEPS_PER_UNIT
	var x1 := (lattice_x + 1.0) / LATTICE_STEPS_PER_UNIT
	var y1 := (lattice_y + 1.0) / LATTICE_STEPS_PER_UNIT
	var z1 := (lattice_z + 1.0) / LATTICE_STEPS_PER_UNIT
	var along_x_near_low := lerpf(noise.get_noise_3d(x0, y0, z0), noise.get_noise_3d(x1, y0, z0), blend_x)
	var along_x_near_high := lerpf(noise.get_noise_3d(x0, y1, z0), noise.get_noise_3d(x1, y1, z0), blend_x)
	var along_x_far_low := lerpf(noise.get_noise_3d(x0, y0, z1), noise.get_noise_3d(x1, y0, z1), blend_x)
	var along_x_far_high := lerpf(noise.get_noise_3d(x0, y1, z1), noise.get_noise_3d(x1, y1, z1), blend_x)
	return lerpf(lerpf(along_x_near_low, along_x_near_high, blend_y), lerpf(along_x_far_low, along_x_far_high, blend_y), blend_z)


## A cached FastNoiseLite field matching the shape of FractalPerlin(aSeed, pos, multChange,
## octaveBase, octaveChange, octaves) in Rodina's _perlin.h. FastNoiseLite is the C++ equivalent
## of the shader's Perlin field and keeps chunk generation affordable. The original shader uses
## an analytic derivative for domain warping; _warp below uses a finite-difference direction,
## which is the same idea with an explicit epsilon.
func _grammar_noise(seed_value: int, frequency: float, octaves: int, gain: float, lacunarity: float, cellular := false) -> FastNoiseLite:
	var key := "%d/%.5f/%d/%.5f/%.5f/%s" % [seed_value, frequency, octaves, gain, lacunarity, str(cellular)]
	_noise_mutex.lock()
	if _grammar_noises.has(key):
		var cached: FastNoiseLite = _grammar_noises[key]
		_noise_mutex.unlock()
		return cached
	var noise := FastNoiseLite.new()
	noise.seed = SeedHash.derive(profile.terrain_seed, key) & 0x7FFFFFFF
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	noise.fractal_octaves = maxi(1, octaves)
	noise.fractal_gain = gain
	noise.fractal_lacunarity = lacunarity
	if cellular:
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
		noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		noise.cellular_jitter = 0.5
	else:
		noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_grammar_noises[key] = noise
	_noise_mutex.unlock()
	return noise


func _fractal(seed_value: int, p: Vector3, mult_change: float, octave_base: float, octave_change: float, octaves: int) -> float:
	var noise := _grammar_noise(seed_value, octave_base, octaves, mult_change, octave_change)
	return (noise.get_noise_3d(p.x, p.y, p.z) + 1.0) * 0.5


func _special(seed_value: int, p: Vector3, mult_change: float, octave_base: float, octave_change: float, octaves: int) -> float:
	# SpecialPerlin suppresses octaves where the derivative is large. A second fractal is a cheap
	# faithful-enough stand-in for the derivative weighting used by Rodina's terrain bake.
	var base := _fractal(seed_value, p, mult_change, octave_base, octave_change, octaves)
	var rough := _fractal(seed_value + 7, p, mult_change, octave_base * 1.7, octave_change, maxi(2, octaves - 1))
	return clampf(base * (0.65 + 0.35 * (1.0 - rough)), 0.0, 1.0)


func _warp(seed_value: int, p: Vector3, mult_change: float, octave_base: float, octave_change: float, octaves: int) -> Vector3:
	# FractalPerlinDerivative(...).xyz in PlanetPerun/Jarilo. The finite difference is evaluated
	# in the same direction space and is normalized by the caller.
	var e := 0.01
	var base := _fractal(seed_value, p, mult_change, octave_base, octave_change, octaves)
	var dx := _fractal(seed_value, p + Vector3(e, 0, 0), mult_change, octave_base, octave_change, octaves) - base
	var dy := _fractal(seed_value, p + Vector3(0, e, 0), mult_change, octave_base, octave_change, octaves) - base
	var dz := _fractal(seed_value, p + Vector3(0, 0, e), mult_change, octave_base, octave_change, octaves) - base
	return Vector3(dx, dy, dz) / e


func _voronoi_base(p: Vector3, scale: float, jitter: float, max_distance: float) -> float:
	# Voronoi2(VoronoiPoints, scale/jitter, maxDistance). Rodina's original points come from a GPU
	# constant buffer; FastNoiseLite's cellular field is the equivalent deterministic 3D cell field.
	var noise := _grammar_noise(0, maxf(scale, 0.0001), 1, 1.0, 2.0, true)
	noise.cellular_jitter = jitter
	var distance := absf(noise.get_noise_3d(p.x, p.y, p.z))
	return analog(distance, 0.0, max_distance, 1.0, 0.0)


static func analog(value: float, from_low: float, from_high: float, to_low: float, to_high: float) -> float:
	var ratio := clampf((value - from_low) / maxf(from_high - from_low, 1e-9), 0.0, 1.0)
	return lerpf(to_low, to_high, ratio)


static func ease_out_in_sin2(value: float) -> float:
	var t := analog(value, 0.0, 1.0, -PI * 0.5, PI * 0.5)
	return analog(sin(t), -1.0, 1.0, 0.0, 1.0)


func _holes(value: float, thresholds: Vector4) -> float:
	if value <= thresholds.y:
		return smoothstep(thresholds.x, thresholds.y, value)
	elif value <= thresholds.z:
		return 1.0
	elif value <= thresholds.w:
		return smoothstep(thresholds.w, thresholds.z, value)
	return 0.0


func _perun_height(p: Vector3) -> float:
	# GenerationVars[1..17] for Perun (EGDataPlanets.lua:286-324). Seed groups are 10/0.
	var mask_distort := _warp(10, p, 1.0, 1.0, 2.0, 2)
	var distort := _warp(0, p, 1.0, 1.0, 2.0, 9)
	var mask_coord := (p + mask_distort * 0.05 + distort * 0.005).normalized()
	var base_coords := (p + distort * 0.02).normalized()
	var mountain_distort := _warp(10, mask_coord, 1.0, 2.0, 2.0, 2)
	var mountain_coord1 := (mask_coord + mountain_distort * 0.2).normalized()
	var mountain_coords := (p + distort * 0.001).normalized()
	var base := _voronoi_base(base_coords, 0.5, 0.5, 0.25)
	var holes := _holes(_fractal(0, mountain_coords, 1.0, 128.0, 2.0, 4), Vector4(0.275, 0.375, 0.375, 0.55))
	var plateau := analog(_fractal(10, mask_coord, 3.0, 0.56, 2.0, 12), 0.5, 0.675, 0.0, 1.0)
	var mountain_perlin := _fractal(10, mountain_coord1, 3.0, 0.6, 2.0, 5)
	var mountain_mask := analog(mountain_perlin, 0.45, 0.6, 0.0, 1.0)
	var mountains := analog(_fractal(0, mountain_coords, 1.0, 1.0, 2.0, 9), 0.4, 0.7, 0.0, 1.0)
	mountains = analog(mountain_mask * mountains, 0.0, 0.5, 0.0, 1.0)
	var roughness := analog(mountains, 0.0, 0.9, 0.3, 0.5)
	mountains = mountains * mountains
	plateau = ease_out_in_sin2(analog(plateau, 0.1, 0.425, 0.0, 1.0))
	base = ease_out_in_sin2(analog(base, 0.4, 0.7, 0.3, 1.0))
	base = lerpf(base, 0.0, plateau)
	base = lerpf(base, 0.0, mountains)
	mountains = lerpf(mountains, 0.0, holes)
	var height := 0.0
	height += mountains * (20000.0 * _fractal(0, p, roughness, 500.0, 2.0, 12))
	height += plateau * (12000.0 + 5000.0 * _fractal(0, p, 0.5, 300.0, 2.0, 10))
	height += base * (500.0 * _fractal(0, p, 0.35, 3750.0, 2.0, 7))
	return height


func _jarilo_height(p: Vector3) -> float:
	# GenerationVars[1..17,100..114] for Jarilo (EGDataPlanets.lua:567-615).
	var map_distort := _warp(10, p, 1.0, 1.0, 2.0, 2)
	var feature_distort := _warp(0, p, 1.0, 1.0, 2.0, 9)
	var base_coords := (p + map_distort * 0.06 + feature_distort * 0.02).normalized()
	var plateau_coord := (p + map_distort * 0.05 + feature_distort * 0.0).normalized()
	var dunes := _voronoi_base(base_coords, 0.5, 0.5, 0.25)
	var plateau := analog(_fractal(10, plateau_coord, 2.0, 0.5, 2.0, 16), 0.4, 0.8, 0.0, 1.0)
	var mountain_distort := _warp(10, plateau_coord, 1.0, 2.0, 2.0, 2)
	var mountain_coord1 := (plateau_coord + mountain_distort * 0.0).normalized()
	var mountain_coords := (p + feature_distort * 0.001).normalized()
	var mountain_perlin := _fractal(10, mountain_coord1, 1.0, 1.0, 2.0, 9)
	var mountain_mask := analog(mountain_perlin, 0.45, 0.8, 0.0, 1.0)
	var mountains := analog(_fractal(0, mountain_coords, 1.0, 2.0, 2.0, 2), 0.0, 0.5, 0.0, 1.0)
	mountains = analog(mountain_mask * mountains, 0.0, 0.5, 0.0, 1.0)
	mountains = mountains * mountains
	var holes := _holes(_fractal(0, p, 1.0, 2500.0, 2.0, 4), Vector4(0.0, 0.0, 0.375, 0.5))
	plateau = ease_out_in_sin2(analog(plateau, 0.4, 0.8, 0.0, 1.0))
	dunes = ease_out_in_sin2(analog(dunes, 0.4, 0.7, 0.0, 1.0))
	dunes = analog(plateau, 0.0, 0.15, dunes, 0.0)
	dunes = analog(mountains, 0.05, 0.1, dunes, 0.0)
	var height := 0.0
	height += mountains * (50000.0 * _special(0, p, 0.0, 500.0, 2.0, 12))
	var plateau_hills := _special(153, p, 0.5, 4000.0, 2.0, 9)
	plateau_hills = lerpf(plateau_hills, 0.45, holes)
	height += plateau * (2000.0 + 2000.0 * plateau_hills)
	var dune_mask := dunes
	if dune_mask > 0.0:
		var dune_distort := _warp(12, p, 1.0, 0.5, 2.0, 3)
		var dune_coord := (p + dune_distort * 0.001).normalized()
		var dune_control := sin(dune_coord.dot(Vector3(1, -1, -1)) * 1000.0)
		var x1 := fposmod(dune_coord.dot(Vector3(1, 1, 1)) * 800.0, 1.0)
		var x2 := fposmod(dune_coord.dot(Vector3(1, 1, 1)) * 800.0 + 0.5, 1.0)
		var shape1 := ease_in_sin(absf(analog(x1, 0.0, 1.0, -1.0, 1.0)))
		var shape2 := ease_in_sin(absf(analog(x2, 0.0, 1.0, -1.0, 1.0)))
		var dune1 := shape1 * ease_out_in_sin(analog(dune_control, 1.0, -1.0, 0.0, 1.0))
		var dune2 := shape2 * ease_out_in_sin(analog(dune_control, -1.0, 1.0, 0.0, 1.0))
		height += dune_mask * (700.0 * dune1 + 700.0 * dune2)
	return height


static func ease_in_sin(value: float) -> float:
	var t := clampf(1.0 - value, 0.0, 1.0)
	return 1.0 - sin(t * PI * 0.5)


static func ease_out_in_sin(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return sin(t * PI * 0.5) * sin(t * PI * 0.5)


func _veles_height(p: Vector3) -> float:
	# PlanetVeles.h constants. Deliberately kept short until this grammar is calibrated against
	# a Veles screenshot; it is still much closer than the generic Sol noise stack.
	var base := _voronoi_base(p, 0.25, 0.5, 0.25)
	var plate_cracks := _fractal(10, p, 1.0, 10.0, 2.0, 10)
	plate_cracks = analog(absf(0.5 - plate_cracks), 0.0, 0.025, 1.0, 0.25)
	var plate_mask := _fractal(10, p, 1.0, 1.0, 2.0, 10) * analog(p.x, -0.9, 0.0, 0.3, 2.0)
	var plateau := analog(plate_mask, 0.4, 0.41, 0.0, 1.0) - plate_cracks
	var mountain_mask := analog(plate_mask, 0.375, 0.45, 0.0, 1.0)
	var mountains := analog(_fractal(0, p, 1.0, 1.0, 2.0, 9), 0.4, 0.7, 0.0, 1.0)
	mountains = analog(mountain_mask * mountains, 0.0, 0.5, 0.0, 1.0)
	mountains = mountains * mountains
	plateau = ease_out_in_sin2(plateau)
	mountains = analog(mountains, 0.0, 0.5, 0.0, 1.0)
	base = lerpf(base, 0.0, plateau)
	base = lerpf(base, 0.0, mountains)
	var volcano := pow(analog(base, 0.875, 0.995, 0.0, 1.0), 3.0)
	base = ease_out_in_sin2(analog(base, 0.4, 0.7, 0.3, 1.0))
	mountains = lerpf(mountains, 0.0, _holes(0.0, Vector4(0.275, 0.375, 0.375, 0.55)))
	var height := 0.0
	height += mountains * (20000.0 * _fractal(0, p, 0.5, 500.0, 2.0, 12))
	height += plateau * (15000.0 + 5000.0 * _fractal(0, p, 0.5, 300.0, 2.0, 10))
	height += (base * 8000.0 + volcano * 5000.0) * _fractal(0, p, 0.5, 500.0, 2.0, 12)
	height += volcano * 30000.0
	return height


func _morena_height(_p: Vector3) -> float:
	# Placeholder is explicitly temporary; Morena's cracked-plate grammar is the next port.
	return 0.0


func _asteroid_height(p: Vector3) -> float:
	# PlanetAsteroid.h: radius offset plus additive mountains, enough to break the sphere.
	var mountains := analog(_fractal(10, p, 0.2, 1.0, 2.0, 3), 0.2, 1.0, 0.0, 1.0)
	return -profile.radius * 0.35 + 250.0 * mountains * _fractal(0, p, 0.5, 2.5, 2.0, 10)


func height(direction: Vector3) -> float:
	var unit := direction.normalized()
	return height_xyz(unit.x, unit.y, unit.z)
