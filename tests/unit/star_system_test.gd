extends "res://tests/test_case.gd"


func _system() -> StarSystem:
	return StarSystem.default_system()


func test_orbits_are_circular_periodic_and_deterministic() -> void:
	var system := _system()
	var body: BodyDef = system.bodies[&"planet"]
	var star_distance_at_zero := system.body_position(&"planet", 0.0)
	assert_near(sqrt(star_distance_at_zero.x * star_distance_at_zero.x + star_distance_at_zero.z * star_distance_at_zero.z), body.orbit_radius, 1e-3)
	var later := system.body_position(&"planet", 1.234e6)
	assert_near(sqrt(later.x * later.x + later.y * later.y + later.z * later.z), body.orbit_radius, 1e-3, "radius constant over time")
	var one_period_on := system.body_position(&"planet", body.orbit_period)
	assert_near(one_period_on.x, star_distance_at_zero.x, 1e-2, "back where it started after one period")
	assert_near(one_period_on.z, star_distance_at_zero.z, 1e-2)
	assert_near(_system().body_position(&"verdant", 5.5e5).x, system.body_position(&"verdant", 5.5e5).x, 0.0, "two instances agree")


func test_moon_orbits_its_planet_not_the_star() -> void:
	var system := _system()
	for time_seconds in [0.0, 2.0e5, 7.7e5]:
		var planet := system.body_position(&"planet", time_seconds)
		var moon := system.body_position(&"selene", time_seconds)
		var separation := sqrt(pow(moon.x - planet.x, 2.0) + pow(moon.y - planet.y, 2.0) + pow(moon.z - planet.z, 2.0))
		assert_near(separation, 1.0e8, 1e-2)


func test_velocity_is_the_derivative_of_position() -> void:
	var system := _system()
	for body_id in [&"planet", &"selene", &"cinder"]:
		var time_seconds := 3.3e5
		var step := 1.0
		var before := system.body_position(body_id, time_seconds - step)
		var after := system.body_position(body_id, time_seconds + step)
		var velocity := system.body_velocity(body_id, time_seconds)
		assert_near(velocity.x, (after.x - before.x) / (2.0 * step), 1e-2, "%s vx" % body_id)
		assert_near(velocity.z, (after.z - before.z) / (2.0 * step), 1e-2, "%s vz" % body_id)


func test_position_conversion_round_trips_between_frames() -> void:
	var system := _system()
	var original := WorldPos.new(&"planet", 1234567.891, -2345678.123, 6100000.456)
	var time_seconds := 8.8e5
	var in_system := system.convert_position(original, StarSystem.SYSTEM_FRAME, time_seconds)
	var in_moon := system.convert_position(in_system, &"selene", time_seconds)
	var back := system.convert_position(in_moon, &"planet", time_seconds)
	assert_true(back.is_approximately_equal(original, 1e-3), "round trip error %f" % back.distance_to(original))
	assert_true(in_system.x != original.x, "frames really differ")


func test_velocity_conversion_is_galilean() -> void:
	var system := _system()
	var velocity := Vector3(10, 20, 30)
	var there := system.convert_velocity(velocity, &"planet", &"selene", 1.0e5)
	var back := system.convert_velocity(there, &"selene", &"planet", 1.0e5)
	assert_true(back.distance_to(velocity) < 1e-3)
	var in_system := system.convert_velocity(Vector3.ZERO, &"planet", StarSystem.SYSTEM_FRAME, 1.0e5)
	var planet_velocity := system.body_velocity(&"planet", 1.0e5)
	assert_near(in_system.x, planet_velocity.x, 1e-3, "sitting still on a planet moves with it")


func test_frame_selection_uses_sphere_of_influence_with_hysteresis() -> void:
	var system := _system()
	var time_seconds := 0.0
	var planet_center := system.body_position(&"planet", time_seconds)
	var radius: float = (system.bodies[&"planet"] as BodyDef).radius
	var near_planet := WorldPos.new(StarSystem.SYSTEM_FRAME, planet_center.x + radius * 9.0, planet_center.y, planet_center.z)
	assert_eq(system.frame_for(near_planet, time_seconds, StarSystem.SYSTEM_FRAME), &"planet")
	var edge := WorldPos.new(StarSystem.SYSTEM_FRAME, planet_center.x + radius * 11.0, planet_center.y, planet_center.z)
	assert_eq(system.frame_for(edge, time_seconds, StarSystem.SYSTEM_FRAME), StarSystem.SYSTEM_FRAME, "outside 10 R: system frame")
	assert_eq(system.frame_for(edge, time_seconds, &"planet"), &"planet", "already inside: stays until 12 R")
	var far := WorldPos.new(StarSystem.SYSTEM_FRAME, planet_center.x + radius * 13.0, planet_center.y, planet_center.z)
	assert_eq(system.frame_for(far, time_seconds, &"planet"), StarSystem.SYSTEM_FRAME)
	var moon_center := system.body_position(&"selene", time_seconds)
	var near_moon := WorldPos.new(StarSystem.SYSTEM_FRAME, moon_center.x + 3.0e6, moon_center.y, moon_center.z)
	assert_eq(system.frame_for(near_moon, time_seconds, StarSystem.SYSTEM_FRAME), &"selene")


func test_planet_bodies_carry_each_worlds_own_numbers() -> void:
	var system := _system()
	var moon := system.build_planet_body(&"selene")
	assert_eq(moon.atmosphere_height, 100000.0, "Selene has Morena's cold air")
	assert_eq(moon.frame_id, &"selene")
	assert_near(moon.radius, 1.7e6, 1e-6)
	var rock := system.build_planet_body(&"pebble")
	assert_true(rock.atmosphere_ratio(WorldPos.new(&"pebble", 0.0, 0.0, rock.radius + 100.0)) == INF, "airless world has no atmosphere")
	var home := system.build_planet_body(&"planet")
	assert_near(home.surface_gravity, 12.0, 1e-9)
	for body_id in system.bodies:
		var body: BodyDef = system.bodies[body_id]
		if not body.is_star:
			assert_near(body.terrain_profile.radius, body.radius, 1e-6, "%s terrain radius matches body radius" % body_id)
			var heights_differ: bool = system.build_planet_body(body_id).terrain_height_xyz(0.3, 0.5, 0.8) != home.terrain_height_xyz(0.3, 0.5, 0.8) or body_id == &"planet"
			assert_true(heights_differ, "%s has its own terrain" % body_id)
