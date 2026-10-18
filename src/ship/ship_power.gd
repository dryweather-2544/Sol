class_name ShipPower
extends RefCounted
## The reactor as a negotiation (research: PULSAR 05 §10.1-10.2, clean-room model, no numbers taken):
## a finite output shared by three conduits, each capped by a limit the crew sets. Drawing power makes
## heat; past the safety limit the reactor shuts itself down until it has cooled. Coolant is a finite
## emergency vent. Pure logic, ticked by ShipSystems. Mutating calls return "" on success, else why not.
## All numbers are untuned first guesses.

enum Conduit { ENGINES, WEAPONS, LIFE_SUPPORT }

const MAX_OUTPUT := 100.0
## Temperature is a fraction of the safety limit: 0 = cold, 1 = automatic shutdown.
const HEAT_PER_SECOND_AT_FULL_OUTPUT := 0.02
## Cancels the heat of 80 % output, so sustained draw above that slowly heats the core.
const PASSIVE_COOLING_PER_SECOND := 0.016
const RESTART_BELOW_TEMPERATURE := 0.5
const COOLANT_PER_VENT := 0.25
const HEAT_REMOVED_PER_VENT := 0.3

## Scales what the reactor can make; set from the reactor subsystem's health.
var output_factor := 1.0
var temperature := 0.0
var coolant := 1.0
var _shut_down := false
var _limits := [1.0, 1.0, 1.0]
## Life support always draws a little, so an idle ship still uses power.
var _requests := [0.0, 0.0, 15.0]
var _delivered := [0.0, 0.0, 0.0]


func set_limit(conduit: Conduit, limit: float) -> String:
	_limits[conduit] = clampf(limit, 0.0, 1.0)
	_distribute()
	return ""


func limit(conduit: Conduit) -> float:
	return _limits[conduit]


## How much a conduit's consumers want (power units, 0..MAX_OUTPUT).
func set_request(conduit: Conduit, units: float) -> void:
	_requests[conduit] = clampf(units, 0.0, MAX_OUTPUT)
	_distribute()


func request(conduit: Conduit) -> float:
	return _requests[conduit]


## Fraction of what a conduit asked for that it actually gets (1 when it asked for nothing).
func satisfaction(conduit: Conduit) -> float:
	return 1.0 if _requests[conduit] <= 0.0 else _delivered[conduit] / _requests[conduit]


func to_dictionary() -> Dictionary:
	return {"temperature": temperature, "coolant": coolant, "shut_down": _shut_down, "limits": _limits.duplicate()}


func restore(data: Dictionary) -> void:
	temperature = float(data.get("temperature", 0.0))
	coolant = float(data.get("coolant", 1.0))
	_shut_down = bool(data.get("shut_down", false))
	var saved_limits: Array = data.get("limits", [1.0, 1.0, 1.0])
	for conduit in 3:
		_limits[conduit] = clampf(float(saved_limits[conduit]), 0.0, 1.0) if conduit < saved_limits.size() else 1.0
	_distribute()


func delivered(conduit: Conduit) -> float:
	return _delivered[conduit]


func total_delivered() -> float:
	return _delivered[0] + _delivered[1] + _delivered[2]


func output() -> float:
	return 0.0 if _shut_down else MAX_OUTPUT * output_factor


func is_shut_down() -> bool:
	return _shut_down


func vent_coolant() -> String:
	if coolant < COOLANT_PER_VENT - 0.0001:
		return "No coolant left"
	coolant = maxf(0.0, coolant - COOLANT_PER_VENT)
	temperature = maxf(0.0, temperature - HEAT_REMOVED_PER_VENT)
	return ""


func request_restart() -> String:
	if not _shut_down:
		return "Reactor is already running"
	if temperature >= RESTART_BELOW_TEMPERATURE:
		return "Core too hot to restart"
	_shut_down = false
	_distribute()
	return ""


func update(delta: float) -> void:
	_distribute()
	var heat := HEAT_PER_SECOND_AT_FULL_OUTPUT * total_delivered() / MAX_OUTPUT
	temperature = maxf(0.0, temperature + (heat - PASSIVE_COOLING_PER_SECOND) * delta)
	if temperature >= 1.0 and not _shut_down:
		_shut_down = true
		_distribute()


## Each conduit gets what it asks for up to its limit; if that adds up to more than the reactor makes,
## everyone is cut back by the same fraction.
func _distribute() -> void:
	var available := output()
	var wanted := [0.0, 0.0, 0.0]
	var total_wanted := 0.0
	for conduit in 3:
		wanted[conduit] = minf(_requests[conduit], _limits[conduit] * available)
		total_wanted += wanted[conduit]
	var scale := 1.0 if total_wanted <= available else available / total_wanted
	for conduit in 3:
		_delivered[conduit] = wanted[conduit] * scale
