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


func _init(terrain_profile: TerrainProfile) -> void:
	profile = terrain_profile
	_macro = _make_noise("macro", 6, FastNoiseLite.FRACTAL_FBM)
	_ridge = _make_noise("ridge", 4, FastNoiseLite.FRACTAL_NONE)
	_hills = _make_noise("hills", 3, FastNoiseLite.FRACTAL_FBM)
	_rough = _make_noise("rough", 2, FastNoiseLite.FRACTAL_FBM)


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
	var macro := _macro.get_noise_3d(dx * profile.macro_scale, dy * profile.macro_scale, dz * profile.macro_scale)
	var ridged := 1.0 - absf(_ridge.get_noise_3d(dx * profile.mountain_scale, dy * profile.mountain_scale, dz * profile.mountain_scale))
	var mountain_mask := smoothstep(0.05, 0.5, macro)
	var height := profile.macro_amplitude * macro + profile.mountain_amplitude * ridged * ridged * mountain_mask
	var to_hills := profile.radius / profile.hill_wavelength
	var to_rough := profile.radius / profile.rough_wavelength
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


func height(direction: Vector3) -> float:
	var unit := direction.normalized()
	return height_xyz(unit.x, unit.y, unit.z)
