class_name SuitState
extends RefCounted
## The player's suit: oxygen (drains when the air is not breathable, refills in a breathable place),
## jetpack fuel (drains while burning, recharges on the ground) and health (drains when out of oxygen).
## Pure logic; the game feeds it the situation each tick.

const OXYGEN_SECONDS := 180.0
const OXYGEN_REFILL_SECONDS := 10.0
const FUEL_BURN_SECONDS := 6.0
const FUEL_RECHARGE_SECONDS := 4.0
const SUFFOCATION_DAMAGE_PER_SECOND := 0.2
const HEAL_PER_SECOND := 0.1

signal died

## Multiplier on how long the tank lasts (suit tank upgrade).
var oxygen_duration_multiplier := 1.0
var oxygen := 1.0
var fuel := 1.0
var health := 1.0


func update(delta: float, breathable: bool, jetpack_burning: bool, grounded: bool) -> void:
	if breathable:
		oxygen = minf(1.0, oxygen + delta / OXYGEN_REFILL_SECONDS)
		if health > 0.0:
			health = minf(1.0, health + HEAL_PER_SECOND * delta)
	else:
		oxygen = maxf(0.0, oxygen - delta / (OXYGEN_SECONDS * oxygen_duration_multiplier))
		if oxygen <= 0.0 and health > 0.0:
			health = maxf(0.0, health - SUFFOCATION_DAMAGE_PER_SECOND * delta)
			if health <= 0.0:
				died.emit()
	if jetpack_burning:
		fuel = maxf(0.0, fuel - delta / FUEL_BURN_SECONDS)
	elif grounded:
		fuel = minf(1.0, fuel + delta / FUEL_RECHARGE_SECONDS)


## Heat from a fire in the room: costs health directly, whatever the air is like.
func burn(amount: float) -> void:
	if health <= 0.0:
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		died.emit()


func has_fuel() -> bool:
	return fuel > 0.0


func reset() -> void:
	oxygen = 1.0
	fuel = 1.0
	health = 1.0
