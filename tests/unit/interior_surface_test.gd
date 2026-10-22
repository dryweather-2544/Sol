extends "res://tests/test_case.gd"
## Interior surface hygiene: no two box meshes with different materials may share a same-facing plane over an area
## (that is z-fighting: the flicker/"wall glitch" seen in the ship), and decals must stay on their own surfaces.

const PLANE_TOLERANCE := 0.003
const MIN_OVERLAP_AREA := 0.005
const FLOOR_Y := -0.9
const CEILING_Y := 1.5


func _build_visuals() -> ShipVisuals:
	var ship := Ship.new()
	ship.systems = ShipSystems.new()
	var visuals := ShipVisuals.new()
	visuals.ship = ship
	visuals._ready()
	return visuals


static func _local_transform(node: Node3D, root: Node3D) -> Transform3D:
	var transform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			transform = (current as Node3D).transform * transform
		current = current.get_parent()
	return transform


## Every box in the ship as {node, aabb (ship space), layers, material}. Only axis-aligned boxes (the walls, trims, slabs).
static func collect_boxes(root: Node3D) -> Array:
	var boxes: Array = []
	var pending: Array = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if not (node is MeshInstance3D) or not ((node as MeshInstance3D).mesh is BoxMesh) or not (node as MeshInstance3D).visible:
			continue # (invisible: the fire boxes, drawn only while a room burns)
		var instance := node as MeshInstance3D
		var transform := _local_transform(instance, root)
		var axis_aligned := true
		for axis in [transform.basis.x, transform.basis.y, transform.basis.z]:
			var longest := maxf(absf(axis.x), maxf(absf(axis.y), absf(axis.z)))
			if longest < 0.999 * axis.length():
				axis_aligned = false
		if not axis_aligned:
			continue
		var box := transform * instance.get_aabb()
		boxes.append({"node": instance, "aabb": box, "layers": instance.layers, "material": instance.material_override if instance.material_override != null else instance.get_surface_override_material(0)})
	return boxes


## Same-facing coplanar overlaps between boxes that can be drawn by one camera and have different materials.
static func find_coplanar_overlaps(boxes: Array) -> Array:
	var found: Array = []
	for first_index in boxes.size():
		var first: Dictionary = boxes[first_index]
		for second_index in range(first_index + 1, boxes.size()):
			var second: Dictionary = boxes[second_index]
			if (int(first["layers"]) & int(second["layers"])) == 0 or first["material"] == second["material"]:
				continue
			var a: AABB = first["aabb"]
			var b: AABB = second["aabb"]
			if not a.grow(PLANE_TOLERANCE).intersects(b.grow(PLANE_TOLERANCE)):
				continue
			for axis in 3:
				var u := (axis + 1) % 3
				var v := (axis + 2) % 3
				var overlap_u := minf(a.end[u], b.end[u]) - maxf(a.position[u], b.position[u])
				var overlap_v := minf(a.end[v], b.end[v]) - maxf(a.position[v], b.position[v])
				if overlap_u * overlap_v < MIN_OVERLAP_AREA or overlap_u <= 0.0 or overlap_v <= 0.0:
					continue
				var same_max := absf(a.end[axis] - b.end[axis]) <= PLANE_TOLERANCE
				var same_min := absf(a.position[axis] - b.position[axis]) <= PLANE_TOLERANCE
				# both faces point the same way and sit on one plane: they fight for the pixel
				# the faces under the floor and above the ceiling are inside the slabs: never seen
				if axis == 1 and ((same_min and absf(a.position.y - FLOOR_Y) < 0.01) or (same_max and absf(a.end.y - CEILING_Y) < 0.01)):
					continue
				if (same_max or same_min) and not _face_is_buried(boxes, a if same_max or not same_min else a, axis, same_max, a, b, u, v):
					found.append({"first": first["node"], "second": second["node"], "axis": axis, "at": a.end[axis] if same_max else a.position[axis], "area": overlap_u * overlap_v, "sides": "max" if same_max else "min", "centre": a.get_center()})
					break
	return found


## A shared face whose outward side is inside another box (the back of a console against a wall, a panel's rear in the wall)
## is never drawn, so it cannot flicker.
static func _face_is_buried(boxes: Array, _unused: AABB, axis: int, facing_max: bool, a: AABB, b: AABB, u: int, v: int) -> bool:
	var point := Vector3.ZERO
	point[axis] = (a.end[axis] + 0.02) if facing_max else (a.position[axis] - 0.02)
	point[u] = (maxf(a.position[u], b.position[u]) + minf(a.end[u], b.end[u])) * 0.5
	point[v] = (maxf(a.position[v], b.position[v]) + minf(a.end[v], b.end[v])) * 0.5
	for other: Dictionary in boxes:
		if (other["aabb"] as AABB).has_point(point):
			return true
	return false


func test_no_visible_coplanar_surfaces_in_the_ship() -> void:
	var visuals := _build_visuals()
	var found := find_coplanar_overlaps(collect_boxes(visuals))
	var lines: Array = []
	for item in found:
		lines.append("%s | %s (axis %d at %.3f, centre %s)" % [item["first"].name, item["second"].name, item["axis"], item["at"], item["centre"]])
	assert_eq(found.size(), 0, "visible coplanar overlaps:\n" + "\n".join(lines))
	visuals.free()
