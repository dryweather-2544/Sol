class_name SpaceEnvironment
extends Node3D
const VisualStyleScript = preload("res://src/world/visual_style.gd")
## Sun, star sky and ambient light. set_daylight(0..1) fades from black space with stars to a
## blue atmosphere sky as the ship descends.

const DEFAULT_SUN_DIRECTION := Vector3(0.45, -0.57, -0.69)

## Direction the sunlight travels (from the sun toward the world); set each frame from the star system.
var sun_direction := DEFAULT_SUN_DIRECTION.normalized()
var _sky_material := ShaderMaterial.new()
var _environment := Environment.new()
var _sun := DirectionalLight3D.new()
var _rodina_body: BodyDef
var _profile := ""


func _ready() -> void:
	VisualStyleScript.refresh_from_settings()
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
	_environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	_environment.tonemap_exposure = 0.70
	_environment.tonemap_white = 6.0
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.10, 0.13, 0.19)
	_environment.ambient_light_energy = 0.55
	# Restrained post stack: contact shadowing in the ship and at landing sites, a little bloom for
	# thrusters/screens, and a warm/cool grade. No SDFGI or volumetric fog on the 16 GB target.
	_environment.ssao_enabled = true
	_environment.ssao_radius = 1.6
	_environment.ssao_intensity = 2.2
	_environment.ssao_power = 1.4
	_environment.ssao_detail = 0.6
	_environment.ssao_light_affect = 0.25
	_environment.glow_enabled = true
	_environment.glow_intensity = 0.35
	_environment.glow_strength = 1.05
	_environment.glow_bloom = 0.04
	_environment.glow_hdr_threshold = 1.25
	_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_environment.adjustment_enabled = true
	_environment.adjustment_brightness = 1.0
	_environment.adjustment_contrast = 1.12
	_environment.adjustment_saturation = 1.06
	var world_environment := WorldEnvironment.new()
	world_environment.environment = _environment
	add_child(world_environment)
	_sun.light_color = Color(1.0, 0.94, 0.84)
	_sun.light_energy = 1.08
	_sun.light_angular_distance = 0.35
	_sun.shadow_enabled = true
	_sun.shadow_bias = 0.04
	_sun.shadow_normal_bias = 1.2
	_sun.directional_shadow_max_distance = 240.0
	add_child(_sun)
	_apply_profile()
	set_sun_direction(sun_direction)
	set_daylight(0.0, Vector3.UP)


## daylight: 0 = space, 1 = full sky. up_direction: local up, for the horizon glow.
func set_daylight(daylight: float, up_direction: Vector3, altitude_metres: float = 0.0) -> void:
	_apply_profile()
	_sky_material.set_shader_parameter("daylight", daylight)
	_sky_material.set_shader_parameter("sun_direction", -sun_direction)
	_sky_material.set_shader_parameter("horizon_up", up_direction)
	if VisualStyleScript.is_rodina():
		_apply_rodina_palette()
		var horizon := Color(0.72, 0.50, 0.44)
		var ambient := Color(0.045, 0.035, 0.055)
		if _rodina_body != null:
			horizon = _rodina_body.rodina_sky_horizon
			ambient = _rodina_body.rodina_ambient_color
		# The reference keeps a thin, coloured horizon haze instead of a white depth wash.
		_environment.fog_enabled = daylight > 0.02
		_environment.fog_light_color = horizon.darkened(0.35)
		_environment.fog_density = 1.2e-5 * daylight * (1.0 - smoothstep(2000.0, 30000.0, altitude_metres))
		_environment.fog_sky_affect = 0.0
		_environment.ambient_light_energy = lerpf(0.28, 0.16, daylight)
		_environment.ambient_light_color = ambient.lerp(horizon.darkened(0.65), daylight * 0.35)
		return
	# Original Sol look, unchanged.
	_environment.fog_enabled = daylight > 0.02
	_environment.fog_light_color = Color(0.56, 0.66, 0.78)
	_environment.fog_density = 2.2e-5 * daylight * (1.0 - smoothstep(2000.0, 30000.0, altitude_metres))
	_environment.fog_sky_affect = 0.0
	_environment.ambient_light_energy = lerpf(0.46, 0.30, daylight)
	_environment.ambient_light_color = Color(0.10, 0.13, 0.19).lerp(Color(0.34, 0.42, 0.54), daylight)


## The active body supplies the authored Rodina sky/sun palette. Sol ignores this hook entirely.
func apply_body_style(body: BodyDef) -> void:
	_rodina_body = body
	if VisualStyleScript.is_rodina():
		_apply_rodina_palette()


func _apply_profile() -> void:
	var style := VisualStyleScript.refresh_from_settings()
	if style == _profile:
		return
	_profile = style
	var rodina := style == VisualStyleScript.RODINA
	_sky_material.set_shader_parameter("rodina_mode", 1.0 if rodina else 0.0)
	if rodina:
		# A deliberately flat grade; per-body colours do the saturation work.
		_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		_environment.tonemap_exposure = 1.0
		_environment.tonemap_white = 1.0
		_environment.ssao_enabled = false
		_environment.glow_enabled = true
		_environment.glow_intensity = 0.20
		_environment.glow_strength = 1.0
		_environment.glow_bloom = 0.02
		_environment.glow_hdr_threshold = 1.15
		_environment.adjustment_enabled = true
		_environment.adjustment_brightness = 1.0
		_environment.adjustment_contrast = 1.10
		_environment.adjustment_saturation = 1.0
	else:
		# Exact original Sol profile.
		_environment.tonemap_mode = Environment.TONE_MAPPER_ACES
		_environment.tonemap_exposure = 0.70
		_environment.tonemap_white = 6.0
		_environment.ssao_enabled = true
		_environment.ssao_radius = 1.6
		_environment.ssao_intensity = 2.2
		_environment.ssao_power = 1.4
		_environment.ssao_detail = 0.6
		_environment.ssao_light_affect = 0.25
		_environment.glow_enabled = true
		_environment.glow_intensity = 0.35
		_environment.glow_strength = 1.05
		_environment.glow_bloom = 0.04
		_environment.glow_hdr_threshold = 1.25
		_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		_environment.adjustment_enabled = true
		_environment.adjustment_brightness = 1.0
		_environment.adjustment_contrast = 1.12
		_environment.adjustment_saturation = 1.06
		_sun.light_color = Color(1.0, 0.94, 0.84)
		_sun.light_energy = 1.08
	if _rodina_body != null and rodina:
		_apply_rodina_palette()


func _apply_rodina_palette() -> void:
	if _rodina_body == null:
		return
	_sky_material.set_shader_parameter("rodina_space_color", _rodina_body.rodina_space_color)
	_sky_material.set_shader_parameter("rodina_sky_zenith", _rodina_body.rodina_sky_zenith)
	_sky_material.set_shader_parameter("rodina_sky_horizon", _rodina_body.rodina_sky_horizon)
	_sky_material.set_shader_parameter("rodina_sun_color", _rodina_body.rodina_sun_color)
	_sun.light_color = _rodina_body.rodina_light_color
	_sun.light_energy = 1.0


func set_sun_direction(light_direction: Vector3) -> void:
	sun_direction = light_direction.normalized()
	var up_hint := Vector3.UP if absf(sun_direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	_sun.transform = Transform3D(Basis.looking_at(sun_direction, up_hint), Vector3.ZERO)
	_sky_material.set_shader_parameter("sun_direction", -sun_direction)
