class_name SpaceEnvironment
extends Node3D
## Sun, star sky and ambient light. set_daylight(0..1) fades from black space with stars to a
## blue atmosphere sky as the ship descends.

const SUN_ROTATION_DEGREES := Vector3(-35.0, 40.0, 0.0)

var _sky_material := ShaderMaterial.new()
var _environment := Environment.new()
var _sun := DirectionalLight3D.new()


## Direction the sunlight travels (from the sun toward the world).
static func sun_direction() -> Vector3:
	return Basis.from_euler(SUN_ROTATION_DEGREES * (PI / 180.0)) * Vector3(0, 0, -1)


func _ready() -> void:
	_sky_material.shader = load("res://data/shaders/space_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_material
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.12, 0.14, 0.2)
	_environment.ambient_light_energy = 0.6
	var world_environment := WorldEnvironment.new()
	world_environment.environment = _environment
	add_child(world_environment)
	_sun.rotation_degrees = SUN_ROTATION_DEGREES
	_sun.light_energy = 1.6
	_sun.shadow_enabled = false
	add_child(_sun)
	set_daylight(0.0, Vector3.UP)


## daylight: 0 = space, 1 = full sky. up_direction: local up, for the horizon glow.
func set_daylight(daylight: float, up_direction: Vector3) -> void:
	_sky_material.set_shader_parameter("daylight", daylight)
	_sky_material.set_shader_parameter("sun_direction", -sun_direction())
	_environment.ambient_light_energy = lerpf(0.6, 0.55, daylight)
	_environment.ambient_light_color = Color(0.12, 0.14, 0.2).lerp(Color(0.45, 0.55, 0.75), daylight)
