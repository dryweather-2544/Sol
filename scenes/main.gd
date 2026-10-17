extends Node3D
## Boot scene: one planet, one ship in orbit, chase camera, overlay. The player starts in the
## pilot seat; when landed, F steps out (M2 debug exit, replaced by airlock/seat in M3) and F
## near the ship climbs back in.

const START_ALTITUDE := 300000.0
const START_SUN_ANGLE_DEGREES := 50.0
const EXIT_SIDE_OFFSET := 8.0

var ship: Ship
var planet: PlanetBody
var terrain: PlanetTerrain
var space_environment: SpaceEnvironment
var player_source := PlayerPilotSource.new()
var player_state := PlayerState.new()
var on_foot: OnFootController
var camera: ChaseCamera
var floating_origin: FloatingOrigin
var overlay: DebugOverlay
var _message := ""
var _message_seconds_left := 0.0


func _ready() -> void:
	planet = PlanetBody.new()
	space_environment = SpaceEnvironment.new()
	add_child(space_environment)

	# Start above a point where the sun is START_SUN_ANGLE_DEGREES from overhead, facing the planet.
	var toward_sun := -SpaceEnvironment.sun_direction()
	var tilt_axis := toward_sun.cross(Vector3.UP).normalized()
	var start_up := toward_sun.rotated(tilt_axis, deg_to_rad(START_SUN_ANGLE_DEGREES))
	ship = Ship.new()
	ship.planet = planet
	ship.state.position = WorldPos.new(planet.frame_id, start_up.x * (planet.radius + START_ALTITUDE), start_up.y * (planet.radius + START_ALTITUDE), start_up.z * (planet.radius + START_ALTITUDE))
	ship.state.basis = Basis.looking_at(-start_up, Vector3.UP) # nose toward the planet
	ship.render_origin = ship.state.position.duplicate_position()
	ship.position = Vector3.ZERO
	add_child(ship)

	terrain = PlanetTerrain.new(planet)
	terrain.render_origin = ship.render_origin.duplicate_position()
	terrain.viewer = ship.state.position
	add_child(terrain)

	on_foot = OnFootController.new()
	on_foot.planet = planet
	on_foot.render_origin = ship.render_origin.duplicate_position()
	add_child(on_foot)

	floating_origin = FloatingOrigin.new()
	floating_origin.anchor = ship
	add_child(floating_origin) # after the actors, so it runs after their physics ticks
	camera = ChaseCamera.new()
	camera.target = ship
	add_child(camera)
	camera.snap_to_target()
	camera.current = true
	overlay = DebugOverlay.new()
	overlay.ship = ship
	overlay.terrain = terrain
	add_child(overlay)
	ship.controller.request_control(player_source, &"pilot_seat")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_message_seconds_left = maxf(0.0, _message_seconds_left - delta)
	var actor_position := on_foot.body.position if on_foot.active else ship.state.position
	terrain.viewer = actor_position
	if not on_foot.active:
		# Near plane small enough for the ship (11 m ahead of the camera); far plane just past the
		# horizon. Keeping far/near moderate avoids depth-precision and light-culler problems.
		var altitude := maxf(ship.state.altitude_above_ground, 1.0)
		camera.near = clampf(altitude * 0.002, 0.3, 2.0)
		camera.far = clampf(sqrt(2.0 * planet.radius * altitude) * 2.0 + 5000.0, 20000.0, 3.0e7)
	var atmosphere_ratio := planet.atmosphere_ratio(actor_position)
	var daylight := 1.0 - smoothstep(0.0, 1.0, atmosphere_ratio)
	var sun_above_horizon := smoothstep(-0.1, 0.3, planet.up_at(actor_position).dot(-SpaceEnvironment.sun_direction()))
	space_environment.set_daylight(daylight * sun_above_horizon, planet.up_at(actor_position))
	overlay.prompt_text = _message if _message_seconds_left > 0.0 else _prompt_for_current_situation()
	overlay.on_foot = on_foot if on_foot.active else null


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if on_foot.active:
			on_foot.add_mouse_motion(event.relative)
		else:
			player_source.add_mouse_motion(event.relative)
	elif event.is_action_pressed("interact"):
		if on_foot.active:
			_try_board_ship()
		else:
			_try_exit_ship()
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _prompt_for_current_situation() -> String:
	if on_foot.active:
		var near_ship := on_foot.body.position.distance_to(ship.state.position) <= PlayerState.BOARD_MAX_DISTANCE
		return "Press F to board the ship" if near_ship else ""
	return "Press F to leave the ship" if ship.state.landed else ""


func _try_exit_ship() -> void:
	var outcome := player_state.try_exit_ship(ship.state)
	if not outcome.ok():
		_show_message(outcome.message)
		return
	ship.controller.release_control(player_source)
	var side := ship.state.basis.x
	var exit_position := ship.state.position.offset_by(side * EXIT_SIDE_OFFSET)
	on_foot.render_origin = ship.render_origin.duplicate_position()
	on_foot.body.place_on_ground(planet, exit_position, -ship.state.basis.z)
	on_foot.active = true
	on_foot.sync_transform()
	on_foot.reset_physics_interpolation()
	floating_origin.anchor = on_foot


func _try_board_ship() -> void:
	var outcome := player_state.try_board_ship(on_foot.body.position.distance_to(ship.state.position), ship.state)
	if not outcome.ok():
		_show_message(outcome.message)
		return
	on_foot.active = false
	camera.current = true
	camera.snap_to_target()
	floating_origin.anchor = ship
	ship.controller.request_control(player_source, &"pilot_seat")


func _show_message(text: String) -> void:
	_message = text
	_message_seconds_left = 2.5
