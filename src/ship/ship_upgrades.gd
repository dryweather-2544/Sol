class_name ShipUpgrades
extends RefCounted
## Permanent improvements bought at the cabin workbench with salvage. Pure data and effect queries; the
## ship, suit and weapons read the multipliers.

const CATALOG := {
	&"hull_plating": {"name": "Hull plating", "cost": {&"scrap": 20}, "help": "Hull takes 30% less damage."},
	&"efficient_engines": {"name": "Efficient engines", "cost": {&"scrap": 15, &"data_chip": 1}, "help": "Cruise and boost burn 40% less fuel."},
	&"gun_amplifier": {"name": "Gun amplifier", "cost": {&"scrap": 15, &"data_chip": 2}, "help": "Ship guns do 50% more damage."},
	&"suit_tank": {"name": "Suit tank", "cost": {&"scrap": 10, &"data_chip": 1}, "help": "Suit oxygen lasts 60% longer."},
}

var owned := {} # id -> true


func has(upgrade_id: StringName) -> bool:
	return owned.has(upgrade_id)


func damage_taken_multiplier() -> float:
	return 0.7 if has(&"hull_plating") else 1.0


func fuel_burn_multiplier() -> float:
	return 0.6 if has(&"efficient_engines") else 1.0


func gun_damage_multiplier() -> float:
	return 1.5 if has(&"gun_amplifier") else 1.0


func oxygen_duration_multiplier() -> float:
	return 1.6 if has(&"suit_tank") else 1.0


## Returns "" when bought, else why not. Spends the cost from the inventory.
func buy(upgrade_id: StringName, inventory: Inventory) -> String:
	if not CATALOG.has(upgrade_id):
		return "Unknown upgrade"
	if has(upgrade_id):
		return "Already installed"
	var cost: Dictionary = CATALOG[upgrade_id]["cost"]
	for item_id in cost:
		if inventory.count(item_id) < cost[item_id]:
			return "Need %d %s" % [cost[item_id], ItemDefinition.display_name(item_id)]
	for item_id in cost:
		inventory.remove(item_id, cost[item_id])
	owned[upgrade_id] = true
	return ""


func to_array() -> Array:
	var ids: Array = []
	for upgrade_id in owned:
		ids.append(String(upgrade_id))
	ids.sort()
	return ids


func restore(ids: Array) -> void:
	owned.clear()
	for upgrade_id in ids:
		if CATALOG.has(StringName(String(upgrade_id))):
			owned[StringName(String(upgrade_id))] = true
