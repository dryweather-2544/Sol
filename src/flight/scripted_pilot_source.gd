class_name ScriptedPilotSource
extends PilotSource
## Plays back a fixed list of commands, one per poll. After the list ends it flies neutral
## (assist damps the ship to rest). Used by replay tests and automated checks.

var commands: Array[PilotCommand]
var tick_index := 0


func _init(scripted_commands: Array[PilotCommand] = []) -> void:
	source_id = &"scripted"
	commands = scripted_commands


func poll(ship_state: ShipState, _delta: float) -> PilotCommand:
	if tick_index < commands.size():
		tick_index += 1
		return commands[tick_index - 1]
	var neutral := PilotCommand.new()
	neutral.gear = ship_state.selected_gear
	return neutral
