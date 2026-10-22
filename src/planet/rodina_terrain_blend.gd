class_name RodinaTerrainBlend
extends RefCounted
## RodinaTerrain.fx's surface colour at one point: the world's terrain features (RodinaTerrainSets) composited in order,
## each gated by altitude, latitude, slope and the four planet feature masks (GetTerrainBlend, lines 40-75), each coloured
## lerp(planetColor, DiffuseColor, ColorBlendGround) (lines 202-204), painter-style (lines 192-298): the first feature takes its
## blend of the surface, later ones fill what is left, and nothing renormalises the remainder, so uncovered surface is dark.
## What is NOT here: the four albedo texture tiers per feature and the two planet-scale texture layers (they add deviations
## around each feature's own mean colour, so the colours below are the average look), the eye-altitude colour blend
## (ColorBlendSpace; this is the ground value) and the camera-distance widening of the gates (fadeMult is 1).
## Pure and thread-safe. Result is display-space and unclamped, like the shader's `diffuse`.

## Offsets so the altitude and latitude noises are different slices of the same noise.
const ALTITUDE_NOISE_OFFSET := Vector3(17.3, 5.1, 91.7)
## The slope band's target values (see terrain_blend).
const NORMAL_TARGET_LOW := 1.0
const NORMAL_TARGET_HIGH := 0.0
const LATITUDE_NOISE_OFFSET := Vector3(-43.9, 61.2, 7.7)


## grammar: TerrainProfile.Grammar; feature: the clamped feature texel (base, plateau, mountains, holes); height: metres above
## the planet radius; direction: unit vector from the planet centre (y is the pole axis); slope_cos: dot(direction, surface
## normal) (1 = flat); world: planet-frame position in metres (for the altitude/latitude noises).
static func color(grammar: int, feature: Vector4, height: float, direction: Vector3, slope_cos: float, world: Vector3) -> Color:
	var plain := RodinaPlanets.feature_color(grammar, feature)
	var terrains := RodinaTerrainSets.features_for(grammar)
	if terrains.is_empty():
		return plain
	var scales := RodinaTerrainSets.noise_scales_for(grammar)
	# PerlinMap sampled triplanar, minus 0.5: here one Perlin value scaled to about +-0.5.
	var altitude_noise := 0.5 * RodinaNoise.perlin(world.x / scales.x + ALTITUDE_NOISE_OFFSET.x, world.y / scales.x + ALTITUDE_NOISE_OFFSET.y, world.z / scales.x + ALTITUDE_NOISE_OFFSET.z)
	var latitude_noise := 0.5 * RodinaNoise.perlin(world.x / scales.y + LATITUDE_NOISE_OFFSET.x, world.y / scales.y + LATITUDE_NOISE_OFFSET.y, world.z / scales.y + LATITUDE_NOISE_OFFSET.z)
	var latitude := asin(clampf(absf(direction.y), 0.0, 1.0))
	var slope_angle := acos(clampf(slope_cos, -1.0, 1.0))
	var remaining := 1.0
	var sum := Color(0.0, 0.0, 0.0, 1.0)
	for terrain in terrains:
		var blend := terrain_blend(terrain, feature, height, latitude, slope_angle, altitude_noise, latitude_noise)
		if blend <= 0.0:
			continue
		var diffuse: Color = terrain["diffuse"]
		var mix_amount: float = terrain["blend_ground"]
		var weight := blend * remaining
		sum.r += lerpf(plain.r, diffuse.r, mix_amount) * weight
		sum.g += lerpf(plain.g, diffuse.g, mix_amount) * weight
		sum.b += lerpf(plain.b, diffuse.b, mix_amount) * weight
		remaining -= weight
		if remaining <= 0.0:
			break
	return sum


## GetTerrainBlend with fadeMult = 1: altitude x latitude x slope x the four feature-mask bands, each in 0..1.
static func terrain_blend(terrain: Dictionary, feature: Vector4, height: float, latitude: float, slope_angle: float, altitude_noise: float, latitude_noise: float) -> float:
	var height_adjust: float = altitude_noise * float(terrain["height_noise"])
	var height_edge: float = float(terrain["height_edge"]) + height_adjust
	var height_fade: float = terrain["height_fade"]
	var altitude_blend := RodinaPlanets.ratio(height, height_edge - height_fade, height_edge + height_fade)
	if altitude_blend <= 0.0:
		return 0.0
	var latitude_adjust := deg_to_rad(float(terrain["latitude_noise"])) * latitude_noise
	var latitude_edge := deg_to_rad(float(terrain["latitude_edge"])) + latitude_adjust
	var latitude_fade := deg_to_rad(float(terrain["latitude_fade"]))
	var latitude_blend := RodinaPlanets.ratio(latitude, latitude_edge - latitude_fade, latitude_edge + latitude_fade)
	if latitude_blend <= 0.0:
		return 0.0
	var normal_edge := float(terrain["normal_edge"])
	var normal_fade := float(terrain["normal_fade"])
	# NormalTargetLow/High are not in the recovered data (the engine supplies them). 1 -> 0 is the reading that fits the authored
	# values: a positive fade means "present on slopes below the edge" (so 90 degrees = everywhere) and a negative fade means
	# "present on slopes above it" (Morena's CliffWall, Perun's MountainSide). The reference doc guessed 0 -> 1, which switches
	# every 90-degree feature off on flat ground and makes CliffWall a floor colour.
	var normal_blend := RodinaPlanets.analogue(slope_angle, deg_to_rad(normal_edge - normal_fade), deg_to_rad(normal_edge + normal_fade), NORMAL_TARGET_LOW, NORMAL_TARGET_HIGH)
	if normal_blend <= 0.0:
		return 0.0
	var blend := altitude_blend * latitude_blend * normal_blend
	var edges: Vector4 = terrain["features_edge"]
	var fades: Vector4 = terrain["features_fade"]
	var used: Array = terrain["features_used"]
	for channel in 4:
		if used[channel]:
			blend *= RodinaPlanets.ratio(feature[channel], edges[channel] - fades[channel], edges[channel] + fades[channel])
			if blend <= 0.0:
				return 0.0
	return blend
