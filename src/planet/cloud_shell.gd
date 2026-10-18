class_name CloudShell
extends MeshInstance3D
## A planet's cloud layer seen from above (orbit and high altitude), on a sphere just outside the surface. The weather is procedural
## (data/shaders/cloud_shell.gdshader). Hidden from inside the layer: the clouds you fly through are a later step.

const SHADER := "res://data/shaders/cloud_shell.gdshader"
## Seconds per full turn of the weather relative to the ground (slow drift, so clouds visibly move over minutes in orbit).
const DRIFT_PERIOD_SECONDS := 20000.0

var _material := ShaderMaterial.new()


func _init() -> void:
	name = "CloudShell"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 128 # only coverage: the shader finds the exact sphere
	sphere.rings = 64
	mesh = sphere
	_material.shader = load(SHADER)
	_material.render_priority = -1 # before the atmosphere shell (priority 0), so haze draws over the clouds
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0


## planet_radius and cloud_altitude in metres (or any one unit, scaled together). centre: render-space position of the planet centre.
func update_shell(planet_radius: float, cloud_altitude: float, centre: Vector3, sun_direction: Vector3, body: BodyDef, game_seconds: float) -> void:
	position = centre
	var shell_radius := planet_radius + cloud_altitude
	scale = Vector3.ONE * shell_radius
	_material.set_shader_parameter("sun_direction", sun_direction)
	_material.set_shader_parameter("cloud_color", body.cloud_color)
	_material.set_shader_parameter("shadow_color", body.cloud_color.darkened(0.45).lerp(body.atmosphere_color, 0.25))
	_material.set_shader_parameter("coverage", body.cloud_coverage)
	_material.set_shader_parameter("seed", seed_for(body.id))
	_material.set_shader_parameter("drift", fposmod(game_seconds / DRIFT_PERIOD_SECONDS, 1.0) * TAU)
	_material.set_shader_parameter("fade_band", 2.0 * cloud_altitude / shell_radius)


## A stable small number per world, so every planet has its own weather and a saved game sees the same sky.
static func seed_for(body_id: StringName) -> float:
	return float(String(body_id).hash() % 1000) * 0.013
