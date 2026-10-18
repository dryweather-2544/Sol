extends Node3D
## Boot scene: one planet, the ship in orbit, the player in the pilot seat. This script only
## builds nodes, turns keys/mouse into commands for GameSession, and picks the active camera;
## all game rules live in GameSession and the classes it uses.

const START_ALTITUDE := 300000.0
const START_SUN_ANGLE_DEGREES := 50.0
const WORLD_SEED := 42
const AUTOSAVE_INTERVAL_SECONDS := 300.0

var ship: Ship
var system: StarSystem
var runtime: WorldRuntime
var planet: PlanetBody ## null while in the star-centred system frame
var terrain: PlanetTerrain
var impostors: BodyImpostors
var atmosphere_shell: AtmosphereShell
var space_environment: SpaceEnvironment
var player_source := PlayerPilotSource.new()
var session: GameSession
var on_foot: OnFootController
var interior_view: InteriorView
var chase_camera: ChaseCamera
var cockpit_camera: CockpitCamera
var floating_origin: FloatingOrigin
var overlay: DebugOverlay
var poi_manager: PoiManager
var menu: PauseMenu
var inventory_menu: InventoryMenu
var workbench_menu: WorkbenchMenu
var reactor_menu: ReactorMenu
var audio: AudioService
var enemy_director: EnemyDirector
var projectile_view: ProjectileView
var _cockpit_view := false
var _welcomed := false
var _nav_target_index := -1
var save_manager := SaveManager.new()
var _was_landed := false
var _seconds_since_autosave := 0.0


func _ready() -> void:
	system = StarSystem.default_system()
	planet = system.build_planet_body(system.home_id)
	space_environment = SpaceEnvironment.new()
	add_child(space_environment)

	# Start above a point where the sun is START_SUN_ANGLE_DEGREES from overhead, facing the planet.
	var toward_sun := -system.sun_direction_in_frame(system.home_id, 0.0)
	var tilt_axis := toward_sun.cross(Vector3.UP).normalized()
	var start_up := toward_sun.rotated(tilt_axis, deg_to_rad(START_SUN_ANGLE_DEGREES))
	ship = Ship.new()
	ship.planet = planet
	ship.state.position = WorldPos.new(planet.frame_id, start_up.x * (planet.radius + START_ALTITUDE), start_up.y * (planet.radius + START_ALTITUDE), start_up.z * (planet.radius + START_ALTITUDE))
	ship.state.basis = Basis.looking_at(-start_up, Vector3.UP) # nose toward the planet
	ship.render_origin = ship.state.position.duplicate_position()
	ship.state.gear = PilotCommand.GEAR_CRUISE # start in orbit, 300 km up: cruise gets you down in half a minute
	session = GameSession.new(planet, ship, player_source) # gives the ship its interior systems
	runtime = WorldRuntime.new(system, session, system.home_id)
	runtime.frame_changed.connect(_on_frame_changed)
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

	_build_poi_manager()

	projectile_view = ProjectileView.new()
	projectile_view.sim = session.projectiles
	projectile_view.render_origin = ship.render_origin.duplicate_position()
	add_child(projectile_view)

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
	overlay.poi_manager = poi_manager
	add_child(overlay)
	atmosphere_shell = AtmosphereShell.new()
	add_child(atmosphere_shell)
	impostors = BodyImpostors.new()
	impostors.system = system
	impostors.runtime = runtime
	add_child(impostors)
	_update_active_camera()
	audio = AudioService.new()
	audio.session = session
	audio.ship = ship
	add_child(audio)
	session.player_lost.connect(_on_player_lost)
	inventory_menu = InventoryMenu.new()
	inventory_menu.session = session
	inventory_menu.closed.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	add_child(inventory_menu)
	workbench_menu = WorkbenchMenu.new()
	workbench_menu.session = session
	workbench_menu.closed.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	session.workbench_requested.connect(func():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		workbench_menu.open())
	add_child(workbench_menu)
	reactor_menu = ReactorMenu.new()
	reactor_menu.session = session
	reactor_menu.closed.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	session.reactor_requested.connect(func():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		reactor_menu.open())
	add_child(reactor_menu)
	menu = PauseMenu.new()
	menu.resume_requested.connect(_on_menu_resume)
	menu.load_requested.connect(func(): _load_from("quicksave"); _on_menu_resume())
	menu.continue_requested.connect(func(): _load_from("autosave"); _on_menu_resume())
	menu.save_requested.connect(func(): _save_to("quicksave"))
	menu.quit_requested.connect(func(): get_tree().quit())
	menu.autosave_exists = save_manager.load_slot("autosave")["ok"]
	menu.world_ready_check = func() -> bool: return terrain != null and terrain.is_settled()
	add_child(menu)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	var command := OnFootCommand.new()
	command.move = Vector2(Input.get_axis("strafe_left", "strafe_right"), Input.get_axis("thrust_back", "thrust_forward"))
	command.run = Input.is_action_pressed("boost")
	command.jump = Input.is_action_pressed("move_up")
	command.jetpack = Input.is_action_pressed("move_up")
	var keyboard_turn := Input.get_axis("yaw_right", "yaw_left") * 2.0 * delta
	if session.mode == GameSession.Mode.OUTSIDE:
		command.yaw_delta = on_foot.take_pending_yaw() + keyboard_turn
	else:
		command.yaw_delta = interior_view.take_pending_yaw() + keyboard_turn
	if session.mode == GameSession.Mode.OUTSIDE and Input.is_action_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		session.player_fire(-on_foot.camera.global_transform.basis.z)
	var mode_before := session.mode
	runtime.advance(delta)
	runtime.update_frame()
	session.tick(delta, command)
	on_foot.sync_transform()
	interior_view.sync_view()
	if session.mode != mode_before:
		_on_mode_changed()
		if session.mode == GameSession.Mode.SEATED or mode_before == GameSession.Mode.OUTSIDE:
			_autosave("boarded")
	_autosave_if_due(delta)


func _process(_delta: float) -> void:
	_apply_field_of_view()
	var actor_position := session.player_world_position()
	if terrain != null:
		terrain.viewer = actor_position
	if poi_manager != null:
		poi_manager.viewer = actor_position
		session.check_discovery(poi_manager.known_instances())
		session.nearby_pois = poi_manager.known_instances()
		session.apply_poi_blockers(session.nearby_pois)
		session.apply_building_walls()
	var far_plane := 40000.0
	if session.mode == GameSession.Mode.SEATED or session.mode == GameSession.Mode.SITTING:
		# Near plane small enough for the ship (11 m ahead of the camera); far plane just past the
		# horizon (or far enough for other worlds in open space). Keeping far/near moderate avoids
		# depth-precision and light-culler problems.
		var altitude := maxf(ship.state.altitude_above_ground, 1.0)
		var near_plane := clampf(altitude * 0.002, 0.3, 2.0)
		if planet != null:
			far_plane = clampf(sqrt(2.0 * planet.radius * altitude) * 2.0 + 5000.0, 20000.0, 3.0e7)
		else:
			far_plane = 4.0e6
		chase_camera.near = near_plane
		chase_camera.far = far_plane
		cockpit_camera.near = minf(near_plane, 0.5)
		cockpit_camera.far = far_plane
	impostors.placement_distance = far_plane * 0.8
	impostors.viewer_local = on_foot.position if session.mode == GameSession.Mode.OUTSIDE else ship.position
	var sun_direction := system.sun_direction_in_frame(runtime.active_frame, runtime.time_seconds)
	if runtime.active_frame == StarSystem.SYSTEM_FRAME:
		var to_star := system.body_position(system.star_id, runtime.time_seconds)
		var here := system.convert_position(actor_position, StarSystem.SYSTEM_FRAME, runtime.time_seconds)
		sun_direction = Vector3(here.x - to_star.x, here.y - to_star.y, here.z - to_star.z).normalized()
	space_environment.set_sun_direction(sun_direction)
	atmosphere_shell.visible = planet != null and planet.atmosphere_height > 0.0
	if atmosphere_shell.visible:
		var home_body: BodyDef = system.bodies[runtime.active_frame]
		atmosphere_shell.update_shell(planet.radius + planet.atmosphere_height * 1.6, WorldPos.new(planet.frame_id, 0.0, 0.0, 0.0).to_local_vector3(terrain.render_origin) if terrain != null else Vector3.ZERO, sun_direction, home_body.atmosphere_color)
	if planet != null:
		var atmosphere_ratio := planet.atmosphere_ratio(actor_position)
		var daylight := 1.0 - smoothstep(0.0, 1.0, atmosphere_ratio) if atmosphere_ratio != INF else 0.0
		var sun_above_horizon := smoothstep(-0.1, 0.3, planet.up_at(actor_position).dot(-sun_direction))
		space_environment.set_daylight(daylight * sun_above_horizon, planet.up_at(actor_position), 0.0 if session.mode == GameSession.Mode.OUTSIDE else ship.state.altitude_above_ground)
	else:
		space_environment.set_daylight(0.0, Vector3.UP)
	overlay.frame_text = _frame_and_nav_text()


func _input(event: InputEvent) -> void:
	if workbench_menu.visible:
		if event.is_action_pressed("pause"):
			workbench_menu.close()
		return
	if reactor_menu.visible:
		if event.is_action_pressed("pause"):
			reactor_menu.close()
		return
	if inventory_menu.visible:
		if event.is_action_pressed("inventory") or event.is_action_pressed("pause"):
			inventory_menu.close()
		return
	if menu.visible:
		return
	if event.is_action_pressed("inventory"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		inventory_menu.open()
		return
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
	elif event.is_action_pressed("nav_next"):
		_cycle_nav_target()
	elif event.is_action_pressed("toggle_view"):
		if session.mode == GameSession.Mode.OUTSIDE:
			on_foot.third_person = not on_foot.third_person
		else:
			_cockpit_view = not _cockpit_view
			_update_active_camera()
	elif event.is_action_pressed("quicksave"):
		_save_to("quicksave")
	elif event.is_action_pressed("quickload"):
		_load_from("quicksave")
	elif event.is_action_pressed("pause"):
		if not menu.visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			menu.open_pause()
	elif event is InputEventMouseButton and event.pressed and not menu.visible:
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
	var error := save_manager.save(slot, SaveGame.capture(session, WORLD_SEED, runtime.time_seconds))
	session.say("Saved (%s)" % slot if error == "" else "Save failed: " + error)


func _load_from(slot: String) -> void:
	var loaded := save_manager.load_slot(slot)
	if not loaded["ok"]:
		session.say("Load failed: " + String(loaded["error"]))
		return
	var saved_data: Dictionary = loaded["data"]
	runtime.time_seconds = float(saved_data["world"]["time"])
	runtime.navigator.time_seconds = runtime.time_seconds
	var saved_frame := StringName(String(saved_data["ship"]["position"]["frame_id"]))
	if saved_frame != runtime.active_frame:
		runtime.force_frame(saved_frame)
	var error := SaveGame.restore(session, saved_data)
	if error != "":
		session.say("Load failed: " + error)
		return
	_recentre_everything_on_ship()
	_on_mode_changed()
	chase_camera.snap_to_target()
	session.say("Loaded (%s)%s" % [slot, " from backup" if loaded["used_backup"] else ""])


func _autosave(reason: String) -> void:
	if session.mode == GameSession.Mode.SITTING:
		return # never mid-transition
	var error := save_manager.save("autosave", SaveGame.capture(session, WORLD_SEED, runtime.time_seconds))
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


## Everything that lives in render space is re-centred on the ship (after a load or frame switch).
func _recentre_everything_on_ship() -> void:
	var new_origin := session.ship.state.position.duplicate_position()
	ship.render_origin = new_origin
	ship.apply_origin_shift(Vector3.ZERO)
	if terrain != null:
		terrain.render_origin = new_origin.duplicate_position()
		terrain.apply_origin_shift(Vector3.ZERO)
	if poi_manager != null:
		poi_manager.render_origin = new_origin.duplicate_position()
		poi_manager.apply_origin_shift(Vector3.ZERO)
	projectile_view.render_origin = new_origin.duplicate_position()
	if enemy_director != null:
		enemy_director.render_origin = new_origin.duplicate_position()
	on_foot.planet = planet
	on_foot.render_origin = new_origin.duplicate_position()


func _build_poi_manager() -> void:
	if poi_manager != null:
		poi_manager.queue_free()
		poi_manager = null
	_build_enemy_director(null)
	if planet == null:
		return
	var prefix := "" if runtime.active_frame == system.home_id else String(runtime.active_frame)
	poi_manager = PoiManager.new(PoiPlanner.new(planet, SeedHash.derive(WORLD_SEED, String(runtime.active_frame)), 0.22, prefix))
	poi_manager.render_origin = ship.render_origin.duplicate_position()
	poi_manager.viewer = ship.state.position
	add_child(poi_manager)
	_build_enemy_director(poi_manager)


func _build_enemy_director(manager: PoiManager) -> void:
	if enemy_director != null:
		enemy_director.clear_all()
		enemy_director.queue_free()
		enemy_director = null
	if manager == null:
		return
	enemy_director = EnemyDirector.new()
	enemy_director.session = session
	enemy_director.planet = planet
	enemy_director.poi_manager = manager
	enemy_director.render_origin = ship.render_origin.duplicate_position()
	add_child(enemy_director)


func _build_terrain() -> void:
	if terrain != null:
		terrain.queue_free()
		terrain = null
	if planet == null:
		return
	terrain = PlanetTerrain.new(planet)
	terrain.render_origin = ship.render_origin.duplicate_position()
	terrain.viewer = ship.state.position
	add_child(terrain)


func _on_frame_changed(_old_frame: StringName, _new_frame: StringName) -> void:
	session.nearby_pois = []
	planet = runtime.planet_for(runtime.active_frame)
	_build_terrain()
	_build_poi_manager()
	_recentre_everything_on_ship()
	overlay.terrain = terrain
	overlay.poi_manager = poi_manager
	chase_camera.snap_to_target()
	session.say("Entering %s" % (system.bodies[runtime.active_frame] as BodyDef).display_name if runtime.active_frame != StarSystem.SYSTEM_FRAME else "Leaving orbit - open space")


func _nav_targets() -> Array[StringName]:
	var targets: Array[StringName] = []
	for body_id in system.bodies:
		if body_id != runtime.active_frame:
			targets.append(body_id)
	return targets


func _cycle_nav_target() -> void:
	var targets := _nav_targets()
	_nav_target_index = (_nav_target_index + 1) % (targets.size() + 1) # last step = no target
	session.say("Nav target cleared" if _nav_target_index >= targets.size() else "Nav target: " + (system.bodies[targets[_nav_target_index]] as BodyDef).display_name)


func _frame_and_nav_text() -> String:
	var frame_name := "open space" if runtime.active_frame == StarSystem.SYSTEM_FRAME else (system.bodies[runtime.active_frame] as BodyDef).display_name
	var text := "Frame: %s   T: cycle nav target" % frame_name
	var targets := _nav_targets()
	if _nav_target_index < 0 or _nav_target_index >= targets.size():
		return text
	var target_id := targets[_nav_target_index]
	var target_center := system.convert_position(WorldPos.new(target_id, 0.0, 0.0, 0.0), runtime.active_frame, runtime.time_seconds)
	var here := session.player_world_position()
	var offset := target_center.vector_from(here)
	var surface_distance := maxf(offset.length() - (system.bodies[target_id] as BodyDef).radius, 0.0)
	var forward := session.forward_vector()
	var bearing_up := ship.state.basis.y if planet == null else planet.up_at(here)
	var angle_off := rad_to_deg(forward.angle_to(offset))
	var side := "ahead" if angle_off < 20.0 else ("behind" if angle_off > 140.0 else ("to the right" if forward.cross(bearing_up).dot(offset) > 0.0 else "to the left"))
	var distance_text := "%.0f m" % surface_distance if surface_distance < 1.0e4 else ("%.0f km" % (surface_distance / 1000.0) if surface_distance < 1.0e7 else "%.2e m" % surface_distance)
	return text + "\nTarget: %s   %s   %s" % [(system.bodies[target_id] as BodyDef).display_name, distance_text, side]


func _on_menu_resume() -> void:
	if not _welcomed:
		_welcomed = true
		session.say("W thrusts, mouse steers, [ ] change gear. Aim down at the planet, thrust, and land belly-down.")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	menu.autosave_exists = save_manager.load_slot("autosave")["ok"]


func _apply_field_of_view() -> void:
	var fov := GameSettings.instance().field_of_view
	for camera in [chase_camera, cockpit_camera, interior_view.camera, on_foot.camera]:
		(camera as Camera3D).fov = fov


func _on_player_lost(reason: String) -> void:
	session.say("%s - restoring your last save..." % reason)
	await get_tree().create_timer(2.5).timeout
	var loaded := save_manager.load_slot("autosave")
	if loaded["ok"]:
		_load_from("autosave")
	else:
		get_tree().reload_current_scene()
