class_name ShipVisuals
extends Node3D
## Builds the ship from the interior layout (so the walls you see inside are the walls you walk
## between), wraps it in the exterior hull (ShipExterior) and animates the doors, ramp and turret
## from the ship's systems. Nose points to -z.

var ship: Ship
var _door_nodes := {}   # portal id -> {leaves: [{node, axis (0 = x, 2 = z), base, travel}], light: StandardMaterial3D}
var _room_lights := {} # room id -> OmniLight3D (the first lamp of the room)
var _room_extra_lights := {} # room id -> Array[OmniLight3D] (the other lamps of a long room)
var _light_share := {} # room id -> each lamp's share of the room's energy
var _fixture_materials := {} # room id -> StandardMaterial3D of the ceiling panels (glow follows the lamp colour)
var _trim_materials := {} # room id -> StandardMaterial3D of the skirting and cove
var _fire_nodes := {}   # room id -> MeshInstance3D
var _interior_base := {} # interior material -> untinted albedo (restyle)
var _airlock_screen_material: StandardMaterial3D
var _machine_screen_materials := {}
var _station_screens := {} # station id -> StandardMaterial3D (emission shows the station's state)
var _smoke_nodes := {}    # room id -> CPUParticles3D
var _scorch_decals := {}  # room id -> Decal, hidden until the room has had a fire this session (not saved: saves may not change in N9)
var exterior := ShipExterior.new()
## The detail pass over the rooms (panelling, ceiling ribs, pipes, hatches, screen graphics): src/interior/interior_detail.gd.
var detail := InteriorDetail.new()
## Rodina-style plumes and entry heat (hidden in the sol style).
var effects := ShipEffects.new()
## Doors slide sideways (+x) into the wall beside the opening; sliding up would push them out through the roof.
const DOOR_SLIDE := 1.45
const EMERGENCY_RED := Color(0.9, 0.2, 0.2)
## Hull fraction under which the lamps pulse red (the hull alarm sounds at the same 25 %).
const HULL_ALERT_BELOW := 0.25
## Photo tools only (tools/ship_shots.gd): show the flight pose (pods level) while parked.
var force_pods_level := false
## Bigger on the inside (ADR 0012): everything drawn in the layout's pocket rooms lives under `pocket`, the exterior's
## hull pieces in `_hull_nodes`. Which of them a camera draws is decided by render layers and that camera's cull mask
## (ADR 0013), never by hiding nodes: every piece of the ship stays visible in the scene tree all the time.
var pocket := Node3D.new()
var _hull_nodes: Array[Node3D] = []
var _end_nodes: Array[Node3D] = [] # the hull's nose and tail pieces (LAYER_ENDS)
## The outward-facing shell of the threshold rooms (cockpit, airlock): their side walls, floors and ceilings. Seen from a pocket room's
## window it would show as a bare box, so a camera in a pocket room leaves it out unless a door joins that room to a pocket room and is open.
var _shell_nodes := {} # room id -> Array[Node3D]
var _camera_in_pocket := false
## Render layers (VisualInstance3D.layers / Camera3D.cull_mask bits). Layer 1 stays the world and everything else.
const LAYER_POCKET := 1 << 1  # layer 2: the pocket rooms (geometry, lamps, decals, fire)
const LAYER_HULL := 1 << 2    # layer 3: the middle of the exterior hull (between the nose and the tail), pods and turret
const LAYER_ENDS := 1 << 5    # layer 6: the nose (canopy, cockpit end of the hull) and the tail (loading face, ramp): never inside a pocket room
## The hull's end pieces are cut from the middle at these ship-local z values (a hull station at the cockpit's rear and one inside the airlock),
## so the nose and tail can be drawn from inside the ship without the plating of the middle showing through the bigger rooms.
const HULL_NOSE_END_Z := -3.79
const HULL_TAIL_START_Z := 8.29
const SHELL_LAYERS := {&"cockpit": 1 << 3, &"airlock": 1 << 4} # layers 4, 5: each threshold room's outward shell
const ALL_LAYERS := 0xFFFFF
var _build_target: Node3D = self # where the builders below put what they make
## The game session (main sets it; null in tests): the scanners screen reads its pulse cooldown from here.
var session: Object = null
## Readable status text on the machine screens (PULSAR's lesson: the ship tells you its state where the machine is).
var _screen_labels := {} # screen id -> Label3D
var _label_timer := 0.0
## Engineering's reactor core (InteriorLayout.reactor_core), lit from ShipPower.
var _reactor_core_material: StandardMaterial3D
var _reactor_conduit_material: StandardMaterial3D
var _reactor_light: OmniLight3D
const SCREEN_FONT := "res://assets/sol/fonts/Michroma-Regular.ttf"
const GEAR_NAMES := ["DOCK", "COMBAT", "CRUISE", "WARP"]

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
var _living_floor_material := _material(Color(0.32, 0.24, 0.18), 0.8, 0.05) # warm dark decking in the living area
var _medical_floor_material := _material(Color(0.72, 0.82, 0.8), 0.35, 0.1)  # clean pale floor in the med bay
var _frame_material := _material(Color(0.2, 0.21, 0.24), 0.5, 0.6)
var _window_glass_material := _make_window_glass()
var _nozzle_material: Material = AssetLibrary.material_or("mat_hull_nozzle", _glow_material)


func _ready() -> void:
	var layout := ship.systems.layout
	pocket.name = "Pocket"
	add_child(pocket)
	_build_floors_and_ceilings(layout)
	_build_walls(layout)
	_build_doors(layout)
	_build_seat_and_console(layout)
	_build_panels(layout)
	_build_furniture(layout)
	_build_reactor(layout)
	_build_screen_labels(layout)
	var before := get_child_count()
	exterior.build(self, layout, ship.systems.turret.muzzle_offset, _nozzle_material, _exhaust_disc)
	for index in range(before, get_child_count()):
		var piece := get_child(index) as Node3D
		if piece.name == &"HullStatic":
			_split_hull_static(piece as MeshInstance3D)
		elif piece.name == &"HullNose" or String(piece.name).begins_with("Ramp") or (piece.position.z >= 10.5 and not String(piece.name).begins_with("Nozzle") and not String(piece.name).begins_with("Pod")):
			_end_nodes.append(piece) # the canopy and the ramp lie outside every room, so they are drawn from inside too
		else:
			_hull_nodes.append(piece) # the middle of the hull (and the pods, which lie inside the bigger cargo room) is drawn from outside only
	add_child(effects)
	effects.setup(exterior.nacelles())
	_build_lights(layout)
	detail.build(self, layout)
	restyle()
	if _wall_material != _hull_material:
		_build_reflection_probe(layout)
	_build_decals(layout)
	_assign_layers()


func _process(delta: float) -> void:
	var layout := ship.systems.layout
	for portal_id in _door_nodes:
		var portal: Portal = layout.portals[portal_id]
		var record: Dictionary = _door_nodes[portal_id]
		for leaf in record["leaves"]:
			var leaf_node := leaf["node"] as Node3D
			var leaf_position := leaf_node.position
			leaf_position[leaf["axis"]] = leaf["base"] + portal.open_factor * leaf["travel"]
			leaf_node.position = leaf_position
		_update_door_light(layout, portal, record["light"])
	var aim := ship.systems.turret.aim_local
	if aim.length() > 0.5:
		exterior.turret_pivot.basis = Basis.looking_at(aim, Vector3.UP if absf(aim.y) < 0.99 else Vector3.FORWARD)
	var hazards := ship.systems.hazards
	var flicker := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)
	for room_id in _fire_nodes:
		var intensity := hazards.fire_in(room_id)
		if intensity > 0.0 and _scorch_decals.has(room_id):
			(_scorch_decals[room_id] as Decal).visible = true
		(_fire_nodes[room_id] as Node3D).visible = intensity > 0.0
		(_smoke_nodes[room_id] as CPUParticles3D).emitting = intensity > 0.0
		(_fire_nodes[room_id] as Node3D).scale = Vector3.ONE * (0.4 + 0.8 * intensity) * (0.9 + 0.2 * flicker)
		var base := VisualStyle.room_light(room_id)
		_apply_room_light(room_id, Color(1.0, 0.35 + 0.2 * flicker, 0.2) if intensity > 0.0 else base["color"],
			base["energy"] + 2.0 * intensity if intensity > 0.0 else base["energy"])
	_update_room_alert(hazards)
	_update_screens()
	_update_reactor()
	_label_timer -= delta
	if _label_timer <= 0.0:
		_label_timer = 0.25 # text changes four times a second, not every frame
		_update_screen_labels()
	var drop := layout.floor_y - layout.ramp_end_y
	var low_and_slow := ship.planet != null and (ship.state.landed or (ship.state.altitude_above_ground < 80.0 and ship.state.speed() < 30.0))
	var command := ship.last_command
	exterior.update_pods(low_and_slow and not force_pods_level, 0.0 if force_pods_level else delta, command.thrust)
	var demand := 1.0 if command.boost else minf(command.thrust.length(), 1.0)
	if VisualStyle.is_rodina():
		# Rodina's main engine burns for forward thrust only; reverse and strafing fire the thruster jets (ShipEffects).
		demand = clampf(-command.thrust.z, 0.0, 1.0)
	exterior.update_exhaust(demand, delta)
	effects.update_effects(ship, delta)
	exterior.update_ramp(ship.systems.walkway.progress, asin(clampf(drop / layout.ramp_rect.size.y, -0.9, 0.9)))


## Alert lighting for rooms that are not on fire (burning rooms keep the fire light above): a reactor shutdown drops the lamps
## to a dim pulsing emergency red (Rodina's CeilingLightEmergency colour); a badly damaged hull pulses the normal lamps red.
func _update_room_alert(hazards: ShipHazards) -> void:
	var blackout := ship.systems.power.is_shut_down()
	var hull_low := ship.state.hull > 0.0 and ship.state.hull < HULL_ALERT_BELOW
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
	for room_id in _room_lights:
		if _fire_nodes.has(room_id) and hazards.fire_in(room_id) > 0.0:
			continue
		var base := VisualStyle.room_light(room_id)
		var colour: Color = base["color"]
		var energy: float = base["energy"]
		if blackout:
			colour = EMERGENCY_RED
			energy *= 0.25 + 0.15 * pulse
		elif hull_low:
			colour = colour.lerp(EMERGENCY_RED, 0.35 + 0.45 * pulse)
			energy *= 0.75 + 0.25 * pulse
		_apply_room_light(room_id, colour, energy)


## Applies the visual style to the interior (materials tinted in place from their stored base colour, room lights) and
## the exterior. Called once built and again on a style switch.
func restyle() -> void:
	exterior.restyle()
	var tint := VisualStyle.interior_tint()
	for material in [_wall_material, _floor_slab_material, _rubber_floor_material, _console_material, _metal_material, _door_material, _floor_material, _living_floor_material, _medical_floor_material] + _trim_materials.values():
		if material is BaseMaterial3D:
			var base_material := material as BaseMaterial3D
			if not _interior_base.has(base_material):
				_interior_base[base_material] = base_material.albedo_color
			base_material.albedo_color = (_interior_base[base_material] as Color) * tint
	for room_id in _room_lights:
		var spec := VisualStyle.room_light(room_id)
		_apply_room_light(room_id, spec["color"], spec["energy"], spec["range"])


## Where the camera is, for bigger-on-the-inside drawing (ADR 0012): `inside_ship` = the camera is in the interior
## (walking inside, or the cockpit view); `room_id` = the room it is in (&"" if none). In a pocket room only the interior
## is drawn; outside only the hull and the threshold rooms; in the cockpit or airlock both.
func set_camera_place(inside_ship: bool, room_id: StringName) -> void:
	_camera_in_pocket = inside_ship and ship.systems.layout.is_pocket(room_id)


## The cull mask for a camera at this place (ADR 0013). Outside: everything but the pocket. Inside the ship: never the middle of the
## hull (its plating cuts through the bigger rooms, and the cockpit and airlock look into them through their doors), always the
## nose and tail ends (canopy, ramp) only in the cockpit and airlock themselves; in a pocket room nothing of the hull is drawn. A threshold room's shell is drawn only while a
## door joins that room to a pocket room and is open; in the cockpit or airlock both shells are drawn.
func cull_mask_for(inside_ship: bool, room_id: StringName) -> int:
	var layout := ship.systems.layout
	if not inside_ship or room_id == &"":
		return ALL_LAYERS & ~LAYER_POCKET if not inside_ship else ALL_LAYERS
	if not layout.is_pocket(room_id):
		return ALL_LAYERS & ~LAYER_HULL
	var mask := ALL_LAYERS & ~(LAYER_HULL | LAYER_ENDS) # walking in a pocket room (or its doorways): no hull at all, nose and tail included
	for shell_room in SHELL_LAYERS:
		if not _shell_door_open(layout, shell_room):
			mask &= ~int(SHELL_LAYERS[shell_room])
	return mask


func _shell_door_open(layout: InteriorLayout, room_id: StringName) -> bool:
	for portal_id in layout.portals:
		var portal: Portal = layout.portals[portal_id]
		if portal.open_factor > 0.01 and room_id in layout.portal_rooms(portal_id):
			return true
	return false


## True when a camera at the last place set (set_camera_place) draws the hull.
func is_hull_visible() -> bool:
	return not _camera_in_pocket


## Puts every VisualInstance3D (meshes, lamps, decals, particles, labels) under `node`, `node` included, on `mask`.
static func _set_layers(node: Node, mask: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = mask
	for child in node.get_children():
		_set_layers(child, mask)


## Cuts the hull into its nose end (all triangles at z <= HULL_NOSE_END_Z), its tail end (z >= HULL_TAIL_START_Z) and the middle.
## Triangles that straddle a cut stay in the middle: both cuts sit on hull stations, so no triangle does. The pieces keep the
## surface order and materials of the original; the original node becomes the middle.
func _split_hull_static(node: MeshInstance3D) -> void:
	var source := node.mesh as ArrayMesh
	var groups: Array = [ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new()] # nose end, middle, tail end
	var materials: Array = [[], [], []]
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var picked: Array = [[], [], []] # plain Arrays: a Packed array stored in an Array is copied on every read
		var picked_normals: Array = [[], [], []]
		for first in range(0, vertices.size() - 2, 3):
			var low := minf(vertices[first].z, minf(vertices[first + 1].z, vertices[first + 2].z))
			var high := maxf(vertices[first].z, maxf(vertices[first + 1].z, vertices[first + 2].z))
			var group := 1
			if high <= HULL_NOSE_END_Z:
				group = 0
			elif low >= HULL_TAIL_START_Z:
				group = 2
			for corner in 3:
				(picked[group] as Array).append(vertices[first + corner])
				(picked_normals[group] as Array).append(normals[first + corner])
		for group in 3:
			if (picked[group] as Array).is_empty():
				continue
			var part := []
			part.resize(Mesh.ARRAY_MAX)
			part[Mesh.ARRAY_VERTEX] = PackedVector3Array(picked[group])
			part[Mesh.ARRAY_NORMAL] = PackedVector3Array(picked_normals[group])
			(groups[group] as ArrayMesh).add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part)
			(materials[group] as Array).append(node.get_surface_override_material(surface))
	var names := ["HullStaticNose", "HullStatic", "HullStaticTail"]
	for group in 3:
		var piece := node if group == 1 else MeshInstance3D.new()
		piece.mesh = groups[group]
		for surface in (materials[group] as Array).size():
			piece.set_surface_override_material(surface, (materials[group] as Array)[surface])
		if group != 1:
			piece.name = names[group]
			piece.transform = node.transform
			add_child(piece)
			_end_nodes.append(piece)
	_hull_nodes.append(node)


## Assigns the render layers once everything is built: pocket rooms on LAYER_POCKET (their lamps light only the inside, and an
## outside camera neither draws nor applies them), hull pieces on LAYER_HULL, each threshold shell on its own layer.
func _assign_layers() -> void:
	_set_layers(pocket, LAYER_POCKET)
	for node in _hull_nodes:
		_set_layers(node, LAYER_HULL)
	for node in _end_nodes:
		_set_layers(node, LAYER_ENDS)
	for room_id in _shell_nodes:
		for node: Node3D in _shell_nodes[room_id]:
			_set_layers(node, SHELL_LAYERS.get(room_id, 1))
	for light in pocket.find_children("*", "Light3D", true, false):
		(light as Light3D).light_cull_mask = ALL_LAYERS & ~(LAYER_HULL | LAYER_ENDS) # a lamp inside never lights the hull's outer skin


func _target_for_room(layout: InteriorLayout, room_id: StringName) -> Node3D:
	return pocket if layout.is_pocket(room_id) else self


## A portal belongs to the pocket when every room it joins does (a door between two pocket rooms).
func _target_for_portal(layout: InteriorLayout, portal_id: StringName) -> Node3D:
	for room_id in layout.portal_rooms(portal_id):
		if not layout.is_pocket(room_id):
			return self
	return pocket


## The pocket when the ship-local point lies in a pocket room (or its wall skin), else the ship itself.
func _target_for_point(layout: InteriorLayout, point: Vector3) -> Node3D:
	for room_id in layout.rooms:
		if (layout.rooms[room_id] as Rect2).grow(0.25).has_point(Vector2(point.x, point.z)):
			return _target_for_room(layout, room_id)
	return self


func _build_floors_and_ceilings(layout: InteriorLayout) -> void:
	for room_id in layout.rooms:
		var room: Rect2 = layout.rooms[room_id]
		_build_target = _target_for_room(layout, room_id)
		var rubber_floor: bool = room_id == &"airlock" or room_id == &"cargo"
		var floor_material: Material = _rubber_floor_material if rubber_floor else _floor_slab_material
		if room_id == &"living_area":
			floor_material = _living_floor_material
		elif room_id == &"medical":
			floor_material = _medical_floor_material
		var first_node := get_child_count()
		_slab(room, layout.floor_y - 0.12, layout.floor_y, floor_material)
		_slab(room, layout.ceiling_y, layout.ceiling_y + 0.12, _wall_material)
		if not layout.is_pocket(room_id):
			_note_shell(room_id, first_node)
	for portal_id in layout.portals:
		var portal: Portal = layout.portals[portal_id]
		_build_target = _target_for_portal(layout, portal_id)
		_slab(portal.opening, layout.floor_y - 0.12, layout.floor_y, _floor_slab_material)
		_slab(portal.opening, layout.ceiling_y, layout.ceiling_y + 0.12, _wall_material)
	_build_target = self


## Walls are the 0.2 m skin just outside each room rectangle, with gaps where a portal opening crosses it.
## The cockpit has no nose wall: it opens into the exterior's glass canopy.
func _build_walls(layout: InteriorLayout) -> void:
	var bottom := layout.floor_y
	var top := layout.ceiling_y
	var thickness := 0.2
	var entries: Array = []
	for room_id in layout.rooms:
		var room: Rect2 = layout.rooms[room_id]
		var walls := {
			"nose": [Rect2(room.position.x - thickness, room.position.y - thickness, room.size.x + 2.0 * thickness, thickness), true],
			"tail": [Rect2(room.position.x - thickness, room.end.y, room.size.x + 2.0 * thickness, thickness), true],
			"left": [Rect2(room.position.x - thickness, room.position.y, thickness, room.size.y), false],
			"right": [Rect2(room.end.x, room.position.y, thickness, room.size.y), false]}
		for side in walls:
			if room_id == &"cockpit" and side == "nose":
				continue # the exterior's canopy nose closes the cockpit (ShipExterior._build_canopy_nose)
			entries.append({"room": room_id, "side": side, "rect": walls[side][0], "along_x": walls[side][1], "pocket": layout.is_pocket(room_id)})
	# Two rooms that meet share one wall plane, and each room's skin used to be drawn on top of the other's (different lengths, so
	# different panel texture scaling: the flicker). Each plane is now drawn once: threshold rooms keep theirs (they are visible from
	# outside), then the longest wall wins, and a later wall is cut back to what is not already covered.
	entries.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		if first["pocket"] != second["pocket"]:
			return not first["pocket"]
		var first_rect: Rect2 = first["rect"]
		var second_rect: Rect2 = second["rect"]
		return maxf(first_rect.size.x, first_rect.size.y) > maxf(second_rect.size.x, second_rect.size.y))
	var kept: Array = []
	for entry in entries:
		var room_id: StringName = entry["room"]
		var side: String = entry["side"]
		var wall: Rect2 = entry["rect"]
		var runs_along_x: bool = entry["along_x"]
		var pieces: Array = [wall]
		for other in kept:
			pieces = _wall_minus(pieces, other, runs_along_x)
		_build_target = _target_for_room(layout, room_id)
		var first_node := get_child_count()
		for piece: Rect2 in pieces:
			var start := piece.position.x if runs_along_x else piece.position.y
			var finish := piece.end.x if runs_along_x else piece.end.y
			var piece_windows := layout.windows_in(room_id, side).filter(func(window): return float(window["center"]) >= start - 0.001 and float(window["center"]) <= finish + 0.001)
			_wall_with_portal_gaps(layout, piece, runs_along_x, bottom, top, piece_windows)
		_build_trim(layout, room_id, side, wall, runs_along_x, bottom, top)
		if not entry["pocket"] and not _touches_pocket_wall(entries, wall):
			_note_shell(room_id, first_node)
		kept.append(wall)
	_build_target = self


## What is left of each rect in `pieces` once `other` (a wall on the same plane, same thickness) is taken away along the wall's run.
static func _wall_minus(pieces: Array, other: Rect2, runs_along_x: bool) -> Array:
	var result: Array = []
	for piece: Rect2 in pieces:
		var overlap := piece.intersection(other)
		if overlap.size.x <= 0.001 or overlap.size.y <= 0.001:
			result.append(piece)
			continue
		if runs_along_x:
			if overlap.position.x - piece.position.x > 0.001:
				result.append(Rect2(piece.position.x, piece.position.y, overlap.position.x - piece.position.x, piece.size.y))
			if piece.end.x - overlap.end.x > 0.001:
				result.append(Rect2(overlap.end.x, piece.position.y, piece.end.x - overlap.end.x, piece.size.y))
		else:
			if overlap.position.y - piece.position.y > 0.001:
				result.append(Rect2(piece.position.x, piece.position.y, piece.size.x, overlap.position.y - piece.position.y))
			if piece.end.y - overlap.end.y > 0.001:
				result.append(Rect2(piece.position.x, overlap.end.y, piece.size.x, piece.end.y - overlap.end.y))
	return result


static func _touches_pocket_wall(entries: Array, wall: Rect2) -> bool:
	for entry in entries:
		if entry["pocket"]:
			var overlap := wall.intersection(entry["rect"])
			if overlap.size.x > 0.001 and overlap.size.y > 0.001:
				return true
	return false


func _note_shell(room_id: StringName, first_node: int) -> void:
	if not _shell_nodes.has(room_id):
		_shell_nodes[room_id] = []
	for index in range(first_node, get_child_count()):
		(_shell_nodes[room_id] as Array).append(get_child(index))


const TRIM_COLOURS := {&"living_area": Color(0.35, 0.24, 0.14), &"medical": Color(0.8, 0.9, 0.88), &"airlock": Color(0.9, 0.35, 0.1),
	&"cargo": Color(0.85, 0.55, 0.1), &"engineering": Color(0.18, 0.4, 0.3), &"bathroom": Color(0.55, 0.75, 0.85)}


func _trim_material_for(room_id: StringName) -> StandardMaterial3D:
	if not _trim_materials.has(room_id):
		_trim_materials[room_id] = _material(TRIM_COLOURS.get(room_id, Color(0.16, 0.17, 0.2)), 0.5, 0.4)
	return _trim_materials[room_id]


## Skirting along the floor (broken at doorways) and a cove under the ceiling, on the room's side of one wall.
func _build_trim(layout: InteriorLayout, room_id: StringName, side: String, wall: Rect2, runs_along_x: bool, bottom: float, top: float) -> void:
	var room: Rect2 = layout.rooms[room_id]
	var inner := {"nose": Vector2(0, 1), "tail": Vector2(0, -1), "left": Vector2(1, 0), "right": Vector2(-1, 0)}[side] as Vector2
	var span_from := room.position.x if runs_along_x else room.position.y
	var span_to := room.end.x if runs_along_x else room.end.y
	var face := wall.get_center() + inner * (InteriorLayout.WALL_THICKNESS * 0.5 + 0.025)
	var material := _trim_material_for(room_id)
	var breaks: Array = []
	for portal in layout.portals.values():
		var opening: Rect2 = (portal as Portal).opening
		if opening.intersects(wall):
			breaks.append(Vector2(opening.position.x, opening.end.x) if runs_along_x else Vector2(opening.position.y, opening.end.y))
	breaks.sort_custom(func(first: Vector2, second: Vector2) -> bool: return first.x < second.x)
	var cursor := span_from
	var runs: Array = []
	for gap in breaks:
		runs.append(Vector2(cursor, maxf(cursor, gap.x)))
		cursor = gap.y
	runs.append(Vector2(cursor, span_to))
	for run in runs:
		_trim_box(face, runs_along_x, run, bottom + 0.07, 0.14, material)
	_trim_box(face, runs_along_x, Vector2(span_from, span_to), top - 0.05, 0.1, material)


func _trim_box(face: Vector2, runs_along_x: bool, run: Vector2, middle_y: float, height: float, material: Material) -> void:
	if run.y - run.x < 0.01:
		return
	var length := run.y - run.x
	var middle := (run.x + run.y) * 0.5
	var box := _box_instance(Vector3(length, height, 0.05) if runs_along_x else Vector3(0.05, height, length), material)
	box.position = Vector3(middle, middle_y, face.y) if runs_along_x else Vector3(face.x, middle_y, middle)
	_build_target.add_child(box)


## One wall with its gaps: doorways (open from the floor, lintel above) and windows (wall below the sill and above the top,
## glass and a frame in between).
func _wall_with_portal_gaps(layout: InteriorLayout, wall: Rect2, runs_along_x: bool, bottom: float, top: float, windows: Array = []) -> void:
	var start := wall.position.x if runs_along_x else wall.position.y
	var finish := wall.end.x if runs_along_x else wall.end.y
	var gaps: Array = []
	for portal in layout.portals.values():
		var opening: Rect2 = (portal as Portal).opening
		if opening.intersects(wall):
			gaps.append({"from": opening.position.x if runs_along_x else opening.position.y, "to": opening.end.x if runs_along_x else opening.end.y,
				"low": bottom, "high": bottom + 2.1, "glass": false})
	for window in windows:
		var low: float = bottom + float(window["sill"])
		gaps.append({"from": float(window["center"]) - float(window["width"]) * 0.5, "to": float(window["center"]) + float(window["width"]) * 0.5,
			"low": low, "high": low + float(window["height"]), "glass": true})
	gaps.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return first["from"] < second["from"])
	var cursor := start
	for gap in gaps:
		_wall_span(wall, runs_along_x, cursor, gap["from"], bottom, top)
		if gap["low"] > bottom + 0.001:
			_wall_span(wall, runs_along_x, gap["from"], gap["to"], bottom, gap["low"]) # under the window
		_wall_span(wall, runs_along_x, gap["from"], gap["to"], gap["high"], top) # lintel
		if gap["glass"]:
			_build_window_glass(wall, runs_along_x, gap)
		cursor = gap["to"]
	_wall_span(wall, runs_along_x, cursor, finish, bottom, top)


## Glass pane across the wall's thickness plus a thin frame round it.
func _build_window_glass(wall: Rect2, runs_along_x: bool, gap: Dictionary) -> void:
	var width: float = gap["to"] - gap["from"]
	var height: float = gap["high"] - gap["low"]
	var centre := (float(gap["from"]) + float(gap["to"])) * 0.5
	var wall_centre := wall.get_center()
	var thickness := minf(wall.size.x, wall.size.y)
	var middle_y: float = (float(gap["low"]) + float(gap["high"])) * 0.5
	var frame := 0.06
	var pieces := [
		[Vector2(width, height), Vector2(0.0, 0.0), 0.03, _window_glass_material],
		[Vector2(width + frame, frame), Vector2(0.0, height * 0.5), thickness + FRAME_PROUD, _metal_material],
		[Vector2(width + frame, frame), Vector2(0.0, -height * 0.5), thickness + FRAME_PROUD, _metal_material],
		[Vector2(frame, height), Vector2(width * 0.5, 0.0), thickness + FRAME_PROUD, _metal_material],
		[Vector2(frame, height), Vector2(-width * 0.5, 0.0), thickness + FRAME_PROUD, _metal_material]]
	for piece in pieces:
		var size: Vector2 = piece[0]
		var offset: Vector2 = piece[1]
		var depth: float = piece[2]
		var box := _box_instance(Vector3(size.x, size.y, depth) if runs_along_x else Vector3(depth, size.y, size.x), piece[3])
		box.position = Vector3(centre + offset.x, middle_y + offset.y, wall_centre.y) if runs_along_x else Vector3(wall_centre.x, middle_y + offset.y, centre + offset.x)
		_build_target.add_child(box)


func _wall_span(wall: Rect2, runs_along_x: bool, from_value: float, to_value: float, y_min: float, y_max: float) -> void:
	if to_value - from_value < 0.001:
		return
	if runs_along_x:
		_wall_box(from_value, to_value, wall.position.y, wall.end.y, y_min, y_max)
	else:
		_wall_box(wall.position.x, wall.end.x, from_value, to_value, y_min, y_max)


## Plain doors are two leaves that part in the middle and slide into the wall either side; airlock doors are one heavy slab.
## A status strip over each doorway (amber closed, green open, red when the airlock is locked out) shows from both sides.
const REVEAL_PROUD := 0.02 ## frames and window frames stand this far proud of the plane they sit in, so no two surfaces share one
const FRAME_PROUD := 0.03


func _build_doors(layout: InteriorLayout) -> void:
	for portal_id in layout.portals:
		var portal: Portal = layout.portals[portal_id]
		var opening := portal.opening
		var door_height := 2.1
		var base_y := layout.floor_y + door_height * 0.5
		# A door in a wall that runs along x is walked through along z and slides along x; a side-wall door is the other way round.
		var crossing_z := opening.size.x >= opening.size.y
		var span := opening.size.x if crossing_z else opening.size.y
		var depth := (opening.size.y if crossing_z else opening.size.x) * 0.9
		var centre := opening.get_center()
		var axis := 0 if crossing_z else 2
		var parent := _target_for_portal(layout, portal_id)
		var leaves := []
		if portal.kind == Portal.Kind.DOOR:
			var half := span * 0.5
			for side in [-1.0, 1.0]:
				var leaf := _box_instance(Vector3(half + 0.02, door_height, depth) if crossing_z else Vector3(depth, door_height, half + 0.02), _door_material)
				leaf.position = Vector3(centre.x + side * half * 0.5, base_y, centre.y) if crossing_z else Vector3(centre.x, base_y, centre.y + side * half * 0.5)
				parent.add_child(leaf)
				leaves.append({"node": leaf, "axis": axis, "base": leaf.position[axis], "travel": side * (half + 0.05)})
		else:
			var slab := _box_instance(Vector3(span, door_height, depth), _door_material)
			slab.position = Vector3(centre.x, base_y, centre.y)
			parent.add_child(slab)
			leaves.append({"node": slab, "axis": 0, "base": slab.position.x, "travel": DOOR_SLIDE})
		var frame_material: Material = _accent_material if portal.kind != Portal.Kind.DOOR else _frame_material
		var jamb := 0.08
		var wall_depth := 0.26
		for side in [-1.0, 1.0]:
			# The frame stands REVEAL_PROUD proud of the wall's opening edge: flush, its inner face shared a plane with the wall
			# reveal and the two materials z-fought along every doorway (tests/unit/interior_surface_test.gd).
			var post := _box_instance(Vector3(jamb + REVEAL_PROUD, door_height, wall_depth) if crossing_z else Vector3(wall_depth, door_height, jamb + REVEAL_PROUD), frame_material)
			var post_offset := span * 0.5 + (jamb - REVEAL_PROUD) * 0.5
			post.position = Vector3(centre.x + side * post_offset, base_y, centre.y) if crossing_z else Vector3(centre.x, base_y, centre.y + side * post_offset)
			parent.add_child(post)
		var head := _box_instance(Vector3(span + jamb * 2.0, jamb + REVEAL_PROUD, wall_depth) if crossing_z else Vector3(wall_depth, jamb + REVEAL_PROUD, span + jamb * 2.0), frame_material)
		head.position = Vector3(centre.x, layout.floor_y + door_height + (jamb - REVEAL_PROUD) * 0.5, centre.y)
		parent.add_child(head)
		var light_material := _emissive(Color(1.0, 0.6, 0.1), 2.0)
		var strip := _box_instance(Vector3(span * 0.7, 0.07, wall_depth + 0.02) if crossing_z else Vector3(wall_depth + 0.02, 0.07, span * 0.7), light_material)
		strip.position = Vector3(centre.x, layout.floor_y + door_height + 0.1, centre.y)
		parent.add_child(strip)
		_door_nodes[portal_id] = {"leaves": leaves, "light": light_material}


## Door status colour: green once the door is opening or open, amber when shut, red on an airlock door that cannot open
## because its partner is open or the airlock is still cycling.
func _update_door_light(layout: InteriorLayout, portal: Portal, material: StandardMaterial3D) -> void:
	var colour := Color(1.0, 0.6, 0.1)
	if portal.target_open or portal.open_factor > 0.0:
		colour = Color(0.2, 1.0, 0.45)
	elif portal.kind != Portal.Kind.DOOR:
		var partner: Portal = layout.portals[&"airlock_outer" if portal.kind == Portal.Kind.AIRLOCK_INNER else &"airlock_inner"]
		if partner.target_open or partner.open_factor > 0.0:
			colour = Color(1.0, 0.15, 0.1)
	material.albedo_color = colour
	material.emission = colour


func _build_seat_and_console(layout: InteriorLayout) -> void:
	for seat_id in layout.seats:
		var seat_position: Vector3 = layout.seats[seat_id]["position"]
		var behind := Vector3(0, 0, 0.38) if absf(layout.seats[seat_id]["facing_yaw"]) < 1.0 else Vector3(0, 0, -0.38)
		var seat := _box_instance(Vector3(0.7, 0.5, 0.7), _accent_material)
		seat.position = seat_position + Vector3(0, 0.25, 0)
		_target_for_point(layout, seat_position).add_child(seat)
		var back := _box_instance(Vector3(0.7, 1.0, 0.12), _accent_material)
		back.position = seat_position + Vector3(0, 0.75, 0) + behind
		_target_for_point(layout, seat_position).add_child(back)
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


## The furniture from the layout (InteriorLayout.furniture): boxes standing on the floor. Solid pieces also block walking.
func _build_furniture(layout: InteriorLayout) -> void:
	var materials := {
		&"linen": _material(Color(0.62, 0.66, 0.72), 0.9, 0.0),
		&"wood": _material(Color(0.42, 0.3, 0.2), 0.7, 0.05),
		&"white": _material(Color(0.85, 0.9, 0.9), 0.4, 0.1),
		&"steel": _material(Color(0.6, 0.62, 0.66), 0.35, 0.8),
		&"console": _console_material,
		&"screen": _emissive(Color(0.3, 0.7, 1.0), 1.5),
		&"glow_pad": _emissive(Color(0.6, 0.95, 0.9), 0.4),
		&"glow_teal": _emissive(Color(0.2, 0.9, 0.8), 2.0),
		&"glow_green": _emissive(Color(0.2, 1.0, 0.5), 2.0),
		&"glass": _window_glass_material,
		&"mirror": _material(Color(0.8, 0.85, 0.9), 0.05, 0.9),
		&"crate": _material(Color(0.42, 0.36, 0.22), 0.75, 0.15)}
	for piece in layout.furniture:
		var size: Vector3 = piece["size"]
		var at: Vector2 = piece["at"]
		var instance := _box_instance(size, materials[piece["material"]])
		instance.name = String(piece["name"])
		instance.position = Vector3(at.x, layout.floor_y + float(piece["lift"]) + size.y * 0.5, at.y)
		_target_for_point(layout, instance.position).add_child(instance)


func _build_panels(layout: InteriorLayout) -> void:
	for machine_id in layout.machine_screens:
		var spec: Dictionary = layout.machine_screens[machine_id]
		var machine_material := _emissive(Color(0.2, 1.0, 0.5), 0.5) # a dim lit glass: the status text on it carries the bright colour
		var machine_screen := _box_instance(spec["size"], machine_material)
		machine_screen.name = String(machine_id) + "_screen"
		machine_screen.position = spec["position"]
		_target_for_point(layout, spec["position"]).add_child(machine_screen)
		_machine_screen_materials[machine_id] = machine_material
	for point in layout.interact_points:
		if layout.seats.has(point["id"]) or layout.portals.has(point["id"]) or point["id"] in [&"bed", &"medbed"] or layout.machine_screens.has(point["id"]):
			continue # seats and doors are used by looking at them: no button beside the door
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
			_target_for_point(layout, point["position"]).add_child(screen)
			_station_screens[point["id"]] = screen_material
			continue
		if point["id"] == &"airlock_computer":
			# A wall screen: green at full pressure, amber while the air changes, red in vacuum (see _update_screens).
			_airlock_screen_material = _emissive(Color(0.2, 1.0, 0.5), 2.0)
			var airlock_screen := _box_instance(Vector3(0.06, 0.5, 0.7), _airlock_screen_material)
			airlock_screen.position = point["position"] + Vector3(0.27 if point["position"].x > 0.0 else -0.27, 1.1, 0)
			_target_for_point(layout, point["position"]).add_child(airlock_screen)
			continue
		var panel := _box_instance(Vector3(0.25, 0.35, 0.08), _panel_material)
		panel.position = point["position"] + Vector3(0, 1.1, 0)
		_target_for_point(layout, point["position"]).add_child(panel)


## Station screens: reactor green -> red with core heat (dark when tripped); engine screen red -> green with engine health.
func _update_screens() -> void:
	var systems := ship.systems
	_update_machine_screens(systems)
	if _airlock_screen_material != null:
		var pressure := systems.airlock_pressure
		var shade := Color(1.0, 0.2, 0.1).lerp(Color(1.0, 0.7, 0.1), clampf(pressure * 2.0, 0.0, 1.0)) if pressure < 0.5 else Color(1.0, 0.7, 0.1).lerp(Color(0.2, 1.0, 0.5), clampf((pressure - 0.5) * 2.0, 0.0, 1.0))
		_airlock_screen_material.albedo_color = shade
		_airlock_screen_material.emission = shade
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


## Machine screens: ops = hull health, battery = charge, limnal drive = ready (green) or not fitted / no fuel (red),
## scanners and radio = steady teal / amber.
func _update_machine_screens(systems: ShipSystems) -> void:
	for machine_id in _machine_screen_materials:
		var shade := Color(0.2, 0.8, 1.0)
		match machine_id:
			&"ops_computer":
				shade = Color(1.0, 0.2, 0.1).lerp(Color(0.2, 1.0, 0.5), clampf(ship.state.hull, 0.0, 1.0))
			&"battery_array":
				shade = Color(1.0, 0.2, 0.1).lerp(Color(0.2, 1.0, 0.5), clampf(systems.power.battery, 0.0, 1.0))
			&"limnal_drive":
				shade = Color(0.2, 1.0, 0.5) if ship.state.fuel > 0.0 else Color(1.0, 0.2, 0.1)
			&"ftl_radio":
				shade = Color(1.0, 0.7, 0.1)
		var machine_material: StandardMaterial3D = _machine_screen_materials[machine_id]
		machine_material.albedo_color = shade
		machine_material.emission = shade


## Sets colour and total energy of every lamp in a room (and the glow of its ceiling panels).
func _apply_room_light(room_id: StringName, colour: Color, energy: float, light_range: float = -1.0) -> void:
	var share: float = _light_share.get(room_id, 1.0)
	var lamps: Array = [_room_lights[room_id]]
	lamps.append_array(_room_extra_lights.get(room_id, []))
	for lamp in lamps:
		(lamp as OmniLight3D).light_color = colour
		(lamp as OmniLight3D).light_energy = energy * share
		if light_range > 0.0:
			(lamp as OmniLight3D).omni_range = light_range
	if _fixture_materials.has(room_id):
		var panel: StandardMaterial3D = _fixture_materials[room_id]
		panel.albedo_color = colour
		panel.emission = colour
		panel.emission_energy_multiplier = clampf(energy * 1.4, 0.15, 3.0)


## One ceiling panel and one lamp per ~4 m of a room's width (long rooms get up to three), so the cabin is lit along its length
## instead of from a single bulb at its centre. Lamps are unshadowed.
func _build_lights(layout: InteriorLayout) -> void:
	for room_id in layout.rooms:
		var rect: Rect2 = layout.rooms[room_id]
		var count := clampi(roundi(rect.size.x / 4.0), 1, 3)
		_light_share[room_id] = 1.0 / sqrt(float(count))
		var panel_material := _emissive(Color.WHITE, 1.0)
		_fixture_materials[room_id] = panel_material
		var extras: Array = []
		for index in count:
			var light := OmniLight3D.new()
			var spot_x := rect.get_center().x + (float(index) - float(count - 1) * 0.5) * rect.size.x / float(count)
			light.position = Vector3(spot_x, 1.3, rect.get_center().y)
			light.shadow_enabled = false
			_target_for_room(layout, room_id).add_child(light)
			if index == 0:
				_room_lights[room_id] = light
			else:
				extras.append(light)
			var panel := _box_instance(Vector3(1.0, 0.04, 0.3), panel_material)
			panel.position = Vector3(spot_x, layout.ceiling_y - 0.02, rect.get_center().y)
			_target_for_room(layout, room_id).add_child(panel)
		_room_extra_lights[room_id] = extras
		if ship.systems.hazards.has_room(room_id):
			var flames := _box_instance(Vector3(0.9, 1.0, 0.9), _emissive(Color(1.0, 0.45, 0.1), 4.0))
			flames.position = Vector3((rect as Rect2).get_center().x, layout.floor_y + 0.5, (rect as Rect2).get_center().y)
			flames.visible = false
			_target_for_room(layout, room_id).add_child(flames)
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
			_target_for_room(layout, room_id).add_child(smoke)
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
	# Duplicate catalogue entries (two hazard stripes, repeated scorch variants) get Godot's
	# @Decal@ auto-name, which loses the catalogue identity. Keep the source name as metadata.
	decal.set_meta(&"catalog_set", set_id)
	decal.set_meta(&"catalog_name", decal_name)
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
	_target_for_point(ship.systems.layout, center).add_child(decal)
	return decal


## Engineering's centrepiece: a glass column on a plinth with the core glowing inside, ribs round it and conduits in the
## floor to the reactor panel and aft. The core's colour and brightness are ShipPower's temperature and output (see
## _update_reactor), so you can read the reactor from across the room.
func _build_reactor(layout: InteriorLayout) -> void:
	if layout.reactor_core.is_empty():
		return
	var at: Vector2 = layout.reactor_core["at"]
	var radius: float = layout.reactor_core["radius"]
	var bottom := layout.floor_y
	var top := layout.ceiling_y
	var root := Node3D.new()
	root.name = "ReactorCore"
	root.position = Vector3(at.x, 0.0, at.y)
	_target_for_point(layout, Vector3(at.x, bottom, at.y)).add_child(root)
	_cylinder(root, radius + 0.2, radius + 0.15, bottom, bottom + 0.3, _metal_material, "ReactorPlinth")
	_cylinder(root, radius + 0.15, radius + 0.2, top - 0.35, top, _metal_material, "ReactorCap")
	_cylinder(root, radius, radius, bottom + 0.3, top - 0.35, _window_glass_material, "ReactorGlass")
	_reactor_core_material = _emissive(Color(0.35, 0.75, 1.0), 2.5)
	_cylinder(root, 0.2, 0.2, bottom + 0.35, top - 0.4, _reactor_core_material, "ReactorCoreGlow")
	for index in 4:
		var angle := PI * 0.25 + PI * 0.5 * float(index)
		var rib := _box_instance(Vector3(0.09, top - bottom - 0.65, 0.09), _frame_material)
		rib.position = Vector3(cos(angle) * (radius + 0.03), (bottom + top) * 0.5, sin(angle) * (radius + 0.03))
		root.add_child(rib)
	_reactor_light = OmniLight3D.new()
	_reactor_light.name = "ReactorLight"
	_reactor_light.position = Vector3(0.0, (bottom + top) * 0.5, 0.0)
	_reactor_light.omni_range = 3.5
	_reactor_light.shadow_enabled = false
	root.add_child(_reactor_light)
	# The power bus: a lit strip in the floor from the plinth across the room to the reactor panel's wall, and a short one
	# forward to the engine station.
	_reactor_conduit_material = _emissive(Color(0.35, 0.75, 1.0), 0.8)
	var room: Rect2 = layout.rooms[layout.room_at(at.x, at.y)]
	var west_run := at.x - radius - 0.2 - room.position.x
	if west_run > 0.1:
		var strip := _box_instance(Vector3(west_run, 0.015, 0.1), _reactor_conduit_material)
		strip.name = "ReactorBusWest"
		strip.position = Vector3(room.position.x + west_run * 0.5 - at.x, bottom + 0.008, 0.0)
		root.add_child(strip)
	var forward_run := at.y - radius - 0.2 - (room.position.y + 1.0)
	if forward_run > 0.1:
		var strip_forward := _box_instance(Vector3(0.1, 0.015, forward_run), _reactor_conduit_material)
		strip_forward.name = "ReactorBusForward"
		strip_forward.position = Vector3(0.0, bottom + 0.008, -(radius + 0.2 + forward_run * 0.5))
		root.add_child(strip_forward)
	# The plinth's read-out faces into the room (toward the walkway, -x).
	_screen_labels[&"reactor_core"] = _make_screen_label(root, Vector3(-(radius + 0.18), bottom + 0.17, 0.0), Vector3.LEFT, 18)


## Core colour from ShipPower: cool blue at rest, orange as it heats, red near the trip point; dark when tripped (a weak amber
## pulse while the battery array carries life support). Brightness follows the reactor's real output and load.
func _update_reactor() -> void:
	if _reactor_core_material == null:
		return
	var power := ship.systems.power
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
	var colour := Color(0.35, 0.75, 1.0)
	var energy := 0.0
	if power.is_shut_down():
		colour = Color(1.0, 0.5, 0.1) if power.on_battery() else Color(0.05, 0.05, 0.05)
		energy = 0.15 + 0.15 * pulse if power.on_battery() else 0.0
	else:
		var heat := clampf(power.temperature, 0.0, 1.0)
		colour = colour.lerp(Color(1.0, 0.5, 0.12), smoothstep(0.3, 0.75, heat)).lerp(Color(1.0, 0.12, 0.05), smoothstep(0.75, 1.0, heat))
		var load := clampf(power.total_delivered() / ShipPower.MAX_OUTPUT, 0.0, 1.0)
		energy = (0.9 + 2.2 * load) * power.output() / ShipPower.MAX_OUTPUT
		if heat > 0.85:
			energy *= 0.75 + 0.25 * pulse # close to tripping: the core flickers
	_reactor_core_material.albedo_color = colour
	_reactor_core_material.emission = colour
	_reactor_core_material.emission_energy_multiplier = energy
	_reactor_conduit_material.albedo_color = colour
	_reactor_conduit_material.emission = colour
	_reactor_conduit_material.emission_energy_multiplier = energy * 0.3
	_reactor_light.light_color = colour
	_reactor_light.light_energy = energy * 0.5
	_reactor_light.visible = energy > 0.01


func _cylinder(parent: Node3D, bottom_radius: float, top_radius: float, y_from: float, y_to: float, material: Material, node_name: String) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom_radius
	mesh.top_radius = top_radius
	mesh.height = y_to - y_from
	mesh.radial_segments = 24
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = Vector3(0.0, (y_from + y_to) * 0.5, 0.0)
	parent.add_child(instance)
	return instance


## A line of status text floating 2 cm in front of a screen. `normal` is the way the screen faces (toward the reader).
func _make_screen_label(parent: Node3D, at: Vector3, normal: Vector3, font_size: int = 22) -> Label3D:
	var label := Label3D.new()
	label.font_size = font_size
	label.pixel_size = 0.0026
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.line_spacing = -2.0
	if ResourceLoader.exists(SCREEN_FONT):
		label.font = load(SCREEN_FONT)
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	label.transform = Transform3D(Basis.looking_at(-normal, up), at + normal * 0.02)
	parent.add_child(label)
	return label


## Text labels for every machine screen (facing into the room the screen is in), the airlock computer and the pilot's dash.
func _build_screen_labels(layout: InteriorLayout) -> void:
	for machine_id in layout.machine_screens:
		var spec: Dictionary = layout.machine_screens[machine_id]
		var at: Vector3 = spec["position"]
		var size: Vector3 = spec["size"]
		var room_id := layout.room_at(at.x, at.z)
		var centre := (layout.rooms[room_id] as Rect2).get_center() if room_id != &"" else Vector2.ZERO
		var normal := Vector3(signf(centre.x - at.x), 0.0, 0.0) if size.x < size.z else Vector3(0.0, 0.0, signf(centre.y - at.z))
		var thickness := minf(size.x, size.z)
		_screen_labels[machine_id] = _make_screen_label(_target_for_point(layout, at), at + normal * thickness * 0.5, normal, 24 if maxf(size.x, size.z) > 0.8 else 18)
	for point in layout.interact_points:
		if point["id"] == &"airlock_computer":
			var side := 1.0 if point["position"].x > 0.0 else -1.0
			var screen_at: Vector3 = point["position"] + Vector3(side * 0.24, 1.1, 0.0)
			_screen_labels[&"airlock_computer"] = _make_screen_label(_target_for_point(layout, screen_at), screen_at, Vector3(-side, 0.0, 0.0), 16)
	# The nav screen lies on the cockpit console (see _build_seat_and_console), tilted toward the pilot.
	var dash := _make_screen_label(self, Vector3(0.0, layout.floor_y + 0.95, -6.45), Vector3(0.0, 0.85, 0.53).normalized(), 18)
	dash.name = "NavReadout"
	_screen_labels[&"nav"] = dash
	_update_screen_labels()


## The words on the screens, from the systems they belong to.
func _update_screen_labels() -> void:
	var systems := ship.systems
	var state := ship.state
	var power := systems.power
	var labels := {
		&"ops_computer": "OPERATIONS\nHULL %d%%   FUEL %d%%\nREACTOR %s" % [roundi(state.hull * 100.0), roundi(state.fuel * 100.0),
			("TRIPPED" if power.is_shut_down() else "ONLINE")],
		&"scanners": "SCANNERS\n" + _scanner_status(),
		&"ftl_radio": "PILOT WAVE RADIO\nLISTENING",
		&"battery_array": "BATTERY %d%%\n%s" % [roundi(power.battery * 100.0), _battery_status(power)],
		&"limnal_drive": "LIMNAL DRIVE\n%s" % ("READY" if state.fuel > 0.0 else "NO FUEL"),
		&"tactical": "DORSAL GUN\n%s\nHEAT %d%%" % [_gun_status(), roundi(systems.turret.heat * 100.0)],
		&"airlock_computer": "AIRLOCK\nPRESSURE %d%%" % roundi(systems.airlock_pressure * 100.0),
		&"reactor_core": ("CORE TRIPPED  BATTERY %d%%" % roundi(power.battery * 100.0)) if power.is_shut_down() else
			"CORE %d%%  OUT %d  COOLANT %d%%" % [roundi(power.temperature * 100.0), roundi(power.total_delivered()), roundi(power.coolant * 100.0)],
		&"nav": "%s  %d m/s\nFUEL %d%%  HULL %d%%" % [GEAR_NAMES[clampi(state.gear, 0, GEAR_NAMES.size() - 1)], roundi(state.speed()),
			roundi(state.fuel * 100.0), roundi(state.hull * 100.0)],
	}
	for label_id in _screen_labels:
		var label: Label3D = _screen_labels[label_id]
		label.text = labels.get(label_id, String(label_id).to_upper())
		var shade := Color(0.75, 1.0, 0.85)
		if _machine_screen_materials.has(label_id):
			shade = ((_machine_screen_materials[label_id] as StandardMaterial3D).emission as Color).lightened(0.35)
		elif label_id == &"reactor_core" and _reactor_core_material != null:
			shade = Color(0.85, 0.95, 1.0) if not power.is_shut_down() else Color(1.0, 0.55, 0.2)
		label.modulate = shade


func _scanner_status() -> String:
	if session == null:
		return "PULSE READY"
	var cooldown: float = session.get("scan_cooldown")
	return "RECHARGING %ds" % ceili(cooldown) if cooldown > 0.0 else "PULSE READY  [N]"


static func _battery_status(power: ShipPower) -> String:
	if power.on_battery():
		return "SUPPLYING LIFE SUPPORT"
	if power.is_shut_down():
		return "FLAT"
	return "FULL" if power.battery >= 0.999 else "CHARGING"


func _gun_status() -> String:
	if ship.systems.turret.overheated:
		return "OVERHEATED"
	return "ARMED (COMBAT GEAR)" if Ship.gear_allows_fire(ship.state.gear) else "SAFE"


## The nozzle texture covers the whole nacelle, so the engine glow becomes a thin emissive disc in the exhaust mouth: the cylinder's top
## cap (+y before the nacelle is rotated 90 degrees about x, which sends +y to +z, the rear). Null when the nacelle itself glows
## (asset materials off), as before.
func _exhaust_disc(cap_y: float, radius: float) -> MeshInstance3D:
	if _nozzle_material == _glow_material:
		return null
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = radius
	disc_mesh.bottom_radius = radius
	disc_mesh.height = 0.04
	var disc := MeshInstance3D.new()
	disc.mesh = disc_mesh
	disc.material_override = _glow_material
	disc.position = Vector3(0.0, cap_y, 0.0)
	return disc


## Bare metal (metallic 1) reflects the sky, which is black space, so the textured interior would render near-black. One interior
## probe over the ship, captured once, gives metal something to reflect.
func _build_reflection_probe(layout: InteriorLayout) -> void:
	var height := layout.ceiling_y - layout.floor_y
	var probe := ReflectionProbe.new()
	probe.size = Vector3(InteriorLayout.POCKET_HALF_WIDTH * 2.0 + 1.0, height + 0.5, 20.0)
	probe.position = Vector3(0.0, layout.floor_y + height * 0.5, 1.8)
	probe.interior = true
	probe.box_projection = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 0.6
	add_child(probe)


func _slab(area: Rect2, bottom_y: float, top_y: float, material: Material) -> void:
	var instance := _box_instance(Vector3(area.size.x, top_y - bottom_y, area.size.y), material)
	instance.position = Vector3(area.position.x + area.size.x * 0.5, (bottom_y + top_y) * 0.5, area.position.y + area.size.y * 0.5)
	_build_target.add_child(instance)


func _wall_box(x_min: float, x_max: float, z_min: float, z_max: float, y_min: float, y_max: float, material: Material = null) -> void:
	var first_z := minf(z_min, z_max)
	var last_z := maxf(z_min, z_max)
	var instance := _box_instance(Vector3(x_max - x_min, y_max - y_min, last_z - first_z), material if material != null else _wall_material)
	instance.position = Vector3((x_min + x_max) * 0.5, (y_min + y_max) * 0.5, (first_z + last_z) * 0.5)
	_build_target.add_child(instance)


func _box_instance(size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	return instance


static func _make_window_glass() -> StandardMaterial3D:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.75, 0.9, 0.16)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.3
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	return glass


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
