extends Node3D
## Draws a big ship's interior from its plan: floors, ceilings, walls with the doorways and windows cut out, sliding doors, furniture, ceiling lamps.
## Everything static is merged into one mesh per material (about thirty draw calls a ship); only the door leaves and the lamps are separate nodes.
## The interior is plain geometry: where a person may walk is decided by the plan's InteriorLayout, not by physics bodies.

const Plan := preload("res://src/bigship/big_ship_plan.gd")

const DOOR_HEIGHT := 2.1
## A door opens when someone is this close to its middle.
const OPEN_DISTANCE := 3.4
## Ceiling lamps are brightened by this, so floors and furniture read clearly rather than near-black.
const LAMP_BOOST := 2.4

## Box faces: outward normal and the four corners (counter-clockwise seen from outside, in half-size units).
const FACES := [
	[Vector3(1, 0, 0), [Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(1, -1, 1)]],
	[Vector3(-1, 0, 0), [Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1), Vector3(-1, -1, -1)]],
	[Vector3(0, 1, 0), [Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)]],
	[Vector3(0, -1, 0), [Vector3(-1, -1, 1), Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1)]],
	[Vector3(0, 0, 1), [Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]],
	[Vector3(0, 0, -1), [Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)]]]

## Material key -> [colour, metallic, roughness, glow (0 = none)]. The keys are the ones the generated furniture uses.
const MATERIALS := {
	"console": [Color(0.16, 0.19, 0.25), 0.5, 0.5, 0.0],
	"steel": [Color(0.55, 0.58, 0.62), 0.8, 0.4, 0.0],
	"white": [Color(0.86, 0.88, 0.9), 0.1, 0.6, 0.0],
	"wood": [Color(0.45, 0.3, 0.18), 0.0, 0.7, 0.0],
	"linen": [Color(0.8, 0.78, 0.7), 0.0, 0.9, 0.0],
	"screen": [Color(0.1, 0.65, 0.6), 0.0, 0.3, 1.2],
	"crate": [Color(0.5, 0.4, 0.25), 0.1, 0.8, 0.0],
	"glow_teal": [Color(0.1, 0.9, 0.9), 0.0, 0.3, 1.6],
	"glow_green": [Color(0.25, 0.85, 0.3), 0.0, 0.5, 1.0],
	"glow_amber": [Color(1.0, 0.65, 0.15), 0.0, 0.4, 1.5],
	"glow_red": [Color(1.0, 0.2, 0.15), 0.0, 0.4, 1.5],
	"glass": [Color(0.6, 0.8, 0.95, 0.25), 0.0, 0.05, 0.0],
	"fabric": [Color(0.2, 0.3, 0.5), 0.0, 0.9, 0.0],
	"carpet": [Color(0.35, 0.18, 0.2), 0.0, 1.0, 0.0],
	"planter": [Color(0.3, 0.22, 0.15), 0.0, 0.9, 0.0],
	"pipe": [Color(0.6, 0.5, 0.35), 0.8, 0.4, 0.0],
	"dark": [Color(0.12, 0.13, 0.15), 0.4, 0.5, 0.0],
	"grey_fabric": [Color(0.4, 0.42, 0.45), 0.0, 0.9, 0.0],
	"red_fabric": [Color(0.55, 0.12, 0.12), 0.0, 0.9, 0.0],
	"wall": [Color(0.6, 0.64, 0.7), 0.2, 0.7, 0.0],
	"ceiling": [Color(0.42, 0.45, 0.5), 0.2, 0.8, 0.0],
	"door": [Color(0.5, 0.54, 0.6), 0.8, 0.35, 0.0],
	"lamp_panel": [Color(1.0, 0.97, 0.9), 0.0, 0.5, 2.0]}

const FLOOR_COLOURS := {
	"bridge": Color(0.14, 0.18, 0.28), "captain": Color(0.3, 0.2, 0.14), "corridor": Color(0.26, 0.27, 0.3), "quarters": Color(0.32, 0.27, 0.2),
	"galley": Color(0.4, 0.38, 0.36), "mess": Color(0.36, 0.3, 0.26), "medical": Color(0.55, 0.62, 0.6), "cargo": Color(0.22, 0.2, 0.17),
	"engineering": Color(0.3, 0.26, 0.18), "lab": Color(0.45, 0.55, 0.58), "armoury": Color(0.2, 0.17, 0.17), "lounge": Color(0.34, 0.2, 0.3),
	"greenhouse": Color(0.2, 0.3, 0.18), "workshop": Color(0.3, 0.28, 0.2), "ops": Color(0.16, 0.19, 0.3), "airlock": Color(0.35, 0.2, 0.18),
	"hangar": Color(0.24, 0.25, 0.3), "core": Color(0.34, 0.24, 0.16), "atrium": Color(0.3, 0.38, 0.28), "storage": Color(0.27, 0.26, 0.22),
	"brig": Color(0.3, 0.3, 0.32), "comms": Color(0.2, 0.26, 0.34), "observation": Color(0.22, 0.28, 0.38), "troop": Color(0.26, 0.28, 0.2)}

## Room kind -> [lamp colour, lamp energy].
const LAMPS := {
	"bridge": [Color(0.75, 0.85, 1.0), 1.0], "captain": [Color(1.0, 0.85, 0.65), 0.9], "corridor": [Color(0.85, 0.9, 1.0), 0.9],
	"quarters": [Color(1.0, 0.88, 0.7), 0.8], "galley": [Color(1.0, 0.95, 0.85), 1.0], "mess": [Color(1.0, 0.92, 0.8), 0.9],
	"medical": [Color(0.85, 1.0, 0.95), 1.2], "cargo": [Color(0.9, 0.9, 0.85), 0.9], "engineering": [Color(1.0, 0.7, 0.4), 1.0],
	"lab": [Color(0.8, 0.95, 1.0), 1.1], "armoury": [Color(1.0, 0.8, 0.8), 0.9], "lounge": [Color(1.0, 0.8, 0.9), 0.8],
	"greenhouse": [Color(0.8, 1.0, 0.7), 1.1], "workshop": [Color(1.0, 0.92, 0.75), 1.0], "ops": [Color(0.7, 0.8, 1.0), 0.9],
	"airlock": [Color(1.0, 0.9, 0.7), 0.9], "hangar": [Color(0.9, 0.95, 1.0), 1.0], "core": [Color(1.0, 0.8, 0.55), 1.0],
	"atrium": [Color(0.95, 1.0, 0.9), 1.2], "storage": [Color(0.95, 0.95, 0.85), 0.8], "brig": [Color(0.9, 0.9, 1.0), 0.8],
	"comms": [Color(0.75, 0.9, 1.0), 0.9], "observation": [Color(0.8, 0.85, 1.0), 0.7], "troop": [Color(0.95, 0.95, 0.85), 0.9]}

var plan: Plan
var _batches := {}
var _materials := {}
var _doors := {}
var _time := 0.0


## Builds the whole interior from the plan.
func build(ship_plan: Plan) -> void:
	plan = ship_plan
	var layout := plan.layout
	for room_id in layout.rooms:
		var room: Rect2 = layout.rooms[room_id]
		var kind := str(plan.kinds.get(room_id, "corridor"))
		_slab(room, layout.floor_y - 0.12, layout.floor_y, "floor_" + kind)
		_slab(room, layout.ceiling_y, layout.ceiling_y + 0.12, "ceiling")
		_build_lamps(room, kind)
	for portal_id in layout.portals:
		var portal: Portal = layout.portals[portal_id]
		_slab(portal.opening, layout.floor_y - 0.12, layout.floor_y, "floor_corridor")
		_slab(portal.opening, layout.ceiling_y, layout.ceiling_y + 0.12, "ceiling")
		_build_door(portal_id, portal)
	_build_walls()
	for piece in layout.furniture:
		var at: Vector2 = piece["at"]
		var size: Vector3 = piece["size"]
		var key := str(piece["material"])
		if not MATERIALS.has(key):
			key = "steel"
		_batch_box(key, Vector3(at.x, layout.floor_y + float(piece["lift"]) + size.y * 0.5, at.y), size)
	_flush_batches()


## Opens and closes the doors for someone standing at this ship-local point, and pulses the screens.
func update(player_position: Vector3, delta: float) -> void:
	_time += delta
	var here := Vector2(player_position.x, player_position.z)
	for portal_id in plan.layout.portals:
		var portal: Portal = plan.layout.portals[portal_id]
		if portal.kind == Portal.Kind.AIRLOCK_OUTER:
			continue
		portal.target_open = here.distance_to(portal.opening.get_center()) < OPEN_DISTANCE
		portal.update(delta)
		_move_door(portal_id, portal)
	var screens := _material("screen")
	screens.emission_energy_multiplier = 1.15 + 0.25 * sin(_time * 2.3)


## Opens every door at once (used when the ship is only looked at, and by tests).
func open_all_doors() -> void:
	for portal_id in plan.layout.portals:
		var portal: Portal = plan.layout.portals[portal_id]
		if portal.kind != Portal.Kind.AIRLOCK_OUTER:
			portal.open_factor = 1.0
			portal.target_open = true
			_move_door(portal_id, portal)


# ------------------------------------------------------------------------------------------------ structure
func _slab(rect: Rect2, y0: float, y1: float, key: String) -> void:
	var middle := rect.get_center()
	_batch_box(key, Vector3(middle.x, (y0 + y1) * 0.5, middle.y), Vector3(rect.size.x, y1 - y0, rect.size.y))


func _build_walls() -> void:
	var layout := plan.layout
	for room_id in layout.rooms:
		for side in ["nose", "tail", "left", "right"]:
			var skin := layout.wall_rect(room_id, side)
			var along_x := InteriorLayout.wall_runs_along_x(side)
			_build_wall(skin, along_x, _holes_in(skin, along_x, room_id, side))


## The doorways and windows that cut one wall, sorted along it: {lo, hi, bottom, top, glass}.
func _holes_in(skin: Rect2, along_x: bool, room_id: StringName, side: String) -> Array:
	var layout := plan.layout
	var holes: Array = []
	for portal_id in layout.portals:
		var opening: Rect2 = (layout.portals[portal_id] as Portal).opening
		if skin.intersects(opening):
			var lo := opening.position.x if along_x else opening.position.y
			var hi := lo + (opening.size.x if along_x else opening.size.y)
			holes.append({"lo": lo, "hi": hi, "bottom": layout.floor_y, "top": layout.floor_y + DOOR_HEIGHT, "glass": false})
	for window in layout.windows_in(room_id, side):
		var middle: float = window["center"]
		var half: float = float(window["width"]) * 0.5
		var sill: float = float(window["sill"])
		holes.append({"lo": middle - half, "hi": middle + half, "bottom": layout.floor_y + sill, "top": layout.floor_y + sill + float(window["height"]), "glass": true})
	holes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["lo"]) < float(b["lo"]))
	return holes


func _build_wall(skin: Rect2, along_x: bool, holes: Array) -> void:
	var floor_y := plan.layout.floor_y
	var ceiling_y := plan.layout.ceiling_y
	var run_lo := skin.position.x if along_x else skin.position.y
	var run_hi := skin.end.x if along_x else skin.end.y
	var cross_lo := skin.position.y if along_x else skin.position.x
	var thickness := skin.size.y if along_x else skin.size.x
	var cursor := run_lo
	for hole in holes:
		var lo := maxf(float(hole["lo"]), run_lo)
		var hi := minf(float(hole["hi"]), run_hi)
		if hi <= lo:
			continue
		if lo > cursor:
			_wall_piece(along_x, cursor, lo, cross_lo, thickness, floor_y, ceiling_y)
		var bottom := float(hole["bottom"])
		var top := float(hole["top"])
		if bottom > floor_y + 0.001:
			_wall_piece(along_x, lo, hi, cross_lo, thickness, floor_y, bottom)
		if top < ceiling_y - 0.001:
			_wall_piece(along_x, lo, hi, cross_lo, thickness, top, ceiling_y)
		if bool(hole["glass"]):
			_wall_piece(along_x, lo, hi, cross_lo + thickness * 0.4, thickness * 0.2, bottom, top, "glass")
		cursor = maxf(cursor, hi)
	if cursor < run_hi:
		_wall_piece(along_x, cursor, run_hi, cross_lo, thickness, floor_y, ceiling_y)


func _wall_piece(along_x: bool, lo: float, hi: float, cross_lo: float, thickness: float, y0: float, y1: float, key := "wall") -> void:
	var length := hi - lo
	var middle_along := (lo + hi) * 0.5
	var middle_cross := cross_lo + thickness * 0.5
	var middle_y := (y0 + y1) * 0.5
	if along_x:
		_batch_box(key, Vector3(middle_along, middle_y, middle_cross), Vector3(length, y1 - y0, thickness))
	else:
		_batch_box(key, Vector3(middle_cross, middle_y, middle_along), Vector3(thickness, y1 - y0, length))


# ------------------------------------------------------------------------------------------------ doors
func _build_door(portal_id: StringName, portal: Portal) -> void:
	var layout := plan.layout
	var opening := portal.opening
	var along_x := opening.size.x > opening.size.y
	var middle := opening.get_center()
	var span := opening.size.x if along_x else opening.size.y
	var thickness := opening.size.y if along_x else opening.size.x
	var light_key := "glow_teal"
	if portal.kind == Portal.Kind.AIRLOCK_INNER:
		light_key = "glow_amber"
	elif portal.kind == Portal.Kind.AIRLOCK_OUTER:
		light_key = "glow_red"
	var lintel_y := layout.floor_y + DOOR_HEIGHT - 0.05
	if along_x:
		_batch_box(light_key, Vector3(middle.x, lintel_y, middle.y), Vector3(span, 0.05, thickness + 0.04))
	else:
		_batch_box(light_key, Vector3(middle.x, lintel_y, middle.y), Vector3(thickness + 0.04, 0.05, span))
	if portal.kind == Portal.Kind.AIRLOCK_OUTER:
		# the outside door stays shut: one plain leaf
		if along_x:
			_batch_box("door", Vector3(middle.x, layout.floor_y + DOOR_HEIGHT * 0.5, middle.y), Vector3(span, DOOR_HEIGHT, thickness * 0.7))
		else:
			_batch_box("door", Vector3(middle.x, layout.floor_y + DOOR_HEIGHT * 0.5, middle.y), Vector3(thickness * 0.7, DOOR_HEIGHT, span))
		return
	var leaves: Array = []
	for i in 2:
		var leaf := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(span * 0.5, DOOR_HEIGHT, thickness * 0.6) if along_x else Vector3(thickness * 0.6, DOOR_HEIGHT, span * 0.5)
		mesh.material = _material("door")
		leaf.mesh = mesh
		leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(leaf)
		leaves.append(leaf)
	_doors[portal_id] = {"leaves": leaves, "along_x": along_x, "middle": middle, "span": span}
	_move_door(portal_id, portal)


func _move_door(portal_id: StringName, portal: Portal) -> void:
	if not _doors.has(portal_id):
		return
	var door: Dictionary = _doors[portal_id]
	var span: float = door["span"]
	var middle: Vector2 = door["middle"]
	var along_x: bool = door["along_x"]
	var offset := span * 0.25 + portal.open_factor * span * 0.5
	var y := plan.layout.floor_y + DOOR_HEIGHT * 0.5
	var leaves: Array = door["leaves"]
	for i in 2:
		var direction := -1.0 if i == 0 else 1.0
		var leaf: MeshInstance3D = leaves[i]
		if along_x:
			leaf.position = Vector3(middle.x + direction * offset, y, middle.y)
		else:
			leaf.position = Vector3(middle.x, y, middle.y + direction * offset)


# ------------------------------------------------------------------------------------------------ lamps
func _build_lamps(room: Rect2, kind: String) -> void:
	var layout := plan.layout
	var spec: Array = LAMPS.get(kind, [Color(1, 1, 1), 0.9])
	var columns := maxi(1, int(round(room.size.x / 7.0)))
	var rows := maxi(1, int(round(room.size.y / 7.0)))
	var cell_x := room.size.x / float(columns)
	var cell_z := room.size.y / float(rows)
	var height := layout.ceiling_y - layout.floor_y
	var reach := sqrt(cell_x * cell_x * 0.25 + cell_z * cell_z * 0.25 + height * height) + 1.6
	for column in columns:
		for row in rows:
			var x := room.position.x + (float(column) + 0.5) * cell_x
			var z := room.position.y + (float(row) + 0.5) * cell_z
			var lamp := OmniLight3D.new()
			lamp.light_color = spec[0]
			lamp.light_energy = float(spec[1]) * LAMP_BOOST
			lamp.omni_range = reach
			lamp.shadow_enabled = false
			lamp.position = Vector3(x, layout.ceiling_y - 0.4, z)
			add_child(lamp)
			_batch_box("lamp_panel", Vector3(x, layout.ceiling_y - 0.03, z), Vector3(minf(1.2, cell_x * 0.4), 0.05, 0.4))


# ------------------------------------------------------------------------------------------------ merged meshes
func _batch_box(key: String, centre: Vector3, size: Vector3) -> void:
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return
	if not _batches.has(key):
		_batches[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "i": PackedInt32Array()}
	var batch: Dictionary = _batches[key]
	var vertices: PackedVector3Array = batch["v"]
	var normals: PackedVector3Array = batch["n"]
	var indices: PackedInt32Array = batch["i"]
	var half := size * 0.5
	for face in FACES:
		var normal: Vector3 = face[0]
		var corners: Array = face[1]
		var first := vertices.size()
		for corner in corners:
			vertices.append(centre + (corner as Vector3) * half)
			normals.append(normal)
		# the faces are listed counter-clockwise from outside; Godot's front side is clockwise
		indices.append_array(PackedInt32Array([first, first + 2, first + 1, first, first + 3, first + 2]))
	batch["v"] = vertices
	batch["n"] = normals
	batch["i"] = indices
	_batches[key] = batch


func _flush_batches() -> void:
	for key in _batches:
		var batch: Dictionary = _batches[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = batch["v"]
		arrays[Mesh.ARRAY_NORMAL] = batch["n"]
		arrays[Mesh.ARRAY_INDEX] = batch["i"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, _material(str(key)))
		var instance := MeshInstance3D.new()
		instance.name = "Merged_" + str(key)
		instance.mesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
	_batches.clear()


func _material(key: String) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var spec: Array = _spec_for(key)
	var material := StandardMaterial3D.new()
	material.albedo_color = spec[0]
	material.metallic = float(spec[1])
	material.roughness = float(spec[2])
	var glow := float(spec[3])
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = spec[0]
		material.emission_energy_multiplier = glow
	if key == "glass":
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = material
	return material


func _spec_for(key: String) -> Array:
	if MATERIALS.has(key):
		return MATERIALS[key]
	if key.begins_with("floor_"):
		return [FLOOR_COLOURS.get(key.substr(6), Color(0.3, 0.3, 0.3)), 0.1, 0.6, 0.0]
	return [Color(0.5, 0.5, 0.5), 0.2, 0.7, 0.0]
