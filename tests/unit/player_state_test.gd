extends "res://tests/test_case.gd"


func _landed_ship_state() -> ShipState:
	var ship_state := ShipState.new()
	ship_state.landed = true
	return ship_state


func test_cannot_exit_while_flying_or_moving() -> void:
	var player := PlayerState.new()
	var flying := ShipState.new()
	var outcome := player.try_exit_ship(flying)
	assert_eq(outcome.result, PlayerState.Result.BLOCKED_NOT_LANDED)
	assert_true(player.authority == PlayerState.Authority.PILOT, "failed exit must not change state")
	var sliding := _landed_ship_state()
	sliding.velocity = Vector3(5, 0, 0)
	assert_eq(player.try_exit_ship(sliding).result, PlayerState.Result.BLOCKED_MOVING)


func test_exit_then_board_round_trip() -> void:
	var player := PlayerState.new()
	var ship_state := _landed_ship_state()
	assert_true(player.try_exit_ship(ship_state).ok())
	assert_true(player.posture == PlayerState.Posture.STANDING and player.authority == PlayerState.Authority.NONE and player.location == PlayerState.Location.EXTERIOR)
	assert_eq(player.try_exit_ship(ship_state).result, PlayerState.Result.BLOCKED_AUTHORITY, "cannot exit twice")
	assert_eq(player.try_board_ship(50.0, ship_state).result, PlayerState.Result.BLOCKED_TOO_FAR)
	assert_true(player.try_board_ship(5.0, ship_state).ok())
	assert_true(player.posture == PlayerState.Posture.SEATED and player.authority == PlayerState.Authority.PILOT)
	assert_eq(player.try_board_ship(1.0, ship_state).result, PlayerState.Result.BLOCKED_AUTHORITY, "already piloting")
