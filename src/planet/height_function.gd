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
	# Keyed by the formatted parameters (5 decimals). Fixed-parameter call sites go through
	# _slot_noise instead, which calls this once per slot; only call sites with a per-sample gain
	# (Perun/asteroid roughness) still pay for this lookup on every sample.
	var key := "%d/%.5f/%d/%.5f/%.5f/%s" % [seed_value, frequency, octaves, gain, lacunarity, str(cellular)]
	if _grammar_noises.has(key):
		return _grammar_noises[key]
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
	return noise


## N14 perf: each grammar call site passes a fixed slot so its FastNoiseLite is fetched by array
## index instead of a dictionary lookup. slot < 0 keeps the keyed lookup. Same noise object
## parameters and seed either way, so the height is bit-identical.
const SLOT_COUNT := 64
var _slot_noises: Array = []


func _slot_noise(slot: int, seed_value: int, frequency: float, octaves: int, gain: float, lacunarity: float, cellular := false) -> FastNoiseLite:
	if slot < 0:
		return _grammar_noise(seed_value, frequency, octaves, gain, lacunarity, cellular)
	if _slot_noises.is_empty():
		_slot_noises.resize(SLOT_COUNT * 2)
	var noise: FastNoiseLite = _slot_noises[slot]
	if noise == null:
		noise = _grammar_noise(seed_value, frequency, octaves, gain, lacunarity, cellular)
		_slot_noises[slot] = noise
	return noise


func _fractal(seed_value: int, p: Vector3, mult_change: float, octave_base: float, octave_change: float, octaves: int, slot := -1) -> float:
	var noise := _slot_noise(slot, seed_value, octave_base, octaves, mult_change, octave_change)
	return (noise.get_noise_3d(p.x, p.y, p.z) + 1.0) * 0.5


func _special(seed_value: int, p: Vector3, mult_change: float, octave_base: float, octave_change: float, octaves: int, slot := -1) -> float:
	# SpecialPerlin suppresses octaves where the derivative is large. A second fractal is a cheap
	# faithful-enough stand-in for the derivative weighting used by Rodina's terrain bake.
	var base := _fractal(seed_value, p, mult_change, octave_base, octave_change, octaves, slot)
	var rough := _fractal(seed_value + 7, p, mult_change, octave_base * 1.7, octave_change, maxi(2, octaves - 1), slot + SLOT_COUNT if slot >= 0 else -1)
	return clampf(base * (0.65 + 0.35 * (1.0 - rough)), 0.0, 1.0)


func _warp(seed_value: int, p: Vector3, mult_change: float, octave_base: float, octave_change: float, octaves: int, slot := -1) -> Vector3:
	# FractalPerlinDerivative(...).xyz in PlanetPerun/Jarilo. The finite difference is evaluated
	# in the same direction space and is normalized by the caller. One noise fetch serves all four
	# samples (the same noise _fractal would return for each).
	var e := 0.01
	var noise := _slot_noise(slot, seed_value, octave_base, octaves, mult_change, octave_change)
	var base := (noise.get_noise_3d(p.x, p.y, p.z) + 1.0) * 0.5
	var px := p + Vector3(e, 0, 0)
	var py := p + Vector3(0, e, 0)
	var pz := p + Vector3(0, 0, e)
	var dx := (noise.get_noise_3d(px.x, px.y, px.z) + 1.0) * 0.5 - base
	var dy := (noise.get_noise_3d(py.x, py.y, py.z) + 1.0) * 0.5 - base
	var dz := (noise.get_noise_3d(pz.x, pz.y, pz.z) + 1.0) * 0.5 - base
	return Vector3(dx, dy, dz) / e


func _voronoi_base(p: Vector3, scale: float, jitter: float, max_distance: float, slot := -1) -> float:
	# Voronoi2(VoronoiPoints, scale/jitter, maxDistance). Rodina's original points come from a GPU
	# constant buffer; FastNoiseLite's cellular field is the equivalent deterministic 3D cell field.
	var noise := _slot_noise(slot, 0, maxf(scale, 0.0001), 1, 1.0, 2.0, true)
	if noise.cellular_jitter != jitter:
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
	var mask_distort := _warp(10, p, 1.0, 1.0, 2.0, 2, 0)
	var distort := _warp(0, p, 1.0, 1.0, 2.0, 9, 1)
	var mask_coord := (p + mask_distort * 0.05 + distort * 0.005).normalized()
	var base_coords := (p + distort * 0.02).normalized()
	var mountain_distort := _warp(10, mask_coord, 1.0, 2.0, 2.0, 2, 2)
	var mountain_coord1 := (mask_coord + mountain_distort * 0.2).normalized()
	var mountain_coords := (p + distort * 0.001).normalized()
	var base := _voronoi_base(base_coords, 0.5, 0.5, 0.25, 3)
	var holes := _holes(_fractal(0, mountain_coords, 1.0, 128.0, 2.0, 4, 4), Vector4(0.275, 0.375, 0.375, 0.55))
	var plateau := analog(_fractal(10, mask_coord, 3.0, 0.56, 2.0, 12, 5), 0.5, 0.675, 0.0, 1.0)
	var mountain_perlin := _fractal(10, mountain_coord1, 3.0, 0.6, 2.0, 5, 6)
	var mountain_mask := analog(mountain_perlin, 0.45, 0.6, 0.0, 1.0)
	var mountains := analog(_fractal(0, mountain_coords, 1.0, 1.0, 2.0, 9, 7), 0.4, 0.7, 0.0, 1.0)
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
	height += plateau * (12000.0 + 5000.0 * _fractal(0, p, 0.5, 300.0, 2.0, 10, 9))
	height += base * (500.0 * _fractal(0, p, 0.35, 3750.0, 2.0, 7, 10))
	return height


## Rodina's Jarilo (PlanetJarilo.h GetPlanetFeatures/GetPlanetHeight) with its GenerationVars
## (EGDataPlanets.lua Jarilo; [14] is listed twice there, the later value wins as in Lua).
## Every formula and constant is the original's. The Perlin octaves of FractalPerlin and
## FractalPerlinDerivative come from FastNoiseLite's Perlin (same seed-as-coordinate-offset and
## per-octave coordinate derivative as _perlin.h; a different lattice hash; plain FractalPerlin uses
## FastNoiseLite's own FBM, which is the same sum normalised the same way), SpecialPerlin keeps the
## original's derivative damping, and Voronoi2's 1000 engine-supplied points are replaced by a
## cellular field calibrated to the same distance distribution (the points are not in the
## recovered files). Exact _perlin.h noise: RodinaNoise (too slow per vertex in GDScript).
const JARILO_VORONOI_FREQUENCY := 8.9 ## cells per unit: ~1000 cells over the unit sphere
const JARILO_VORONOI_JITTER := 2.0

func _jarilo_height(p: Vector3) -> float:
	# GetPlanetFeatures
	var map_distort := p - _r_deriv(10.0, p, 1.0, 1.0, 2.0, 2)        # seeds1.x, [1]
	var feature_distort := p - _r_deriv(0.0, p, 1.0, 1.0, 2.0, 9)     # seeds2.x, [2]
	var base_coords := (p + map_distort * 0.06 + feature_distort * 0.02).normalized()  # [5]
	var base := _r_voronoi2(base_coords, 0.5, 0.5, 0.2)                # [15]
	var plateau_coord := (p + map_distort * 0.05 + feature_distort * 0.0).normalized()  # [4]
	var plateau := analog(_fractal(20, plateau_coord, 0.5, 2.0, 2.0, 16, 46), 0.4, 0.8, 0.0, 1.0)  # seeds1.z, [7], [8]
	var mountain_distort := plateau_coord - _r_deriv(10.0, plateau_coord, 1.0, 2.0, 2.0, 2)  # seeds1.y, [3]
	var mountain_coord1 := (plateau_coord + mountain_distort * 0.0).normalized()  # [6].x
	var mountain_coords := (p + feature_distort * 0.001).normalized()             # [6].y
	var mountain_mask := analog(_fractal(21, mountain_coord1, 0.5, 2.0, 2.0, 5, 47), 0.1, 0.4, 0.0, 1.0)  # seeds1.w, [11], [12]
	var mountains := analog(_fractal(0, mountain_coords, 1.0, 1.0, 2.0, 9, 48), 0.45, 0.8, 0.0, 1.0)     # seeds2.z, [13], [14]
	var holes := _holes(_fractal(1, p, 0.5, 2500.0, 2.0, 4, 49), Vector4(0.0, 0.0, 0.375, 0.5))       # seeds2.y, [9], [10]
	mountains = mountain_mask * mountains
	# GetPlanetHeight
	var dunes := base
	mountains = analog(mountains, 0.0, 0.5, 0.0, 1.0)            # [100]
	var roughness := analog(mountains, 0.0, 0.9, 0.3, 0.5)       # [101]
	mountains = mountains * mountains
	plateau = ease_out_in_sin2(analog(plateau, 0.05, 0.1, 0.0, 1.0))  # [105]
	dunes = ease_out_in_sin2(analog(dunes, 0.4, 0.7, 0.0, 1.0))       # [110]
	dunes = analog(plateau, 0.0, 0.15, dunes, 0.0)               # [113]
	dunes = analog(mountains, 0.05, 0.1, dunes, 0.0)             # [114]
	var height := 0.0
	if mountains > 0.0: # mountains * (...) is 0 otherwise; skipping it changes nothing
		height += mountains * (0.0 + 50000.0 * _r_special(0.0, p, roughness, 500.0, 2.0, 12))  # [102], [103]
	if plateau > 0.0:
		var plateau_hills := _r_special(153.0, p, 0.5, 4000.0, 2.0, 9)  # [106]
		plateau_hills = lerpf(plateau_hills, 0.45, holes)                        # [108]
		height += plateau * (2000.0 + 2000.0 * plateau_hills)                    # [107]
	if dunes > 0.0:
		var dune_distort := _r_deriv(12.0, p, 0.5, 100.0, 2.0, 3)
		var dune_coord := (p + dune_distort * 0.001).normalized()
		var dune_control := sin(dune_coord.dot(Vector3(1, -1, -1)) * 1000.0)   # [111].x
		var x1 := fposmod(dune_coord.dot(Vector3(1, 1, 1)) * 800.0, 1.0)       # [111].y
		var x2 := fposmod(dune_coord.dot(Vector3(1, 1, 1)) * 800.0 + 0.5, 1.0) # [111].z
		var shape1 := ease_in_sin(absf(analog(x1, 0.0, 1.0, -1.0, 1.0)))
		var shape2 := ease_in_sin(absf(analog(x2, 0.0, 1.0, -1.0, 1.0)))
		var dune1 := shape1 * ease_out_in_sin(analog(dune_control, 1.0, -1.0, 0.0, 1.0))
		var dune2 := shape2 * ease_out_in_sin(analog(dune_control, -1.0, 1.0, 0.0, 1.0))
		height += dunes * (700.0 * dune1 + 700.0 * dune2)                       # [112]
	return height


# --- Rodina-shaped fractals over a single Perlin octave field (see _jarilo_height) ----------
var _r_noise: FastNoiseLite
var _r_cells: FastNoiseLite


func _r_octave_noise() -> FastNoiseLite:
	if _r_noise == null:
		_r_noise = FastNoiseLite.new()
		_r_noise.noise_type = FastNoiseLite.TYPE_PERLIN
		_r_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
		_r_noise.frequency = 1.0
		_r_noise.seed = SeedHash.derive(profile.terrain_seed, "rodina_perlin") & 0x7FFFFFFF
	return _r_noise


## _perlin.h FractalPerlin: octaves of Perlin at seed + p * frequency, normalised to 0..1.
func _r_fbm(seed: float, p: Vector3, mult_change: float, octave_base: float, octave_change: float, octaves: int) -> float:
	var noise_field := _r_octave_noise()
	var frequency := octave_base
	var noise := 0.0
	var range_sum := 0.0
	var mult := 1.0
	for octave in octaves:
		noise += mult * noise_field.get_noise_3d(seed + p.x * frequency, seed + p.y * frequency, seed + p.z * frequency)
		range_sum += mult
		frequency *= octave_change
		mult *= mult_change
	return clampf((noise + range_sum) / (2.0 * range_sum), 0.0, 1.0)


## _perlin.h FractalPerlinDerivative(...).xyz: sum over octaves of mult x dPerlin/dcoord (derivative
## in each octave's own coordinate, not chain-ruled by frequency, as in the original).
func _r_deriv(seed: float, p: Vector3, mult_change: float, octave_base: float, octave_change: float, octaves: int) -> Vector3:
	var noise_field := _r_octave_noise()
	var frequency := octave_base
	var total := Vector3.ZERO
	var mult := 1.0
	var e := 0.01
	for octave in octaves:
		var cx := seed + p.x * frequency
		var cy := seed + p.y * frequency
		var cz := seed + p.z * frequency
		var n0 := noise_field.get_noise_3d(cx, cy, cz)
		total += mult * Vector3(noise_field.get_noise_3d(cx + e, cy, cz) - n0, noise_field.get_noise_3d(cx, cy + e, cz) - n0, noise_field.get_noise_3d(cx, cy, cz + e) - n0) / e
		frequency *= octave_change
		mult *= mult_change
	return total


## _perlin.h SpecialPerlin: each octave divided by 1 + the running x/z derivative squared.
func _r_special(seed: float, p: Vector3, mult_change: float, octave_base: float, octave_change: float, octaves: int) -> float:
	var noise_field := _r_octave_noise()
	var frequency := octave_base
	var noise := 0.0
	var range_sum := 0.0
	var mult := 1.0
	var dx := 0.0
	var dz := 0.0
	var e := 0.01
	for octave in octaves:
		var cx := seed + p.x * frequency
		var cy := seed + p.y * frequency
		var cz := seed + p.z * frequency
		var n0 := noise_field.get_noise_3d(cx, cy, cz)
		dx += (noise_field.get_noise_3d(cx + e, cy, cz) - n0) / e
		dz += (noise_field.get_noise_3d(cx, cy, cz + e) - n0) / e
		noise += mult * n0 / (1.0 + dx * dx + dz * dz)
		range_sum += mult
		frequency *= octave_change
		mult *= mult_change
	return clampf((noise + range_sum) / (2.0 * range_sum), 0.0, 1.0)


## _voronoi.h Voronoi2(p, (f1, f2), max): (f1 x nearest + f2 x second-nearest distance) remapped
## 0..max -> 1..0. Cellular field with ~1000 cells over the unit sphere in place of the points.
func _r_voronoi2(p: Vector3, factor1: float, factor2: float, max_distance: float) -> float:
	if _r_cells == null:
		_r_cells = FastNoiseLite.new()
		_r_cells.noise_type = FastNoiseLite.TYPE_CELLULAR
		_r_cells.frequency = JARILO_VORONOI_FREQUENCY
		_r_cells.cellular_jitter = JARILO_VORONOI_JITTER
		_r_cells.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
		_r_cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_ADD
		_r_cells.seed = SeedHash.derive(profile.terrain_seed, "rodina_voronoi") & 0x7FFFFFFF
	# DISTANCE2_ADD returns (d1 + d2) / 2 - 1 in cell units; convert to unit-sphere distance.
	var cell_mean := (_r_cells.get_noise_3d(p.x, p.y, p.z) + 1.0) / JARILO_VORONOI_FREQUENCY
	# A jittered 3D cell grid has a narrower spread of (d1 + d2) / 2 than 1000 uniform random points
	# on the sphere; this linear map matches that distribution's 10th-90th percentiles (calibrated by
	# brute force over 1000 seeded points, 1500 queries: medians 0.067 vs 0.067).
	var mean_distance := maxf(0.0, -0.1016 + 2.456 * cell_mean)
	var distance := (factor1 + factor2) * mean_distance
	return analog(distance, 0.0, max_distance, 1.0, 0.0)


static func ease_in_sin(value: float) -> float:
	var t := clampf(1.0 - value, 0.0, 1.0)
	return 1.0 - sin(t * PI * 0.5)


static func ease_out_in_sin(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return sin(t * PI * 0.5) * sin(t * PI * 0.5)


func _veles_height(p: Vector3) -> float:
	# PlanetVeles.h constants. Deliberately kept short until this grammar is calibrated against
	# a Veles screenshot; it is still much closer than the generic Sol noise stack.
	var base := _voronoi_base(p, 0.25, 0.5, 0.25, 22)
	var plate_cracks := _fractal(10, p, 1.0, 10.0, 2.0, 10, 23)
	plate_cracks = analog(absf(0.5 - plate_cracks), 0.0, 0.025, 1.0, 0.25)
	var plate_mask := _fractal(10, p, 1.0, 1.0, 2.0, 10, 24) * analog(p.x, -0.9, 0.0, 0.3, 2.0)
	var plateau := analog(plate_mask, 0.4, 0.41, 0.0, 1.0) - plate_cracks
	var mountain_mask := analog(plate_mask, 0.375, 0.45, 0.0, 1.0)
	var mountains := analog(_fractal(0, p, 1.0, 1.0, 2.0, 9, 25), 0.4, 0.7, 0.0, 1.0)
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
	height += mountains * (20000.0 * _fractal(0, p, 0.5, 500.0, 2.0, 12, 26))
	height += plateau * (15000.0 + 5000.0 * _fractal(0, p, 0.5, 300.0, 2.0, 10, 27))
	height += (base * 8000.0 + volcano * 5000.0) * _fractal(0, p, 0.5, 500.0, 2.0, 12, 28)
	height += volcano * 30000.0
	return height


func _morena_height(p: Vector3) -> float:
	# PlanetMorena.h: a hand-written cracked-plate grammar, not a GenerationVars world.
	var crack_distort_big := _warp(12, p, 0.5, 0.5, 2.0, 8, 29)
	var crack_distort := _warp(10, p, 0.5, 2.0, 2.0, 8, 30)
	var crack_coord := (p + crack_distort_big * 0.05 + crack_distort * 0.075).normalized()
	var plate_perlin := _fractal(10, p, 0.6, 60.0, 2.0, 7, 31)
	var big_mask_1 := plate_perlin - cos(clampf(30.0 * (0.9 * crack_coord.z + 0.3 * crack_coord.y), -8.0 * PI, 8.0 * PI))
	var big_mask_2 := plate_perlin - cos(clampf(30.0 * crack_coord.z, -8.0 * PI, 8.0 * PI))
	var plate_cracks := minf(absf(big_mask_1), absf(big_mask_2))
	var small_cracks := _fractal(0, p, 0.56, 25.0, 2.0, 10, 32)
	small_cracks = minf(absf(0.46 - small_cracks), minf(absf(0.5 - small_cracks), absf(0.54 - small_cracks)))
	small_cracks = smoothstep(0.0, 1.0, analog(small_cracks, 0.003, 0.010, 1.0, 0.0))
	var hills := 0.0
	var dunes := 0.0
	if big_mask_1 < 0.0 or big_mask_2 < 0.0:
		hills = analog(plate_cracks, 0.35, 1.0, 0.0, 1.0)
		small_cracks *= smoothstep(0.0, 1.0, analog(plate_cracks, 0.3, 0.5, 1.0, 0.0))
	elif big_mask_1 > 0.0 and big_mask_2 > 0.0:
		dunes = analog(plate_cracks, 0.4, 1.0, 0.0, 1.0)
		small_cracks *= smoothstep(0.0, 1.0, analog(plate_cracks, 0.3, 0.35, 1.0, 0.0))
	var big_cracks := ease_out_in_sin(analog(plate_cracks, 0.05, 0.15, 1.0, 0.0)) * 0.75
	var cracks := maxf(big_cracks, small_cracks * 0.25)
	var plateau := lerpf(1.0, 0.0, analog(dunes, 0.0, 0.15, 0.0, 1.0))
	var mountains := lerpf(hills, 0.0, cracks)
	var height := 14000.0
	height += plateau * (-1000.0 + 2000.0 * _fractal(0, p, 0.48, 300.0, 2.0, 6, 33))
	height += cracks * -15000.0
	if mountains > 0.0:
		height += mountains * 30000.0 * _fractal(0, p, 0.5, 500.0, 2.0, 12, 34)
	var dune_mask := analog(dunes, 0.0, 0.15, 0.0, 1.0)
	if dune_mask > 0.0:
		var dune_distort := _warp(12, p, 0.5, 100.0, 2.0, 3, 35)
		var dune_coord := (p + dune_distort * 0.001).normalized()
		var control := sin(dune_coord.dot(Vector3(1, -1, -1)) * 1000.0)
		var x1 := fposmod(dune_coord.dot(Vector3(1, 1, 1)) * 400.0, 1.0)
		var x2 := fposmod(dune_coord.dot(Vector3(1, 1, 1)) * 400.0 + 0.5, 1.0)
		var shape1 := ease_in_sin(absf(analog(x1, 0.0, 1.0, -1.0, 1.0)))
		var shape2 := ease_in_sin(absf(analog(x2, 0.0, 1.0, -1.0, 1.0)))
		var dune1 := shape1 * ease_out_in_sin(analog(control, 1.0, -1.0, 0.0, 1.0))
		var dune2 := shape2 * ease_out_in_sin(analog(control, -1.0, 1.0, 0.0, 1.0))
		height += dune_mask * (800.0 * dune1 + 800.0 * dune2)
	return height


func _asteroid_height(p: Vector3) -> float:
	# PlanetAsteroid.h: the same base/plateau/mountain/hole feature grammar as Perun, with a flat
	# radius offset. The small Asteroid GenerationVars are used (plateau 3 km, mountains 0.5 km);
	# the amplitude is scaled down for a tiny body like Pebble and kept for Selene.
	var scale := clampf(profile.radius / 1700000.0, 0.1, 1.0)
	var map_distort := _warp(10, p, 1.0, 1.0, 2.0, 2, 36)
	var feature_distort := _warp(0, p, 1.0, 1.0, 2.0, 9, 37)
	var base_coords := (p + map_distort * 0.1 + feature_distort * 0.005).normalized()
	var plateau_coord := (p + map_distort * 0.0 + feature_distort * 0.0).normalized()
	var base := _voronoi_base(base_coords, 0.5, 0.5, 0.25, 38)
	var plateau := analog(_fractal(10, plateau_coord, 0.5, 2.0, 2.0, 9, 39), 0.0, 1.0, 0.0, 1.0)
	var mountain_perlin := _fractal(10, plateau_coord, 0.5, 1.0, 2.0, 3, 40)
	var mountain_mask := analog(mountain_perlin, 0.5, 1.0, 0.0, 1.0)
	var mountains := analog(_fractal(0, p, 0.5, 2.0, 2.0, 9, 41), 0.4, 1.0, 0.0, 1.0)
	var holes := _holes(_fractal(0, p, 0.5, 40.0, 2.0, 4, 42), Vector4(0.1, 0.39, 0.4, 0.65))
	mountains = analog(mountain_mask * mountains, 0.0, 0.35, 0.0, 1.0)
	var roughness := analog(mountains, 0.0, 0.9, 0.3, 0.5)
	mountains = mountains * mountains
	plateau = analog(plateau, 0.4, 0.8, 0.0, 1.0)
	base = ease_out_in_sin2(analog(base, 0.4, 0.7, 0.3, 1.0))
	base = lerpf(base, 0.0, plateau)
	base = lerpf(base, 0.0, mountains)
	mountains = lerpf(mountains, 0.0, holes)
	var height := -1000.0 * scale
	height += mountains * (250.0 + 150.0 * _fractal(0, p, roughness, 80.0, 2.0, 10)) * scale
	height += plateau * 3000.0 * scale
	height += base * 500.0 * _fractal(0, p, 0.35, 3750.0, 2.0, 7, 44) * scale
	return height


func height(direction: Vector3) -> float:
	var unit := direction.normalized()
	return height_xyz(unit.x, unit.y, unit.z)
