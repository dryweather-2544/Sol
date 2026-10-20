class_name SpaceEnvironment
extends Node3D
## Sun, star sky and ambient light. set_daylight(0..1) fades from black space with stars to the planet's day sky as
## the ship descends. apply_look() sets the colours for the world the player is at, under the active VisualStyle
## (the Sol look reproduces the original constants).

const DEFAULT_SUN_DIRECTION := Vector3(0.45, -0.57, -0.69)

## Direction the sunlight travels (from the sun toward the world); set each frame from the star system.
var sun_direction := DEFAULT_SUN_DIRECTION.normalized()
var _sky_material := ShaderMaterial.new()
var _environment := Environment.new()
var _sun := DirectionalLight3D.new()
## Rodina-style "backside" fill: a weak, shadowless light from the side away from the sun (energy 0 in the Sol style).
var _back_light := DirectionalLight3D.new()
var _look := PlanetLook.new()


func _ready() -> void:
	_sky_material.shader = load("res://data/shaders/space_sky.gdshader")
	# The panorama replaces the hash stars only if the switch is on and the texture loads; otherwise starfield_amount stays 0.
	var starfield: Texture2D = AssetLibrary.texture("sky/tex_sky_starfield.png") if GameSettings.instance().starfield else null
	_sky_material.set_shader_parameter("starfield", starfield)
	_sky_material.set_shader_parameter("starfield_amount", 1.0 if starfield != null else 0.0)
	var sky := Sky.new()
	sky.sky_material = _sky_material
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var world_environment := WorldEnvironment.new()
	world_environment.environment = _environment
	add_child(world_environment)
	_sun.shadow_enabled = false
	add_child(_sun)
	_back_light.name = "BackLight"
	_back_light.shadow_enabled = false
	_back_light.light_specular = 0.0
	add_child(_back_light)
	apply_look(_look)
	set_sun_direction(sun_direction)
	set_daylight(0.0, Vector3.UP)


## Colours and lights for the current world and visual style. Call on arrival at a world and when the style changes.
func apply_look(look: PlanetLook) -> void:
	_look = look
	var space := VisualStyle.space_parameters()
	_environment.tonemap_mode = VisualStyle.tonemap_mode()
	_environment.glow_enabled = VisualStyle.glow_enabled()
	_environment.glow_intensity = 0.7
	_environment.glow_bloom = 0.06
	_environment.glow_hdr_threshold = 0.95
	_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_sun.light_color = look.sun_color
	_sun.light_energy = look.sun_energy
	_back_light.light_color = look.back_color
	_back_light.light_energy = look.back_energy
	_back_light.visible = look.back_energy > 0.0
	var parameters := {
		"space_color": space["space_color"], "star_gain": space["star_gain"], "star_tint": space["star_tint"], "star_gamma": space["star_gamma"],
		"sky_zenith": look.sky_zenith, "sky_horizon": look.sky_horizon, "gradient_scale": look.gradient_scale,
		"gradient_bias": look.gradient_bias, "gradient_power": look.gradient_power, "legacy_glow": look.legacy_sun_glow,
		"legacy_glow_color": look.legacy_sun_glow_color, "sun_color": look.sun_color, "sun_disc_gain": look.sun_disc_gain,
		"sun_halo_gain": look.sun_halo_gain, "sun_disc_color": look.sun_disc_color, "sun_halo_color": look.sun_halo_color,
		"sun_disc_radius": look.sun_disc_radius, "sun_halo_width": look.sun_halo_width, "sunset_halo_width": look.sunset_halo_width,
		"sunset_color": look.sunset_color, "sunset_gain": look.sunset_gain,
		"local_up_amount": 0.0 if look.family == &"sol" else 1.0}
	for parameter in parameters:
		var value: Variant = parameters[parameter]
		_sky_material.set_shader_parameter(parameter, Vector3(value.r, value.g, value.b) if value is Color else value)


## daylight: 0 = space, 1 = full sky. up_direction: local up, for the horizon glow.
func set_daylight(daylight: float, up_direction: Vector3, altitude_metres: float = 0.0) -> void:
	_sky_material.set_shader_parameter("daylight", daylight)
	_sky_material.set_shader_parameter("sun_direction", -sun_direction)
	_sky_material.set_shader_parameter("up_direction", up_direction)
	# Ground haze: a little distance fog by day, thinning out with altitude.
	_environment.fog_enabled = daylight > 0.02
	_environment.fog_light_color = _look.fog_color
	var thinning := 1.0 - smoothstep(2000.0, 30000.0, altitude_metres) if _look.fog_thins_with_altitude else 1.0
	_environment.fog_density = _look.fog_density * daylight * thinning
	_environment.fog_aerial_perspective = _look.fog_aerial_perspective
	_environment.fog_sky_affect = 0.0
	_environment.ambient_light_energy = lerpf(_look.ambient_energy_space, _look.ambient_energy_day, daylight)
	_environment.ambient_light_color = _look.ambient_space.lerp(_look.ambient_day, daylight)


## sun_elevation: cosine of the sun's angle from the local up (dot(up, toward the sun)); 1 in open space. Rodina fades
## the star light through the terminator (rendering_notes §6.2, GetPlanetDayLightIntensity); the Sol look ignores it.
func set_sun_elevation(sun_elevation: float) -> void:
	var factor := 1.0
	if _look.terminator_enabled:
		factor = smoothstep(_look.terminator_end, _look.terminator_begin, sun_elevation)
	_sun.light_energy = _look.sun_energy * factor


func set_sun_direction(light_direction: Vector3) -> void:
	sun_direction = light_direction.normalized()
	var up_hint := Vector3.UP if absf(sun_direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	_sun.transform = Transform3D(Basis.looking_at(sun_direction, up_hint), Vector3.ZERO)
	_back_light.transform = Transform3D(Basis.looking_at(-sun_direction, up_hint), Vector3.ZERO)
	_sky_material.set_shader_parameter("sun_direction", -sun_direction)
