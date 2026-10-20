extends "res://tests/test_case.gd"
## The deployed ramp is a surface to walk on, not a direction trigger: walking along it, across it and diagonally
## over it follows the input; entering or leaving it never changes the heading, and the walker never jumps.
## Coordinates are ship-local (x right, y up, -z forward); the ramp runs aft from the outer door (z 10.8 to 15).

const DELTA := 1.0 / 60.0
## Largest sideways change of ship-local position allowed in one tick: run speed is 8 m/s, so 0.14 m per tick at most.
const MAX_STEP_PER_TICK := 0.2
## A foot steps up onto the ramp (GameSession.RAMP_STEP_UP) or down onto lower ground (OnFootBody.STEP_DOWN_DISTANCE)
## in one tick, as on any terrain; anything larger is a jump.
const MAX_STEP_HEIGHT := OnFootBody.STEP_DOWN_DISTANCE + 0.05


class HoldPilot extends PilotSource:
	func _init() -> void:
		source_id = &"ramp_test"


var _session: GameSession
var _previous := Vector3.ZERO
var _worst_step := 0.0


## A landed ship on the default planet with the outer door open and the walkway deployed; the player standing inside.
func _landed_session() -> void:
	var planet := PlanetBody.new()
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	var direction := Vector3(0.3, 0.5, 0.8).normalized()
	var ground := planet.surface_radius_xyz(direction.x, direction.y, direction.z)
	ship.state.position = WorldPos.new(planet.frame_id, direction.x * (ground + 2.2), direction.y * (ground + 2.2), direction.z * (ground + 2.2))
	ship.state.basis = Basis.looking_at(Vector3.UP.cross(direction).normalized(), direction)
	_session = GameSession.new(planet, ship, HoldPilot.new())
	for tick in 60 * 10:
		_session.tick(DELTA, OnFootCommand.new())
		if ship.state.landed and ship.state.speed() < 0.01:
			break
	assert_true(ship.state.landed, "ship landed for the ramp test")
	_session.interact() # stand up
	assert_eq(_session.mode, GameSession.Mode.INSIDE, "standing inside")
	# Open the outer door from its panel, as a player does (that also fits the ramp's end to the ground).
	_session.interior_body.place(Vector3(1.2, _session.systems.layout.floor_y, 10.0), PI)
	_session.interact()
	assert_true(_session.systems.airlock.outer.target_open, "outer door opening (%s)" % _session.message)
	for tick in 60 * 4:
		_session.tick(DELTA, OnFootCommand.new())
	assert_true(_session.systems.walkway.is_deployed(), "walkway deployed")
	_previous = _local_feet()
	_worst_step = 0.0


func _local_feet() -> Vector3:
	return ShipFrame.local_from_world(_session.ship.state, _session.player_world_position())


## Ship-local horizontal heading of whichever body is walking (unit, x/z).
func _local_heading() -> Vector2:
	if _session.mode == GameSession.Mode.INSIDE:
		var forward := _session.interior_body.forward()
		return Vector2(forward.x, forward.z)
	var local := _session.ship.state.basis.transposed() * _session.exterior_body.heading
	return Vector2(local.x, local.z).normalized()


func _tick(move: Vector2) -> void:
	var command := OnFootCommand.new()
	command.move = move
	_session.tick(DELTA, command)
	var now := _local_feet()
	var horizontal := Vector2(now.x - _previous.x, now.z - _previous.z).length()
	var vertical := absf(now.y - _previous.y)
	if OS.get_environment("RAMP_DEBUG") != "" and (horizontal > MAX_STEP_PER_TICK or vertical > MAX_STEP_HEIGHT):
		print("RAMP_DEBUG jump %.3f / %.3f from %s to %s mode %d" % [horizontal, vertical, _previous, now, _session.mode])
	# Sideways jumps count fully; a vertical step only counts beyond what a foot steps up or down in one go.
	_worst_step = maxf(_worst_step, horizontal if vertical <= MAX_STEP_HEIGHT else vertical)
	_previous = now


## The walker's own "right" (planet-level, as the input means it), as a ship-local (x, z) direction.
func _local_right() -> Vector2:
	var up := _session.planet.up_at(_session.exterior_body.position)
	var right := _session.ship.state.basis.transposed() * _session.exterior_body.heading.cross(up)
	return Vector2(right.x, right.z).normalized()


## Puts the player inside at ship-local (0, z) facing aft (a test setup move, not counted as a step).
func _place_inside(z: float) -> void:
	_session.interior_body.place(Vector3(0.0, _session.systems.layout.floor_height_at(0.0, z), z), PI)
	_previous = _local_feet()
	_worst_step = 0.0


## Puts the player outside, standing on the ground at ship-local (x, z), facing a ship-local direction.
func _stand_outside(x: float, z: float, facing_local: Vector3) -> void:
	_place_inside(10.0)
	for tick in 60 * 3:
		if _session.mode == GameSession.Mode.OUTSIDE:
			break
		_tick(Vector2(0, 1)) # step off the ramp end to get outside the legal way
	assert_eq(_session.mode, GameSession.Mode.OUTSIDE, "outside")
	var world := ShipFrame.world_from_local(_session.ship.state, Vector3(x, 0.0, z))
	_session.exterior_body.place_on_ground(_session.planet, world, _session.ship.state.basis * facing_local)
	_previous = _local_feet()
	_worst_step = 0.0


func test_walking_down_and_back_up_the_ramp_along_its_length() -> void:
	_landed_session()
	_place_inside(10.0) # in the airlock, facing aft
	var heading_before := _local_heading()
	for tick in 60 * 3:
		_tick(Vector2(0, 1))
	assert_eq(_session.mode, GameSession.Mode.OUTSIDE, "walked down the ramp and off it")
	assert_true(_local_feet().z > 15.0, "past the ramp end: z %.2f" % _local_feet().z)
	assert_true(_local_heading().dot(heading_before) > 0.9999, "heading unchanged by the ramp: %s vs %s" % [_local_heading(), heading_before])
	for tick in 60 * 4:
		_tick(Vector2(0, -1)) # walk backwards, up the ramp
		if _session.mode == GameSession.Mode.INSIDE:
			break
	assert_eq(_session.mode, GameSession.Mode.INSIDE, "walked backwards up the ramp and in")
	assert_true(_local_heading().dot(heading_before) > 0.9999, "heading still unchanged")
	assert_true(_worst_step < MAX_STEP_PER_TICK, "no jumps: worst step %.3f m" % _worst_step)


## Walks from the airlock down onto the ramp and stops with the feet at ship-local z (on the ramp, outside).
func _walk_onto_ramp_to(z: float) -> void:
	_place_inside(10.0)
	for tick in 60 * 3:
		if _local_feet().z >= z:
			break
		_tick(Vector2(0, 1))
	for tick in 30:
		_tick(Vector2.ZERO) # come to a stop
	assert_eq(_session.mode, GameSession.Mode.OUTSIDE, "on the ramp, outside the hull")
	var layout := _session.systems.layout
	assert_near(_local_feet().y, layout.floor_height_at(_local_feet().x, _local_feet().z), 0.05, "standing on the ramp surface")


func test_strafing_across_the_ramp_goes_straight_and_steps_off_its_edge() -> void:
	_landed_session()
	_walk_onto_ramp_to(12.6)
	var start := _local_feet()
	var heading_before := _local_heading()
	var right := _local_right()
	# Facing aft (+z), "right" is about -x.
	for tick in 60 * 2:
		_tick(Vector2(1, 0))
	var feet := _local_feet()
	assert_eq(_session.mode, GameSession.Mode.OUTSIDE, "still outside")
	assert_true(feet.x < -2.5, "strafed across and off the ramp's edge: x %.2f" % feet.x)
	var travelled := Vector2(feet.x - start.x, feet.z - start.z)
	assert_true(travelled.normalized().dot(right) > 0.9995, "straight to the walker's right, no drift along the ramp: %s vs %s" % [travelled.normalized(), right])
	assert_true(feet.y < start.y - 0.3, "dropped from the ramp to the ground: %.2f -> %.2f" % [start.y, feet.y])
	assert_true(_local_heading().dot(heading_before) > 0.9999, "heading unchanged")
	assert_true(_worst_step < MAX_STEP_PER_TICK, "no jumps: worst step %.3f m" % _worst_step)


func test_walking_diagonally_on_the_ramp_keeps_its_direction() -> void:
	_landed_session()
	_walk_onto_ramp_to(12.0)
	var start := _local_feet()
	for tick in 45:
		_tick(Vector2(0.7071, 0.7071)) # forward-right while facing aft: toward (-x, +z)
	var travelled := Vector2(_local_feet().x - start.x, _local_feet().z - start.z)
	assert_true(travelled.length() > 2.0, "moved: %.2f m" % travelled.length())
	assert_true(travelled.normalized().dot(Vector2(-1, 1).normalized()) > 0.995, "went where pushed: %s" % travelled.normalized())
	assert_true(_worst_step < MAX_STEP_PER_TICK, "no jumps: worst step %.3f m" % _worst_step)


func test_crossing_the_low_end_of_the_ramp_from_the_ground() -> void:
	_landed_session()
	var layout := _session.systems.layout
	# Near the foot the ramp is within a step of the ground: walk straight over it, side to side.
	_stand_outside(-2.5, layout.ramp_rect.end.y - 0.3, Vector3(0, 0, -1)) # facing the ship, so "right" is +x
	var start := _local_feet()
	var heading_before := _local_heading()
	var right := _local_right()
	for tick in 60 * 2:
		_tick(Vector2(1, 0))
	var feet := _local_feet()
	assert_eq(_session.mode, GameSession.Mode.OUTSIDE, "crossing does not pull the player into the ship")
	assert_true(feet.x > 2.0, "crossed to the other side: x %.2f" % feet.x)
	var travelled := Vector2(feet.x - start.x, feet.z - start.z)
	assert_true(travelled.normalized().dot(right) > 0.9995, "straight to the walker's right, no drift along the ramp: %s vs %s" % [travelled.normalized(), right])
	assert_true(_local_heading().dot(heading_before) > 0.9999, "heading unchanged")
	assert_true(_worst_step < MAX_STEP_PER_TICK, "no jumps: worst step %.3f m" % _worst_step)
	assert_true(_worst_step < MAX_STEP_PER_TICK, "no jumps: worst step %.3f m" % _worst_step)


func test_standing_still_on_the_ramp_stays_put() -> void:
	_landed_session()
	_place_inside(10.0)
	for tick in 60:
		_tick(Vector2(0, 1))
	for tick in 60: # let go and come to a stop
		_tick(Vector2.ZERO)
	var rest := _local_feet()
	for tick in 120:
		_tick(Vector2.ZERO)
	assert_true(_local_feet().distance_to(rest) < 0.01, "no creep on the ramp: %.3f m" % _local_feet().distance_to(rest))


func test_ramp_surface_carries_the_walker_and_its_sides_are_solid() -> void:
	_landed_session()
	_place_inside(10.0)
	for tick in 60:
		_tick(Vector2(0, 1))
	# Half way down the ramp the walker stands on its surface, not on the ground under it.
	var layout := _session.systems.layout
	var feet := _local_feet()
	if feet.z > layout.ramp_rect.position.y and feet.z < layout.ramp_rect.end.y:
		assert_near(feet.y, layout.floor_height_at(0.0, feet.z), 0.05, "on the ramp surface at z %.2f" % feet.z)
	# From the ground, the high end of the ramp (near the door) is a wall, not a step.
	_stand_outside(-2.5, 11.6, Vector3(1, 0, 0))
	for tick in 60 * 2:
		_tick(Vector2(0, 1))
	assert_true(_local_feet().x < -0.9, "blocked by the ramp's side where it is high: x %.2f" % _local_feet().x)
	assert_eq(_session.mode, GameSession.Mode.OUTSIDE)
