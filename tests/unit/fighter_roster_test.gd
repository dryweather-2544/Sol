extends "res://tests/test_case.gd"
## The thirty small fighters and the ten cockpit interiors they sit in: every craft is its own hull, stat line, screen colour and line of
## character; every interior is wired to something. The model files are git-ignored, so nothing here requires them to exist.

const Spec := preload("res://src/flight/fighter_cockpit_spec.gd")


func test_there_are_thirty_fighters_and_none_repeats_another() -> void:
	var defs := FighterCatalog.all()
	assert_eq(defs.size(), 30, "thirty fighters")
	var names := {}
	var models := {}
	var accents := {}
	var blurbs := {}
	var stat_lines := {}
	for def in defs:
		assert_true(not names.has(def.display_name), "%s: name used once" % def.id)
		names[def.display_name] = true
		assert_true(not models.has(def.model_path), "%s: hull model used once" % def.id)
		models[def.model_path] = true
		assert_true(not accents.has(def.accent.to_html()), "%s: screen colour used once" % def.id)
		accents[def.accent.to_html()] = true
		assert_true(def.blurb != "" and not blurbs.has(def.blurb), "%s: its own line of character" % def.id)
		blurbs[def.blurb] = true
		var line := "%s/%s/%s/%s/%s/%s/%s/%s" % [def.size, def.speed_scale, def.turn_scale, def.toughness, def.gun_damage, def.gun_rate, def.preferred_range, def.aim_error]
		assert_true(not stat_lines.has(line), "%s: its own stat line" % def.id)
		stat_lines[line] = true


func test_every_role_has_a_proper_squad_and_every_craft_is_sane() -> void:
	for role in [FighterDef.Role.INTERCEPTOR, FighterDef.Role.FIGHTER, FighterDef.Role.HEAVY, FighterDef.Role.ACE]:
		assert_true(FighterCatalog.of_roles([role]).size() >= 6, "six or more %s" % FighterDef.role_name(role))
	for def in FighterCatalog.all():
		assert_true(def.size >= 8.0 and def.size <= 17.5, "%s: small-craft size" % def.id)
		assert_true(def.nominal_dps() > 0.03 and def.nominal_dps() <= 0.08, "%s: a real gun that is not an instant kill" % def.id)
		assert_near(def.cockpit.z, -0.12 * def.size, 0.1 * def.size * 0.12 + 0.1, "%s: the pilot's eye sits a tenth of the hull back from the nose" % def.id)
		assert_true(def.cockpit.x == 0.0, "%s: eye on the centre line" % def.id)
		assert_true(def.engines.size() >= 1 and def.engines.size() <= 2, "%s: one or two engines" % def.id)
		for engine in def.engines:
			assert_true(engine.z > def.size * 0.3 and engine.z <= def.size * 0.55, "%s: engines at the tail" % def.id)
	# tougher hulls turn slower: the heavies are the slowest turners, the interceptors the quickest
	var slowest_interceptor_turn := 99.0
	var fastest_heavy_turn := 0.0
	for def in FighterCatalog.of_roles([FighterDef.Role.INTERCEPTOR]):
		slowest_interceptor_turn = minf(slowest_interceptor_turn, def.turn_scale)
	for def in FighterCatalog.of_roles([FighterDef.Role.HEAVY]):
		fastest_heavy_turn = maxf(fastest_heavy_turn, def.turn_scale)
	assert_true(slowest_interceptor_turn > fastest_heavy_turn, "every interceptor out-turns every heavy")


func test_every_craft_has_an_interior_and_every_interior_is_used() -> void:
	var specs := Spec.all()
	assert_eq(specs.size(), 10, "ten interiors")
	var used := {}
	for def in FighterCatalog.all():
		assert_true(specs.has(def.cockpit_id), "%s sits in a known interior" % def.id)
		used[def.cockpit_id] = int(used.get(def.cockpit_id, 0)) + 1
	for spec_id in specs:
		assert_true(int(used.get(spec_id, 0)) >= 2, "%s is used by two or more fighters" % spec_id)
	assert_eq(Spec.by_id(&"nope").id, &"xwing", "an unknown id falls back to the first interior")


func test_interior_numbers_hang_together() -> void:
	for spec_id in Spec.all():
		var spec = Spec.all()[spec_id]
		assert_true(spec.model_path.begins_with("res://assets/cockpit/") and spec.model_path.ends_with(".glb"), "%s: model path" % spec_id)
		assert_true(spec.eye.y > spec.floor_y + 0.55 and spec.eye.y < spec.floor_y + 1.4, "%s: the eye is a seated pilot's height over the floor" % spec_id)
		assert_true(spec.eye.y > spec.sill_y, "%s: the eye is above the window sill" % spec_id)
		assert_true(spec.front_z > spec.back_z + 0.5, "%s: the cabin has length" % spec_id)
		assert_true(spec.half_width > 0.3 and spec.half_width < 1.5, "%s: the cabin has width" % spec_id)
		assert_true(spec.plate_size >= 0.15 and spec.plate_size <= 0.3, "%s: readable screens" % spec_id)
		assert_true(spec.plate_centre.z > 0.3 and spec.plate_centre.z < 1.0, "%s: screens are ahead of the pilot" % spec_id)
		assert_true(spec.plate_centre.x > 0.2 and spec.plate_centre.x < 0.8, "%s: one screen either side" % spec_id)
		assert_true(spec.plate_centre.y < spec.eye.y, "%s: screens are below the eye line" % spec_id)


func test_a_cockpit_is_built_for_every_fighter_in_its_own_colour() -> void:
	for def in FighterCatalog.all():
		var craft := Ship.new()
		craft.configure_fighter(def)
		var cockpit := FighterCockpit.new()
		cockpit.setup(craft, def)
		if cockpit.interior_id != &"canopy": # (with no model files on disk the home-built canopy stands in)
			assert_true(cockpit.interior_id == def.cockpit_id or cockpit.interior_id == &"xwing", "%s: its own interior, or the first one when its file is missing" % def.id)
		var drawn := 0
		for node in cockpit.find_children("*", "GeometryInstance3D", true, false):
			drawn += 1
			assert_eq((node as GeometryInstance3D).layers, FighterCockpit.LAYER_MASK, "%s: %s is on the cockpit layer only" % [def.id, node.name])
		assert_true(drawn >= 6, "%s: a cockpit has an interior mesh, a fill, a seat and screens (the newer interiors are one many-surface mesh)" % def.id)
		cockpit._process(1.0 / 60.0)
		assert_true(not cockpit.visible, "%s: hidden until the cockpit camera is current" % def.id)
		cockpit.free()
		craft.free()


func test_screens_take_the_crafts_colour() -> void:
	const Display := preload("res://src/flight/fighter_display.gd")
	var display := Display.new()
	assert_eq(display.accent, Display.CYAN, "cyan unless told otherwise")
	display.accent = Color(0.9, 0.3, 0.3)
	assert_eq(display._level_colour(0.9), Color(0.9, 0.3, 0.3), "a healthy gauge uses the accent")
	assert_eq(display._level_colour(0.5), Display.AMBER, "warning colours stay")
	assert_eq(display._level_colour(0.1), Display.ALERT)
	assert_eq(Display.level_color(0.9), Display.CYAN, "the static helper is unchanged")
	display.free()
