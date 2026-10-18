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
static func tile_offset(chunk_origin: PackedFloat64Array) -> Vector3:
	return Vector3(fposmod(chunk_origin[0], TILE_PERIOD), fposmod(chunk_origin[1], TILE_PERIOD), fposmod(chunk_origin[2], TILE_PERIOD))


static func _texture(layer_id: String, suffix: String) -> Texture2D:
	return AssetLibrary.texture("materials/%s/%s_%s.png" % [layer_id, layer_id, suffix])


## A shader material for this world, or null (switch off, shader or any of the six textures missing). One per terrain, shared by all chunks.
static func build_material(atmosphere_height: float) -> ShaderMaterial:
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
	return material
