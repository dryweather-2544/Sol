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
	visuals.set_camera_place(false, &"")
	assert_true(not visuals.pocket.visible and visuals.is_hull_visible(), "outside: hull drawn, pocket hidden")
	visuals.set_camera_place(true, &"airlock")
	assert_true(visuals.pocket.visible and visuals.is_hull_visible(), "in the airlock: both")
	visuals.set_camera_place(true, &"cockpit")
	assert_true(visuals.pocket.visible and visuals.is_hull_visible(), "in the cockpit: both")
	visuals.set_camera_place(true, &"cabin")
	assert_true(visuals.pocket.visible and not visuals.is_hull_visible(), "in a pocket room: no hull to cut through it")
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
	visuals.set_camera_place(true, &"cabin")
	visuals._update_shell_visibility(layout)
	assert_true(not (visuals._shell_nodes[&"cockpit"][0] as Node3D).visible, "shell hidden from the cabin")
	(layout.portals[&"cockpit_door"] as Portal).open_factor = 1.0
	visuals._update_shell_visibility(layout)
	assert_true((visuals._shell_nodes[&"cockpit"][0] as Node3D).visible, "an open cockpit door shows the cockpit")
	visuals.set_camera_place(false, &"")
	visuals._update_shell_visibility(layout)
	assert_true((visuals._shell_nodes[&"airlock"][0] as Node3D).visible, "from outside the shell is drawn")
	visuals.free()
