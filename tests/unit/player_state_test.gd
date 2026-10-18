extends "res://tests/test_case.gd"


func test_full_cycle_stand_walk_out_in_sit() -> void:
	var player := PlayerState.new()
	assert_true(player.try_stand_up().ok())
	assert_true(player.authority == PlayerState.Authority.NONE and player.posture == PlayerState.Posture.STANDING)
	assert_true(player.try_go_outside().ok())
	assert_true(player.location == PlayerState.Location.EXTERIOR)
	assert_true(not player.try_begin_sit().ok(), "cannot sit while outside")
	assert_true(player.try_go_inside().ok())
	assert_true(player.try_begin_sit().ok())
	assert_true(player.posture == PlayerState.Posture.SITTING_DOWN and player.authority == PlayerState.Authority.NONE, "no control until seated")
	assert_true(player.try_finish_sit().ok())
	assert_true(player.authority == PlayerState.Authority.PILOT and player.is_legal())


func test_cancel_sit_returns_to_standing_with_no_authority() -> void:
	var player := PlayerState.new()
	player.try_stand_up()
	player.try_begin_sit()
	assert_true(player.try_cancel_sit().ok())
	assert_true(player.posture == PlayerState.Posture.STANDING and player.authority == PlayerState.Authority.NONE)


func test_illegal_transitions_are_refused_without_changing_state() -> void:
	var player := PlayerState.new() # seated pilot inside
	assert_true(not player.try_go_outside().ok(), "cannot walk out while seated")
	assert_true(not player.try_begin_sit().ok(), "already seated")
	assert_true(not player.try_finish_sit().ok())
	assert_true(player.posture == PlayerState.Posture.SEATED and player.authority == PlayerState.Authority.PILOT and player.is_legal())
