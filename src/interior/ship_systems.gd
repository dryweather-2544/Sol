class_name ShipSystems
extends RefCounted
## The ship's interior state in one place: layout, airlock, walkway, seats, and the interlocks
## that tie them to flight (no takeoff with the outer door open or the walkway out; the outer
## door only opens when landed and slow). Pure logic, ticked by the game each physics step.

var layout := InteriorLayout.player_ship()
var airlock: AirlockController
var walkway := WalkwayController.new()
var seats := SeatManager.new([&"pilot_seat"])
## portal id -> true while a person is standing in (or beside) that doorway; set by the game each tick.
## A door never closes on someone.
var occupied_portals := {}
## 0..1 air pressure in the airlock room; vents to the outside when the outer door is open.
var airlock_pressure := 1.0
## Pressure outside (1 on a breathable world, 0 in vacuum or toxic air); set by the game each tick.
var ambient_pressure := 1.0
## Set by the outer-door toggle: close the outer door once the walkway has stowed.
var _outer_close_pending := false


func _init() -> void:
	airlock = AirlockController.new(layout.portals[&"airlock_inner"], layout.portals[&"airlock_outer"])


func update(delta: float, ship_state: ShipState) -> void:
	for portal in layout.portals.values():
		if portal != airlock.inner and portal != airlock.outer:
			(portal as Portal).update(delta)
	airlock.update(delta)
	walkway.update(delta, ship_state)
	if airlock.outer.open_factor > 0.0:
		airlock_pressure = move_toward(airlock_pressure, ambient_pressure, delta / 0.8)
	else:
		airlock_pressure = move_toward(airlock_pressure, 1.0, delta / AirlockController.CYCLE_SECONDS)
	seats.update(delta)
	layout.ramp_walkable = walkway.is_deployed()
	if _outer_close_pending and walkway.is_stowed() and not _is_occupied(&"airlock_outer"):
		airlock.request_close_outer(false)
		_outer_close_pending = false


## Empty string when the ship may lift off; otherwise why not.
func takeoff_block_reason() -> String:
	if walkway.occupied:
		return "Walkway occupied"
	if not walkway.is_stowed() or airlock.outer.open_factor > 0.0 or airlock.outer.target_open:
		return "Close the outer door and stow the walkway"
	return ""


## Interact with the inner door panel. Returns a message ("" on success).
func toggle_inner_door() -> String:
	var result: int
	if airlock.inner.target_open:
		result = airlock.request_close_inner(_is_occupied(&"airlock_inner"))
	elif airlock_pressure < 0.99:
		return "Airlock is still pressurising"
	else:
		result = airlock.request_open_inner()
	return AirlockController.describe(result)


## Interact with the outer door panel: opens (and deploys the walkway) or stows and closes.
func toggle_outer_door(ship_state: ShipState) -> String:
	if airlock.outer.target_open:
		if walkway.occupied or _is_occupied(&"airlock_outer"):
			return "Someone is in the way"
		walkway.request_retract()
		_outer_close_pending = true
		return ""
	var result := airlock.request_open_outer(ship_state)
	if result == AirlockController.Result.OK and not walkway.request_deploy(ship_state):
		airlock.outer.target_open = false
		return "Cannot deploy the walkway"
	return AirlockController.describe(result)


func toggle_cockpit_door() -> String:
	var door: Portal = layout.portals[&"cockpit_door"]
	if door.target_open and _is_occupied(&"cockpit_door"):
		return "Someone is in the doorway"
	door.target_open = not door.target_open
	return ""


## Called when the pilot sits down: stow the walkway and close the outer door (nothing happens
## while someone is on the ramp; takeoff stays blocked until it is done).
func secure_for_takeoff() -> void:
	if walkway.occupied:
		return
	if airlock.outer.target_open or airlock.outer.open_factor > 0.0:
		walkway.request_retract()
		_outer_close_pending = true


func _is_occupied(portal_id: StringName) -> bool:
	return occupied_portals.get(portal_id, false)


## Drop queued actions (used when a save is loaded; the saved door/walkway states are authoritative).
func reset_pending_actions() -> void:
	_outer_close_pending = false
	seats.reset()
