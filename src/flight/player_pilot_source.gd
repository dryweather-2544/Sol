class_name PlayerPilotSource
extends PilotSource
## Reads keyboard and mouse. Mouse motion arrives as events, so it is accumulated and
## consumed once per physics tick; turn demand is proportional to mouse speed.

## Turn demand (0..1) per pixel moved during one physics tick.
var mouse_sensitivity := 0.04 ## before the player's GameSettings multiplier
var _mouse_motion_this_tick := Vector2.ZERO


func _init() -> void:
	source_id = &"player"


func add_mouse_motion(relative_pixels: Vector2) -> void:
	_mouse_motion_this_tick += relative_pixels


func poll(ship_state: ShipState, _delta: float) -> PilotCommand:
	var settings := GameSettings.instance()
	var effective_sensitivity := mouse_sensitivity * settings.mouse_sensitivity
	var command := PilotCommand.new()
	command.thrust = Vector3(
		Input.get_axis("strafe_left", "strafe_right"),
		Input.get_axis("move_down", "move_up"),
		Input.get_axis("thrust_forward", "thrust_back"))
	# Mouse up = nose up, mouse right = turn right (negative yaw).
	command.turn = Vector3(
		clampf(-_mouse_motion_this_tick.y * effective_sensitivity * settings.pitch_sign() + Input.get_axis("pitch_down", "pitch_up"), -1.0, 1.0),
		clampf(-_mouse_motion_this_tick.x * effective_sensitivity + Input.get_axis("yaw_right", "yaw_left"), -1.0, 1.0),
		Input.get_axis("roll_right", "roll_left"))
	_mouse_motion_this_tick = Vector2.ZERO
	command.boost = Input.is_action_pressed("boost")
	command.fire = Input.is_action_pressed("fire")
	command.brake = Input.is_action_pressed("brake")
	# Shift from the gear the pilot chose (not the one in effect), so a forced lower gear does not eat a shift.
	command.gear = ship_state.selected_gear
	if Input.is_action_just_pressed("gear_up"):
		command.gear = mini(command.gear + 1, PilotCommand.GEAR_WARP)
	if Input.is_action_just_pressed("gear_down"):
		command.gear = maxi(command.gear - 1, PilotCommand.GEAR_DOCK)
	return command
