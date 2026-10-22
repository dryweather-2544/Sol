class_name RodinaPlanets
extends RefCounted
## Rodina's planet height functions (Shaders/PlanetPerun.h, PlanetJarilo.h, PlanetVeles.h, PlanetMorena.h,
## PlanetAsteroid.h) with the GenerationVars from Scripts/DataGameplay/EGDataPlanets.lua, in 64-bit on the CPU.
## data/shaders/rodina_heights.glsl is the same code in float32 on the GPU, as Rodina runs it (its planets are
## drawn from height textures the GPU renders from these functions). The CPU copy answers the few ground queries
## per frame (ship contact, landing, points of interest); the GPU builds every terrain chunk.
##
## Noise is RodinaNoise (_perlin.h). The one thing not recoverable is the engine-supplied VoronoiPoints table
## (1000 points); a seeded uniform set on the unit sphere replaces it, shared by every planet.
## Index numbers in the comments are the PlanetGenConstants slots from the Lua tables.

const VORONOI_COUNT := 1000
const VORONOI_SEED := 5017
const GRID := 8 ## cells per axis over [-1, 1]^3 for the CPU nearest-point search

static var _mutex := Mutex.new()
static var _ready := false
static var _points := PackedVector3Array()
static var _cells := {} ## cell index -> PackedInt32Array of point indices


## The 1000 Voronoi points, built once (thread-safe).
static func points() -> PackedVector3Array:
	_ensure()
	return _points


## The points as a flat float32 array of vec4 (xyz, 0) for the GPU buffer.
static func points_as_floats() -> PackedFloat32Array:
	_ensure()
	var floats := PackedFloat32Array()
	floats.resize(VORONOI_COUNT * 4)
	for index in VORONOI_COUNT:
		floats[index * 4] = _points[index].x
		floats[index * 4 + 1] = _points[index].y
		floats[index * 4 + 2] = _points[index].z
	return floats


static func _ensure() -> void:
	if _ready:
		return
	_mutex.lock()
	if not _ready:
		var rng := SeedRng.new(VORONOI_SEED)
		_points.resize(VORONOI_COUNT)
		for index in VORONOI_COUNT:
			var z := rng.next_float() * 2.0 - 1.0
			var angle := rng.next_float() * TAU
			var ring := sqrt(maxf(0.0, 1.0 - z * z))
			_points[index] = Vector3(ring * cos(angle), ring * sin(angle), z)
		for index in VORONOI_COUNT:
			var key := _cell_key(_cell_of(_points[index]))
			var bucket: PackedInt32Array = _cells.get(key, PackedInt32Array())
			bucket.append(index)
			_cells[key] = bucket
		_ready = true
	_mutex.unlock()


static func _cell_of(p: Vector3) -> Vector3i:
	return Vector3i(clampi(int(floorf((p.x + 1.0) * GRID * 0.5)), 0, GRID - 1), clampi(int(floorf((p.y + 1.0) * GRID * 0.5)), 0, GRID - 1), clampi(int(floorf((p.z + 1.0) * GRID * 0.5)), 0, GRID - 1))


static func _cell_key(cell: Vector3i) -> int:
	return (cell.x * GRID + cell.y) * GRID + cell.z


# --- HLSL helpers (Shaders/_utility.h) -------------------------------------------------------

## GetRatioClamp: saturate((v - lo) / (hi - lo)). A zero-width range divides by zero: +inf saturates to 1,
## -inf and NaN to 0.
static func ratio(value: float, from_low: float, from_high: float) -> float:
	if from_high == from_low:
		return 1.0 if value > from_low else 0.0
	return clampf((value - from_low) / (from_high - from_low), 0.0, 1.0)


static func analogue(value: float, from_low: float, from_high: float, to_low: float, to_high: float) -> float:
	return to_low + (to_high - to_low) * ratio(value, from_low, from_high)


static func ease_out_in_sin2(t: float) -> float:
	return analogue(sin(analogue(t, 0.0, 1.0, -PI * 0.5, PI * 0.5)), -1.0, 1.0, 0.0, 1.0)


static func ease_in_sin(t: float) -> float:
	return 1.0 - sin(clampf(1.0 - t, 0.0, 1.0) * PI * 0.5)


static func ease_out_in_sin(t: float) -> float:
	var s := sin(clampf(t, 0.0, 1.0) * PI * 0.5)
	return s * s


## HLSL smoothstep(a, b, x), including reversed and zero-width edges.
static func hsmooth(edge_a: float, edge_b: float, x: float) -> float:
	var t := ratio(x, edge_a, edge_b)
	return t * t * (3.0 - 2.0 * t)


static func _fp(seed: float, p: Vector3, mult: float, octave_base: float, octave_change: float, octaves: int) -> float:
	return RodinaNoise.fractal(seed, p, mult, octave_base, octave_change, octaves)


static func _sp(seed: float, p: Vector3, mult: float, octave_base: float, octave_change: float, octaves: int) -> float:
	return RodinaNoise.special(seed, p, mult, octave_base, octave_change, octaves)


## FractalPerlinDerivative(...).xyz
static func _dv(seed: float, p: Vector3, mult: float, octave_base: float, octave_change: float, octaves: int) -> Vector3:
	var d := RodinaNoise.fractal_derivative(seed, p, mult, octave_base, octave_change, octaves)
	return Vector3(d.x, d.y, d.z)


## The holes remap shared by Perun, Jarilo and Asteroid (GetPlanetFeatures).
static func _holes(value: float, edges: Vector4) -> float:
	if value <= edges.y:
		return hsmooth(edges.x, edges.y, value)
	if value <= edges.z:
		return 1.0
	if value <= edges.w:
		return hsmooth(edges.w, edges.z, value)
	return 0.0


# --- _voronoi.h -----------------------------------------------------------------------------

## (nearest, second nearest) distance to the 1000 points: GetPoint(p, -1) and GetPoint(p, d1).
static func nearest_two(p: Vector3) -> Vector2:
	_ensure()
	var cell := _cell_of(p)
	var best1 := INF
	var best2 := INF
	for cx in range(maxi(cell.x - 1, 0), mini(cell.x + 2, GRID)):
		for cy in range(maxi(cell.y - 1, 0), mini(cell.y + 2, GRID)):
			for cz in range(maxi(cell.z - 1, 0), mini(cell.z + 2, GRID)):
				var bucket: PackedInt32Array = _cells.get(_cell_key(Vector3i(cx, cy, cz)), PackedInt32Array())
				for index in bucket:
					var distance_squared := p.distance_squared_to(_points[index])
					if distance_squared < best1:
						best2 = best1
						best1 = distance_squared
					elif distance_squared < best2 and distance_squared > best1:
						best2 = distance_squared
	# The 3x3x3 block covers a quarter of a unit in every direction; anything it could have missed is farther.
	var reach := 2.0 / GRID
	if best2 > reach * reach or best1 == INF:
		best1 = INF
		best2 = INF
		for index in VORONOI_COUNT:
			best1 = minf(best1, p.distance_squared_to(_points[index]))
		for index in VORONOI_COUNT:
			var distance_squared := p.distance_squared_to(_points[index])
			if distance_squared > best1 and distance_squared < best2:
				best2 = distance_squared
	return Vector2(sqrt(best1), sqrt(best2))


static func voronoi(p: Vector3, max_distance: float) -> float:
	return analogue(nearest_two(p).x, 0.0, max_distance, 1.0, 0.0)


static func voronoi2(p: Vector3, factor1: float, factor2: float, max_distance: float) -> float:
	var distances := nearest_two(p)
	return analogue(factor1 * distances.x + factor2 * distances.y, 0.0, max_distance, 1.0, 0.0)


## Height in metres above the planet radius. grammar is a TerrainProfile.Grammar value; radius only
## scales the asteroid amplitudes. Returns 0 for any other grammar.
static func height(grammar: int, p: Vector3, radius: float) -> float:
	match grammar:
		TerrainProfile.Grammar.PERUN:
			return perun(p)
		TerrainProfile.Grammar.JARILO:
			return jarilo(p)
		TerrainProfile.Grammar.VELES:
			return veles(p)
		TerrainProfile.Grammar.MORENA:
			return morena(p)
		TerrainProfile.Grammar.ASTEROID:
			return asteroid(p, asteroid_scale(radius))
	return 0.0


## Sol's tweak to Rodina's Asteroid mountains so a 15 km rock reads as craggy, not just smooth and rolling: Rodina's own values
## are an edge of 0.5 (mountains on only a small part of the rock) and an amplitude of 500 m. Mirrored in rodina_heights.glsl
## and HeightFunction._asteroid_height; the colour feature uses the same edge so colour and height agree.
const ASTEROID_MOUNTAIN_EDGE := 0.1
const ASTEROID_MOUNTAIN_AMPLITUDE := 1400.0
## Sol-only sharp creases laid over the mountains (not in Rodina): ridged noise of about 400 m wavelength. The noise runs
## 0..1 around 0.47, so the crease is where it crosses 0.47 and the ridge stands up to 0.2 * this amplitude.
const ASTEROID_CRAG_AMPLITUDE := 1000.0


## Rodina's Asteroid terrain is authored for rocks of about 10 km radius (DwarfMoon 10 km, AsteroidLarge 10 km), with up to
## a few km of relief, so a 15 km rock keeps the full authored relief. Only much smaller rocks are shrunk to match.
static func asteroid_scale(radius: float) -> float:
	return clampf(radius / 15000.0, 0.1, 1.0)


## PlanetPerun.h with Perun's GenerationVars (EGDataPlanets.lua:286-324).
static func perun(p: Vector3) -> float:
	var mask_distort := p - _dv(10.0, p, 1.0, 1.0, 2.0, 2)         # seeds1.x, [1]
	var distort := p - _dv(0.0, p, 1.0, 1.0, 2.0, 9)               # seeds2.x, [2]
	var mask_coord := (p + mask_distort * 0.05 + distort * 0.005).normalized()  # [4]
	var base_coords := (p + distort * 0.02).normalized()           # [5]
	var mountain_distort := mask_coord - _dv(10.0, mask_coord, 1.0, 2.0, 2.0, 2)  # seeds1.y, [3]
	var mountain_coord1 := (mask_coord + mountain_distort * 0.2).normalized()    # [6].x
	var mountain_coords := (p + distort * 0.001).normalized()      # [6].y
	var base := voronoi2(base_coords, 0.5, 0.5, 0.25)              # [15]
	var holes := _holes(_fp(0.0, mountain_coords, 0.5, 128.0, 2.0, 4), Vector4(0.275, 0.375, 0.375, 0.55))  # seeds2.y, [9], [10]
	var plateau := analogue(_fp(10.0, mask_coord, 0.56, 3.0, 2.0, 12), 0.5, 0.675, 0.0, 1.0)  # seeds1.z, [7], [8]
	var mountain_mask := analogue(_fp(10.0, mountain_coord1, 0.6, 3.0, 2.0, 5), 0.45, 0.6, 0.0, 1.0)  # seeds1.w, [11], [12]
	var mountains := analogue(_fp(0.0, mountain_coords, 1.0, 1.0, 2.0, 9), 0.4, 0.7, 0.0, 1.0)       # seeds2.z, [13], [14]
	mountains = mountain_mask * mountains
	# GetPlanetHeight
	mountains = analogue(mountains, 0.0, 0.5, 0.0, 1.0)            # [100]
	var roughness := analogue(mountains, 0.0, 0.9, 0.3, 0.5)       # [101]
	mountains = mountains * mountains
	plateau = ease_out_in_sin2(analogue(plateau, 0.1, 0.425, 0.0, 1.0))  # [105]
	base = ease_out_in_sin2(analogue(base, 0.4, 0.7, 0.3, 1.0))    # [110]
	base = lerpf(base, 0.0, plateau)
	base = lerpf(base, 0.0, mountains)
	mountains = lerpf(mountains, 0.0, holes)
	var height := 0.0
	# A term whose weight is zero adds nothing, so it is not evaluated.
	if mountains > 0.0:
		height += mountains * (0.0 + 20000.0 * _fp(0.0, p, roughness, 500.0, 2.0, 12))   # [102], [103]
	if plateau > 0.0:
		height += plateau * (12000.0 + 5000.0 * _fp(0.0, p, 0.5, 300.0, 2.0, 10))        # [106], [107]
	if base > 0.0:
		height += base * (0.0 + 500.0 * _fp(0.0, p, 0.35, 3750.0, 2.0, 7))               # [111], [112]
	return height


## PlanetJarilo.h with Jarilo's GenerationVars (EGDataPlanets.lua:567-611; [14] is listed twice, the later wins).
static func jarilo(p: Vector3) -> float:
	var map_distort := p - _dv(10.0, p, 1.0, 1.0, 2.0, 2)          # seeds1.x, [1]
	var feature_distort := p - _dv(0.0, p, 1.0, 1.0, 2.0, 9)       # seeds2.x, [2]
	var base_coords := (p + map_distort * 0.06 + feature_distort * 0.02).normalized()  # [5]
	var base := voronoi2(base_coords, 0.5, 0.5, 0.2)               # [15]
	var plateau_coord := (p + map_distort * 0.05 + feature_distort * 0.0).normalized()  # [4]
	var plateau := analogue(_fp(20.0, plateau_coord, 0.5, 2.0, 2.0, 16), 0.4, 0.8, 0.0, 1.0)  # seeds1.z, [7], [8]
	var mountain_distort := plateau_coord - _dv(10.0, plateau_coord, 1.0, 2.0, 2.0, 2)  # seeds1.y, [3]
	var mountain_coord1 := (plateau_coord + mountain_distort * 0.0).normalized()        # [6].x
	var mountain_coords := (p + feature_distort * 0.001).normalized()                   # [6].y
	var mountain_mask := analogue(_fp(20.0, mountain_coord1, 0.5, 2.0, 2.0, 5), 0.1, 0.4, 0.0, 1.0)  # seeds1.w, [11], [12]
	var mountains := analogue(_fp(0.0, mountain_coords, 1.0, 1.0, 2.0, 9), 0.45, 0.8, 0.0, 1.0)      # seeds2.z, [13], [14]
	var holes := _holes(_fp(0.0, p, 0.5, 2500.0, 2.0, 4), Vector4(0.0, 0.0, 0.375, 0.5))             # seeds2.y, [9], [10]
	mountains = mountain_mask * mountains
	# GetPlanetHeight
	var dunes := base
	mountains = analogue(mountains, 0.0, 0.5, 0.0, 1.0)            # [100]
	var roughness := analogue(mountains, 0.0, 0.9, 0.3, 0.5)       # [101]
	mountains = mountains * mountains
	plateau = ease_out_in_sin2(analogue(plateau, 0.05, 0.1, 0.0, 1.0))  # [105]
	dunes = ease_out_in_sin2(analogue(dunes, 0.4, 0.7, 0.0, 1.0))       # [110]
	dunes = analogue(plateau, 0.0, 0.15, dunes, 0.0)               # [113]
	dunes = analogue(mountains, 0.05, 0.1, dunes, 0.0)             # [114]
	var height := 0.0
	if mountains > 0.0:
		height += mountains * (0.0 + 50000.0 * _sp(0.0, p, roughness, 500.0, 2.0, 12))  # [102], [103]
	if plateau > 0.0:
		var plateau_hills := _sp(153.0, p, 0.5, 4000.0, 2.0, 9)    # [106]
		plateau_hills = lerpf(plateau_hills, 0.45, holes)          # [108]
		height += plateau * (2000.0 + 2000.0 * plateau_hills)      # [107]
	if dunes > 0.0:
		var dune_distort := _dv(12.0, p, 0.5, 100.0, 2.0, 3)
		var dune_coord := (p + dune_distort * 0.001).normalized()
		var dune_control := sin(dune_coord.dot(Vector3(1, -1, -1)) * 1000.0)      # [111].x
		var x1 := fposmod(dune_coord.dot(Vector3(1, 1, 1)) * 800.0, 1.0)          # [111].y
		var x2 := fposmod(dune_coord.dot(Vector3(1, 1, 1)) * 800.0 + 0.5, 1.0)    # [111].z
		var shape1 := ease_in_sin(absf(analogue(x1, 0.0, 1.0, -1.0, 1.0)))
		var shape2 := ease_in_sin(absf(analogue(x2, 0.0, 1.0, -1.0, 1.0)))
		var dune1 := shape1 * ease_out_in_sin(analogue(dune_control, 1.0, -1.0, 0.0, 1.0))
		var dune2 := shape2 * ease_out_in_sin(analogue(dune_control, -1.0, 1.0, 0.0, 1.0))
		height += dunes * (700.0 * dune1 + 700.0 * dune2)          # [112]
	return height


## PlanetVeles.h. Its domain warps are commented out in the shader, so every coordinate is p.
static func veles(p: Vector3) -> float:
	var base := voronoi(p, 0.25)
	var half_mask := analogue(p.x, -0.9, 0.0, 0.3, 2.0)
	var holes := _fp(0.0, p, 0.5, 128.0, 2.0, 4)
	if holes <= 0.375:
		holes = hsmooth(0.275, 0.375, holes)
	else:
		holes = hsmooth(0.55, 0.375, holes)
	var plate_cracks := analogue(absf(0.5 - _fp(10.0, p, 0.56, 10.0, 2.0, 10)), 0.0, 0.025, 1.0, 0.25)
	var plate_mask := _fp(10.0, p, 0.6, 1.0, 2.0, 10) * half_mask
	var plate := analogue(plate_mask, 0.4, 0.41, 0.0, 1.0)
	var mountain_mask := analogue(plate_mask, 0.375, 0.45, 0.0, 1.0)
	var mountains := analogue(_fp(0.0, p, 1.0, 1.0, 2.0, 9), 0.4, 0.7, 0.0, 1.0)
	mountains = mountain_mask * mountains
	var plateau := plate - plate_cracks
	# GetPlanetHeight
	plateau = ease_out_in_sin2(plateau)
	mountains = analogue(mountains, 0.0, 0.5, 0.0, 1.0)
	var roughness := analogue(mountains, 0.0, 0.9, 0.3, 0.5)
	mountains = mountains * mountains
	base = lerpf(base, 0.0, plateau)
	base = lerpf(base, 0.0, mountains)
	var volcano := pow(analogue(base, 0.875, 0.995, 0.0, 1.0), 3.0)
	if base > 0.9955:
		volcano = analogue(base, 0.9955, 0.998, 1.0, 0.45)
	volcano = hsmooth(0.0, 1.0, volcano)
	base = ease_out_in_sin2(analogue(base, 0.4, 0.7, 0.3, 1.0))
	mountains = lerpf(mountains, 0.0, holes)
	var height := 0.0
	if mountains > 0.0:
		height += mountains * (20000.0 * _fp(0.0, p, roughness, 500.0, 2.0, 12))
	if plateau > 0.0:
		height += plateau * (15000.0 + 5000.0 * _fp(0.0, p, 0.5, 300.0, 2.0, 10))
	var lowland := base * 8000.0 + volcano * 5000.0
	if lowland != 0.0:
		height += lowland * _fp(0.0, p, 0.5, 500.0, 2.0, 12)
	height += volcano * 30000.0
	return height


## Sol's scale on Morena's big plate cracks (the long trenches along the plate boundaries, 11 km deep and dark). On Sol's
## 1700 km Selene they read from orbit as one thin black line around the world, so they are off; the small cracks, hills and
## dunes stay. 1.0 = Rodina's own.
const MORENA_BIG_CRACK_SCALE := 0.0


## PlanetMorena.h: a hand-written cracked-plate grammar, not a GenerationVars world.
static func morena(p: Vector3) -> float:
	var crack_distort_big := _dv(12.0, p, 0.5, 0.5, 2.0, 8)
	var crack_distort := _dv(10.0, p, 0.5, 2.0, 2.0, 8)
	var crack_coord := (p + crack_distort_big * 0.05 + crack_distort * 0.075).normalized()
	var plate_perlin := _fp(10.0, p, 0.6, 60.0, 2.0, 7)
	var big_mask_1 := plate_perlin - cos(maxf(minf(30.0 * (0.9 * crack_coord.z + 0.3 * crack_coord.y), 8.0 * 3.14159), -8.0 * 3.14159))
	var big_mask_2 := plate_perlin - cos(maxf(minf(30.0 * (1.0 * crack_coord.z + 0.0 * crack_coord.y), 8.0 * 3.14159), -8.0 * 3.14159))
	var plate_cracks := minf(absf(big_mask_1), absf(big_mask_2))
	var small_cracks := _fp(0.0, p, 0.56, 25.0, 2.0, 10)
	small_cracks = minf(absf(0.46 - small_cracks), minf(absf(0.5 - small_cracks), absf(0.54 - small_cracks)))
	small_cracks = hsmooth(0.0, 1.0, analogue(small_cracks, 0.003, 0.010, 1.0, 0.0))
	var hills := 0.0
	var dunes := 0.0
	if big_mask_1 < 0.0 or big_mask_2 < 0.0:
		hills = analogue(plate_cracks, 0.35, 1.0, 0.0, 1.0)
		small_cracks *= hsmooth(0.0, 1.0, analogue(plate_cracks, 0.3, 0.5, 1.0, 0.0))
	elif big_mask_1 > 0.0 and big_mask_2 > 0.0:
		dunes = analogue(plate_cracks, 0.4, 1.0, 0.0, 1.0)
		small_cracks *= hsmooth(0.0, 1.0, analogue(plate_cracks, 0.3, 0.35, 1.0, 0.0))
	# GetPlanetHeight
	var big_cracks := ease_out_in_sin(analogue(plate_cracks, 0.05, 0.15, 1.0, 0.0)) * 0.75 * MORENA_BIG_CRACK_SCALE
	var small := small_cracks * 0.25
	var dune_mask := analogue(dunes, 0.0, 0.15, 0.0, 1.0)
	var cracks := maxf(big_cracks, small)
	var plateau := lerpf(1.0, 0.0, dune_mask)
	var mountains := lerpf(hills, 0.0, cracks)
	var height := 14000.0
	height += plateau * (-1000.0 + 2000.0 * _fp(0.0, p, 0.48, 300.0, 2.0, 6))
	height += cracks * -15000.0
	if mountains > 0.0:
		height += mountains * (30000.0 * _fp(0.0, p, 0.5, 500.0, 2.0, 12))
	if dune_mask > 0.0:
		var dune_distort := _dv(12.0, p, 0.5, 100.0, 2.0, 3)
		var dune_coord := (p + dune_distort * 0.001).normalized()
		var control := sin(dune_coord.dot(Vector3(1, -1, -1)) * 1000.0)
		var x1 := fposmod(dune_coord.dot(Vector3(1, 1, 1)) * 400.0, 1.0)
		var x2 := fposmod(dune_coord.dot(Vector3(1, 1, 1)) * 400.0 + 0.5, 1.0)
		var shape1 := ease_in_sin(absf(analogue(x1, 0.0, 1.0, -1.0, 1.0)))
		var shape2 := ease_in_sin(absf(analogue(x2, 0.0, 1.0, -1.0, 1.0)))
		var dune1 := shape1 * ease_out_in_sin(analogue(control, 1.0, -1.0, 0.0, 1.0))
		var dune2 := shape2 * ease_out_in_sin(analogue(control, -1.0, 1.0, 0.0, 1.0))
		height += dune_mask * (800.0 * dune1 + 800.0 * dune2)
	return height


## PlanetAsteroid.h (the uncommented GetPlanetFeatures) with the Asteroid GenerationVars block
## (EGDataPlanets.lua:1252+, later duplicates winning as in Lua). The engine's per-rock Randomize()
## seeds are not reproducible, so the block's own seeds (20, 10, 113, 20) are used. `scale` shrinks the
## authored amplitudes for tiny bodies.
static func asteroid(p: Vector3, scale: float) -> float:
	# [4] and [6] are zero, so the plateau and mountain coordinates are p itself. The base term is
	# base * (0 + 0 * noise) because [112] is zero, and holes are always 0 because [10] is (1,1,1,1).
	var plateau := analogue(_fp(113.0, p, 0.5, 0.5, 2.0, 12), 0.0, 1.0, 0.0, 1.0)  # seeds1.z, [7], [8]
	var mountain_mask := analogue(_fp(20.0, p, 0.5, 0.5, 2.0, 3), -1.0, -1.0, 0.0, 1.0)  # seeds1.w, [11], [12]
	var mountains := analogue(_fp(0.0, p, 0.5, 1.0, 2.0, 3), ASTEROID_MOUNTAIN_EDGE, 1.0, 0.0, 1.0)  # seeds2.z, [13], [14]
	mountains = mountain_mask * mountains
	mountains = analogue(mountains, 0.0, 0.3, 0.0, 1.0)            # [100]
	var roughness := analogue(mountains, 0.0, 0.9, 0.3, 0.5)       # [101]
	mountains = mountains * mountains
	plateau = analogue(plateau, 0.0, 1.0, 0.0, 1.0)                # [105]
	var height := -1000.0                                          # [104]
	if mountains > 0.0:
		height += mountains * ASTEROID_MOUNTAIN_AMPLITUDE * _fp(0.0, p, roughness, 2.5, 2.0, 10)  # [102], [103]
		height += mountains * ASTEROID_CRAG_AMPLITUDE * (0.2 - absf(_fp(5.0, p, 0.55, 40.0, 2.0, 6) - 0.47))
	height += plateau * 3000.0                                              # [107]
	return height * scale


# --- Planet features and colours (PSPlanetColors + RodinaTerrain.fx:118-126) --------------------------------

## The four-channel feature texture Rodina's terrain material samples: (base, plateau, mountains, holes), as written by
## each Planet<Name>.fx PSPlanetColors (Morena packs its own channels). CPU mirror of GetPlanetFeatures: same coordinates,
## constants and ordering as the height functions above, so colour and height always agree. Returns Vector4.ZERO for LEGACY.
static func features(grammar: int, p: Vector3) -> Vector4:
	match grammar:
		TerrainProfile.Grammar.PERUN:
			return perun_features(p)
		TerrainProfile.Grammar.JARILO:
			return jarilo_features(p)
		TerrainProfile.Grammar.VELES:
			return veles_features(p)
		TerrainProfile.Grammar.MORENA:
			return morena_features(p)
		TerrainProfile.Grammar.ASTEROID:
			return asteroid_features(p)
	return Vector4.ZERO


## PlanetPerun.h GetPlanetFeatures (25-100) then PlanetPerun.fx: mountains = Analogue(mountains, .1, 1, 0, 1).
static func perun_features(p: Vector3) -> Vector4:
	var mask_distort := p - _dv(10.0, p, 1.0, 1.0, 2.0, 2)
	var distort := p - _dv(0.0, p, 1.0, 1.0, 2.0, 9)
	var mask_coord := (p + mask_distort * 0.05 + distort * 0.005).normalized()
	var base_coords := (p + distort * 0.02).normalized()
	var mountain_distort := mask_coord - _dv(10.0, mask_coord, 1.0, 2.0, 2.0, 2)
	var mountain_coord1 := (mask_coord + mountain_distort * 0.2).normalized()
	var mountain_coords := (p + distort * 0.001).normalized()
	var base := voronoi2(base_coords, 0.5, 0.5, 0.25)
	var holes := _holes(_fp(0.0, mountain_coords, 0.5, 128.0, 2.0, 4), Vector4(0.275, 0.375, 0.375, 0.55))
	var plateau := analogue(_fp(10.0, mask_coord, 0.56, 3.0, 2.0, 12), 0.5, 0.675, 0.0, 1.0)
	var mountain_mask := analogue(_fp(10.0, mountain_coord1, 0.6, 3.0, 2.0, 5), 0.45, 0.6, 0.0, 1.0)
	var mountains := analogue(_fp(0.0, mountain_coords, 1.0, 1.0, 2.0, 9), 0.4, 0.7, 0.0, 1.0)
	return Vector4(base, plateau, analogue(mountain_mask * mountains, 0.1, 1.0, 0.0, 1.0), holes)


## PlanetJarilo.h GetPlanetFeatures (25-97) then PlanetJarilo.fx.
static func jarilo_features(p: Vector3) -> Vector4:
	var map_distort := p - _dv(10.0, p, 1.0, 1.0, 2.0, 2)
	var feature_distort := p - _dv(0.0, p, 1.0, 1.0, 2.0, 9)
	var base_coords := (p + map_distort * 0.06 + feature_distort * 0.02).normalized()
	var base := voronoi2(base_coords, 0.5, 0.5, 0.2)
	var plateau_coord := (p + map_distort * 0.05).normalized()
	var plateau := analogue(_fp(20.0, plateau_coord, 0.5, 2.0, 2.0, 16), 0.4, 0.8, 0.0, 1.0)
	var mountain_coords := (p + feature_distort * 0.001).normalized()
	var mountain_mask := analogue(_fp(20.0, plateau_coord, 0.5, 2.0, 2.0, 5), 0.1, 0.4, 0.0, 1.0)
	var mountains := analogue(_fp(0.0, mountain_coords, 1.0, 1.0, 2.0, 9), 0.45, 0.8, 0.0, 1.0)
	var holes := _holes(_fp(0.0, p, 0.5, 2500.0, 2.0, 4), Vector4(0.0, 0.0, 0.375, 0.5))
	return Vector4(base, plateau, analogue(mountain_mask * mountains, 0.1, 1.0, 0.0, 1.0), holes)


## PlanetVeles.h GetPlanetFeatures (25-71; warps commented out, so every coordinate is p) then PlanetVeles.fx.
static func veles_features(p: Vector3) -> Vector4:
	var base := voronoi(p, 0.25)
	var half_mask := analogue(p.x, -0.9, 0.0, 0.3, 2.0)
	var holes := _fp(0.0, p, 0.5, 128.0, 2.0, 4)
	if holes <= 0.375:
		holes = hsmooth(0.275, 0.375, holes)
	else:
		holes = hsmooth(0.55, 0.375, holes)
	var plate_cracks := analogue(absf(0.5 - _fp(10.0, p, 0.56, 10.0, 2.0, 10)), 0.0, 0.025, 1.0, 0.25)
	var plate_mask := _fp(10.0, p, 0.6, 1.0, 2.0, 10) * half_mask
	var plate := analogue(plate_mask, 0.4, 0.41, 0.0, 1.0)
	var mountain_mask := analogue(plate_mask, 0.375, 0.45, 0.0, 1.0)
	var mountains := analogue(_fp(0.0, p, 1.0, 1.0, 2.0, 9), 0.4, 0.7, 0.0, 1.0)
	return Vector4(base, plate - plate_cracks, analogue(mountain_mask * mountains, 0.1, 1.0, 0.0, 1.0), holes)


## PlanetMorena.h GetPlanetFeatures (25-89) then PlanetMorena.fx, which repacks them:
## (FractalPerlin(8, p, .5, 8, 2, 8), pow(Analogue(plateCracks, 0, .5, 1, 0), 1.5), hills, Analogue(dunes, 0, .75, 0, 1)).
static func morena_features(p: Vector3) -> Vector4:
	var crack_distort_big := _dv(12.0, p, 0.5, 0.5, 2.0, 8)
	var crack_distort := _dv(10.0, p, 0.5, 2.0, 2.0, 8)
	var crack_coord := (p + crack_distort_big * 0.05 + crack_distort * 0.075).normalized()
	var plate_perlin := _fp(10.0, p, 0.6, 60.0, 2.0, 7)
	var big_mask_1 := plate_perlin - cos(maxf(minf(30.0 * (0.9 * crack_coord.z + 0.3 * crack_coord.y), 8.0 * 3.14159), -8.0 * 3.14159))
	var big_mask_2 := plate_perlin - cos(maxf(minf(30.0 * (1.0 * crack_coord.z + 0.0 * crack_coord.y), 8.0 * 3.14159), -8.0 * 3.14159))
	var plate_cracks := minf(absf(big_mask_1), absf(big_mask_2))
	var small_cracks := _fp(0.0, p, 0.56, 25.0, 2.0, 10)
	small_cracks = minf(absf(0.46 - small_cracks), minf(absf(0.5 - small_cracks), absf(0.54 - small_cracks)))
	small_cracks = hsmooth(0.0, 1.0, analogue(small_cracks, 0.003, 0.010, 1.0, 0.0))
	var hills := 0.0
	var dunes := 0.0
	if big_mask_1 < 0.0 or big_mask_2 < 0.0:
		hills = analogue(plate_cracks, 0.35, 1.0, 0.0, 1.0)
		small_cracks *= hsmooth(0.0, 1.0, analogue(plate_cracks, 0.3, 0.5, 1.0, 0.0))
	elif big_mask_1 > 0.0 and big_mask_2 > 0.0:
		dunes = analogue(plate_cracks, 0.4, 1.0, 0.0, 1.0)
		small_cracks *= hsmooth(0.0, 1.0, analogue(plate_cracks, 0.3, 0.35, 1.0, 0.0))
	var big_cracks := pow(analogue(plate_cracks, 0.0, 0.5, 1.0, 0.0), 1.5) * MORENA_BIG_CRACK_SCALE
	return Vector4(_fp(8.0, p, 0.5, 8.0, 2.0, 8), big_cracks, hills, analogue(dunes, 0.0, 0.75, 0.0, 1.0))


## PlanetAsteroid.h GetPlanetFeatures (26-98) with the Asteroid GenerationVars (later duplicate keys win) then PlanetAsteroid.fx.
## The engine's per-rock Randomize seeds are not reproducible, so the block's own seeds (20, 10, 113, 20) are used.
static func asteroid_features(p: Vector3) -> Vector4:
	var map_distort := p - _dv(20.0, p, 1.0, 1.0, 2.0, 2)          # seeds1.x, [1]
	var feature_distort := p - _dv(0.0, p, 1.0, 1.0, 2.0, 9)       # seeds2.x, [2]
	var base_coords := (p + map_distort * 0.1 + feature_distort * 0.005).normalized()  # [5]
	var base := voronoi2(base_coords, 0.5, 0.5, 0.25)              # [15]
	var plateau := analogue(_fp(113.0, p, 0.5, 0.5, 2.0, 12), 0.0, 1.0, 0.0, 1.0)  # [4] = 0: plateau coord is p
	var mountain_mask := analogue(_fp(20.0, p, 0.5, 0.5, 2.0, 3), -1.0, -1.0, 0.0, 1.0)  # [6] = 0
	var mountains := analogue(_fp(0.0, p, 0.5, 1.0, 2.0, 3), ASTEROID_MOUNTAIN_EDGE, 1.0, 0.0, 1.0)
	var holes := _holes(_fp(0.0, p, 0.5, 128.0, 2.0, 4), Vector4(1.0, 1.0, 1.0, 1.0))  # [9], [10] = (1,1,1,1)
	return Vector4(base, plateau, analogue(mountain_mask * mountains, 0.1, 1.0, 0.0, 1.0), holes)


## Scripts/EGUtility.lua EGHueSaturateValue(h, s, v): high = v, low = v * (1 - s), six hue sectors. Deliberately unclamped:
## several Rodina colours use negative or above-one values (they subtract from, or brighten, the base colour).
static func hue_saturate_value(hue: float, saturation: float, value: float) -> Color:
	var high := value
	var low := value * (1.0 - saturation)
	var h := fposmod(hue, 360.0)
	if h < 60.0:
		return Color(high, analogue(h, 0.0, 60.0, low, high), low)
	if h < 120.0:
		return Color(analogue(h, 60.0, 120.0, high, low), high, low)
	if h < 180.0:
		return Color(low, high, analogue(h, 120.0, 180.0, low, high))
	if h < 240.0:
		return Color(low, analogue(h, 180.0, 240.0, high, low), high)
	if h < 300.0:
		return Color(analogue(h, 240.0, 300.0, low, high), low, high)
	return Color(high, low, analogue(h, 300.0, 360.0, high, low))


## EGDataPlanets.lua PlanetFeatureColor1a/1b/2/3/4 for a grammar's world. Perun 274-278, Jarilo 548-554 (a duplicated
## block: the later lines win), Veles 433-437, Morena 718-722, Asteroid 1246-1250. Empty for LEGACY.
static func feature_colors(grammar: int) -> Dictionary:
	match grammar:
		TerrainProfile.Grammar.PERUN:
			return {"c1a": Color(0.25, 0.2, 0.2), "c1b": Color(0.125, 0.1, 0.1), "c2": hue_saturate_value(1.0, 0.0, 0.25),
				"c3": hue_saturate_value(1.0, 0.0, 0.325), "c4": hue_saturate_value(1.0, 0.0, -0.002)}
		TerrainProfile.Grammar.JARILO:
			return {"c1a": hue_saturate_value(45.0, 0.5, 0.61), "c1b": hue_saturate_value(30.0, 0.5, 1.0), "c2": hue_saturate_value(0.0, 0.0, -0.8),
				"c3": hue_saturate_value(0.0, 0.0, -0.66), "c4": hue_saturate_value(0.0, 0.0, 0.0)}
		TerrainProfile.Grammar.VELES:
			return {"c1a": hue_saturate_value(27.0, 0.7, 0.2), "c1b": hue_saturate_value(27.0, 0.7, 0.1), "c2": hue_saturate_value(0.0, 0.0, 0.35),
				"c3": hue_saturate_value(0.0, 0.0, 0.3), "c4": hue_saturate_value(0.0, 0.0, -0.002)}
		TerrainProfile.Grammar.MORENA:
			return {"c1a": hue_saturate_value(230.0, 0.4, 1.2), "c1b": hue_saturate_value(230.0, 0.0, 1.2), "c2": hue_saturate_value(13.0, 1.0, -0.4),
				"c3": hue_saturate_value(0.0, 0.2, 0.25), "c4": hue_saturate_value(0.0, 0.0, 0.15)}
		TerrainProfile.Grammar.ASTEROID:
			return {"c1a": hue_saturate_value(45.0, 0.0, 0.0), "c1b": hue_saturate_value(30.0, 0.2, 0.3), "c2": hue_saturate_value(0.0, 0.0, 0.0),
				"c3": hue_saturate_value(180.0, 0.1, -0.5), "c4": hue_saturate_value(0.0, 0.0, 0.0)}
	return {}


## RodinaTerrain.fx:118-126, unclamped: lerp(1a, 1b, base) + plateau*2 + mountains*3 + holes*4. 1a is the colour at base = 0.
static func feature_color(grammar: int, feature: Vector4) -> Color:
	var colors := feature_colors(grammar)
	if colors.is_empty():
		return Color(0.5, 0.5, 0.5)
	var a: Color = colors["c1a"]
	var b: Color = colors["c1b"]
	var c2: Color = colors["c2"]
	var c3: Color = colors["c3"]
	var c4: Color = colors["c4"]
	return Color(
		lerpf(a.r, b.r, feature.x) + feature.y * c2.r + feature.z * c3.r + feature.w * c4.r,
		lerpf(a.g, b.g, feature.x) + feature.y * c2.g + feature.z * c3.g + feature.w * c4.g,
		lerpf(a.b, b.b, feature.x) + feature.y * c2.b + feature.z * c3.b + feature.w * c4.b)
