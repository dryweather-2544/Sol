extends SceneTree
## Visual smoke check (needs a display, not --headless):
##   godot --path . -s res://tools/screenshot.gd -- out.png [altitude_metres] [pitch_degrees_down]
## Boots main.tscn, moves the ship to the given altitude above its start point (default: stay in
## orbit), waits for the terrain to finish loading, then saves the viewport to a PNG.

var _frames := 0
var _main: Node
var _settled_frames := 0
var _exited_at_frame := -1


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_move_ship()
	if _frames > 2:
		_settled_frames = _settled_frames + 1 if _main.terrain.is_settled() else 0
	var arguments_now := OS.get_cmdline_user_args()
	if arguments_now.size() > 3 and arguments_now[3] == "exit":
		# Wait for landing, step out, then walk forward a little before the shot.
		if _exited_at_frame < 0 and _main.ship.state.landed and _settled_frames > 30:
			_main._try_exit_ship()
			_exited_at_frame = _frames
		if _exited_at_frame < 0:
			Input.action_press("move_down")
			if _frames < 1400:
				return false
		Input.action_release("move_down")
		if _exited_at_frame >= 0 and _frames < _exited_at_frame + 90:
			Input.action_press("thrust_forward")
			return false
		Input.action_release("thrust_forward")
	if _settled_frames > 30 or _frames > 1500:
		var arguments := OS.get_cmdline_user_args()
		var output_path: String = arguments[0] if arguments.size() > 0 else "screenshot.png"
		root.get_viewport().get_texture().get_image().save_png(output_path)
		print("saved ", output_path, " frames ", _frames, " chunks ", _main.terrain.displayed_chunk_count(), " settled ", _main.terrain.is_settled(), " agl ", _main.ship.state.altitude_above_ground, " desired ", _main.terrain._desired.size(), " pending ", _main.terrain._pending.size(), " results ", _main.terrain._ready_results.size(), " landed ", _main.ship.state.landed, " on_foot ", _main.on_foot.active)
		quit()
	return false


func _move_ship() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() < 2:
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
	forward = forward.rotated(Vector3.UP.cross(up).normalized() , pitch_down) if pitch_down != 0.0 else forward
	ship.state.basis = Basis.looking_at(forward, up)
	ship.state.velocity = Vector3.ZERO
	_main.terrain.render_origin = ship.render_origin.duplicate_position()
	_main.camera.snap_to_target()
