class_name PlanetLook
extends RefCounted
## Everything visual about one world under one visual style (VisualStyle): terrain colouring, terrain detail texture,
## sky, haze, lights and atmosphere rim. Pure presentation: nothing here may change terrain height, collision or saves.
## Built once per style switch and then only read (chunk meshing reads it on worker threads), so never mutate one
## after handing it out.

var family: StringName = &"sol"

## Terrain colouring. Empty `features` = the original Sol rule (ChunkMesher._color_for on the TerrainProfile palette).
## Otherwise an ordered list of features in the manner of Rodina's terrain blending (research rendering_notes §3.3):
## each feature is gated by altitude AND latitude AND slope AND a noise mask (a product, not an average), and features
## are composited first-match-wins: each one takes its gate's share of the coverage that is left. `base_color` fills
## whatever coverage remains. Colours are linear (they become vertex colours).
var features: Array[Dictionary] = []
var base_color := Color(0.5, 0.5, 0.5)
## Ground hue seen from orbit; the terrain shader leans toward it as the viewer climbs (orbit_mix_* below).
var orbit_color := Color(0.5, 0.5, 0.5)
var orbit_mix_max := 0.0
## Viewer altitude band (metres above ground) over which the terrain leans from its ground colours to orbit_color.
var orbit_mix_from := 3000.0
var orbit_mix_to := 60000.0

## Terrain detail texture (data/shaders/terrain_detail.gdshader). Sol: 4 / 6 / 29 m tiles, full contrast, 80-250 m fade.
var detail_flat_tile := 4.0
var detail_steep_tile := 6.0
var detail_far_tile := 29.0
var detail_contrast := 1.0
var detail_fade_start := 80.0
var detail_fade_end := 250.0
var triplanar_sharpness := 4.0
## A common multiple of the three tile sizes: chunk texture offsets wrap at it, so the detail lines up across chunk borders.
var detail_tile_period := 348.0

## Day sky (linear colours). gradient_* reshape the zenith/horizon blend: t = pow(clamp(dir.y * scale + bias), power).
var sky_zenith := Color(0.15, 0.32, 0.65)
var sky_horizon := Color(0.55, 0.7, 0.9)
var gradient_scale := 0.5
var gradient_bias := 0.5
var gradient_power := 1.0
## Sol's soft sun glow (pow(sun_dot, 64) x gain); 0 in the Rodina profile, which draws a disc and a halo instead.
var legacy_sun_glow := 0.8
var legacy_sun_glow_color := Color(1.0, 0.9, 0.7)
## Rodina-style sun: a hard disc, a squared halo that widens as the sun nears the horizon, a sunset tint on the
## sun-facing horizon (technique: research rendering_notes §4.3; all values are Sol's own).
var sun_disc_gain := 0.0
var sun_halo_gain := 0.0
var sun_halo_width := 0.12   # radians, sun high
var sunset_halo_width := 0.45 # radians, sun at the horizon
var sunset_color := Color(1.0, 0.5, 0.2)
## Star disc and halo colours in the sky (Rodina: the atmosphere's filter colours) and the disc's angular radius.
## A negative red means "use sun_color" (the default, so the Sol look is unchanged).
var sun_disc_color := Color(-1.0, -1.0, -1.0)
var sun_halo_color := Color(-1.0, -1.0, -1.0)
var sun_disc_radius := 0.0095
var sunset_gain := 0.0

## Haze: Godot distance fog. Density is scaled by daylight and thins with altitude (SpaceEnvironment).
var fog_color := Color(0.62, 0.75, 0.92)
var fog_density := 3.0e-5
## Sol thins the haze away between 2 and 30 km altitude. Rodina's haze follows the distance through the air instead
## (research rendering_notes §4.2), so far terrain stays hazy from altitude too: thinning off, lower density.
var fog_thins_with_altitude := true
## Godot fog_aerial_perspective: 0 = flat fog colour, 1 = fog takes the sky's colour toward the horizon.
var fog_aerial_perspective := 0.0

## Lights. back_* is a shadowless fill from the side away from the sun (Rodina's "backside" term, rendering_notes §6.1).
var sun_color := Color.WHITE
var sun_energy := 1.25
## Rodina's day/night terminator (TerminatorBegin/End, EGDataPlanets.lua): sunlight is full while the sun's elevation
## cosine is above terminator_begin and gone below terminator_end. Off (the Sol look) unless terminator_enabled.
var terminator_enabled := false
var terminator_begin := 0.2
var terminator_end := -0.5
var back_color := Color(0.0, 0.0, 0.0)
var back_energy := 0.0
var ambient_space := Color(0.12, 0.14, 0.2)
var ambient_day := Color(0.45, 0.55, 0.75)
var ambient_energy_space := 0.6
var ambient_energy_day := 0.55

## Glowing rim of the atmosphere seen from space, and the colour of the far-away impostor sphere.
var rim_color := Color(0.35, 0.6, 1.0)
var rim_power := 6.0 ## limb sharpness (lower = wider glow)
## Rodina's atmosphere model (rodina_atmosphere.gdshaderinc) for sky and shell: shader parameter name -> value.
## Empty = off (the Sol look and airless worlds keep the original sky and rim).
var rodina_atmosphere := {}
var rim_haze := 0.0 ## atmosphere colour laid over the lit disc from space
var impostor_color := Color(0.5, 0.5, 0.5)

var _mask_noise: FastNoiseLite


## Terrain colour at one vertex. height: metres above the reference radius; steepness: 1 - cos(slope);
## latitude: |sin(latitude)|; world: position in the planet frame (for the noise masks).
func surface_color(profile: TerrainProfile, height: float, steepness: float, latitude: float, world: Vector3) -> Color:
	if features.is_empty():
		return ChunkMesher._color_for(profile, height, steepness, latitude)
	var coverage := 1.0
	var red := 0.0
	var green := 0.0
	var blue := 0.0
	for feature in features:
		var gate := _band(height, feature.get("height_min", -1.0e9), feature.get("height_max", 1.0e9), feature.get("height_fade", 300.0)) \
			* _band(latitude, feature.get("latitude_min", -1.0), feature.get("latitude_max", 2.0), feature.get("latitude_fade", 0.03)) \
			* _band(steepness, feature.get("slope_min", -1.0), feature.get("slope_max", 2.0), feature.get("slope_fade", 0.02))
		if feature.has("mask_scale") and gate > 0.0:
			var mask := mask_value(world, feature["mask_scale"], feature.get("mask_seed", 0))
			gate *= smoothstep(feature.get("mask_min", 0.0) - feature.get("mask_fade", 0.1), feature.get("mask_min", 0.0) + feature.get("mask_fade", 0.1), mask)
		var take := gate * coverage
		if take <= 0.0:
			continue
		var color: Color = feature["color"]
		red += color.r * take
		green += color.g * take
		blue += color.b * take
		coverage -= take
		if coverage <= 0.001:
			break
	return Color(red + base_color.r * coverage, green + base_color.g * coverage, blue + base_color.b * coverage)


## A smooth noise in -1..1 sampled at the planet-frame position divided by `scale_metres`.
func mask_value(world: Vector3, scale_metres: float, seed_offset: int) -> float:
	if _mask_noise == null:
		_mask_noise = FastNoiseLite.new()
		_mask_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_mask_noise.frequency = 1.0
		_mask_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_mask_noise.fractal_octaves = 3
	var offset := float(seed_offset) * 101.7
	return _mask_noise.get_noise_3d(world.x / scale_metres + offset, world.y / scale_metres, world.z / scale_metres - offset)


## 0 = ground colours, up to orbit_mix_max = orbit colour, by viewer altitude above ground.
func orbit_mix_at(altitude_metres: float) -> float:
	return orbit_mix_max * smoothstep(orbit_mix_from, orbit_mix_to, altitude_metres)


## The noise used by mask_value is created up front so worker threads never race to create it.
func prepare() -> PlanetLook:
	mask_value(Vector3.ZERO, 1.0, 0)
	return self


static func _band(value: float, low: float, high: float, fade: float) -> float:
	return smoothstep(low - fade, low + fade, value) * (1.0 - smoothstep(high - fade, high + fade, value))
