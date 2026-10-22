extends "res://tests/test_case.gd"
## The player's gunner station: an AI flies, the player aims the roof gun inside its arc and it heats up.

const DELTA := 1.0 / 60.0


func _session() -> GameSession:
	var planet := PlanetBody.new()
	planet.height_override = func(_dx: float, _dy: float, _dz: float) -> float: return 0.0
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	ship.state.position = WorldPos.new(planet.frame_id, 0.0, 0.0, planet.radius + 2.1)
	ship.state.basis = Basis(Vector3.RIGHT, PI / 2.0)
	var session := GameSession.new(planet, ship, PilotSource.new())
	for tick in 120:
		session.tick(DELTA, OnFootCommand.new())
	return session


func test_aim_pitch_is_clamped_and_yaw_wraps() -> void:
	var turret := ShipTurret.new()
	turret.add_aim(Vector2(0.0, -100000.0))
	assert_eq(turret.aim_pitch, ShipTurret.PITCH_MAX)
	turret.add_aim(Vector2(0.0, 100000.0))
	assert_eq(turret.aim_pitch, ShipTurret.PITCH_MIN)
	turret.add_aim(Vector2(100000.0, 0.0))
	assert_true(absf(turret.aim_yaw) <= PI, "yaw stays wrapped")
	assert_true(absf(turret.manual_direction().length() - 1.0) < 0.001, "direction is a unit vector")


func test_station_hands_the_ship_to_an_ai_and_back() -> void:
	var session := _session()
	assert_true(session.ship.controller.current_source == session.pilot_source)
	session.toggle_gunner_station()
	assert_true(session.gunner_station)
	assert_true(session.ship.controller.current_source == session.gunner_ai)
	assert_eq(session.validate(), "")
	session.toggle_gunner_station()
	assert_true(not session.gunner_station)
	assert_true(session.ship.controller.current_source == session.pilot_source)


func test_holding_the_trigger_overheats_then_cools() -> void:
	var session := _session()
	session.toggle_gunner_station()
	session.gunner_trigger = true
	for tick in 600:
		session.tick(DELTA, OnFootCommand.new())
		if session.systems.turret.overheated:
			break
	assert_true(session.systems.turret.overheated, "ten seconds of fire overheats the gun")
	session.gunner_trigger = false
	for tick in 600:
		session.tick(DELTA, OnFootCommand.new())
	assert_true(not session.systems.turret.overheated, "it cooled off")
