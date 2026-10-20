extends "res://tests/test_case.gd"
## Prototype: the Cargo Spaceship hull is the ship's outside (render layer 3, outside cameras only) while the blockout stays the ship
## inside (layer 2, inside cameras only), apart from the ramp and outer door which every camera sees.
## The ship is added to the tree so Ship._ready builds its visuals and hull; the hull asset must be imported (tools/run_tests.sh does that).


func _player_ship() -> Ship:
	var ship := Ship.new()
	ship.systems = ShipSystems.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(ship)
	return ship


func _discard(ship: Ship) -> void:
	(Engine.get_main_loop() as SceneTree).root.remove_child(ship)
	ship.free()


func _visuals_of(ship: Ship) -> ShipVisuals:
	for child in ship.get_children():
		if child is ShipVisuals:
			return child as ShipVisuals
	return null


func test_hull_is_active_and_sized_to_the_hull_box() -> void:
	var settings := GameSettings.instance()
	var original := settings.exterior_hull
	settings.exterior_hull = true
	var ship := _player_ship()
	assert_true(ship.exterior_hull != null and ship.exterior_hull.active, "the hull loads on the player ship")
	if ship.exterior_hull != null and ship.exterior_hull.active:
		var bounds := ship.exterior_hull.bounds_in_ship
		assert_near(bounds.position.z, ShipHullCollision.HULL_FRONT_Z, 0.05, "nose at the hull box front")
		assert_near(bounds.end.z, ShipHullCollision.HULL_REAR_Z, 0.05, "tail at the hull box rear")
		assert_near(bounds.position.y, ExteriorHull.BOTTOM_Y, 0.05, "lowest point at the gear contact height")
		assert_near(bounds.get_center().x, 0.0, 0.05, "centred on the ship axis")
	_discard(ship)
	settings.exterior_hull = original


func test_layers_split_outside_hull_from_inside_blockout() -> void:
	var settings := GameSettings.instance()
	var original := settings.exterior_hull
	settings.exterior_hull = true
	var ship := _player_ship()
	var hull_instances := ship.exterior_hull.find_children("*", "GeometryInstance3D", true, false)
	assert_true(hull_instances.size() > 0, "the hull has meshes")
	var hull_on_wrong_layer := 0
	for instance in hull_instances:
		if (instance as GeometryInstance3D).layers != ExteriorHull.layer_bit(ExteriorHull.HULL_LAYER):
			hull_on_wrong_layer += 1
	assert_eq(hull_on_wrong_layer, 0, "every hull mesh is on the hull layer only")
	var visuals := _visuals_of(ship)
	var blockout_inside := 0
	var shared := 0
	var misplaced := 0
	for node in visuals.find_children("*", "GeometryInstance3D", true, false):
		var instance := node as GeometryInstance3D
		if instance.has_meta(ExteriorHull.SHARED_META):
			shared += 1
			if instance.layers & 1 == 0:
				misplaced += 1
		elif instance.layers == ExteriorHull.layer_bit(ExteriorHull.INTERIOR_LAYER):
			blockout_inside += 1
		else:
			misplaced += 1
	assert_true(blockout_inside > 20, "the blockout's own pieces are on the inside layer (%d)" % blockout_inside)
	assert_eq(shared, 2, "only the ramp and the outer door stay visible to every camera")
	assert_eq(misplaced, 0, "no blockout piece is on a layer it should not be on")
	_discard(ship)
	settings.exterior_hull = original


func test_camera_masks_hide_the_right_layer() -> void:
	var outside := Camera3D.new()
	var inside := Camera3D.new()
	ExteriorHull.apply_camera_masks([outside], [inside])
	assert_true(outside.cull_mask & ExteriorHull.layer_bit(ExteriorHull.HULL_LAYER) != 0, "outside camera sees the hull")
	assert_true(outside.cull_mask & ExteriorHull.layer_bit(ExteriorHull.INTERIOR_LAYER) == 0, "outside camera does not see the blockout")
	assert_true(outside.cull_mask & 1 != 0, "outside camera still sees layer 1 (terrain, ramp, gear)")
	assert_true(inside.cull_mask & ExteriorHull.layer_bit(ExteriorHull.INTERIOR_LAYER) != 0, "inside camera sees the blockout")
	assert_true(inside.cull_mask & ExteriorHull.layer_bit(ExteriorHull.HULL_LAYER) == 0, "inside camera does not see the hull")
	outside.free()
	inside.free()


func test_switch_off_keeps_the_blockout_visible_to_everyone() -> void:
	var settings := GameSettings.instance()
	var original := settings.exterior_hull
	settings.exterior_hull = false
	var ship := _player_ship()
	assert_true(not ship.exterior_hull.active, "no hull with the switch off")
	var hidden := 0
	for node in _visuals_of(ship).find_children("*", "GeometryInstance3D", true, false):
		if (node as GeometryInstance3D).layers & 1 == 0:
			hidden += 1
	assert_eq(hidden, 0, "the blockout stays on layer 1")
	_discard(ship)
	settings.exterior_hull = original


func test_silhouette_from_points_ignores_thin_outliers_and_widens_by_a_slice() -> void:
	var points := PackedVector3Array()
	for index in 100: # a 2 m wide fuselage in slice 2 (z 1.0 to 1.5) ...
		points.append(Vector3(1.0 if index % 2 == 0 else -1.0, 0.0, 1.2))
	points.append(Vector3(6.0, 0.0, 1.2)) # ... plus one antenna tip that must not widen it
	var silhouette := HullSilhouette.from_points(points, 0.0, 3.0, -1.0, 1.0)
	assert_near(silhouette.half_width_at(1.2), 1.05, 0.001, "95th percentile 1.0 plus the 0.05 margin, antenna ignored")
	assert_near(silhouette.half_width_at(0.6), 1.05, 0.001, "the neighbouring slice is widened to match")
	assert_near(silhouette.half_width_at(2.9), 0.05, 0.001, "an empty slice is just the margin")


func test_hull_silhouette_follows_the_narrow_spine_and_the_wide_rear_block() -> void:
	var settings := GameSettings.instance()
	var original := settings.exterior_hull
	settings.exterior_hull = true
	var ship := _player_ship()
	var silhouette := ship.exterior_hull.silhouette
	assert_true(silhouette != null, "the hull has a silhouette")
	if silhouette != null:
		assert_true(silhouette.half_width_at(0.0) < ShipHullCollision.HULL_HALF_WIDTH - 1.0, "spine well inside the old 3.2 m wall (%.2f)" % silhouette.half_width_at(0.0))
		assert_true(silhouette.half_width_at(8.0) > ShipHullCollision.HULL_HALF_WIDTH, "rear block wider than the old wall (%.2f)" % silhouette.half_width_at(8.0))
		var beside_spine := Vector3(2.5, -2.0, 0.0)
		var layout := InteriorLayout.player_ship()
		assert_eq(ShipHullCollision.push_out(beside_spine, 0.4, layout.ramp_rect, false, silhouette), beside_spine, "no invisible wall beside the spine")
		assert_true(ShipHullCollision.push_out(beside_spine, 0.4, layout.ramp_rect, false) != beside_spine, "the old box would have pushed there")
		var inside_spine := Vector3(0.5, -2.0, 0.0)
		assert_true(ShipHullCollision.push_out(inside_spine, 0.4, layout.ramp_rect, false, silhouette) != inside_spine, "still blocked where the hull is")
	_discard(ship)
	settings.exterior_hull = original


func test_legs_reach_the_ground_and_support_points_follow_the_hull() -> void:
	var settings := GameSettings.instance()
	var original := settings.exterior_hull
	settings.exterior_hull = true
	var ship := _player_ship()
	var legs := 0
	for child in ship.exterior_hull.get_children():
		if child.has_meta(ExteriorHull.LEG_META):
			legs += 1
			var box := (child as MeshInstance3D).mesh as BoxMesh
			assert_near((child as MeshInstance3D).position.y - box.size.y * 0.5, ExteriorHull.BOTTOM_Y, 0.01, "a leg stands on the gear contact height")
			assert_eq((child as MeshInstance3D).layers, ExteriorHull.layer_bit(ExteriorHull.HULL_LAYER), "a leg is on the hull layer")
	assert_eq(legs, 4, "two front and two rear legs")
	var points := ship.exterior_hull.support_points()
	assert_eq(points.size(), 6, "four gear contacts plus nose and tail")
	for index in 4:
		assert_near(points[index].y, ExteriorHull.BOTTOM_Y, 0.001, "gear contact %d at the lowest hull height" % index)
	assert_eq(ship.tuning.support_points, points, "the ship's ground contact uses them")
	assert_true(points[5].z < ShipHullCollision.HULL_REAR_Z, "the tail point is inside the hull")
	_discard(ship)
	settings.exterior_hull = original


func test_rodina_hull_material_is_dark_and_restores_to_sol() -> void:
	var settings := GameSettings.instance()
	var original := settings.exterior_hull
	settings.exterior_hull = true
	var ship := _player_ship()
	var hull := ship.exterior_hull
	assert_true(hull != null and hull.active, "the cargo hull is available")
	if hull != null and hull.active:
		var mesh_instance: MeshInstance3D = null
		for node in hull.find_children("*", "MeshInstance3D", true, false):
			mesh_instance = node as MeshInstance3D
			if mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0:
				break
		assert_true(mesh_instance != null, "found a hull surface")
		if mesh_instance != null:
			hull.apply_visual_style(true)
			var dark := mesh_instance.get_surface_override_material(0) as StandardMaterial3D
			assert_true(dark != null and dark.albedo_color.v < 0.25, "Rodina hull is dark")
			assert_true(dark.roughness > 0.7, "Rodina hull is not glossy")
			hull.apply_visual_style(false)
			assert_true(mesh_instance.get_surface_override_material(0) == null, "Sol restores the imported material")
	_discard(ship)
	settings.exterior_hull = original
