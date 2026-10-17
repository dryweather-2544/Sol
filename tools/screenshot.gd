extends SceneTree
## Visual smoke check (needs a display, not --headless):
##   godot --path . -s res://tools/screenshot.gd -- out.png
## Boots main.tscn, flies a scripted turn for ~2 s, saves the viewport to a PNG.

var _frames := 0
var _main: Node


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _start_scripted_flight() -> void:
	var commands: Array[PilotCommand] = []
	for tick in 200:
		var command := PilotCommand.new()
		command.thrust = Vector3(0, 0, -1)
		command.turn = Vector3(0.2, 0.5, 0.6)
		commands.append(command)
	_main.ship.controller.release_control(_main.player_source)
	_main.ship.controller.request_control(ScriptedPilotSource.new(commands), &"pilot_seat")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_start_scripted_flight()
	if _frames == 150:
		var arguments := OS.get_cmdline_user_args()
		var output_path: String = arguments[0] if arguments.size() > 0 else "screenshot.png"
		root.get_viewport().get_texture().get_image().save_png(output_path)
		print("saved ", output_path, " speed ", _main.ship.state.speed())
		quit()
	return false
