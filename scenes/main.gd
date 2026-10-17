extends Node3D
## Boot scene: one planet, one ship in orbit, chase camera, overlay. The player starts in the
## pilot seat. Start position and orientation are data-driven constants for now (M1).

const START_ALTITUDE := 300000.0
const START_SUN_ANGLE_DEGREES := 50.0

var ship: Ship
var planet: PlanetBody
var terrain: PlanetTerrain
var space_environment: SpaceEnvironment
var player_source := PlayerPilotSource.new()
var camera: ChaseCamera


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

	var floating_origin := FloatingOrigin.new()
	floating_origin.anchor = ship
	add_child(floating_origin) # after ship, so it runs after the ship's physics tick
	camera = ChaseCamera.new()
	camera.target = ship
	add_child(camera)
	camera.snap_to_target()
	camera.current = true
	var overlay := DebugOverlay.new()
	overlay.ship = ship
	overlay.terrain = terrain
	add_child(overlay)
	ship.controller.request_control(player_source, &"pilot_seat")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	# Near plane small enough for the ship (11 m ahead of the camera); far plane just past the horizon.
	# Keeping far/near moderate avoids depth-precision and light-culler problems at planet scale.
	var altitude := maxf(ship.state.altitude_above_ground, 1.0)
	camera.near = clampf(altitude * 0.002, 0.3, 2.0)
	camera.far = clampf(sqrt(2.0 * planet.radius * altitude) * 2.0 + 5000.0, 20000.0, 3.0e7)
	terrain.viewer = ship.state.position
	var daylight := 1.0 - smoothstep(0.0, 1.0, ship.state.atmosphere_ratio)
	var sun_above_horizon := smoothstep(-0.1, 0.3, planet.up_at(ship.state.position).dot(-SpaceEnvironment.sun_direction()))
	space_environment.set_daylight(daylight * sun_above_horizon, planet.up_at(ship.state.position))


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player_source.add_mouse_motion(event.relative)
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
