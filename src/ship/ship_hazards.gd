class_name ShipHazards
extends RefCounted
## Air and fire, room by room (research: PULSAR 05 §4: fire burns oxygen and damages systems, life support
## restores air). Every ship room except the airlock (which has its own pressure) holds 0..1 oxygen and 0..1
## fire. Fire starts when a subsystem takes enough damage, grows while there is air, burns the room's air and
## the subsystems housed there, spreads through open doors, and starves when the air runs low. Closed doors
## contain it. Fully deterministic (no random numbers). Pure logic, ticked by ShipSystems.

const OXYGEN_FLOW_PER_SECOND := 0.25 ## exchange rate across an open doorway
const LIFE_SUPPORT_REFILL_PER_SECOND := 0.03 ## at full life support, in every room
const FIRE_START_INTENSITY := 0.25
const FIRE_GROWTH_PER_SECOND := 0.04
const FIRE_OXYGEN_USE_PER_SECOND := 0.05 ## at intensity 1
const FIRE_STARVES_BELOW := 0.12
const FIRE_DECAY_STARVED_PER_SECOND := 0.2
const FIRE_SPREAD_MIN_INTENSITY := 0.5
const FIRE_SPREAD_PROGRESS_NEEDED := 6.0 ## intensity-seconds through an open doorway before the next room catches
const FIRE_SPREAD_NEEDS_OXYGEN := 0.3
const SUBSYSTEM_BURN_PER_SECOND := 0.02 ## health lost at intensity 1
const IGNITION_THRESHOLD := 0.15 ## accumulated subsystem damage that starts a fire
const IGNITION_DECAY_PER_SECOND := 0.01
const LOW_OXYGEN := 0.3 ## below this a person needs their suit

## Which room houses the parts that a hit to this subsystem breaks.
const SUBSYSTEM_ROOM := {
	ShipSubsystems.Id.ENGINES: &"engineering", ShipSubsystems.Id.WEAPONS: &"turret_room",
	ShipSubsystems.Id.REACTOR: &"engineering", ShipSubsystems.Id.LIFE_SUPPORT: &"cabin"}
## Which subsystems a fire in a room damages.
const ROOM_SUBSYSTEMS := {
	&"engineering": [ShipSubsystems.Id.REACTOR, ShipSubsystems.Id.ENGINES],
	&"turret_room": [ShipSubsystems.Id.WEAPONS], &"cabin": [ShipSubsystems.Id.LIFE_SUPPORT]}

var oxygen := {}   # room id -> 0..1
var fire := {}     # room id -> 0..1 intensity
var _ignition := {}
var _spread := {}  # "from>to" -> accumulated intensity-seconds
var _links: Array = [] # [portal_id, room_a, room_b]


func _init(layout: InteriorLayout) -> void:
	for room_id in layout.rooms:
		if room_id == &"airlock":
			continue
		oxygen[room_id] = 1.0
		fire[room_id] = 0.0
		_ignition[room_id] = 0.0
	for portal_id in layout.portals:
		var joined := layout.portal_rooms(portal_id)
		if joined.size() == 2 and oxygen.has(joined[0]) and oxygen.has(joined[1]):
			_links.append([portal_id, joined[0], joined[1]])


func has_room(room_id: StringName) -> bool:
	return oxygen.has(room_id)


func oxygen_in(room_id: StringName) -> float:
	return oxygen.get(room_id, 1.0)


func is_breathable(room_id: StringName) -> bool:
	return oxygen_in(room_id) >= LOW_OXYGEN


func fire_in(room_id: StringName) -> float:
	return fire.get(room_id, 0.0)


func burning_rooms() -> Array[StringName]:
	var rooms: Array[StringName] = []
	for room_id in fire:
		if fire[room_id] > 0.0:
			rooms.append(room_id)
	return rooms


func any_fire() -> bool:
	return not burning_rooms().is_empty()


func ignite(room_id: StringName) -> bool:
	if not oxygen.has(room_id) or fire[room_id] > 0.0 or oxygen[room_id] < FIRE_SPREAD_NEEDS_OXYGEN:
		return false
	fire[room_id] = FIRE_START_INTENSITY
	return true


## A subsystem in this room took damage; enough of it starts a fire. Returns true if one started.
func add_ignition_risk(room_id: StringName, hull_damage: float) -> bool:
	if not _ignition.has(room_id):
		return false
	_ignition[room_id] += hull_damage
	if _ignition[room_id] >= IGNITION_THRESHOLD:
		_ignition[room_id] = 0.0
		return ignite(room_id)
	return false


## Returns true if there was fire to fight.
func extinguish(room_id: StringName, amount: float) -> bool:
	if fire_in(room_id) <= 0.0:
		return false
	fire[room_id] = maxf(0.0, fire[room_id] - amount)
	return true


## Advances by delta. Returns {subsystem id -> health to burn off} for ShipSystems to apply.
func update(delta: float, layout: InteriorLayout, life_support_factor: float) -> Dictionary:
	var burn := {}
	for room_id in fire:
		var intensity: float = fire[room_id]
		if intensity <= 0.0:
			continue
		if oxygen[room_id] < FIRE_STARVES_BELOW:
			fire[room_id] = maxf(0.0, intensity - FIRE_DECAY_STARVED_PER_SECOND * delta)
			continue
		fire[room_id] = minf(1.0, intensity + FIRE_GROWTH_PER_SECOND * delta)
		oxygen[room_id] = maxf(0.0, oxygen[room_id] - FIRE_OXYGEN_USE_PER_SECOND * intensity * delta)
		for subsystem_id in ROOM_SUBSYSTEMS.get(room_id, []):
			burn[subsystem_id] = burn.get(subsystem_id, 0.0) + SUBSYSTEM_BURN_PER_SECOND * intensity * delta
	for link in _links:
		var portal: Portal = layout.portals[link[0]]
		if not portal.is_passable():
			continue
		var room_a: StringName = link[1]
		var room_b: StringName = link[2]
		var transfer: float = (oxygen[room_a] - oxygen[room_b]) * minf(1.0, OXYGEN_FLOW_PER_SECOND * delta) * 0.5
		oxygen[room_a] -= transfer
		oxygen[room_b] += transfer
		_try_spread(room_a, room_b, delta)
		_try_spread(room_b, room_a, delta)
	for room_id in oxygen:
		oxygen[room_id] = minf(1.0, oxygen[room_id] + LIFE_SUPPORT_REFILL_PER_SECOND * life_support_factor * delta)
		_ignition[room_id] = maxf(0.0, _ignition[room_id] - IGNITION_DECAY_PER_SECOND * delta)
	return burn


func _try_spread(from_room: StringName, to_room: StringName, delta: float) -> void:
	var key := "%s>%s" % [from_room, to_room]
	if fire[from_room] < FIRE_SPREAD_MIN_INTENSITY or fire[to_room] > 0.0:
		_spread[key] = 0.0
		return
	_spread[key] = _spread.get(key, 0.0) + fire[from_room] * delta
	if _spread[key] >= FIRE_SPREAD_PROGRESS_NEEDED and ignite(to_room):
		_spread[key] = 0.0


func to_dictionary() -> Dictionary:
	var saved_oxygen := {}
	var saved_fire := {}
	for room_id in oxygen:
		saved_oxygen[String(room_id)] = oxygen[room_id]
		saved_fire[String(room_id)] = fire[room_id]
	return {"oxygen": saved_oxygen, "fire": saved_fire}


func restore(data: Dictionary) -> void:
	for room_id in oxygen:
		oxygen[room_id] = clampf(float(data.get("oxygen", {}).get(String(room_id), 1.0)), 0.0, 1.0)
		fire[room_id] = clampf(float(data.get("fire", {}).get(String(room_id), 0.0)), 0.0, 1.0)
		_ignition[room_id] = 0.0
	_spread.clear()
