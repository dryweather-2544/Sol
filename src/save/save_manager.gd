class_name SaveManager
extends RefCounted
## Reads and writes save files safely. A file is {"checksum": SHA-256 of the body text, "body":
## the save data as text}. Writes go to slot.tmp first and are renamed into place, the previous
## good file is kept as slot.bak, and a file whose checksum fails is never trusted.

var directory := "user://saves"


func _init(save_directory: String = "user://saves") -> void:
	directory = save_directory


func path_for(slot: String) -> String:
	return directory.path_join(slot + ".json")


## Returns "" on success or an error message.
func save(slot: String, data: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(directory)
	var body_text := JSON.stringify(data, "", true)
	var wrapper_text := JSON.stringify({"checksum": body_text.sha256_text(), "body": body_text})
	var final_path := path_for(slot)
	var temporary_path := final_path + ".tmp"
	var temporary_file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if temporary_file == null:
		return "cannot write %s (error %d)" % [temporary_path, FileAccess.get_open_error()]
	temporary_file.store_string(wrapper_text)
	temporary_file.flush()
	temporary_file.close()
	if FileAccess.file_exists(final_path):
		DirAccess.copy_absolute(final_path, final_path + ".bak")
	var rename_error := DirAccess.rename_absolute(temporary_path, final_path)
	if rename_error != OK:
		return "cannot move the new save into place (error %d)" % rename_error
	return ""


## Returns {ok, data, error, used_backup}. Falls back to slot.bak if the main file is damaged.
func load_slot(slot: String) -> Dictionary:
	var main_result := _read_file(path_for(slot))
	if main_result["ok"]:
		main_result["used_backup"] = false
		return main_result
	var backup_result := _read_file(path_for(slot) + ".bak")
	if backup_result["ok"]:
		backup_result["used_backup"] = true
		return backup_result
	main_result["used_backup"] = false
	return main_result


func _read_file(path: String) -> Dictionary:
	var failure := {"ok": false, "data": {}, "error": ""}
	if not FileAccess.file_exists(path):
		failure["error"] = "no save at %s" % path
		return failure
	var text := FileAccess.get_file_as_string(path)
	var wrapper_parser := JSON.new()
	if wrapper_parser.parse(text) != OK or typeof(wrapper_parser.data) != TYPE_DICTIONARY:
		failure["error"] = "save file is damaged (unreadable)"
		return failure
	var wrapper: Dictionary = wrapper_parser.data
	if not wrapper.has("body") or not wrapper.has("checksum"):
		failure["error"] = "save file is damaged (unreadable)"
		return failure
	if String(wrapper["body"]).sha256_text() != String(wrapper["checksum"]):
		failure["error"] = "save file is damaged (checksum mismatch)"
		return failure
	var body_parser := JSON.new()
	if body_parser.parse(String(wrapper["body"])) != OK or typeof(body_parser.data) != TYPE_DICTIONARY:
		failure["error"] = "save body is not valid data"
		return failure
	var migrated := SaveMigrations.migrate(body_parser.data)
	if not migrated["ok"]:
		failure["error"] = migrated["error"]
		return failure
	return {"ok": true, "data": migrated["data"], "error": ""}
