extends "res://tests/test_case.gd"
## ADR 0012: the ship is bigger on the inside. Pocket rooms are wider than the hull and drawn only from inside; the hull
## is hidden while the camera is in a pocket room; the cockpit and airlock (the threshold) fit in the hull.


func _build_visuals() -> ShipVisuals:
	var ship := Ship.new()
	ship.systems = ShipSystems.new()
	var visuals := ShipVisuals.new()
	visuals.ship = ship
	visuals._ready()
	return visuals


func test_pocket_rooms_are_wider_than_the_hull_and_the_threshold_fits_inside_it() -> void:
	var layout := InteriorLayout.player_ship()
	var widest := 0.0
	for room_id in layout.rooms:
		var room: Rect2 = layout.rooms[room_id]
		var half_width := maxf(-room.position.x, room.end.x)
		if layout.is_pocket(room_id):
			widest = maxf(widest, half_width)
		else:
			assert_true(half_width < ShipHullCollision.HULL_HALF_WIDTH, "%s fits in the hull (half width %.2f)" % [room_id, half_width])
	assert_true(widest > ShipHullCollision.HULL_HALF_WIDTH + 1.0, "the inside is wider than the outside (%.2f vs %.2f)" % [widest, ShipHullCollision.HULL_HALF_WIDTH])
	assert_true(not layout.is_pocket(&"airlock") and not layout.is_pocket(&"cockpit"))


func test_every_station_stands_on_walkable_floor_in_its_room() -> void:
	var layout := InteriorLayout.player_ship()
	for point in layout.interact_points:
		var spot := layout.standing_spot_for(point["id"])
		assert_true(spot != Vector2.INF, "%s can be reached" % point["id"])


func test_hull_and_pocket_follow_the_camera() -> void:
	var visuals := _build_visuals()
	assert_true(visuals.pocket.get_child_count() > 20, "the pocket rooms' floors, walls and lights live in the pocket")
	var outside := visuals.cull_mask_for(false, &"")
	assert_true(outside & ShipVisuals.LAYER_POCKET == 0 and outside & ShipVisuals.LAYER_HULL != 0, "outside: hull drawn, pocket left out")
	for room_id in [&"airlock", &"cockpit"]:
		var mask := visuals.cull_mask_for(true, room_id)
		assert_true(mask & ShipVisuals.LAYER_POCKET != 0 and mask & ShipVisuals.LAYER_ENDS != 0, "in the %s: the pocket and the hull's nose and tail" % room_id)
		assert_true(mask & ShipVisuals.LAYER_HULL == 0, "in the %s: not the middle of the hull, which would cut through the rooms seen through its doors" % room_id)
	var cabin := visuals.cull_mask_for(true, &"cabin")
	assert_true(cabin & ShipVisuals.LAYER_POCKET != 0 and cabin & ShipVisuals.LAYER_HULL == 0, "in a pocket room: no hull to cut through it")
	assert_true(cabin & ShipVisuals.LAYER_ENDS == 0, "walking in a pocket room: no hull at all, nose and tail included")
	assert_true(outside & ShipVisuals.LAYER_ENDS != 0, "outside: the nose and tail too")
	assert_true(cabin & 1 != 0, "the world (layer 1) is always drawn")
	visuals.free()


## ADR 0013: the ship is never hidden node by node. Every piece stays visible in the tree; the layers decide what a camera draws.
func test_nothing_in_the_ship_is_ever_hidden_by_visibility() -> void:
	var visuals := _build_visuals()
	var hull_before := visuals._hull_nodes.map(func(node): return node.visible) # a few hull parts (ramp lamp) switch themselves
	for place in [[false, &""], [true, &"cabin"], [true, &"cockpit"], [true, &"engineering"]]:
		visuals.set_camera_place(place[0], place[1])
		visuals._process(0.016)
		assert_true(visuals.pocket.visible, "pocket node visible at %s" % [place])
		assert_eq(visuals._hull_nodes.map(func(node): return node.visible), hull_before, "no hull node hidden at %s" % [place])
		for room_id in visuals._shell_nodes:
			for node in visuals._shell_nodes[room_id]:
				assert_true(node.visible, "%s shell visible at %s" % [room_id, place])
	for wall in visuals.pocket.find_children("*", "MeshInstance3D", true, false):
		assert_eq((wall as MeshInstance3D).layers, ShipVisuals.LAYER_POCKET, "%s is on the pocket layer" % wall.name)
	for lamp in visuals.pocket.find_children("*", "Light3D", true, false):
		assert_eq((lamp as Light3D).layers, ShipVisuals.LAYER_POCKET, "pocket lamps are culled with the pocket")
		assert_true((lamp as Light3D).light_cull_mask & ShipVisuals.LAYER_HULL == 0, "a lamp inside does not light the hull")
	for node in visuals._hull_nodes:
		for mesh in node.find_children("*", "VisualInstance3D", true, false) + ([node] if node is VisualInstance3D else []):
			assert_eq((mesh as VisualInstance3D).layers, ShipVisuals.LAYER_HULL)
	visuals.free()


func test_nothing_from_a_pocket_room_is_left_outside_the_pocket() -> void:
	# Anything wider than the hull must be in the pocket, or it pokes through the hull from outside.
	var visuals := _build_visuals()
	for child in visuals.get_children():
		if child is MeshInstance3D and child != null and not (child in visuals._hull_nodes):
			var box := (child as MeshInstance3D).get_aabb()
			var node := child as MeshInstance3D
			var reach := maxf(absf(node.position.x + box.position.x), absf(node.position.x + box.end.x))
			assert_true(reach <= ShipHullCollision.HULL_HALF_WIDTH + 0.05, "%s reaches x=%.2f outside the pocket" % [node.name, reach])
	visuals.free()


func test_crew_in_pocket_rooms_are_hidden_from_outside() -> void:
	var systems := ShipSystems.new()
	var crew := ShipCrew.new()
	crew.add_member(systems, &"mara", &"engineer", &"reactor_panel")
	var view := CrewView.new()
	view.crew = crew
	view.layout = systems.layout
	view.pocket_visible = false
	view._process(0.016)
	var avatar: Node3D = view.get_child(0)
	assert_true(not avatar.visible, "an engineer in engineering is not drawn from outside")
	view.pocket_visible = true
	view._process(0.016)
	assert_true(avatar.visible)
	view.free()


## Two walls drawn on the same plane z-fight (flicker), so no two wall-material boxes of the interior may overlap.
func test_no_two_interior_walls_overlap() -> void:
	var visuals := _build_visuals()
	var boxes: Array = []
	for parent in [visuals, visuals.pocket]:
		for child in parent.get_children():
			var instance := child as MeshInstance3D
			if instance == null or instance in visuals._hull_nodes or not instance.mesh is BoxMesh:
				continue
			if instance.material_override != visuals._wall_material:
				continue
			var size := (instance.mesh as BoxMesh).size
			boxes.append(AABB(instance.position - size * 0.5, size))
	assert_true(boxes.size() > 20, "the interior has wall boxes")
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			var overlap: AABB = (boxes[i] as AABB).intersection(boxes[j])
			assert_true(overlap.get_volume() < 0.0005, "wall boxes %s and %s overlap by %.4f m3" % [boxes[i], boxes[j], overlap.get_volume()])
	visuals.free()


func test_threshold_shell_is_hidden_from_pocket_rooms_unless_a_door_is_open() -> void:
	var visuals := _build_visuals()
	var layout := visuals.ship.systems.layout
	assert_true(visuals._shell_nodes.has(&"cockpit") and visuals._shell_nodes.has(&"airlock"), "cockpit and airlock have an outward shell")
	var cockpit_layer: int = ShipVisuals.SHELL_LAYERS[&"cockpit"]
	var airlock_layer: int = ShipVisuals.SHELL_LAYERS[&"airlock"]
	assert_eq((visuals._shell_nodes[&"cockpit"][0] as VisualInstance3D).layers, cockpit_layer)
	assert_true(visuals.cull_mask_for(true, &"cabin") & cockpit_layer == 0, "shell left out from the cabin")
	(layout.portals[&"cockpit_door"] as Portal).open_factor = 1.0
	assert_true(visuals.cull_mask_for(true, &"cabin") & cockpit_layer != 0, "an open cockpit door shows the cockpit")
	assert_true(visuals.cull_mask_for(true, &"cabin") & airlock_layer == 0, "but not the airlock's shell")
	assert_true(visuals.cull_mask_for(false, &"") & airlock_layer != 0, "from outside the shell is drawn")
	visuals.free()


## Standing in a doorway (between rooms) must not draw the hull: it used to, and the outside of the ship showed through the walls.
func test_a_camera_in_a_doorway_next_to_a_pocket_room_does_not_draw_the_hull() -> void:
	var visuals := _build_visuals()
	var layout := visuals.ship.systems.layout
	var checked := 0
	for portal_id in layout.portals:
		var portal: Portal = layout.portals[portal_id]
		var centre := portal.opening.get_center()
		var neighbours_pocket := false
		for room_id in layout.rooms:
			if (layout.rooms[room_id] as Rect2).grow(0.35).has_point(centre) and layout.is_pocket(room_id):
				neighbours_pocket = true
		if not neighbours_pocket:
			continue
		var room_id := layout.room_for_view(centre.x, centre.y)
		assert_true(layout.is_pocket(room_id), "%s: the doorway counts as a pocket room, not %s" % [portal_id, room_id])
		assert_true(visuals.cull_mask_for(true, room_id) & ShipVisuals.LAYER_HULL == 0, "%s: no hull from the doorway" % portal_id)
		checked += 1
	assert_true(checked >= 8, "most doors are checked (%d)" % checked)
	visuals.free()


## The hull's nose and tail ends are drawn from inside every room, so none of their geometry may lie inside a room (or its wall
## skin): that is what the cut at the cockpit's rear and inside the airlock guarantees.
func test_the_hull_ends_drawn_from_inside_never_overlap_a_room() -> void:
	var visuals := _build_visuals()
	var layout := visuals.ship.systems.layout
	assert_true(visuals._end_nodes.size() >= 3, "nose, tail and ramp pieces exist (%d)" % visuals._end_nodes.size())
	# The cut loses no triangle: the pieces together hold exactly what the hull builder made.
	var builder_total := 0
	for piece in visuals.get_children():
		if piece is MeshInstance3D and String(piece.name).begins_with("HullStatic"):
			assert_true((piece as MeshInstance3D).mesh.get_surface_count() > 0, "%s is not empty" % piece.name)
			for surface in (piece as MeshInstance3D).mesh.get_surface_count():
				builder_total += ((piece as MeshInstance3D).mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var whole := ShipExterior.new()
	var probe := Node3D.new()
	whole.build(probe, layout, Vector3(0, 0, 0), StandardMaterial3D.new(), func(_a, _b): return null)
	var expected := 0
	for surface in (probe.get_node("HullStatic") as MeshInstance3D).mesh.get_surface_count():
		expected += (((probe.get_node("HullStatic") as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	assert_eq(builder_total, expected, "the split keeps every vertex of the hull")
	probe.free()
	for end_node in visuals._end_nodes:
		for mesh_node in [end_node] + end_node.find_children("*", "MeshInstance3D", true, false):
			if not (mesh_node is MeshInstance3D) or (mesh_node as MeshInstance3D).mesh == null:
				continue
			var transform := Transform3D.IDENTITY
			var current: Node = mesh_node
			while current != null and current != visuals:
				if current is Node3D:
					transform = (current as Node3D).transform * transform
				current = current.get_parent()
			var box := transform * (mesh_node as MeshInstance3D).get_aabb()
			var footprint := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
			for room_id in layout.rooms:
				if layout.is_pocket(room_id):
					assert_true(not footprint.intersects((layout.rooms[room_id] as Rect2).grow(0.2)), "%s (%s) stays out of the %s" % [end_node.name, mesh_node.name, room_id])
	visuals.free()
