class_name HullMeshBuilder
extends RefCounted
## Collects flat-shaded (hard-surface) triangles per material slot and commits them as one ArrayMesh with one
## surface per slot used, so a whole group of parts costs one draw call per material. Parts are lofts through
## profile rings, chamfered boxes, faceted cylinders and planar caps (optionally with rectangular openings).
## Every add_* takes a Transform3D so parts are authored in their own frame. The materials on the ship are
## triplanar, so no UVs are written.

# slot -> Array of Vector3. Plain Arrays, not Packed ones: a PackedVector3Array taken out of a Dictionary is a copy,
# so appending to it would be lost.
var _vertices := {}
var _normals := {}


## Mirrors a half profile (x >= 0, from the top centre down to the bottom centre) into a closed ring. The
## returned ring runs p0..pn then back up the -x side; `half_slots[i]` (strip between p_i and p_i+1) is mirrored.
static func mirror_ring(half: PackedVector3Array) -> PackedVector3Array:
	var ring := half.duplicate()
	for index in range(half.size() - 2, 0, -1):
		ring.append(Vector3(-half[index].x, half[index].y, half[index].z))
	return ring


static func mirror_slots(half_slots: PackedInt32Array) -> PackedInt32Array:
	var slots := half_slots.duplicate()
	for index in range(half_slots.size() - 1, -1, -1):
		slots.append(half_slots[index])
	return slots


## A regular polygon ring around the z axis (radius to the corners), first corner at `start_angle` from +y.
static func polygon_ring(sides: int, radius: float, z: float, start_angle: float = 0.0) -> PackedVector3Array:
	var ring := PackedVector3Array()
	for index in sides:
		var angle := start_angle + TAU * index / sides
		ring.append(Vector3(sin(angle) * radius, cos(angle) * radius, z))
	return ring


## Lofts closed rings (all the same point count). `slots[i]` is the material of the strip between point i and
## i+1 (it wraps). Faces point away from the loft axis, or toward it when `inward` (an intake throat).
## Caps (fan from the ring centre) are added when their slot is >= 0.
func add_loft(rings: Array, slots: PackedInt32Array, xform := Transform3D.IDENTITY, inward := false, first_cap_slot := -1, last_cap_slot := -1) -> void:
	var count: int = (rings[0] as PackedVector3Array).size()
	for ring_index in rings.size() - 1:
		var ring_a: PackedVector3Array = rings[ring_index]
		var ring_b: PackedVector3Array = rings[ring_index + 1]
		var axis_point := (_centroid(ring_a) + _centroid(ring_b)) * 0.5
		for index in count:
			var next := (index + 1) % count
			var slot := slots[index % slots.size()]
			_add_quad_facing(slot, ring_a[index], ring_a[next], ring_b[next], ring_b[index], axis_point, inward, xform)
	if first_cap_slot >= 0:
		add_cap(rings[0], first_cap_slot, _centroid(rings[0]) - _centroid(rings[1]), xform)
	if last_cap_slot >= 0:
		var last: int = rings.size() - 1
		add_cap(rings[last], last_cap_slot, _centroid(rings[last]) - _centroid(rings[last - 1]), xform)


## A planar convex cap facing `facing` (fan from the centroid).
func add_cap(ring: PackedVector3Array, slot: int, facing: Vector3, xform := Transform3D.IDENTITY) -> void:
	var centre := _centroid(ring)
	for index in ring.size():
		_add_triangle_facing(slot, centre, ring[index], ring[(index + 1) % ring.size()], facing, xform)


## A planar cap at depth `z` (facing +z or -z) over a convex polygon in (x, y), minus one rectangular opening.
## The opening is cut by splitting the polygon into the bands above, below, left and right of it.
func add_cap_with_opening(outline: PackedVector2Array, opening: Rect2, z: float, facing_z: float, slot: int, xform := Transform3D.IDENTITY) -> void:
	var big := 1000.0
	var bands := [
		Rect2(-big, opening.end.y, 2.0 * big, big),
		Rect2(-big, -big, 2.0 * big, big + opening.position.y),
		Rect2(-big, opening.position.y, big + opening.position.x, opening.size.y),
		Rect2(opening.end.x, opening.position.y, big, opening.size.y)]
	for band in bands:
		var band_polygon := PackedVector2Array([band.position, Vector2(band.end.x, band.position.y), band.end, Vector2(band.position.x, band.end.y)])
		for piece in Geometry2D.intersect_polygons(outline, band_polygon):
			var ring := PackedVector3Array()
			for point in piece:
				ring.append(Vector3(point.x, point.y, z))
			if ring.size() >= 3:
				add_cap(ring, slot, Vector3(0, 0, facing_z), xform)


## A box with every edge chamfered by `chamfer`, centred on the origin of `xform`. `side_slot` (default `slot`)
## is used for the four long faces around z, `slot` for the end faces and their chamfers.
func add_chamfer_box(size: Vector3, chamfer: float, slot: int, xform := Transform3D.IDENTITY, side_slot := -1) -> void:
	var half := size * 0.5
	var c := minf(chamfer, minf(half.x, minf(half.y, half.z)) * 0.95)
	var full := _octagon(half.x, half.y, c)
	var inner := _octagon(half.x - c, half.y - c, minf(c, minf(half.x - c, half.y - c) * 0.95))
	var rings := [_at_z(inner, -half.z), _at_z(full, -half.z + c), _at_z(full, half.z - c), _at_z(inner, half.z)]
	var around := side_slot if side_slot >= 0 else slot
	# Octagon strips: top, top-right chamfer, right, bottom-right, bottom, bottom-left, left, top-left.
	var strip_slots := PackedInt32Array([around, slot, around, slot, around, slot, around, slot])
	var end_slots := PackedInt32Array([slot, slot, slot, slot, slot, slot, slot, slot])
	add_loft([rings[0], rings[1]], end_slots, xform)
	add_loft([rings[1], rings[2]], strip_slots, xform)
	add_loft([rings[2], rings[3]], end_slots, xform, false, -1, slot)
	add_cap(rings[0], slot, Vector3(0, 0, -1), xform)


## A faceted cylinder along local z from z0 to z1 (flats at top and bottom), capped at both ends.
func add_cylinder(sides: int, radius_0: float, radius_1: float, z0: float, z1: float, slot: int, xform := Transform3D.IDENTITY, cap_slot := -2) -> void:
	var start := PI / sides
	var rings := [polygon_ring(sides, radius_0, z0, start), polygon_ring(sides, radius_1, z1, start)]
	var caps := slot if cap_slot == -2 else cap_slot
	add_loft(rings, PackedInt32Array([slot]), xform, false, caps, caps)


## A straight bar of square section (side `thickness`) from `from` to `to` (in the xform's frame).
func add_bar(from: Vector3, to: Vector3, thickness: float, slot: int, xform := Transform3D.IDENTITY, chamfer := 0.0) -> void:
	var length := from.distance_to(to)
	if length < 0.001:
		return
	var direction := (to - from) / length
	var up := Vector3.UP if absf(direction.y) < 0.95 else Vector3.RIGHT
	var basis := Basis.looking_at(direction, up)
	add_chamfer_box(Vector3(thickness, thickness, length), chamfer if chamfer > 0.0 else thickness * 0.2, slot, xform * Transform3D(basis, (from + to) * 0.5))


func is_empty() -> bool:
	return _vertices.is_empty()


## The finished mesh and, for each surface index, the slot it was built from.
func commit() -> Dictionary:
	var mesh := ArrayMesh.new()
	var slot_of_surface := PackedInt32Array()
	var slots := _vertices.keys()
	slots.sort()
	for slot in slots:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(_vertices[slot])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(_normals[slot])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		slot_of_surface.append(slot)
	return {"mesh": mesh, "slots": slot_of_surface}


## A loft quad is often slightly twisted (its corners are not coplanar), so both triangles get the quad's own normal
## (from its diagonals): with per-triangle normals the twist shows as a diagonal crease across the panel.
func _add_quad_facing(slot: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, axis_point: Vector3, inward: bool, xform: Transform3D) -> void:
	var outward := (a + b + c + d) * 0.25 - axis_point
	if inward:
		outward = -outward
	var quad_normal := (c - a).cross(d - b)
	if quad_normal.length_squared() < 1e-12:
		quad_normal = Vector3.ZERO
	elif quad_normal.dot(outward) < 0.0:
		quad_normal = -quad_normal
	_add_triangle_facing(slot, a, b, c, outward, xform, quad_normal)
	_add_triangle_facing(slot, a, c, d, outward, xform, quad_normal)


## Adds one triangle wound so its front face (Godot: clockwise as seen from the front) looks along `facing`.
## Degenerate triangles (collapsed chamfer corners) are dropped.
func _add_triangle_facing(slot: int, a: Vector3, b: Vector3, c: Vector3, facing: Vector3, xform: Transform3D, shading_normal := Vector3.ZERO) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 1e-12:
		return
	normal = normal.normalized()
	var first := b
	var second := c
	if normal.dot(facing) > 0.0:
		normal = -normal
		first = c
		second = b
	# With (a, first, second) the right-hand normal now points backward, so the triangle is clockwise from the front.
	var front := -normal
	if not _vertices.has(slot):
		_vertices[slot] = []
		_normals[slot] = []
	var vertices: Array = _vertices[slot]
	var normals: Array = _normals[slot]
	var world_normal := (xform.basis * (shading_normal.normalized() if shading_normal != Vector3.ZERO else front)).normalized()
	for point in [a, first, second]:
		vertices.append(xform * point)
		normals.append(world_normal)


static func _octagon(half_x: float, half_y: float, chamfer: float) -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(-half_x + chamfer, half_y, 0), Vector3(half_x - chamfer, half_y, 0), Vector3(half_x, half_y - chamfer, 0), Vector3(half_x, -half_y + chamfer, 0),
		Vector3(half_x - chamfer, -half_y, 0), Vector3(-half_x + chamfer, -half_y, 0), Vector3(-half_x, -half_y + chamfer, 0), Vector3(-half_x, half_y - chamfer, 0)])


static func _at_z(ring: PackedVector3Array, z: float) -> PackedVector3Array:
	var moved := PackedVector3Array()
	for point in ring:
		moved.append(Vector3(point.x, point.y, z))
	return moved


static func _centroid(ring: PackedVector3Array) -> Vector3:
	var total := Vector3.ZERO
	for point in ring:
		total += point
	return total / ring.size()
