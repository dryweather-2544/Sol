class_name ShipSubsystems
extends RefCounted
## Health of the parts of the ship that matter to the crew: 1 = fine, 0 = dead. Hull damage is shared
## with one subsystem (picked by where the hit landed), so a battered ship also gets slower, weaker and
## less able to make power. Pure logic. Research: PULSAR 05 §1.2 / §10.4 (damage splits into a system).

enum Id { ENGINES, WEAPONS, REACTOR, LIFE_SUPPORT }

## A hit of `amount` hull damage costs the struck subsystem this many times as much health.
const SYSTEM_DAMAGE_SHARE := 1.5
## Below this a subsystem still works, at its health fraction; this is the floor for engines so a ship with a
## dead drive can still make an emergency landing instead of falling out of the sky.
const EMERGENCY_THRUST := 0.15

var health := [1.0, 1.0, 1.0, 1.0]
var _round_robin := 0


static func label(id: int) -> String:
	return ["engines", "weapons", "reactor", "life support"][id]


## Which subsystem a hit lands on, from the hit direction in ship-local axes (nose is -z).
static func subsystem_for_direction(local_direction_to_attacker: Vector3) -> int:
	if local_direction_to_attacker.z > 0.5:
		return Id.ENGINES
	if local_direction_to_attacker.z < -0.5:
		return Id.WEAPONS
	if local_direction_to_attacker.y > 0.5:
		return Id.REACTOR
	return Id.LIFE_SUPPORT


## For hits with no known direction (drones, ground impacts): cycle through the systems, deterministically.
func next_round_robin() -> int:
	_round_robin = (_round_robin + 1) % 4
	return _round_robin


func damage(id: int, hull_damage: float) -> void:
	health[id] = maxf(0.0, health[id] - hull_damage * SYSTEM_DAMAGE_SHARE)


func value(id: int) -> float:
	return health[id]


func worst_id() -> int:
	var worst := 0
	for id in 4:
		if health[id] < health[worst]:
			worst = id
	return worst


func is_undamaged() -> bool:
	for id in 4:
		if health[id] < 1.0:
			return false
	return true


## Repairs the most damaged subsystem. Returns the label of what was repaired, "" if nothing needed it.
func repair_worst(amount: float) -> String:
	if is_undamaged():
		return ""
	var id := worst_id()
	health[id] = minf(1.0, health[id] + amount)
	return label(id)


func to_array() -> Array:
	return health.duplicate()


func restore(values: Array) -> void:
	for id in 4:
		health[id] = clampf(float(values[id]), 0.0, 1.0) if id < values.size() else 1.0
