class_name ShipSystems
extends RefCounted
## The ship's interior state in one place: layout, airlock, walkway, seats, and the interlocks
## that tie them to flight (no takeoff with the outer door open or the walkway out; the outer
## door only opens when landed and slow). Pure logic, ticked by the game each physics step.

var layout := InteriorLayout.player_ship()
var airlock: AirlockController
var walkway := WalkwayController.new()
var seats := SeatManager.new([&"pilot_seat", &"gunner_seat"])
## portal id -> true while a person is standing in (or beside) that doorway; set by the game each tick.
## A door never closes on someone.
var occupied_portals := {}
## 0..1 air pressure in the airlock room; vents to the outside when the outer door is open.
var airlock_pressure := 1.0
## Pressure outside (1 on a breathable world, 0 in vacuum or toxic air); set by the game each tick.
var ambient_pressure := 1.0
## Reactor and conduits; ticked here, not yet wired to flight or weapons.
var power := ShipPower.new()
var subsystems := ShipSubsystems.new()
## Room air and fire.
var hazards := ShipHazards.new(layout)
## The dorsal gun the gunner works; its firing adds to the weapons conduit demand.
var turret := ShipTurret.new()
var turret_firing := false
## Set when the Mayday ambush starts: the next hit on the ship is a guaranteed engine hit and engineering fire.
var ambush_armed := false
signal ambush_hit
## What the airlock computer is working towards (&"in" or &"out"; &"" when idle) and what it tells the player.
var airlock_goal := &""
var airlock_status := ""
var _airlock_refusal := ""
## Set by the outer-door toggle: close the outer door once the walkway has stowed.
var _outer_close_pending := false

## Plain doors shut by themselves this long after the last person left the doorway (Rodina doors autoclose);
## it also stops fire and smoke spreading through doors left open. Airlock doors never do.
const DOOR_AUTO_CLOSE_SECONDS := 5.0
## Off only for scripted tests that leave doors open on purpose while the "player" is elsewhere.
var auto_close_enabled := true
const AUTO_RESTART_BELOW_TEMPERATURE := 0.2
const ENGINE_CAP_AFTER_AMBUSH := 0.6


func _init() -> void:
	airlock = AirlockController.new(layout.portals[&"airlock_inner"], layout.portals[&"airlock_outer"])


func update(delta: float, ship_state: ShipState) -> void:
	for portal in layout.portals.values():
		if portal != airlock.inner and portal != airlock.outer:
			(portal as Portal).update(delta)
			_auto_close(portal as Portal, delta)
	airlock.update(delta)
	if airlock_goal != &"":
		_step_airlock_goal(ship_state)
	walkway.update(delta, ship_state)
	if airlock.outer.open_factor > 0.0:
		airlock_pressure = move_toward(airlock_pressure, ambient_pressure, delta / 0.8)
	else:
		airlock_pressure = move_toward(airlock_pressure, 1.0, delta / AirlockController.CYCLE_SECONDS)
	seats.update(delta)
	power.output_factor = subsystems.value(ShipSubsystems.Id.REACTOR)
	power.update(delta)
	# A tripped reactor comes back by itself once it is properly cool (so a shutdown costs time, never the
	# run); the reactor panel can restart it earlier, from RESTART_BELOW_TEMPERATURE.
	if power.is_shut_down() and power.temperature < AUTO_RESTART_BELOW_TEMPERATURE:
		power.request_restart()
	var life_support_factor := power.satisfaction(ShipPower.Conduit.LIFE_SUPPORT) * subsystems.value(ShipSubsystems.Id.LIFE_SUPPORT)
	var burned := hazards.update(delta, layout, life_support_factor)
	for subsystem_id in burned:
		subsystems.drain(subsystem_id, burned[subsystem_id])
	layout.ramp_walkable = walkway.is_deployed()
	if _outer_close_pending and walkway.is_stowed() and not _is_occupied(&"airlock_outer"):
		airlock.request_close_outer(false)
		_outer_close_pending = false


## Hull damage that reached a subsystem; enough of it starts a fire in the room that houses it.
func damage_subsystem(subsystem_id: int, hull_damage: float) -> void:
	subsystems.damage(subsystem_id, hull_damage)
	hazards.add_ignition_risk(ShipHazards.SUBSYSTEM_ROOM[subsystem_id], hull_damage)


## Called when the ship is hit. Returns true if it was the scripted ambush hit.
func take_ambush_hit() -> bool:
	if not ambush_armed:
		return false
	ambush_armed = false
	subsystems.cap[ShipSubsystems.Id.ENGINES] = ENGINE_CAP_AFTER_AMBUSH # the coupling is burnt out: repairs cannot fully fix it
	damage_subsystem(ShipSubsystems.Id.ENGINES, 0.5)
	hazards.ignite(&"engineering")
	ambush_hit.emit()
	return true


## The reactor panel's controls. Every ship change a crew member makes goes through a request_*(actor_id, ...)
## that returns "" on success or the reason it was refused, so a host-authoritative layer could sit here later.
func request_set_limit(_actor_id: StringName, conduit: ShipPower.Conduit, limit: float) -> String:
	return power.set_limit(conduit, limit)


func request_vent_coolant(_actor_id: StringName) -> String:
	return power.vent_coolant()


func request_restart_reactor(_actor_id: StringName) -> String:
	return power.request_restart()


## What the pilot is asking of the ship this tick, in power units. Idle systems still draw a little.
func set_demand(command: PilotCommand) -> void:
	var thrust_draw := 35.0 * command.thrust.limit_length(1.0).length() + (20.0 if command.boost else 0.0)
	power.set_request(ShipPower.Conduit.ENGINES, 15.0 + thrust_draw)
	power.set_request(ShipPower.Conduit.WEAPONS, 5.0 + (25.0 if command.fire else 0.0) + (15.0 if turret_firing else 0.0))


## 0..1 multiplier on thrust: starved power and engine damage both slow the ship, but never below
## EMERGENCY_THRUST, so a crippled ship can still limp down to the ground.
func engine_factor() -> float:
	var factor := power.satisfaction(ShipPower.Conduit.ENGINES) * subsystems.value(ShipSubsystems.Id.ENGINES)
	return maxf(ShipSubsystems.EMERGENCY_THRUST, factor)


## 0..1 multiplier on rate of fire; 0 means the guns are dead.
func weapon_factor() -> float:
	return power.satisfaction(ShipPower.Conduit.WEAPONS) * subsystems.value(ShipSubsystems.Id.WEAPONS)


## Empty string when the ship may lift off; otherwise why not.
func takeoff_block_reason() -> String:
	if walkway.occupied:
		return "Walkway occupied"
	if not walkway.is_stowed() or airlock.outer.open_factor > 0.0 or airlock.outer.target_open:
		return "Close the outer door and stow the walkway"
	return ""


func _auto_close(door: Portal, delta: float) -> void:
	if not auto_close_enabled or not door.target_open or _is_occupied(door.id):
		door.idle_open_seconds = 0.0
		return
	door.idle_open_seconds += delta
	if door.idle_open_seconds >= DOOR_AUTO_CLOSE_SECONDS:
		door.target_open = false
		door.idle_open_seconds = 0.0


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


## Interact with one of the plain interior doors (cockpit_door, engineering_door, ...).
func toggle_door(portal_id: StringName) -> String:
	var door: Portal = layout.portals[portal_id]
	if door.target_open and _is_occupied(portal_id):
		return "Someone is in the doorway"
	door.target_open = not door.target_open
	return ""


## The airlock computer (Rodina's Open In / Close / Open Out). "in" and "out" run the whole sequence by themselves: close the
## door on the other side (stowing the ramp first if it is out), wait for the air, then open. "close" shuts whichever door is
## open. Returns "" or why it could not start; later trouble is left in airlock_status.
func request_airlock(goal: StringName, ship_state: ShipState) -> String:
	match goal:
		&"close":
			airlock_goal = &""
			airlock_status = ""
			if airlock.inner.target_open:
				return AirlockController.describe(airlock.request_close_inner(_is_occupied(&"airlock_inner")))
			if airlock.outer.target_open:
				return toggle_outer_door(ship_state)
			return ""
		&"in", &"out":
			airlock_goal = goal
			airlock_status = "Working..."
			_airlock_refusal = ""
			_step_airlock_goal(ship_state)
			return _airlock_refusal
	return ""


func _step_airlock_goal(ship_state: ShipState) -> void:
	if airlock_goal == &"in":
		if airlock.inner.target_open:
			_finish_airlock_goal("Inner door open")
		elif airlock.outer.target_open or airlock.outer.open_factor > 0.0:
			if airlock.outer.target_open and not _outer_close_pending:
				var refused := toggle_outer_door(ship_state) # stows the ramp, then closes the outer door
				if refused != "":
					_refuse_airlock_goal(refused)
					return
			airlock_status = "Closing the outer door..."
		elif airlock_pressure < 0.99:
			airlock_status = "Pressurising..."
		else:
			var result := airlock.request_open_inner()
			if result == AirlockController.Result.OK:
				_finish_airlock_goal("Inner door open")
			elif result == AirlockController.Result.BLOCKED_CYCLING:
				airlock_status = "Cycling..."
			else:
				_refuse_airlock_goal(AirlockController.describe(result))
	elif airlock_goal == &"out":
		if airlock.outer.target_open:
			_finish_airlock_goal("Outer door open")
		elif airlock.inner.target_open or airlock.inner.open_factor > 0.0:
			if airlock.inner.target_open:
				var closing := airlock.request_close_inner(_is_occupied(&"airlock_inner"))
				if closing != AirlockController.Result.OK:
					_refuse_airlock_goal(AirlockController.describe(closing))
					return
			airlock_status = "Closing the inner door..."
		else:
			var refused := toggle_outer_door(ship_state)
			if refused == "":
				_finish_airlock_goal("Outer door open")
			elif refused == AirlockController.describe(AirlockController.Result.BLOCKED_CYCLING):
				airlock_status = "Cycling..."
			else:
				_refuse_airlock_goal(refused)


func _finish_airlock_goal(status: String) -> void:
	airlock_goal = &""
	airlock_status = status


func _refuse_airlock_goal(reason: String) -> void:
	_finish_airlock_goal(reason)
	_airlock_refusal = reason


## Called when the pilot sits down: stow the walkway and close the outer door (nothing happens
## while someone is on the ramp; takeoff stays blocked until it is done).
func secure_for_takeoff() -> void:
	airlock_goal = &""
	if walkway.occupied:
		return
	if airlock.outer.target_open or airlock.outer.open_factor > 0.0:
		walkway.request_retract()
		_outer_close_pending = true


func is_portal_occupied(portal_id: StringName) -> bool:
	return _is_occupied(portal_id)


func _is_occupied(portal_id: StringName) -> bool:
	return occupied_portals.get(portal_id, false)


## Drop queued actions (used when a save is loaded; the saved door/walkway states are authoritative).
func reset_pending_actions() -> void:
	_outer_close_pending = false
	airlock_goal = &""
	airlock_status = ""
	seats.reset()
