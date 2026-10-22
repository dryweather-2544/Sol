extends "res://tests/test_case.gd"

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
	ship.state.basis = Basis(Vector3.RIGHT, PI / 2.0)
	var session := GameSession.new(planet, ship, PilotSource.new())
	for tick in 120:
		session.tick(DELTA, OnFootCommand.new())
	session.interact()
	session.exterior_body.place_on_ground(planet, ship.state.position.offset_by(ship.state.basis.x * 30.0), Vector3(1, 0, 0))
	session.restore_mode(GameSession.Mode.OUTSIDE)
	return session


func test_drone_ignores_a_distant_player_then_closes_in_and_shoots_them() -> void:
	var planet := _flat_planet()
	var session := _session(planet)
	var spawn := session.exterior_body.position.offset_by(Vector3(1, 0, 0) * 200.0)
	var drone := GroundEnemy.new(planet, spawn, 5)
	session.enemy_targets.append(CombatTargets.GroundEnemyTarget.new(drone))
	var start := drone.body.position.duplicate_position()
	for tick in 120:
		drone.step(DELTA, session.exterior_body.position, planet, session.projectiles)
	assert_true(drone.body.position.distance_to(start) < 0.1, "idle while the player is far away")
	drone.body.place_on_ground(planet, session.exterior_body.position.offset_by(Vector3(1, 0, 0) * 60.0), Vector3(1, 0, 0))
	var closest := INF
	for tick in 60 * 15:
		drone.step(DELTA, session.exterior_body.position, planet, session.projectiles)
		session.tick(DELTA, OnFootCommand.new())
		closest = minf(closest, drone.body.position.distance_to(session.exterior_body.position))
	assert_true(closest < GroundEnemy.KEEP_DISTANCE + 3.0 and closest > GroundEnemy.KEEP_DISTANCE - 4.0, "stopped at keep-off range: %f" % closest)
	assert_true(session.suit.health < 1.0, "its shots hurt the player")
	session.ship.free()


func test_player_pistol_kills_a_drone_in_a_few_hits_and_shots_respect_teams() -> void:
	var planet := _flat_planet()
	var session := _session(planet)
	var drone_position := session.exterior_body.position.offset_by(Vector3(0, 1, 0) * 25.0)
	var drone := GroundEnemy.new(planet, drone_position, 9)
	session.enemy_targets.append(CombatTargets.GroundEnemyTarget.new(drone))
	var aim := (drone.body.position.offset_by(Vector3(drone.body.position.x, drone.body.position.y, drone.body.position.z).normalized() * 1.0)).vector_from(session.exterior_body.position.offset_by(Vector3(session.exterior_body.position.x, session.exterior_body.position.y, session.exterior_body.position.z).normalized() * 1.5)).normalized()
	var fired := 0
	for tick in 60 * 6:
		session.player_fire(aim)
		session.tick(DELTA, OnFootCommand.new())
		if not drone.is_alive():
			break
	assert_true(not drone.is_alive(), "three pistol hits (0.34 each) kill a 1.0 health drone")
	assert_near(session.suit.health, 1.0, 1e-9, "the player's own shots never hurt the player")
	session.ship.free()


func test_enemy_director_spawns_guards_once_and_clearing_is_remembered() -> void:
	var planet := _flat_planet()
	var session := _session(planet)
	var planner := PoiPlanner.new(planet, 77, 1.0)
	var manager := PoiManager.new(planner)
	var outpost: PoiInstance
	for instance in planner.plan_region(session.exterior_body.position, 30000.0):
		if instance.type == PoiDefinition.Type.OUTPOST and (outpost == null or instance.position.distance_to(session.exterior_body.position) < outpost.position.distance_to(session.exterior_body.position)):
			outpost = instance
	assert_true(outpost != null, "the dense test world has an outpost")
	manager.viewer = outpost.position.offset_by(PoiBuilder.frame_basis(outpost).x * 300.0)
	manager.update_now()
	var director := EnemyDirector.new()
	director.session = session
	director.planet = planet
	director.poi_manager = manager
	session.exterior_body.place_on_ground(planet, manager.viewer, Vector3(1, 0, 0))
	var outposts_in_range := 0
	for instance in manager.known_instances():
		if instance.type == PoiDefinition.Type.OUTPOST and instance.position.distance_to(manager.viewer) < PoiRings.CONTENT_ENTER:
			outposts_in_range += 1
	assert_true(outposts_in_range >= 1)
	for refresh in outposts_in_range: # the director builds at most one outpost's guards per refresh
		director._refresh(manager.viewer)
	assert_eq(director.active_encounter_count(), outposts_in_range)
	assert_eq(session.enemy_targets.size(), outposts_in_range * (EnemyDirector.SHIPS_PER_OUTPOST + EnemyDirector.DRONES_PER_OUTPOST))
	director._refresh(manager.viewer)
	assert_eq(director.active_encounter_count(), outposts_in_range, "no duplicate spawn")
	for target in session.enemy_targets:
		if target is ShipCombatant:
			target.ship.state.hull = 0.0
		else:
			target.enemy.health = 0.0
	var scrap_before := session.inventory.count(ItemDefinition.SCRAP)
	director._refresh(manager.viewer)
	assert_true(session.cleared_log.is_cleared(outpost.id), "outposts marked cleared")
	assert_eq(director.active_encounter_count(), 0)
	assert_eq(session.enemy_targets.size(), 0)
	assert_eq(session.inventory.count(ItemDefinition.SCRAP), scrap_before + 4 * outposts_in_range)
	director._refresh(manager.viewer)
	assert_eq(director.active_encounter_count(), 0, "a cleared outpost does not respawn guards")
	director.free()
	manager.free()
	session.ship.free()
