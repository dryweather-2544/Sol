class_name PlaceholderShipMesh
extends RefCounted
## Primitive-shape stand-in for the ship so flight can be judged by eye. Nose points to -z.


static func build(ship_node: Node3D) -> void:
	var hull := _material(Color(0.62, 0.66, 0.72), 0.5, 0.4)
	var accent := _material(Color(0.9, 0.35, 0.1), 0.6, 0.2)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.3, 0.6, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.3, 0.6, 1.0)
	glow.emission_energy_multiplier = 3.0
	var canopy := _material(Color(0.1, 0.15, 0.25), 0.1, 0.9)

	_add(ship_node, BoxMesh.new(), hull, Vector3(0, 0, 0), Vector3.ZERO, Vector3(2.2, 0.9, 6.0))
	var nose := CylinderMesh.new()
	nose.top_radius = 0.0
	nose.bottom_radius = 1.0
	nose.height = 3.0
	nose.radial_segments = 4
	_add(ship_node, nose, hull, Vector3(0, 0, -4.5), Vector3(-90, 45, 0), Vector3(1.1, 1.0, 0.45))
	_add(ship_node, BoxMesh.new(), hull, Vector3(-3.6, 0, 1.2), Vector3(0, 0, 0), Vector3(5.0, 0.15, 2.6))
	_add(ship_node, BoxMesh.new(), hull, Vector3(3.6, 0, 1.2), Vector3(0, 0, 0), Vector3(5.0, 0.15, 2.6))
	_add(ship_node, BoxMesh.new(), accent, Vector3(0, 0.95, 2.0), Vector3.ZERO, Vector3(0.15, 1.2, 1.8))
	_add(ship_node, SphereMesh.new(), canopy, Vector3(0, 0.55, -1.2), Vector3.ZERO, Vector3(1.4, 0.8, 2.2))
	for side in [-1.0, 1.0]:
		var engine := CylinderMesh.new()
		engine.top_radius = 0.5
		engine.bottom_radius = 0.6
		engine.height = 1.2
		_add(ship_node, engine, glow, Vector3(0.9 * side, 0, 3.3), Vector3(90, 0, 0), Vector3.ONE)
	_add(ship_node, BoxMesh.new(), accent, Vector3(-6.2, 0, 1.2), Vector3.ZERO, Vector3(0.3, 0.2, 2.6))
	_add(ship_node, BoxMesh.new(), _material(Color(0.1, 0.8, 0.2), 0.6, 0.2), Vector3(6.2, 0, 1.2), Vector3.ZERO, Vector3(0.3, 0.2, 2.6))


static func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


static func _add(parent: Node3D, mesh: Mesh, material: Material, position: Vector3, rotation_degrees_value: Vector3, scale_value: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.rotation_degrees = rotation_degrees_value
	instance.scale = scale_value
	parent.add_child(instance)
