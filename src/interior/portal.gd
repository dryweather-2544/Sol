class_name Portal
extends RefCounted
## One door/hatch. open_factor moves 0..1 toward the target; the opening only lets people through
## once it is nearly fully open.

enum Kind { DOOR, AIRLOCK_INNER, AIRLOCK_OUTER }

const OPEN_SECONDS := 0.8
const PASSABLE_FACTOR := 0.85

var id: StringName
var kind: int
## Footprint of the doorway in ship-local (x, z): Rect2.position = (x, z) of the minimum corner.
var opening: Rect2
var open_factor := 0.0
var target_open := false
## Seconds this door has stood open with nobody in the doorway (ShipSystems closes plain doors after AUTO_CLOSE_SECONDS).
var idle_open_seconds := 0.0


func _init(portal_id: StringName, portal_kind: int, doorway: Rect2) -> void:
	id = portal_id
	kind = portal_kind
	opening = doorway


func update(delta: float) -> void:
	open_factor = move_toward(open_factor, 1.0 if target_open else 0.0, delta / OPEN_SECONDS)


func is_passable() -> bool:
	return open_factor >= PASSABLE_FACTOR


func is_fully_closed() -> bool:
	return open_factor <= 0.0 and not target_open
