extends SceneTree
## Deterministic entry probe for tuning. Usage:
##   godot --path . -s res://tools/entry_probe.gd -- <speed_mps> <descent_angle_deg> [screenshot_prefix]
## The ship starts 300 km above the same point and coasts (lock_linear) so the trajectory is
## determined by gravity and the atmospheric model, not by player input.

class EntryPilot extends PilotSource:
	var brake_when_hot := false
	func _init() -> void:
		source_id = &"entry_probe"
	func poll(ship_state: ShipState, _delta: float) -> PilotCommand:
		var command := PilotCommand.parked(ship_state.gear)
		if brake_when_hot and ship_state.entry_heat > 0.55:
			command.brake = true
			command.gear = PilotCommand.GEAR_COMBAT
		return command

var main: Node
var frames := 0
var speed := 6000.0
var angle := -12.0
var prefix := ""
var last_print := -1000
var _started := false
var _shots := 0
var _cockpit := false
var _recovery := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: speed = float(args[0])
	if args.size() > 1: angle = float(args[1])
	if args.size() > 2: prefix = args[2]
	_cockpit = args.size() > 3 and args[3] == "cockpit"
	_recovery = args.size() > 3 and args[3] == "recover"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		main.menu.dismiss()
	if frames == 5:
		_setup()
		_started = true
	if not _started:
		return false
	if frames % 60 == 0:
		var state: ShipState = main.ship.state
		if frames - last_print >= 300:
			last_print = frames
			print("t=%4.0f alt=%8.1f speed=%8.1f angle=%+6.1f density=%.3f heat=%.3f hull=%.3f corridor=%d warn=%s" % [
				frames / 60.0, state.altitude_above_ground, state.speed(), state.entry_angle_deg,
				state.entry_density, state.entry_heat, state.hull, state.entry_corridor, state.entry_warning])
		if prefix != "" and state.entry_heat > 0.15 and _shots == 0:
			_save(prefix + "_heat.png"); _shots += 1
		if prefix != "" and state.entry_heat > 0.55 and _shots == 1:
			_save(prefix + "_critical.png"); _shots += 1
		if state.altitude_above_ground < 2500.0 or state.hull <= 0.0:
			if prefix != "" and _shots < 3:
				_save(prefix + "_low.png"); _shots += 1
			print("END alt=%.1f speed=%.1f hull=%.3f heat=%.3f" % [state.altitude_above_ground, state.speed(), state.hull, state.entry_heat])
			quit()
	if frames > 60 * 300:
		print("TIMEOUT alt=%.1f speed=%.1f heat=%.3f hull=%.3f" % [main.ship.state.altitude_above_ground, main.ship.state.speed(), main.ship.state.entry_heat, main.ship.state.hull])
		quit()
	return false


func _setup() -> void:
	var ship: Ship = main.ship
	var planet: PlanetBody = main.planet
	var up := Vector3(0.3, 0.5, 0.8).normalized()
	var tangent := Vector3.UP.cross(up).normalized()
	ship.state.position = WorldPos.new(planet.frame_id, up.x * (planet.radius + 300000.0), up.y * (planet.radius + 300000.0), up.z * (planet.radius + 300000.0))
	ship.render_origin = ship.state.position.duplicate_position()
	main.terrain.render_origin = ship.render_origin.duplicate_position()
	main.terrain.viewer = ship.state.position
	var descent_speed := sin(deg_to_rad(absf(angle))) * speed
	var horizontal := cos(deg_to_rad(absf(angle))) * speed
	ship.state.velocity = -up * descent_speed + tangent * horizontal
	ship.state.basis = Basis.looking_at(ship.state.velocity.normalized(), up)
	ship.state.gear = PilotCommand.GEAR_CRUISE
	ship.state.landed = false
	main.chase_camera.snap_to_target()
	if _cockpit:
		main._cockpit_view = true
		main._update_active_camera()
	var entry_pilot := EntryPilot.new()
	entry_pilot.brake_when_hot = _recovery
	ship.controller.release_control(main.player_source)
	ship.controller.request_control(entry_pilot, &"pilot_seat")


func _save(path: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(path)
	print("SHOT ", path)
