class_name CloudShell
extends MeshInstance3D
## A planet's cloud layer. Seen from above it is a thin sphere (data/shaders/cloud_shell.gdshader); from inside or just above the layer a
## screen-covering pass ray-marches the slab of air between the layer's bottom and top (cloud_volume.gdshader). Both read the same 3D noise
## texture (data/shaders/cloud_common.gdshaderinc), so a cloud keeps its shape as you descend into it; the weather is procedural.

const SHELL_SHADER := "res://data/shaders/cloud_shell.gdshader"
const VOLUME_SHADER := "res://data/shaders/cloud_volume.gdshader"
## Seconds per full turn of the weather relative to the ground (slow drift, so clouds visibly move over minutes in orbit).
const DRIFT_PERIOD_SECONDS := 20000.0
## The layer's thickness is this fraction of its altitude (Aurelia: 2.5 km thick at 10 km altitude).
const THICKNESS_FRACTION := 0.25
## Size and tiling of the baked noise: 4 or so features per tile at this frequency.
const NOISE_SIZE := 96
const NOISE_FREQUENCY := 0.04

static var _noise_texture: NoiseTexture3D

var _material := ShaderMaterial.new()
var _volume_material := ShaderMaterial.new()
var _volume_quad: MeshInstance3D


func _init() -> void:
	name = "CloudShell"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 128 # only coverage: the shader finds the exact sphere
	sphere.rings = 64
	mesh = sphere
	_material.shader = load(SHELL_SHADER)
	_material.render_priority = -1 # before the atmosphere shell (priority 0), so haze draws over the clouds
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	_volume_material.shader = load(VOLUME_SHADER)
	_volume_material.render_priority = 1 # after the atmosphere pass: clouds over sky haze
	_volume_quad = MeshInstance3D.new()
	_volume_quad.name = "VolumePass"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_volume_quad.mesh = quad
	_volume_quad.material_override = _volume_material
	_volume_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_volume_quad.extra_cull_margin = 1.0e9 # its vertices are replaced by the screen corners, so its box must never cull it
	_volume_quad.ignore_occlusion_culling = true
	add_child(_volume_quad)
	var texture := shared_noise_texture()
	_material.set_shader_parameter("cloud_noise", texture)
	_volume_material.set_shader_parameter("cloud_noise", texture)


## The one baked noise texture every cloud shell shares (built on first use; NoiseTexture3D bakes on a thread, so clouds appear a moment later).
static func shared_noise_texture() -> NoiseTexture3D:
	if _noise_texture == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_PERLIN
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 4
		noise.frequency = NOISE_FREQUENCY
		_noise_texture = NoiseTexture3D.new()
		_noise_texture.width = NOISE_SIZE
		_noise_texture.height = NOISE_SIZE
		_noise_texture.depth = NOISE_SIZE
		_noise_texture.seamless = true
		_noise_texture.noise = noise
	return _noise_texture


## Radii of the layer's bottom and top, in the same units as the arguments (x = bottom, y = top): centred on planet_radius + cloud_altitude.
static func layer_radii(planet_radius: float, cloud_altitude: float) -> Vector2:
	var half_thickness := cloud_altitude * THICKNESS_FRACTION * 0.5
	return Vector2(planet_radius + cloud_altitude - half_thickness, planet_radius + cloud_altitude + half_thickness)


## planet_radius and cloud_altitude in metres (or any one unit, scaled together). centre: render-space position of the planet centre.
func update_shell(planet_radius: float, cloud_altitude: float, centre: Vector3, sun_direction: Vector3, body: BodyDef, game_seconds: float) -> void:
	position = centre
	var shell_radius := planet_radius + cloud_altitude
	scale = Vector3.ONE * shell_radius
	var radii := layer_radii(planet_radius, cloud_altitude) / shell_radius
	var fade_band := 2.0 * cloud_altitude / shell_radius
	var shadow_color := body.cloud_color.darkened(0.45).lerp(body.atmosphere_color, 0.25)
	var drift_angle := fposmod(game_seconds / DRIFT_PERIOD_SECONDS, 1.0) * TAU
	for material in [_material, _volume_material]:
		(material as ShaderMaterial).set_shader_parameter("sun_direction", sun_direction)
		(material as ShaderMaterial).set_shader_parameter("cloud_color", body.cloud_color)
		(material as ShaderMaterial).set_shader_parameter("shadow_color", shadow_color)
		(material as ShaderMaterial).set_shader_parameter("coverage", body.cloud_coverage)
		(material as ShaderMaterial).set_shader_parameter("seed", seed_for(body.id))
		(material as ShaderMaterial).set_shader_parameter("drift", drift_angle)
		(material as ShaderMaterial).set_shader_parameter("top_radius", radii.y)
		(material as ShaderMaterial).set_shader_parameter("fade_band", fade_band)
	_volume_material.set_shader_parameter("bottom_radius", radii.x)
	_volume_material.set_shader_parameter("shell_metres", shell_radius)


## A stable small number per world, so every planet has its own weather and a saved game sees the same sky.
static func seed_for(body_id: StringName) -> float:
	return float(String(body_id).hash() % 1000) * 0.013
