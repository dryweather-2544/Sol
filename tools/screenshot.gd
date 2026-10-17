extends SceneTree
## Visual smoke check (needs a display, not --headless):
##   godot --path . -s res://tools/screenshot.gd -- out.png [altitude_m] [pitch_deg_down] [mode] [x] [z] [yaw_deg]
## Boots main.tscn, moves the ship to the given altitude above its start point (altitude 0 or
## less = leave it in orbit), waits for the terrain, then saves the viewport. Modes:
##   (none)   chase-camera view
##   cockpit  cockpit camera view
##   inside   land, stand up, put the player at ship-local (x, z) facing yaw_deg, interior view
##   outside  land, walk out through the airlock instantly, outside first-person view
##   poi      (args: out altitude pitch poi type_index) hover above the nearest POI of that type
## Chunk loading is awaited, so the picture is what the player sees once the world has loaded.

var _frames := 0
var _main: Node
var _settled_frames := 0
var _stage := 0
var _stage_frame := 0


func _initialize() -> void:
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
		elif arguments.size() > 5:
			var yaw := deg_to_rad(float(arguments[6])) if arguments.size() > 6 else 0.0
			_main.session.interior_body.place(Vector3(float(arguments[4]), -0.9, float(arguments[5])), yaw)
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
	var offset := side * 90.0
	ship.state.position = WorldPos.new(planet.frame_id, poi_up.x * target_radius + offset.x, poi_up.y * target_radius + offset.y, poi_up.z * target_radius + offset.z)
	ship.render_origin = ship.state.position.duplicate_position()
	ship.position = Vector3.ZERO
	var look := Vector3(best.position.x - ship.state.position.x, best.position.y - ship.state.position.y, best.position.z - ship.state.position.z).normalized()
	ship.state.basis = Basis.looking_at(look, poi_up)
	ship.state.velocity = Vector3.ZERO
	_main.terrain.render_origin = ship.render_origin.duplicate_position()
	_main.poi_manager.render_origin = ship.render_origin.duplicate_position()
	_main.poi_manager.viewer = ship.state.position
	_main.poi_manager.apply_origin_shift(Vector3.ZERO)
	_main.chase_camera.snap_to_target()
	print("moved to ", best.display_name)
