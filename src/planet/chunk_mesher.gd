class_name ChunkMesher
extends RefCounted
## Builds the mesh arrays for one chunk. Pure and thread-safe (reads the planet only), so it
## can run on worker threads. Vertices are stored relative to the chunk's origin point so they
## stay small; the caller places the node at origin - render_origin.

const GRID := 32 # quads per edge; vertices per edge = GRID + 1
## Slope weight written into each vertex colour's alpha for the terrain detail shader: 0 = flat layer, 1 = steep (rock) layer.
## "Steepness" is 1 - cos(slope angle); the 0.5 point is at about 26 degrees. The plain material ignores alpha (it is opaque).
const STEEP_WEIGHT_FROM := 0.04
const STEEP_WEIGHT_TO := 0.16


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
			var steepness := 1.0 - normal.dot(outward)
			var base_color := planet.look.surface_color(planet.profile_or_default(), lattice_heights[index], steepness, absf(outward.y), position + Vector3(origin_x, origin_y, origin_z)) \
				if planet.look != null else _color_for(planet.profile_or_default(), lattice_heights[index], steepness, outward.y)
			# Patchy variation from the absolute position so colours match across chunk borders.
			var patch := sin((position.x + origin_x) * 0.00031) * sin((position.z + origin_z) * 0.00043) + 0.5 * sin((position.y + origin_y) * 0.0021 + (position.x + origin_x) * 0.0017)
			var shade := 0.9 + 0.1 * patch
			colors.append(Color(base_color.r * shade, base_color.g * shade, base_color.b * shade, steep_weight(1.0 - normal.dot(outward))))

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


static func steep_weight(steepness: float) -> float:
	return smoothstep(STEEP_WEIGHT_FROM, STEEP_WEIGHT_TO, steepness)


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


## Colour from height, slope and latitude: height bands low->mid->high, a snow line that drops toward the poles,
## polar caps, and bare rock on steep ground (the material "gates" of research PLN-10, as simple CPU rules).
static func _color_for(profile: TerrainProfile, height: float, steepness: float, latitude_sine: float) -> Color:
	var latitude := absf(latitude_sine)
	var color: Color
	if height < 1500.0:
		color = profile.palette_low.lerp(profile.palette_mid, clampf((height + 500.0) / 2000.0, 0.0, 1.0))
	else:
		color = profile.palette_mid.lerp(profile.palette_high, clampf((height - 1500.0) / 2500.0, 0.0, 1.0))
	var snow_line := profile.snow_height - latitude * 3500.0
	var snow_amount := clampf((height - snow_line) / 600.0, 0.0, 1.0)
	if profile.snow_height < 1.0e8: # worlds with snow_height set absurdly high have no snow or ice at all
		snow_amount = maxf(snow_amount, smoothstep(0.82, 0.95, latitude))
	color = color.lerp(profile.palette_snow, snow_amount * (1.0 - clampf(steepness * 8.0, 0.0, 0.7)))
	return color.lerp(profile.palette_rock, clampf(steepness * 6.0, 0.0, 0.8))
