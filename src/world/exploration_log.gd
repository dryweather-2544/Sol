class_name ExplorationLog
extends RefCounted
## Turns the discovery log and the loot ledger into the rows of the exploration log screen (J). Pure, so tests read it too.


## One row per discovered site, in discovery order:
## {id, name, type_name, location, status ("investigated"/"not investigated"/"visited"), detail, reward}.
static func rows(discovery_log: DiscoveryLog, loot_log: LootLog) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for poi_id in discovery_log.order:
		var type: int = discovery_log.types.get(poi_id, -1)
		var total: int = discovery_log.crate_totals.get(poi_id, 0)
		var searched := 0
		for crate_index in total:
			if loot_log.is_looted(StringName("%s#%d" % [poi_id, crate_index])):
				searched += 1
		var status := "visited"
		if type >= 0 and total > 0:
			status = "investigated" if searched >= total else "not investigated"
		var detail := ""
		var reward := ""
		if type >= 0 and PoiDefinition.is_minor(type):
			if status == "investigated":
				detail = PoiDefinition.finding_text(type, discovery_log.seeds.get(poi_id, 0))
				reward = _reward_text(LootTable.roll(discovery_log.seeds.get(poi_id, 0), type, 0))
		elif type >= 0 and total > 0:
			detail = "%d of %d crates searched" % [searched, total]
		result.append({
			"id": poi_id,
			"name": discovery_log.names.get(poi_id, String(poi_id)),
			"type_name": String(PoiDefinition.TYPE_NAMES.get(type, "Site")),
			"location": location_text(discovery_log.positions.get(poi_id)),
			"status": status,
			"detail": detail,
			"reward": reward,
		})
	return result


static func summary(discovery_log: DiscoveryLog, loot_log: LootLog) -> String:
	var investigated := 0
	for row in rows(discovery_log, loot_log):
		if row["status"] == "investigated":
			investigated += 1
	return "Discovered %d   Investigated %d   Signals not yet identified %d" % [discovery_log.count(), investigated, discovery_log.unidentified_contact_count()]


## "Selene  12.3 N  45.6 E" from a planet-frame position, or "" if unknown.
static func location_text(position: Variant) -> String:
	if position == null:
		return ""
	var point: WorldPos = position
	var length := sqrt(point.x * point.x + point.y * point.y + point.z * point.z)
	if length <= 0.0:
		return String(point.frame_id).capitalize()
	var latitude := rad_to_deg(asin(clampf(point.y / length, -1.0, 1.0)))
	var longitude := rad_to_deg(atan2(point.x, point.z))
	return "%s   %.1f° %s  %.1f° %s" % [String(point.frame_id).capitalize(), absf(latitude), "N" if latitude >= 0.0 else "S", absf(longitude), "E" if longitude >= 0.0 else "W"]


static func _reward_text(contents: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for entry in contents:
		parts.append("%d %s" % [entry["count"], ItemDefinition.display_name(entry["item"])])
	return ", ".join(parts)
