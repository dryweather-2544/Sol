class_name AtmosphereShell
extends MeshInstance3D
## A planet's atmosphere, drawn on a sphere around it. With GameSettings.atmosphere_scattering (default) it is Rayleigh/Mie scattering
## that works from orbit down to the ground (data/shaders/atmosphere_scatter.gdshader, adapted from Cuberact's MIT port of O'Neil's
## shader); with the switch off it is the original thin rim glow (atmosphere_rim.gdshader).

const SCATTER_SHADER := "res://data/shaders/atmosphere_scatter.gdshader"
const RIM_SHADER := "res://data/shaders/atmosphere_rim.gdshader"
## The rim shell was drawn 1.6 atmosphere heights out; kept for the fallback so the old look is unchanged.
const RIM_SHELL_HEIGHT_FACTOR := 1.6
## 1 / wavelength^4 of the bluest channel for Earth-like air (0.475 um); other channels are scaled to match the world's colour.
const REFERENCE_INVERSE_WAVELENGTH4 := 19.6

var scattering := GameSettings.instance().atmosphere_scattering
var _material := ShaderMaterial.new()
## Scattering only: a screen-covering quad that draws the atmosphere while the camera is inside it (see the shader header).
var _inside_quad: MeshInstance3D
var _inside_material: ShaderMaterial


func _init() -> void:
	name = "AtmosphereShell"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 128 # only coverage: the shader finds the true sphere analytically
	sphere.rings = 64
	mesh = sphere
	_material.shader = load(SCATTER_SHADER if scattering else RIM_SHADER)
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	if scattering:
		_inside_material = ShaderMaterial.new()
		_inside_material.shader = _material.shader
		_inside_material.set_shader_parameter("fullscreen", true)
		_inside_quad = MeshInstance3D.new()
		_inside_quad.name = "InsideQuad"
		var quad := QuadMesh.new()
		quad.size = Vector2(2.0, 2.0)
		_inside_quad.mesh = quad
		_inside_quad.material_override = _inside_material
		_inside_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_inside_quad.extra_cull_margin = 1.0e9 # its vertices are replaced by the screen corners, so its box must never cull it
		_inside_quad.ignore_occlusion_culling = true
		add_child(_inside_quad)


## planet_radius and atmosphere_height in metres (or any one unit, scaled together). centre: render-space position of the planet centre.
## sun_direction: the way the sunlight travels. atmosphere_color: the colour of the world's air, which sets what scatters most.
func update_shell(planet_radius: float, atmosphere_height: float, centre: Vector3, sun_direction: Vector3, atmosphere_color: Color) -> void:
	position = centre
	_material.set_shader_parameter("sun_direction", sun_direction)
	if scattering:
		var outer_radius := planet_radius + atmosphere_height
		scale = Vector3.ONE * outer_radius
		_material.set_shader_parameter("inner_ratio", planet_radius / outer_radius)
		_material.set_shader_parameter("wavelengths", wavelengths_for(atmosphere_color))
		for parameter in [&"sun_direction", &"inner_ratio", &"wavelengths"]:
			_inside_material.set_shader_parameter(parameter, _material.get_shader_parameter(parameter))
	else:
		scale = Vector3.ONE * (planet_radius + atmosphere_height * RIM_SHELL_HEIGHT_FACTOR)
		_material.set_shader_parameter("rim_color", atmosphere_color)


## Wavelengths (micrometres) whose Rayleigh scattering (1 / wavelength^4) is proportional to the colour's channels, anchored so the
## strongest channel scatters like Earth's blue: a blue colour gives the usual blue sky, an orange one an orange sky.
static func wavelengths_for(color: Color) -> Vector3:
	var strongest := maxf(maxf(color.r, color.g), maxf(color.b, 0.05))
	var inverse4 := Vector3(maxf(color.r, 0.02), maxf(color.g, 0.02), maxf(color.b, 0.02)) * (REFERENCE_INVERSE_WAVELENGTH4 / strongest)
	return Vector3(pow(1.0 / inverse4.x, 0.25), pow(1.0 / inverse4.y, 0.25), pow(1.0 / inverse4.z, 0.25))
