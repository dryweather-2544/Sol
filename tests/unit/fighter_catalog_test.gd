extends "res://tests/test_case.gd"
## The small single-seat fighters: roster data, how a Ship is configured from one, the model builder's fallback,
## and the skirmish waves. The .glb files are not committed, so nothing here requires them to exist.

const DELTA := 1.0 / 60.0


func _flat_planet() -> PlanetBody:
	var planet := PlanetBody.new()
	planet.height_override = func(_dx: float, _dy: float, _dz: float) -> float: return 0.0
	return planet


func _session(planet: PlanetBody) -> GameSession:
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	ship.state.position = WorldPos.new(planet.frame_id, 0.0, 0.0, planet.radius + 2.1)
	return GameSession.new(planet, ship, PilotSource.new())


func test_roster_is_complete_and_unique() -> void:
	var ids := {}
	for def in FighterCatalog.all():
		assert_true(not ids.has(def.id), "%s listed once" % def.id)
		ids[def.id] = true
		assert_true(def.size > 5.0 and def.size < 20.0, "%s is smaller than the player's ship" % def.id)
		assert_true(def.model_path.begins_with("res://assets/fighters/") and def.model_path.ends_with(".glb"), def.id)
		assert_true(def.toughness > 0.0 and def.gun_rate > 0.0 and def.gun_damage > 0.0, def.id)
		assert_true(def.nominal_dps() <= 0.08, "%s is a nuisance, not an instant kill" % def.id)
	for role in [FighterDef.Role.INTERCEPTOR, FighterDef.Role.FIGHTER, FighterDef.Role.HEAVY, FighterDef.Role.ACE]:
		assert_true(FighterCatalog.of_roles([role]).size() >= 2, "two or more %s" % FighterDef.role_name(role))
	assert_true(FighterCatalog.by_id(&"talon") != null)
	assert_true(FighterCatalog.by_id(&"nope") == null)


func test_waves_grow_and_unlock_heavier_roles() -> void:
	assert_eq(FighterCatalog.wave_size(1), 2)
	assert_eq(FighterCatalog.wave_size(3), 4)
	assert_eq(FighterCatalog.wave_size(50), 5, "capped")
	assert_true(not FighterDef.Role.HEAVY in FighterCatalog.roles_for_wave(2))
	assert_true(FighterDef.Role.HEAVY in FighterCatalog.roles_for_wave(3))
	assert_true(not FighterDef.Role.ACE in FighterCatalog.roles_for_wave(4))
	assert_true(FighterDef.Role.ACE in FighterCatalog.roles_for_wave(5))
	var wing := FighterCatalog.wave(6, SeedRng.new(5))
	assert_eq(wing.size(), 5)
	assert_eq(wing[0].role, FighterDef.Role.ACE, "late waves always carry an ace")
	var first := FighterCatalog.wave(3, SeedRng.new(9))
	var second := FighterCatalog.wave(3, SeedRng.new(9))
	for index in first.size():
		assert_eq(first[index].id, second[index].id, "same seed, same wing")


func test_configure_fighter_applies_handling_and_gun() -> void:
	var baseline := Ship.new()
	var def := FighterCatalog.by_id(&"dart")
	var ship := Ship.new()
	ship.configure_fighter(def)
	assert_near(ship.tuning.gear_max_speed[PilotCommand.GEAR_COMBAT], baseline.tuning.gear_max_speed[PilotCommand.GEAR_COMBAT] * def.speed_scale, 1e-5)
	assert_near(ship.tuning.rotation_speed, baseline.tuning.rotation_speed * def.turn_scale, 1e-5)
	assert_near(ship.tuning.support_points[0].y, baseline.tuning.support_points[0].y * def.size / FighterDef.REFERENCE_SIZE, 1e-5, "landing points shrink with the hull")
	assert_near(baseline.tuning.support_points[0].y, -2.0, 1e-5, "other ships' tuning is untouched")
	assert_near(ship.weapon.damage, def.gun_damage, 1e-12)
	assert_near(ship.weapon.shots_per_second, def.gun_rate, 1e-12)
	assert_near(ship.muzzle_offset.z, -def.size * 0.45, 1e-5)
	assert_near(ship.barrel_x, def.size * 0.1, 1e-5)
	baseline.free()
	ship.free()


func test_toughness_divides_incoming_damage() -> void:
	var soft := Ship.new()
	var tough := Ship.new()
	ShipCombatant.new(soft, 1, 5.0, 1.0).apply_damage(0.1, null)
	ShipCombatant.new(tough, 1, 5.0, 2.0).apply_damage(0.1, null)
	assert_near(soft.state.hull, 0.9, 1e-5)
	assert_near(tough.state.hull, 0.95, 1e-5)
	soft.free()
	tough.free()


func test_model_builder_adds_a_holder_and_scales_to_size() -> void:
	var def := FighterCatalog.by_id(&"talon")
	var node := Node3D.new()
	FighterModel.build(node, def)
	var holder := node.get_node_or_null("FighterModel") as Node3D
	assert_true(holder != null, "model holder exists with or without the .glb")
	if ResourceLoader.exists(def.model_path):
		var box := FighterModel._bounds(holder, Transform3D.IDENTITY, [])
		var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
		assert_near(longest, def.size, 0.05 * def.size, "model is scaled so its longest side is the def's size")
		assert_near(box.get_center().length(), 0.0, 0.1 * def.size, "model is centred")
	else:
		assert_near(holder.scale.x, def.size / FighterDef.REFERENCE_SIZE, 1e-5, "placeholder fallback is scaled to size")
	node.free()


func test_skirmish_waves_spawn_attack_and_escalate() -> void:
	var planet := _flat_planet()
	var session := _session(planet)
	var manager := PoiManager.new(PoiPlanner.new(planet, 77, 1.0))
	var director := EnemyDirector.new()
	director.session = session
	director.planet = planet
	director.poi_manager = manager
	var first_size := director.spawn_skirmish()
	assert_eq(first_size, FighterCatalog.wave_size(1))
	assert_eq(session.enemy_targets.size(), first_size)
	assert_eq(director.spawn_skirmish(), 0, "one wave at a time")
	var scrap_before := session.inventory.count(ItemDefinition.SCRAP)
	for target in session.enemy_targets.duplicate():
		assert_eq((target as ShipCombatant).ship.team_id, 1)
		(target as ShipCombatant).apply_damage(100.0, null) # destroyed signal pays the kill reward
	assert_eq(session.inventory.count(ItemDefinition.SCRAP), scrap_before + first_size, "1 scrap per kill")
	director._refresh(session.player_world_position())
	assert_eq(director.active_encounter_count(), 0, "a dead wave is removed")
	assert_eq(session.enemy_targets.size(), 0)
	assert_eq(director.spawn_skirmish(), FighterCatalog.wave_size(2), "the next wave is bigger")
	director.clear_all()
	director.free()
	manager.free()
	session.ship.free()


func _fighter_craft(def_id: StringName) -> Ship:
	var craft := Ship.new()
	craft.player_controlled = true
	craft.configure_fighter(FighterCatalog.by_id(def_id))
	return craft


func test_a_fighter_is_a_separate_ship_with_its_own_tuning() -> void:
	var mother := Ship.new()
	var craft := _fighter_craft(&"raptor")
	var def := FighterCatalog.by_id(&"raptor")
	assert_true(craft.fighter == def and mother.fighter == null)
	assert_true(craft.nose_gun_enabled, "a fighter shoots from its nose")
	assert_near(craft.tuning.gear_max_speed[PilotCommand.GEAR_COMBAT], mother.tuning.gear_max_speed[PilotCommand.GEAR_COMBAT] * def.speed_scale, 1e-5)
	assert_true(craft.systems == null, "no interior, doors or crew")
	assert_true(def.engines.size() >= 1, "engine flame positions are listed")
	assert_true(def.cockpit != Vector3.ZERO, "the cockpit eye point is listed")
	mother.free()
	craft.free()


func test_boarding_a_fighter_from_the_helm_parks_the_mothership() -> void:
	var session := _session(_flat_planet())
	var craft := _fighter_craft(&"dart")
	session.board_fighter(craft)
	assert_eq(session.mode, GameSession.Mode.FIGHTER)
	assert_true(session.active_ship() == craft)
	assert_true(craft.controller.current_source == session.pilot_source, "the player now flies the fighter")
	assert_true(session.ship.controller.current_source != session.pilot_source, "not the mothership")
	assert_true(session.ship.controller.current_source != null, "an idle autopilot holds the mothership in place")
	session.return_to_mothership()
	assert_eq(session.mode, GameSession.Mode.SEATED)
	assert_true(session.active_ship() == session.ship)
	assert_true(session.ship.controller.current_source == session.pilot_source, "back at the helm")
	assert_true(session.fighter_craft == null, "a fighter in the air is let go")
	craft.free()
	session.ship.free()


func test_boarding_from_on_foot_and_climbing_out_on_the_ground() -> void:
	var planet := _flat_planet()
	var session := _session(planet)
	session.restore_mode(GameSession.Mode.OUTSIDE)
	session.exterior_body.place_on_ground(planet, session.ship.state.position, Vector3.FORWARD)
	var craft := _fighter_craft(&"wasp")
	craft.state.position = session.exterior_body.position.offset_by(Vector3(0, 0, -8))
	session.fighter_craft = craft
	assert_true(session.fighter_in_reach(), "a fighter beside you can be boarded")
	session.board_fighter(craft)
	assert_eq(session.mode, GameSession.Mode.FIGHTER)
	assert_eq(session.mode_before_fighter, GameSession.Mode.OUTSIDE)
	assert_true(session.climb_out_of_fighter() != "", "no climbing out in the air")
	craft.state.landed = true
	assert_eq(session.climb_out_of_fighter(), "")
	assert_eq(session.mode, GameSession.Mode.OUTSIDE)
	assert_true(session.fighter_craft == craft, "a landed fighter stays parked")
	craft.free()
	session.ship.free()


func test_losing_the_fighter_returns_the_player_and_saves_skip_it() -> void:
	var session := _session(_flat_planet())
	var craft := _fighter_craft(&"nova")
	session.board_fighter(craft)
	var saved := SaveGame.capture(session, 1, 0.0)
	assert_eq(int(saved["player"]["mode"]), GameSession.Mode.SEATED, "the saved game is the mothership's, at the helm")
	session.lose_fighter()
	assert_eq(session.mode, GameSession.Mode.SEATED)
	assert_true(session.fighter_craft == null and session.active_ship() == session.ship)
	craft.free()
	session.ship.free()


func test_cockpit_builds_on_its_own_render_layer() -> void:
	var def := FighterCatalog.by_id(&"talon")
	var craft := Ship.new()
	craft.configure_fighter(def)
	var cockpit := FighterCockpit.new()
	cockpit.setup(craft, def)
	assert_true(cockpit.find_children("*", "Node3D", true, false).size() > 40, "frame, dash, consoles, buttons, stick and seat")
	var drawn := 0
	for node in cockpit.find_children("*", "GeometryInstance3D", true, false):
		drawn += 1
		assert_eq((node as GeometryInstance3D).layers, FighterCockpit.LAYER_MASK, "%s is on the cockpit layer only" % node.name)
	assert_true(drawn > 40)
	cockpit._process(1.0 / 60.0) # no cockpit camera yet: stays hidden, hull model untouched
	assert_true(not cockpit.visible)
	cockpit.free()
	craft.free()


func test_radar_puts_forward_contacts_up_the_screen() -> void:
	var ahead := FighterRadar.to_screen(Vector3(0.0, 0.0, -1250.0), 2500.0, 100.0)
	assert_near(ahead.x, 0.0, 1e-6)
	assert_near(ahead.y, -50.0, 1e-6)
	var right := FighterRadar.to_screen(Vector3(2500.0, 0.0, 0.0), 2500.0, 100.0)
	assert_near(right.x, 100.0, 1e-6)
	var far := FighterRadar.to_screen(Vector3(0.0, 0.0, -50000.0), 2500.0, 100.0)
	assert_near(far.length(), 100.0, 1e-6, "contacts beyond the range sit on the rim")


func test_the_players_fighter_has_a_real_gun_and_answers_the_stick_faster() -> void:
	var def := FighterCatalog.by_id(&"talon")
	var hostile := Ship.new()
	hostile.configure_fighter(def)
	var mine := _fighter_craft(&"talon")
	var mother := Ship.new()
	assert_near(hostile.weapon.damage, def.gun_damage, 1e-12, "AI fighters keep the low per-def gun")
	assert_true(mine.weapon.damage * mine.weapon.shots_per_second > hostile.weapon.damage * hostile.weapon.shots_per_second * 3.0, "the player's gun is much stronger")
	var combat := PilotCommand.GEAR_COMBAT
	assert_near(mine.tuning.gear_rotation_hardness[combat], mother.tuning.gear_rotation_hardness[combat] * Ship.FIGHTER_TURN_RESPONSE, 1e-9, "the stick pushes the turn harder than the mothership's")
	hostile.free()
	mine.free()
	mother.free()


func test_a_fighter_ai_turns_before_it_thrusts_and_the_chase_camera_is_rigid() -> void:
	var ai := AIPilotSource.new(AIPilotSource.Mode.ATTACK)
	ai.turn_before_thrust = true
	ai.move_lock_strength = 0.25
	var behind := WorldPos.new(&"space", 0.0, 0.0, 3000.0) # the target is behind a ship that faces -z
	ai.target_provider = func(): return behind
	var state := ShipState.new()
	state.position = WorldPos.new(&"space")
	var command := ai.poll(state, 1.0 / 60.0)
	assert_near(command.thrust.z, 0.0, 1e-6, "no racing off the wrong way")
	assert_near(command.move_lock, 0.25, 1e-9)
	var ahead := WorldPos.new(&"space", 0.0, 0.0, -3000.0)
	ai.target_provider = func(): return ahead
	command = ai.poll(state, 1.0 / 60.0)
	assert_true(command.thrust.z < -0.9, "full drive once the nose is on the target")
	var camera := ChaseCamera.new()
	var target := Node3D.new()
	camera.target = target
	camera.rigid_follow = true
	camera.snap_to_target()
	target.rotate_y(1.0)
	camera._physics_process(1.0 / 60.0)
	assert_near(Quaternion(camera.global_basis.orthonormalized()).angle_to(Quaternion(target.global_basis.orthonormalized())), 0.0, 0.2, "the view turns with the hull at once")
	camera.free()
	target.free()
