extends "res://tests/test_case.gd"


func _landed_slow_ship() -> ShipState:
	var ship_state := ShipState.new()
	ship_state.landed = true
	return ship_state


func test_ten_thousand_random_requests_never_open_both_doors() -> void:
	var rng := SeedRng.new(7)
	var airlock := AirlockController.new(Portal.new(&"inner", Portal.Kind.AIRLOCK_INNER, Rect2()), Portal.new(&"outer", Portal.Kind.AIRLOCK_OUTER, Rect2()))
	var ship_state := _landed_slow_ship()
	var accepted_open_requests := 0
	for step in 10000:
		match rng.next_int_in_range(0, 6):
			0: accepted_open_requests += 1 if airlock.request_open_inner() == AirlockController.Result.OK else 0
			1: accepted_open_requests += 1 if airlock.request_open_outer(ship_state) == AirlockController.Result.OK else 0
			2: airlock.request_close_inner(false)
			3: airlock.request_close_outer(false)
			4: ship_state.landed = rng.next_float() < 0.7
		airlock.update(rng.next_float() * 0.5)
		assert_true(airlock.is_invariant_ok(), "both doors open at step %d" % step)
	assert_true(accepted_open_requests > 100, "the fuzz actually opened doors: %d" % accepted_open_requests)


func test_other_door_is_refused_until_first_is_closed_and_cycled() -> void:
	var airlock := AirlockController.new(Portal.new(&"inner", Portal.Kind.AIRLOCK_INNER, Rect2()), Portal.new(&"outer", Portal.Kind.AIRLOCK_OUTER, Rect2()))
	var ship_state := _landed_slow_ship()
	assert_eq(airlock.request_open_inner(), AirlockController.Result.OK)
	assert_eq(airlock.request_open_outer(ship_state), AirlockController.Result.BLOCKED_OTHER_DOOR_OPEN)
	airlock.update(1.0)
	assert_eq(airlock.request_close_inner(false), AirlockController.Result.OK)
	airlock.update(0.3)
	assert_eq(airlock.request_open_outer(ship_state), AirlockController.Result.BLOCKED_OTHER_DOOR_OPEN, "inner still closing")
	airlock.update(1.0)
	assert_eq(airlock.request_open_outer(ship_state), AirlockController.Result.BLOCKED_CYCLING, "pressure cycle")
	airlock.update(AirlockController.CYCLE_SECONDS)
	assert_eq(airlock.request_open_outer(ship_state), AirlockController.Result.OK)


func test_outer_door_refused_when_not_landed_or_fast_and_closing_refused_when_occupied() -> void:
	var airlock := AirlockController.new(Portal.new(&"inner", Portal.Kind.AIRLOCK_INNER, Rect2()), Portal.new(&"outer", Portal.Kind.AIRLOCK_OUTER, Rect2()))
	var flying := ShipState.new()
	assert_eq(airlock.request_open_outer(flying), AirlockController.Result.BLOCKED_NOT_LANDED)
	var sliding := _landed_slow_ship()
	sliding.velocity = Vector3(3, 0, 0)
	assert_eq(airlock.request_open_outer(sliding), AirlockController.Result.BLOCKED_MOVING)
	airlock.request_open_inner()
	assert_eq(airlock.request_close_inner(true), AirlockController.Result.BLOCKED_OCCUPIED)
	assert_true(airlock.inner.target_open, "occupied doorway keeps the door open")
