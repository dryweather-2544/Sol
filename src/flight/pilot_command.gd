class_name PilotCommand
extends RefCounted
## One tick of pilot intent. Players, AI, replays and scripts all produce this; FlightModel is
## the only thing that consumes it (research FLY-01..04). face_dir / tick are left out until an
## AI source (M10) or a recorder needs them.

const GEAR_DOCK := 0
const GEAR_COMBAT := 1
const GEAR_CRUISE := 2

## Ship-local, each axis -1..1, Godot axes: x right, y up, -z forward.
var thrust := Vector3.ZERO
## Turn-rate demand about ship-local axes, each -1..1: x pitch (+ = nose up), y yaw (+ = nose left), z roll (+ = left wing down).
var turn := Vector3.ZERO
var gear := GEAR_DOCK
var boost := false
var brake := false
## Coast: no thrust and no assist damping, velocity is held.
var lock_linear := false
var source_id: StringName = &""


## What an unpiloted ship does: hold velocity, stop rotating.
static func parked(current_gear: int) -> PilotCommand:
	var command := PilotCommand.new()
	command.gear = current_gear
	command.lock_linear = true
	command.source_id = &"parked"
	return command
