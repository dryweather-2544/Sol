class_name LootLog
extends RefCounted
## Which crates have been emptied, by id "<poi id>#<crate index>". Saved with the game.

var _looted := {}


func is_looted(crate_id: StringName) -> bool:
	return _looted.has(crate_id)


func mark_looted(crate_id: StringName) -> void:
	_looted[crate_id] = true


func to_array() -> Array:
	var ids: Array = []
	for crate_id in _looted:
		ids.append(String(crate_id))
	ids.sort()
	return ids


func restore(ids: Array) -> void:
	_looted.clear()
	for crate_id in ids:
		_looted[StringName(String(crate_id))] = true
