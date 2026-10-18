extends "res://tests/test_case.gd"


func test_two_actors_one_seat_exactly_one_wins() -> void:
	var seats := SeatManager.new([&"pilot_seat"])
	var first := seats.try_sit(&"alice", &"pilot_seat")
	var second := seats.try_sit(&"bob", &"pilot_seat")
	assert_true(first and not second, "exactly one succeeds")
	seats.update(SeatManager.SIT_SECONDS + 0.1)
	assert_eq(seats.occupant_of(&"pilot_seat"), &"alice")
	assert_true(not seats.try_sit(&"bob", &"pilot_seat"), "still taken once occupied")
	assert_true(seats.stand(&"alice"))
	assert_true(seats.try_sit(&"bob", &"pilot_seat"), "free after standing")


func test_cancel_mid_sit_frees_the_seat_and_no_occupancy_event_fires() -> void:
	var seats := SeatManager.new([&"pilot_seat"])
	var events: Array = []
	seats.seat_occupied.connect(func(seat_id, actor_id): events.append([seat_id, actor_id]))
	seats.try_sit(&"alice", &"pilot_seat")
	seats.update(SeatManager.SIT_SECONDS * 0.5)
	assert_true(not seats.is_seated(&"alice"), "still sitting down")
	assert_true(seats.cancel_sit(&"alice"))
	seats.update(SeatManager.SIT_SECONDS)
	assert_eq(seats.state_of(&"pilot_seat"), SeatManager.SeatState.FREE)
	assert_true(events.is_empty(), "cancelled sit never occupies")
	assert_true(seats.try_sit(&"bob", &"pilot_seat"))


func test_one_actor_cannot_hold_two_seats_and_cannot_cancel_after_seated() -> void:
	var seats := SeatManager.new([&"pilot_seat", &"co_pilot_seat"])
	assert_true(seats.try_sit(&"alice", &"pilot_seat"))
	assert_true(not seats.try_sit(&"alice", &"co_pilot_seat"))
	seats.update(1.0)
	assert_true(not seats.cancel_sit(&"alice"), "cancel only works while sitting down")
	assert_true(seats.is_seated(&"alice"))
