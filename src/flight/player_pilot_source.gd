class_name PlayerPilotSource
extends PilotSource
## Reads keyboard and mouse. Mouse motion arrives as events, so it is accumulated and
## consumed once per physics tick; turn demand is proportional to mouse speed.

## Turn demand (0..1) per pixel moved during one physics tick.
var mouse_sensitivity := 0.04 ## before the player's GameSettings multiplier
var _mouse_motion_this_tick := Vector2.ZERO
## Rodina EGBehaviorPlayer:UpdateShiftGears (EGBehaviorPlayer.lua:97-159): hold the clutch (right mouse), tap W to shift up
## or S to shift down; the shift commits when W/S (or the clutch) are released. A shift the gear cannot make is refused
## (Rodina plays ShiftGrind) and nothing more is accepted until both keys are let go.
var _pending_gear := -1
## True while the pilot has a cockpit screen focused: right clicks then select controls, and must not also work the clutch.
var ignore_clutch := false
var _shift_block := false


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
	var clutch := Input.is_action_pressed("clutch") and not ignore_clutch
	command.clutch = clutch
	command.gear = _clutch_shift(ship_state, clutch)
	if clutch and ship_state.gear < PilotCommand.GEAR_WARP:
		# Rodina: the drive is disconnected while the clutch is held (below the limnal gear); W/S are the shift keys.
		command.lock_linear = true
		command.thrust = Vector3.ZERO
	if not clutch: # the direct [ ] keys; under the clutch only W/S shift
		if Input.is_action_just_pressed("gear_up"):
			command.gear = mini(command.gear + 1, PilotCommand.GEAR_WARP)
		if Input.is_action_just_pressed("gear_down"):
			command.gear = maxi(command.gear - 1, PilotCommand.GEAR_DOCK)
	return command


## Returns the gear the pilot has committed to this tick (the shift state machine above).
func _clutch_shift(ship_state: ShipState, clutch: bool) -> int:
	var gear := ship_state.selected_gear
	if not clutch:
		if _pending_gear >= 0:
			gear = _pending_gear # letting go of the clutch commits (Rodina: Gear = NextGear)
		_pending_gear = -1
		_shift_block = true
		ship_state.shift_pending = -1
		return gear
	var up := Input.is_action_pressed("thrust_forward")
	var down := Input.is_action_pressed("thrust_back")
	if not up and not down:
		_shift_block = false
		if _pending_gear >= 0:
			gear = _pending_gear
			_pending_gear = -1
		ship_state.shift_pending = -1
		return gear
	if not _shift_block:
		var target := gear + 1 if up else gear - 1
		if target >= PilotCommand.GEAR_DOCK and target <= mini(ship_state.allowed_gear, PilotCommand.GEAR_WARP):
			_pending_gear = target
		elif _pending_gear < 0:
			_shift_block = true
			ship_state.shift_refusals += 1
	ship_state.shift_pending = _pending_gear
	return gear
