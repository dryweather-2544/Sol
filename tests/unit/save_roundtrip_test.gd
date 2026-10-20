extends "res://tests/test_case.gd"
## Save -> file -> load into a fresh session -> capture again, in the five states the milestone names.
## Positions must match to 1 cm, velocity and door/walkway states exactly (to float round-trip).

const DELTA := 1.0 / 60.0
const SAVE_DIRECTORY := "user://test_saves_roundtrip"


func _new_session(altitude_above_ground: float, velocity: Vector3) -> GameSession:
	var planet := PlanetBody.new()
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	var direction := Vector3(0.3, 0.5, 0.8).normalized()
	var ground := planet.surface_radius_xyz(direction.x, direction.y, direction.z)
	var radius := ground + altitude_above_ground
	ship.state.position = WorldPos.new(planet.frame_id, direction.x * radius, direction.y * radius, direction.z * radius)
	ship.state.basis = Basis.looking_at(Vector3.UP.cross(direction).normalized(), direction)
	ship.state.velocity = velocity
	return GameSession.new(planet, ship, PilotSource.new())


func _landed_session() -> GameSession:
	var session := _new_session(2.1, Vector3.ZERO)
	for tick in 120:
		session.tick(DELTA, OnFootCommand.new())
	return session


func _states() -> Dictionary:
	var states := {}
	var in_space := _new_session(300000.0, Vector3(30, -20, 100))
	in_space.ship.state.angular_velocity = Vector3(0.1, 0.2, 0.3)
	in_space.ship.state.gear = 1
	in_space.ship.state.selected_gear = 2 # cruise chosen, combat in effect (as with an empty tank)
	states["piloting_in_space"] = in_space
	states["landed_seated"] = _landed_session()
	var inside := _landed_session()
	inside.interact()
	inside.interior_body.place(Vector3(0.6, -0.9, 1.4), 1.2)
	states["inside_standing"] = inside
	var outside := _landed_session()
	outside.interact()
	outside.exterior_body.place_on_ground(outside.planet, outside.ship.state.position.offset_by(outside.ship.state.basis.x * 12.0), Vector3(0, 0, 1))
	outside.restore_mode(GameSession.Mode.OUTSIDE)
	states["outside_on_foot"] = outside
	var mid_airlock := _landed_session()
	mid_airlock.interact()
	mid_airlock.interior_body.place(Vector3(0.0, -0.9, 4.7), 3.1)
	mid_airlock.systems.airlock.outer.target_open = true
	mid_airlock.systems.airlock.outer.open_factor = 0.4
	mid_airlock.systems.walkway.state = WalkwayController.State.DEPLOYING
	mid_airlock.systems.walkway.progress = 0.3
	mid_airlock.systems.layout.ramp_end_y = -2.3
	(mid_airlock.systems.layout.portals[&"cockpit_door"] as Portal).target_open = true
	(mid_airlock.systems.layout.portals[&"cockpit_door"] as Portal).open_factor = 1.0
	states["mid_airlock"] = mid_airlock
	return states


func _round_trip(session: GameSession, slot: String) -> Dictionary:
	var manager := SaveManager.new(SAVE_DIRECTORY)
	assert_eq(manager.save(slot, SaveGame.capture(session, 42)), "", "save " + slot)
	var loaded := manager.load_slot(slot)
	assert_true(loaded["ok"], "load %s: %s" % [slot, loaded["error"]])
	var fresh := _new_session(5000.0, Vector3(1, 2, 3))
	assert_eq(SaveGame.restore(fresh, loaded["data"]), "")
	return {"original": session, "restored": fresh}


func test_all_five_states_round_trip() -> void:
	var states := _states()
	for state_name in states:
		var pair := _round_trip(states[state_name], state_name)
		var original: GameSession = pair["original"]
		var restored: GameSession = pair["restored"]
		var label: String = state_name
		assert_true(restored.ship.state.position.distance_to(original.ship.state.position) < 0.01, label + ": ship position")
		assert_true(restored.ship.state.velocity.distance_to(original.ship.state.velocity) < 1e-4, label + ": ship velocity")
		assert_true(Quaternion(restored.ship.state.basis).dot(Quaternion(original.ship.state.basis)) > 0.999999, label + ": orientation")
		assert_true(restored.ship.state.angular_velocity.distance_to(original.ship.state.angular_velocity) < 1e-4, label + ": angular velocity")
		assert_eq(restored.ship.state.gear, original.ship.state.gear, label + ": gear")
		assert_eq(restored.ship.state.selected_gear, original.ship.state.selected_gear, label + ": selected gear")
		assert_eq(restored.ship.state.landed, original.ship.state.landed, label + ": landed")
		assert_eq(restored.mode, original.mode, label + ": mode")
		assert_eq(restored.player_state.authority, original.player_state.authority, label + ": authority")
		assert_eq(restored.player_state.posture, original.player_state.posture, label + ": posture")
		if original.mode == GameSession.Mode.INSIDE:
			assert_true(restored.interior_body.position.distance_to(original.interior_body.position) < 1e-4, label + ": interior position")
			assert_near(restored.interior_body.yaw, original.interior_body.yaw, 1e-6, label + ": interior yaw")
		for portal_id in original.systems.layout.portals:
			var original_portal: Portal = original.systems.layout.portals[portal_id]
			var restored_portal: Portal = restored.systems.layout.portals[portal_id]
			assert_eq(restored_portal.target_open, original_portal.target_open, "%s: %s target" % [label, portal_id])
			assert_near(restored_portal.open_factor, original_portal.open_factor, 1e-9, "%s: %s factor" % [label, portal_id])
		assert_eq(restored.systems.walkway.state, original.systems.walkway.state, label + ": walkway state")
		assert_near(restored.systems.walkway.progress, original.systems.walkway.progress, 1e-9, label + ": walkway progress")
		assert_eq(restored.ship.controller.is_parked(), original.ship.controller.is_parked(), label + ": pilot control")
		if original.mode == GameSession.Mode.OUTSIDE:
			assert_true(restored.exterior_body.position.distance_to(original.exterior_body.position) < 0.01, label + ": walker position")
		assert_eq(restored.validate(), "", label + ": restored state is legal")
		original.ship.free()
		restored.ship.free()


func test_restored_session_keeps_running_without_a_jump() -> void:
	var original := _landed_session()
	var pair := _round_trip(original, "continue")
	var restored: GameSession = pair["restored"]
	var before := restored.ship.state.position.duplicate_position()
	for tick in 120:
		restored.tick(DELTA, OnFootCommand.new())
	assert_true(restored.ship.state.landed, "still landed after loading")
	assert_true(restored.ship.state.position.distance_to(before) < 0.05, "ship did not move")
	assert_eq(restored.validate(), "")
	original.ship.free()
	restored.ship.free()


func test_hull_and_suit_survive_a_save() -> void:
	var original := _landed_session()
	original.ship.state.hull = 0.37
	original.suit.oxygen = 0.42
	original.suit.fuel = 0.11
	original.suit.health = 0.8
	var pair := _round_trip(original, "survival")
	var restored: GameSession = pair["restored"]
	assert_near(restored.ship.state.hull, 0.37, 1e-9)
	assert_near(restored.suit.oxygen, 0.42, 1e-9)
	assert_near(restored.suit.fuel, 0.11, 1e-9)
	assert_near(restored.suit.health, 0.8, 1e-9)
	original.ship.free()
	restored.ship.free()


func test_warp_gear_survives_a_save_round_trip() -> void:
	var original := _new_session(300000.0, Vector3(0, 0, -100))
	original.ship.state.gear = PilotCommand.GEAR_WARP
	original.ship.state.selected_gear = PilotCommand.GEAR_WARP
	var pair := _round_trip(original, "warp_gear")
	var restored: GameSession = pair["restored"]
	assert_eq(restored.ship.state.gear, PilotCommand.GEAR_WARP, "warp gear is saved")
	assert_eq(restored.ship.state.selected_gear, PilotCommand.GEAR_WARP, "warp selection is saved")
	original.ship.free()
	restored.ship.free()
