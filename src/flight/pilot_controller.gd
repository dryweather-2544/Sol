class_name PilotController
extends Node
## Decides which PilotSource flies the ship. One source at a time; a second request is denied
## with a reason. With no source the ship is PARKED (holds velocity), never disabled.

signal control_changed(previous_source: PilotSource, new_source: PilotSource)


class ControlResult extends RefCounted:
	var granted := false
	var reason := ""


var current_source: PilotSource
var current_seat_id: StringName = &""


func request_control(source: PilotSource, seat_id: StringName) -> ControlResult:
	var result := ControlResult.new()
	if source == null:
		result.reason = "no pilot source given"
		return result
	if current_source != null and current_source != source:
		result.reason = "ship already controlled by %s" % current_source.source_id
		return result
	result.granted = true
	if current_source == null:
		current_source = source
		current_seat_id = seat_id
		control_changed.emit(null, source)
	return result


func release_control(source: PilotSource) -> void:
	if source == null or source != current_source:
		return
	current_source = null
	current_seat_id = &""
	control_changed.emit(source, null)


func is_parked() -> bool:
	return current_source == null


func poll_command(ship_state: ShipState, delta: float) -> PilotCommand:
	if current_source == null:
		return PilotCommand.parked(ship_state.gear)
	var command := current_source.poll(ship_state, delta)
	command.source_id = current_source.source_id
	return command
