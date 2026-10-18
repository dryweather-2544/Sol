class_name ShipVisuals
extends Node3D
## Builds the placeholder ship from the interior layout (so the walls you see are the walls you
## walk between) and animates the doors and ramp from the ship's systems. Nose points to -z.

var ship: Ship
var _door_nodes := {}   # portal id -> {node: MeshInstance3D, base_y: float}
var _room_lights := {} # room id -> OmniLight3D
var _fire_nodes := {}   # room id -> MeshInstance3D
var _station_screens := {} # station id -> StandardMaterial3D (emission shows the station's state)
var _smoke_nodes := {}    # room id -> CPUParticles3D
var _scorch_decals := {}  # room id -> Decal, hidden until the room has had a fire this session (not saved: saves may not change in N9)
var _turret_pivot := Node3D.new()
var _ramp_pivot := Node3D.new()
var _ramp_mesh := MeshInstance3D.new()

var _hull_material := _material(Color(0.55, 0.6, 0.68), 0.55, 0.35)
var _floor_material := _material(Color(0.25, 0.27, 0.3), 0.8, 0.1)
var _accent_material := _material(Color(0.9, 0.35, 0.1), 0.6, 0.2)
var _door_material: Material = AssetLibrary.material_or("mat_ship_brushed_metal", _material(Color(0.75, 0.78, 0.82), 0.4, 0.5))
var _glow_material := _emissive(Color(0.3, 0.7, 1.0), 3.0)
var _panel_material := _emissive(Color(0.2, 1.0, 0.5), 2.5)
# N9: textured versions of the roles above. Each falls back to its code material when the asset is missing or GameSettings.asset_materials
# is off, so the original look is always one switch away. Interiors and exterior hull plating share boxes, so walls use the paint panel.
var _wall_material: Material = AssetLibrary.material_or("mat_ship_paint_panel", _hull_material)
var _exterior_material: Material = AssetLibrary.material_or("mat_hull_plating", _hull_material)
var _floor_slab_material: Material = AssetLibrary.material_or("mat_ship_floor_plate", _floor_material)
var _rubber_floor_material: Material = AssetLibrary.material_or("mat_ship_rubber_mat", _floor_slab_material)
var _console_material: Material = AssetLibrary.material_or("mat_ship_composite_dark", _floor_material)
var _metal_material: Material = AssetLibrary.material_or("mat_ship_brushed_metal", _floor_material)
var _nozzle_material: Material = AssetLibrary.material_or("mat_hull_nozzle", _glow_material)


func _ready() -> void:
	var layout := ship.systems.layout
	_build_floors_and_ceilings(layout)
	_build_walls(layout)
	_build_doors(layout)
	_build_seat_and_console(layout)
	_build_panels(layout)
	_build_exterior_extras(layout)
	_build_ramp(layout)
	_build_turret()
	_build_lights(layout)
	if _wall_material != _hull_material:
		_build_reflection_probe(layout)
	_build_decals(layout)


func _process(_delta: float) -> void:
	var layout := ship.systems.layout
	for portal_id in _door_nodes:
		var portal: Portal = layout.portals[portal_id]
		var record: Dictionary = _door_nodes[portal_id]
		(record["node"] as Node3D).position.y = record["base_y"] + portal.open_factor * 2.3
	var aim := ship.systems.turret.aim_local
	if aim.length() > 0.5:
		_turret_pivot.basis = Basis.looking_at(aim, Vector3.UP if absf(aim.y) < 0.99 else Vector3.FORWARD)
	var hazards := ship.systems.hazards
	var flicker := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)
	for room_id in _fire_nodes:
		var intensity := hazards.fire_in(room_id)
		if intensity > 0.0 and _scorch_decals.has(room_id):
			(_scorch_decals[room_id] as Decal).visible = true
		(_fire_nodes[room_id] as Node3D).visible = intensity > 0.0
		(_smoke_nodes[room_id] as CPUParticles3D).emitting = intensity > 0.0
		(_fire_nodes[room_id] as Node3D).scale = Vector3.ONE * (0.4 + 0.8 * intensity) * (0.9 + 0.2 * flicker)
		var light: OmniLight3D = _room_lights[room_id]
		light.light_color = Color(1.0, 0.35 + 0.2 * flicker, 0.2) if intensity > 0.0 else Color.WHITE
		light.light_energy = 1.6 + 2.0 * intensity if intensity > 0.0 else 1.6
	_update_screens()
	var walkway := ship.systems.walkway
	_ramp_pivot.visible = walkway.progress > 0.0
	_ramp_mesh.scale.z = maxf(walkway.progress, 0.001)
	var drop := layout.floor_y - layout.ramp_end_y
	_ramp_pivot.rotation.x = asin(clampf(drop / layout.ramp_rect.size.y, -0.9, 0.9))


func _build_floors_and_ceilings(layout: InteriorLayout) -> void:
	for room_id in layout.rooms:
		var room: Rect2 = layout.rooms[room_id]
		var rubber_floor: bool = room_id == &"airlock" or room_id == &"cargo"
		_slab(room, layout.floor_y - 0.12, layout.floor_y, _rubber_floor_material if rubber_floor else _floor_slab_material)
		_slab(room, layout.ceiling_y, layout.ceiling_y + 0.12, _wall_material)
	for portal in layout.portals.values():
		_slab((portal as Portal).opening, layout.floor_y - 0.12, layout.floor_y, _floor_slab_material)
		_slab((portal as Portal).opening, layout.ceiling_y, layout.ceiling_y + 0.12, _wall_material)


## Walls are the 0.2 m skin just outside each room rectangle, with gaps where a portal opening crosses it.
## The cockpit's nose wall is glass.
func _build_walls(layout: InteriorLayout) -> void:
	var bottom := layout.floor_y
	var top := layout.ceiling_y
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.5, 0.7, 0.9, 0.2)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	var glass_material: Material = AssetLibrary.material_or("mat_ship_glass", glass)
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
				_wall_box(wall.position.x, wall.end.x, wall.position.y, wall.end.y, bottom, top, glass_material)
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
		if portal.kind == Portal.Kind.AIRLOCK_OUTER:
			instance.set_meta(ExteriorHull.SHARED_META, true) # the outer door is seen from outside too
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
	var console := _box_instance(Vector3(2.4, 0.9, 0.6), _console_material)
	console.position = Vector3(0, layout.floor_y + 0.45, -6.5)
	add_child(console)
	var nav_material: Material = AssetLibrary.material_copy_or("mat_ship_screen_nav", _glow_material)
	if nav_material != _glow_material and nav_material is StandardMaterial3D:
		(nav_material as StandardMaterial3D).albedo_color = Color(0.3, 0.7, 1.0) # the tint contract: albedo_color AND emission carry the state colour
		(nav_material as StandardMaterial3D).emission = Color(0.3, 0.7, 1.0)
	var screen := _box_instance(Vector3(2.2, 0.05, 0.5), nav_material)
	screen.position = Vector3(0, layout.floor_y + 0.92, -6.5)
	add_child(screen)


func _build_panels(layout: InteriorLayout) -> void:
	for point in layout.interact_points:
		if layout.seats.has(point["id"]):
			continue
		if point["id"] in [&"reactor_panel", &"engine_station"]:
			# A wall screen that shows the station's state (see _update_screens).
			var screen_material := _emissive(Color(0.2, 1.0, 0.5), 2.0)
			# Reactor screen = west wall (+x face shows), generic = east wall (-x face): the layout puts the reactor panel at x = -2.7 and
			# the engine station at x = +2.7, which is what the assets were authored for (mat_ship_screen SOURCE.md).
			var asset_screen := AssetLibrary.material_copy_or("mat_ship_screen_reactor" if point["id"] == &"reactor_panel" else "mat_ship_screen_generic", null)
			if asset_screen is StandardMaterial3D:
				screen_material = asset_screen as StandardMaterial3D
			var screen := _box_instance(Vector3(0.06, 0.55, 0.8), screen_material)
			var wall_side := 1.0 if point["position"].x > 0.0 else -1.0
			# The wall skin is 0.2 m thick with its inner face 0.3 m behind the panel point, so the old offset of 0.42 put this 0.06 m box
			# inside the wall (hidden). 0.27 puts its back flush with the wall face and its front 0.06 m proud of it.
			screen.position = point["position"] + Vector3(wall_side * 0.27, 1.1, 0)
			add_child(screen)
			_station_screens[point["id"]] = screen_material
			continue
		var panel := _box_instance(Vector3(0.25, 0.35, 0.08), _panel_material)
		panel.position = point["position"] + Vector3(0, 1.1, 0)
		add_child(panel)


func _build_exterior_extras(layout: InteriorLayout) -> void:
	for side in [-1.0, 1.0]:
		var wing := _box_instance(Vector3(4.6, 0.15, 3.4), _exterior_material)
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
		nacelle.material_override = _nozzle_material
		if _nozzle_material != _glow_material:
			nacelle.add_child(_exhaust_disc())
		nacelle.rotation_degrees = Vector3(90, 0, 0)
		nacelle.position = Vector3(side * 2.4, -0.3, 9.3)
		add_child(nacelle)
		var gear := _box_instance(Vector3(0.3, 1.2, 0.3), _metal_material)
		gear.position = Vector3(side * 2.6, -1.4, 8.5)
		add_child(gear)
		var gear_front := _box_instance(Vector3(0.3, 1.2, 0.3), _metal_material)
		gear_front.position = Vector3(side * 2.6, -1.4, -5.0)
		add_child(gear_front)
	var fin := _box_instance(Vector3(0.2, 1.6, 2.2), _accent_material)
	fin.position = Vector3(0, ship.systems.layout.ceiling_y + 0.9, 6.0)
	add_child(fin)


## Station screens: reactor green -> red with core heat (dark when tripped); engine screen red -> green with engine health.
func _update_screens() -> void:
	var systems := ship.systems
	if _station_screens.has(&"reactor_panel"):
		var material: StandardMaterial3D = _station_screens[&"reactor_panel"]
		var shade := Color(0.15, 0.15, 0.15) if systems.power.is_shut_down() else Color(0.2, 1.0, 0.5).lerp(Color(1.0, 0.2, 0.1), clampf(systems.power.temperature, 0.0, 1.0))
		material.albedo_color = shade
		material.emission = shade
	if _station_screens.has(&"engine_station"):
		var material: StandardMaterial3D = _station_screens[&"engine_station"]
		var shade := Color(1.0, 0.2, 0.1).lerp(Color(0.2, 1.0, 0.5), systems.subsystems.value(ShipSubsystems.Id.ENGINES))
		material.albedo_color = shade
		material.emission = shade


## The dorsal gun above the turret room; the barrel follows ShipTurret's aim.
func _build_turret() -> void:
	_turret_pivot.position = ship.systems.turret.muzzle_offset - Vector3(0, 0.15, 0)
	add_child(_turret_pivot)
	var base := _box_instance(Vector3(0.7, 0.3, 0.7), _metal_material)
	base.position = Vector3(0, -0.05, 0)
	_turret_pivot.add_child(base)
	var barrel := _box_instance(Vector3(0.14, 0.14, 1.1), _accent_material)
	barrel.position = Vector3(0, 0.1, -0.6)
	_turret_pivot.add_child(barrel)


func _build_ramp(layout: InteriorLayout) -> void:
	_ramp_pivot.position = Vector3(layout.ramp_rect.position.x + layout.ramp_rect.size.x * 0.5, layout.floor_y - 0.04, layout.ramp_rect.position.y)
	add_child(_ramp_pivot)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(layout.ramp_rect.size.x, 0.08, layout.ramp_rect.size.y)
	_ramp_mesh.mesh = mesh
	_ramp_mesh.material_override = _door_material
	_ramp_mesh.set_meta(ExteriorHull.SHARED_META, true) # the player walks down it
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
			var smoke := CPUParticles3D.new()
			smoke.position = flames.position + Vector3(0, 0.4, 0)
			smoke.amount = 28
			smoke.lifetime = 1.6
			smoke.direction = Vector3.UP
			smoke.spread = 25.0
			smoke.initial_velocity_min = 0.6
			smoke.initial_velocity_max = 1.2
			smoke.gravity = Vector3.ZERO
			var puff := SphereMesh.new()
			puff.radius = 0.12
			puff.height = 0.24
			smoke.mesh = puff
			smoke.material_override = _emissive(Color(1.0, 0.55, 0.15), 3.0)
			smoke.emitting = false
			add_child(smoke)
			_smoke_nodes[room_id] = smoke


## Decals from the Sol-Assets sets: room names above the doors, hazard stripes at the airlock and reactor, station IDs on the walls, and
## hidden scorch marks that appear in a room once it has burned. Positions come from the layout, never from hard-coded numbers.
func _build_decals(layout: InteriorLayout) -> void:
	if not GameSettings.instance().decals:
		return
	var plate_height := layout.floor_y + 2.3 # the lintel above a 2.1 m door spans 2.1 m up to the ceiling
	# [decal, door, true = the wall face on the door's tail side (looks toward +z, into the room behind the door)]
	var plates := [["room_cockpit", &"cockpit_door", false], ["room_cabin", &"cockpit_door", true], ["room_engineering", &"engineering_door", true],
		["room_turret", &"turret_door", true], ["room_cargo", &"cargo_door", true], ["room_airlock", &"airlock_inner", true]]
	for plate in plates:
		var opening: Rect2 = (layout.portals[plate[1]] as Portal).opening
		var tail_side: bool = plate[2]
		var wall_z := opening.end.y if tail_side else opening.position.y
		_add_decal("dec_ship_markings", plate[0], Vector3(opening.get_center().x, plate_height, wall_z), _wall_decal_basis(Vector3(0, 0, 1) if tail_side else Vector3(0, 0, -1)))
	var airlock_door: Rect2 = (layout.portals[&"airlock_inner"] as Portal).opening
	for offset_x in [-0.5, 0.5]:
		_add_decal("dec_ship_markings", "hazard_stripe", Vector3(airlock_door.get_center().x + offset_x, layout.floor_y, airlock_door.get_center().y), Basis.IDENTITY)
	var station_ids := {&"reactor_panel": "id_reactor", &"engine_station": "id_engine", &"repair_panel": "id_repair", &"workbench": "id_workbench", &"extinguisher_locker": "id_extinguisher"}
	for point in layout.interact_points:
		if not station_ids.has(point["id"]):
			continue
		var position: Vector3 = point["position"]
		for room_id in layout.rooms:
			var rect: Rect2 = layout.rooms[room_id]
			if not rect.has_point(Vector2(position.x, position.z)):
				continue
			var on_west_wall := position.x < rect.get_center().x
			var wall_x := rect.position.x if on_west_wall else rect.end.x
			_add_decal("dec_ship_markings", station_ids[point["id"]], Vector3(wall_x, layout.floor_y + 1.5, position.z), _wall_decal_basis(Vector3.RIGHT if on_west_wall else Vector3.LEFT))
			if point["id"] == &"reactor_panel":
				_add_decal("dec_ship_markings", "hazard_stripe", Vector3(position.x + 0.4, layout.floor_y, position.z), Basis(Vector3.UP, PI * 0.5))
	var scorch_index := 0
	for room_id in layout.rooms:
		if not ship.systems.hazards.has_room(room_id):
			continue
		var rect: Rect2 = layout.rooms[room_id]
		var scorch := _add_decal("dec_ship_damage", "scorch_01" if scorch_index % 2 == 0 else "scorch_02", Vector3(rect.get_center().x, layout.floor_y, rect.get_center().y), Basis.IDENTITY)
		scorch_index += 1
		if scorch != null:
			scorch.visible = false
			_scorch_decals[room_id] = scorch


## A Decal projects along its local -y with the texture's top at local -z. For a vertical wall the basis is: local y = the wall normal
## (toward the viewer), local -z = up, local x = the viewer's right.
static func _wall_decal_basis(normal: Vector3) -> Basis:
	var right := -normal.cross(Vector3.UP).normalized()
	return Basis(right, normal, -Vector3.UP)


## Adds one catalogue decal at `center`, or returns null (decal skipped, logged once) when its texture is missing.
func _add_decal(set_id: String, decal_name: String, center: Vector3, orientation: Basis) -> Decal:
	var entry: Dictionary = DecalCatalog.SETS[set_id][decal_name]
	var albedo := AssetLibrary.texture("decals/%s/%s_%s_albedo.png" % [set_id, set_id, decal_name])
	if albedo == null:
		return null
	var decal := Decal.new()
	decal.name = "Decal_" + decal_name
	decal.set_meta("catalog_name", decal_name) # the node name gets mangled to @Decal@N when two decals share it
	decal.size = Vector3(entry["size_x"], entry["depth"], entry["size_z"])
	decal.texture_albedo = albedo
	var maps: String = entry["maps"]
	if maps.contains("normal"):
		decal.texture_normal = AssetLibrary.texture("decals/%s/%s_%s_normal.png" % [set_id, set_id, decal_name])
	if maps.contains("orm"):
		decal.texture_orm = AssetLibrary.texture("decals/%s/%s_%s_orm.png" % [set_id, set_id, decal_name])
	decal.modulate = Color.html(entry["modulate"])
	decal.albedo_mix = entry["albedo_mix"]
	decal.transform = Transform3D(orientation, center)
	add_child(decal)
	return decal


## The nozzle texture covers the whole nacelle, so the engine glow becomes a thin emissive disc in the exhaust mouth: the cylinder's top
## cap (+y before the nacelle is rotated 90 degrees about x, which sends +y to +z, the rear).
func _exhaust_disc() -> MeshInstance3D:
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 0.5
	disc_mesh.bottom_radius = 0.5
	disc_mesh.height = 0.04
	var disc := MeshInstance3D.new()
	disc.mesh = disc_mesh
	disc.material_override = _glow_material
	disc.position = Vector3(0.0, 1.19, 0.0)
	return disc


## Bare metal (metallic 1) reflects the sky, which is black space, so the textured interior would render near-black. One interior
## probe over the ship, captured once, gives metal something to reflect.
func _build_reflection_probe(layout: InteriorLayout) -> void:
	var height := layout.ceiling_y - layout.floor_y
	var probe := ReflectionProbe.new()
	probe.size = Vector3(8.0, height + 0.5, 20.0)
	probe.position = Vector3(0.0, layout.floor_y + height * 0.5, 1.8)
	probe.interior = true
	probe.box_projection = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 0.6
	add_child(probe)


func _slab(area: Rect2, bottom_y: float, top_y: float, material: Material) -> void:
	var instance := _box_instance(Vector3(area.size.x, top_y - bottom_y, area.size.y), material)
	instance.position = Vector3(area.position.x + area.size.x * 0.5, (bottom_y + top_y) * 0.5, area.position.y + area.size.y * 0.5)
	add_child(instance)


func _wall_box(x_min: float, x_max: float, z_min: float, z_max: float, y_min: float, y_max: float, material: Material = null) -> void:
	var first_z := minf(z_min, z_max)
	var last_z := maxf(z_min, z_max)
	var instance := _box_instance(Vector3(x_max - x_min, y_max - y_min, last_z - first_z), material if material != null else _wall_material)
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
