extends "res://tests/test_case.gd"
## The engine pods vector with the thrust (ShipExterior.pod_angle_for): level for forward, upright for up, all the way
## round for reverse, nozzle-up for down, level with no demand.


func test_pods_follow_the_thrust_direction() -> void:
	assert_near(ShipExterior.pod_angle_for(Vector3.ZERO), 0.0, 1e-9, "no demand: level")
	assert_near(ShipExterior.pod_angle_for(Vector3(0, 0, -1)), 0.0, 1e-9, "forward: level, nozzles aft")
	assert_near(ShipExterior.pod_angle_for(Vector3(0, 1, 0)), PI * 0.5, 1e-6, "up: upright, nozzles down")
	assert_near(ShipExterior.pod_angle_for(Vector3(0, 0, 1)), PI, 1e-6, "reverse: all the way round, nozzles forward")
	assert_near(ShipExterior.pod_angle_for(Vector3(0, -1, 0)), -PI * 0.5, 1e-6, "down: nozzles straight up")
	assert_true(ShipExterior.pod_angle_for(Vector3(0, 0, 1)) <= ShipExterior.POD_TILT_MAX + 1e-9)


func test_demands_turn_the_pods_fully_and_strafing_does_not_tilt() -> void:
	assert_near(ShipExterior.pod_angle_for(Vector3(0, 0.5, 0)), PI * 0.5, 1e-6, "any real demand turns them the whole way")
	assert_true(ShipExterior.pod_angle_for(Vector3(0, 0.02, 0)) < PI * 0.5, "only a hair of demand blends in")
	assert_near(ShipExterior.pod_angle_for(Vector3(1, 0, 0)), 0.0, 1e-9, "strafing leaves the pods level")
