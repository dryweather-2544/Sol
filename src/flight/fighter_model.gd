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
	holder.rotation.y = MODEL_YAW
	holder.add_child(model)
	return holder


static func _instantiate(path: String) -> Node3D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var scene = load(path)
	if not scene is PackedScene:
		return null
	var node = (scene as PackedScene).instantiate()
	return node as Node3D


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
