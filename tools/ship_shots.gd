extends SceneTree
## Ship look-development photos (needs a display, not --headless):
##   godot --path . -s res://tools/ship_shots.gd -- out_dir [only_view_name]
## Boots main.tscn, lands the ship, steps the player out (third person, so the avatar stands
## beside the hull for scale) and saves one picture per view below from a free camera placed in
## ship-local metres (nose -z, right +x, up +y; the gear feet are at y = -2.0). The ramp is
## photographed deployed and stowed. The gameplay chase view is a separate run of screenshot.gd.

## name -> [camera position, look-at point, field of view, ramp deployed]
const VIEWS := {
	"01_front_three_quarter": [Vector3(-13.0, 3.5, -17.0), Vector3(0.0, -0.2, 0.5), 50.0, true],
	"02_rear_three_quarter": [Vector3(13.0, 4.5, 24.0), Vector3(0.0, -0.2, 2.5), 50.0, true],
	"03_side_profile": [Vector3(-34.0, 0.0, 1.8), Vector3(0.0, 0.0, 1.8), 36.0, false],
	"04_top_down": [Vector3(0.0, 38.0, 1.8), Vector3(0.0, 0.0, 1.8), 40.0, false],
	"05_low_angle": [Vector3(7.5, -1.55, -13.0), Vector3(0.0, 0.3, 1.0), 55.0, true],
	"06_beside_player": [Vector3(10.0, -0.6, -8.0), Vector3(2.5, -0.6, 0.0), 50.0, true],
	"07_ramp_deployed": [Vector3(5.5, 0.2, 21.0), Vector3(0.0, -1.0, 11.5), 50.0, true],
	"08_ramp_stowed": [Vector3(5.5, 0.2, 21.0), Vector3(0.0, -1.0, 11.5), 50.0, false],
	"09_front": [Vector3(0.0, 0.0, -26.0), Vector3(0.0, 0.0, 0.0), 42.0, false],
	"10_rear": [Vector3(0.0, 0.5, 30.0), Vector3(0.0, 0.0, 4.0), 42.0, false],
	"11_far_three_quarter": [Vector3(-26.0, 9.0, -30.0), Vector3(0.0, 0.0, 1.5), 40.0, false],
	# ChaseCamera.offset_behind_up (0, 3.4, 17) looking 40 m ahead, with the game camera's field of view (-1 = use it).
	"12_gameplay_chase": [Vector3(0.0, 3.4, 17.0), Vector3(0.0, 0.0, -40.0), -1.0, false],
	# CockpitCamera position (pilot's eyes) looking straight ahead through the window band.
	"13_pilot_view": [Vector3(0.0, 0.6, -5.3), Vector3(0.0, 0.3, -40.0), -2.0, false],
	# Flight pose: pods level, ramp stowed (forced while parked; in play the pods level out above 80 m or 30 m/s).
	"14_flight_pose": [Vector3(-14.0, 4.5, -16.0), Vector3(0.0, 0.2, 1.0), 50.0, false],
	"15_flight_pose_side": [Vector3(-34.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0), 36.0, false],
}

var _main: Node
var _frames := 0
var _settled_frames := 0
var _stage := 0
var _stage_frame := 0
var _camera := Camera3D.new()
var _view_names: Array = []
var _view_index := 0
const SMALL := Vector2i(320, 180)
const LARGE := Vector2i(1280, 720)


func _initialize() -> void:
	root.size = SMALL # software rendering cost follows pixel count: run the landing small, photograph large
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	var only := OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else ""
	for view_name in VIEWS:
		if only == "" or (view_name as String).contains(only):
			_view_names.append(view_name)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_main.menu.dismiss()
		_lift_ship(4.0)
	if _frames > 2:
		_settled_frames = _settled_frames + 1 if _main.terrain.is_settled() else 0
	if _frames % 10 == 0:
		_log("frame ", _frames, " stage ", _stage, " landed ", _main.ship.state.landed, " agl %.1f" % _main.ship.state.altitude_above_ground, " settled ", _settled_frames)
	match _stage:
		0:
			Input.action_press("move_down")
			if _main.ship.state.landed and _settled_frames > 30:
				Input.action_release("move_down")
				_stage = 1
		1:
			if _frames > 2:
				_step_out()
				_stage = 2
				_stage_frame = _frames
		2:
			if _frames > _stage_frame + 10:
				_stage = 3
		3:
			if _view_index >= _view_names.size():
				_log("ship_shots done, landed ", _main.ship.state.landed, " ramp_end_y ", _main.session.systems.layout.ramp_end_y)
				quit()
				return false
			_set_view(_view_names[_view_index])
			_stage = 4
			_stage_frame = _frames
		4:
			if _frames > _stage_frame + 2: # the ramp is set directly (no animation); two frames let shadows settle
				_save(_view_names[_view_index])
				_view_index += 1
				_stage = 3
	return false


func _lift_ship(altitude: float) -> void:
	var ship: Ship = _main.ship
	var planet: PlanetBody = _main.planet
	var up := planet.up_at(ship.state.position)
	var ground_radius := planet.surface_radius_xyz(up.x, up.y, up.z)
	var target_radius := ground_radius + altitude
	ship.state.position = WorldPos.new(planet.frame_id, up.x * target_radius, up.y * target_radius, up.z * target_radius)
	ship.render_origin = ship.state.position.duplicate_position()
	ship.position = Vector3.ZERO
	var forward := (Vector3.UP.cross(up).cross(up)).normalized()
	ship.state.basis = Basis.looking_at(forward, up)
	ship.state.velocity = Vector3.ZERO
	_main.terrain.render_origin = ship.render_origin.duplicate_position()
	_main.chase_camera.snap_to_target()


func _step_out() -> void:
	var session: GameSession = _main.session
	session.interact() # stand up from the pilot seat
	var systems := session.systems
	systems.airlock.outer.target_open = true
	systems.airlock.outer.open_factor = 1.0
	_set_ramp(true)
	var ship_state: ShipState = session.ship.state
	# The avatar stands beside the forward gear on the right side, facing the hull.
	session.exterior_body.place_on_ground(session.planet, ship_state.position.offset_by(ship_state.basis * Vector3(4.6, 0.0, -1.5)), -ship_state.basis.x)
	session.restore_mode(GameSession.Mode.OUTSIDE)
	_main.on_foot.third_person = true
	_main._on_mode_changed()
	if _main.overlay != null:
		_main.overlay.visible = false
	root.add_child(_camera)


func _set_ramp(deployed: bool) -> void:
	var session: GameSession = _main.session
	var systems := session.systems
	systems.walkway.state = WalkwayController.State.DEPLOYED if deployed else WalkwayController.State.STOWED
	systems.walkway.progress = 1.0 if deployed else 0.0
	systems.layout.ramp_walkable = deployed
	systems.airlock.outer.target_open = deployed
	systems.airlock.outer.open_factor = 1.0 if deployed else 0.0
	session._fit_ramp_to_ground()


func _set_view(view_name: String) -> void:
	var view: Array = VIEWS[view_name]
	_set_ramp(view[3])
	for child in _main.ship.get_children():
		if child is ShipVisuals:
			(child as ShipVisuals).force_pods_level = view_name.contains("flight_pose")
	var ship: Ship = _main.ship
	var eye: Vector3 = view[0]
	var target: Vector3 = view[1]
	var up := Vector3.UP if absf((target - eye).normalized().y) < 0.99 else Vector3.FORWARD
	var local := Transform3D(Basis.looking_at(target - eye, up), eye)
	_camera.global_transform = ship.global_transform * local
	var fov: float = view[2]
	if fov == -1.0:
		fov = _main.chase_camera.fov
	elif fov == -2.0:
		fov = _main.cockpit_camera.fov
	_camera.fov = fov
	_camera.near = 0.1
	_camera.far = 20000.0
	_camera.current = true
	root.size = LARGE


func _save(view_name: String) -> void:
	await RenderingServer.frame_post_draw
	var out_dir: String = OS.get_cmdline_user_args()[0]
	var path := out_dir.path_join(view_name + ".png")
	root.get_viewport().get_texture().get_image().save_png(path)
	_log("saved ", path)


## Progress goes straight to a file: Godot buffers stdout until exit, which hides a slow software-rendered run.
func _log(a: Variant = "", b: Variant = "", c: Variant = "", d: Variant = "", e: Variant = "", f: Variant = "", g: Variant = "", h: Variant = "", i: Variant = "", j: Variant = "", k: Variant = "", l: Variant = "") -> void:
	var line := "".join([str(a), str(b), str(c), str(d), str(e), str(f), str(g), str(h), str(i), str(j), str(k), str(l)])
	var path: String = OS.get_cmdline_user_args()[0].path_join("progress.log")
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(line)
		file.close()
	print(line)
