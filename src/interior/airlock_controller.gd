class_name AirlockController
extends RefCounted
## Inner + outer door with one rule that can never be broken: the two are never open at the same
## time (open_factor of at least one is 0). Rodina's own interlock is disabled code (INT-11), so
## this is a Sol rule. After one door closes, the other waits CYCLE_SECONDS (pressure equalising).

enum Result { OK, BLOCKED_OTHER_DOOR_OPEN, BLOCKED_CYCLING, BLOCKED_MOVING, BLOCKED_NOT_LANDED, BLOCKED_OCCUPIED }

const CYCLE_SECONDS := 1.5
const OUTER_DOOR_MAX_SHIP_SPEED := 2.0

var inner: Portal
var outer: Portal
var _cycle_seconds_left := 0.0
var _door_waiting_for_cycle: Portal


func _init(inner_portal: Portal, outer_portal: Portal) -> void:
	inner = inner_portal
	outer = outer_portal


func request_open_inner() -> int:
	if outer.open_factor > 0.0 or outer.target_open:
		return Result.BLOCKED_OTHER_DOOR_OPEN
	if _door_waiting_for_cycle == inner and _cycle_seconds_left > 0.0:
		return Result.BLOCKED_CYCLING
	inner.target_open = true
	return Result.OK


func request_open_outer(ship_state: ShipState) -> int:
	if inner.open_factor > 0.0 or inner.target_open:
		return Result.BLOCKED_OTHER_DOOR_OPEN
	if _door_waiting_for_cycle == outer and _cycle_seconds_left > 0.0:
		return Result.BLOCKED_CYCLING
	if not ship_state.landed:
		return Result.BLOCKED_NOT_LANDED
	if ship_state.speed() > OUTER_DOOR_MAX_SHIP_SPEED:
		return Result.BLOCKED_MOVING
	outer.target_open = true
	return Result.OK


func request_close_inner(someone_in_doorway: bool) -> int:
	if someone_in_doorway:
		return Result.BLOCKED_OCCUPIED
	inner.target_open = false
	return Result.OK


func request_close_outer(someone_in_doorway: bool) -> int:
	if someone_in_doorway:
		return Result.BLOCKED_OCCUPIED
	outer.target_open = false
	return Result.OK


func update(delta: float) -> void:
	var inner_was_open := inner.open_factor > 0.0
	var outer_was_open := outer.open_factor > 0.0
	inner.update(delta)
	outer.update(delta)
	if inner_was_open and inner.open_factor <= 0.0:
		_start_cycle(outer)
	if outer_was_open and outer.open_factor <= 0.0:
		_start_cycle(inner)
	_cycle_seconds_left = maxf(0.0, _cycle_seconds_left - delta)


## The safety invariant, exposed so tests (and a debug overlay) can check it.
func is_invariant_ok() -> bool:
	return inner.open_factor <= 0.0 or outer.open_factor <= 0.0


func _start_cycle(door_that_must_wait: Portal) -> void:
	_door_waiting_for_cycle = door_that_must_wait
	_cycle_seconds_left = CYCLE_SECONDS


static func describe(result: int) -> String:
	match result:
		Result.BLOCKED_OTHER_DOOR_OPEN: return "Close the other airlock door first"
		Result.BLOCKED_CYCLING: return "Airlock is cycling"
		Result.BLOCKED_MOVING: return "Ship is moving too fast"
		Result.BLOCKED_NOT_LANDED: return "Ship is not landed"
		Result.BLOCKED_OCCUPIED: return "Someone is in the doorway"
	return ""
