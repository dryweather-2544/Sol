class_name PilotSource
extends RefCounted
## Base class for anything that can fly a ship: player input, AI, script, replay.

var source_id: StringName = &"unnamed"


func poll(_ship_state: ShipState, _delta: float) -> PilotCommand:
	var command := PilotCommand.new()
	command.gear = _ship_state.gear
	return command
