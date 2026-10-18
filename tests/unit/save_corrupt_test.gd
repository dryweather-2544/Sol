extends "res://tests/test_case.gd"

const SAVE_DIRECTORY := "user://test_saves_corrupt"


func _sample(value: int) -> Dictionary:
	return {"save_version": SaveGame.SAVE_VERSION, "game_version": "test", "world_seed": value, "ship": {}, "player": {}, "interior": {}}


func _clean() -> SaveManager:
	var manager := SaveManager.new(SAVE_DIRECTORY)
	for file_name in ["slot.json", "slot.json.bak", "slot.json.tmp"]:
		DirAccess.remove_absolute(SAVE_DIRECTORY.path_join(file_name))
	return manager


func _write_raw(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_save_leaves_no_temp_file_and_keeps_previous_as_backup() -> void:
	var manager := _clean()
	assert_eq(manager.save("slot", _sample(1)), "")
	assert_true(not FileAccess.file_exists(manager.path_for("slot") + ".tmp"), "no .tmp left behind")
	assert_eq(manager.save("slot", _sample(2)), "")
	assert_true(FileAccess.file_exists(manager.path_for("slot") + ".bak"), "previous save kept as .bak")
	var loaded := manager.load_slot("slot")
	assert_true(loaded["ok"] and int(loaded["data"]["world_seed"]) == 2 and not loaded["used_backup"])


func test_truncated_main_file_falls_back_to_the_previous_save() -> void:
	var manager := _clean()
	manager.save("slot", _sample(1))
	manager.save("slot", _sample(2))
	var text := FileAccess.get_file_as_string(manager.path_for("slot"))
	_write_raw(manager.path_for("slot"), text.substr(0, text.length() / 2))
	var loaded := manager.load_slot("slot")
	assert_true(loaded["ok"], "backup should load: %s" % loaded["error"])
	assert_true(loaded["used_backup"], "reports it used the backup")
	assert_eq(int(loaded["data"]["world_seed"]), 1, "the previous save survives")


func test_checksum_mismatch_is_detected_and_reported_when_no_backup_exists() -> void:
	var manager := _clean()
	manager.save("slot", _sample(7))
	var text := FileAccess.get_file_as_string(manager.path_for("slot"))
	var tampered := text.replace("world_seed\\\":7", "world_seed\\\":8")
	assert_true(tampered != text, "the test really changed the file")
	_write_raw(manager.path_for("slot"), tampered)
	var loaded := manager.load_slot("slot")
	assert_true(not loaded["ok"], "tampered save must not load")
	assert_true(String(loaded["error"]).contains("checksum"), "clear error: %s" % loaded["error"])


func test_missing_and_future_version_saves_give_clear_errors() -> void:
	var manager := _clean()
	assert_true(not manager.load_slot("slot")["ok"])
	var future := _sample(1)
	future["save_version"] = SaveGame.SAVE_VERSION + 5
	manager.save("slot", future)
	var loaded := manager.load_slot("slot")
	assert_true(not loaded["ok"] and String(loaded["error"]).contains("newer"), loaded["error"])


func test_committed_v1_fixture_still_loads_and_restores() -> void:
	# tests/fixtures/saves/v1_landed_seated.json was written by SaveGame v1 and must load forever.
	var manager := SaveManager.new(ProjectSettings.globalize_path("res://tests/fixtures/saves"))
	var loaded := manager.load_slot("v1_landed_seated")
	assert_true(loaded["ok"], "fixture failed to load: %s" % loaded["error"])
	assert_eq(int(loaded["data"]["save_version"]), SaveGame.SAVE_VERSION, "v1 file is migrated up on load")
	assert_eq(int(loaded["data"]["world_seed"]), 42)
	var planet := PlanetBody.new()
	var ship := Ship.new()
	ship.planet = planet
	ship.render_origin = WorldPos.new(planet.frame_id)
	var session := GameSession.new(planet, ship, PilotSource.new())
	assert_eq(SaveGame.restore(session, loaded["data"]), "")
	assert_true(ship.state.landed and session.mode == GameSession.Mode.SEATED)
	assert_eq(session.validate(), "")
	ship.free()
