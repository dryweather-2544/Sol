extends "res://tests/test_case.gd"

const DELTA := 1.0 / 60.0


func _walk(body: InteriorBody, layout: InteriorLayout, move: Vector2, ticks: int) -> void:
	var command := OnFootCommand.new()
	command.move = move
	for tick in ticks:
		body.step(command, layout, DELTA)


func test_closed_door_blocks_and_open_door_lets_you_through() -> void:
	var layout := InteriorLayout.player_ship()
	var door: Portal = layout.portals[&"cockpit_door"]
	var body := InteriorBody.new()
	body.place(Vector3(0, layout.floor_y, -4.4), PI) # facing +z toward the cabin door... yaw PI faces +z
	_walk(body, layout, Vector2(0, 1), 120)
	assert_true(body.position.z < -3.6, "closed door stops the walker: z=%f" % body.position.z)
	door.target_open = true
	for tick in 60:
		door.update(DELTA)
	_walk(body, layout, Vector2(0, 1), 120)
	assert_true(body.position.z > -3.0, "open door lets the walker into the cabin: z=%f" % body.position.z)


func test_walkers_stay_inside_the_rooms_and_slide_along_walls() -> void:
	var layout := InteriorLayout.player_ship()
	var body := InteriorBody.new()
	body.place(Vector3(0, layout.floor_y, 0), 0.0)
	_walk(body, layout, Vector2(1, 0), 300) # strafe right into the side wall
	assert_true(body.position.x <= 3.0 - InteriorBody.RADIUS + 1e-3, "stopped by the wall: x=%f" % body.position.x)
	assert_near(body.position.y, layout.floor_y, 1e-6)


func test_ramp_is_only_walkable_when_deployed_and_slopes_down() -> void:
	var layout := InteriorLayout.player_ship()
	var ramp_x := 0.0
	var ramp_z := layout.ramp_rect.position.y + 1.0
	assert_true(not layout.is_position_walkable(ramp_x, ramp_z, InteriorBody.RADIUS), "stowed")
	layout.ramp_walkable = true
	assert_true(layout.is_position_walkable(ramp_x, ramp_z, InteriorBody.RADIUS), "deployed")
	layout.ramp_end_y = -2.0
	assert_near(layout.floor_height_at(0.0, layout.ramp_rect.position.y), layout.floor_y, 1e-6)
	assert_near(layout.floor_height_at(0.0, layout.ramp_rect.end.y - 0.001), -2.0, 1e-2)
	assert_true(layout.floor_height_at(0.0, layout.ramp_rect.position.y + 2.0) < layout.floor_y)


func test_nearest_interaction_picks_the_closest_panel() -> void:
	var layout := InteriorLayout.player_ship()
	assert_eq(layout.nearest_interaction(Vector3(0, layout.floor_y, -5.0)), &"pilot_seat")
	assert_eq(layout.nearest_interaction(Vector3(1.2, layout.floor_y, 4.2)), &"airlock_inner")
	assert_eq(layout.nearest_interaction(Vector3(1.2, layout.floor_y, 5.2)), &"airlock_outer")
	assert_eq(layout.nearest_interaction(Vector3(0, layout.floor_y, 0.0)), &"")


func test_exterior_walker_is_pushed_out_of_the_hull_but_not_off_the_ramp() -> void:
	var layout := InteriorLayout.player_ship()
	var inside_hull := Vector3(1.0, -2.0, 0.0) # standing under the cabin
	var pushed := ShipHullCollision.push_out(inside_hull, 0.4, layout.ramp_rect, false)
	assert_true(absf(pushed.x) >= ShipHullCollision.HULL_HALF_WIDTH, "moved out through the nearest side")
	var on_ramp := Vector3(0.0, -2.0, layout.ramp_rect.position.y + 1.0)
	assert_eq(ShipHullCollision.push_out(on_ramp, 0.4, layout.ramp_rect, true), on_ramp, "ramp mouth is open when deployed")
