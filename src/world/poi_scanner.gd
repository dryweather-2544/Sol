class_name PoiScanner
extends RefCounted
## The handheld/ship scanner. A pulse reports the sites within RANGE of the player: how far, which way and what kind of
## signal. Undiscovered sites show only a class of signal ("Dense mineral reading"); walking within
## PoiDefinition.DISCOVER_RADIUS of one identifies it. Nothing outside RANGE is revealed, so exploring means moving.
## Pure functions over the POIs the PoiManager already knows: no per-frame world scan.

enum Status { UNKNOWN, DISCOVERED, INVESTIGATED }

const RANGE := 3000.0
const COOLDOWN_SECONDS := 4.0
## How long the scan readout stays on screen after a pulse.
const READOUT_SECONDS := 25.0


## True once every crate of the site has been emptied (a probe, deposit or anomaly has exactly one).
static func is_investigated(instance: PoiInstance, loot_log: LootLog) -> bool:
	var crate_count := PoiBuilder.crate_positions(instance).size()
	if crate_count == 0:
		return false
	for crate_index in crate_count:
		if not loot_log.is_looted(PoiBuilder.crate_id(instance, crate_index)):
			return false
	return true


static func status_of(instance: PoiInstance, discovery_log: DiscoveryLog, loot_log: LootLog) -> int:
	if not discovery_log.is_discovered(instance.id):
		return Status.UNKNOWN
	if is_investigated(instance, loot_log):
		return Status.INVESTIGATED
	return Status.DISCOVERED


## Sends a pulse: every site within RANGE becomes a remembered contact (if still unknown) and is returned nearest first.
static func pulse(viewer: WorldPos, forward: Vector3, instances: Array, discovery_log: DiscoveryLog, loot_log: LootLog) -> Array[Dictionary]:
	var contacts: Array[Dictionary] = []
	for instance in instances:
		if instance.position.frame_id != viewer.frame_id:
			continue
		if instance.position.distance_to(viewer) > RANGE:
			continue
		if not discovery_log.is_discovered(instance.id):
			discovery_log.add_contact(instance.id)
		contacts.append(_contact(instance, viewer, forward, discovery_log, loot_log))
	_sort_nearest_first(contacts)
	return contacts


## What the readout shows between pulses: remembered contacts and discovered-but-unfinished sites in range, nearest first.
static func live_contacts(viewer: WorldPos, forward: Vector3, instances: Array, discovery_log: DiscoveryLog, loot_log: LootLog) -> Array[Dictionary]:
	var contacts: Array[Dictionary] = []
	for instance in instances:
		if instance.position.frame_id != viewer.frame_id:
			continue
		if not discovery_log.is_discovered(instance.id) and not discovery_log.is_contact(instance.id):
			continue
		if instance.position.distance_to(viewer) > RANGE:
			continue
		var contact := _contact(instance, viewer, forward, discovery_log, loot_log)
		if contact["status"] == Status.INVESTIGATED:
			continue
		contacts.append(contact)
	_sort_nearest_first(contacts)
	return contacts


static func _sort_nearest_first(contacts: Array[Dictionary]) -> void:
	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])


static func _contact(instance: PoiInstance, viewer: WorldPos, forward: Vector3, discovery_log: DiscoveryLog, loot_log: LootLog) -> Dictionary:
	var offset := instance.position.vector_from(viewer)
	var status := status_of(instance, discovery_log, loot_log)
	return {
		"id": instance.id,
		"distance": offset.length(),
		"bearing": bearing_degrees(viewer, forward, offset),
		"status": status,
		"label": String(PoiDefinition.SIGNAL_NAMES[instance.type]) if status == Status.UNKNOWN else instance.display_name,
		"type": instance.type,
	}


## Angle of `offset` from the way the player faces, in the ground plane: 0 ahead, positive to the right, +-180 behind.
static func bearing_degrees(viewer: WorldPos, forward: Vector3, offset: Vector3) -> float:
	var up := Vector3(viewer.x, viewer.y, viewer.z).normalized()
	var ahead := forward - up * forward.dot(up)
	var toward := offset - up * offset.dot(up)
	if up == Vector3.ZERO or ahead.length() < 1e-4 or toward.length() < 1.0:
		return 0.0
	return -rad_to_deg(ahead.signed_angle_to(toward, up))


static func direction_text(bearing: float) -> String:
	var magnitude := absf(bearing)
	var side := "right" if bearing > 0.0 else "left"
	if magnitude < 22.5:
		return "ahead"
	if magnitude < 67.5:
		return "ahead " + side
	if magnitude < 112.5:
		return side
	if magnitude < 157.5:
		return "behind " + side
	return "behind"


static func distance_text(metres: float) -> String:
	if metres < 1000.0:
		return "%d m" % roundi(metres)
	return "%.1f km" % (metres / 1000.0)


static func status_text(status: int) -> String:
	match status:
		Status.UNKNOWN: return "unidentified"
		Status.DISCOVERED: return "to investigate"
	return "investigated"


## Up to max_lines lines for the screen: "Dense mineral reading  1.4 km  ahead right  (unidentified)".
static func readout(contacts: Array[Dictionary], max_lines: int = 3) -> String:
	var lines: Array[String] = []
	for contact in contacts:
		if lines.size() >= max_lines:
			break
		lines.append("%s   %s   %s   (%s)" % [contact["label"], distance_text(contact["distance"]), direction_text(contact["bearing"]), status_text(contact["status"])])
	return "\n".join(lines)
