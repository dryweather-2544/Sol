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


## radius_metres: planet radius plus atmosphere height. centre: render-space position of the planet centre.
func update_shell(radius_metres: float, centre: Vector3, sun_direction: Vector3, rim_color: Color) -> void:
	position = centre
	scale = Vector3.ONE * radius_metres
	_material.set_shader_parameter("sun_direction", sun_direction)
	_material.set_shader_parameter("rim_color", rim_color)
