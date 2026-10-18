extends "res://tests/test_case.gd"
## N9 S2: the ship's roles use the Sol-Assets materials when the switch is on and the original code materials when it is off.
## ShipVisuals._ready() is called directly (no scene tree needed); the assets must be imported, which tools/run_tests.sh does first.


func _build_visuals() -> ShipVisuals:
	var ship := Ship.new()
	ship.systems = ShipSystems.new()
	var visuals := ShipVisuals.new()
	visuals.ship = ship
	visuals._ready()
	return visuals


func _meshes_using(visuals: ShipVisuals, material: Material) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for child in visuals.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).material_override == material:
			found.append(child as MeshInstance3D)
	return found


func _has_probe(visuals: ShipVisuals) -> bool:
	for child in visuals.get_children():
		if child is ReflectionProbe:
			return true
	return false


func test_roles_use_asset_materials_when_the_switch_is_on() -> void:
	var settings := GameSettings.instance()
	var original := settings.asset_materials
	settings.asset_materials = true
	var paint := AssetLibrary.material("mat_ship_paint_panel")
	assert_true(paint != null, "mat_ship_paint_panel loads (assets copied and imported)")
	var visuals := _build_visuals()
	assert_true(visuals._wall_material == paint, "walls and ceilings use the paint panel")
	assert_true(visuals._floor_slab_material == AssetLibrary.material("mat_ship_floor_plate"), "floors use the floor plate")
	assert_true(visuals._door_material == AssetLibrary.material("mat_ship_brushed_metal"), "doors use brushed metal")
	assert_true(_meshes_using(visuals, paint).size() >= 6, "the walls/ceilings really carry it (got %d boxes)" % _meshes_using(visuals, paint).size())
	assert_true(_meshes_using(visuals, AssetLibrary.material("mat_ship_rubber_mat")).size() >= 2, "airlock and cargo floors are rubber")
	assert_true(_has_probe(visuals), "an interior reflection probe is added for the metal")
	visuals.free()
	settings.asset_materials = original


func test_both_nacelles_get_the_nozzle_and_an_exhaust_disc() -> void:
	var settings := GameSettings.instance()
	var original := settings.asset_materials
	settings.asset_materials = true
	var nozzle := AssetLibrary.material("mat_hull_nozzle")
	assert_true(nozzle != null, "mat_hull_nozzle loads")
	var visuals := _build_visuals()
	var nacelles := _meshes_using(visuals, nozzle)
	assert_eq(nacelles.size(), 2, "two nacelles")
	for nacelle in nacelles:
		assert_eq(nacelle.get_child_count(), 1, "each nacelle carries one exhaust disc")
		assert_true((nacelle.get_child(0) as MeshInstance3D).material_override == visuals._glow_material, "the disc is the engine glow")
	visuals.free()
	settings.asset_materials = original


func test_switch_off_restores_the_original_look() -> void:
	var settings := GameSettings.instance()
	var original := settings.asset_materials
	settings.asset_materials = false
	var visuals := _build_visuals()
	assert_true(visuals._wall_material == visuals._hull_material, "walls are the code hull material again")
	assert_true(visuals._nozzle_material == visuals._glow_material, "nacelles glow as before")
	assert_true(not _has_probe(visuals), "no probe without assets")
	assert_eq(_meshes_using(visuals, visuals._glow_material).size() >= 2, true, "the glow material is back on the nacelles")
	visuals.free()
	settings.asset_materials = original
