extends "res://tests/test_case.gd"
## POI planning, rings and discovery.

const DELTA := 1.0 / 60.0


func _planner(seed_value: int = 99, density: float = 0.22) -> PoiPlanner:
	return PoiPlanner.new(PlanetBody.new(), seed_value, density)


func _region_hash(planner: PoiPlanner, center: WorldPos, radius: float) -> int:
	var instances := planner.plan_region(center, radius)
	var ids: Array[String] = []
	var by_id := {}
	for instance in instances:
		ids.append(String(instance.id))
		by_id[String(instance.id)] = instance
	ids.sort()
	var running := ids.size()
	for poi_id in ids:
		running = SeedHash.combine(running, by_id[poi_id].data_hash())
	return running


func _center() -> WorldPos:
	var planet := PlanetBody.new()
	var direction := Vector3(0.3, 0.5, 0.8).normalized()
	var ground := planet.surface_radius_xyz(direction.x, direction.y, direction.z)
	return WorldPos.new(&"planet", direction.x * ground, direction.y * ground, direction.z * ground)


func test_same_seed_gives_identical_pois_regardless_of_planning_order() -> void:
	var center := _center()
	var first := _planner()
	var second := _planner()
	second.plan_region(center.offset_by(Vector3(9000, 0, 0)), 8000.0) # plan other cells first
	assert_eq(_region_hash(first, center, 20000.0), _region_hash(second, center, 20000.0))
	assert_true(_region_hash(_planner(100), center, 20000.0) != _region_hash(first, center, 20000.0), "another seed differs")


func test_golden_poi_region_hash() -> void:
	# Recorded from this implementation (Godot 4.7.2, generation_version 1). If it changes, every POI
	# on every world moved: bump PoiPlanner.GENERATION_VERSION and re-record on purpose.
	assert_eq(_region_hash(_planner(), _center(), 20000.0), GOLDEN_REGION_HASH)


const GOLDEN_REGION_HASH := 2779771745


func test_pois_sit_on_the_terrain_and_have_sensible_spacing() -> void:
	var planner := _planner()
	var center := _center()
	var instances := planner.plan_region(center, 30000.0)
	assert_true(instances.size() > 10 and instances.size() < 120, "count in 30 km: %d" % instances.size())
	var types := {}
	for instance in instances:
		types[instance.type] = true
		assert_near(planner.planet.altitude_above_ground(instance.position), 0.0, 1e-6, "on the ground")
		assert_true(instance.display_name != "")
	assert_true(types.size() == 3, "all three types occur: %s" % str(types.keys()))


func test_ring_hysteresis_stops_flicker() -> void:
	var ring := PoiRings.update_ring(13000.0, PoiRings.Ring.NONE)
	assert_eq(ring, PoiRings.Ring.NONE)
	ring = PoiRings.update_ring(11990.0, ring)
	assert_eq(ring, PoiRings.Ring.PROXY)
	ring = PoiRings.update_ring(14000.0, ring)
	assert_eq(ring, PoiRings.Ring.PROXY, "between enter and exit distance it stays")
	ring = PoiRings.update_ring(15100.0, ring)
	assert_eq(ring, PoiRings.Ring.NONE)
	ring = PoiRings.update_ring(3000.0, ring)
	assert_eq(ring, PoiRings.Ring.CONTENT, "jumping straight to a close distance enters the content ring")
	ring = PoiRings.update_ring(5000.0, ring)
	assert_eq(ring, PoiRings.Ring.CONTENT)
	ring = PoiRings.update_ring(7000.0, ring)
	assert_eq(ring, PoiRings.Ring.PROXY)
	ring = PoiRings.update_ring(1000.0, ring)
	assert_eq(ring, PoiRings.Ring.DETAIL)


func test_five_hundred_planned_pois_but_only_ring_active_ones_have_nodes() -> void:
	var planner := _planner(7, 0.22)
	var center := _center()
	planner.plan_region(center, 115000.0)
	assert_true(planner.planned_count() >= 500, "planned %d" % planner.planned_count())
	var manager := PoiManager.new(planner)
	manager.render_origin = center.duplicate_position()
	var worst_content := 0
	var worst_markers := 0
	var up := Vector3(center.x, center.y, center.z).normalized()
	var side := up.cross(Vector3.RIGHT).normalized()
	for step in 40:
		var probe := center.offset_by(side * (step * 2500.0))
		var surface := planner.planet.surface_radius_xyz(probe.x / planner.planet.distance_from_center(probe), probe.y / planner.planet.distance_from_center(probe), probe.z / planner.planet.distance_from_center(probe))
		var distance := planner.planet.distance_from_center(probe)
		manager.viewer = WorldPos.new(&"planet", probe.x / distance * surface, probe.y / distance * surface, probe.z / distance * surface)
		manager.update_now()
		worst_content = maxi(worst_content, manager.content_node_count())
		worst_markers = maxi(worst_markers, manager.marker_node_count())
	assert_true(worst_content <= 30, "content nodes %d" % worst_content)
	assert_true(worst_markers <= 30, "markers %d" % worst_markers)
	assert_true(worst_content + worst_markers > 0, "the walk did pass some POIs")
	manager.free()


func test_discovery_fires_once_per_poi_and_only_on_foot_and_close() -> void:
	var planet := PlanetBody.new()
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	var center := _center()
	ship.state.position = WorldPos.new(planet.frame_id, center.x * (1.0 + 2.1 / planet.distance_from_center(center)), center.y * (1.0 + 2.1 / planet.distance_from_center(center)), center.z * (1.0 + 2.1 / planet.distance_from_center(center)))
	ship.state.basis = Basis.looking_at(Vector3.UP.cross(Vector3(center.x, center.y, center.z).normalized()).normalized(), Vector3(center.x, center.y, center.z).normalized())
	var session := GameSession.new(planet, ship, PilotSource.new())
	for tick in 120:
		session.tick(DELTA, OnFootCommand.new())
	var near_instance := PoiInstance.new()
	near_instance.id = &"poi_test_near"
	near_instance.display_name = "Wreck 00-001"
	var far_instance := PoiInstance.new()
	far_instance.id = &"poi_test_far"
	far_instance.display_name = "Beacon 00-002"
	var discoveries: Array[StringName] = []
	session.discovery_log.poi_discovered.connect(func(instance): discoveries.append(instance.id))

	session.interact() # stand up inside the ship
	near_instance.position = ShipFrame.world_from_local(ship.state, Vector3(0, 0, 0))
	session.check_discovery([near_instance])
	assert_eq(discoveries.size(), 0, "not discovered from inside the ship")

	session.exterior_body.place_on_ground(planet, ship.state.position.offset_by(ship.state.basis.x * 12.0), Vector3(0, 0, 1))
	session.restore_mode(GameSession.Mode.OUTSIDE)
	near_instance.position = session.exterior_body.position.offset_by(Vector3(0, 0, 0) + ship.state.basis.z * 60.0)
	far_instance.position = session.exterior_body.position.offset_by(ship.state.basis.z * 500.0)
	session.check_discovery([near_instance, far_instance])
	assert_eq(discoveries, [&"poi_test_near"] as Array[StringName], "only the close one, within 120 m")
	session.check_discovery([near_instance, far_instance])
	session.check_discovery([near_instance, far_instance])
	assert_eq(discoveries.size(), 1, "fires once")
	assert_eq(session.discovery_log.count(), 1)
	ship.free()


func test_walker_cannot_walk_into_a_prop_blocker() -> void:
	var planet := PlanetBody.new()
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	var center := _center()
	var ship_distance := planet.distance_from_center(center) + 2.1
	var direction := Vector3(center.x, center.y, center.z).normalized()
	ship.state.position = WorldPos.new(planet.frame_id, direction.x * ship_distance, direction.y * ship_distance, direction.z * ship_distance)
	ship.state.basis = Basis.looking_at(Vector3.UP.cross(direction).normalized(), direction)
	var session := GameSession.new(planet, ship, PilotSource.new())
	var beacon := PoiInstance.new()
	beacon.id = &"poi_blocker_test"
	beacon.type = PoiDefinition.Type.BEACON
	beacon.seed_value = 5
	var beacon_ground := planet.surface_radius_xyz(direction.x, direction.y, direction.z)
	beacon.position = WorldPos.new(planet.frame_id, direction.x * beacon_ground, direction.y * beacon_ground, direction.z * beacon_ground).offset_by(ship.state.basis.x * 30.0)
	var distance := planet.distance_from_center(beacon.position)
	var beacon_direction := Vector3(beacon.position.x, beacon.position.y, beacon.position.z) / distance
	beacon.position = WorldPos.new(planet.frame_id, beacon_direction.x * planet.surface_radius_xyz(beacon_direction.x, beacon_direction.y, beacon_direction.z), beacon_direction.y * planet.surface_radius_xyz(beacon_direction.x, beacon_direction.y, beacon_direction.z), beacon_direction.z * planet.surface_radius_xyz(beacon_direction.x, beacon_direction.y, beacon_direction.z))
	session.exterior_body.place_on_ground(planet, beacon.position.offset_by(ship.state.basis.x * -20.0), ship.state.basis.x)
	session.restore_mode(GameSession.Mode.OUTSIDE)
	var closest := INF
	var walk := OnFootCommand.new()
	walk.move = Vector2(0, 1)
	for tick in 600:
		session.exterior_body.heading = (beacon.position.vector_from(session.exterior_body.position))
		session.exterior_body.heading = (session.exterior_body.heading - planet.up_at(session.exterior_body.position) * session.exterior_body.heading.dot(planet.up_at(session.exterior_body.position))).normalized()
		session.exterior_body.step(walk, planet, DELTA)
		session.apply_poi_blockers([beacon])
		closest = minf(closest, session.exterior_body.position.distance_to(beacon.position))
	assert_true(closest >= 3.6 - 0.2, "walker stopped %f m from the beacon centre (base radius 3.6)" % closest)
	assert_true(closest < 6.0, "and did walk up to it: %f" % closest)
	ship.free()


func test_threaded_manager_merges_the_same_pois_as_the_synchronous_one() -> void:
	var center := _center()
	var sync_manager := PoiManager.new(_planner(7))
	sync_manager.render_origin = center.duplicate_position()
	sync_manager.viewer = center
	sync_manager.update_now()
	var threaded_manager := PoiManager.new(_planner(7))
	threaded_manager.threaded = true
	threaded_manager.render_origin = center.duplicate_position()
	threaded_manager.viewer = center
	threaded_manager.update_now() # starts the job
	var tries := 0
	while threaded_manager._job_task != -1 and tries < 4000:
		OS.delay_msec(5)
		threaded_manager.update_now()
		tries += 1
	threaded_manager.update_now()
	assert_true(sync_manager.known_instances().size() > 0, "the region holds POIs")
	assert_eq(threaded_manager.known_instances().size(), sync_manager.known_instances().size(), "same POIs once the job lands")
	threaded_manager._exit_tree()
	sync_manager.free()
	threaded_manager.free()
