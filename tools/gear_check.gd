extends SceneTree
## Real main scene, real player input actions: start, shift gears with the gear_up / gear_down actions, hold
## thrust_forward, and print gear (in effect / selected), speed, fuel and frame. Headless is fine:
##   godot --headless --path . -s res://tools/gear_check.gd

var _main: Node
var _frames := 0


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _report(label: String) -> void:
	var state: ShipState = _main.ship.state
	print("GEAR_CHECK %-28s frame %4d  gear %d selected %d  speed %9.1f m/s  fuel %.3f  alt %.0f m  world %s  pilot %s" % [
		label, _frames, state.gear, state.selected_gear, state.speed(), state.fuel, state.altitude_above_ground,
		String(_main.runtime.active_frame), String(_main.ship.controller.current_source.source_id) if _main.ship.controller.current_source != null else "none"])


func _tap(action: String) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)


func _release(action: String) -> void:
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)


func _process(_delta: float) -> bool:
	_frames += 1
	match _frames:
		2:
			_main.menu.dismiss()
		5:
			_report("start")
		10:
			_tap("gear_down")
		12:
			_release("gear_down")
		14:
			_tap("gear_down")
		16:
			_release("gear_down")
		20:
			_report("after two gear_down")
			Input.action_press("thrust_forward")
		140:
			_report("precision, W held 2 s")
			_tap("gear_up")
		142:
			_release("gear_up")
		260:
			_report("combat, W held 2 s")
			_tap("gear_up")
		262:
			_release("gear_up")
		380:
			_report("cruise, W held 2 s")
		500:
			_report("cruise, W held 4 s")
			Input.action_release("thrust_forward")
			quit(0)
	return false
