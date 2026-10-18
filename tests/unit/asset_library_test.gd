extends "res://tests/test_case.gd"
## N9: the asset loader must degrade to the placeholder instead of failing (a missing file or a switched-off toggle).


func test_missing_material_returns_null_and_warns_once() -> void:
	AssetLibrary.reset_warnings()
	assert_true(AssetLibrary.material("mat_does_not_exist") == null, "unknown id gives null")
	assert_true(AssetLibrary.material("mat_does_not_exist") == null, "and again")
	assert_eq(AssetLibrary.warnings.size(), 1, "logged once, not on every call")
	AssetLibrary.reset_warnings()


func test_material_or_falls_back_when_missing() -> void:
	var fallback := StandardMaterial3D.new()
	var settings := GameSettings.instance()
	var original := settings.asset_materials
	settings.asset_materials = true
	assert_true(AssetLibrary.material_or("mat_does_not_exist", fallback) == fallback, "missing file -> the code material")
	settings.asset_materials = original
	AssetLibrary.reset_warnings()


func test_material_or_returns_fallback_when_switched_off_even_if_the_asset_exists() -> void:
	var fallback := StandardMaterial3D.new()
	var settings := GameSettings.instance()
	var original := settings.asset_materials
	settings.asset_materials = false
	assert_true(AssetLibrary.material_or("mat_ship_floor_plate", fallback) == fallback, "switch off -> placeholder")
	assert_true(AssetLibrary.material_copy_or("mat_ship_floor_plate", fallback) == fallback, "same for the private-copy variant")
	settings.asset_materials = original


func test_variant_materials_live_in_their_base_folder() -> void:
	if not ResourceLoader.exists(AssetLibrary.ROOT + "materials/mat_hull_plating/mat_hull_plating_primer.tres"):
		return # not copied yet (an early N9 step)
	var path := AssetLibrary.material_path("mat_hull_plating_primer")
	assert_true(path.ends_with("mat_hull_plating/mat_hull_plating_primer.tres"), "got " + path)


## Every .tres copied into assets/sol must load as a Material with its textures (needs the import that tools/run_tests.sh does first).
func test_every_copied_material_loads() -> void:
	var directory := DirAccess.open(AssetLibrary.ROOT + "materials")
	if directory == null:
		return # nothing copied yet
	for folder in directory.get_directories():
		var inner := DirAccess.open("%smaterials/%s" % [AssetLibrary.ROOT, folder])
		for file in inner.get_files():
			if not file.ends_with(".tres"):
				continue
			var loaded := ResourceLoader.load("%smaterials/%s/%s" % [AssetLibrary.ROOT, folder, file])
			assert_true(loaded is Material, "%s/%s loads as a Material" % [folder, file])
