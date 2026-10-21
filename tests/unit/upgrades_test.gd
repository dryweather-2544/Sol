extends "res://tests/test_case.gd"

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


func test_buying_spends_the_cost_once_and_refuses_when_short() -> void:
	var session := _session()
	assert_true(session.buy_upgrade(&"hull_plating").contains("Need"), "no scrap yet")
	session.inventory.slot_limit = 20
	session.inventory.add(ItemDefinition.SCRAP, 60)
	session.inventory.add(ItemDefinition.DATA_CHIP, 3)
	assert_eq(session.buy_upgrade(&"hull_plating"), "")
	assert_eq(session.inventory.count(ItemDefinition.SCRAP), 40)
	assert_eq(session.buy_upgrade(&"hull_plating"), "Already installed")
	assert_eq(session.inventory.count(ItemDefinition.SCRAP), 40, "not charged twice")
	assert_eq(session.buy_upgrade(&"gun_amplifier"), "")
	assert_eq(session.inventory.count(ItemDefinition.DATA_CHIP), 1)
	assert_true(session.buy_upgrade(&"efficient_engines") == "" and session.buy_upgrade(&"suit_tank").contains("Need"), "chips run out")
	session.ship.free()


func test_each_upgrade_changes_its_number() -> void:
	var session := _session()
	session.inventory.slot_limit = 40
	session.inventory.add(ItemDefinition.SCRAP, 200)
	session.inventory.add(ItemDefinition.DATA_CHIP, 20)
	# damage
	var plain := ShipDamage.impact_damage(500.0)
	var before_hull := session.ship.state.hull
	session.ship.state.last_impact_speed = 500.0
	session.ship._take_damage(DELTA)
	assert_near(before_hull - session.ship.state.hull, plain, 1e-9)
	session.ship.state.hull = 1.0
	session.buy_upgrade(&"hull_plating")
	session.ship.state.impact_damage_cooldown = 0.0
	session.ship.state.last_impact_speed = 500.0
	session.ship._take_damage(DELTA)
	assert_near(1.0 - session.ship.state.hull, plain * 0.7, 1e-9, "30% less damage")
	# fuel
	session.buy_upgrade(&"efficient_engines")
	var burn := PilotCommand.new()
	burn.thrust = Vector3(0, 0, -1)
	burn.boost = true
	session.ship.state.fuel = 1.0
	session.ship._burn_fuel(burn, 1.0)
	assert_near(1.0 - session.ship.state.fuel, Ship.FUEL_BOOST_PER_SECOND * 0.6, 1e-9)
	# oxygen
	session.buy_upgrade(&"suit_tank")
	session.suit.oxygen = 1.0
	session.suit.update(18.0, false, false, true)
	assert_near(session.suit.oxygen, 1.0 - 18.0 / (SuitState.OXYGEN_SECONDS * 1.6), 1e-9)
	# guns
	session.buy_upgrade(&"gun_amplifier")
	session.ship.projectiles = session.projectiles
	var fire := PilotCommand.new()
	fire.fire = true
	session.ship._fire_weapon(fire, DELTA)
	assert_near(session.projectiles.projectiles[-1].damage, session.ship.weapon.damage * 1.5, 1e-9)
	assert_near(session.ship.weapon.damage, Weapon.ship_gun().damage, 1e-9, "base damage is left unchanged")
	session.ship.free()


func test_upgrades_survive_a_save() -> void:
	var session := _session()
	session.inventory.slot_limit = 40
	session.inventory.add(ItemDefinition.SCRAP, 50)
	session.inventory.add(ItemDefinition.DATA_CHIP, 3)
	session.buy_upgrade(&"suit_tank")
	session.buy_upgrade(&"hull_plating")
	var data := SaveGame.capture(session, 42)
	var fresh := _session()
	assert_eq(SaveGame.restore(fresh, data), "")
	assert_true(fresh.ship.upgrades.has(&"suit_tank") and fresh.ship.upgrades.has(&"hull_plating"))
	assert_near(fresh.suit.oxygen_duration_multiplier, 1.6, 1e-9, "suit multiplier restored too")
	session.ship.free()
	fresh.ship.free()
