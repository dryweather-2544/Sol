extends "res://tests/test_case.gd"
## N9: the copied .png.import files keep the settings the assets were authored with. Copying PNGs alone would import them with Godot's
## defaults (no VRAM compression, normal maps unflagged), so the .import files travel with them and are checked here.

func _all_import_files(directory_path: String, found: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	for file_name in directory.get_files():
		if file_name.ends_with(".png.import"):
			found.append(directory_path.path_join(file_name))
	for sub_directory in directory.get_directories():
		_all_import_files(directory_path.path_join(sub_directory), found)


func _setting(text: String, key: String) -> String:
	for line in text.split("\n"):
		if line.begins_with(key + "="):
			return line.trim_prefix(key + "=")
	return ""


func test_import_settings_per_texture_kind() -> void:
	var files: Array[String] = []
	_all_import_files("res://assets/sol", files)
	assert_true(files.size() > 0, "there are imported textures")
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		var short_name := path.trim_prefix("res://assets/sol/")
		var is_sky := short_name.begins_with("sky/")
		assert_eq(_setting(text, "mipmaps/generate"), "false" if is_sky else "true", "%s: mipmaps %s" % [short_name, "off for the sky" if is_sky else "on"])
		if short_name.ends_with("_height.png.import"):
			assert_eq(_setting(text, "compress/mode"), "0", "%s: height maps are lossless" % short_name)
		else:
			assert_eq(_setting(text, "compress/mode"), "2", "%s: VRAM compressed" % short_name)
		if short_name.ends_with("_normal.png.import"):
			assert_eq(_setting(text, "compress/normal_map"), "1", "%s: flagged as a normal map" % short_name)
		assert_eq(_setting(text, "source_file"), "\"res://assets/sol/%s\"" % short_name.trim_suffix(".import"), "%s: source_file names its own png" % short_name)
