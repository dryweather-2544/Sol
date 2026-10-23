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

## Wall, window-wall and door modules from the kit packs (see ATTRIBUTION.md), converted to .glb under assets/ships/kit/. They are optional: a
## machine without them keeps the plain box walls. The kit walls are large facade panels, so each is shrunk to the room's wall height.
const KIT_DIR := "res://assets/ships/kit/"
const KIT_WALLS := ["wall_plain", "wall_window"]

## Material key -> [texture crop of the kit atlas in assets/ships/kit/, metres per tile (0 = stretch once over each face), tint]. Keys not listed (and every
## key when the files are missing) keep the plain colours above.
const TEXTURED := {
	"console": ["tex_panel_console", 0.0, Color(0.9, 0.95, 1.0)], "dark": ["tex_dark", 1.2, Color(1, 1, 1)],
	"steel": ["tex_metal", 1.5, Color(1, 1, 1)], "white": ["tex_metal", 1.5, Color(1.15, 1.15, 1.2)], "ceiling": ["tex_metal", 1.5, Color(0.8, 0.82, 0.88)],
	"door": ["tex_metal", 1.5, Color(0.75, 0.8, 0.9)],
	"screen": ["tex_hud", 0.0, Color(1, 1, 1)], "glow_teal": ["tex_hud", 0.0, Color(1, 1, 1)]}
const FLOOR_TEXTURE := ["tex_diamond", 1.2]

static var _texture_cache := {}

## name -> {"parts": [[mesh, transform]], "box": AABB, "material": Material} (or {} when the file is missing), shared by every interior.
static var _kit_cache := {}


var plan: Plan
var _kit_materials := {}
var _batches := {}
var _materials := {}
var _doors := {}
var _time := 0.0
var _light_walls := false
const BRIDGE_TAIL_PULL := 0.3


## Builds the whole interior from the plan.
func build(ship_plan: Plan) -> void:
	plan = ship_plan
	var layout := plan.layout
	for room_id in layout.rooms:
		var room: Rect2 = layout.rooms[room_id]
		var kind := str(plan.kinds.get(room_id, "corridor"))
		if plan.bridges.has(room_id):
			# the bridge model brings its own floor and ceiling: keep ours clear of them so they never fight
			_slab(room, layout.floor_y - 0.25, layout.floor_y - 0.1, "floor_" + kind)
			_slab(room, layout.ceiling_y + 0.35, layout.ceiling_y + 0.5, "ceiling")
		else:
			_slab(room, layout.floor_y - 0.12, layout.floor_y, "floor_" + kind)
			_slab(room, layout.ceiling_y, layout.ceiling_y + 0.12, "ceiling")
		_build_lamps(room, kind)
	for portal_id in layout.portals:
		var portal: Portal = layout.portals[portal_id]
		_slab(portal.opening, layout.floor_y - 0.12, layout.floor_y, "floor_corridor")
		_slab(portal.opening, layout.ceiling_y, layout.ceiling_y + 0.12, "ceiling")
		_build_door(portal_id, portal)
	_build_walls()
	for room_id in plan.bridges:
		_place_bridge_model(room_id)
	for piece in layout.furniture:
		var at: Vector2 = piece["at"]
		if _in_dressed_bridge(at) and not str(piece["name"]).begins_with("chair_"):
			continue
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
	screens.emission_energy_multiplier = (0.45 + 0.1 * sin(_time * 2.3)) if screens.emission_texture != null else 1.15 + 0.25 * sin(_time * 2.3)


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
			if side == "nose" and plan.bridges.has(room_id):
				continue  # the model's own nose wall, with its whole window open to the outside
			_light_walls = plan.bridges.has(room_id)
			var skin := layout.wall_rect(room_id, side)
			var along_x := InteriorLayout.wall_runs_along_x(side)
			var holes := _holes_in(skin, along_x, room_id, side)
			if side == "tail" and _light_walls:
				skin.position.y -= BRIDGE_TAIL_PULL # the bridge's back wall stands inside the room, clear of the corridor's wall that shares the old line
			_build_wall(skin, along_x, holes, side)


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


func _build_wall(skin: Rect2, along_x: bool, holes: Array, side := "nose") -> void:
	var floor_y := plan.layout.floor_y
	var ceiling_y := plan.layout.ceiling_y + (0.36 if _light_walls else 0.0) # a bridge's ceiling slab sits above the model's own ceiling: the walls reach it
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
			_wall_piece(along_x, cursor, lo, cross_lo, thickness, floor_y, ceiling_y, "wall", side)
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
		_wall_piece(along_x, cursor, run_hi, cross_lo, thickness, floor_y, ceiling_y, "wall", side)


func _wall_piece(along_x: bool, lo: float, hi: float, cross_lo: float, thickness: float, y0: float, y1: float, key := "wall", side := "") -> void:
	var length := hi - lo
	if key == "wall" and _light_walls:
		key = "white" # the bridge's own walls match the model's pale panelling instead of the dark kit facades
	elif key == "wall" and side != "" and length >= 0.6 and _kit_wall(along_x, lo, hi, cross_lo, thickness, y0, y1, side):
		return
	var middle_along := (lo + hi) * 0.5
	var middle_cross := cross_lo + thickness * 0.5
	var middle_y := (y0 + y1) * 0.5
	if along_x:
		_batch_box(key, Vector3(middle_along, middle_y, middle_cross), Vector3(length, y1 - y0, thickness))
	else:
		_batch_box(key, Vector3(middle_cross, middle_y, middle_along), Vector3(thickness, y1 - y0, length))


# ------------------------------------------------------------------------------------------------ kit modules
## Loads one kit model (cached): its meshes with their transforms inside the model, the overall bounds and the first material.
static func _kit_piece(piece_name: String, open := false) -> Dictionary:
	var cache_key := piece_name + ("_open" if open else "")
	if _kit_cache.has(cache_key):
		return _kit_cache[cache_key]
	var result := {}
	var disk_path := ProjectSettings.globalize_path(KIT_DIR + piece_name + ".glb")
	if FileAccess.file_exists(disk_path):
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file(disk_path, state) == OK:
			var scene := document.generate_scene(state) as Node3D
			if scene != null:
				var parts: Array = []
				var box := AABB()
				var material: Material = null
				for node in scene.find_children("*", "MeshInstance3D", true, false):
					var instance := node as MeshInstance3D
					if instance.mesh == null:
						continue
					if open and (str(instance.name).begins_with("sheet") or str(instance.name).begins_with("panel_interior")):
						continue # an outer wall's painted window glass is left out, so the window really is open to the outside
					var local := _transform_in(instance, scene)
					parts.append([instance.mesh, local])
					var part_box: AABB = local * instance.mesh.get_aabb()
					box = part_box if parts.size() == 1 else box.merge(part_box)
					if material == null:
						material = instance.mesh.surface_get_material(0)
				if not parts.is_empty():
					result = {"parts": parts, "box": box, "material": material}
				scene.free()
	_kit_cache[cache_key] = result
	return result


static func _transform_in(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


## True when nothing lies beyond this wall segment: its windows then open onto the real outside instead of showing painted glass.
func _is_outer_wall(along_x: bool, lo: float, hi: float, cross_lo: float, thickness: float, side: String) -> bool:
	var middle := (lo + hi) * 0.5
	var outward := -0.8 if side == "nose" or side == "left" else thickness + 0.8
	var probe := Vector2(middle, cross_lo + outward) if along_x else Vector2(cross_lo + outward, middle)
	return plan.layout.room_at(probe.x, probe.y) == &""


## Fills a full-height wall segment with kit wall modules (every other one a window panel). False when the kit is not on this machine.
func _kit_wall(along_x: bool, lo: float, hi: float, cross_lo: float, thickness: float, y0: float, y1: float, side: String) -> bool:
	if y1 - y0 < 1.0:
		return false
	var open := _is_outer_wall(along_x, lo, hi, cross_lo, thickness, side)
	var plain := _kit_piece(KIT_WALLS[0], open)
	if plain.is_empty():
		return false
	var length := hi - lo
	var count := maxi(1, int(round(length / 3.9)))
	var step := length / float(count)
	# the module's inside face is -z; turn it to face into the room, and put the face on the room's side of the skin
	var yaw := 0.0
	var face_at := cross_lo
	match side:
		"nose":
			yaw = PI
			face_at = cross_lo + thickness
		"left":
			yaw = -PI * 0.5
			face_at = cross_lo + thickness
		"right":
			yaw = PI * 0.5
		_:
			yaw = 0.0
	for index in count:
		var module := plain
		if index % 2 == 1 and not _kit_piece(KIT_WALLS[1], open).is_empty():
			module = _kit_piece(KIT_WALLS[1], open)
		var box: AABB = module["box"]
		var scale_y := (y1 - y0) / maxf(box.size.y, 0.001)
		var scale_x := step / maxf(box.size.x, 0.001)
		var scale_z := thickness / maxf(box.size.z, 0.001)
		var along_middle := lo + step * (float(index) + 0.5)
		var origin := Vector3(along_middle, y0, face_at) if along_x else Vector3(face_at, y0, along_middle)
		var placed := Transform3D(Basis(Vector3.UP, yaw), origin) * Transform3D(Basis.from_scale(Vector3(scale_x, scale_y, scale_z)), Vector3.ZERO)
		placed = placed * Transform3D(Basis.IDENTITY, Vector3(-box.get_center().x, -box.position.y, -box.position.z))
		_batch_kit((KIT_WALLS[0] if module == plain else KIT_WALLS[1]) + ("_open" if open else ""), module, placed)
	return true


## Adds every mesh of a kit module, transformed, to the merged batch for that module's material.
func _batch_kit(key: String, module: Dictionary, placed: Transform3D, cull := Callable()) -> void:
	var batch_key := "kit_" + key
	if not _batches.has(batch_key):
		_batches[batch_key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "i": PackedInt32Array(), "uv": PackedVector2Array()}
		_kit_materials[batch_key] = module["material"]
	var batch: Dictionary = _batches[batch_key]
	var vertices: PackedVector3Array = batch["v"]
	var normals: PackedVector3Array = batch["n"]
	var indices: PackedInt32Array = batch["i"]
	var uvs: PackedVector2Array = batch["uv"]
	var normal_basis := placed.basis.inverse().transposed()
	for part in module["parts"]:
		var mesh: Mesh = part[0]
		var local: Transform3D = part[1]
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var source_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var first := vertices.size()
			var full := placed * local
			var full_normal := (normal_basis * local.basis)
			for i in source_vertices.size():
				vertices.append(full * source_vertices[i])
				normals.append((full_normal * (source_normals[i] if i < source_normals.size() else Vector3.UP)).normalized())
				uvs.append(source_uvs[i] if i < source_uvs.size() else Vector2.ZERO)
			if source_indices.is_empty():
				for i in source_vertices.size():
					indices.append(first + i)
			else:
				for i in range(0, source_indices.size() - 2, 3):
					if cull.is_valid():
						var inside_model: Vector3 = local * ((source_vertices[source_indices[i]] + source_vertices[source_indices[i + 1]] + source_vertices[source_indices[i + 2]]) / 3.0)
						if bool(cull.call(inside_model)):
							continue
					indices.append(first + source_indices[i])
					indices.append(first + source_indices[i + 1])
					indices.append(first + source_indices[i + 2])
	batch["v"] = vertices
	batch["n"] = normals
	batch["i"] = indices
	batch["uv"] = uvs


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
	var tile := _tile_for(key)
	if tile >= 0.0 and not batch.has("uv"):
		batch["uv"] = PackedVector2Array()
	var box_uvs: PackedVector2Array = batch["uv"] if batch.has("uv") else PackedVector2Array()
	for face in FACES:
		var normal: Vector3 = face[0]
		var corners: Array = face[1]
		var first := vertices.size()
		var corner_index := 0
		for corner in corners:
			var point: Vector3 = centre + (corner as Vector3) * half
			vertices.append(point)
			normals.append(normal)
			if tile >= 0.0:
				if tile == 0.0:
					box_uvs.append(Vector2([0.0, 1.0, 1.0, 0.0][corner_index], [1.0, 1.0, 0.0, 0.0][corner_index]))
				elif absf(normal.y) > 0.5:
					box_uvs.append(Vector2(point.x, point.z) / tile)
				elif absf(normal.x) > 0.5:
					box_uvs.append(Vector2(point.z, -point.y) / tile)
				else:
					box_uvs.append(Vector2(point.x, -point.y) / tile)
			corner_index += 1
		# the faces are listed counter-clockwise from outside; Godot's front side is clockwise
		indices.append_array(PackedInt32Array([first, first + 2, first + 1, first, first + 3, first + 2]))
	batch["v"] = vertices
	batch["n"] = normals
	batch["i"] = indices
	if tile >= 0.0:
		batch["uv"] = box_uvs
	_batches[key] = batch


## Metres per texture tile for a box material (0 = stretched over each face), or -1 when it has no texture.
func _tile_for(key: String) -> float:
	if _texture_for(key) == null:
		return -1.0
	if key.begins_with("floor_"):
		return float(FLOOR_TEXTURE[1])
	return float(TEXTURED[key][1])


func _texture_for(key: String) -> Texture2D:
	var file := ""
	if key.begins_with("floor_"):
		file = FLOOR_TEXTURE[0]
	elif TEXTURED.has(key):
		file = TEXTURED[key][0]
	else:
		return null
	if not _texture_cache.has(file):
		var path := ProjectSettings.globalize_path(KIT_DIR + file + ".png")
		var texture: Texture2D = null
		if FileAccess.file_exists(path):
			var image := Image.load_from_file(path)
			if image != null:
				image.generate_mipmaps()
				texture = ImageTexture.create_from_image(image)
		_texture_cache[file] = texture
	return _texture_cache[file]


func _flush_batches() -> void:
	for key in _batches:
		var batch: Dictionary = _batches[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = batch["v"]
		arrays[Mesh.ARRAY_NORMAL] = batch["n"]
		arrays[Mesh.ARRAY_INDEX] = batch["i"]
		if batch.has("uv"):
			arrays[Mesh.ARRAY_TEX_UV] = batch["uv"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, _kit_materials[key] if _kit_materials.has(key) else _material(str(key)))
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
	var texture := _texture_for(key)
	if texture != null:
		material.albedo_texture = texture
		material.texture_repeat = true
		if key.begins_with("floor_"):
			material.albedo_color = (spec[0] as Color).lightened(0.35)
		else:
			material.albedo_color = TEXTURED[key][2]
	var glow := float(spec[3])
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = spec[0]
		if texture != null:
			material.emission = Color.WHITE
			material.emission_texture = texture
			material.albedo_color = Color(0.15, 0.2, 0.3)
			glow = 0.5
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


# ------------------------------------------------------------------------------------------------ bridge set
## The cropped control room from the Spaceship 003 pack (see ATTRIBUTION.md), one scene per file, shared by every interior.
static var _bridge_cache := {}


static func _bridge_scene(file: String) -> Node3D:
	if _bridge_cache.has(file):
		return _bridge_cache[file]
	var scene: Node3D = null
	var path := ProjectSettings.globalize_path(Plan.BRIDGE_DIR + file)
	if FileAccess.file_exists(path):
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file(path, state) == OK:
			scene = document.generate_scene(state) as Node3D
	_bridge_cache[file] = scene
	return scene


## True when this furniture spot is inside a bridge the model dresses (the plan already removed the generated pieces; only chairs stay).
func _in_dressed_bridge(at: Vector2) -> bool:
	for room_id in plan.bridges:
		if (plan.bridges[room_id]["room"] as Rect2).has_point(at):
			return true
	return false


func _place_bridge_model(room_id: StringName) -> void:
	var info: Dictionary = plan.bridges[room_id]
	var scene := _bridge_scene(str(info["file"]))
	if scene == null:
		return
	var room: Rect2 = info["room"]
	var instance := scene.duplicate() as Node3D
	var scale_x := float(info["scale_x"])
	var origin := Vector3(room.get_center().x, plan.layout.floor_y + 0.02, room.position.y)
	instance.transform = Transform3D(Basis.from_scale(Vector3(scale_x, 1.0, float(info["scale_z"]))), origin) \
			* Transform3D(Basis.IDENTITY, Vector3(-Plan.BRIDGE_MODEL_CENTRE_X, 0.0, -Plan.BRIDGE_MODEL_NOSE_Z))
	for node in instance.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.name = "BridgeSet_" + str(room_id)
	add_child(instance)
