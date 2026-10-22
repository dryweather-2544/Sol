extends "res://tests/test_case.gd"
## N9: assets/sol/SOURCE.txt must describe exactly the files that are there (catches a hand edit or a half-finished copy), and no
## copied .tres may point back into the lookdev folders. The same checks run without Godot in tools/asset_usage_check.py.

const HASHED_SUFFIXES := [".png", ".tres", ".wav", ".md"]


func _all_files(directory_path: String, found: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	for file_name in directory.get_files():
		found.append(directory_path.path_join(file_name))
	for sub_directory in directory.get_directories():
		_all_files(directory_path.path_join(sub_directory), found)


func test_source_file_matches_the_copied_files() -> void:
	var source_text := FileAccess.get_file_as_string("res://assets/sol/SOURCE.txt")
	assert_true(source_text != "", "assets/sol/SOURCE.txt exists")
	# SOURCE.txt is generated from the imported asset set; the project's own generated assets (screens, trim, interior decals) are in LOCAL_SOURCE.txt.
	var local_text := FileAccess.get_file_as_string("res://assets/sol/LOCAL_SOURCE.txt")
	assert_true(local_text != "", "assets/sol/LOCAL_SOURCE.txt exists")
	var recorded := {}
	for line in (source_text + "\n" + local_text).split("\n"):
		var parts := line.split("  ", true, 1)
		if parts.size() == 2 and parts[0].length() == 64:
			recorded[parts[1]] = parts[0]
	assert_true(recorded.size() > 0, "SOURCE.txt lists files")
	var actual: Array[String] = []
	_all_files("res://assets/sol", actual)
	var hashed_count := 0
	for path in actual:
		var relative := path.trim_prefix("res://assets/sol/")
		var is_hashed := false
		for suffix in HASHED_SUFFIXES:
			if relative.ends_with(suffix):
				is_hashed = true
		if not is_hashed:
			continue
		hashed_count += 1
		assert_true(recorded.has(relative), "%s is listed in SOURCE.txt" % relative)
		if recorded.has(relative):
			assert_eq(FileAccess.get_sha256(path), recorded[relative], "%s is byte-identical to the recorded copy" % relative)
	assert_eq(hashed_count, recorded.size(), "SOURCE.txt lists no file that is gone")


func test_no_copied_material_points_into_lookdev() -> void:
	var actual: Array[String] = []
	_all_files("res://assets/sol", actual)
	for path in actual:
		if not (path.ends_with(".tres") or path.ends_with(".import")):
			continue
		var text := FileAccess.get_file_as_string(path)
		for forbidden in ["res://materials/", "res://decals/", "res://sky/", "lookdev"]:
			assert_true(not text.contains(forbidden), "%s does not mention %s" % [path.trim_prefix("res://assets/sol/"), forbidden])
