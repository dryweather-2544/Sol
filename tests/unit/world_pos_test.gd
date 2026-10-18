extends "res://tests/test_case.gd"

const WorldPosScript := preload("res://src/core/world_pos.gd")


func test_far_position_keeps_millimetre_precision() -> void:
	var near_surface = WorldPosScript.new(&"planet_a", 6000000.0, 0.0, 0.0)
	var one_millimetre_away = near_surface.offset_by(Vector3(0.001, 0.0, 0.0))
	assert_near(one_millimetre_away.x - near_surface.x, 0.001, 1e-6)
	assert_near(one_millimetre_away.distance_to(near_surface), 0.001, 1e-6)


func test_to_local_vector3_is_small_and_accurate() -> void:
	var origin = WorldPosScript.new(&"planet_a", 6000000.0, 10.0, -20.0)
	var point = origin.offset_by(Vector3(1.5, 2.5, 3.5))
	var local_vector: Vector3 = point.to_local_vector3(origin)
	assert_near(local_vector.x, 1.5, 1e-4)
	assert_near(local_vector.y, 2.5, 1e-4)
	assert_near(local_vector.z, 3.5, 1e-4)


func test_different_frames_never_compare_equal() -> void:
	var first = WorldPosScript.new(&"planet_a", 1.0, 2.0, 3.0)
	var second = WorldPosScript.new(&"planet_b", 1.0, 2.0, 3.0)
	assert_true(not first.is_approximately_equal(second))


func test_dictionary_round_trip() -> void:
	var original = WorldPosScript.new(&"planet_a", 6000000.123456, -1234.5, 0.000001)
	var restored = WorldPosScript.from_dictionary(original.to_dictionary())
	assert_eq(restored.frame_id, &"planet_a")
	assert_eq(restored.x, original.x)
	assert_eq(restored.y, original.y)
	assert_eq(restored.z, original.z)
