class_name ShipVisuals
extends Node3D
## Builds the placeholder ship from the interior layout (so the walls you see are the walls you
## walk between) and animates the doors and ramp from the ship's systems. Nose points to -z.

var ship: Ship
var _door_nodes := {}   # portal id -> {node: MeshInstance3D, base_y: float}
var _room_lights := {} # room id -> OmniLight3D
var _fire_nodes := {}   # room id -> MeshInstance3D
var _ramp_pivot := Node3D.new()
var _ramp_mesh := MeshInstance3D.new()

var _hull_material := _material(Color(0.55, 0.6, 0.68), 0.55, 0.35)
var _floor_material := _material(Color(0.25, 0.27, 0.3), 0.8, 0.1)
var _accent_material := _material(Color(0.9, 0.35, 0.1), 0.6, 0.2)
var _door_material := _material(Color(0.75, 0.78, 0.82), 0.4, 0.5)
var _glow_material := _emissive(Color(0.3, 0.7, 1.0), 3.0)
var _panel_material := _emissive(Color(0.2, 1.0, 0.5), 2.5)


func _ready() -> void:
	var layout := ship.systems.layout
	_build_floors_and_ceilings(layout)
	_build_walls(layout)
	_build_doors(layout)
	_build_seat_and_console(layout)
	_build_panels(layout)
	_build_exterior_extras(layout)
	_build_ramp(layout)
	_build_lights(layout)


func _process(_delta: float) -> void:
	var layout := ship.systems.layout
	for portal_id in _door_nodes:
		var portal: Portal = layout.portals[portal_id]
		var record: Dictionary = _door_nodes[portal_id]
		(record["node"] as Node3D).position.y = record["base_y"] + portal.open_factor * 2.3
	var hazards := ship.systems.hazards
	var flicker := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)
	for room_id in _fire_nodes:
		var intensity := hazards.fire_in(room_id)
		(_fire_nodes[room_id] as Node3D).visible = intensity > 0.0
		(_fire_nodes[room_id] as Node3D).scale = Vector3.ONE * (0.4 + 0.8 * intensity) * (0.9 + 0.2 * flicker)
		var light: OmniLight3D = _room_lights[room_id]
		light.light_color = Color(1.0, 0.35 + 0.2 * flicker, 0.2) if intensity > 0.0 else Color.WHITE
		light.light_energy = 1.6 + 2.0 * intensity if intensity > 0.0 else 1.6
	var walkway := ship.systems.walkway
	_ramp_pivot.visible = walkway.progress > 0.0
	_ramp_mesh.scale.z = maxf(walkway.progress, 0.001)
	var drop := layout.floor_y - layout.ramp_end_y
	_ramp_pivot.rotation.x = asin(clampf(drop / layout.ramp_rect.size.y, -0.9, 0.9))


func _build_floors_and_ceilings(layout: InteriorLayout) -> void:
	for room in layout.rooms.values():
		_slab(room, layout.floor_y - 0.12, layout.floor_y, _floor_material)
		_slab(room, layout.ceiling_y, layout.ceiling_y + 0.12, _hull_material)
	for portal in layout.portals.values():
		_slab((portal as Portal).opening, layout.floor_y - 0.12, layout.floor_y, _floor_material)
		_slab((portal as Portal).opening, layout.ceiling_y, layout.ceiling_y + 0.12, _hull_material)


## Walls are the 0.2 m skin just outside each room rectangle, with gaps where a portal opening crosses it.
## The cockpit's nose wall is glass.
func _build_walls(layout: InteriorLayout) -> void:
	var bottom := layout.floor_y
	var top := layout.ceiling_y
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.5, 0.7, 0.9, 0.2)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	var thickness := 0.2
	for room_id in layout.rooms:
		var room: Rect2 = layout.rooms[room_id]
		var walls := {
			"nose": [Rect2(room.position.x - thickness, room.position.y - thickness, room.size.x + 2.0 * thickness, thickness), true],
			"tail": [Rect2(room.position.x - thickness, room.end.y, room.size.x + 2.0 * thickness, thickness), true],
			"left": [Rect2(room.position.x - thickness, room.position.y, thickness, room.size.y), false],
			"right": [Rect2(room.end.x, room.position.y, thickness, room.size.y), false]}
		for side in walls:
			var wall: Rect2 = walls[side][0]
			var runs_along_x: bool = walls[side][1]
			if room_id == &"cockpit" and side == "nose":
				_wall_box(wall.position.x, wall.end.x, wall.position.y, wall.end.y, bottom, top, glass)
				continue
			_wall_with_portal_gaps(layout, wall, runs_along_x, bottom, top)


func _wall_with_portal_gaps(layout: InteriorLayout, wall: Rect2, runs_along_x: bool, bottom: float, top: float) -> void:
	var start := wall.position.x if runs_along_x else wall.position.y
	var finish := wall.end.x if runs_along_x else wall.end.y
	var gaps: Array = []
	for portal in layout.portals.values():
		var opening: Rect2 = (portal as Portal).opening
		if opening.intersects(wall):
			gaps.append(Vector2(opening.position.x, opening.end.x) if runs_along_x else Vector2(opening.position.y, opening.end.y))
	gaps.sort_custom(func(first: Vector2, second: Vector2) -> bool: return first.x < second.x)
	var cursor := start
	for gap in gaps:
		_wall_span(wall, runs_along_x, cursor, gap.x, bottom, top)
		_wall_span(wall, runs_along_x, gap.x, gap.y, bottom + 2.1, top) # lintel above the door
		cursor = gap.y
	_wall_span(wall, runs_along_x, cursor, finish, bottom, top)


func _wall_span(wall: Rect2, runs_along_x: bool, from_value: float, to_value: float, y_min: float, y_max: float) -> void:
	if to_value - from_value < 0.001:
		return
	if runs_along_x:
		_wall_box(from_value, to_value, wall.position.y, wall.end.y, y_min, y_max)
	else:
		_wall_box(wall.position.x, wall.end.x, from_value, to_value, y_min, y_max)


func _build_doors(layout: InteriorLayout) -> void:
	for portal_id in layout.portals:
		var portal: Portal = layout.portals[portal_id]
		var opening := portal.opening
		var door_height := 2.1
		var base_y := layout.floor_y + door_height * 0.5
		var instance := _box_instance(Vector3(opening.size.x, door_height, opening.size.y * 0.9), _door_material)
		instance.position = Vector3(opening.position.x + opening.size.x * 0.5, base_y, opening.position.y + opening.size.y * 0.5)
		add_child(instance)
		_door_nodes[portal_id] = {"node": instance, "base_y": base_y}


func _build_seat_and_console(layout: InteriorLayout) -> void:
	for seat_id in layout.seats:
		var seat_position: Vector3 = layout.seats[seat_id]["position"]
		var behind := Vector3(0, 0, 0.38) if absf(layout.seats[seat_id]["facing_yaw"]) < 1.0 else Vector3(0, 0, -0.38)
		var seat := _box_instance(Vector3(0.7, 0.5, 0.7), _accent_material)
		seat.position = seat_position + Vector3(0, 0.25, 0)
		add_child(seat)
		var back := _box_instance(Vector3(0.7, 1.0, 0.12), _accent_material)
		back.position = seat_position + Vector3(0, 0.75, 0) + behind
		add_child(back)
	var console := _box_instance(Vector3(2.4, 0.9, 0.6), _floor_material)
	console.position = Vector3(0, layout.floor_y + 0.45, -6.5)
	add_child(console)
	var screen := _box_instance(Vector3(2.2, 0.05, 0.5), _glow_material)
	screen.position = Vector3(0, layout.floor_y + 0.92, -6.5)
	add_child(screen)


func _build_panels(layout: InteriorLayout) -> void:
	for point in layout.interact_points:
		if layout.seats.has(point["id"]):
			continue
		var panel := _box_instance(Vector3(0.25, 0.35, 0.08), _panel_material)
		panel.position = point["position"] + Vector3(0, 1.1, 0)
		add_child(panel)


func _build_exterior_extras(layout: InteriorLayout) -> void:
	for side in [-1.0, 1.0]:
		var wing := _box_instance(Vector3(4.6, 0.15, 3.4), _hull_material)
		wing.position = Vector3(side * 5.5, 0.1, 2.0)
		add_child(wing)
		var tip := _box_instance(Vector3(0.3, 0.3, 3.4), _accent_material if side < 0.0 else _material(Color(0.1, 0.8, 0.2), 0.6, 0.2))
		tip.position = Vector3(side * 7.8, 0.1, 2.0)
		add_child(tip)
		var engine := CylinderMesh.new()
		engine.top_radius = 0.55
		engine.bottom_radius = 0.65
		engine.height = 2.4
		var nacelle := MeshInstance3D.new()
		nacelle.mesh = engine
		nacelle.material_override = _glow_material
		nacelle.rotation_degrees = Vector3(90, 0, 0)
		nacelle.position = Vector3(side * 2.4, -0.3, 9.3)
		add_child(nacelle)
		var gear := _box_instance(Vector3(0.3, 1.2, 0.3), _floor_material)
		gear.position = Vector3(side * 2.6, -1.4, 8.5)
		add_child(gear)
		var gear_front := _box_instance(Vector3(0.3, 1.2, 0.3), _floor_material)
		gear_front.position = Vector3(side * 2.6, -1.4, -5.0)
		add_child(gear_front)
	var fin := _box_instance(Vector3(0.2, 1.6, 2.2), _accent_material)
	fin.position = Vector3(0, ship.systems.layout.ceiling_y + 0.9, 6.0)
	add_child(fin)


func _build_ramp(layout: InteriorLayout) -> void:
	_ramp_pivot.position = Vector3(layout.ramp_rect.position.x + layout.ramp_rect.size.x * 0.5, layout.floor_y - 0.04, layout.ramp_rect.position.y)
	add_child(_ramp_pivot)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(layout.ramp_rect.size.x, 0.08, layout.ramp_rect.size.y)
	_ramp_mesh.mesh = mesh
	_ramp_mesh.material_override = _door_material
	_ramp_mesh.position = Vector3(0, 0, layout.ramp_rect.size.y * 0.5)
	_ramp_pivot.add_child(_ramp_mesh)
	_ramp_pivot.visible = false


func _build_lights(layout: InteriorLayout) -> void:
	for room_id in layout.rooms:
		var rect: Rect2 = layout.rooms[room_id]
		var light := OmniLight3D.new()
		light.position = Vector3(rect.get_center().x, 1.3, rect.get_center().y)
		light.omni_range = 5.5
		light.light_energy = 1.6
		light.shadow_enabled = false
		add_child(light)
		_room_lights[room_id] = light
		if ship.systems.hazards.has_room(room_id):
			var flames := _box_instance(Vector3(0.9, 1.0, 0.9), _emissive(Color(1.0, 0.45, 0.1), 4.0))
			flames.position = Vector3((rect as Rect2).get_center().x, layout.floor_y + 0.5, (rect as Rect2).get_center().y)
			flames.visible = false
			add_child(flames)
			_fire_nodes[room_id] = flames


func _slab(area: Rect2, bottom_y: float, top_y: float, material: Material) -> void:
	var instance := _box_instance(Vector3(area.size.x, top_y - bottom_y, area.size.y), material)
	instance.position = Vector3(area.position.x + area.size.x * 0.5, (bottom_y + top_y) * 0.5, area.position.y + area.size.y * 0.5)
	add_child(instance)


func _wall_box(x_min: float, x_max: float, z_min: float, z_max: float, y_min: float, y_max: float, material: Material = null) -> void:
	var first_z := minf(z_min, z_max)
	var last_z := maxf(z_min, z_max)
	var instance := _box_instance(Vector3(x_max - x_min, y_max - y_min, last_z - first_z), material if material != null else _hull_material)
	instance.position = Vector3((x_min + x_max) * 0.5, (y_min + y_max) * 0.5, (first_z + last_z) * 0.5)
	add_child(instance)


func _box_instance(size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	return instance


static func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


static func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material
