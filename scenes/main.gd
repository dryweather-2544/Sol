extends Node3D
## Boot scene: one planet, the ship in orbit, the player in the pilot seat. This script only
## builds nodes, turns keys/mouse into commands for GameSession, and picks the active camera;
## all game rules live in GameSession and the classes it uses.

const START_ALTITUDE := 300000.0
const START_SUN_ANGLE_DEGREES := 50.0
const WORLD_SEED := 42
const AUTOSAVE_INTERVAL_SECONDS := 300.0

var ship: Ship
var planet: PlanetBody
var terrain: PlanetTerrain
var space_environment: SpaceEnvironment
var player_source := PlayerPilotSource.new()
var session: GameSession
var on_foot: OnFootController
var interior_view: InteriorView
var chase_camera: ChaseCamera
var cockpit_camera: CockpitCamera
var floating_origin: FloatingOrigin
var overlay: DebugOverlay
var _cockpit_view := false
var save_manager := SaveManager.new()
var _was_landed := false
var _seconds_since_autosave := 0.0


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
	session = GameSession.new(planet, ship, player_source) # gives the ship its interior systems
	add_child(ship)

	interior_view = InteriorView.new()
	interior_view.body = session.interior_body
	ship.add_child(interior_view)
	cockpit_camera = CockpitCamera.new()
	ship.add_child(cockpit_camera)

	terrain = PlanetTerrain.new(planet)
	terrain.render_origin = ship.render_origin.duplicate_position()
	terrain.viewer = ship.state.position
	add_child(terrain)

	on_foot = OnFootController.new()
	on_foot.planet = planet
	on_foot.body = session.exterior_body
	on_foot.render_origin = ship.render_origin.duplicate_position()
	add_child(on_foot)

	floating_origin = FloatingOrigin.new()
	floating_origin.anchor = ship
	add_child(floating_origin) # after the actors, so it runs after their physics ticks
	chase_camera = ChaseCamera.new()
	chase_camera.target = ship
	add_child(chase_camera)
	chase_camera.snap_to_target()
	overlay = DebugOverlay.new()
	overlay.ship = ship
	overlay.terrain = terrain
	overlay.session = session
	add_child(overlay)
	_update_active_camera()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var command := OnFootCommand.new()
	command.move = Vector2(Input.get_axis("strafe_left", "strafe_right"), Input.get_axis("thrust_back", "thrust_forward"))
	command.run = Input.is_action_pressed("boost")
	command.jump = Input.is_action_pressed("move_up")
	var keyboard_turn := Input.get_axis("yaw_right", "yaw_left") * 2.0 * delta
	if session.mode == GameSession.Mode.OUTSIDE:
		command.yaw_delta = on_foot.take_pending_yaw() + keyboard_turn
	else:
		command.yaw_delta = interior_view.take_pending_yaw() + keyboard_turn
	var mode_before := session.mode
	session.tick(delta, command)
	on_foot.sync_transform()
	interior_view.sync_view()
	if session.mode != mode_before:
		_on_mode_changed()
		if session.mode == GameSession.Mode.SEATED or mode_before == GameSession.Mode.OUTSIDE:
			_autosave("boarded")
	_autosave_if_due(delta)


func _process(_delta: float) -> void:
	var actor_position := session.player_world_position()
	terrain.viewer = actor_position
	if session.mode == GameSession.Mode.SEATED or session.mode == GameSession.Mode.SITTING:
		# Near plane small enough for the ship (11 m ahead of the camera); far plane just past the
		# horizon. Keeping far/near moderate avoids depth-precision and light-culler problems.
		var altitude := maxf(ship.state.altitude_above_ground, 1.0)
		var near_plane := clampf(altitude * 0.002, 0.3, 2.0)
		var far_plane := clampf(sqrt(2.0 * planet.radius * altitude) * 2.0 + 5000.0, 20000.0, 3.0e7)
		chase_camera.near = near_plane
		chase_camera.far = far_plane
		cockpit_camera.near = minf(near_plane, 0.5)
		cockpit_camera.far = far_plane
	var atmosphere_ratio := planet.atmosphere_ratio(actor_position)
	var daylight := 1.0 - smoothstep(0.0, 1.0, atmosphere_ratio)
	var sun_above_horizon := smoothstep(-0.1, 0.3, planet.up_at(actor_position).dot(-SpaceEnvironment.sun_direction()))
	space_environment.set_daylight(daylight * sun_above_horizon, planet.up_at(actor_position))


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		match session.mode:
			GameSession.Mode.OUTSIDE:
				on_foot.add_mouse_motion(event.relative)
			GameSession.Mode.INSIDE:
				interior_view.add_mouse_motion(event.relative)
			_:
				player_source.add_mouse_motion(event.relative)
	elif event.is_action_pressed("interact"):
		var mode_before := session.mode
		session.interact()
		if session.mode != mode_before:
			_on_mode_changed()
	elif event.is_action_pressed("toggle_view"):
		_cockpit_view = not _cockpit_view
		_update_active_camera()
	elif event.is_action_pressed("quicksave"):
		_save_to("quicksave")
	elif event.is_action_pressed("quickload"):
		_load_from("quicksave")
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_mode_changed() -> void:
	floating_origin.anchor = on_foot if session.mode == GameSession.Mode.OUTSIDE else ship
	if session.mode == GameSession.Mode.OUTSIDE:
		on_foot.render_origin = ship.render_origin.duplicate_position()
	on_foot.sync_transform()
	on_foot.reset_physics_interpolation()
	if session.mode == GameSession.Mode.SEATED:
		chase_camera.snap_to_target()
	_update_active_camera()


func _update_active_camera() -> void:
	match session.mode:
		GameSession.Mode.OUTSIDE:
			on_foot.camera.current = true
		GameSession.Mode.INSIDE:
			interior_view.camera.current = true
		_:
			if _cockpit_view:
				cockpit_camera.current = true
			else:
				chase_camera.current = true


func _save_to(slot: String) -> void:
	var error := save_manager.save(slot, SaveGame.capture(session, WORLD_SEED))
	session.say("Saved (%s)" % slot if error == "" else "Save failed: " + error)


func _load_from(slot: String) -> void:
	var loaded := save_manager.load_slot(slot)
	if not loaded["ok"]:
		session.say("Load failed: " + String(loaded["error"]))
		return
	var error := SaveGame.restore(session, loaded["data"])
	if error != "":
		session.say("Load failed: " + error)
		return
	# Everything now lives somewhere else: re-centre the render origin on the ship and re-place nodes.
	var new_origin := session.ship.state.position.duplicate_position()
	ship.render_origin = new_origin
	ship.apply_origin_shift(Vector3.ZERO)
	terrain.render_origin = new_origin.duplicate_position()
	terrain.apply_origin_shift(Vector3.ZERO)
	on_foot.render_origin = new_origin.duplicate_position()
	_on_mode_changed()
	chase_camera.snap_to_target()
	session.say("Loaded (%s)%s" % [slot, " from backup" if loaded["used_backup"] else ""])


func _autosave(reason: String) -> void:
	if session.mode == GameSession.Mode.SITTING:
		return # never mid-transition
	var error := save_manager.save("autosave", SaveGame.capture(session, WORLD_SEED))
	if error != "":
		push_warning("autosave (%s) failed: %s" % [reason, error])


func _autosave_if_due(delta: float) -> void:
	_seconds_since_autosave += delta
	var landed_now := ship.state.landed
	if landed_now and not _was_landed:
		_autosave("landed")
		_seconds_since_autosave = 0.0
	_was_landed = landed_now
	if _seconds_since_autosave >= AUTOSAVE_INTERVAL_SECONDS:
		_seconds_since_autosave = 0.0
		_autosave("timer")
