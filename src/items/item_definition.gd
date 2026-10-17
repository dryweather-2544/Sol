class_name ItemDefinition
extends RefCounted
## The item catalog. One place defines every item: its name, stack size and whether it can be used.

const FUEL_CELL: StringName = &"fuel_cell"
const OXYGEN_TANK: StringName = &"oxygen_tank"
const REPAIR_KIT: StringName = &"repair_kit"
const SCRAP: StringName = &"scrap"
const DATA_CHIP: StringName = &"data_chip"

const ITEMS := {
	FUEL_CELL: {"name": "Fuel cell", "stack": 5, "usable": true, "help": "Refuels the ship (+50%). Use near the ship."},
	OXYGEN_TANK: {"name": "Oxygen tank", "stack": 5, "usable": true, "help": "Refills your suit oxygen."},
	REPAIR_KIT: {"name": "Repair kit", "stack": 5, "usable": true, "help": "Repairs 50% of the hull. Use near the ship."},
	SCRAP: {"name": "Scrap metal", "stack": 50, "usable": false, "help": "Salvage. Not used yet."},
	DATA_CHIP: {"name": "Data chip", "stack": 10, "usable": false, "help": "Recovered data. Not used yet."},
}


static func exists(item_id: StringName) -> bool:
	return ITEMS.has(item_id)


static func display_name(item_id: StringName) -> String:
	return ITEMS[item_id]["name"]


static func stack_size(item_id: StringName) -> int:
	return ITEMS[item_id]["stack"]


static func is_usable(item_id: StringName) -> bool:
	return ITEMS[item_id]["usable"]
