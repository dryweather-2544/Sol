class_name RodinaSkyBake
extends RefCounted
## Rodina's skybox generator, ported: Shaders/PlanetSkybox.fx (PSPlanetColors) with the "RodinaSkybox" PlanetDef
## GenerationVars from Scripts/DataRender/EGDataSkybox.lua (later assignments win, as in Lua, so the SKINNY MODE block is
## live). Rodina bakes it once into a 1024 px cube map and RodinaSkybox.fx composites it; tools/bake_rodina_skybox.gd does the
## same here and data/shaders/space_sky.gdshader does the composite.
##
## Channels (as PlanetSkybox.fx writes them): R = Milky Way (x random grain .9..1), G = dust (subtracted by the composite),
## B = stars (+ the Milky-Way-masked second star layer).
## Perlin: RodinaNoise (an exact _perlin.h port). Not recoverable: the 1000 engine-supplied Voronoi points (position + strength)
## that GetStar reads, so they are 1000 seeded uniform points on the unit sphere with uniform strengths: same count, same
## falloff (linear within 0.002 of a point, nine shifted lookups per layer), different positions.
## Axes: Rodina is z-up, Sol y-up; the bake evaluates Rodina's formulas at (x, -z, y) of the world direction.
## Output goes to assets/generated/rodina_skybox/ (git-ignored: derived from Rodina's data, never publish it).

const FACE_NAMES := ["px", "nx", "py", "ny", "pz", "nz"]
const STAR_COUNT := 1000                # VoronoiGetNumCells()
const STAR_MAX_DISTANCE := 0.002        # [150].x
const STAR_SEED := 32165413127          # the PlanetDef's Seed, for want of the engine's point table
## GetStar's nine lookups: the point itself, then eight shifted-and-renormalised copies of it.
const STAR_OFFSETS := [
	Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.3, 0.2), Vector3(0.0, 0.4, -0.2), Vector3(0.3, -0.2, 0.0),
	Vector3(-0.3, 0.5, 0.0), Vector3(-0.1, 0.2, 0.2), Vector3(0.2, -0.4, -0.2), Vector3(0.15, -0.2, -0.5),
	Vector3(-0.2, 0.5, 0.2)]
const SPLAT_STEPS := 6
const SPLAT_STEP := 0.0006
const NOISE_MIN_MASK := 0.001

# GenerationVars (EGDataSkybox.lua, final values).
const SEEDS := Vector4(12.0, 109.0, 218.0, 0.0)                 # [1]
const MILKY_PERLIN := Vector4(0.5, 2.0, 2.0, 15.0)              # [2]
const MILKY_ANALOGUE := Vector4(0.1, 0.6, 0.0, 1.0)             # [3]
const MILKY_PLANE := Vector4(0.0, 0.0, 1.0, 0.0)                # [4]
const MILKY_GAUSSIAN := Vector4(1.0, 0.3, 1.0, 0.0)             # [5]
const MILKY_CENTER := Vector3(1.0, 0.0, 0.0)                    # [6]
const MILKY_CENTER_SHAPE := Vector4(1.0, 0.75, 1.2, 0.9)        # [7]
const MILKY_CENTER_BRIGHT := Vector4(1.0, -1.0, 1.25, 0.35)     # [8]
const DUST_PERLIN_1 := Vector4(0.5, 15.5, 2.0, 12.0)            # [9]
const DUST_RANGE_1 := Vector4(-1.0, -1.0, 0.0, 1.0)             # [10]
const DUST_PERLIN_2 := Vector4(0.5, 10.5, 2.0, 12.0)            # [12]
const DUST_RANGE_2 := Vector4(0.2, 0.6, 0.0, 1.0)               # [13]
const MILKY_PERLIN_2 := Vector4(0.8, 6.0, 2.0, 12.0)            # [14]
const MILKY_RANGE_2 := Vector4(0.0, 0.525, 0.0, 1.0)            # [15]
const COORD_MULT := Vector3(1.0, 1.0, 1.5)                      # [16]
const DUST_SHAPE := Vector4(1.0, 0.75, 1.15, 1.0)               # [17]
const DUST_BRIGHT := Vector4(1.0, -0.25, 0.8, 0.15)             # [18]
const DUST_GAUSSIAN := Vector4(1.0, 0.175, 1.0, 0.0)            # [19]
const DUST_DISTORT_PERLIN := Vector4(1.0, 1.0, 2.0, 2.0)        # [20]
const DUST_DISTORT_AMOUNT := 0.05                               # [21].x
const MILKY_RANDOM_RANGE := Vector4(0.0, 1.0, 0.9, 1.0)         # [204]

var size := 1024
var points := PackedVector3Array()
var strengths := PackedFloat32Array()
var stars := PackedFloat32Array()        # 6 faces x size x size
var milky_stars := PackedFloat32Array()
var rows: Array = []
var _mutex := Mutex.new()
var _rows_done := 0


func _init(face_size: int = 1024) -> void:
	size = face_size
	var rng := RandomNumberGenerator.new()
	rng.seed = STAR_SEED
	for index in STAR_COUNT:
		var z := rng.randf_range(-1.0, 1.0)
		var phi := rng.randf() * TAU
		var ring := sqrt(1.0 - z * z)
		points.append(Vector3(ring * cos(phi), ring * sin(phi), z))
		strengths.append(rng.randf())
	stars.resize(6 * size * size)
	milky_stars.resize(6 * size * size)


# --- Rodina utility.h --------------------------------------------------------------------------

## Analogue(value, fromLow, fromHigh, toLow, toHigh): HLSL saturate((v - a) / (b - a)) then lerp, so a zero-width range
## (EGDataSkybox [10] = {-1, -1, 0, 1}) divides by zero to +inf and saturates to 1.
static func analogue(value: float, from_low: float, from_high: float, to_low: float, to_high: float) -> float:
	var ratio := 0.0
	if from_high == from_low:
		ratio = 1.0 if value > from_low else 0.0
	else:
		ratio = clampf((value - from_low) / (from_high - from_low), 0.0, 1.0)
	return lerpf(to_low, to_high, ratio)


static func analogue4(value: float, params: Vector4) -> float:
	return analogue(value, params.x, params.y, params.z, params.w)


## _utility.h Gaussian2.
static func gaussian2(x: float, exponent: float, bell_height: float, bell_offset: float, bell_width: float) -> float:
	var power := absf(pow(x - bell_offset, exponent)) / (2.0 * bell_width * bell_width)
	return bell_height * pow(2.71828, -power)


## _utility.h random(float3): the per-pixel grain on the Milky Way.
static func hlsl_random(p: Vector3) -> float:
	var r := Vector3(23.1406926327792690, 2.6651441426902251, cos(12.24434343))
	var divisor := 0.0000007 + 256.0 * p.dot(r)
	if divisor == 0.0:
		return 0.0
	var value := cos(fmod(123456789.0, divisor))
	return value - floorf(value)


# --- cube map layout (OpenGL face order and orientation, as Godot's Cubemap) ---------------------

static func texel_direction(face: int, x: int, y: int, face_size: int) -> Vector3:
	var sc := 2.0 * (float(x) + 0.5) / float(face_size) - 1.0
	var tc := 2.0 * (float(y) + 0.5) / float(face_size) - 1.0
	match face:
		0: return Vector3(1.0, -tc, -sc).normalized()
		1: return Vector3(-1.0, -tc, sc).normalized()
		2: return Vector3(sc, 1.0, tc).normalized()
		3: return Vector3(sc, -1.0, -tc).normalized()
		4: return Vector3(sc, -tc, 1.0).normalized()
	return Vector3(-sc, -tc, -1.0).normalized()


## The texel a direction falls in, as Vector3i(face, x, y).
static func direction_texel(direction: Vector3, face_size: int) -> Vector3i:
	var ax := absf(direction.x)
	var ay := absf(direction.y)
	var az := absf(direction.z)
	var face := 0
	var sc := 0.0
	var tc := 0.0
	var ma := 1.0
	if ax >= ay and ax >= az:
		ma = ax
		if direction.x > 0.0:
			face = 0
			sc = -direction.z
			tc = -direction.y
		else:
			face = 1
			sc = direction.z
			tc = -direction.y
	elif ay >= az:
		ma = ay
		if direction.y > 0.0:
			face = 2
			sc = direction.x
			tc = direction.z
		else:
			face = 3
			sc = direction.x
			tc = -direction.z
	else:
		ma = az
		if direction.z > 0.0:
			face = 4
			sc = direction.x
			tc = -direction.y
		else:
			face = 5
			sc = -direction.x
			tc = -direction.y
	var s := 0.5 * (sc / ma + 1.0)
	var t := 0.5 * (tc / ma + 1.0)
	return Vector3i(face, clampi(floori(s * face_size), 0, face_size - 1), clampi(floori(t * face_size), 0, face_size - 1))


## Sol world direction (y up) to Rodina's sphere coordinate (z up), and back.
static func to_rodina(direction: Vector3) -> Vector3:
	return Vector3(direction.x, -direction.z, direction.y)


static func from_rodina(rodina: Vector3) -> Vector3:
	return Vector3(rodina.x, rodina.z, -rodina.y)


## PlanetSkybox.fx's four star layers read the point set through axis swizzles: p, p.yzx, -p.xzy, -p.zxy.
static func swizzle(group: int, p: Vector3) -> Vector3:
	match group:
		0: return p
		1: return Vector3(p.y, p.z, p.x)
		2: return Vector3(-p.x, -p.z, -p.y)
	return Vector3(-p.z, -p.x, -p.y)


static func unswizzle(group: int, q: Vector3) -> Vector3:
	match group:
		0: return q
		1: return Vector3(q.z, q.x, q.y)
		2: return Vector3(-q.x, -q.z, -q.y)
	return Vector3(-q.y, -q.z, -q.x)


# --- stars -------------------------------------------------------------------------------------

## GetStar for every point: each of the 4 swizzled layers x 9 lookups, splatted from the point side. A lookup at world
## texel p reads q = normalize(swizzle(p) + offset) and is VoronoiStrength(q): strength x (1 - distance to the nearest point / 0.002).
func bake_stars() -> void:
	for group in 4:
		for offset_index in STAR_OFFSETS.size():
			for point_index in points.size():
				splat(group, offset_index, point_index)


## One point's disc as seen through one lookup: find where q lands on the sphere, walk the texels around it and add the
## linear falloff (x strength, x 0.25 for the second layers) to the star or Milky-Way-star layer.
func splat(group: int, offset_index: int, point_index: int) -> void:
	var offset: Vector3 = STAR_OFFSETS[offset_index]
	var point := points[point_index]
	var b := point.dot(offset)
	var t := b + sqrt(maxf(b * b - (offset.length_squared() - 1.0), 0.0))
	var center := from_rodina(unswizzle(group, (point * t - offset).normalized()))
	var axis_u := center.cross(Vector3.UP if absf(center.y) < 0.9 else Vector3.RIGHT).normalized()
	var axis_v := center.cross(axis_u)
	var weight := 1.0 if group % 2 == 0 else 0.25
	var strength := strengths[point_index] * weight
	var seen := {}
	for i in range(-SPLAT_STEPS, SPLAT_STEPS + 1):
		for j in range(-SPLAT_STEPS, SPLAT_STEPS + 1):
			var direction := (center + (axis_u * float(i) + axis_v * float(j)) * SPLAT_STEP).normalized()
			var texel := direction_texel(direction, size)
			var index := (texel.x * size + texel.z) * size + texel.y
			if seen.has(index):
				continue
			seen[index] = true
			var rodina := to_rodina(texel_direction(texel.x, texel.y, texel.z, size))
			var distance := (swizzle(group, rodina) + offset).normalized().distance_to(point)
			if distance >= STAR_MAX_DISTANCE:
				continue
			var value := strength * (1.0 - distance / STAR_MAX_DISTANCE)
			if group < 2:
				stars[index] += value
			else:
				milky_stars[index] += value


# --- Milky Way and dust (per texel) ------------------------------------------------------------

## PSPlanetColors for one texel: Vector3(milky way, dust, stars).
func texel_channels(face: int, x: int, y: int) -> Vector3:
	var index := (face * size + y) * size + x
	var p := to_rodina(texel_direction(face, x, y, size))
	var plane_normal := Vector3(MILKY_PLANE.x, MILKY_PLANE.y, MILKY_PLANE.z)
	var plane_distance := absf(plane_normal.dot(p) + MILKY_PLANE.w) / plane_normal.length()
	var center_dot := p.dot(MILKY_CENTER.normalized())
	var center_shape := analogue4(center_dot, MILKY_CENTER_SHAPE)
	var center_brightness := analogue4(center_dot, MILKY_CENTER_BRIGHT)
	var milky_mask := center_brightness * gaussian2(plane_distance, MILKY_GAUSSIAN.z, MILKY_GAUSSIAN.x * center_shape, 0.0, MILKY_GAUSSIAN.y * center_shape)
	var milky_way := 0.0
	if milky_mask > NOISE_MIN_MASK:
		var way1 := analogue4(RodinaNoise.fractal(SEEDS.x, p, MILKY_PERLIN.x, MILKY_PERLIN.y, MILKY_PERLIN.z, int(MILKY_PERLIN.w)), MILKY_ANALOGUE)
		var way2 := analogue4(RodinaNoise.fractal(SEEDS.x, p, MILKY_PERLIN_2.x, MILKY_PERLIN_2.y, MILKY_PERLIN_2.z, int(MILKY_PERLIN_2.w)), MILKY_RANGE_2)
		milky_way = way1 * way2 * milky_mask * analogue4(hlsl_random(p), MILKY_RANDOM_RANGE)
	var dust_shape := analogue4(center_dot, DUST_SHAPE)
	var dust_brightness := analogue4(center_dot, DUST_BRIGHT)
	var dust_mask := dust_brightness * gaussian2(plane_distance, DUST_GAUSSIAN.z, DUST_GAUSSIAN.x * dust_shape, 0.0, DUST_GAUSSIAN.y * dust_shape)
	var dust := 0.0
	if dust_mask > NOISE_MIN_MASK:
		var adjusted := p * COORD_MULT
		var dust1 := analogue4(RodinaNoise.fractal(SEEDS.y, adjusted, DUST_PERLIN_1.x, DUST_PERLIN_1.y, DUST_PERLIN_1.z, int(DUST_PERLIN_1.w)), DUST_RANGE_1)
		var derivative := RodinaNoise.fractal_derivative(SEEDS.w, adjusted, DUST_DISTORT_PERLIN.x, DUST_DISTORT_PERLIN.y, DUST_DISTORT_PERLIN.z, int(DUST_DISTORT_PERLIN.w))
		var distortion := adjusted - Vector3(derivative.x, derivative.y, derivative.z)
		var dust_coord := (adjusted + distortion * DUST_DISTORT_AMOUNT).normalized()
		var dust2 := analogue4(RodinaNoise.fractal(SEEDS.z, dust_coord, DUST_PERLIN_2.x, DUST_PERLIN_2.y, DUST_PERLIN_2.z, int(DUST_PERLIN_2.w)), DUST_RANGE_2)
		dust = dust1 * dust_mask * dust2
	return Vector3(milky_way, dust, stars[index] + milky_mask * milky_stars[index])


## One row of one face as RGB8 bytes (the group task body: index = face * size + row).
func bake_row(row_index: int) -> void:
	var face := floori(float(row_index) / float(size))
	var y := row_index - face * size
	var bytes := PackedByteArray()
	bytes.resize(size * 3)
	for x in size:
		var channels := texel_channels(face, x, y)
		bytes[x * 3] = clampi(roundi(channels.x * 255.0), 0, 255)
		bytes[x * 3 + 1] = clampi(roundi(channels.y * 255.0), 0, 255)
		bytes[x * 3 + 2] = clampi(roundi(channels.z * 255.0), 0, 255)
	_mutex.lock()
	rows[row_index] = bytes
	_rows_done += 1
	var done := _rows_done
	_mutex.unlock()
	if done % 512 == 0:
		print("  skybox rows %d / %d" % [done, 6 * size])


## Bakes every face on the worker pool (call bake_stars first).
func bake_all() -> void:
	rows.resize(6 * size)
	_rows_done = 0
	var group := WorkerThreadPool.add_group_task(bake_row, 6 * size, -1, true, "Rodina skybox")
	WorkerThreadPool.wait_for_group_task_completion(group)


## Writes face_px.png ... face_nz.png into the directory (absolute path).
func save(directory: String) -> Error:
	DirAccess.make_dir_recursive_absolute(directory)
	for face in 6:
		var data := PackedByteArray()
		for y in size:
			data.append_array(rows[face * size + y])
		var image := Image.create_from_data(size, size, false, Image.FORMAT_RGB8, data)
		var error := image.save_png(directory.path_join("face_%s.png" % FACE_NAMES[face]))
		if error != OK:
			return error
	return OK
