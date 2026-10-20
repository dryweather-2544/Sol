extends "res://tests/test_case.gd"


func test_compute_shift_only_beyond_threshold() -> void:
	assert_eq(FloatingOrigin.compute_shift(Vector3(1000, 0, 0), 1024.0), Vector3.ZERO)
	assert_eq(FloatingOrigin.compute_shift(Vector3(0, 0, -2000), 1024.0), Vector3(0, 0, -2000))


func test_fifty_km_flight_rebases_often_and_never_jumps() -> void:
	var ship := Ship.new()
	var floating_origin := FloatingOrigin.new()
	floating_origin.anchor = ship
	var commands: Array[PilotCommand] = []
	for tick in 4500:
		var command := PilotCommand.new()
		command.move_lock = 1.0 # scripted pilot: holds the velocity it asks for (Rodina AI mover MoveLock)
		command.stop_rotation = true # and holds its attitude (Rodina AI sets its turn rate directly)
		command.thrust = Vector3(0, 0, -1)
		command.gear = PilotCommand.GEAR_COMBAT
		command.boost = true
		commands.append(command)
	ship.controller.request_control(ScriptedPilotSource.new(commands), &"pilot_seat")
	var previous_world := ship.state.position.duplicate_position()
	var worst_world_step := 0.0
	var worst_local_distance := 0.0
	for tick in 4500:
		ship.simulate_tick(1.0 / 60.0)
		floating_origin.update()
		var world_step := ship.state.position.distance_to(previous_world)
		worst_world_step = maxf(worst_world_step, world_step)
		previous_world = ship.state.position.duplicate_position()
		var local_from_state := ship.state.position.to_local_vector3(ship.render_origin)
		assert_near(ship.position.distance_to(local_from_state), 0.0, 1e-3, "render position must match WorldPos")
		worst_local_distance = maxf(worst_local_distance, ship.position.length())
	var travelled := ship.state.position.distance_to(WorldPos.new(&"space"))
	assert_true(travelled > 50000.0, "flew at least 50 km, got %.0f" % travelled)
	assert_true(floating_origin.rebase_count >= 40, "rebased %d times" % floating_origin.rebase_count)
	assert_true(worst_world_step <= 750.0 / 60.0 + 1e-3, "no jump bigger than one tick of motion: %f" % worst_world_step)
	assert_true(worst_local_distance < 1024.0 + 20.0, "ship stays near render origin: %f" % worst_local_distance)
	floating_origin.free()
	ship.free()


func test_chase_camera_recomputes_its_transform_after_an_origin_rebase() -> void:
	# The camera is reset after the ship moves, not before: otherwise the renderer keeps one
	# pre-rebase camera sample and draws the ship at the edge of / behind the camera for a frame.
	var ship := Ship.new()
	var camera := ChaseCamera.new()
	camera.target = ship
	ship.position = Vector3(1200.0, 0.0, 0.0)
	camera.snap_to_target()
	ship.position = Vector3.ZERO
	camera.apply_origin_shift(Vector3(1200.0, 0.0, 0.0))
	var expected := ship.position + Basis.IDENTITY * camera.offset_behind_up
	assert_near(camera.position.distance_to(expected), 0.0, 1e-5, "camera follows the rebased ship immediately")
	camera.free()
	ship.free()
