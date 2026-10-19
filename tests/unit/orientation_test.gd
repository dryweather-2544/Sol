extends "res://tests/test_case.gd"
## Camera orientation regression: the chase camera must sit on the ship's centreline and keep
## the ship's right axis aligned. Before the fix this camera was offset 3.8 m sideways, which
## made a level ship read as if it were flying sideways.

func _camera_for(basis: Basis) -> ChaseCamera:
	var tree := Engine.get_main_loop() as SceneTree
	var ship := Ship.new()
	tree.root.add_child(ship)
	ship.state.basis = basis
	ship._sync_transform()
	ship.force_update_transform()
	var camera := ChaseCamera.new()
	tree.root.add_child(camera)
	camera.target = ship
	camera._apply_basis(basis)
	return camera


func test_chase_camera_is_centred_behind_the_ship() -> void:
	var basis := Basis.IDENTITY
	var camera := _camera_for(basis)
	var relative := camera.position
	assert_near(relative.dot(basis.x), 0.0, 0.001, "no lateral camera offset")
	assert_true(relative.dot(basis.z) > 0.0, "camera is behind the ship (+Z in Sol's local frame)")
	assert_true(relative.dot(basis.y) > 0.0, "camera is above the ship")
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.remove_child(camera)
	tree.root.remove_child(camera.target)
	camera.target.free()
	camera.free()


func test_camera_right_matches_ship_right_at_yaw_and_roll() -> void:
	for angle in [0.35, PI * 0.5, PI, -0.7]:
		var basis := Basis(Vector3.UP, angle) * Basis(Vector3(0.0, 0.0, 1.0), 0.4)
		var camera := _camera_for(basis)
		assert_true(camera.basis.x.dot(basis.x) > 0.999, "camera right must follow ship right at yaw %f" % angle)
		assert_true(camera.position.dot(basis.x) < 0.001, "camera must stay on the centreline at yaw %f" % angle)
		var tree := Engine.get_main_loop() as SceneTree
		tree.root.remove_child(camera)
		tree.root.remove_child(camera.target)
		camera.target.free()
		camera.free()
