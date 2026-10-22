extends "res://tests/test_case.gd"
## The invisible ship interior (2f9b74e): a near plane of 0.05 m with a far plane of 4,000 km makes Godot's float32 projection
## degenerate, and frustum culling drops every mesh. CameraRange keeps every camera's planes usable.


func test_the_2f9b74e_planes_are_degenerate_and_the_clamped_ones_are_not() -> void:
	assert_true(not CameraRange.is_safe(0.05, 4.0e6), "near 0.05 m / far 4,000 km: the far plane collapses (the bug)")
	assert_true(CameraRange.is_safe(0.05, 40000.0), "near 0.05 m / far 40 km is fine")
	for far in [40000.0, 3.0e5, 8.5e5, 4.0e6, 3.0e7]:
		var near := CameraRange.near_for(far, 0.05, 0.25)
		var safe_far := CameraRange.clamp_far(near, far)
		assert_true(CameraRange.is_safe(near, safe_far), "walking camera planes %.3f / %.0f" % [near, safe_far])
		assert_true(near <= 0.25 + 0.0001, "the walking camera's near plane stays inside a person's radius")
	for near in [0.3, 0.5, 2.0]:
		for far in [2.0e4, 4.0e6, 3.0e7]:
			assert_true(CameraRange.is_safe(near, CameraRange.clamp_far(near, far)), "flight camera planes %.1f / %.0f" % [near, far])


func test_cameras_start_with_safe_planes() -> void:
	var cockpit := CockpitCamera.new()
	var view := InteriorView.new()
	for camera: Camera3D in [cockpit, view.camera]:
		assert_true(CameraRange.is_safe(camera.near, camera.far), "%s starts with %.2f / %.0f" % [camera.name, camera.near, camera.far])
	cockpit.free()
	view.free()
