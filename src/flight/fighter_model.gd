class_name FighterModel
extends RefCounted
## Builds the visible shape of a fighter under a Ship node: the .glb scaled to FighterDef.size and centred, nose to -z.
## The pack's models face +z (the nose is the narrow end), so they are turned half a revolution. Falls back to the
## placeholder ship shape when the model file is missing (it is not committed: see ATTRIBUTION.md).

const MODEL_YAW := PI


## Returns the holder node (a child of ship_node).
static func build(ship_node: Node3D, def: FighterDef) -> Node3D:
	var holder := Node3D.new()
	holder.name = "FighterModel"
	ship_node.add_child(holder)
	var model := _instantiate(def.model_path)
	if model == null:
		PlaceholderShipMesh.build(holder, def.hull_color)
		holder.scale = Vector3.ONE * (def.size / FighterDef.REFERENCE_SIZE)
		return holder
	var box := _bounds(model, Transform3D.IDENTITY, [])
	if box.size == Vector3.ZERO:
		holder.add_child(model)
		return holder
	var model_scale := def.size / maxf(box.size.x, maxf(box.size.y, box.size.z))
	model.scale = Vector3.ONE * model_scale
	model.position = -box.get_center() * model_scale
	holder.rotation.y = def.hull_yaw
	holder.add_child(model)
	preload("res://src/core/ship_style.gd").apply_fighter(model, int(def.role), def.is_big_ship) # Valheim-style ship paint; SOL_SHIP_STYLE=off disables
	# the real extents, so landing gear contact (Ship) sits on the model's own underside instead of a guessed height
	holder.set_meta("half_extents", box.size * model_scale * 0.5)
	return holder


## Raw glTF scenes read straight from disk (path -> scene, or null), for models the editor has not imported yet.
static var _runtime := {}


static func _instantiate(path: String) -> Node3D:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		var scene = load(path)
		if scene is PackedScene:
			return (scene as PackedScene).instantiate() as Node3D
		return null
	# Not imported (the editor has not scanned the file yet): read it from disk so a new model works without opening the editor first.
	if not _runtime.has(path):
		var loaded: Node3D = null
		var disk_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(disk_path):
			var document := GLTFDocument.new()
			var state := GLTFState.new()
			if document.append_from_file(disk_path, state) == OK:
				loaded = document.generate_scene(state) as Node3D
		_runtime[path] = loaded
	var original: Node3D = _runtime[path]
	if original == null:
		return null
	return original.duplicate() as Node3D


## Bounding box of every mesh under node, in the space of node's parent. `accumulated` is a one-element scratch array.
static func _bounds(node: Node, parent_transform: Transform3D, accumulated: Array) -> AABB:
	var node_transform := parent_transform
	if node is Node3D:
		node_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_box: AABB = node_transform * (node as MeshInstance3D).mesh.get_aabb()
		if accumulated.is_empty():
			accumulated.append(mesh_box)
		else:
			accumulated[0] = (accumulated[0] as AABB).merge(mesh_box)
	for child in node.get_children():
		_bounds(child, node_transform, accumulated)
	return accumulated[0] if not accumulated.is_empty() else AABB()
