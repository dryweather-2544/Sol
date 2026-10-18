extends SceneTree
## Visual smoke check (needs a display, not --headless):
##   godot --path . -s res://tools/screenshot.gd -- out.png [altitude_m] [pitch_deg_down] [mode] [x] [z] [yaw_deg]
## Boots main.tscn, moves the ship to the given altitude above its start point (altitude 0 or
## less = leave it in orbit), waits for the terrain, then saves the viewport. Modes:
##   (none)   chase-camera view
##   cockpit  cockpit camera view
##   inside   land, stand up, put the player at ship-local (x, z) facing yaw_deg, interior view
##            (optional 8th argument: fire = engineering on fire, reactor = reactor panel open)
##   outside  land, walk out through the airlock instantly, outside first-person view
##   poi      (args: out altitude pitch poi type_index [side_offset_m [yaw_away_deg]]) hover above the nearest POI of that type
## Chunk loading is awaited, so the picture is what the player sees once the world has loaded.

var _frames := 0
var _main: Node
var _settled_frames := 0
var _stage := 0
var _stage_frame := 0


func _initialize() -> void:
	if OS.get_environment("SOL_ASSETS") == "off": # N9 tooling: measure/photograph the placeholder look with the same build
		var settings := GameSettings.instance()
		settings.asset_materials = false
		settings.decals = false
		settings.terrain_detail = false
		settings.starfield = false
		settings.sample_audio = false
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _args() -> PackedStringArray:
	return OS.get_cmdline_user_args()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2 and not (OS.get_cmdline_user_args().size() > 0 and OS.get_cmdline_user_args()[0].ends_with("menu_title.png")):
		_main.menu.dismiss() # skip the title screen
	var arguments := _args()
	var mode := arguments[3] if arguments.size() > 3 else ""
	if _frames == 2:
		_move_ship()
	if mode == "depot" and _frames == 3:
		_move_to_poi(2) # teleport the ship beside the nearest outpost so its POI is planned and streamed
	if mode == "third" and _frames == 3:
		pass
	if mode == "depot" and _frames == 150:
		_stand_in_depot(arguments[4] if arguments.size() > 4 else "6")
	if mode == "poi" and _frames == 3:
		_move_to_poi(int(arguments[4]) if arguments.size() > 4 else 0)
	if _frames > 2:
		_settled_frames = _settled_frames + 1 if _main.terrain.is_settled() else 0
	var wants_ground_mode := mode == "inside" or mode == "outside"
	if wants_ground_mode and _stage == 0:
		Input.action_press("move_down")
		if _main.ship.state.landed and _settled_frames > 30:
			Input.action_release("move_down")
			_stage = 1
			_stage_frame = _frames
		return false
	if wants_ground_mode and _stage == 1:
		_main.session.interact() # stand up
		_main.session.interior_body.place(Vector3(0, -0.9, -4.0), 0.0)
		if mode == "outside":
			_open_airlock_instantly()
			if arguments.size() > 4:
				var session: GameSession = _main.session
				session.exterior_body.place_on_ground(session.planet, session.ship.state.position.offset_by(session.ship.state.basis.x * 14.0 + session.ship.state.basis.z * 6.0), -session.ship.state.basis.x)
				session.restore_mode(GameSession.Mode.OUTSIDE)
				_main.on_foot.third_person = arguments[4] == "third"
		elif arguments.size() > 5:
			var yaw := deg_to_rad(float(arguments[6])) if arguments.size() > 6 else 0.0
			_main.session.interior_body.place(Vector3(float(arguments[4]), -0.9, float(arguments[5])), yaw)
		var extra := arguments[7] if arguments.size() > 7 else ""
		if extra == "fire": # 8th argument: start a fire in engineering
			_main.session.systems.hazards.ignite(&"engineering")
			_main.session.systems.hazards.fire[&"engineering"] = 0.8
		elif extra == "reactor": # 8th argument: open the reactor panel
			_main.session.systems.power.temperature = 0.62
			_main.reactor_menu.open()
		_main._on_mode_changed()
		_stage = 2
		_stage_frame = _frames
		return false
	if mode == "cockpit" and _stage == 0:
		_main._cockpit_view = true
		_main._update_active_camera()
		_stage = 2
		_stage_frame = _frames
	if _stage == 2 and _frames < _stage_frame + 90:
		return false
	if mode == "depot" and _frames < 260:
		return false
	if mode == "poi" and _frames < 200:
		return false
	if _settled_frames > 30 and _frames < 90 and OS.get_cmdline_user_args()[0].ends_with("menu_title.png"):
		pass
	if _settled_frames > 30 or _frames > 2400:
		var output_path: String = arguments[0] if arguments.size() > 0 else "screenshot.png"
		root.get_viewport().get_texture().get_image().save_png(output_path)
		print("saved ", output_path, " frames ", _frames, " chunks ", _main.terrain.displayed_chunk_count(), " settled ", _main.terrain.is_settled(), " agl ", _main.ship.state.altitude_above_ground, " mode ", _main.session.mode, " landed ", _main.ship.state.landed)
		quit()
	return false


func _open_airlock_instantly() -> void:
	var session: GameSession = _main.session
	var systems := session.systems
	for portal in systems.layout.portals.values():
		(portal as Portal).open_factor = 0.0
	systems.airlock.outer.target_open = true
	systems.airlock.outer.open_factor = 1.0
	systems.walkway.state = WalkwayController.State.DEPLOYED
	systems.walkway.progress = 1.0
	systems.layout.ramp_walkable = true
	session._fit_ramp_to_ground()
	var ramp := systems.layout.ramp_rect
	session.interior_body.place(Vector3(0, systems.layout.floor_height_at(0, ramp.end.y - 1.0), ramp.end.y - 1.0), 3.14159)


func _move_ship() -> void:
	var arguments := _args()
	if arguments.size() < 2 or float(arguments[1]) <= 0.0:
		return
	var ship: Ship = _main.ship
	var planet: PlanetBody = _main.planet
	var up := planet.up_at(ship.state.position)
	var ground_radius := planet.surface_radius_xyz(up.x, up.y, up.z)
	var target_radius := ground_radius + float(arguments[1])
	ship.state.position = WorldPos.new(planet.frame_id, up.x * target_radius, up.y * target_radius, up.z * target_radius)
	ship.render_origin = ship.state.position.duplicate_position()
	ship.position = Vector3.ZERO
	var pitch_down := deg_to_rad(float(arguments[2])) if arguments.size() > 2 else 0.0
	var forward := (Vector3.UP.cross(up).cross(up)).normalized()
	forward = forward.rotated(Vector3.UP.cross(up).normalized(), pitch_down) if pitch_down != 0.0 else forward
	ship.state.basis = Basis.looking_at(forward, up)
	ship.state.velocity = Vector3.ZERO
	_main.terrain.render_origin = ship.render_origin.duplicate_position()
	_main.chase_camera.snap_to_target()


func _move_to_poi(type_index: int) -> void:
	var ship: Ship = _main.ship
	var planet: PlanetBody = _main.planet
	var up := planet.up_at(ship.state.position)
	var ground := planet.surface_radius_xyz(up.x, up.y, up.z)
	var start_ground := WorldPos.new(planet.frame_id, up.x * ground, up.y * ground, up.z * ground)
	var best: PoiInstance
	for instance in _main.poi_manager.planner.plan_region(start_ground, 60000.0):
		if instance.type == type_index and (best == null or instance.position.distance_to(start_ground) < best.position.distance_to(start_ground)):
			best = instance
	if best == null:
		print("no POI of type ", type_index, " found")
		return
	var poi_up := Vector3(best.position.x, best.position.y, best.position.z).normalized()
	var target_radius := planet.distance_from_center(best.position) + float(_args()[1])
	var side := poi_up.cross(Vector3.RIGHT).normalized()
	# hover a little to the side of the POI, looking at it
	var offset := side * (float(_args()[5]) if _args().size() > 5 else 90.0)
	ship.state.position = WorldPos.new(planet.frame_id, poi_up.x * target_radius + offset.x, poi_up.y * target_radius + offset.y, poi_up.z * target_radius + offset.z)
	ship.render_origin = ship.state.position.duplicate_position()
	ship.position = Vector3.ZERO
	var look := Vector3(best.position.x - ship.state.position.x, best.position.y - ship.state.position.y, best.position.z - ship.state.position.z).normalized()
	if _args().size() > 6:
		look = look.rotated(poi_up, deg_to_rad(float(_args()[6]))) # optional yaw away from the POI so the ship does not hide it from the chase camera
	ship.state.basis = Basis.looking_at(look, poi_up)
	ship.state.velocity = Vector3.ZERO
	_main.terrain.render_origin = ship.render_origin.duplicate_position()
	_main.poi_manager.render_origin = ship.render_origin.duplicate_position()
	_main.poi_manager.viewer = ship.state.position
	_main.poi_manager.apply_origin_shift(Vector3.ZERO)
	_main.chase_camera.snap_to_target()
	print("moved to ", best.display_name)


## Put the player on foot at (0, z) in the nearest outpost depot's local frame, facing into the building.
func _stand_in_depot(z_text: String) -> void:
	var session: GameSession = _main.session
	var nearest: PoiInstance
	for instance in _main.poi_manager.known_instances():
		if instance.type == PoiDefinition.Type.OUTPOST and (nearest == null or instance.position.distance_to(session.ship.state.position) < nearest.position.distance_to(session.ship.state.position)):
			nearest = instance
	if nearest == null:
		print("no outpost known")
		return
	var frame := PoiBuilder.frame_basis(nearest)
	var spot := PoiBuilder.DEPOT_ORIGIN + Vector2(0.0, float(z_text))
	session.nearby_pois = _main.poi_manager.known_instances()
	var world := nearest.position.offset_by(frame.x * spot.x + frame.z * spot.y)
	session.exterior_body.place_on_ground(session.planet, world, -frame.z)
	session.restore_mode(GameSession.Mode.OUTSIDE)
	_main._on_mode_changed()
	print("standing at depot of ", nearest.display_name)
