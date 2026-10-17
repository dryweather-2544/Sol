class_name PoiBuilder
extends RefCounted
## Builds the placeholder scenery for a POI from its seed. Props sit on the real terrain height. All
## primitives, no third-party assets. Local axes: x/z along the ground, y = away from the planet.

const GROUND_SAMPLE_ARMS := 1


## Orientation of a POI's local frame at its position: y is up (away from the planet centre).
static func frame_basis(instance: PoiInstance) -> Basis:
	var up := Vector3(instance.position.x, instance.position.y, instance.position.z).normalized()
	var helper := Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.UP
	var side := up.cross(helper).normalized()
	return Basis(side, up, side.cross(up))


## Height of the terrain at local (x, z) relative to the POI's own ground point.
static func ground_offset(planet: PlanetBody, instance: PoiInstance, local_x: float, local_z: float) -> float:
	var frame := frame_basis(instance)
	var point_x := instance.position.x + frame.x.x * local_x + frame.z.x * local_z
	var point_y := instance.position.y + frame.x.y * local_x + frame.z.y * local_z
	var point_z := instance.position.z + frame.x.z * local_x + frame.z.z * local_z
	var distance := sqrt(point_x * point_x + point_y * point_y + point_z * point_z)
	var origin_distance := sqrt(instance.position.x * instance.position.x + instance.position.y * instance.position.y + instance.position.z * instance.position.z)
	return planet.surface_radius_xyz(point_x / distance, point_y / distance, point_z / distance) - origin_distance


## Solid circles (local x, z, radius) that people on foot cannot walk into. Mirrors the random draws in
## the builders below, so the circles sit under the visible props.
static func blockers(instance: PoiInstance) -> Array[Vector3]:
	var circles: Array[Vector3] = []
	var rng := SeedRng.new(instance.seed_value)
	match instance.type:
		PoiDefinition.Type.WRECK:
			var hull_yaw := rng.next_float() * TAU
			var axis := Vector2(sin(hull_yaw), cos(hull_yaw))
			for offset in [-8.0, -4.0, 0.0, 4.0, 8.0]:
				circles.append(Vector3(axis.x * offset, axis.y * offset, 3.2))
			circles.append(Vector3(axis.x * -12.0 + 2.0, axis.y * -12.0, 3.0))
		PoiDefinition.Type.BEACON:
			circles.append(Vector3(0.0, 0.0, 3.6))
		_:
			for building_index in 3:
				var angle := (float(building_index) / 3.0 + rng.next_float() * 0.2) * TAU
				var width := 9.0 + rng.next_float() * 5.0
				rng.next_float() # height
				var depth := 8.0 + rng.next_float() * 5.0
				circles.append(Vector3(cos(angle) * 30.0, sin(angle) * 30.0, maxf(width, depth) * 0.6))
			circles.append(Vector3(0.0, 0.0, 0.6))
	return circles


## Where the loot crates stand (local x, z) for a POI. Fixed per type so scenery and loot agree.
static func crate_positions(instance: PoiInstance) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	match instance.type:
		PoiDefinition.Type.WRECK:
			var rng := SeedRng.new(instance.seed_value)
			var hull_yaw := rng.next_float() * TAU
			positions.append(Vector2(sin(hull_yaw) * 6.5 + cos(hull_yaw) * 4.5, cos(hull_yaw) * 6.5 - sin(hull_yaw) * 4.5))
			positions.append(Vector2(-sin(hull_yaw) * 5.0 - cos(hull_yaw) * 4.5, -cos(hull_yaw) * 5.0 + sin(hull_yaw) * 4.5))
		PoiDefinition.Type.BEACON:
			positions.append(Vector2(5.5, 0.0))
		_:
			positions.append(Vector2(14.0, 0.0))
			positions.append(Vector2(-14.0, 6.0))
			positions.append(Vector2(2.0, -15.0))
	return positions


static func crate_id(instance: PoiInstance, crate_index: int) -> StringName:
	return StringName("%s#%d" % [instance.id, crate_index])


static func build_content(instance: PoiInstance, planet: PlanetBody) -> Node3D:
	var root := Node3D.new()
	root.name = String(instance.id)
	var rng := SeedRng.new(instance.seed_value)
	match instance.type:
		PoiDefinition.Type.WRECK:
			_build_wreck(root, instance, planet, rng)
		PoiDefinition.Type.BEACON:
			_build_beacon(root, instance, planet)
		_:
			_build_outpost(root, instance, planet, rng)
	var crate_material := _material(Color(0.8, 0.55, 0.15), 0.6, 0.3)
	var crate_index := 0
	for crate_position in crate_positions(instance):
		var crate_node := MeshInstance3D.new()
		var crate_mesh := BoxMesh.new()
		crate_mesh.size = Vector3(1.4, 1.0, 1.0)
		crate_node.mesh = crate_mesh
		crate_node.material_override = crate_material
		crate_node.name = "Crate%d" % crate_index
		crate_node.position = Vector3(crate_position.x, ground_offset(planet, instance, crate_position.x, crate_position.y) + 0.5, crate_position.y)
		root.add_child(crate_node)
		crate_index += 1
	return root


## A tall translucent beam so the POI can be seen from far away; null for types without one.
static func build_marker(instance: PoiInstance) -> Node3D:
	var height: float = PoiDefinition.BEAM_HEIGHT[instance.type]
	if height <= 0.0:
		return null
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var color: Color = PoiDefinition.BEAM_COLOR[instance.type]
	material.albedo_color = Color(color.r, color.g, color.b, 0.45)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = height
	mesh.radial_segments = 8
	var instance_node := MeshInstance3D.new()
	instance_node.mesh = mesh
	instance_node.material_override = material
	instance_node.position = Vector3(0, height * 0.5, 0)
	instance_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var holder := Node3D.new()
	holder.name = "Marker_" + String(instance.id)
	holder.add_child(instance_node)
	return holder


static func _build_wreck(root: Node3D, instance: PoiInstance, planet: PlanetBody, rng: SeedRng) -> void:
	var metal := _material(Color(0.28, 0.28, 0.3), 0.7, 0.6)
	var rust := _material(Color(0.45, 0.25, 0.12), 0.9, 0.2)
	var hull_offset := ground_offset(planet, instance, 0.0, 0.0)
	var hull_yaw := rng.next_float() * TAU
	_box(root, Vector3(5.0, 3.5, 20.0), metal, Vector3(0, hull_offset + 1.0, 0), Vector3(rng.next_float() * 14.0 - 7.0, rad_to_deg(hull_yaw), rng.next_float() * 16.0 - 8.0))
	_box(root, Vector3(4.0, 2.5, 7.0), rust, Vector3(2.0, hull_offset + 1.2, -12.0), Vector3(10.0, rad_to_deg(hull_yaw) + 20.0, 25.0))
	for debris_index in 14:
		var angle := rng.next_float() * TAU
		var distance := 8.0 + rng.next_float() * 40.0
		var local_x := cos(angle) * distance
		var local_z := sin(angle) * distance
		var size := 0.6 + rng.next_float() * 3.0
		_box(root, Vector3(size, size * (0.3 + rng.next_float()), size * (0.5 + rng.next_float())), metal if rng.next_float() < 0.6 else rust,
			Vector3(local_x, ground_offset(planet, instance, local_x, local_z) + size * 0.25, local_z), Vector3(rng.next_float() * 40.0, rng.next_float() * 360.0, rng.next_float() * 40.0))


static func _build_beacon(root: Node3D, instance: PoiInstance, planet: PlanetBody) -> void:
	var base_height := ground_offset(planet, instance, 0.0, 0.0)
	var concrete := _material(Color(0.5, 0.5, 0.52), 0.9, 0.0)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.3, 0.8, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.3, 0.8, 1.0)
	glow.emission_energy_multiplier = 4.0
	var base := CylinderMesh.new()
	base.top_radius = 3.0
	base.bottom_radius = 3.5
	base.height = 1.5
	_mesh(root, base, concrete, Vector3(0, base_height + 0.5, 0))
	var mast := CylinderMesh.new()
	mast.top_radius = 0.25
	mast.bottom_radius = 0.45
	mast.height = 26.0
	_mesh(root, mast, concrete, Vector3(0, base_height + 13.5, 0))
	var light := SphereMesh.new()
	light.radius = 1.3
	light.height = 2.6
	_mesh(root, light, glow, Vector3(0, base_height + 27.5, 0))


static func _build_outpost(root: Node3D, instance: PoiInstance, planet: PlanetBody, rng: SeedRng) -> void:
	var wall := _material(Color(0.62, 0.64, 0.66), 0.6, 0.3)
	var pad_material := _material(Color(0.2, 0.2, 0.22), 0.9, 0.0)
	var window := StandardMaterial3D.new()
	window.albedo_color = Color(1.0, 0.85, 0.5)
	window.emission_enabled = true
	window.emission = Color(1.0, 0.8, 0.4)
	window.emission_energy_multiplier = 2.5
	var base_height := ground_offset(planet, instance, 0.0, 0.0)
	var pad := CylinderMesh.new()
	pad.top_radius = 20.0
	pad.bottom_radius = 20.0
	pad.height = 0.6
	_mesh(root, pad, pad_material, Vector3(0, base_height + 0.2, 0))
	for building_index in 3:
		var angle := (float(building_index) / 3.0 + rng.next_float() * 0.2) * TAU
		var local_x := cos(angle) * 30.0
		var local_z := sin(angle) * 30.0
		var ground := ground_offset(planet, instance, local_x, local_z)
		var building_size := Vector3(9.0 + rng.next_float() * 5.0, 5.0 + rng.next_float() * 3.0, 8.0 + rng.next_float() * 5.0)
		var yaw := rad_to_deg(angle)
		_box(root, building_size, wall, Vector3(local_x, ground + building_size.y * 0.5, local_z), Vector3(0, yaw, 0))
		_box(root, Vector3(building_size.x * 0.8, 0.6, building_size.z + 0.1), window, Vector3(local_x, ground + building_size.y * 0.65, local_z), Vector3(0, yaw, 0))
	var mast := CylinderMesh.new()
	mast.top_radius = 0.2
	mast.bottom_radius = 0.35
	mast.height = 18.0
	_mesh(root, mast, wall, Vector3(0, base_height + 9.0, 0))


static func _box(parent: Node3D, size: Vector3, material: Material, local_position: Vector3, rotation_degrees_value: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := _mesh(parent, mesh, material, local_position)
	node.rotation_degrees = rotation_degrees_value


static func _mesh(parent: Node3D, mesh: Mesh, material: Material, local_position: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = local_position
	parent.add_child(node)
	return node


static func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material
