extends "res://tests/test_case.gd"
## Flying into a star hurts: nothing far out, a steep ramp near the surface, and certain death inside it.


func test_no_heat_beyond_one_radius_above_the_surface() -> void:
	assert_near(ShipDamage.star_heat_rate(2.0e9, 1.0e9), 0.0, 1e-9)
	assert_near(ShipDamage.star_heat_rate(5.0e9, 1.0e9), 0.0, 1e-9)


func test_heat_grows_towards_the_surface() -> void:
	var far := ShipDamage.star_heat_rate(1.8e9, 1.0e9)
	var mid := ShipDamage.star_heat_rate(1.5e9, 1.0e9)
	var close := ShipDamage.star_heat_rate(1.1e9, 1.0e9)
	assert_true(far > 0.0 and mid > far and close > mid, "heat rises as the ship closes in")
	assert_true(ShipDamage.star_heat_rate(1.0001e9, 1.0e9) > 0.5, "skimming the surface burns the hull in a couple of seconds")


func test_inside_the_star_is_certain_death() -> void:
	var rate := ShipDamage.star_heat_rate(0.5e9, 1.0e9)
	assert_true(rate >= 5.0, "inside the star the hull is gone in well under a second")


func test_ship_destroyed_by_heat() -> void:
	var ship := Ship.new()
	var destroyed := [false]
	ship.destroyed.connect(func(): destroyed[0] = true)
	ship.apply_heat(0.4)
	assert_near(ship.state.hull, 0.6, 1e-4)
	assert_true(not destroyed[0])
	ship.apply_heat(1.0)
	assert_near(ship.state.hull, 0.0, 1e-6)
	assert_true(destroyed[0], "the ship is lost when the heat takes the hull to zero")
	ship.free()
