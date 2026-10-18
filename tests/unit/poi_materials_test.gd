extends "res://tests/test_case.gd"
## N9 S7: POI structures use the Sol-Assets materials when the switch is on and the code materials when it is off.


func _flat_planet() -> PlanetBody:
	var planet := PlanetBody.new()
	planet.height_override = func(_dx: float, _dy: float, _dz: float) -> float: return 0.0
	return planet


func _poi(poi_type: int) -> PoiInstance:
	var poi := PoiInstance.new()
	poi.id = &"poi_material_test"
	poi.type = poi_type
	poi.seed_value = 99
	poi.position = WorldPos.new(&"planet", 0.0, 0.0, 6000000.0) # on the +z pole of a flat 6000 km planet
	return poi


func _materials_in(root: Node) -> Array[Material]:
	var found: Array[Material] = []
	for child in root.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).material_override != null:
			found.append((child as MeshInstance3D).material_override)
	return found


func test_wreck_uses_derelict_hull_and_rusted_metal() -> void:
	var settings := GameSettings.instance()
	var original := settings.asset_materials
	settings.asset_materials = true
	var content := PoiBuilder.build_content(_poi(PoiDefinition.Type.WRECK), _flat_planet())
	var materials := _materials_in(content)
	assert_true(materials.has(AssetLibrary.material("mat_hull_plating_derelict")), "derelict hull plating is on the wreck")
	assert_true(materials.has(AssetLibrary.material("mat_poi_rusted_metal")), "rusted metal is on the wreck")
	content.free()
	settings.asset_materials = original


func test_beacon_outpost_use_concrete() -> void:
	var settings := GameSettings.instance()
	var original := settings.asset_materials
	settings.asset_materials = true
	var concrete := AssetLibrary.material("mat_poi_concrete")
	assert_true(concrete != null, "concrete loads")
	for poi_type in [PoiDefinition.Type.BEACON, PoiDefinition.Type.OUTPOST]:
		var content := PoiBuilder.build_content(_poi(poi_type), _flat_planet())
		assert_true(_materials_in(content).has(concrete), "type %d carries concrete" % poi_type)
		content.free()
	settings.asset_materials = original


func test_switch_off_keeps_the_code_materials() -> void:
	var settings := GameSettings.instance()
	var original := settings.asset_materials
	settings.asset_materials = false
	for poi_type in [PoiDefinition.Type.WRECK, PoiDefinition.Type.BEACON, PoiDefinition.Type.OUTPOST]:
		var content := PoiBuilder.build_content(_poi(poi_type), _flat_planet())
		for material in _materials_in(content):
			assert_true(material is StandardMaterial3D, "only code StandardMaterial3D materials with the switch off")
			assert_true(not (material is ORMMaterial3D), "no ORM asset material with the switch off")
		content.free()
	settings.asset_materials = original
