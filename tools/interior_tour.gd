extends Node
## Interior walkthrough photos through the real game camera (needs a display, not --headless).
##   Cloud/CLI: godot --path . res://tools/interior_tour.tscn -- [out_dir] [landed|orbit] [only_view_name]
##   Mac: open tools/interior_tour.tscn in the editor and Scene > Run Current Scene (writes tests/visual/out/interior_tour/).
## Boots main.tscn (in orbit, seated), stands the player up, then places the InteriorBody at each view below
## (ship-local metres, yaw, pitch) and saves what the InteriorView camera sees, with the game's own visibility
## logic running (ShipVisuals.set_camera_place, door animation). `landed` lands the ship first, so the windows
## look at terrain instead of space. Also logs, per view, how many of the ship's meshes were visible.

## name -> [x, z, yaw (0 = toward the nose, -z), pitch, open doors]
const VIEWS := {
	"01_cockpit_rear": [0.0, -4.6, PI, -0.05, []],
	"02_cockpit_front": [0.0, -4.6, 0.0, -0.1, []],
	"03_cabin_from_door": [0.0, -3.0, PI, -0.05, []],
	"04_cabin_west": [0.0, -1.6, PI * 0.5, -0.05, []],
	"05_cabin_east": [0.0, -1.6, -PI * 0.5, -0.05, []],
	"06_cabin_to_cockpit_open": [0.0, -1.0, 0.0, 0.0, [&"cockpit_door"]],
	"07_engineering_aft": [0.0, 0.5, PI, -0.05, []],
	"08_engineering_west": [0.0, 1.6, PI * 0.5, -0.1, []],
	"09_engineering_east": [0.0, 1.6, -PI * 0.5, -0.1, []],
	"10_engineering_fwd": [0.0, 2.8, 0.0, -0.05, []],
	"11_turret_room": [0.0, 3.7, PI, -0.05, []],
	"12_cargo_west": [0.0, 7.0, PI * 0.5, -0.1, []],
	"13_cargo_east": [0.0, 7.0, -PI * 0.5, -0.1, []],
	"14_airlock_aft": [0.0, 8.8, PI, -0.05, []],
	"15_airlock_fwd": [0.0, 10.0, 0.0, -0.05, [&"airlock_inner"]],
	"16_cabin_look_up": [0.0, -1.6, PI, 0.9, []],
	"17_cabin_look_down": [0.0, -1.6, PI, -1.0, []],
	# Doorway views (the hull used to draw through the walls from the cockpit, and from inside a door frame).
	"18_dw_cockpit_rear_open": [0.0, -4.6, PI, -0.05, [&"cockpit_door"]],
	"19_dw_in_cockpit_door": [0.0, -3.5, PI, -0.05, [&"cockpit_door"]],
	"20_dw_in_cockpit_door_west": [0.0, -3.5, PI * 0.5, -0.05, [&"cockpit_door"]],
	"21_dw_cockpit_front_open": [0.0, -4.0, 0.0, -0.1, [&"cockpit_door"]],
	"22_dw_airlock_rear_open": [0.0, 8.8, PI, -0.05, [&"airlock_inner"]],
	"23_dw_in_airlock_door": [0.0, 8.1, 0.0, -0.05, [&"airlock_inner"]],
}

var _main: Node
var _frames := 0
var _stage := 0
var _stage_frame := 0
var _view_names: Array = []
var _view_index := 0
var _landed := false
var _settled := 0


var _out_dir := ""
var root: Window
## Run the walk (pressing the real movement keys and F at doors) after the fixed views.
@export var walk := true
var _walk_index := 0
var _walk_frames := 0


func _ready() -> void:
	if OS.get_cmdline_user_args().has("lowtick"):
		Engine.physics_ticks_per_second = 4 # fewer physics ticks than drawn frames, as on a fast Mac: physics interpolation is in play
	process_mode = Node.PROCESS_MODE_ALWAYS # the pause menu pauses the tree at boot
	root = get_tree().root
	if not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		get_window().size = Vector2i(320, 180) # software rendering cost follows pixels: land small, photograph at 960x540
	var args := OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://tests/visual/out/interior_tour")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_landed = args.size() > 1 and args[1] == "landed"
	var only := args[2] if args.size() > 2 else ""
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child.call_deferred(_main)
	for view_name in VIEWS:
		if only == "" or (view_name as String).contains(only):
			_view_names.append(view_name)


func _process(_delta: float) -> void:
	if _main == null or not _main.is_inside_tree():
		return
	_frames += 1
	if _frames == 2:
		_main.menu.dismiss()
		if _landed:
			_lift_ship(4.0)
	match _stage:
		0:
			if not _landed:
				if _frames > 30:
					_stage = 1
			else:
				_settled = _settled + 1 if _main.terrain.is_settled() else 0
				# Software rendering lands very slowly: hovering 4 m up over settled terrain is enough to look out of the windows
				# and to step out (the ramp is fitted to the ground).
				if (_main.ship.state.landed or _settled > 20) or _frames > 400:
					_log("near ground: landed ", _main.ship.state.landed, " agl %.1f" % _main.ship.state.altitude_above_ground, " frames ", _frames)
					_stage = 1
		1:
			if DisplayServer.get_name() != "headless":
				get_window().size = Vector2i(960, 540)
			_main.session.interact() # stand up
			_main._on_mode_changed()
			_log("stood up, mode ", _main.session.mode)
			_stage = 2
			_stage_frame = _frames
		2:
			if _frames > _stage_frame + 5:
				_stage = 3
		3:
			if _view_index >= _view_names.size():
				_stage = 5 if walk and not OS.get_cmdline_user_args().has("nowalk") else 9
				if _landed and OS.get_cmdline_user_args().has("roundtrip"):
					_stage = 6
				_stage_frame = _frames
				_main.session.interior_body.place(Vector3(0, _main.session.systems.layout.floor_y, -4.95), PI)
				_main.interior_view._pitch = -0.05
				for portal in _main.session.systems.layout.portals.values():
					(portal as Portal).target_open = false
				return
			_place(_view_names[_view_index])
			_stage = 4
			_stage_frame = _frames
		4:
			if _frames > _stage_frame + 8:
				_save(_view_names[_view_index])
				_view_index += 1
				_stage = 3
		5:
			_walk_step()
		6:
			_roundtrip_step()
		9:
			_log("interior_tour done")
			get_tree().quit()


## Walks the route with the real controls: turns toward the next waypoint, holds W, presses F (interact) when looking at a
## closed door, and saves a frame every 24 frames.
const ROUTE := [Vector2(0.0, -3.0), Vector2(0.0, -1.0), Vector2(-3.5, -1.6), Vector2(0.0, -0.6), Vector2(0.0, 1.6), Vector2(3.5, 1.6),
	Vector2(0.0, 2.8), Vector2(0.0, 4.4), Vector2(0.0, 6.8), Vector2(-3.5, 7.0), Vector2(0.0, 7.4), Vector2(0.0, 9.6), Vector2(0.0, 7.0),
	Vector2(0.0, 1.0), Vector2(0.0, -2.0), Vector2(0.0, -4.6)]


func _walk_step() -> void:
	var session: GameSession = _main.session
	var body := session.interior_body
	_walk_frames += 1
	if _walk_index >= ROUTE.size() or _walk_frames > 6000:
		Input.action_release("thrust_forward")
		_log("walk finished at ", body.position, " index ", _walk_index, " frames ", _walk_frames)
		_stage = 9
		return
	var goal: Vector2 = ROUTE[_walk_index]
	var to_goal := goal - Vector2(body.position.x, body.position.z)
	if to_goal.length() < 0.35:
		_walk_index += 1
		return
	var wanted_yaw := atan2(-to_goal.x, -to_goal.y)
	body.yaw = lerp_angle(body.yaw, wanted_yaw, 0.25)
	Input.action_press("thrust_forward")
	var target := session.interaction_target()
	var layout := session.systems.layout
	if layout.portals.has(target) and not (layout.portals[target] as Portal).target_open and _walk_frames % 10 == 0:
		session.interact()
		_log("F on ", target, " -> open ", (layout.portals[target] as Portal).target_open, " prompt was door")
	if _walk_frames % 24 == 0:
		_save("walk_%04d" % _walk_frames)


## Landed only: steps outside (as tools/ship_shots.gd does), stands on the ground for a while, then walks up the ramp with
## the real controls until GameSession switches to INSIDE, walks into the cabin and photographs it. This is the
## outside -> inside transition (floating-origin anchor change, pocket shown again) that a fixed view never exercises.
var _round_phase := 0
var _round_frames := 0


func _roundtrip_step() -> void:
	var session: GameSession = _main.session
	var systems := session.systems
	_round_frames += 1
	match _round_phase:
		0:
			systems.walkway.state = WalkwayController.State.DEPLOYED
			systems.walkway.progress = 1.0
			systems.layout.ramp_walkable = true
			systems.airlock.outer.target_open = true
			systems.airlock.outer.open_factor = 1.0
			systems.airlock.inner.target_open = true
			systems.airlock.inner.open_factor = 1.0
			session._fit_ramp_to_ground()
			var ship_state: ShipState = session.ship.state
			session.exterior_body.place_on_ground(session.planet, ship_state.position.offset_by(ship_state.basis * Vector3(0.0, 0.0, 19.0)), -ship_state.basis.z)
			session.restore_mode(GameSession.Mode.OUTSIDE)
			_main._on_mode_changed()
			_log("outside, mode ", session.mode)
			_round_phase = 1
			_round_frames = 0
		1:
			if _round_frames == 30:
				_save("rt_01_outside")
			if _round_frames > 40:
				_round_phase = 2
				_round_frames = 0
		2:
			# Face the ship and walk up the ramp.
			var to_ship := session.ship.state.position.vector_from(session.exterior_body.position)
			var up: Vector3 = session.planet.up_at(session.exterior_body.position)
			var flat := (to_ship - up * to_ship.dot(up)).normalized()
			session.exterior_body.heading = flat
			Input.action_press("thrust_forward")
			if session.mode == GameSession.Mode.INSIDE:
				Input.action_release("thrust_forward")
				_log("walked in after ", _round_frames, " frames, local ", session.interior_body.position)
				_round_phase = 3
				_round_frames = 0
			elif _round_frames > 1500:
				Input.action_release("thrust_forward")
				_log("walk-in failed; mode ", session.mode, " outside local ", ShipFrame.local_from_world(session.ship.state, session.exterior_body.position))
				_stage = 9
		3:
			# Inside: the real controls carry on up the airlock and into the cargo bay; photograph the way in.
			var body := session.interior_body
			var goal := Vector2(0.0, 1.0)
			var to_goal := goal - Vector2(body.position.x, body.position.z)
			if to_goal.length() > 0.4 and _round_frames < 900:
				body.yaw = lerp_angle(body.yaw, atan2(-to_goal.x, -to_goal.y), 0.3)
				Input.action_press("thrust_forward")
				var target := session.interaction_target()
				if systems.layout.portals.has(target) and not (systems.layout.portals[target] as Portal).target_open and _round_frames % 10 == 0:
					session.interact()
				if _round_frames % 20 == 0:
					_save("rt_%04d_walk" % _round_frames)
			else:
				Input.action_release("thrust_forward")
				_round_phase = 4
				_round_frames = 0
		4:
			var spins := [0.0, PI * 0.5, PI, -PI * 0.5]
			if _round_frames % 10 == 0:
				var index := _round_frames / 10 - 1
				if index >= spins.size():
					_stage = 9
					return
				_save("rt_spin_%d" % index)
			session.interior_body.yaw = spins[mini(_round_frames / 10, spins.size() - 1)]


func _place(view_name: String) -> void:
	var view: Array = VIEWS[view_name]
	var session: GameSession = _main.session
	var layout := session.systems.layout
	for portal_id in layout.portals:
		var portal: Portal = layout.portals[portal_id]
		var open: bool = portal_id in view[4]
		portal.target_open = open
		portal.open_factor = 1.0 if open else 0.0
	session.interior_body.place(Vector3(view[0], layout.floor_y, view[1]), view[2])
	_main.interior_view._pitch = view[3]


func _lift_ship(altitude: float) -> void:
	var ship: Ship = _main.ship
	var planet: PlanetBody = _main.planet
	if planet == null:
		return
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


func _save(view_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out_dir.path_join(view_name + ".png")
	root.get_viewport().get_texture().get_image().save_png(path)
	var camera := root.get_viewport().get_camera_3d()
	var shown := 0
	var hidden := 0
	var drawn := 0
	var worst_drift := 0.0 # how far, relative to the camera, the place sent to the renderer (physics interpolation) is from the real one
	var worst_name := ""
	var camera_drawn := camera.get_global_transform_interpolated().origin
	var camera_real := camera.global_position
	for child in _main.ship.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.is_visible_in_tree():
			shown += 1
			if mesh.layers & camera.cull_mask:
				drawn += 1
			var drift := (mesh.get_global_transform_interpolated().origin - camera_drawn).distance_to(mesh.global_position - camera_real)
			if drift > worst_drift:
				worst_drift = drift
				worst_name = String(mesh.get_path()).get_file() + " under " + String(mesh.get_parent().name)
		else:
			hidden += 1
	var local: Vector3 = _main.ship.global_transform.affine_inverse() * camera.global_position
	_log("saved ", view_name, " camera ", camera.name, " local ", local, " room ", _main.session.systems.layout.room_at(local.x, local.z),
		" meshes shown ", shown, " hidden ", hidden, " drawn by this camera ", drawn, " mask 0x%x" % camera.cull_mask,
		" worst drift vs camera %.3f m (%s)" % [worst_drift, worst_name], " near ", camera.near, " far ", camera.far)


func _log(a: Variant = "", b: Variant = "", c: Variant = "", d: Variant = "", e: Variant = "", f: Variant = "", g: Variant = "", h: Variant = "", i: Variant = "", j: Variant = "", k: Variant = "", l: Variant = "", m: Variant = "", n: Variant = "", o: Variant = "", p: Variant = "", q: Variant = "", r: Variant = "", t: Variant = "", u: Variant = "") -> void:
	var line := "".join([str(a), str(b), str(c), str(d), str(e), str(f), str(g), str(h), str(i), str(j), str(k), str(l), str(m), str(n), str(o), str(p), str(q), str(r), str(t), str(u)])
	var path: String = _out_dir.path_join("progress.log")
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(line)
		file.close()
	print(line)
