class_name PoiBuilder
extends RefCounted
## Builds the placeholder scenery for a POI from its seed. Props sit on the real terrain height. All
## primitives, no third-party assets. Local axes: x/z along the ground, y = away from the planet.

const GROUND_SAMPLE_ARMS := 1
## Where the depot's entrance sits in the outpost's local x, z (it extends toward -z from here).
const DEPOT_ORIGIN := Vector2(-75.0, 0.0)
const DEPOT_FLOOR_LIFT := 0.25
## Where the one interaction of a minor site sits (local x, z), just outside its solid centre.
const MINOR_INTERACT_POINT := {PoiDefinition.Type.PROBE: Vector2(2.4, 0.0), PoiDefinition.Type.DEPOSIT: Vector2(4.0, 0.0), PoiDefinition.Type.ANOMALY: Vector2(3.0, 0.0)}


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
		PoiDefinition.Type.PROBE:
			circles.append(Vector3(0.0, 0.0, 1.4))
		PoiDefinition.Type.DEPOSIT:
			circles.append(Vector3(0.0, 0.0, 3.0))
		PoiDefinition.Type.ANOMALY:
			circles.append(Vector3(0.0, 0.0, 2.2))
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
		PoiDefinition.Type.PROBE, PoiDefinition.Type.DEPOSIT, PoiDefinition.Type.ANOMALY:
			positions.append(MINOR_INTERACT_POINT[instance.type])
		_:
			positions.append(Vector2(14.0, 0.0))
			positions.append(Vector2(-14.0, 6.0))
			positions.append(Vector2(2.0, -15.0))
			for depot_crate in instance.building().crate_positions():
				positions.append(DEPOT_ORIGIN + depot_crate)
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
		PoiDefinition.Type.PROBE:
			_build_probe(root, instance, planet, rng)
			return root
		PoiDefinition.Type.DEPOSIT:
			_build_deposit(root, instance, planet, rng)
			return root
		PoiDefinition.Type.ANOMALY:
			_build_anomaly(root, instance, planet, rng)
			return root
		_:
			_build_outpost(root, instance, planet, rng)
			_build_depot(root, instance, planet)
	var crate_material := _material(Color(0.8, 0.55, 0.15), 0.6, 0.3)
	var crate_index := 0
	for crate_position in crate_positions(instance):
		var crate_node := MeshInstance3D.new()
		var crate_mesh := BoxMesh.new()
		crate_mesh.size = Vector3(1.4, 1.0, 1.0)
		crate_node.mesh = crate_mesh
		crate_node.material_override = crate_material
		crate_node.name = "Crate%d" % crate_index
		var crate_ground := depot_floor_height(planet, instance) if is_in_depot(instance, crate_position.x, crate_position.y) else ground_offset(planet, instance, crate_position.x, crate_position.y)
		crate_node.position = Vector3(crate_position.x, crate_ground + 0.5, crate_position.y)
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
	var metal: Material = AssetLibrary.material_or("mat_hull_plating_derelict", _material(Color(0.28, 0.28, 0.3), 0.7, 0.6))
	var rust: Material = AssetLibrary.material_or("mat_poi_rusted_metal", _material(Color(0.45, 0.25, 0.12), 0.9, 0.2))
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


## A small emissive stake at the interaction point, so the spot to press F at is visible.
static func _interact_stake(root: Node3D, instance: PoiInstance, planet: PlanetBody, color: Color) -> void:
	var point: Vector2 = MINOR_INTERACT_POINT[instance.type]
	var ground := ground_offset(planet, instance, point.x, point.y)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = color
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = 3.0
	var pole := CylinderMesh.new()
	pole.top_radius = 0.04
	pole.bottom_radius = 0.06
	pole.height = 1.3
	_mesh(root, pole, _material(Color(0.3, 0.3, 0.32), 0.6, 0.6), Vector3(point.x, ground + 0.65, point.y))
	_box(root, Vector3(0.22, 0.12, 0.22), glow, Vector3(point.x, ground + 1.36, point.y), Vector3.ZERO)


## A crashed research probe: scorched body, bent dish, folded solar panels.
static func _build_probe(root: Node3D, instance: PoiInstance, planet: PlanetBody, rng: SeedRng) -> void:
	var hull: Material = AssetLibrary.material_or("mat_hull_plating_derelict", _material(Color(0.62, 0.62, 0.64), 0.5, 0.7))
	var panel_material := _material(Color(0.08, 0.1, 0.2), 0.3, 0.5)
	var scorch := _material(Color(0.12, 0.1, 0.09), 0.9, 0.2)
	var base_height := ground_offset(planet, instance, 0.0, 0.0)
	var yaw := rng.next_float() * 360.0
	var body := CylinderMesh.new()
	body.top_radius = 0.7
	body.bottom_radius = 0.9
	body.height = 1.6
	var body_node := _mesh(root, body, hull, Vector3(0, base_height + 0.6, 0))
	body_node.rotation_degrees = Vector3(rng.next_float() * 20.0 - 10.0, yaw, rng.next_float() * 20.0 - 10.0)
	_box(root, Vector3(1.9, 0.12, 1.9), scorch, Vector3(0, base_height + 0.05, 0), Vector3(0, yaw, 0))
	var dish := CylinderMesh.new()
	dish.top_radius = 1.1
	dish.bottom_radius = 0.2
	dish.height = 0.35
	var dish_node := _mesh(root, dish, hull, Vector3(0.6, base_height + 1.7, 0.2))
	dish_node.rotation_degrees = Vector3(30.0 + rng.next_float() * 30.0, yaw, 25.0)
	_box(root, Vector3(3.2, 0.06, 1.1), panel_material, Vector3(-1.8, base_height + 0.45, 0.6), Vector3(0, yaw, 14.0))
	_box(root, Vector3(2.4, 0.06, 1.1), panel_material, Vector3(1.3, base_height + 0.2, -1.4), Vector3(8.0, yaw + 40.0, -6.0))
	_interact_stake(root, instance, planet, Color(0.4, 0.85, 1.0))
	var light := OmniLight3D.new()
	light.position = Vector3(0.0, base_height + 2.0, 0.0)
	light.omni_range = 9.0
	light.light_energy = 0.7
	light.light_color = Color(0.5, 0.85, 1.0)
	root.add_child(light)


## An exposed ore body: a ring of angular rocks with a bright metallic seam.
static func _build_deposit(root: Node3D, instance: PoiInstance, planet: PlanetBody, rng: SeedRng) -> void:
	var rock := _material(Color(0.28, 0.26, 0.24), 0.95, 0.1)
	var ore := _material(Color(0.6, 0.48, 0.3), 0.4, 0.85)
	for rock_index in 7:
		var angle := rng.next_float() * TAU
		var distance := rng.next_float() * 2.0
		var local_x := cos(angle) * distance
		var local_z := sin(angle) * distance
		var size := 1.0 + rng.next_float() * 1.8
		var material: Material = ore if rock_index % 3 == 0 else rock
		_box(root, Vector3(size, size * (0.7 + rng.next_float() * 0.8), size * (0.7 + rng.next_float() * 0.6)), material,
			Vector3(local_x, ground_offset(planet, instance, local_x, local_z) + size * 0.3, local_z), Vector3(rng.next_float() * 30.0, rng.next_float() * 360.0, rng.next_float() * 30.0))
	_interact_stake(root, instance, planet, Color(1.0, 0.75, 0.25))


## A scientific anomaly: a ring of crystal spikes round a faintly glowing core.
static func _build_anomaly(root: Node3D, instance: PoiInstance, planet: PlanetBody, rng: SeedRng) -> void:
	var crystal := StandardMaterial3D.new()
	crystal.albedo_color = Color(0.35, 0.25, 0.5)
	crystal.roughness = 0.2
	crystal.metallic = 0.3
	crystal.emission_enabled = true
	crystal.emission = Color(0.5, 0.3, 0.9)
	crystal.emission_energy_multiplier = 0.8
	var core_material := StandardMaterial3D.new()
	core_material.albedo_color = Color(0.8, 0.6, 1.0)
	core_material.emission_enabled = true
	core_material.emission = Color(0.7, 0.45, 1.0)
	core_material.emission_energy_multiplier = 3.5
	var base_height := ground_offset(planet, instance, 0.0, 0.0)
	var spikes := 8
	for spike_index in spikes:
		if spike_index == 0:
			continue # leave a gap on the side the interaction point is on
		var angle := (float(spike_index) / float(spikes)) * TAU
		var local_x := cos(angle) * 2.2
		var local_z := sin(angle) * 2.2
		var spike_height := 1.8 + rng.next_float() * 2.2
		_box(root, Vector3(0.45, spike_height, 0.45), crystal, Vector3(local_x, ground_offset(planet, instance, local_x, local_z) + spike_height * 0.5, local_z),
			Vector3(rng.next_float() * 24.0 - 12.0, rng.next_float() * 360.0, rng.next_float() * 24.0 - 12.0))
	var core := SphereMesh.new()
	core.radius = 0.6
	core.height = 1.2
	_mesh(root, core, core_material, Vector3(0, base_height + 1.7, 0))
	_interact_stake(root, instance, planet, Color(0.75, 0.5, 1.0))
	var light := OmniLight3D.new()
	light.position = Vector3(0.0, base_height + 1.8, 0.0)
	light.omni_range = 14.0
	light.light_energy = 1.2
	light.light_color = Color(0.7, 0.45, 1.0)
	root.add_child(light)


static func _build_beacon(root: Node3D, instance: PoiInstance, planet: PlanetBody) -> void:
	var base_height := ground_offset(planet, instance, 0.0, 0.0)
	var concrete: Material = AssetLibrary.material_or("mat_poi_concrete", _material(Color(0.5, 0.5, 0.52), 0.9, 0.0))
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
	var wall: Material = AssetLibrary.material_or("mat_poi_concrete", _material(Color(0.62, 0.64, 0.66), 0.6, 0.3))
	var pad_material: Material = AssetLibrary.material_or("mat_poi_concrete", _material(Color(0.2, 0.2, 0.22), 0.9, 0.0))
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


## Height (relative to the POI's own ground point) of the depot's floor: above the highest ground under it,
## so terrain never pokes through.
static func depot_floor_height(planet: PlanetBody, instance: PoiInstance) -> float:
	var building := instance.building()
	var area := building.footprint()
	var highest := -INF
	for sample_x in 5:
		for sample_z in 5:
			var local_x := DEPOT_ORIGIN.x + area.position.x + area.size.x * sample_x / 4.0
			var local_z := DEPOT_ORIGIN.y + area.position.y + area.size.y * sample_z / 4.0
			highest = maxf(highest, ground_offset(planet, instance, local_x, local_z))
	return highest + DEPOT_FLOOR_LIFT


static func is_in_depot(instance: PoiInstance, local_x: float, local_z: float, margin: float = 0.0) -> bool:
	var building := instance.building()
	return building != null and building.footprint(margin).has_point(Vector2(local_x, local_z) - DEPOT_ORIGIN)


static func _build_depot(root: Node3D, instance: PoiInstance, planet: PlanetBody) -> void:
	var building := instance.building()
	var floor_height := depot_floor_height(planet, instance)
	var concrete: Material = AssetLibrary.material_or("mat_poi_concrete", _material(Color(0.55, 0.56, 0.58), 0.9, 0.0))
	var floor_material := _material(Color(0.22, 0.23, 0.25), 0.8, 0.1)
	var roof_material := _material(Color(0.4, 0.42, 0.45), 0.8, 0.2)
	var area := building.footprint()
	# Foundation block from below the ground up to the floor.
	var foundation_depth := 6.0
	_box_at(root, Rect2(DEPOT_ORIGIN + area.position, area.size), floor_height - foundation_depth, floor_height - 0.05, concrete)
	for room in building.rooms:
		var room_area := Rect2(DEPOT_ORIGIN + room.rect.position, room.rect.size)
		_box_at(root, room_area, floor_height - 0.1, floor_height, floor_material)
		_box_at(root, room_area, floor_height + PoiBuilding.WALL_HEIGHT, floor_height + PoiBuilding.WALL_HEIGHT + 0.3, roof_material)
		var light := OmniLight3D.new()
		light.position = Vector3(room_area.get_center().x, floor_height + 2.6, room_area.get_center().y)
		light.omni_range = maxf(room_area.size.x, room_area.size.y) * 1.1
		light.light_energy = 1.4
		root.add_child(light)
	for wall in building.walls:
		_box_at(root, Rect2(DEPOT_ORIGIN + wall.position, wall.size), floor_height, floor_height + PoiBuilding.WALL_HEIGHT, concrete)
	# Doorway lintels and the entrance sign light.
	for door in building.doorways:
		var door_rect: Rect2 = door["rect"]
		_box_at(root, Rect2(DEPOT_ORIGIN + door_rect.position, door_rect.size), floor_height + 2.5, floor_height + PoiBuilding.WALL_HEIGHT, concrete)
	var sign_material := StandardMaterial3D.new()
	sign_material.albedo_color = Color(0.3, 1.0, 0.5)
	sign_material.emission_enabled = true
	sign_material.emission = Color(0.3, 1.0, 0.5)
	sign_material.emission_energy_multiplier = 3.0
	_box_at(root, Rect2(DEPOT_ORIGIN + Vector2(-0.4, 0.3), Vector2(0.8, 0.2)), floor_height + 2.7, floor_height + 3.1, sign_material)


static func _box_at(parent: Node3D, area: Rect2, bottom_y: float, top_y: float, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(area.size.x, top_y - bottom_y, area.size.y)
	_mesh(parent, mesh, material, Vector3(area.get_center().x, (bottom_y + top_y) * 0.5, area.get_center().y))
