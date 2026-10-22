class_name DiscoveryLog
extends RefCounted
## Which POIs the player has discovered, keyed by per-instance id (Rodina keys by class name, which
## collides: research TRAP-09). Discovery fires once per POI.
## Also remembers scanner contacts: sites a scan pulse picked up but the player has not reached yet.
## Entries saved before the exploration log existed only have an id and a name; the extra fields default.

signal poi_discovered(instance: PoiInstance)

var _discovered := {} # id -> true
var order: Array[StringName] = []
var names := {}      # id -> display name (so the log screen works for POIs no longer planned)
var types := {}      # id -> PoiDefinition.Type
var seeds := {}      # id -> POI seed (the log re-derives research text and rewards from it)
var positions := {}  # id -> WorldPos where it lies
var crate_totals := {} # id -> number of crates the site holds
var _contacts := {}  # id -> true: scanned, not necessarily discovered


## Returns true only the first time.
func try_discover(instance: PoiInstance) -> bool:
	if _discovered.has(instance.id):
		return false
	_discovered[instance.id] = true
	order.append(instance.id)
	names[instance.id] = instance.display_name
	types[instance.id] = instance.type
	seeds[instance.id] = instance.seed_value
	positions[instance.id] = instance.position.duplicate_position()
	crate_totals[instance.id] = PoiBuilder.crate_positions(instance).size()
	poi_discovered.emit(instance)
	return true


func is_discovered(poi_id: StringName) -> bool:
	return _discovered.has(poi_id)


func count() -> int:
	return _discovered.size()


## A scan pulse picked up this site. Returns true only the first time.
func add_contact(poi_id: StringName) -> bool:
	if _contacts.has(poi_id):
		return false
	_contacts[poi_id] = true
	return true


func is_contact(poi_id: StringName) -> bool:
	return _contacts.has(poi_id)


## Contacts that have not been reached yet.
func unidentified_contact_count() -> int:
	var total := 0
	for poi_id in _contacts:
		if not _discovered.has(poi_id):
			total += 1
	return total


func contacts_to_array() -> Array:
	var ids: Array = []
	for poi_id in _contacts:
		ids.append(String(poi_id))
	ids.sort()
	return ids


func restore_contacts(ids: Array) -> void:
	_contacts.clear()
	for poi_id in ids:
		_contacts[StringName(String(poi_id))] = true


func to_array() -> Array:
	var entries: Array = []
	for poi_id in order:
		var entry := {"id": String(poi_id), "name": names.get(poi_id, "")}
		if types.has(poi_id):
			entry["type"] = int(types[poi_id])
			entry["seed"] = int(seeds.get(poi_id, 0))
			entry["crates"] = int(crate_totals.get(poi_id, 0))
		if positions.has(poi_id):
			entry["position"] = (positions[poi_id] as WorldPos).to_dictionary()
		entries.append(entry)
	return entries


func restore(entries: Array) -> void:
	_discovered.clear()
	order.clear()
	names.clear()
	types.clear()
	seeds.clear()
	positions.clear()
	crate_totals.clear()
	for entry in entries:
		var poi_id := StringName(String(entry["id"]))
		_discovered[poi_id] = true
		order.append(poi_id)
		names[poi_id] = String(entry.get("name", ""))
		if entry.has("type"):
			types[poi_id] = int(entry["type"])
			seeds[poi_id] = int(entry.get("seed", 0))
			crate_totals[poi_id] = int(entry.get("crates", 0))
		if entry.has("position"):
			positions[poi_id] = WorldPos.from_dictionary(entry["position"])
