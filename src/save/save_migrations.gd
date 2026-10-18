class_name SaveMigrations
extends RefCounted
## Upgrades old save data one version at a time (v1 -> v2 -> ...). Fixtures of every released
## version live in tests/fixtures/saves/ and must keep loading. v1 to v11 exist.


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


## Each case turns version N into N+1. v1 -> v2 added the "pois" section (nothing discovered yet).
static func _step_up(data: Dictionary) -> Dictionary:
	var upgraded := data.duplicate(true)
	match int(data["save_version"]):
		1:
			upgraded["pois"] = {"generation_version": 1, "discovered": []}
		2:
			upgraded["world"] = {"time": 0.0, "frame": "planet"} # v2 had one planet, whose frame was "planet"
		3:
			upgraded["ship"]["hull"] = 1.0 # v4 added hull damage and the suit
			upgraded["player"]["suit"] = {"oxygen": 1.0, "fuel": 1.0, "health": 1.0}
		4:
			upgraded["ship"]["fuel"] = 1.0 # v5 added ship fuel, the inventory and looted crates
			upgraded["pois"]["looted"] = []
			upgraded["inventory"] = {"oxygen_tank": 1, "repair_kit": 1}
		5:
			upgraded["pois"]["cleared"] = [] # v6 added destroyed POI guards
		10:
			# v11 put the Mayday mission (3 more objectives) before the last story step.
			var progress_data: Dictionary = upgraded.get("progress", {})
			if int(progress_data.get("objective", 0)) >= 4:
				progress_data["objective"] = int(progress_data["objective"]) + 3
		9:
			# v10 rebuilt the ship: six rooms instead of three. The airlock and ramp moved 4.6 m aft, so anyone saved
			# in them moves with them; the old cabin is now cabin + engineering and needs no change.
			var interior_position: Array = upgraded.get("player", {}).get("interior_position", [])
			if interior_position.size() == 3 and float(interior_position[2]) >= 3.4:
				interior_position[2] = float(interior_position[2]) + 4.6
		8:
			upgraded["systems"] = {"subsystems": [1.0, 1.0, 1.0, 1.0], "power": {}} # v9 added ship subsystems and the reactor; old ships are intact and cold
		7:
			upgraded["upgrades"] = [] # v8 added ship upgrades
		6:
			upgraded["progress"] = {"objective": 0, "warp_installed": true} # v7 added the story; old saves keep the open-space access they had
	upgraded["save_version"] = int(data["save_version"]) + 1
	return upgraded
