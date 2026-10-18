class_name DiscoveryLog
extends RefCounted
## Which POIs the player has discovered, keyed by per-instance id (Rodina keys by class name, which
## collides: research TRAP-09). Discovery fires once per POI.

signal poi_discovered(instance: PoiInstance)

var _discovered := {} # id -> true
var order: Array[StringName] = []
var names := {}      # id -> display name (so the log screen works for POIs no longer planned)


## Returns true only the first time.
func try_discover(instance: PoiInstance) -> bool:
	if _discovered.has(instance.id):
		return false
	_discovered[instance.id] = true
	order.append(instance.id)
	names[instance.id] = instance.display_name
	poi_discovered.emit(instance)
	return true


func is_discovered(poi_id: StringName) -> bool:
	return _discovered.has(poi_id)


func count() -> int:
	return _discovered.size()


func to_array() -> Array:
	var entries: Array = []
	for poi_id in order:
		entries.append({"id": String(poi_id), "name": names.get(poi_id, "")})
	return entries


func restore(entries: Array) -> void:
	_discovered.clear()
	order.clear()
	names.clear()
	for entry in entries:
		var poi_id := StringName(String(entry["id"]))
		_discovered[poi_id] = true
		order.append(poi_id)
		names[poi_id] = String(entry.get("name", ""))
