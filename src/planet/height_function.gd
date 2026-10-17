class_name HeightFunction
extends RefCounted
## The single source of truth for terrain height: the mesh, ground contact and walking all
## ask this. Height is metres above profile.radius for a point given as a direction from the
## planet centre (passed as three doubles so nothing is rounded to 32 bits before the noise).
##
## Precision note: FastNoiseLite takes 32-bit coordinates. Macro noise uses unit-sphere
## directions (fine). Metre-scale detail uses position / wavelength, which is rounded to about
## 0.4 m at 6,000 km; with the small detail amplitudes that is a few centimetres of height error.

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
	height += profile.hill_amplitude * _hills.get_noise_3d(dx * to_hills, dy * to_hills, dz * to_hills)
	height += profile.rough_amplitude * _rough.get_noise_3d(dx * to_rough, dy * to_rough, dz * to_rough)
	return height


func height(direction: Vector3) -> float:
	var unit := direction.normalized()
	return height_xyz(unit.x, unit.y, unit.z)
