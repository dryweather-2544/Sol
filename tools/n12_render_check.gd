extends SceneTree
## N12 graphical regression check. Needs a display:
##   N12_MODE=rest|combat|cruise|warp godot --path . -s res://tools/n12_render_check.gd
## Boots the real main scene, places the ship 300 km above Aurelia with the planet filling the
## background, and logs the rendered ship/camera relationship across floating-origin rebases.
## Writes one screenshot to user://n12_render_check/<mode>.png.

const MODES := {
	"rest": {"speed": 0.0, "gear": PilotCommand.GEAR_DOCK, "rotate": true},
	"combat": {"speed": 450.0, "gear": PilotCommand.GEAR_COMBAT, "rotate": false},
	"cruise": {"speed": 5000.0, "gear": PilotCommand.GEAR_CRUISE, "rotate": false},
	"warp": {"speed": 300000.0, "gear": PilotCommand.GEAR_WARP, "rotate": false},
}

var _main: Node
var _frames := 0
var _mode := "cruise"
var _config: Dictionary
var _last_screen := Vector2.ZERO
var _worst_jump := 0.0
var _worst_dot := 1.0
var _rebases := 0


func _initialize() -> void:
	_mode = OS.get_environment("N12_MODE")
	if not MODES.has(_mode):
		_mode = "cruise"
	_config = MODES[_mode]
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_main.menu.dismiss()
	if _frames == 12:
		_setup()
	if _frames > 20 and _frames <= 220:
		_sample()
	if _frames == 221:
		_finish()
	return false


func _setup() -> void:
	var ship: Ship = _main.ship
	var planet: PlanetBody = _main.planet
	var up := planet.up_at(ship.state.position).normalized()
	var radius := planet.radius + 300000.0
	ship.state.position = WorldPos.new(planet.frame_id, up.x * radius, up.y * radius, up.z * radius)
	ship.render_origin = ship.state.position.duplicate_position()
	ship.state.basis = Basis.looking_at(-up, Vector3.UP)
	var speed: float = _config["speed"]
	if speed == 0.0:
		ship.state.velocity = Vector3.ZERO
	elif _mode == "warp":
		# WARP is an open-space/tangential mode. Diving at the surface from 300 km would hit the
		# ground within the probe window, which is not a rendering test.
		ship.state.velocity = ship.state.basis.x * speed
	else:
		ship.state.velocity = -up * speed
	ship.state.gear = _config["gear"]
	ship.state.selected_gear = _config["gear"]
	ship.apply_origin_shift(Vector3.ZERO)
	_main.chase_camera.target = ship
	_main.chase_camera.snap_to_target()
	_main.chase_camera.current = true
	_main.floating_origin.anchor = ship
	print("N12 %s setup speed=%s gear=%d" % [_mode, str(ship.state.velocity.length()), ship.state.gear])


func _sample() -> void:
	var ship: Ship = _main.ship
	var camera: Camera3D = _main.chase_camera
	if _config["rotate"]:
		ship.state.basis = ship.state.basis.rotated(ship.state.basis.y.normalized(), 0.006)
	var screen: Vector2 = camera.unproject_position(ship.global_position)
	if _last_screen != Vector2.ZERO:
		_worst_jump = maxf(_worst_jump, screen.distance_to(_last_screen))
	_last_screen = screen
	var ship_transform := ship.get_global_transform_interpolated()
	var camera_transform := camera.get_global_transform_interpolated()
	var to_ship := (ship_transform.origin - camera_transform.origin).normalized()
	_worst_dot = minf(_worst_dot, (-camera_transform.basis.z).dot(to_ship))
	_rebases = _main.floating_origin.rebase_count
	if _frames == 120:
		var shot_dir := "user://n12_render_check"
		DirAccess.make_dir_recursive_absolute(shot_dir)
		root.get_texture().get_image().save_png(shot_dir + "/%s.png" % _mode)


func _finish() -> void:
	var screen: Vector2 = _main.chase_camera.unproject_position(_main.ship.global_position)
	var visible: bool = _worst_dot > 0.5 and screen.x >= 0.0 and screen.y >= 0.0 and screen.x <= 1152.0 and screen.y <= 648.0
	print("N12 %s RESULT worst_jump=%.2f px worst_camera_ship_dot=%.4f rebases=%d visible_at_end=%s frame=%s" % [
		_mode, _worst_jump, _worst_dot, _rebases, str(visible), str(_main.runtime.active_frame)])
	quit(0 if _worst_jump < 500.0 and _worst_dot > 0.5 else 1)
