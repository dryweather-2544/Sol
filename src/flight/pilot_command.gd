class_name PilotCommand
extends RefCounted
## One tick of pilot intent. Players, AI, replays and scripts all produce this; FlightModel is
## the only thing that consumes it (research FLY-01..04). face_dir / tick are left out until an
## AI source (M10) or a recorder needs them.

const GEAR_DOCK := 0
const GEAR_COMBAT := 1
const GEAR_CRUISE := 2
## Open-space limnal/warp gear above CRUISE; the installed warp drive and system-frame environment gate it.
const GEAR_WARP := 3

## Ship-local, each axis -1..1, Godot axes: x right, y up, -z forward.
var thrust := Vector3.ZERO
## Turn-rate demand about ship-local axes, each -1..1: x pitch (+ = nose up), y yaw (+ = nose left), z roll (+ = left wing down).
var turn := Vector3.ZERO
## Desired nose direction in the ship's frame (unit vector, ZERO = use `turn`). AI pilots set this; the
## flight model turns the ship toward it (research FLY-02: AI gives a face vector, players a turn vector).
var face_direction := Vector3.ZERO
## Fire the ship's guns this tick.
var fire := false
var gear := GEAR_DOCK
var boost := false
var brake := false
## Coast with the drive disconnected (Rodina Clutch): thrust and drag do nothing, momentum and gravity carry the ship.
var lock_linear := false
## 0..1 (Rodina MoveLock): how far to override the acceleration limit and match the thrust's target velocity exactly
## this tick. AI and scripted pilots use it to hold a velocity (Rodina's AI mover does); players leave it 0.
var move_lock := 0.0
## Hold the attitude still (Sol's parked ship). Rodina sets no rotation for an unpiloted ship; Sol stops it instead.
var stop_rotation := false
var source_id: StringName = &""


## What an unpiloted ship does: coast (hold velocity, gravity still acts) and stop rotating.
static func parked(current_gear: int) -> PilotCommand:
	var command := PilotCommand.new()
	command.gear = current_gear
	command.lock_linear = true
	command.stop_rotation = true
	command.source_id = &"parked"
	return command


## A copy with all thrust removed (used when an interlock holds the ship; commands may be shared, never mutate them).
func without_thrust() -> PilotCommand:
	var copy := PilotCommand.new()
	copy.turn = turn
	copy.face_direction = face_direction
	copy.fire = fire
	copy.gear = gear
	copy.boost = boost
	copy.brake = brake
	copy.lock_linear = lock_linear
	copy.move_lock = move_lock
	copy.stop_rotation = stop_rotation
	copy.source_id = source_id
	return copy


## A copy with thrust scaled (used when engines are damaged or starved of power).
func with_thrust_scaled(factor: float) -> PilotCommand:
	var copy := without_thrust()
	copy.thrust = thrust * factor
	return copy


## A copy with boost off (used when the tank is empty).
func without_boost() -> PilotCommand:
	var copy := PilotCommand.new()
	copy.thrust = thrust
	copy.turn = turn
	copy.face_direction = face_direction
	copy.fire = fire
	copy.gear = gear
	copy.brake = brake
	copy.lock_linear = lock_linear
	copy.move_lock = move_lock
	copy.stop_rotation = stop_rotation
	copy.source_id = source_id
	return copy
