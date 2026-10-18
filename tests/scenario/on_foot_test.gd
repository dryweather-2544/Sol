extends "res://tests/test_case.gd"
## Walking on the real terrain: stays upright and on the ground, jumps land where predicted,
## slopes beyond the limit block.

const DELTA := 1.0 / 60.0


func _body_standing_at(planet: PlanetBody, direction: Vector3) -> OnFootBody:
	var body := OnFootBody.new()
	var start := WorldPos.new(planet.frame_id, direction.x * planet.radius, direction.y * planet.radius, direction.z * planet.radius)
	body.place_on_ground(planet, start, Vector3.UP.cross(direction))
	return body


func _forward(run: bool = false) -> OnFootCommand:
	var command := OnFootCommand.new()
	command.move = Vector2(0, 1)
	command.run = run
	return command


func test_two_km_walk_stays_on_the_ground_and_upright() -> void:
	var planet := PlanetBody.new()
	var body := _body_standing_at(planet, Vector3(0.3, 0.5, 0.8).normalized())
	var start := body.position.duplicate_position()
	var command := _forward(true)
	var worst_height := 0.0
	var worst_tilt_degrees := 0.0
	var ticks := 0
	while body.position.distance_to(start) < 2000.0 and ticks < 60 * 600:
		body.step(command, planet, DELTA)
		ticks += 1
		worst_height = maxf(worst_height, body.height_above_ground)
		var up := planet.up_at(body.position)
		assert_true(planet.altitude_above_ground(body.position) >= -1e-6, "fell below the terrain")
		worst_tilt_degrees = maxf(worst_tilt_degrees, rad_to_deg(acos(clampf(body.heading.dot(up), -1.0, 1.0))) - 90.0)
	assert_true(body.position.distance_to(start) >= 2000.0, "gave up after %d ticks (blocked?)" % ticks)
	assert_true(worst_height < 2.0, "never leaves the ground much: %f" % worst_height)
	assert_true(absf(worst_tilt_degrees) < 0.01, "heading stays in the tangent plane: %f" % worst_tilt_degrees)


func test_walking_speed_is_the_configured_speed_on_flat_ground() -> void:
	var planet := PlanetBody.new()
	planet.height_override = func(_dx: float, _dy: float, _dz: float) -> float: return 0.0
	var body := _body_standing_at(planet, Vector3(0, 0, 1))
	var start := body.position.duplicate_position()
	for tick in 120:
		body.step(_forward(), planet, DELTA)
	assert_near(body.velocity.length(), OnFootBody.WALK_SPEED, 1e-6)
	assert_near(body.position.distance_to(start), OnFootBody.WALK_SPEED * 2.0 - 0.5 * 0.1, 0.15, "about 4 m/s for 2 s minus the ramp-up")


func test_jump_lands_where_a_ballistic_prediction_says() -> void:
	var planet := PlanetBody.new()
	planet.height_override = func(_dx: float, _dy: float, _dz: float) -> float: return 0.0
	var body := _body_standing_at(planet, Vector3(0, 0, 1))
	for tick in 60:
		body.step(_forward(), planet, DELTA) # reach full walking speed first
	var jump_start := body.position.duplicate_position()
	var forward_speed := body.velocity.length()
	var jump := _forward()
	jump.jump = true
	body.step(jump, planet, DELTA)
	assert_true(not body.grounded, "left the ground")
	var airborne_ticks := 1
	while not body.grounded and airborne_ticks < 600:
		body.step(_forward(), planet, DELTA)
		airborne_ticks += 1
	var gravity := planet.surface_gravity
	var predicted_air_time := 2.0 * OnFootBody.JUMP_SPEED / gravity
	assert_near(airborne_ticks * DELTA, predicted_air_time, 2.0 * DELTA, "flight time")
	var predicted_distance := forward_speed * predicted_air_time
	assert_near(body.position.distance_to(jump_start), predicted_distance, 0.05, "landing point within 5 cm of prediction (to the tick)")


func test_steep_slope_blocks_walking_and_gentle_slope_does_not() -> void:
	for case_data in [[30.0, true], [60.0, false]]:
		var planet := PlanetBody.new()
		var slope_degrees: float = case_data[0]
		var should_walk: bool = case_data[1]
		var slope := tan(deg_to_rad(slope_degrees))
		var planet_radius := planet.radius
		planet.height_override = func(dx: float, _dy: float, _dz: float) -> float: return slope * dx * planet_radius
		var body := OnFootBody.new()
		body.place_on_ground(planet, WorldPos.new(planet.frame_id, 0.0, 0.0, planet_radius), Vector3(1, 0, 0)) # walk uphill (+x rises)
		for tick in 180:
			body.step(_forward(), planet, DELTA)
		if should_walk:
			assert_true(body.position.x > 4.0, "%d degrees should be walkable, moved %f" % [int(slope_degrees), body.position.x])
		else:
			assert_true(body.position.x < 0.5 and body.blocked_by_slope, "%d degrees should block, moved %f" % [int(slope_degrees), body.position.x])


func test_walking_off_a_ledge_makes_you_fall_and_land() -> void:
	var planet := PlanetBody.new()
	var planet_radius := planet.radius
	planet.height_override = func(dx: float, _dy: float, _dz: float) -> float: return 0.0 if dx * planet_radius < 5.0 else -10.0
	var body := OnFootBody.new()
	body.place_on_ground(planet, WorldPos.new(planet.frame_id, 0.0, 0.0, planet_radius), Vector3(1, 0, 0))
	var left_ground := false
	for tick in 600:
		body.step(_forward(), planet, DELTA)
		left_ground = left_ground or not body.grounded
	assert_true(left_ground, "fell off the ledge")
	assert_true(body.grounded, "and landed on the lower ground")
