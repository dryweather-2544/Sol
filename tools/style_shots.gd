extends SceneTree
## Visual-style comparison photos (needs a display, not --headless):
##   SOL_VISUAL_STYLE=rodina godot --path . -s res://tools/style_shots.gd -- out_dir [body_filter]
## Boots main.tscn, then for each world jumps the ship there (WorldRuntime.force_frame, as a save load does), holds it
## still at set altitudes with the sun about SUN_ELEVATION_DEGREES above the local horizon, and saves one picture per view
## from a free camera (ship hidden). Views: orbit (planet and limb), approach (high, along the horizon), low (low flight),
## ground (eye height by the landed ship, ship visible). Run once per style with the same arguments to compare.
## Progress goes to <out_dir>/progress.log (Godot buffers stdout until exit).

const SMALL := Vector2i(320, 180)
const LARGE := Vector2i(1280, 720)
const SUN_ELEVATION_DEGREES := 35.0
## [name, altitude metres (orbit: in planet radii), camera pitch below the horizon in degrees, ship visible]
const VIEWS := [["orbit", 1.4, 34.0, false], ["approach", 30000.0, 7.0, false], ["low", 900.0, 9.0, false], ["ground", 0.0, 2.0, true]]
## Frames to wait for terrain at each view before shooting anyway (software rendering is slow).
const MAX_SETTLE_FRAMES := 160

var _main: Node
var _frames := 0
var _jobs: Array = [] # [body_id, view]
var _job := -1
var _job_frame := 0
var _settled := 0
var _hold_position: WorldPos
var _hold_basis: Basis
var _camera := Camera3D.new()
var _quit_frame := -1 # quit a few frames after the last save
var _large_frames := 0 # frames rendered at LARGE in the current job
var _look_basis := Basis.IDENTITY
var _eye_offset := Vector3.ZERO # planet-frame metres from the held ship position


func _initialize() -> void:
	root.size = SMALL
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	var filter: String = OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else ""
	for body_id in [&"planet", &"cinder", &"verdant", &"selene", &"pebble"]:
		if filter == "" or String(body_id).contains(filter):
			for view in VIEWS:
				_jobs.append([body_id, view])


func _process(_delta: float) -> bool:
	_frames += 1
	if _quit_frame > 0:
		if _frames >= _quit_frame:
			quit()
		return false
	if _frames == 2:
		_main.menu.dismiss()
		for child in _main.get_children():
			if child is CanvasLayer:
				(child as CanvasLayer).visible = false
		root.add_child(_camera)
		_log("style ", VisualStyle.active(), " jobs ", _jobs.size())
	if _frames < 4:
		return false
	if _job < 0 or _frames > _job_frame + 3 and _shot_ready():
		if _job >= 0:
			_save()
		_job += 1
		if _job >= _jobs.size():
			_log("style_shots done")
			_quit_frame = _frames + 4
			return false
		_start_job()
	_hold()
	return false


func _shot_ready() -> bool:
	_settled = _settled + 1 if _main.terrain == null or _main.terrain.is_settled() else 0
	return _large_frames >= 2 and (_settled > 12 or _frames > _job_frame + MAX_SETTLE_FRAMES)


func _start_job() -> void:
	var body_id: StringName = _jobs[_job][0]
	var view: Array = _jobs[_job][1]
	var runtime: WorldRuntime = _main.runtime
	if runtime.active_frame != body_id:
		runtime.force_frame(body_id)
	var system: StarSystem = _main.system
	var planet: PlanetBody = runtime.planet_for(body_id)
	# A surface point where the sun stands SUN_ELEVATION_DEGREES above the horizon.
	var toward_sun := -system.sun_direction_in_frame(body_id, runtime.time_seconds)
	var tilt_axis := toward_sun.cross(Vector3.UP).normalized()
	var up := toward_sun.rotated(tilt_axis, deg_to_rad(90.0 - SUN_ELEVATION_DEGREES))
	var ground := planet.surface_radius_xyz(up.x, up.y, up.z)
	var altitude: float = view[1] * planet.radius if view[0] == "orbit" else view[1]
	var on_ground: bool = view[0] == "ground"
	_hold_position = WorldPos.new(planet.frame_id, up.x * (ground + altitude + (2.0 if on_ground else 0.0)), up.y * (ground + altitude + (2.0 if on_ground else 0.0)), up.z * (ground + altitude + (2.0 if on_ground else 0.0)))
	# Face 70 degrees round from the sun's direction along the ground: side light, the sun's glow at the edge of frame.
	var sun_flat := (toward_sun - up * toward_sun.dot(up)).normalized()
	var forward := sun_flat.rotated(up, deg_to_rad(70.0))
	_hold_basis = Basis.looking_at(forward, up)
	var ship: Ship = _main.ship
	ship.state.position = _hold_position
	ship.state.basis = _hold_basis
	ship.state.velocity = Vector3.ZERO
	ship.state.landed = on_ground
	ship.render_origin = _hold_position.duplicate_position()
	ship.apply_origin_shift(Vector3.ZERO)
	_main._recentre_everything_on_ship()
	ship.visible = view[3]
	var pitch_degrees: float = view[2]
	if view[0] == "orbit":
		# Put the limb just below the frame centre: the horizon dips by acos(R / (R + h)).
		pitch_degrees = rad_to_deg(acos(planet.radius / (planet.radius + altitude))) - 8.0
	_look_basis = Basis.looking_at(forward.rotated(forward.cross(up).normalized(), -deg_to_rad(pitch_degrees)), up)
	_eye_offset = Vector3.ZERO
	if on_ground:
		# Stand off the ship's flank at eye height above the real ground there (it may be higher or lower than under the ship).
		var spot := (up * ground - forward * 14.0 + forward.cross(up).normalized() * 9.0).normalized()
		var eye_radius := planet.surface_radius_xyz(spot.x, spot.y, spot.z) + 1.7
		_eye_offset = Vector3(spot.x * eye_radius - _hold_position.x, spot.y * eye_radius - _hold_position.y, spot.z * eye_radius - _hold_position.z)
	_place_camera()
	_camera.fov = 60.0
	_camera.near = 0.2 if on_ground else 5.0
	_camera.far = 3.0e7
	_camera.current = true
	root.size = SMALL
	_job_frame = _frames
	_settled = 0
	_large_frames = 0
	_log("job ", _job, " ", body_id, " ", view[0], " altitude ", altitude)


## Keeps the ship (and so the viewer) still: gravity would pull it down while slow frames run many physics steps.
func _hold() -> void:
	if _hold_position == null:
		return
	var ship: Ship = _main.ship
	ship.state.position = _hold_position.duplicate_position()
	ship.state.basis = _hold_basis
	ship.state.velocity = Vector3.ZERO
	_place_camera()
	if _frames > _job_frame + 2:
		var large := _frames > _job_frame + 3 and _shot_ready_peek()
		_large_frames = _large_frames + 1 if large and root.size == LARGE else 0
		root.size = LARGE if large else SMALL


## Render space is the planet frame shifted (never rotated), so planet-frame directions are render directions.
func _place_camera() -> void:
	_camera.global_transform = Transform3D(_look_basis, (_main.ship as Ship).global_transform.origin + _eye_offset)


func _shot_ready_peek() -> bool:
	return _settled > 10 or _frames > _job_frame + MAX_SETTLE_FRAMES - 2


## Saves the last drawn frame (rendered at LARGE for at least two frames) under this job's name, before the next
## job moves the camera.
func _save() -> void:
	var job: Array = _jobs[_job]
	var path: String = OS.get_cmdline_user_args()[0].path_join("%s_%s_%s.png" % [VisualStyle.active(), job[0], job[1][0]])
	root.get_viewport().get_texture().get_image().save_png(path)
	_log("saved ", path)


func _log(a: Variant = "", b: Variant = "", c: Variant = "", d: Variant = "", e: Variant = "", f: Variant = "", g: Variant = "", h: Variant = "") -> void:
	var line := "".join([str(a), str(b), str(c), str(d), str(e), str(f), str(g), str(h)])
	var path: String = OS.get_cmdline_user_args()[0].path_join("progress.log")
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(line)
		file.close()
	print(line)
