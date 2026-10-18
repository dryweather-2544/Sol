class_name Inventory
extends RefCounted
## The player's one item ledger (research ITM-03 warns of two): counts per item id, limited by a
## number of slots, where each item fills ceil(count / stack_size) slots.

signal changed

var slot_limit := 12
var _counts := {} # item id -> count


func count(item_id: StringName) -> int:
	return _counts.get(item_id, 0)


func slots_used() -> int:
	var used := 0
	for item_id in _counts:
		used += _slots_for(item_id, _counts[item_id])
	return used


func can_fit(item_id: StringName, amount: int) -> bool:
	var new_slots := slots_used() - _slots_for(item_id, count(item_id)) + _slots_for(item_id, count(item_id) + amount)
	return new_slots <= slot_limit


## Adds everything or nothing. Returns true if it all fit.
func add(item_id: StringName, amount: int) -> bool:
	if amount <= 0 or not ItemDefinition.exists(item_id) or not can_fit(item_id, amount):
		return false
	_counts[item_id] = count(item_id) + amount
	changed.emit()
	return true


func remove(item_id: StringName, amount: int) -> bool:
	if amount <= 0 or count(item_id) < amount:
		return false
	_counts[item_id] = count(item_id) - amount
	if _counts[item_id] == 0:
		_counts.erase(item_id)
	changed.emit()
	return true


func item_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for item_id in _counts:
		ids.append(item_id)
	ids.sort()
	return ids


func to_dictionary() -> Dictionary:
	var data := {}
	for item_id in _counts:
		data[String(item_id)] = _counts[item_id]
	return data


func restore(data: Dictionary) -> void:
	_counts.clear()
	for key in data:
		if ItemDefinition.exists(StringName(key)):
			_counts[StringName(key)] = int(data[key])
	changed.emit()


func _slots_for(item_id: StringName, amount: int) -> int:
	if amount <= 0:
		return 0
	return int(ceil(float(amount) / ItemDefinition.stack_size(item_id)))
