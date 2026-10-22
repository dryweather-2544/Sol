extends "res://tests/test_case.gd"


func _session() -> GameSession:
	var planet := PlanetBody.new()
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	return GameSession.new(planet, ship, PilotSource.new())


func test_every_machine_has_a_readout() -> void:
	var session := _session()
	var menu := MachineMenu.new()
	menu.session = session
	for kind in MachineMenu.TITLES:
		assert_true(menu.body_text(kind) != "", "%s shows something" % kind)
	assert_true(menu.body_text(&"ops_computer").contains("Ship health: 100%"), "ops shows the hull")
	assert_true(menu.body_text(&"limnal_drive").contains("OFFLINE"), "the drive is offline until the Warp coil is fitted")
	session.progress.warp_installed = true
	assert_true(menu.body_text(&"limnal_drive").contains("READY"), "and ready once it is")
	menu.free()
	session.ship.free()


func test_emergency_doors_open_and_close_plain_doors_but_not_the_airlock() -> void:
	var session := _session()
	var menu := MachineMenu.new()
	menu.session = session
	menu.set_all_doors(true)
	assert_true((session.systems.layout.portals[&"cockpit_door"] as Portal).target_open, "plain doors open")
	assert_true(not (session.systems.layout.portals[&"airlock_outer"] as Portal).target_open, "the airlock outer door is left to its rules")
	menu.set_all_doors(false)
	assert_true(not (session.systems.layout.portals[&"cockpit_door"] as Portal).target_open, "plain doors close")
	menu.free()
	session.ship.free()

