extends SceneTree
## Visual check of interplanetary travel (needs a display):
##   godot --path . -s res://tools/travel_shots.gd -- out_prefix target_body_id
## Boots main.tscn, lets a scripted pilot (which also aims the ship, a test cheat) fly to the target
## body, and saves a screenshot in open space and one on arrival in the target's frame.

class AimPilot extends PilotSource:
	var main: Node
	var target: StringName

	func _init() -> void:
		source_id = &"travel_shots"

	func poll(ship_state: ShipState, _delta: float) -> PilotCommand:
		var runtime: WorldRuntime = main.runtime
		var center := runtime.system.convert_position(WorldPos.new(target, 0.0, 0.0, 0.0), runtime.active_frame, runtime.time_seconds)
		var to_target := Vector3(center.x - ship_state.position.x, center.y - ship_state.position.y, center.z - ship_state.position.z).normalized()
		var up := Vector3(ship_state.position.x, ship_state.position.y, ship_state.position.z).normalized()
		if runtime.active_frame != StarSystem.SYSTEM_FRAME and ship_state.altitude_above_ground < 1.5e7 and runtime.active_frame != target:
			to_target = (to_target + up * 1.5).normalized() # climb away from the planet first
		ship_state.basis = Basis.looking_at(to_target, Vector3.UP if absf(to_target.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)
		var command := PilotCommand.new()
		command.gear = PilotCommand.GEAR_CRUISE
		command.thrust = Vector3(0, 0, -1)
		return command


var _main: Node
var _frames := 0
var _shot_open_space := false
var _arrival_frame := -1
var _finishing := false


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	var arguments := OS.get_cmdline_user_args()
	var prefix: String = arguments[0]
	var target := StringName(arguments[1])
	if _frames == 3:
		var pilot := AimPilot.new()
		pilot.main = _main
		pilot.target = target
		_main.ship.controller.release_control(_main.player_source)
		_main.ship.controller.request_control(pilot, &"pilot_seat")
	var runtime: WorldRuntime = _main.runtime
	if not _shot_open_space and runtime.active_frame == StarSystem.SYSTEM_FRAME and _frames > 120:
		_save(prefix + "_space.png")
		_shot_open_space = true
	if runtime.active_frame == target and _arrival_frame < 0:
		_arrival_frame = _frames
	if _arrival_frame > 0 and _frames > _arrival_frame + 240:
		_finish(prefix + "_arrival.png")
	if _frames > 6000:
		print("gave up; frame ", runtime.active_frame)
		_finish(prefix + "_timeout.png")
	return false


func _finish(path: String) -> void:
	if _finishing:
		return
	_finishing = true
	await _save(path)
	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	var runtime: WorldRuntime = _main.runtime
	print("saved ", path, " frame ", runtime.active_frame, " agl ", _main.ship.state.altitude_above_ground, " speed ", _main.ship.state.speed(), " frames ", _frames)
