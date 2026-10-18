class_name LootTable
extends RefCounted
## Seeded loot: the same POI and crate always hold the same things (research ITM-13: a weighted
## grammar; Sol uses a flat weighted list per POI type). Pure and deterministic.

## Per POI type: [item id, weight, min count, max count]
const TABLES := {
	PoiDefinition.Type.WRECK: [[&"scrap", 6, 2, 8], [&"repair_kit", 2, 1, 1], [&"data_chip", 2, 1, 2], [&"fuel_cell", 1, 1, 1], [&"oxygen_tank", 1, 1, 1]],
	PoiDefinition.Type.BEACON: [[&"data_chip", 5, 1, 3], [&"oxygen_tank", 2, 1, 1], [&"fuel_cell", 2, 1, 1]],
	PoiDefinition.Type.OUTPOST: [[&"fuel_cell", 4, 1, 2], [&"oxygen_tank", 3, 1, 2], [&"repair_kit", 3, 1, 2], [&"scrap", 3, 3, 10], [&"data_chip", 1, 1, 1]],
}
const ROLLS_PER_CRATE := 2


## Items in one crate: Array of {"item": StringName, "count": int}.
static func roll(poi_seed: int, poi_type: int, crate_index: int) -> Array[Dictionary]:
	var rng := SeedRng.new(SeedHash.combine(SeedHash.combine(poi_seed, SeedHash.string_hash("loot")), crate_index))
	var table: Array = TABLES[poi_type]
	var total_weight := 0
	for entry in table:
		total_weight += int(entry[1])
	var stacks := {}
	for roll_index in ROLLS_PER_CRATE:
		var pick := rng.next_float() * total_weight
		var running := 0.0
		for entry in table:
			running += int(entry[1])
			if pick < running:
				stacks[entry[0]] = int(stacks.get(entry[0], 0)) + rng.next_int_in_range(int(entry[2]), int(entry[3]))
				break
	var result: Array[Dictionary] = []
	var item_ids := stacks.keys()
	item_ids.sort()
	for item_id in item_ids:
		result.append({"item": item_id, "count": stacks[item_id]})
	return result
