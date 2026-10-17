class_name ChunkMesher
extends RefCounted
## Builds the mesh arrays for one chunk. Pure and thread-safe (reads the planet only), so it
## can run on worker threads. Vertices are stored relative to the chunk's origin point so they
## stay small; the caller places the node at origin - render_origin.

const GRID := 32 # quads per edge; vertices per edge = GRID + 1


## Returns {origin: PackedFloat64Array(3), vertices, normals, colors, indices} for the key.
static func build(key: int, planet: PlanetBody) -> Dictionary:
	var face := ChunkKey.face_of(key)
	var level := ChunkKey.level_of(key)
	var span := 2.0 / float(1 << level)
	var face_u_start := -1.0 + ChunkKey.column_of(key) * span
	var face_v_start := -1.0 + ChunkKey.row_of(key) * span
	var step := span / GRID
	var edge_metres := (PI * 0.5 * planet.radius) / float(1 << level)

	var center_direction := CubeSphere.direction_xyz(face, face_u_start + span * 0.5, face_v_start + span * 0.5)
	var origin_x: float = center_direction[0] * planet.radius
	var origin_y: float = center_direction[1] * planet.radius
	var origin_z: float = center_direction[2] * planet.radius

	# Positions on a (GRID+3)^2 lattice: one extra ring so edge normals use real neighbours.
	var lattice := GRID + 3
	var lattice_positions := PackedVector3Array()
	lattice_positions.resize(lattice * lattice)
	var lattice_heights := PackedFloat32Array()
	lattice_heights.resize(lattice * lattice)
	for row in lattice:
		for column in lattice:
			var direction := CubeSphere.direction_xyz(face, face_u_start + (column - 1) * step, face_v_start + (row - 1) * step)
			var height := planet.terrain_height_xyz(direction[0], direction[1], direction[2])
			var distance := planet.radius + height
			lattice_positions[row * lattice + column] = Vector3(direction[0] * distance - origin_x, direction[1] * distance - origin_y, direction[2] * distance - origin_z)
			lattice_heights[row * lattice + column] = height

	var vertices_per_edge := GRID + 1
	var skirt_drop := maxf(2.0, edge_metres * 0.05)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for row in vertices_per_edge:
		for column in vertices_per_edge:
			var index := (row + 1) * lattice + (column + 1)
			var position := lattice_positions[index]
			var tangent_u := lattice_positions[index + 1] - lattice_positions[index - 1]
			var tangent_v := lattice_positions[index + lattice] - lattice_positions[index - lattice]
			var normal := tangent_u.cross(tangent_v).normalized() # cross(u,v) points outward on every face
			vertices.append(position)
			normals.append(normal)
			var outward := (position + Vector3(origin_x, origin_y, origin_z)).normalized()
			var base_color := _color_for(lattice_heights[index], 1.0 - normal.dot(outward))
			# Patchy variation from the absolute position so colours match across chunk borders.
			var patch := sin((position.x + origin_x) * 0.00031) * sin((position.z + origin_z) * 0.00043) + 0.5 * sin((position.y + origin_y) * 0.0021 + (position.x + origin_x) * 0.0017)
			colors.append(base_color * (0.9 + 0.1 * patch))

	var indices := PackedInt32Array()
	for row in GRID:
		for column in GRID:
			var corner_a := row * vertices_per_edge + column
			var corner_b := corner_a + 1
			var corner_c := corner_a + vertices_per_edge
			var corner_d := corner_c + 1
			# Godot treats clockwise as front-facing, so each triangle is listed clockwise seen from outside.
			indices.append_array([corner_a, corner_c, corner_b, corner_b, corner_c, corner_d])

	# Skirts: a copy of each border vertex pushed toward the planet centre, to hide cracks between LODs.
	var skirt_edges := [
		_border_indices(vertices_per_edge, 0), _border_indices(vertices_per_edge, 1),
		_border_indices(vertices_per_edge, 2), _border_indices(vertices_per_edge, 3)]
	for border in skirt_edges:
		var first_skirt_index := vertices.size()
		for border_vertex in border:
			var surface_position: Vector3 = vertices[border_vertex]
			var outward := (surface_position + Vector3(origin_x, origin_y, origin_z)).normalized()
			vertices.append(surface_position - outward * skirt_drop)
			normals.append(normals[border_vertex])
			colors.append(colors[border_vertex])
		for position_along_border in border.size() - 1:
			var top_a: int = border[position_along_border]
			var top_b: int = border[position_along_border + 1]
			var skirt_a: int = first_skirt_index + position_along_border
			var skirt_b: int = skirt_a + 1
			indices.append_array([top_a, skirt_a, top_b, top_b, skirt_a, skirt_b])

	return {"origin": PackedFloat64Array([origin_x, origin_y, origin_z]), "vertices": vertices, "normals": normals, "colors": colors, "indices": indices}


## Vertex indices along one border (0 = row 0, 1 = last row, 2 = column 0, 3 = last column).
static func _border_indices(vertices_per_edge: int, which: int) -> PackedInt32Array:
	var border := PackedInt32Array()
	for position_along_border in vertices_per_edge:
		match which:
			0: border.append(position_along_border)
			1: border.append((vertices_per_edge - 1) * vertices_per_edge + position_along_border)
			2: border.append(position_along_border * vertices_per_edge)
			_: border.append(position_along_border * vertices_per_edge + vertices_per_edge - 1)
	return border


static func _color_for(height: float, steepness: float) -> Color:
	var low := Color(0.28, 0.36, 0.2)
	var mid := Color(0.45, 0.4, 0.28)
	var high := Color(0.5, 0.5, 0.5)
	var snow := Color(0.95, 0.96, 1.0)
	var color: Color
	if height < 1500.0:
		color = low.lerp(mid, clampf((height + 500.0) / 2000.0, 0.0, 1.0))
	elif height < 4000.0:
		color = mid.lerp(high, (height - 1500.0) / 2500.0)
	else:
		color = high.lerp(snow, clampf((height - 4000.0) / 800.0, 0.0, 1.0))
	return color.lerp(Color(0.38, 0.36, 0.34), clampf(steepness * 6.0, 0.0, 0.8))
