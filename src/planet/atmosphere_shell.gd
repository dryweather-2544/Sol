class_name AtmosphereShell
extends MeshInstance3D
## A glowing rim around a planet's atmosphere, seen from space. Invisible from inside (back faces are culled).

var _material := ShaderMaterial.new()


func _init() -> void:
	name = "AtmosphereShell"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	mesh = sphere
	_material.shader = load("res://data/shaders/atmosphere_rim.gdshader")
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0


## Rodina style: the shell is the atmosphere itself, drawn with Rodina's atmosphere maths (rodina_atmosphere_shell).
var _rodina_material := ShaderMaterial.new()


## Shows Rodina's atmosphere around a planet of planet_radius (metres) with air atmosphere_height high. parameters: the
## PlanetLook's rodina_atmosphere values. Returns false (and does nothing) when the look has none.
func update_rodina(planet_radius: float, atmosphere_height: float, centre: Vector3, sun_direction: Vector3, star_radius_angle: float, parameters: Dictionary) -> bool:
	if parameters.is_empty():
		return false
	if _rodina_material.shader == null:
		_rodina_material.shader = load("res://data/shaders/rodina_atmosphere_shell.gdshader")
	material_override = _rodina_material
	position = centre
	scale = Vector3.ONE * (planet_radius + atmosphere_height) * 1.005
	for parameter in parameters:
		if String(parameter).begins_with("shell_"):
			continue # shell-only overrides, applied below
		var value: Variant = parameters[parameter]
		_rodina_material.set_shader_parameter(parameter, Vector3(value.r, value.g, value.b) if value is Color else value)
	# Sol's brighter glow colours for the view from space (the sky from inside keeps Rodina's own colours).
	for pair in [["shell_scatter1", "atm_scatter1"], ["shell_scatter2", "atm_scatter2"]]:
		if parameters.has(pair[0]):
			var colour: Color = parameters[pair[0]]
			_rodina_material.set_shader_parameter(pair[1], Vector3(colour.r, colour.g, colour.b))
	_rodina_material.set_shader_parameter("atm_glow_gain", float(parameters.get("shell_glow_gain", 1.0)))
	_rodina_material.set_shader_parameter("rodina_atmosphere", true)
	_rodina_material.set_shader_parameter("planet_centre", centre)
	_rodina_material.set_shader_parameter("planet_radius", planet_radius)
	_rodina_material.set_shader_parameter("atm_height", atmosphere_height / planet_radius)
	_rodina_material.set_shader_parameter("atm_star_radius_angle", star_radius_angle)
	_rodina_material.set_shader_parameter("sun_direction", sun_direction)
	return true


## radius_metres: planet radius plus atmosphere height. centre: render-space position of the planet centre.
func update_shell(radius_metres: float, centre: Vector3, sun_direction: Vector3, rim_color: Color, rim_power: float = 6.0, disc_haze: float = 0.0) -> void:
	material_override = _material
	position = centre
	scale = Vector3.ONE * radius_metres
	_material.set_shader_parameter("sun_direction", sun_direction)
	_material.set_shader_parameter("rim_color", rim_color)
	_material.set_shader_parameter("rim_power", rim_power)
	_material.set_shader_parameter("disc_haze", disc_haze)
