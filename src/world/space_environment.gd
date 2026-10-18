class_name SpaceEnvironment
extends Node3D
## Sun, star sky and ambient light. set_daylight(0..1) fades from black space with stars to a
## blue atmosphere sky as the ship descends.

const DEFAULT_SUN_DIRECTION := Vector3(0.45, -0.57, -0.69)

## Direction the sunlight travels (from the sun toward the world); set each frame from the star system.
var sun_direction := DEFAULT_SUN_DIRECTION.normalized()
var _sky_material := ShaderMaterial.new()
var _environment := Environment.new()
var _sun := DirectionalLight3D.new()


func _ready() -> void:
	_sky_material.shader = load("res://data/shaders/space_sky.gdshader")
	# The panorama replaces the hash stars only if the switch is on and the texture loads; otherwise starfield_amount stays 0.
	var starfield: Texture2D = AssetLibrary.texture("sky/tex_sky_starfield.png") if GameSettings.instance().starfield else null
	_sky_material.set_shader_parameter("starfield", starfield)
	_sky_material.set_shader_parameter("starfield_amount", 1.0 if starfield != null else 0.0)
	_sky_material.set_shader_parameter("gradient_amount", 0.0 if GameSettings.instance().atmosphere_scattering else 1.0) # the atmosphere shell supplies the sky colour
	var sky := Sky.new()
	sky.sky_material = _sky_material
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.12, 0.14, 0.2)
	_environment.ambient_light_energy = 0.6
	var world_environment := WorldEnvironment.new()
	world_environment.environment = _environment
	add_child(world_environment)
	_sun.light_energy = 1.25
	_sun.shadow_enabled = false
	add_child(_sun)
	set_sun_direction(sun_direction)
	set_daylight(0.0, Vector3.UP)


## daylight: 0 = space, 1 = full sky. up_direction: local up, for the horizon glow.
func set_daylight(daylight: float, up_direction: Vector3, altitude_metres: float = 0.0) -> void:
	_sky_material.set_shader_parameter("daylight", daylight)
	_sky_material.set_shader_parameter("sun_direction", -sun_direction)
	# Ground haze: a little distance fog by day, thinning out with altitude.
	_environment.fog_enabled = daylight > 0.02
	_environment.fog_light_color = Color(0.62, 0.75, 0.92)
	_environment.fog_density = 3.0e-5 * daylight * (1.0 - smoothstep(2000.0, 30000.0, altitude_metres))
	_environment.fog_sky_affect = 0.0
	_environment.ambient_light_energy = lerpf(0.6, 0.55, daylight)
	_environment.ambient_light_color = Color(0.12, 0.14, 0.2).lerp(Color(0.45, 0.55, 0.75), daylight)


func set_sun_direction(light_direction: Vector3) -> void:
	sun_direction = light_direction.normalized()
	var up_hint := Vector3.UP if absf(sun_direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	_sun.transform = Transform3D(Basis.looking_at(sun_direction, up_hint), Vector3.ZERO)
	_sky_material.set_shader_parameter("sun_direction", -sun_direction)
