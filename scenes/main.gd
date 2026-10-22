extends Node3D
## Boot scene: one planet, the ship in orbit, the player in the pilot seat. This script only
## builds nodes, turns keys/mouse into commands for GameSession, and picks the active camera;
## all game rules live in GameSession and the classes it uses.

const START_ALTITUDE := 300000.0
const START_SUN_ANGLE_DEGREES := 50.0
const WORLD_SEED := 42
## Chance that a POI cell also holds a small scanner-found site (probe, deposit or anomaly).
const MINOR_SITE_DENSITY := 0.45
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
var turret_camera: Camera3D
var _turret_zoom := 9.0 # metres behind the barrel; the mouse wheel changes it
var _orbit_yaw := 0.0
var _look_yaw := 0.0 # free look at the helm: right mouse held swings the view round the ship without turning it
var _look_pitch := 0.0
var _orbit_pitch := 0.35
var floating_origin: FloatingOrigin
var overlay: DebugOverlay
var poi_manager: PoiManager
var menu: PauseMenu
var inventory_menu: InventoryMenu
var workbench_menu: WorkbenchMenu
var reactor_menu: ReactorMenu
var airlock_menu: AirlockMenu
var machine_menu: MachineMenu
## Walking up or down the ramp: the first-person view eases from the old camera's pose to the new one instead of snapping upright.
const CAMERA_BLEND_SECONDS := 0.5
var _blend_camera := Camera3D.new()
var _blend_from := Transform3D.IDENTITY
var _blend_time := CAMERA_BLEND_SECONDS
var _blend_target: Camera3D
var exploration_menu: ExplorationMenu
var _ambush_pending := false
var audio: AudioService
var speed_effects: SpeedEffects
var entry_effects: EntryEffects
var enemy_director: EnemyDirector
var projectile_view: ProjectileView
var combat_effects: CombatEffects
var _cockpit_view := false
## Rodina's warp and speed camera (FOV, chase distance and angle, shake); drives the ship cameras in the rodina style.
var warp_view := LimnalWarpView.new()
var _welcomed := false
var _nav_target_index := -1
var save_manager := SaveManager.new()
var _was_landed := false
var _seconds_since_autosave := 0.0
## VisualStyle bookkeeping: the style revision and the look last applied to the sky, lights and rim.
var _style_revision := -1
var _applied_look: PlanetLook


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
	ship.state.gear = PilotCommand.GEAR_CRUISE # start in orbit in cruise (PRECISION is for near the ground)
	ship.state.selected_gear = PilotCommand.GEAR_CRUISE
	ship.render_origin = ship.state.position.duplicate_position()
	ship.state.gear = PilotCommand.GEAR_CRUISE # start in orbit, 300 km up: cruise gets you down in half a minute
	session = GameSession.new(planet, ship, player_source) # gives the ship its interior systems
	runtime = WorldRuntime.new(system, session, system.home_id)
	runtime.frame_changed.connect(_on_frame_changed)
	add_child(ship)
	for child in ship.get_children():
		if child is ShipVisuals:
			(child as ShipVisuals).session = session # the scanners screen shows the pulse cooldown

	interior_view = InteriorView.new()
	interior_view.body = session.interior_body
	ship.add_child(interior_view)
	cockpit_camera = CockpitCamera.new()
	ship.add_child(cockpit_camera)
	turret_camera = Camera3D.new()
	turret_camera.name = "TurretCamera"
	turret_camera.near = 0.3
	turret_camera.far = 40000.0
	ship.add_child(turret_camera)
	session.ambush_requested.connect(func(_beacon_direction: Vector3): _ambush_pending = true)
	session.crew.add_member(session.systems, &"mara", &"engineer", &"reactor_panel")
	session.crew.add_member(session.systems, &"kit", &"gunner", &"gunner_seat")
	var crew_view := CrewView.new()
	crew_view.crew = session.crew
	crew_view.layout = session.systems.layout
	ship.add_child(crew_view)

	terrain = PlanetTerrain.new(planet)
	terrain.render_origin = ship.render_origin.duplicate_position()
	terrain.viewer = ship.state.position
	terrain.viewer_velocity = Vector3.ZERO
	terrain.threaded_planning = true
	add_child(terrain)

	_build_poi_manager()

	projectile_view = ProjectileView.new()
	projectile_view.sim = session.projectiles
	projectile_view.render_origin = ship.render_origin.duplicate_position()
	add_child(projectile_view)
	combat_effects = CombatEffects.new()
	combat_effects.render_origin = ship.render_origin.duplicate_position()
	add_child(combat_effects)
	session.projectiles.hit.connect(func(_projectile, _target): combat_effects.flash(_projectile.position))

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
	speed_effects = SpeedEffects.new()
	speed_effects.ship = ship
	add_child(speed_effects) # below the HUD overlay in CanvasLayer order
	entry_effects = EntryEffects.new()
	entry_effects.ship = ship
	add_child(entry_effects)
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
	inventory_menu.audio = audio
	inventory_menu.closed.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	add_child(inventory_menu)
	exploration_menu = ExplorationMenu.new()
	exploration_menu.session = session
	exploration_menu.audio = audio
	exploration_menu.closed.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	add_child(exploration_menu)
	workbench_menu = WorkbenchMenu.new()
	workbench_menu.session = session
	workbench_menu.audio = audio
	workbench_menu.closed.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	session.workbench_requested.connect(func():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		workbench_menu.open())
	add_child(workbench_menu)
	reactor_menu = ReactorMenu.new()
	reactor_menu.session = session
	reactor_menu.audio = audio
	reactor_menu.closed.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	session.reactor_requested.connect(func():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		reactor_menu.open())
	add_child(reactor_menu)
	session.rest_requested.connect(func(): _save_to("autosave"))
	airlock_menu = AirlockMenu.new()
	airlock_menu.session = session
	airlock_menu.audio = audio
	airlock_menu.closed.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	session.airlock_requested.connect(func():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		airlock_menu.open())
	add_child(airlock_menu)
	machine_menu = MachineMenu.new()
	machine_menu.session = session
	machine_menu.audio = audio
	machine_menu.scanner_rows = _scanner_rows
	machine_menu.select_nav_target = _select_nav_target
	machine_menu.current_nav_name = _current_nav_name
	machine_menu.closed.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	session.machine_requested.connect(func(kind: StringName):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		machine_menu.open(kind))
	add_child(machine_menu)
	menu = PauseMenu.new()
	menu.audio = audio
	menu.resume_requested.connect(_on_menu_resume)
	menu.load_requested.connect(func(): _load_from("quicksave"); _on_menu_resume())
	menu.continue_requested.connect(func(): _load_from("autosave"); _on_menu_resume())
	menu.save_requested.connect(func(): _save_to("quicksave"))
	menu.quit_requested.connect(func(): get_tree().quit())
	menu.autosave_exists = save_manager.load_slot("autosave")["ok"]
	menu.world_ready_check = func() -> bool: return terrain != null and terrain.is_settled()
	add_child(menu)
	_style_revision = VisualStyle.revision
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	var command := OnFootCommand.new()
	command.move = Vector2(Input.get_axis("strafe_left", "strafe_right"), Input.get_axis("thrust_back", "thrust_forward"))
	command.run = Input.is_action_pressed("boost")
	command.jump = Input.is_action_pressed("move_up")
	command.jetpack = Input.is_action_pressed("move_up")
	if airlock_menu.visible or machine_menu.visible:
		command.move = Vector2.ZERO # the player stands at the computer while it is open
		command.jump = false
	var keyboard_turn := Input.get_axis("yaw_right", "yaw_left") * 2.0 * delta
	if session.mode == GameSession.Mode.OUTSIDE:
		command.yaw_delta = on_foot.take_pending_yaw() + keyboard_turn
	else:
		command.yaw_delta = interior_view.take_pending_yaw() + keyboard_turn
	if session.mode == GameSession.Mode.OUTSIDE and Input.is_action_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		session.player_fire(-on_foot.camera.global_transform.basis.z)
	session.gunner_trigger = session.gunner_station and Input.is_action_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var mode_before := session.mode
	runtime.advance(delta)
	runtime.update_frame()
	_update_mission()
	session.tick(delta, command)
	_update_warp_view(delta)
	on_foot.sync_transform()
	interior_view.sync_view()
	interior_view.set_lamp(session.mode == GameSession.Mode.INSIDE)
	session.set_look(interior_view.camera.position, -interior_view.camera.basis.z)
	if session.mode != mode_before:
		_begin_camera_blend(mode_before)
		_on_mode_changed()
		if session.mode == GameSession.Mode.SEATED or mode_before == GameSession.Mode.OUTSIDE:
			_autosave("boarded")
	_autosave_if_due(delta)


func _process(delta: float) -> void:
	_update_camera_blend(delta)
	_apply_field_of_view()
	if VisualStyle.revision != _style_revision:
		_restyle()
	var look := _current_look()
	if look != _applied_look:
		_applied_look = look
		space_environment.apply_look(look)
	var actor_position := session.player_world_position()
	if terrain != null:
		terrain.viewer = actor_position
		terrain.viewer_velocity = ship.state.velocity if session.mode == GameSession.Mode.SEATED or session.mode == GameSession.Mode.SITTING else Vector3.ZERO
	if poi_manager != null:
		poi_manager.viewer = actor_position
		session.check_discovery(poi_manager.known_instances())
		session.nearby_pois = poi_manager.known_instances()
		session.apply_poi_blockers(session.nearby_pois)
		session.apply_building_walls()
	var far_plane := 40000.0
	if session.mode == GameSession.Mode.SEATED or session.mode == GameSession.Mode.SITTING:
		# Near plane small enough for the ship (11 m ahead of the camera); far plane just past the
		# horizon (or far enough for other worlds in open space). CameraRange keeps far/near inside what
		# the engine's float32 projection can hold, so frustum culling never throws the scene away.
		var altitude := maxf(ship.state.altitude_above_ground, 1.0)
		var near_plane := clampf(altitude * 0.002, 0.3, 2.0)
		if planet != null:
			far_plane = clampf(sqrt(2.0 * planet.radius * altitude) * 2.0 + 5000.0, 20000.0, 3.0e7)
		else:
			far_plane = 4.0e6
		var close_near := minf(near_plane, 0.5) # cockpit and turret: the canopy and the gun are close
		far_plane = CameraRange.clamp_far(close_near, far_plane)
		chase_camera.near = near_plane
		chase_camera.far = far_plane
		cockpit_camera.near = close_near
		cockpit_camera.far = far_plane
		turret_camera.near = close_near
		turret_camera.far = far_plane
	if session.mode == GameSession.Mode.INSIDE:
		# The pocket rooms' windows look at the world, so the walking camera sees to the horizon too. Its near plane rises
		# only as far as that needs (at most 0.25 m, still inside a person's 0.3 m radius from any wall) and its far plane is
		# capped to what that near plane allows (CameraRange: the 2f9b74e far plane with near 0.05 m culled the whole ship).
		var altitude_inside := maxf(ship.state.altitude_above_ground, 1.0)
		var wanted_far := clampf(sqrt(2.0 * planet.radius * altitude_inside) * 2.0 + 5000.0, 40000.0, 3.0e7) if planet != null else 4.0e6
		var inside_near := CameraRange.near_for(wanted_far, 0.05, 0.25)
		far_plane = CameraRange.clamp_far(inside_near, wanted_far)
		interior_view.camera.near = inside_near
		interior_view.camera.far = far_plane
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
		var home_look := VisualStyle.look_for(home_body)
		var shell_centre := WorldPos.new(planet.frame_id, 0.0, 0.0, 0.0).to_local_vector3(terrain.render_origin) if terrain != null else Vector3.ZERO
		if not atmosphere_shell.update_rodina(planet.radius, planet.atmosphere_height, shell_centre, sun_direction, _star_radius_angle(runtime.active_frame), home_look.rodina_atmosphere if VisualStyle.is_rodina() else {}):
			atmosphere_shell.update_shell(planet.radius + planet.atmosphere_height * 1.6, shell_centre, sun_direction, home_look.rim_color, home_look.rim_power, home_look.rim_haze)
	space_environment.ambient_scale = VisualStyle.interior_ambient_factor() if session.mode == GameSession.Mode.INSIDE else 1.0
	if planet != null:
		var atmosphere_ratio := planet.atmosphere_ratio(actor_position)
		var daylight := 1.0 - smoothstep(0.0, 1.0, atmosphere_ratio) if atmosphere_ratio != INF else 0.0
		var sun_above_horizon := smoothstep(-0.1, 0.3, planet.up_at(actor_position).dot(-sun_direction))
		impostors.hide_star = VisualStyle.is_rodina() and daylight > 0.02
		space_environment.set_sun_elevation(planet.up_at(actor_position).dot(-sun_direction), daylight)
		var viewer_up := planet.up_at(actor_position)
		space_environment.set_rodina_viewer(VisualStyle.is_rodina() and planet.atmosphere_height > 0.0, viewer_up * (planet.distance_from_center(actor_position) / planet.radius), planet.atmosphere_height / maxf(planet.radius, 1.0), _star_radius_angle(runtime.active_frame))
		var viewer_altitude := 2.0 if session.mode == GameSession.Mode.OUTSIDE else ship.state.altitude_above_ground
		space_environment.set_daylight(daylight * sun_above_horizon, planet.up_at(actor_position), 0.0 if session.mode == GameSession.Mode.OUTSIDE else ship.state.altitude_above_ground)
		if terrain != null:
			terrain.set_viewer_altitude(viewer_altitude)
	else:
		impostors.hide_star = false
		space_environment.set_daylight(0.0, Vector3.UP)
		space_environment.set_sun_elevation(1.0)
		space_environment.set_rodina_viewer(false)
	overlay.frame_text = _frame_and_nav_text()
	if session.gunner_station:
		var turret := session.systems.turret
		overlay.frame_text += "\nGUNNER  heat %d%%%s" % [roundi(turret.heat * 100.0), "  OVERHEATED" if turret.overheated else ""]
		var aim := turret.manual_direction()
		var up_hint := Vector3.UP if absf(aim.y) < 0.99 else Vector3.BACK
		# sits behind and above the barrel, looking down its line, so the muzzle and the shots are in view
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			# right mouse held: look around the ship instead of aiming
			var around := Vector3(sin(_orbit_yaw) * cos(_orbit_pitch), sin(_orbit_pitch), cos(_orbit_yaw) * cos(_orbit_pitch))
			var centre := Vector3(0, 1.5, 0)
			turret_camera.transform = Transform3D(Basis.looking_at(-around, Vector3.UP), centre + around * (_turret_zoom + 10.0))
		else:
			# behind the barrel, but never lower than a little above the roof, so it stays out of the hull
			var camera_position := turret.muzzle_offset - aim * _turret_zoom
			camera_position.y = maxf(camera_position.y, turret.muzzle_offset.y + 1.0 + 0.25 * _turret_zoom)
			turret_camera.transform = Transform3D(Basis.looking_at(aim, up_hint) * Basis.from_euler(Vector3(warp_view.shake.y, warp_view.shake.x, 0.0)), camera_position) # the gun's shots shake the view like Rodina's fire vibration


func _input(event: InputEvent) -> void:
	if machine_menu.visible:
		if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
			machine_menu.close()
		return
	if airlock_menu.visible:
		if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
			airlock_menu.close()
		return
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
	if exploration_menu.visible:
		if event.is_action_pressed("journal") or event.is_action_pressed("pause"):
			exploration_menu.close()
		return
	if menu.visible:
		return
	if event.is_action_pressed("journal"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		exploration_menu.open()
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
				if session.gunner_station and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
					_orbit_yaw = wrapf(_orbit_yaw - event.relative.x * 0.004, -PI, PI)
					_orbit_pitch = clampf(_orbit_pitch - event.relative.y * 0.004, -1.4, 1.4)
				elif session.gunner_station:
					session.systems.turret.add_aim(event.relative)
				elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
					_look_yaw = wrapf(_look_yaw - event.relative.x * 0.004, -PI, PI)
					_look_pitch = clampf(_look_pitch - event.relative.y * 0.004, -1.3, 1.3)
				else:
					player_source.add_mouse_motion(event.relative)
	elif session.gunner_station and event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var step := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0
		_turret_zoom = clampf(_turret_zoom + step * maxf(1.0, _turret_zoom * 0.12), 1.5, 80.0)
	elif event.is_action_pressed("gunner_station"):
		session.toggle_gunner_station()
		_update_active_camera()
	elif event.is_action_pressed("interact"):
		var mode_before := session.mode
		session.interact()
		if session.mode != mode_before:
			_on_mode_changed()
	elif event.is_action_pressed("crew_fix"):
		session.order_crew_fix()
	elif event.is_action_pressed("crew_turret"):
		session.order_crew_turret()
	elif event.is_action_pressed("crew_power"):
		session.cycle_power_preset()
	elif event.is_action_pressed("nav_next"):
		_cycle_nav_target()
	elif event.is_action_pressed("scan"):
		session.scan_pulse()
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


## Remember where the old first-person camera was when the walker crosses the doorway, so the new one can ease in from there.
func _begin_camera_blend(mode_before: int) -> void:
	var walking := [GameSession.Mode.OUTSIDE, GameSession.Mode.INSIDE]
	if not (mode_before in walking and session.mode in walking):
		return
	var old_camera := get_viewport().get_camera_3d()
	if old_camera == null:
		return
	_blend_from = old_camera.global_transform
	_blend_time = 0.0


## For half a second after crossing the ramp threshold a transition camera slides from the old pose to the new camera's pose
## (the new camera keeps updating underneath), then hands over. This replaces the snap upright between planet-up and ship-up.
func _update_camera_blend(delta: float) -> void:
	if _blend_time >= CAMERA_BLEND_SECONDS:
		return
	var target: Camera3D = null
	if session.mode == GameSession.Mode.INSIDE:
		target = interior_view.camera
	elif session.mode == GameSession.Mode.OUTSIDE:
		target = on_foot.camera
	_blend_time += delta
	if target == null or _blend_time >= CAMERA_BLEND_SECONDS:
		_blend_time = CAMERA_BLEND_SECONDS
		_update_active_camera()
		return
	if _blend_camera.get_parent() == null:
		_blend_camera.name = "TransitionCamera"
		add_child(_blend_camera)
	var weight := smoothstep(0.0, 1.0, _blend_time / CAMERA_BLEND_SECONDS)
	_blend_camera.global_transform = _blend_from.interpolate_with(target.global_transform, weight)
	_blend_camera.fov = target.fov
	_blend_camera.near = target.near
	_blend_camera.far = target.far
	_blend_camera.cull_mask = target.cull_mask # ADR 0013: the ship layers this place draws
	_blend_camera.current = true


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
			if session.gunner_station:
				turret_camera.current = true
			elif _cockpit_view:
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
	audio.begin_state_restore()
	var error := SaveGame.restore(session, saved_data)
	audio.resync_from_state()
	if error != "":
		session.say("Load failed: " + error)
		return
	_recentre_everything_on_ship()
	_on_mode_changed()
	warp_view.reset()
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


## Mission glue: put the Mayday beacon on Selene once the ambush has fixed where it is, and spawn the raider.
func _update_mission() -> void:
	if _ambush_pending and enemy_director != null:
		_ambush_pending = false
		enemy_director.spawn_ambush()
	if poi_manager != null and session.progress.beacon_direction != Vector3.ZERO and runtime.active_frame == &"selene":
		if not poi_manager.planner.pinned.has(ProgressTracker.BEACON_ID):
			poi_manager.planner.pin_beacon(ProgressTracker.BEACON_ID, session.progress.beacon_direction, SeedHash.string_hash("mayday"))
			poi_manager.invalidate_plan()


func _build_poi_manager() -> void:
	if poi_manager != null:
		poi_manager.queue_free()
		poi_manager = null
	_build_enemy_director(null)
	if planet == null:
		return
	var prefix := "" if runtime.active_frame == system.home_id else String(runtime.active_frame)
	poi_manager = PoiManager.new(PoiPlanner.new(planet, SeedHash.derive(WORLD_SEED, String(runtime.active_frame)), 0.22, prefix))
	poi_manager.threaded = true
	poi_manager.planner.minor_density = MINOR_SITE_DENSITY
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
	terrain.viewer_velocity = Vector3.ZERO
	terrain.threaded_planning = true
	add_child(terrain)


func _on_frame_changed(_old_frame: StringName, _new_frame: StringName) -> void:
	session.nearby_pois = []
	planet = runtime.planet_for(runtime.active_frame)
	_assign_planet_look()
	_build_terrain()
	_build_poi_manager()
	_recentre_everything_on_ship()
	overlay.terrain = terrain
	overlay.poi_manager = poi_manager
	chase_camera.snap_to_target()
	session.say("Entering %s" % (system.bodies[runtime.active_frame] as BodyDef).display_name if runtime.active_frame != StarSystem.SYSTEM_FRAME else "Leaving orbit - open space")


## The look for where the player is: the current world's, or the deep-space look between worlds.
func _current_look() -> PlanetLook:
	if planet == null or not system.bodies.has(runtime.active_frame):
		return VisualStyle.deep_space_look()
	return VisualStyle.look_for(system.bodies[runtime.active_frame])


## Colours only: terrain is coloured from planet.look (null = the original Sol rule). Cached planet bodies are re-tagged
## here so a world visited before a style switch is drawn in the new style.
func _assign_planet_look() -> void:
	if planet != null and system.bodies.has(planet.frame_id):
		planet.look = VisualStyle.look_for(system.bodies[planet.frame_id]) if VisualStyle.is_rodina() else null


## Re-applies the visual style everywhere after VisualStyle.set_active(): terrain colours (rebuilt, geometry unchanged),
## impostors, the ship's paint and the sky. Physics, saves and positions are not touched.
func _restyle() -> void:
	_style_revision = VisualStyle.revision
	_assign_planet_look()
	if terrain != null:
		_build_terrain()
		overlay.terrain = terrain
	impostors.restyle()
	overlay.restyle()
	for child in ship.get_children():
		if child is ShipVisuals:
			(child as ShipVisuals).restyle()
	_applied_look = null


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


## Scanner menu data: every body but the one we are in, with its surface distance from the player.
func _scanner_rows() -> Array:
	var rows: Array = []
	var here := session.player_world_position()
	for body_id in _nav_targets():
		var body: BodyDef = system.bodies[body_id]
		var centre := system.convert_position(WorldPos.new(body_id, 0.0, 0.0, 0.0), runtime.active_frame, runtime.time_seconds)
		var distance := maxf(centre.vector_from(here).length() - body.radius, 0.0)
		var text := "%.0f m" % distance if distance < 1.0e4 else ("%.0f km" % (distance / 1000.0) if distance < 1.0e7 else "%.2e m" % distance)
		rows.append({"id": body_id, "name": body.display_name, "distance": text})
	return rows


func _select_nav_target(body_id: StringName) -> void:
	var targets := _nav_targets()
	_nav_target_index = targets.find(body_id) if body_id != &"" else -1


func _current_nav_name() -> String:
	var targets := _nav_targets()
	if _nav_target_index < 0 or _nav_target_index >= targets.size():
		return ""
	return (system.bodies[targets[_nav_target_index]] as BodyDef).display_name


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
	var fov := VisualStyle.base_field_of_view(GameSettings.instance().field_of_view)
	for camera in [interior_view.camera, on_foot.camera]:
		(camera as Camera3D).fov = fov
	# Rodina sets the camera FOV from the warp blend (EGDataShipPlayer.lua:325-346); at rest it is the setting.
	var ship_fov := warp_view.field_of_view(fov) if VisualStyle.is_rodina() else fov
	chase_camera.fov = ship_fov
	cockpit_camera.fov = minf(ship_fov + 18.0, 120.0) # wider inside the canopy so more of the windscreen is in view
	turret_camera.fov = ship_fov


## Advances the Rodina warp/speed camera from the ship's real state and hands it to the ship cameras. In the sol style
## it runs nothing and leaves both cameras at rest.
func _update_warp_view(delta: float) -> void:
	if not VisualStyle.is_rodina():
		if warp_view.spacewarp != 0.0 or warp_view.limnal_timer != 0.0 or warp_view.shake != Vector2.ZERO:
			warp_view.reset()
	else:
		var state := ship.state
		var fired := session.gunner_station and session.systems.turret.firing # only real shots shake the view; the pilot's click fires nothing
		warp_view.update(state.gear == PilotCommand.GEAR_WARP, state.atmosphere_resistance, fired, delta)
	var rodina := VisualStyle.is_rodina()
	chase_camera.follow_distance = warp_view.follow_distance() * RodinaEmitter.SHIP_SCALE if rodina else 0.0
	chase_camera.follow_angle = deg_to_rad(warp_view.follow_angle_degrees()) if rodina else 0.0
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or session.gunner_station:
		var settle := 1.0 - exp(-8.0 * delta) # the view swings back behind the ship when free look is released
		_look_yaw = lerpf(_look_yaw, 0.0, settle)
		_look_pitch = lerpf(_look_pitch, 0.0, settle)
	chase_camera.look_yaw = _look_yaw
	chase_camera.look_pitch = _look_pitch
	chase_camera.shake = warp_view.shake
	cockpit_camera.rotation = Vector3(warp_view.shake.y + _look_pitch, warp_view.shake.x + _look_yaw, 0.0)
	var effects := _ship_effects()
	if effects != null:
		effects.limnal_activation = warp_view.activation
		var in_ship_view := session.mode == GameSession.Mode.SEATED or session.mode == GameSession.Mode.SITTING
		effects.camera_inside = session.mode == GameSession.Mode.INSIDE or (in_ship_view and _cockpit_view and not session.gunner_station) # the turret camera is outside the hull
		_update_camera_place(effects.camera_inside)


## The star's angular radius seen from a body (radians), for Rodina's halo and sunset maths. In the rodina style the star
## is drawn at the look's disc size (as large as in Rodina's screenshots), and the halo is measured from that disc.
func _star_radius_angle(body_id: StringName) -> float:
	if VisualStyle.is_rodina() and system.bodies.has(body_id):
		var look := VisualStyle.look_for(system.bodies[body_id])
		if not look.rodina_atmosphere.is_empty():
			return look.sun_disc_radius
	var star: BodyDef = system.bodies[system.star_id]
	if body_id == StarSystem.SYSTEM_FRAME or not system.bodies.has(body_id):
		return 0.01
	var here := system.body_position(body_id, runtime.time_seconds)
	var distance := sqrt(here.x * here.x + here.y * here.y + here.z * here.z)
	return clampf(asin(clampf(star.radius / maxf(distance, star.radius * 1.01), 0.0, 1.0)), 0.001, 0.2)


## Bigger on the inside (ADR 0012): tell the ship and the crew view where the camera is, so the larger pocket rooms are
## drawn only from inside and the hull only from outside them.
func _update_camera_place(camera_inside: bool) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var local := ship.global_transform.affine_inverse() * camera.global_position
	var room_id := session.systems.layout.room_for_view(local.x, local.z) if camera_inside else &""
	for child in ship.get_children():
		if child is ShipVisuals:
			var visuals := child as ShipVisuals
			visuals.set_camera_place(camera_inside, room_id)
			# ADR 0013: every camera gets the cull mask for where it is, every tick, whichever one is current. Nothing is hidden.
			var eye_local := interior_view.camera.position
			interior_view.camera.cull_mask = visuals.cull_mask_for(true, session.systems.layout.room_for_view(eye_local.x, eye_local.z))
			cockpit_camera.cull_mask = visuals.cull_mask_for(true, &"cockpit")
			var outside_mask := visuals.cull_mask_for(false, &"")
			chase_camera.cull_mask = outside_mask
			turret_camera.cull_mask = outside_mask
			on_foot.camera.cull_mask = outside_mask
		elif child is CrewView:
			(child as CrewView).pocket_visible = camera_inside


func _ship_effects() -> ShipEffects:
	for child in ship.get_children():
		if child is ShipVisuals:
			return (child as ShipVisuals).effects
	return null


func _on_player_lost(reason: String) -> void:
	session.say("%s - restoring your last save..." % reason)
	await get_tree().create_timer(2.5).timeout
	var loaded := save_manager.load_slot("autosave")
	if loaded["ok"]:
		_load_from("autosave")
	else:
		get_tree().reload_current_scene()
