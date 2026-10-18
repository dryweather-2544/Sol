extends "res://tests/test_case.gd"

const TICK := 1.0 / 60.0


func _full_draw() -> ShipPower:
	var power := ShipPower.new()
	for conduit in 3:
		power.set_request(conduit, ShipPower.MAX_OUTPUT)
	return power


func test_delivered_power_never_exceeds_request_limit_or_output() -> void:
	var rng := SeedRng.new(11)
	var power := ShipPower.new()
	for case_index in 1000:
		for conduit in 3:
			power.set_limit(conduit, rng.next_float() * 1.2 - 0.1)
			power.set_request(conduit, rng.next_float() * 150.0 - 10.0)
		power.update(rng.next_float())
		if rng.next_float() < 0.05:
			power.request_restart()
		for conduit in 3:
			var delivered := power.delivered(conduit)
			assert_true(delivered >= 0.0, "case %d conduit %d negative" % [case_index, conduit])
			assert_true(delivered <= power.limit(conduit) * power.output() + 1e-6, "case %d conduit %d over its limit" % [case_index, conduit])
		assert_true(power.total_delivered() <= power.output() + 1e-6, "case %d total over output" % case_index)


func test_over_draw_heats_monotonically_until_safety_shutdown() -> void:
	var power := _full_draw()
	var previous := power.temperature
	var ticks := 0
	while not power.is_shut_down() and ticks < 60 * 600:
		power.update(TICK)
		assert_true(power.temperature >= previous, "temperature fell at tick %d under constant over-draw" % ticks)
		previous = power.temperature
		ticks += 1
	assert_true(power.is_shut_down(), "reactor shut down within 10 minutes of full draw")
	assert_true(ticks > 60 * 30, "but not instantly (%d ticks)" % ticks)


func test_coolant_lowers_temperature_and_runs_out() -> void:
	var power := ShipPower.new()
	power.temperature = 0.9
	assert_eq(power.vent_coolant(), "")
	assert_near(power.temperature, 0.9 - ShipPower.HEAT_REMOVED_PER_VENT, 1e-9)
	for vent in 3:
		power.vent_coolant()
	assert_near(power.coolant, 0.0, 1e-9)
	assert_eq(power.vent_coolant(), "No coolant left")
	assert_eq(power.temperature, 0.0, "never below cold")


func test_light_draw_cools_the_core() -> void:
	var power := ShipPower.new()
	power.temperature = 0.5
	for tick in 600:
		power.update(TICK)
	assert_true(power.temperature < 0.5, "idle ship (life support only) cools: %f" % power.temperature)


func test_shutdown_zeroes_output_and_restart_waits_for_cooling() -> void:
	var power := _full_draw()
	power.temperature = 0.999
	power.update(1.0)
	assert_true(power.is_shut_down())
	assert_eq(power.output(), 0.0)
	assert_eq(power.total_delivered(), 0.0)
	assert_eq(power.request_restart(), "Core too hot to restart")
	while power.temperature >= ShipPower.RESTART_BELOW_TEMPERATURE:
		power.update(TICK)
	assert_eq(power.request_restart(), "")
	assert_true(not power.is_shut_down())
	assert_true(power.total_delivered() > 0.0, "power flows again after restart")
	assert_eq(power.request_restart(), "Reactor is already running")


func test_limits_cap_a_conduit_and_shortfall_is_shared() -> void:
	var power := ShipPower.new()
	power.set_request(ShipPower.Conduit.ENGINES, 80.0)
	power.set_request(ShipPower.Conduit.LIFE_SUPPORT, 0.0)
	power.set_limit(ShipPower.Conduit.ENGINES, 0.5)
	assert_near(power.delivered(ShipPower.Conduit.ENGINES), 50.0, 1e-9, "limit caps engines")
	power.set_limit(ShipPower.Conduit.ENGINES, 1.0)
	power.set_request(ShipPower.Conduit.WEAPONS, 80.0)
	assert_near(power.delivered(ShipPower.Conduit.ENGINES), 50.0, 1e-9, "160 wanted from 100: each gets the same fraction")
	assert_near(power.delivered(ShipPower.Conduit.WEAPONS), 50.0, 1e-9)


func test_same_inputs_give_the_same_state_after_ten_thousand_ticks() -> void:
	var first := ShipPower.new()
	var second := ShipPower.new()
	var rng_first := SeedRng.new(23)
	var rng_second := SeedRng.new(23)
	for tick in 10000:
		_random_step(first, rng_first)
		_random_step(second, rng_second)
	assert_eq(first.temperature, second.temperature)
	assert_eq(first.coolant, second.coolant)
	assert_eq(first.is_shut_down(), second.is_shut_down())
	for conduit in 3:
		assert_eq(first.delivered(conduit), second.delivered(conduit))


func _random_step(power: ShipPower, rng: SeedRng) -> void:
	match rng.next_int_in_range(0, 9):
		0: power.set_limit(rng.next_int_in_range(0, 2), rng.next_float())
		1: power.set_request(rng.next_int_in_range(0, 2), rng.next_float() * 100.0)
		2: power.vent_coolant()
		3: power.request_restart()
	power.update(TICK)
