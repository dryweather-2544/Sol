extends RefCounted
## Builds a big ship's outer hull for the menu preview and the walkable view's "hull view": the model file read from disk, scaled so its longest
## horizontal extent is the ship's hull_extent, centred, nose to -z. The models are git-ignored (see ATTRIBUTION.md); a plain stand-in hull is drawn without one.

## Models read so far (path -> the scene, never added to the tree; each build copies it).
static var _loaded := {}


## Adds the hull under `parent` and returns the holder node (a child of `parent`, centred on its origin).
static func build(parent: Node3D, def) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Hull_" + str(def.id)
	parent.add_child(holder)
	var model := _copy_of(str(def.hull_path))
	if model == null:
		_add_stand_in(holder, float(def.hull_extent), Color(def.accent))
		return holder
	var found: Array = []
	_collect_bounds(model, Transform3D.IDENTITY, found)
	if found.is_empty():
		holder.add_child(model)
		return holder
	var box: AABB = found[0]
	var extent := maxf(box.size.x, box.size.z)
	if extent <= 0.0:
		holder.add_child(model)
		return holder
	var model_scale := float(def.hull_extent) / extent
	model.scale = Vector3.ONE * model_scale
	model.position = -box.get_center() * model_scale
	holder.rotation.y = float(def.hull_yaw)
	holder.add_child(model)
	preload("res://src/core/ship_style.gd").apply_hull(model, str(def.id)) # Valheim-style ship paint; SOL_SHIP_STYLE=off disables
	return holder


## True when the model file for this ship exists on disk.
static func has_model(def) -> bool:
	return FileAccess.file_exists(ProjectSettings.globalize_path(str(def.hull_path)))


static func _copy_of(res_path: String) -> Node3D:
	if res_path == "":
		return null
	if not _loaded.has(res_path):
		var scene: Node3D = null
		var disk_path := ProjectSettings.globalize_path(res_path)
		if FileAccess.file_exists(disk_path):
			var document := GLTFDocument.new()
			var state := GLTFState.new()
			if document.append_from_file(disk_path, state) == OK:
				scene = document.generate_scene(state) as Node3D
			if scene == null:
				push_warning("BigShipHull: could not read %s" % res_path)
		_loaded[res_path] = scene
	var original: Node3D = _loaded[res_path]
	if original == null:
		return null
	return original.duplicate() as Node3D


## A long box with a nose wedge and two engine blocks, so the ship can still be looked at without its model.
static func _add_stand_in(holder: Node3D, extent: float, colour: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour.darkened(0.35)
	material.metallic = 0.6
	material.roughness = 0.45
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(extent * 0.22, extent * 0.14, extent)
	box.material = material
	body.mesh = box
	holder.add_child(body)
	var nose := MeshInstance3D.new()
	var wedge := PrismMesh.new()
	wedge.size = Vector3(extent * 0.22, extent * 0.2, extent * 0.14)
	wedge.material = material
	nose.mesh = wedge
	nose.rotation.x = -PI / 2.0
	nose.position = Vector3(0.0, 0.0, -extent * 0.57)
	holder.add_child(nose)
	for side in [-1.0, 1.0]:
		var engine := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = extent * 0.05
		cylinder.bottom_radius = extent * 0.06
		cylinder.height = extent * 0.2
		cylinder.material = material
		engine.mesh = cylinder
		engine.rotation.x = PI / 2.0
		engine.position = Vector3(side * extent * 0.17, 0.0, extent * 0.46)
		holder.add_child(engine)


## Bounding box of every mesh under `node`, in the space of `node`'s parent, merged into found[0].
static func _collect_bounds(node: Node, parent_transform: Transform3D, found: Array) -> void:
	var node_transform := parent_transform
	if node is Node3D:
		node_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_box: AABB = node_transform * (node as MeshInstance3D).mesh.get_aabb()
		if found.is_empty():
			found.append(mesh_box)
		else:
			found[0] = (found[0] as AABB).merge(mesh_box)
	for child in node.get_children():
		_collect_bounds(child, node_transform, found)


## Puts every VisualInstance3D under `node` (itself included) on these render layers.
static func set_layers(node: Node, mask: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = mask
	for child in node.get_children():
		set_layers(child, mask)
