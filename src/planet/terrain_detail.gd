class_name TerrainDetail
extends RefCounted
## The detail shader for planet terrain (data/shaders/terrain_detail.gdshader, copied unchanged from Sol-Assets). It multiplies a
## neutral detail texture onto each chunk's vertex colour, blending a flat layer (regolith on airless worlds, dry soil where there
## is an atmosphere) with a steep layer (fractured rock) by the slope weight ChunkMesher writes into the colour's alpha.
## Everything here may fail: GameSettings.terrain_detail off or a missing texture gives null, and PlanetTerrain keeps its plain material.

const SHADER_PATH := "res://data/shaders/terrain_detail.gdshader"
## The shader tiles at 4, 6 and 29 m; 348 m is a common multiple, so a chunk's texture offset only needs the origin modulo 348.
const TILE_PERIOD := 348.0
const STEEP_LAYER := "mat_terrain_rock_fractured"
## Mean linear albedo luminance of each set, from its SOURCE.md (the shader divides by it so the detail stays neutral).
const MEAN_LINEAR_LUMINANCE := {
	"mat_terrain_regolith": 0.2148,
	"mat_terrain_soil_dry": 0.2066,
	"mat_terrain_rock_fractured": 0.1515,
}


## Worlds without an atmosphere (Selene, Pebble) get regolith; worlds with one (Aurelia, Cinder, Verdant) get dry soil.
static func flat_layer_id(atmosphere_height: float) -> String:
	return "mat_terrain_soil_dry" if atmosphere_height > 0.0 else "mat_terrain_regolith"


## The per-chunk `tile_offset` instance uniform: the chunk origin (planet frame, doubles) modulo the tile period, per axis.
## `period` must be a common multiple of the material's tile sizes (PlanetLook.detail_tile_period; TILE_PERIOD for the shader defaults).
static func tile_offset(chunk_origin: PackedFloat64Array, period: float = TILE_PERIOD) -> Vector3:
	return Vector3(fposmod(chunk_origin[0], period), fposmod(chunk_origin[1], period), fposmod(chunk_origin[2], period))


static func _texture(layer_id: String, suffix: String) -> Texture2D:
	return AssetLibrary.texture("materials/%s/%s_%s.png" % [layer_id, layer_id, suffix])


## A shader material for this world, or null (switch off, shader or any of the six textures missing). One per terrain, shared by all chunks.
## `look` (optional) sets the tile sizes, contrast and fade (the Rodina style uses large, soft detail); null keeps the shader defaults.
static func build_material(atmosphere_height: float, look: PlanetLook = null) -> ShaderMaterial:
	if not GameSettings.instance().terrain_detail:
		return null
	if not ResourceLoader.exists(SHADER_PATH):
		AssetLibrary.warn_once("terrain_shader", "terrain detail shader missing at %s" % SHADER_PATH)
		return null
	var flat_id := flat_layer_id(atmosphere_height)
	var textures := {}
	for layer in [["flat", flat_id], ["steep", STEEP_LAYER]]:
		for suffix in ["albedo", "normal", "orm"]:
			var texture := _texture(layer[1], suffix)
			if texture == null:
				return null
			textures["%s_%s" % [layer[0], suffix]] = texture
	var material := ShaderMaterial.new()
	material.shader = load(SHADER_PATH) as Shader
	if material.shader == null:
		AssetLibrary.warn_once("terrain_shader_load", "terrain detail shader failed to load")
		return null
	for uniform_name in textures:
		material.set_shader_parameter(uniform_name, textures[uniform_name])
	material.set_shader_parameter("flat_mean_linear", MEAN_LINEAR_LUMINANCE[flat_id])
	material.set_shader_parameter("steep_mean_linear", MEAN_LINEAR_LUMINANCE[STEEP_LAYER])
	if look != null:
		material.set_shader_parameter("flat_tile_metres", look.detail_flat_tile)
		material.set_shader_parameter("steep_tile_metres", look.detail_steep_tile)
		material.set_shader_parameter("far_tile_metres", look.detail_far_tile)
		material.set_shader_parameter("detail_contrast", look.detail_contrast)
		material.set_shader_parameter("fade_start_metres", look.detail_fade_start)
		material.set_shader_parameter("fade_end_metres", look.detail_fade_end)
		material.set_shader_parameter("triplanar_sharpness", look.triplanar_sharpness)
		material.set_shader_parameter("orbit_color", Vector3(look.orbit_color.r, look.orbit_color.g, look.orbit_color.b))
	return material
