extends RefCounted
## Reads a Wavefront .obj (with its .mtl's flat diffuse colours) straight from disk into an ArrayMesh, one surface per material. Used for
## models that are git-ignored and may not have been through Godot's importer yet (the pilot seat). Triangles and fans of larger faces.

static var _cache := {}


## `skip_groups`: faces in a group whose name starts with one of these are left out (e.g. the seat's armrests and controls).
static func load_mesh(path: String, skip_groups: PackedStringArray = PackedStringArray()) -> ArrayMesh:
	var key := path + "|" + ",".join(skip_groups)
	if _cache.has(key):
		return _cache[key]
	if not FileAccess.file_exists(path):
		return null
	var materials := _read_materials(path.get_basename() + ".mtl")
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var surfaces := {} # material name -> {"v": PackedVector3Array, "n": PackedVector3Array}
	var order: Array[String] = []
	var current := ""
	var skipping := false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	while not file.eof_reached():
		var line := file.get_line()
		if line.length() < 2:
			continue
		if line.begins_with("v "):
			var parts := line.substr(2).strip_edges().split(" ", false)
			positions.append(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
		elif line.begins_with("vn "):
			var parts := line.substr(3).strip_edges().split(" ", false)
			normals.append(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
		elif line.begins_with("g "):
			var group_name := line.substr(2).strip_edges()
			skipping = false
			for prefix in skip_groups:
				if group_name.begins_with(prefix):
					skipping = true
		elif line.begins_with("usemtl "):
			current = line.substr(7).strip_edges()
			if not surfaces.has(current):
				surfaces[current] = {"v": PackedVector3Array(), "n": PackedVector3Array()}
				order.append(current)
		elif line.begins_with("f ") and not skipping:
			if not surfaces.has(current):
				surfaces[current] = {"v": PackedVector3Array(), "n": PackedVector3Array()}
				order.append(current)
			var corners := line.substr(2).strip_edges().split(" ", false)
			var surface: Dictionary = surfaces[current]
			for corner_index in range(1, corners.size() - 1):
				for index in [0, corner_index + 1, corner_index]: # Godot's front faces wind clockwise, a .obj's counter-clockwise: reversed
					var fields: PackedStringArray = corners[index].split("/")
					var position_index := int(fields[0]) - 1
					(surface["v"] as PackedVector3Array).append(positions[position_index])
					var normal := Vector3.UP
					if fields.size() >= 3 and fields[2] != "":
						normal = normals[int(fields[2]) - 1]
					(surface["n"] as PackedVector3Array).append(normal)
	var mesh := ArrayMesh.new()
	for material_name in order:
		var surface: Dictionary = surfaces[material_name]
		if (surface["v"] as PackedVector3Array).is_empty():
			continue # every face of this material was in a skipped group
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surface["v"]
		arrays[Mesh.ARRAY_NORMAL] = surface["n"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.resource_name = material_name
		material.albedo_color = materials.get(material_name, Color(0.6, 0.6, 0.6))
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	_cache[key] = mesh
	return mesh


static func _read_materials(path: String) -> Dictionary:
	var colors := {}
	if not FileAccess.file_exists(path):
		return colors
	var file := FileAccess.open(path, FileAccess.READ)
	var name := ""
	while file != null and not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with("newmtl "):
			name = line.substr(7).strip_edges()
		elif line.to_lower().begins_with("kd ") and name != "":
			var parts := line.substr(3).strip_edges().split(" ", false)
			colors[name] = Color(float(parts[0]), float(parts[1]), float(parts[2]))
	return colors
