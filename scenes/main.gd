extends Node3D
## Boot scene: one planet, the ship in orbit, the player in the pilot seat. This script only
## builds nodes, turns keys/mouse into commands for GameSession, and picks the active camera;
## all game rules live in GameSession and the classes it uses.

const BigShipMenuScript := preload("res://src/bigship/big_ship_menu.gd") # the five big ships (no class_name, so no class cache refresh is needed)
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
var hangar_menu: HangarMenu
var big_ship_menu # a BigShipMenuScript instance
var _fighter_node: Ship ## the player's separate fighter while one exists (flying or parked); freed when the session lets go of it
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
var _gait := 0 ## Z while on foot: 1 = walk, 2 = run; each press switches, the first gives walk (Shift still runs while held)
## The fighter's own view setting: you start in its cockpit, V swings out to the chase view (kept apart from the mothership's).
var _fighter_cockpit_view := true
var _gear_hint_cooldown := 0.0
## Degrees added to the fighter's field of view with the mouse wheel (in the cockpit) and a middle click (wide view on/off).
var _fighter_zoom_fov := 0.0
## Cockpit screens: a right click on a screen (letting go of the right button while the reticle is on it) focuses it: the view zooms in on it and
## the mouse moves a pointer over it. A right click then presses the control under the pointer, or on empty glass leaves the focus.
var _screen_focus := false
var _pad_hover := 0.0 ## seconds the reticle has rested on a cockpit screen with the right button held
var _screen_zoom := 1.0 ## wheel: scales the focused screen's field of view
var _screen_fov := 0.0 ## the cockpit camera's smoothed field of view
var _leave_blocks_entry := false ## the right button that left the focus must not focus again when it is released
var _screen_hint_shown := false
const FIGHTER_HOLD_ZOOM := -18.0 # degrees of field of view taken off while the right mouse button is held (free look), eased back on release
const FIGHTER_ZOOM_MIN := -22.0
const FIGHTER_ZOOM_MAX := 26.0
const FIGHTER_WIDE_FOV := 20.0
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
	chase_camera.ground_clearance = _camera_ground_clearance
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
	audio.runtime = runtime
	add_child(audio)
	session.player_lost.connect(_on_player_lost)
	inventory_menu = InventoryMenu.new()
	inventory_menu.session = session
	inventory_menu.audio = audio
	inventory_menu.closed.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	add_child(inventory_menu)
	hangar_menu = HangarMenu.new()
	hangar_menu.audio = audio
	hangar_menu.closed.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	hangar_menu.spawn_requested.connect(_on_fighter_spawn)
	hangar_menu.recall_requested.connect(_on_fighter_recall)
	hangar_menu.big_ships_requested.connect(func():
		big_ship_menu.set_outside(get_viewport().world_3d, _bridge_view_anchor(), chase_camera.far)
		big_ship_menu.open())
	add_child(hangar_menu)
	big_ship_menu = BigShipMenuScript.new()
	big_ship_menu.audio = audio
	big_ship_menu.closed.connect(func(): hangar_menu.reopen()) # back to the hangar it was opened from
	big_ship_menu.fly_requested.connect(_on_big_ship_fly)
	add_child(big_ship_menu)
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
	if audio.music != null:
		audio.music.menu = menu
		overlay.music = audio.music
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
	command.run = Input.is_action_pressed("boost") or _gait == 2
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
	# The player's fighter is ticked here, after the mothership and before the camera nodes, never by its own _physics_process (which
	# would run after the chase camera and leave the view one tick behind the ship).
	if _fighter_node != null and is_instance_valid(_fighter_node) and not _fighter_node.is_queued_for_deletion():
		if _screen_focus and not (session.mode == GameSession.Mode.FIGHTER and _fighter_cockpit_view and _fighter_node.cockpit != null and _fighter_node.cockpit.in_focus()):
			_leave_screen_focus() # the view changed (chase view, climbed out) or the cockpit went away
		player_source.ignore_clutch = _screen_focus
		player_source.ignore_fire = _screen_focus # left click presses screen controls then
		_fighter_node.screen_pointer_active = _fighter_node.cockpit != null and (_fighter_node.cockpit.is_pointing() or _fighter_node.cockpit.in_focus())
		if not _screen_hint_shown and _fighter_node.cockpit != null and _fighter_node.cockpit.pointed_screen() >= 0:
			_screen_hint_shown = true
			session.say("Let go of the right button on a screen to focus it")
		_fighter_node.simulate_tick(delta)
	_gear_hint_cooldown = maxf(0.0, _gear_hint_cooldown - delta)
	if session.mode == GameSession.Mode.FIGHTER and _gear_hint_cooldown <= 0.0 and Input.is_action_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var fighter_gear := session.active_ship().state.gear
		if fighter_gear == PilotCommand.GEAR_CRUISE:
			_gear_hint_cooldown = 3.0
			session.say("Dropping out of cruise to COMBAT gear to fire")
		elif not Ship.gear_allows_fire(fighter_gear):
			_gear_hint_cooldown = 3.0
			session.say("Guns are safe in this gear: [ ] to shift to COMBAT")
	_sync_fighter()
	_update_warp_view(delta)
	on_foot.sync_transform()
	interior_view.layout = session.systems.layout
	interior_view.sync_view()
	interior_view.set_lamp(session.mode == GameSession.Mode.INSIDE)
	session.set_look(interior_view.eye_position(), -interior_view.camera.basis.z)
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
		terrain.viewer_velocity = _flown().state.velocity if session.mode == GameSession.Mode.SEATED or session.mode == GameSession.Mode.SITTING or session.mode == GameSession.Mode.FIGHTER else Vector3.ZERO
	if poi_manager != null:
		poi_manager.viewer = actor_position
		session.check_discovery(poi_manager.known_instances())
		session.nearby_pois = poi_manager.known_instances()
		session.apply_poi_blockers(session.nearby_pois)
		session.apply_building_walls()
	var far_plane := 40000.0
	if session.mode == GameSession.Mode.SEATED or session.mode == GameSession.Mode.SITTING or session.mode == GameSession.Mode.FIGHTER:
		# Near plane small enough for the ship (11 m ahead of the camera); far plane just past the
		# horizon (or far enough for other worlds in open space). CameraRange keeps far/near inside what
		# the engine's float32 projection can hold, so frustum culling never throws the scene away.
		var altitude := maxf(_flown().state.altitude_above_ground, 1.0)
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
		if _fighter_node != null and _fighter_node.cockpit_camera != null:
			# Same planes as the chase view: the canopy, a metre away, is drawn by its own short-range camera (CockpitOverlay), so this
			# one no longer needs a 0.1 m near plane, which capped its far plane at ~400 km and made the planet clip in cockpit view.
			_fighter_node.cockpit_camera.near = close_near
			_fighter_node.cockpit_camera.far = far_plane
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
	var terrain_scale := 1.0
	if terrain != null:
		terrain.view_position = on_foot.position if session.mode == GameSession.Mode.OUTSIDE else _flown().position
		terrain.squeeze_range = impostors.placement_distance * 0.95
		terrain_scale = terrain.squeeze_scale()
	impostors.viewer_local = on_foot.position if session.mode == GameSession.Mode.OUTSIDE else _flown().position
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
		if terrain != null and terrain_scale < 1.0: # the shell shrinks with the terrain so the glow stays on the planet's edge
			shell_centre = terrain.view_position + (shell_centre - terrain.view_position) * terrain_scale
		var shell_radius := planet.radius * terrain_scale
		var shell_height := planet.atmosphere_height * terrain_scale
		if not atmosphere_shell.update_rodina(shell_radius, shell_height, shell_centre, sun_direction, _star_radius_angle(runtime.active_frame), home_look.rodina_atmosphere if VisualStyle.is_rodina() else {}):
			atmosphere_shell.update_shell(shell_radius + shell_height * 1.6, shell_centre, sun_direction, home_look.rim_color, home_look.rim_power, home_look.rim_haze)
	space_environment.ambient_scale = VisualStyle.interior_ambient_factor() if session.mode == GameSession.Mode.INSIDE else 1.0
	if planet != null:
		var atmosphere_ratio := planet.atmosphere_ratio(actor_position)
		var daylight := 1.0 - smoothstep(0.0, 1.0, atmosphere_ratio) if atmosphere_ratio != INF else 0.0
		var sun_above_horizon := smoothstep(-0.1, 0.3, planet.up_at(actor_position).dot(-sun_direction))
		impostors.hide_star = VisualStyle.is_rodina() and daylight > 0.02
		space_environment.set_sun_elevation(planet.up_at(actor_position).dot(-sun_direction), daylight)
		var viewer_up := planet.up_at(actor_position)
		space_environment.set_rodina_viewer(VisualStyle.is_rodina() and planet.atmosphere_height > 0.0, viewer_up * (planet.distance_from_center(actor_position) / planet.radius), planet.atmosphere_height / maxf(planet.radius, 1.0), _star_radius_angle(runtime.active_frame))
		var viewer_altitude := 2.0 if session.mode == GameSession.Mode.OUTSIDE else _flown().state.altitude_above_ground
		space_environment.set_daylight(daylight * sun_above_horizon, planet.up_at(actor_position), 0.0 if session.mode == GameSession.Mode.OUTSIDE else _flown().state.altitude_above_ground)
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
	if big_ship_menu != null and big_ship_menu.visible:
		return # the big ships list and the walkable view handle their own keys
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
	if hangar_menu.visible:
		return # the hangar closes itself (Esc or Y)
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
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Y and (session.mode == GameSession.Mode.SEATED or session.mode == GameSession.Mode.OUTSIDE or session.mode == GameSession.Mode.FIGHTER) and not session.gunner_station:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		hangar_menu.in_fighter_form = session.mode == GameSession.Mode.FIGHTER
		hangar_menu.open()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_B and (session.mode == GameSession.Mode.SEATED or session.mode == GameSession.Mode.FIGHTER):
		if enemy_director != null: # skirmish mode: needs a planet frame, like every encounter (see EnemyDirector.spawn_skirmish)
			enemy_director.spawn_skirmish()
		else:
			session.say("No fighters out here: skirmishes need a planet's space")
		return
	if event.is_action_pressed("journal"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		exploration_menu.open()
		return
	if event.is_action_pressed("inventory"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		inventory_menu.open()
		return
	if _screen_focus and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_TAB and _fighter_node != null and _fighter_node.cockpit != null:
		session.say(_fighter_node.cockpit.swap_focus()) # Tab: the other cockpit screen
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
				elif _screen_focus and _fighter_node != null and _fighter_node.cockpit != null:
					_fighter_node.cockpit.move_focus_pointer(event.relative)
				elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
					var zoomed_rate := 0.004 * clampf(1.0 + _fighter_zoom_fov / 45.0, 0.5, 1.0) # finer aim the further it is zoomed in
					_look_yaw = wrapf(_look_yaw - event.relative.x * zoomed_rate, -PI, PI)
					_look_pitch = clampf(_look_pitch - event.relative.y * zoomed_rate, -1.3, 1.3)
				else:
					player_source.add_mouse_motion(event.relative)
	elif session.gunner_station and event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var step := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0
		_turret_zoom = clampf(_turret_zoom + step * maxf(1.0, _turret_zoom * 0.12), 1.5, 80.0)
	elif _screen_focus and session.mode == GameSession.Mode.FIGHTER and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cockpit := _fighter_node.cockpit # left click presses the control under the pointer while the right button holds the zoom
		if cockpit != null and cockpit.focus_hover() != "":
			var told := cockpit.activate()
			if told != "":
				session.say(told)
		get_viewport().set_input_as_handled()
	elif _screen_focus and session.mode == GameSession.Mode.FIGHTER and event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_leave_screen_focus() # letting go of the right button lets go of the zoom: the view eases back
	elif session.mode == GameSession.Mode.FIGHTER and event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_MIDDLE):
		if _screen_focus:
			if event.button_index == MOUSE_BUTTON_MIDDLE:
				session.say(_fighter_node.cockpit.swap_focus()) # middle click: the other cockpit screen
			else:
				_screen_zoom = clampf(_screen_zoom * (1.12 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else 0.89), 0.4, 1.8)
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
	elif event.is_action_pressed("clutch") and (session.mode == GameSession.Mode.INSIDE or session.mode == GameSession.Mode.OUTSIDE):
		_gait = 2 if _gait == 1 else 1
		session.say("Running" if _gait == 2 else "Walking")
	elif event.is_action_pressed("toggle_view"):
		if session.mode == GameSession.Mode.OUTSIDE:
			on_foot.third_person = not on_foot.third_person
		elif session.mode == GameSession.Mode.INSIDE:
			interior_view.third_person = not interior_view.third_person
		elif session.mode == GameSession.Mode.FIGHTER:
			if _fighter_node != null and _fighter_node.cockpit_camera != null: # a big ship has no cockpit view
				_fighter_cockpit_view = not _fighter_cockpit_view
			_update_active_camera()
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
	_retarget()
	if session.mode == GameSession.Mode.OUTSIDE:
		on_foot.render_origin = ship.render_origin.duplicate_position()
	on_foot.sync_transform()
	on_foot.reset_physics_interpolation()
	if session.mode == GameSession.Mode.SEATED or session.mode == GameSession.Mode.FIGHTER:
		chase_camera.snap_to_target()
	_update_active_camera()


## Where a big ship's interior hangs in the real world while it is explored: just off the flown ship, turned so the bridge window looks out over the planet
## (the planet a little below the horizon, so it fills the lower part of the glass); in open space, simply along the ship's own heading.
func _bridge_view_anchor() -> Transform3D:
	var flown := _flown()
	var basis := flown.global_transform.basis.orthonormalized()
	var here := flown.global_position
	if planet != null and terrain != null:
		var centre := WorldPos.new(planet.frame_id, 0.0, 0.0, 0.0).to_local_vector3(terrain.render_origin)
		var to_planet := (centre - here).normalized()
		if to_planet.length() > 0.5:
			var heading := (-basis.z - to_planet * (-basis.z).dot(to_planet))
			if heading.length() < 0.1:
				heading = basis.x
			var nose := (to_planet * 0.3 + heading.normalized() * 0.95).normalized()
			var up := -to_planet
			var look := Basis.looking_at(nose, up)
			return Transform3D(look, here - to_planet * 120.0 - nose * 40.0)
	return flown.global_transform.translated_local(Vector3(0.0, 120.0, 0.0))


## Whatever the player is flying: the mothership, or the separate fighter.
func _flown() -> Ship:
	return session.active_ship()


## For the chase camera: height of a point (render space) above the terrain under it, and the planet's up there. Far from the ground the
## answer is "plenty", so nothing is looked up in flight.
func _camera_ground_clearance(camera_position: Vector3) -> Vector4:
	var flown := _flown()
	if flown == null or planet == null or flown.state.altitude_above_ground > 1500.0:
		return Vector4(INF, 0.0, 1.0, 0.0)
	var offset := camera_position - flown.global_position
	var x := flown.state.position.x + offset.x
	var y := flown.state.position.y + offset.y
	var z := flown.state.position.z + offset.z
	var distance := sqrt(x * x + y * y + z * z)
	if distance < 1.0:
		return Vector4(INF, 0.0, 1.0, 0.0)
	var up := Vector3(x, y, z) / distance
	return Vector4(distance - planet.surface_radius_xyz(up.x, up.y, up.z), up.x, up.y, up.z)


## Points the camera, anchor, HUD, effects and audio at the ship the player is flying now.
func _retarget() -> void:
	var flown := _flown()
	floating_origin.anchor = on_foot if session.mode == GameSession.Mode.OUTSIDE else flown
	chase_camera.target = flown
	chase_camera.view_scale = maxf(0.45, flown.fighter.size / FighterDef.REFERENCE_SIZE) if flown.fighter != null else 1.0
	chase_camera.rigid_follow = flown.fighter != null # a fighter's camera is pinned to the hull; the mothership's swings in turns
	speed_effects.ship = flown
	entry_effects.ship = flown
	overlay.ship = flown
	audio.ship = flown


## Keeps the fighter's scene node in step with the session: freed when the session lets go of it, lost when destroyed.
func _sync_fighter() -> void:
	if session.mode == GameSession.Mode.FIGHTER and session.fighter_craft != null and session.fighter_craft.state.hull <= 0.0:
		session.say("The %s was destroyed" % session.fighter_craft.fighter.display_name)
		session.lose_fighter()
		_on_mode_changed()
		_begin_camera_blend(GameSession.Mode.FIGHTER)
	if _fighter_node != null and _fighter_node != session.fighter_craft:
		_fighter_node.queue_free()
		_fighter_node = null


func _update_active_camera() -> void:
	# In the fighter's cockpit view its outer hull is hidden: the camera sits inside that hull, and the hull's nose and canopy would cover the interior.
	if _fighter_node != null and is_instance_valid(_fighter_node) and _fighter_node.model_holder != null:
		_fighter_node.model_holder.visible = not (session.mode == GameSession.Mode.FIGHTER and _fighter_cockpit_view and not session.gunner_station and _fighter_node.cockpit_camera != null)
	match session.mode:
		GameSession.Mode.OUTSIDE:
			on_foot.camera.current = true
		GameSession.Mode.INSIDE:
			interior_view.camera.current = true
		_:
			if session.gunner_station:
				turret_camera.current = true
			elif session.mode == GameSession.Mode.FIGHTER and _fighter_node != null and _fighter_node.cockpit_camera != null and _fighter_cockpit_view:
				_fighter_node.cockpit_camera.cull_mask = chase_camera.cull_mask & ~FighterCockpit.LAYER_MASK # the cockpit itself: CockpitOverlay
				_fighter_node.cockpit_camera.current = true
			elif _cockpit_view and session.mode != GameSession.Mode.FIGHTER:
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
	session.abandon_fighter() # the fighter is not saved: loading puts you back where you boarded from
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
	var new_origin := _flown().state.position.duplicate_position()
	ship.render_origin = new_origin.duplicate_position()
	ship.apply_origin_shift(Vector3.ZERO)
	if session.fighter_craft != null:
		session.fighter_craft.render_origin = new_origin.duplicate_position()
		session.fighter_craft.apply_origin_shift(Vector3.ZERO)
	if terrain != null:
		terrain.render_origin = new_origin.duplicate_position()
		terrain.apply_origin_shift(Vector3.ZERO)
	if poi_manager != null:
		poi_manager.render_origin = new_origin.duplicate_position()
		poi_manager.apply_origin_shift(Vector3.ZERO)
	projectile_view.render_origin = new_origin.duplicate_position()
	combat_effects.render_origin = new_origin.duplicate_position() # hit flashes asserted "different frames" after a world change
	if enemy_director != null:
		enemy_director.render_origin = new_origin.duplicate_position()
	on_foot.planet = planet
	on_foot.render_origin = new_origin.duplicate_position()


## Hangar: the player's ship becomes the chosen fighter (hull, fuel and position carry over).
func _on_fighter_spawn(def: FighterDef) -> void:
	if session.mode != GameSession.Mode.SEATED and session.mode != GameSession.Mode.OUTSIDE and session.mode != GameSession.Mode.FIGHTER:
		return
	var craft := Ship.new()
	craft.name = "Fighter_%s" % String(def.id)
	craft.planet = planet
	craft.free_space = runtime.navigator if planet == null else null
	craft.player_controlled = true
	craft.auto_tick = false # ticked from _physics_process so the chase camera never reads it a tick late
	craft.configure_fighter(def)
	craft.radar_contacts = func() -> Array: # the cockpit radar: every live hostile ship, as an offset in the fighter's own frame
		var contacts: Array = []
		for target in session.enemy_targets:
			if target is ShipCombatant and (target as ShipCombatant).is_alive():
				var offset := ((target as ShipCombatant).combat_position() as WorldPos).vector_from(craft.state.position)
				contacts.append(craft.state.basis.transposed() * offset)
		return contacts
	craft.render_origin = ship.render_origin.duplicate_position()
	var from_state := _flown().state if session.mode != GameSession.Mode.OUTSIDE else ship.state
	var up_from := session.exterior_body.position if session.mode == GameSession.Mode.OUTSIDE else from_state.position
	var up := planet.up_at(up_from) if planet != null else from_state.basis.y
	if session.mode == GameSession.Mode.OUTSIDE:
		# beside the walker, hovering, nose where the walker is looking
		var heading := (-on_foot.camera.global_transform.basis.z * Vector3(1, 0, 1))
		heading = heading.normalized() if heading.length() > 0.01 else -from_state.basis.z
		var ahead := session.exterior_body.position.offset_by(heading * (def.size + 6.0) + up * 3.0)
		craft.state.position = ahead
		craft.state.basis = Basis.looking_at(heading, up)
		craft.state.gear = PilotCommand.GEAR_DOCK
		craft.state.selected_gear = PilotCommand.GEAR_DOCK
	else:
		var forward := -from_state.basis.z
		craft.state.position = from_state.position.offset_by(forward * maxf(45.0, def.size * 1.2) + from_state.basis.y * 6.0)
		craft.state.basis = from_state.basis
		craft.state.velocity = from_state.velocity
		# A fighter is for flying and shooting: it starts in the combat gear (guns work there) unless the mothership is already in
		# cruise. From the ground it is put higher up, since the combat gear does not hover by itself.
		craft.state.gear = PilotCommand.GEAR_CRUISE if from_state.gear == PilotCommand.GEAR_CRUISE else PilotCommand.GEAR_COMBAT
		craft.state.selected_gear = craft.state.gear
		if from_state.landed:
			craft.state.position = from_state.position.offset_by(forward * 45.0 + from_state.basis.y * 30.0)
	craft.state.fuel = 1.0
	craft.state.hull = 1.0
	if _fighter_node != null: # a fighter already out there is replaced
		if session.mode == GameSession.Mode.FIGHTER:
			session.return_to_mothership() # releases it; the next sync frees the node
		_fighter_node.queue_free()
		_fighter_node = null
		session.fighter_craft = null
	add_child(craft)
	_fighter_node = craft
	var mode_before := session.mode
	session.board_fighter(craft)
	_fighter_cockpit_view = not def.is_big_ship # a fighter starts in its cockpit; a big ship has none
	_begin_camera_blend(mode_before)
	_on_mode_changed()
	session.say("Flying the %s - Y for the hangar" % def.display_name if def.is_big_ship else "Flying the %s - V for the chase view, Y for the hangar" % def.display_name)


## Captain's seat > F: the big ship becomes the craft the player flies (a Ship built like a fighter, but with the ship's own hull, no cockpit and a slow heavy feel).
func _on_big_ship_fly(ship_def) -> void:
	var def := FighterDef.new()
	def.id = StringName("big_" + str(ship_def.id))
	def.display_name = str(ship_def.display_name)
	def.model_path = str(ship_def.hull_path)
	def.size = float(ship_def.hull_extent)
	def.is_big_ship = true
	def.hull_yaw = float(ship_def.hull_yaw)
	def.hull_color = Color(ship_def.accent)
	def.role = FighterDef.Role.HEAVY
	var fast := str(ship_def.speed_class) == "Fast"
	var slow := str(ship_def.speed_class) == "Slow"
	def.speed_scale = 0.9 if fast else (0.45 if slow else 0.65)
	def.turn_scale = 0.35 if fast else (0.15 if slow else 0.22)
	def.toughness = maxf(3.0, def.size / 12.0)
	def.gun_damage = 0.02
	def.gun_rate = 3.0
	def.cockpit = Vector3.ZERO
	def.engines = ship_def.engines.duplicate()
	def.engine_radii = ship_def.engine_radii.duplicate()
	def.blurb = str(ship_def.blurb)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_on_fighter_spawn(def)


## Y > Return: back to where the player boarded (the helm, or on foot). A fighter in the air is gone; one on the ground stays.
func _on_fighter_recall() -> void:
	session.return_to_mothership()
	_sync_fighter()
	_on_mode_changed()
	session.say("Back at the %s" % ("helm" if session.mode == GameSession.Mode.SEATED else "spot you took off from"))


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
	var holding := session.mode == GameSession.Mode.FIGHTER and not _screen_focus and not session.gunner_station and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	_fighter_zoom_fov = lerpf(_fighter_zoom_fov, FIGHTER_HOLD_ZOOM if holding else 0.0, 0.2) # zoom in while the button is held; it snaps back on release
	var fov := VisualStyle.base_field_of_view(GameSettings.instance().field_of_view)
	for camera in [interior_view.camera, on_foot.camera]:
		(camera as Camera3D).fov = fov
	# Rodina sets the camera FOV from the warp blend (EGDataShipPlayer.lua:325-346); at rest it is the setting.
	var ship_fov := warp_view.field_of_view(fov) if VisualStyle.is_rodina() else fov
	chase_camera.fov = clampf(ship_fov + _fighter_zoom_fov, 35.0, 120.0) if session.mode == GameSession.Mode.FIGHTER else ship_fov
	cockpit_camera.fov = minf(ship_fov + 18.0, 120.0) # wider inside the canopy so more of the windscreen is in view
	if _fighter_node != null and _fighter_node.cockpit_camera != null:
		var wanted_fov := clampf(ship_fov + 12.0 + _fighter_zoom_fov, 35.0, 120.0) # wider than the base so more of the world is in view; holding the right mouse button zooms in
		if _screen_focus and _fighter_node.cockpit != null:
			wanted_fov = _fighter_node.cockpit.focus_fov() * _screen_zoom # zoomed in on the focused screen
		_screen_fov = wanted_fov if _screen_fov <= 0.0 else lerpf(_screen_fov, wanted_fov, 0.18)
		_fighter_node.cockpit_camera.fov = _screen_fov
	turret_camera.fov = ship_fov


## Back to the normal cockpit view.
func _leave_screen_focus() -> void:
	_screen_focus = false
	_screen_zoom = 1.0
	_leave_blocks_entry = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if _fighter_node != null and _fighter_node.cockpit != null:
		_fighter_node.cockpit.end_focus()
	player_source.ignore_clutch = false


## Advances the Rodina warp/speed camera from the ship's real state and hands it to the ship cameras. In the sol style
## it runs nothing and leaves both cameras at rest.
func _update_warp_view(delta: float) -> void:
	if not VisualStyle.is_rodina():
		if warp_view.spacewarp != 0.0 or warp_view.limnal_timer != 0.0 or warp_view.shake != Vector2.ZERO:
			warp_view.reset()
	else:
		var state := _flown().state
		var fired := session.gunner_station and session.systems.turret.firing # only real shots shake the view; the pilot's click fires nothing
		warp_view.update(state.gear == PilotCommand.GEAR_WARP, state.atmosphere_resistance, fired, delta)
	var rodina := VisualStyle.is_rodina()
	chase_camera.follow_distance = warp_view.follow_distance() * RodinaEmitter.SHIP_SCALE if rodina else 0.0
	chase_camera.follow_angle = deg_to_rad(warp_view.follow_angle_degrees()) if rodina else 0.0
	var over_pad := session.mode == GameSession.Mode.FIGHTER and _fighter_cockpit_view and not _screen_focus and not session.gunner_station and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and _fighter_node != null and _fighter_node.cockpit != null and _fighter_node.cockpit.pointed_screen() >= 0
	_pad_hover = _pad_hover + delta if over_pad else 0.0
	if _pad_hover > 0.12:
		_pad_hover = 0.0
		_screen_focus = true # right button held with the reticle on a screen: the view eases in on it, and eases back when the button is released
		_fighter_node.cockpit.begin_focus()
	if _screen_focus or not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or session.gunner_station:
		var settle := 1.0 - exp(-8.0 * delta) # the view swings back behind the ship when free look is released (or onto the focused screen)
		var look_target := _fighter_node.cockpit.focus_look() if _screen_focus and _fighter_node != null and _fighter_node.cockpit != null else Vector2.ZERO
		_look_yaw = lerpf(_look_yaw, look_target.x, settle)
		_look_pitch = lerpf(_look_pitch, look_target.y, settle)
	chase_camera.look_yaw = _look_yaw
	chase_camera.look_pitch = _look_pitch
	chase_camera.shake = warp_view.shake
	cockpit_camera.rotation = Vector3(warp_view.shake.y + _look_pitch, warp_view.shake.x + _look_yaw, 0.0)
	if _fighter_node != null and _fighter_node.cockpit_camera != null:
		_fighter_node.cockpit_camera.rotation = Vector3(warp_view.shake.y + _look_pitch, warp_view.shake.x + _look_yaw, 0.0) # right mouse looks round the cockpit
		if _fighter_node.cockpit != null:
			_fighter_node.cockpit.pointer_enabled = session.mode == GameSession.Mode.FIGHTER and _fighter_cockpit_view and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if _fighter_node != null and _fighter_node.effects != null:
		_fighter_node.effects.limnal_activation = warp_view.activation
		_fighter_node.effects.camera_inside = session.mode == GameSession.Mode.FIGHTER and _fighter_cockpit_view
	if _fighter_node != null and _fighter_node.model_holder != null:
		_fighter_node.model_holder.visible = not (session.mode == GameSession.Mode.FIGHTER and _fighter_cockpit_view and not session.gunner_station and _fighter_node.cockpit_camera != null)
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
			if _fighter_node != null and _fighter_node.cockpit_camera != null:
				_fighter_node.cockpit_camera.cull_mask = outside_mask & ~FighterCockpit.LAYER_MASK # the fighter's own cockpit sits on its own layer, drawn by CockpitOverlay
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
