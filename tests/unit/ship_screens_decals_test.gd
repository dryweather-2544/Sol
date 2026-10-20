extends "res://tests/test_case.gd"
## N9 S3: station screens, the nav screen and the decals. ShipVisuals._ready()/_process() are called directly (no scene tree).


func _build_visuals() -> ShipVisuals:
	var ship := Ship.new()
	ship.systems = ShipSystems.new()
	var visuals := ShipVisuals.new()
	visuals.ship = ship
	visuals._ready()
	return visuals


func _decals(visuals: ShipVisuals) -> Array[Decal]:
	var found: Array[Decal] = []
	for child in visuals.get_children():
		if child is Decal:
			found.append(child as Decal)
	return found


func test_decal_catalog_entries_match_the_decals_built() -> void:
	var settings := GameSettings.instance()
	var original := settings.decals
	settings.decals = true
	var visuals := _build_visuals()
	var decals := _decals(visuals)
	# 6 room plates + 2 airlock stripes + 5 station IDs + 1 reactor stripe + one scorch per hazard room
	var hazard_rooms := 0
	for room_id in visuals.ship.systems.layout.rooms:
		if visuals.ship.systems.hazards.has_room(room_id):
			hazard_rooms += 1
	assert_eq(decals.size(), 14 + hazard_rooms, "decal count (14 fixed + %d scorch)" % hazard_rooms)
	for decal in decals:
		var entry: Dictionary = {}
		# Duplicate sibling names get Godot's @Decal@ auto-name; the builder stores the authored
		# catalogue identity in metadata so the test still checks the source entry.
		var catalog_name := String(decal.get_meta(&"catalog_name", decal.name.trim_prefix("Decal_")))
		var catalog_set := String(decal.get_meta(&"catalog_set", ""))
		if catalog_set != "" and DecalCatalog.SETS.has(catalog_set):
			entry = DecalCatalog.SETS[catalog_set].get(catalog_name, {})
		else:
			for set_id in DecalCatalog.SETS:
				if DecalCatalog.SETS[set_id].has(catalog_name):
					entry = DecalCatalog.SETS[set_id][catalog_name]
					break
		assert_true(not entry.is_empty(), "%s is in the catalogue" % decal.name)
		if entry.is_empty():
			continue
		assert_true(decal.size.is_equal_approx(Vector3(entry["size_x"], entry["depth"], entry["size_z"])), "%s size matches decals.csv" % decal.name)
		assert_true(decal.texture_albedo != null, "%s has its albedo" % decal.name)
		assert_true(absf(decal.albedo_mix - float(entry["albedo_mix"])) < 0.0001, "%s albedo_mix matches" % decal.name)
	visuals.free()
	settings.decals = original


func test_decals_sit_inside_the_ship() -> void:
	var settings := GameSettings.instance()
	var original := settings.decals
	settings.decals = true
	var visuals := _build_visuals()
	var layout := visuals.ship.systems.layout
	for decal in _decals(visuals):
		var position := decal.position
		assert_true(position.x >= -3.2 and position.x <= 3.2, "%s x=%.2f within the hull" % [decal.name, position.x])
		assert_true(position.z >= -7.2 and position.z <= 10.7, "%s z=%.2f within the hull" % [decal.name, position.z])
		assert_true(position.y >= layout.floor_y - 0.01 and position.y <= layout.ceiling_y + 0.01, "%s y=%.2f between floor and ceiling" % [decal.name, position.y])
	visuals.free()
	settings.decals = original


func test_wall_decal_basis_faces_the_viewer_with_the_top_up() -> void:
	for normal in [Vector3.RIGHT, Vector3.LEFT, Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var basis := ShipVisuals._wall_decal_basis(normal)
		assert_true(basis.y.is_equal_approx(normal), "local +y is the wall normal %s" % str(normal))
		assert_true((-basis.z).is_equal_approx(Vector3.UP), "the texture top (local -z) points up for %s" % str(normal))
		assert_true(absf(basis.determinant() - 1.0) < 0.001, "a proper rotation (not mirrored) for %s" % str(normal))


func test_scorch_is_hidden_until_the_room_burns() -> void:
	var settings := GameSettings.instance()
	var original := settings.decals
	settings.decals = true
	var visuals := _build_visuals()
	var scorch: Decal = visuals._scorch_decals.get(&"engineering")
	assert_true(scorch != null, "engineering has a scorch decal")
	if scorch != null:
		assert_true(not scorch.visible, "hidden before any fire")
		visuals.ship.systems.hazards.ignite(&"engineering")
		visuals._process(0.016)
		assert_true(scorch.visible, "visible once the room has burned")
	visuals.free()
	settings.decals = original


func test_no_decals_when_the_switch_is_off() -> void:
	var settings := GameSettings.instance()
	var original := settings.decals
	settings.decals = false
	var visuals := _build_visuals()
	assert_eq(_decals(visuals).size(), 0, "no decals")
	assert_true(visuals._scorch_decals.is_empty(), "no scorch decals")
	visuals.free()
	settings.decals = original


func test_screens_keep_their_tint_contract_and_stand_proud_of_the_wall() -> void:
	var settings := GameSettings.instance()
	var original := settings.asset_materials
	settings.asset_materials = true
	var visuals := _build_visuals()
	var reactor: StandardMaterial3D = visuals._station_screens[&"reactor_panel"]
	var energy_before := reactor.emission_energy_multiplier
	visuals._process(0.016)
	assert_eq(reactor.emission_energy_multiplier, energy_before, "the game never touches emission_energy_multiplier (the asset's value is kept)")
	assert_true(reactor.albedo_color.is_equal_approx(reactor.emission), "albedo_color and emission carry the same state colour")
	assert_true(reactor.emission.g > reactor.emission.r, "a cold reactor reads green")
	assert_true(reactor != visuals._station_screens[&"engine_station"], "reactor and generic screens are separate copies")
	# Wall inner faces are at +-3.0 (rooms are 6 m wide); the screen box is 0.06 thick, centred 0.27 m off the panel point at x = -+2.7.
	var layout := visuals.ship.systems.layout
	for point in layout.interact_points:
		if point["id"] in [&"reactor_panel", &"engine_station"]:
			var wall_side := 1.0 if point["position"].x > 0.0 else -1.0
			var front_face := absf(point["position"].x + wall_side * 0.27) - 0.03
			assert_true(front_face < 3.0, "%s screen front face (|x|=%.3f) is not inside the wall" % [point["id"], front_face])
	visuals.free()
	settings.asset_materials = original


func test_screens_fall_back_to_the_emissive_material_when_the_switch_is_off() -> void:
	var settings := GameSettings.instance()
	var original := settings.asset_materials
	settings.asset_materials = false
	var visuals := _build_visuals()
	assert_true(visuals._station_screens.has(&"reactor_panel"), "the reactor screen still exists")
	assert_true(visuals._station_screens[&"reactor_panel"] != AssetLibrary.material("mat_ship_screen_reactor"), "and it is not the asset")
	visuals.free()
	settings.asset_materials = original
