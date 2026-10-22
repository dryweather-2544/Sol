class_name InteriorDetail
extends RefCounted
## The detail pass over the ship interior: two-tone wall panelling with a perforated rail band, ceiling ribs, cable trays and
## pipes, floor lane lines and door thresholds, wall hatches/vents (projected decals cut from the CC0 "Free Decals 02 : Sci-Fi"
## atlas), screen graphics on the machine screens (CC0 "Sci-Fi interface textures"), and crate straps.
## ShipVisuals calls build() once the rooms exist. Everything lives under one "Detail_<room>" node per room, in the same
## place (pocket or ship) as that room's other geometry, so the render-layer rules (ADR 0013) apply to it unchanged.
## Nothing here is solid or interactive; a missing texture just leaves that piece out.

const DECAL_DIR := "res://assets/sol/decals/dec_interior/"
const TRIM_DIR := "res://assets/sol/trim/"
const SCREEN_DIR := "res://assets/sol/screens/"

## Per room: the accent colour (rail underline, pipe couplings), the lower-wall colour, which rail strip it uses, whether it gets
## pipes / lane lines, and the wall decals it may carry as [name, width in metres, yellow variant].
const ROOM_STYLES := {
	&"cockpit": {"accent": Color(0.30, 0.60, 0.85), "wainscot": Color(0.24, 0.28, 0.34), "rail": "ribbed", "pipes": false, "lanes": false,
		"decals": [["pill_lights", 0.34, false], ["teardrop", 0.7, false], ["vent_strip", 0.8, false]]},
	&"cabin": {"accent": Color(0.85, 0.68, 0.18), "wainscot": Color(0.30, 0.31, 0.35), "rail": "perforated", "pipes": false, "lanes": true,
		"decals": [["vent_panel", 0.45, false], ["access_panel", 0.9, false], ["grille", 0.7, false], ["hex_hatch", 0.7, false]]},
	&"engineering": {"accent": Color(0.90, 0.50, 0.12), "wainscot": Color(0.25, 0.30, 0.28), "rail": "perforated", "pipes": true, "lanes": true,
		"decals": [["fan_round", 0.75, false], ["flower_fan", 0.8, false], ["square_hatch", 0.8, true], ["vent_strip", 0.9, false],
			["round_plate", 0.6, false], ["teardrop", 0.8, false]]},
	&"turret_room": {"accent": Color(0.80, 0.25, 0.18), "wainscot": Color(0.31, 0.27, 0.27), "rail": "black", "pipes": true, "lanes": true,
		"decals": [["octagon_cross", 0.75, false], ["trident_ring", 0.75, false], ["access_panel", 0.9, true], ["door_panel", 0.5, false]]},
	&"cargo": {"accent": Color(0.88, 0.62, 0.10), "wainscot": Color(0.33, 0.31, 0.25), "rail": "perforated", "pipes": true, "lanes": true,
		"decals": [["door_panel", 0.55, false], ["access_panel", 1.0, false], ["round_hatch", 0.7, true], ["grille", 0.7, true], ["vent_strip", 0.9, false]]},
	&"airlock": {"accent": Color(0.90, 0.40, 0.10), "wainscot": Color(0.33, 0.28, 0.24), "rail": "dark", "pipes": true, "lanes": false,
		"decals": [["round_hatch", 0.6, true], ["hex_hatch", 0.6, true], ["vent_panel", 0.4, false]]},
	&"living_area": {"accent": Color(0.75, 0.50, 0.25), "wainscot": Color(0.42, 0.30, 0.19), "rail": "ribbed", "pipes": false, "lanes": false,
		"decals": [["vent_panel", 0.4, false], ["round_plate", 0.5, false]]},
	&"medical": {"accent": Color(0.25, 0.80, 0.75), "wainscot": Color(0.62, 0.74, 0.74), "rail": "ribbed", "pipes": false, "lanes": false,
		"decals": [["pill_lights", 0.3, false], ["vent_panel", 0.4, false], ["hex_hatch", 0.55, false]]},
	&"bathroom": {"accent": Color(0.40, 0.70, 0.85), "wainscot": Color(0.45, 0.65, 0.74), "rail": "ribbed", "pipes": false, "lanes": false,
		"decals": [["grille", 0.5, false], ["vent_strip", 0.6, false]]},
}
const DEFAULT_STYLE := {"accent": Color(0.7, 0.7, 0.7), "wainscot": Color(0.18, 0.18, 0.2), "rail": "ribbed", "pipes": false, "lanes": false, "decals": []}

## Which screen graphic each machine screen carries (scr_interface_<n>.png).
const SCREEN_GRAPHICS := {&"ops_computer": 1, &"scanners": 2, &"ftl_radio": 2, &"battery_array": 4, &"limnal_drive": 3, &"tactical": 1}

const WAINSCOT_TOP := 0.95 # metres above the floor
const RAIL_BOTTOM := 0.97
const RAIL_HEIGHT := 0.15
const PLATE_PROUD := 0.016
const DECAL_HEIGHT := 1.75 # centre of a wall decal above the floor (the free wall runs from the rail to the cove)

static var _textures := {}

var _v: ShipVisuals
var _l: InteriorLayout
var _roots := {}
var _materials := {}
var _rng := RandomNumberGenerator.new()
var _tintable_count := 0
## Counts for tests and the tour log.
var boxes_built := 0
var decals_built := 0


func build(visuals: ShipVisuals, layout: InteriorLayout) -> void:
	_v = visuals
	_l = layout
	for room_id in _l.rooms:
		var root := Node3D.new()
		root.name = "Detail_" + String(room_id)
		_v._target_for_room(_l, room_id).add_child(root)
		if not _l.is_pocket(room_id):
			if not _v._shell_nodes.has(room_id):
				_v._shell_nodes[room_id] = []
			(_v._shell_nodes[room_id] as Array).append(root)
		_roots[room_id] = root
		var style: Dictionary = ROOM_STYLES.get(room_id, DEFAULT_STYLE)
		_rng.seed = hash(String(room_id))
		for side in ["nose", "tail", "left", "right"]:
			if room_id == &"cockpit" and side == "nose":
				continue # the canopy closes the cockpit
			_build_wall(room_id, side, style)
		_build_ceiling(room_id, style)
		_build_floor(room_id, style)
		if GameSettings.instance().decals:
			_build_wall_decals(room_id, style)
	_build_thresholds()
	_build_crate_straps()
	_build_screen_graphics()


# ---------------------------------------------------------------------------------------------------------------- walls

func _wall_info(room_id: StringName, side: String) -> Dictionary:
	var room: Rect2 = _l.rooms[room_id]
	match side:
		"nose":
			return {"along_x": true, "face": room.position.y, "normal": Vector2(0, 1), "from": room.position.x, "to": room.end.x}
		"tail":
			return {"along_x": true, "face": room.end.y, "normal": Vector2(0, -1), "from": room.position.x, "to": room.end.x}
		"left":
			return {"along_x": false, "face": room.position.x, "normal": Vector2(1, 0), "from": room.position.y, "to": room.end.y}
	return {"along_x": false, "face": room.end.x, "normal": Vector2(-1, 0), "from": room.position.y, "to": room.end.y}


## A box standing on a wall face: `along` is its centre along the wall, `proud` how far it stands out of the face.
func _wall_box(room_id: StringName, info: Dictionary, box_name: String, along: float, length: float, y_from: float, y_to: float,
		proud: float, material: Material) -> MeshInstance3D:
	var normal: Vector2 = info["normal"]
	var face: float = info["face"]
	var height := y_to - y_from
	var middle_y := (y_from + y_to) * 0.5
	var size := Vector3(length, height, proud) if info["along_x"] else Vector3(proud, height, length)
	var at := Vector3(along, middle_y, face + normal.y * proud * 0.5) if info["along_x"] else Vector3(face + normal.x * proud * 0.5, middle_y, along)
	return _add_box(room_id, box_name, size, at, material)


func _add_box(room_id: StringName, box_name: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := _v._box_instance(size, material)
	instance.name = box_name
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(_roots[room_id] as Node3D).add_child(instance)
	boxes_built += 1
	return instance


## Stretches of the wall that are free of doorways and windows (with a margin each side), as [from, to] pairs along the wall.
func _structural_spans(room_id: StringName, side: String, info: Dictionary, margin: float) -> Array:
	var blockers: Array = []
	var wall := _l.wall_rect(room_id, side)
	var along_x: bool = info["along_x"]
	for portal in _l.portals.values():
		var opening: Rect2 = (portal as Portal).opening
		if opening.intersects(wall):
			blockers.append(Vector2(opening.position.x, opening.end.x) if along_x else Vector2(opening.position.y, opening.end.y))
	for window in _l.windows_in(room_id, side):
		blockers.append(Vector2(float(window["center"]) - float(window["width"]) * 0.5, float(window["center"]) + float(window["width"]) * 0.5))
	return _free_spans(float(info["from"]) + 0.06, float(info["to"]) - 0.06, blockers, margin)


## Like _structural_spans but also keeps clear of stations, tall furniture and the reactor standing near the wall: for decals.
func _decal_spans(room_id: StringName, side: String, info: Dictionary, margin: float) -> Array:
	var blockers: Array = []
	var wall := _l.wall_rect(room_id, side)
	var along_x: bool = info["along_x"]
	var face: float = info["face"]
	for portal in _l.portals.values():
		var opening: Rect2 = (portal as Portal).opening
		if opening.intersects(wall):
			blockers.append(Vector2(opening.position.x, opening.end.x) if along_x else Vector2(opening.position.y, opening.end.y))
	for window in _l.windows_in(room_id, side):
		blockers.append(Vector2(float(window["center"]) - float(window["width"]) * 0.5, float(window["center"]) + float(window["width"]) * 0.5))
	for point in _l.interact_points:
		if _l.portals.has(point["id"]):
			continue
		var position: Vector3 = point["position"]
		if _l.room_at(position.x, position.z) != room_id:
			continue
		var across := absf((position.z if along_x else position.x) - face)
		if across < 1.4:
			var along: float = position.x if along_x else position.z
			blockers.append(Vector2(along - 0.9, along + 0.9))
	for piece in _l.furniture:
		var at: Vector2 = piece["at"]
		var size: Vector3 = piece["size"]
		if _l.room_at(at.x, at.y) != room_id or float(piece["lift"]) + size.y < 0.8:
			continue
		var half := Vector2(size.x, size.z) * 0.5
		var across_edge := (absf(at.y - face) if along_x else absf(at.x - face)) - (half.y if along_x else half.x)
		if across_edge < 0.5:
			var centre: float = at.x if along_x else at.y
			var reach: float = half.x if along_x else half.y
			blockers.append(Vector2(centre - reach - 0.3, centre + reach + 0.3))
	if not _l.reactor_core.is_empty():
		var reactor: Vector2 = _l.reactor_core["at"]
		if _l.room_at(reactor.x, reactor.y) == room_id and absf((reactor.y if along_x else reactor.x) - face) < 1.6:
			var along_reactor: float = reactor.x if along_x else reactor.y
			blockers.append(Vector2(along_reactor - 1.2, along_reactor + 1.2))
	return _free_spans(float(info["from"]) + 0.3, float(info["to"]) - 0.3, blockers, margin)


static func _free_spans(start: float, finish: float, blockers: Array, margin: float) -> Array:
	var sorted := blockers.duplicate()
	sorted.sort_custom(func(first: Vector2, second: Vector2) -> bool: return first.x < second.x)
	var spans: Array = []
	var cursor := start
	for blocker: Vector2 in sorted:
		if blocker.x - margin > cursor:
			spans.append(Vector2(cursor, minf(blocker.x - margin, finish)))
		cursor = maxf(cursor, blocker.y + margin)
	if finish > cursor:
		spans.append(Vector2(cursor, finish))
	return spans.filter(func(span: Vector2) -> bool: return span.y - span.x > 0.25)


func _build_wall(room_id: StringName, side: String, style: Dictionary) -> void:
	var info := _wall_info(room_id, side)
	var floor_y := _l.floor_y
	var ceiling_y := _l.ceiling_y
	var wainscot := _surface(style["wainscot"], 0.65, 0.35, true)
	var accent := _emissive_strip(style["accent"], 0.9)
	var rail := _rail_material(style["rail"])
	var seam := _surface(Color(0.16, 0.17, 0.19), 0.8, 0.2, true)
	var index := 0
	for span: Vector2 in _structural_spans(room_id, side, info, 0.14):
		var length := span.y - span.x
		var count := maxi(1, roundi(length / 1.6))
		var pitch := length / float(count)
		# Lower wall: panels with a gap between, so the paint shows through as the seams.
		for panel in count:
			var middle := span.x + pitch * (float(panel) + 0.5)
			_wall_box(room_id, info, "Wainscot%d" % index, middle + 0.037, pitch - 0.05, floor_y + 0.15, floor_y + WAINSCOT_TOP, 0.022, wainscot)
			index += 1
		_wall_box(room_id, info, "RailAccent%d" % index, (span.x + span.y) * 0.5, length, floor_y + WAINSCOT_TOP + 0.005, floor_y + RAIL_BOTTOM - 0.005, 0.045, accent)
		var rail_instance := _wall_box(room_id, info, "Rail%d" % index, (span.x + span.y) * 0.5, length, floor_y + RAIL_BOTTOM, floor_y + RAIL_BOTTOM + RAIL_HEIGHT, 0.04,
			_rail_for_length(rail, length))
		rail_instance.name = "Rail%d" % index
		# Upper wall: a thin dark seam at every panel boundary.
		for boundary in count + 1:
			var along := span.x + pitch * float(boundary)
			_wall_box(room_id, info, "Seam%d_%d" % [index, boundary], along, 0.022, floor_y + RAIL_BOTTOM + RAIL_HEIGHT + 0.02, ceiling_y - 0.12, 0.012, seam)
		index += 1


# --------------------------------------------------------------------------------------------------------------- ceiling

func _build_ceiling(room_id: StringName, style: Dictionary) -> void:
	var room: Rect2 = _l.rooms[room_id]
	var ceiling_y := _l.ceiling_y
	var rib_material := _surface(Color(0.30, 0.32, 0.36), 0.5, 0.55, true)
	var width := room.size.x - 0.16
	var centre_x := room.get_center().x
	var centre_z := room.get_center().y
	var rib_pitch := 1.1
	var count := int(floor(room.size.y / rib_pitch))
	for index in count:
		var z := room.position.y + (float(index) + 0.5) * room.size.y / float(maxi(count, 1))
		if absf(z - centre_z) < 0.45:
			continue # the lamp panel hangs here
		_add_box(room_id, "CeilingRib%d" % index, Vector3(width, 0.09, 0.11), Vector3(centre_x, ceiling_y - 0.045, z), rib_material)
	# A cable tray along the nose side of the ceiling in the rooms wide enough to need one.
	if room.size.x > 5.0:
		var tray := _add_box(room_id, "CableTray", Vector3(width, 0.07, 0.26), Vector3(centre_x, ceiling_y - 0.165, room.position.y + 0.3), _rail_material("perforated"))
		tray.material_override = _rail_for_length(tray.material_override, width)
	if style["pipes"] and room.size.x > 2.0:
		var pipe_z := room.end.y - 0.3
		var pipe_material := _surface(Color(0.45, 0.47, 0.5), 0.35, 0.85, true)
		_pipe(room_id, "Pipe", Vector3(centre_x, ceiling_y - 0.22, pipe_z), width, 0.06, pipe_material)
		var coupling := _surface(style["accent"], 0.5, 0.4, true)
		var at_x := room.position.x + 0.5
		var number := 0
		while at_x < room.end.x - 0.3:
			_pipe(room_id, "Coupling%d" % number, Vector3(at_x, ceiling_y - 0.22, pipe_z), 0.12, 0.08, coupling)
			at_x += 1.8
			number += 1


func _pipe(room_id: StringName, pipe_name: String, at: Vector3, length: float, radius: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	mesh.rings = 1
	var instance := MeshInstance3D.new()
	instance.name = pipe_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.rotation_degrees = Vector3(0.0, 0.0, 90.0) # the cylinder's axis (y) lies along x
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(_roots[room_id] as Node3D).add_child(instance)


# ----------------------------------------------------------------------------------------------------------------- floor

func _build_floor(room_id: StringName, style: Dictionary) -> void:
	if not style["lanes"]:
		return
	var room: Rect2 = _l.rooms[room_id]
	var line := _surface(Color(0.62, 0.5, 0.1), 0.85, 0.0, true)
	for side in [-1.0, 1.0]:
		_add_box(room_id, "LaneLine", Vector3(0.05, 0.008, room.size.y - 0.3), Vector3(0.8 * side, _l.floor_y + 0.004, room.get_center().y), line)


## A worn plate across every doorway.
func _build_thresholds() -> void:
	var plate := _surface(Color(0.3, 0.31, 0.34), 0.45, 0.8, true)
	for portal_id in _l.portals:
		var opening: Rect2 = (_l.portals[portal_id] as Portal).opening
		var rooms := _l.portal_rooms(portal_id)
		if rooms.is_empty():
			continue
		var holder: StringName = rooms[0]
		for candidate in rooms:
			if _l.is_pocket(candidate):
				holder = candidate
		var crossing_z := opening.size.x >= opening.size.y
		var size := Vector3(opening.size.x + 0.1, 0.015, 0.34) if crossing_z else Vector3(0.34, 0.015, opening.size.y + 0.1)
		var at := Vector3(opening.get_center().x, _l.floor_y + 0.0075, opening.get_center().y)
		_add_box(holder, "Threshold_" + String(portal_id), size, at, plate)


# -------------------------------------------------------------------------------------------------------------- decals

func _build_wall_decals(room_id: StringName, style: Dictionary) -> void:
	var choices: Array = style["decals"]
	if choices.is_empty():
		return
	var placed := 0
	var cursor := _rng.randi() % choices.size()
	for side in ["nose", "tail", "left", "right"]:
		if room_id == &"cockpit" and side == "nose":
			continue
		var info := _wall_info(room_id, side)
		var on_wall := 0
		for span: Vector2 in _decal_spans(room_id, side, info, 0.2):
			var at := span.x + 0.2
			while at < span.y - 0.2 and on_wall < 3 and placed < 7:
				var choice: Array = choices[cursor % choices.size()]
				cursor += 1
				var width: float = choice[1]
				if at + width > span.y:
					at += 0.4
					continue
				if _place_wall_decal(room_id, info, choice[0], at + width * 0.5, width, choice[2]):
					placed += 1
					on_wall += 1
					at += width + 1.3
				else:
					at += 0.5
	for spot in _floor_decal_spots(room_id):
		_place_floor_decal(room_id, spot["name"], spot["at"], spot["width"], spot.get("yellow", false))


func _place_wall_decal(room_id: StringName, info: Dictionary, decal_name: String, along: float, width: float, yellow: bool) -> bool:
	var material := _plate_material(decal_name, yellow)
	if material == null:
		return false
	var aspect := float(material.albedo_texture.get_width()) / float(material.albedo_texture.get_height())
	var normal: Vector2 = info["normal"]
	var face: float = info["face"]
	var wall_normal := Vector3(normal.x, 0.0, normal.y)
	var centre := Vector3(along, _l.floor_y + DECAL_HEIGHT, face + normal.y * PLATE_PROUD) if info["along_x"] else Vector3(face + normal.x * PLATE_PROUD, _l.floor_y + DECAL_HEIGHT, along)
	_add_plate(room_id, "WallPlate_" + decal_name, Vector2(width, width / aspect), Transform3D(Basis.looking_at(-wall_normal, Vector3.UP), centre), material)
	return true


## Hatches and plates set into the deck where nothing stands: [{name, at (x, z), width, yellow}] for the room, kept only if the spot is clear.
func _floor_decal_spots(room_id: StringName) -> Array:
	var wanted := {
		&"cargo": [{"name": "round_hatch", "at": Vector2(-2.3, 6.45), "width": 1.1, "yellow": true}, {"name": "square_hatch", "at": Vector2(2.4, 6.45), "width": 1.1}],
		&"engineering": [{"name": "square_hatch", "at": Vector2(-2.3, 1.6), "width": 1.2}],
		&"turret_room": [{"name": "round_plate", "at": Vector2(2.2, 4.5), "width": 1.0}],
		&"cabin": [{"name": "hex_hatch", "at": Vector2(-2.4, -1.9), "width": 1.0}],
		&"airlock": [{"name": "round_hatch", "at": Vector2(0.0, 9.4), "width": 1.2, "yellow": true}],
	}
	var kept: Array = []
	for spot: Dictionary in wanted.get(room_id, []):
		var at: Vector2 = spot["at"]
		var half := float(spot["width"]) * 0.5 + 0.1
		var footprint := Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0)
		var clear := (_l.rooms[room_id] as Rect2).encloses(footprint)
		for obstacle in _l.obstacles:
			if obstacle.intersects(footprint):
				clear = false
		for station in _l.interact_points:
			if not _l.portals.has(station["id"]) and Vector2(station["position"].x, station["position"].z).distance_to(at) < half + 0.25:
				clear = false
		if clear:
			kept.append(spot)
	return kept


func _place_floor_decal(room_id: StringName, decal_name: String, at: Vector2, width: float, yellow: bool) -> void:
	var material := _plate_material(decal_name, yellow)
	if material == null:
		return
	var aspect := float(material.albedo_texture.get_width()) / float(material.albedo_texture.get_height())
	# Lying on the deck, top of the picture toward the nose (-z).
	var basis := Basis(Vector3.RIGHT, -PI * 0.5)
	_add_plate(room_id, "FloorPlate_" + decal_name, Vector2(width, width / aspect), Transform3D(basis, Vector3(at.x, _l.floor_y + 0.012, at.y)), material)


## A picture quad (alpha-cut atlas piece with its normal map) lying on a wall or the deck. Quads rather than projected Decal nodes:
## they look the same on every renderer and need no depth range, and nothing on the walls is deep enough to need projection.
func _add_plate(room_id: StringName, plate_name: String, size: Vector2, plate_transform: Transform3D, material: Material) -> void:
	var quad := QuadMesh.new()
	quad.size = size
	var instance := MeshInstance3D.new()
	instance.name = plate_name
	instance.mesh = quad
	instance.material_override = material
	instance.transform = plate_transform
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(_roots[room_id] as Node3D).add_child(instance)
	decals_built += 1


func _plate_material(decal_name: String, yellow: bool) -> StandardMaterial3D:
	var key := "p%s_%s" % [decal_name, yellow]
	if _materials.has(key):
		return _materials[key]
	var albedo := _decal_texture(decal_name, "yellow" if yellow else "albedo")
	if albedo == null:
		_materials[key] = null
		return null
	var material := StandardMaterial3D.new()
	material.albedo_texture = albedo
	material.albedo_color = Color(1.25, 1.25, 1.3) if not yellow else Color(1.3, 1.2, 1.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	material.roughness = 0.55
	material.metallic = 0.5
	var normal_map := _decal_texture(decal_name, "normal")
	if normal_map != null:
		material.normal_enabled = true
		material.normal_texture = normal_map
		material.normal_scale = 0.8
	_materials[key] = material
	_register_tintable(material)
	return material


# ------------------------------------------------------------------------------------------------------------ props, screens

## Two dark straps round every crate (the layout's pieces named crate_*), proud of its faces.
func _build_crate_straps() -> void:
	var strap := _surface(Color(0.1, 0.1, 0.11), 0.6, 0.5, true)
	for piece in _l.furniture:
		if not String(piece["name"]).begins_with("crate"):
			continue
		var at: Vector2 = piece["at"]
		var size: Vector3 = piece["size"]
		var room_id := _l.room_at(at.x, at.y)
		if room_id == &"" or not _roots.has(room_id):
			continue
		var middle_y := _l.floor_y + float(piece["lift"]) + size.y * 0.5
		for offset in [-0.3, 0.3]:
			_add_box(room_id, "CrateStrap", Vector3(0.07, size.y + 0.03, size.z + 0.03), Vector3(at.x + size.x * offset, middle_y, at.y), strap)


## A glowing interface graphic over each machine screen, under its status text (the text label floats 2 cm in front).
func _build_screen_graphics() -> void:
	for machine_id in _l.machine_screens:
		if not SCREEN_GRAPHICS.has(machine_id):
			continue
		var texture := _texture(SCREEN_DIR + "scr_interface_%d.png" % int(SCREEN_GRAPHICS[machine_id]))
		if texture == null:
			continue
		var spec: Dictionary = _l.machine_screens[machine_id]
		var at: Vector3 = spec["position"]
		var size: Vector3 = spec["size"]
		var room_id := _l.room_at(at.x, at.z)
		if room_id == &"" or not _roots.has(room_id):
			continue
		var centre := (_l.rooms[room_id] as Rect2).get_center()
		var side_wall := size.x < size.z
		var normal := Vector3(signf(centre.x - at.x), 0.0, 0.0) if side_wall else Vector3(0.0, 0.0, signf(centre.y - at.z))
		var thickness := minf(size.x, size.z)
		var quad := QuadMesh.new()
		quad.size = Vector2(maxf(size.x, size.z) * 0.94, size.y * 0.92)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_texture = texture
		material.albedo_color = Color(0.55, 0.8, 1.0, 0.5)
		var instance := MeshInstance3D.new()
		instance.name = "ScreenGraphic_" + String(machine_id)
		instance.mesh = quad
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var up := Vector3.UP
		instance.transform = Transform3D(Basis.looking_at(-normal, up), at + normal * (thickness * 0.5 + 0.008))
		(_roots[room_id] as Node3D).add_child(instance)


# -------------------------------------------------------------------------------------------------------------- materials

func _surface(colour: Color, roughness: float, metallic: float, tintable: bool) -> StandardMaterial3D:
	var key := "s%s_%s_%s" % [colour.to_html(), roughness, metallic]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	material.metallic = metallic
	_materials[key] = material
	if tintable:
		_register_tintable(material)
	return material


func _emissive_strip(colour: Color, energy: float) -> StandardMaterial3D:
	var key := "e%s_%s" % [colour.to_html(), energy]
	if _materials.has(key):
		return _materials[key]
	var material := ShipVisuals._emissive(colour, energy)
	_materials[key] = material
	return material


## The rail strips from the PSD source: a perforated plate, a ribbed bar, a black and a dark channel. Falls back to a plain metal.
func _rail_material(kind: String) -> StandardMaterial3D:
	var key := "r" + kind
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.roughness = 0.5
	material.metallic = 0.6
	var texture := _texture(TRIM_DIR + "trim_rail_%s.png" % kind)
	if texture != null:
		material.albedo_texture = texture
		material.texture_repeat = true
	else:
		material.albedo_color = Color(0.3, 0.32, 0.35)
	_materials[key] = material
	_register_tintable(material)
	return material


## A copy of a rail material whose texture repeats once per 1.2 m of wall, so the holes keep their size on any length.
func _rail_for_length(base: Material, length: float) -> Material:
	var source := base as StandardMaterial3D
	var bucket := roundi(length / 0.6)
	var key := "rl%d_%d" % [source.get_instance_id(), bucket]
	if _materials.has(key):
		return _materials[key]
	var material := source.duplicate() as StandardMaterial3D
	material.uv1_scale = Vector3(maxf(float(bucket) * 0.6 / 1.2, 0.25), 1.0, 1.0)
	_materials[key] = material
	_register_tintable(material)
	return material


## ShipVisuals.restyle() tints every material in _trim_materials, so the visual style (rodina is darker) reaches these too.
func _register_tintable(material: StandardMaterial3D) -> void:
	_tintable_count += 1
	_v._trim_materials[StringName("detail_%d" % _tintable_count)] = material


func _decal_texture(decal_name: String, kind: String) -> Texture2D:
	return _texture(DECAL_DIR + "dec_interior_%s_%s.png" % [decal_name, kind])


## The imported texture, or, before Godot has imported a new file (first launch after the files were added), the PNG read directly.
static func _texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		var loaded := ResourceLoader.load(path)
		if loaded is Texture2D:
			texture = loaded as Texture2D
	if texture == null and FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			image.generate_mipmaps()
			texture = ImageTexture.create_from_image(image)
	_textures[path] = texture
	return texture
