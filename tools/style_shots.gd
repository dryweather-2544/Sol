extends SceneTree
## Visual-style comparison photos (needs a display, not --headless):
##   SOL_VISUAL_STYLE=rodina godot --path . -s res://tools/style_shots.gd -- out_dir [body_filter] [view_name]
## Boots main.tscn, then for each world jumps the ship there (WorldRuntime.force_frame, as a save load does), holds it
## still at set altitudes with the sun about SUN_ELEVATION_DEGREES above the local horizon, and saves one picture per view
## from a free camera (ship hidden). Views: orbit (planet and limb), approach (high, along the horizon), low (low flight),
## ground (eye height by the landed ship, ship visible). Run once per style with the same arguments to compare.
## Progress goes to <out_dir>/progress.log (Godot buffers stdout until exit).

const SMALL := Vector2i(320, 180)
const LARGE := Vector2i(1280, 720)
const SUN_ELEVATION_DEGREES := 35.0
## [name, altitude metres (orbit: in planet radii), camera pitch below the horizon in degrees, ship visible]
const VIEWS := [["orbit", 1.4, 34.0, false], ["approach", 30000.0, 7.0, false], ["low", 900.0, 9.0, false], ["ground", 0.0, 2.0, true],
	["effects", 40000.0, 0.0, true]]
## The effects view holds the ship at this speed (above ShipDamage.HEAT_START_SPEED) under full thrust: plumes and entry heat.
const EFFECTS_SPEED := 9000.0

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
var _effects := false
var _quit_frame := -1 # quit a few frames after the last save
var _large_frames := 0 # frames rendered at LARGE in the current job
var _look_basis := Basis.IDENTITY
var _eye_offset := Vector3.ZERO # planet-frame metres from the held ship position


func _initialize() -> void:
	root.size = SMALL
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	var filter: String = OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else ""
	var view_filter: String = OS.get_cmdline_user_args()[2] if OS.get_cmdline_user_args().size() > 2 else ""
	for body_id in [&"planet", &"cinder", &"verdant", &"selene", &"pebble"]:
		if filter == "" or String(body_id).contains(filter):
			for view in VIEWS:
				if view[0] == "effects" and (body_id != &"planet" or view_filter != "effects"):
					continue # only on request, and only where there is air to heat
				if view_filter == "" or view[0] == view_filter:
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
	_effects = view[0] == "effects"
	if _effects:
		var pilot := ThrustPilot.new()
		ship.controller.release_control(_main.player_source)
		ship.controller.request_control(pilot, &"pilot_seat")
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
	if _effects:
		# Front three-quarter, slightly above: the nose sheath and the plumes behind the ship are both in frame.
		_eye_offset = forward * 22.0 - forward.cross(up).normalized() * 16.0 + up * 6.0
		_look_basis = Basis.looking_at(-_eye_offset + forward * 2.0, up)
	if on_ground:
		# Stand off the ship's flank at eye height above the real ground there (it may be higher or lower than under the ship).
		var spot := (up * ground - forward * 14.0 + forward.cross(up).normalized() * 9.0).normalized()
		var eye_radius := planet.surface_radius_xyz(spot.x, spot.y, spot.z) + 1.7
		_eye_offset = Vector3(spot.x * eye_radius - _hold_position.x, spot.y * eye_radius - _hold_position.y, spot.z * eye_radius - _hold_position.z)
	_place_camera()
	_camera.fov = 60.0
	_camera.near = 0.2 if on_ground else 5.0
	# Keep far/near moderate, as main.gd does: near 0.2 m with a 30,000 km far plane breaks depth precision and nothing draws.
	_camera.far = 6.0e4 if on_ground else 3.0e7
	_camera.current = true
	var to_ship := (_main.ship as Ship).global_transform.origin - _camera.global_transform.origin
	_log("camera look.up %.3f  look.to_ship %.3f  distance to ship %.1f  ship origin %s" % [-_camera.global_transform.basis.z.dot(up), -_camera.global_transform.basis.z.dot(to_ship.normalized()), to_ship.length(), str((_main.ship as Ship).global_transform.origin)])
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
	ship.state.velocity = -(_hold_basis.z) * EFFECTS_SPEED if _effects else Vector3.ZERO
	if _effects:
		ship.state.hull = 1.0 # the held re-entry speed would otherwise burn the hull away before the shot
		ship.state.fuel = 1.0
	_place_camera()
	if OS.get_environment("STYLE_SHOTS_DEBUG") != "" and _frames % 20 == 0:
		var active := root.get_viewport().get_camera_3d()
		_log("frame %d active camera %s ours current %s ship origin %s mode %d" % [_frames, active.name if active != null else "none", _camera.current, (_main.ship as Ship).global_transform.origin, _main.session.mode])
	if _frames > _job_frame + 2:
		var large := _frames > _job_frame + 3 and _shot_ready_peek()
		_large_frames = _large_frames + 1 if large and root.size == LARGE else 0
		root.size = LARGE if large else SMALL


## Render space is the planet frame shifted (never rotated), so planet-frame directions are render directions.
func _place_camera() -> void:
	var ship: Ship = _main.ship
	if _effects and _camera.get_parent() != ship:
		# The held 9 km/s moves the ship ~150 m per physics step between placing the camera and drawing; riding on the
		# ship keeps the framing.
		_camera.reparent(ship, false)
	var wanted := Transform3D(_look_basis, ship.global_transform.origin + _eye_offset)
	if _camera.get_parent() == ship:
		_camera.transform = ship.global_transform.affine_inverse() * wanted
	else:
		_camera.global_transform = wanted


func _shot_ready_peek() -> bool:
	return _settled > 10 or _frames > _job_frame + MAX_SETTLE_FRAMES - 2


## Saves the last drawn frame (rendered at LARGE for at least two frames) under this job's name, before the next
## job moves the camera.
func _save() -> void:
	var job: Array = _jobs[_job]
	var path: String = OS.get_cmdline_user_args()[0].path_join("%s_%s_%s.png" % [VisualStyle.active(), job[0], job[1][0]])
	root.get_viewport().get_texture().get_image().save_png(path)
	var planet: PlanetBody = _main.planet
	var camera_world := (_main.ship as Ship).state.position.offset_by(_eye_offset)
	_log("saved ", path, " camera altitude above ground %.1f m" % (planet.altitude_above_ground(camera_world) if planet != null else -1.0), " chunks ", _main.terrain.displayed_chunk_count() if _main.terrain != null else 0, " settled ", _settled)


func _log(a: Variant = "", b: Variant = "", c: Variant = "", d: Variant = "", e: Variant = "", f: Variant = "", g: Variant = "", h: Variant = "") -> void:
	var line := "".join([str(a), str(b), str(c), str(d), str(e), str(f), str(g), str(h)])
	var path: String = OS.get_cmdline_user_args()[0].path_join("progress.log")
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(line)
		file.close()
	print(line)


## Full forward thrust, so the engines show their plumes (a test cheat, like travel_shots.gd).
class ThrustPilot extends PilotSource:
	func _init() -> void:
		source_id = &"style_shots"

	func poll(ship_state: ShipState, delta: float) -> PilotCommand:
		var command := super.poll(ship_state, delta) # keeps the current gear
		command.thrust = Vector3(0, 0, -1)
		return command
