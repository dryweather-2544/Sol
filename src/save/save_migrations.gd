class_name SaveMigrations
extends RefCounted
## Upgrades old save data one version at a time (v1 -> v2 -> ...). Fixtures of every released
## version live in tests/fixtures/saves/ and must keep loading. There is only v1 today.


## Returns {ok: bool, data: Dictionary, error: String}.
static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("save_version", 0))
	if version < 1:
		return {"ok": false, "data": data, "error": "save has no valid version"}
	if version > SaveGame.SAVE_VERSION:
		return {"ok": false, "data": data, "error": "save is from a newer game (v%d)" % version}
	var migrated := data
	while int(migrated["save_version"]) < SaveGame.SAVE_VERSION:
		migrated = _step_up(migrated)
	return {"ok": true, "data": migrated, "error": ""}


## Placeholder for the first real migration; each case turns version N into N+1.
static func _step_up(data: Dictionary) -> Dictionary:
	var upgraded := data.duplicate(true)
	upgraded["save_version"] = int(data["save_version"]) + 1
	return upgraded
