extends Node
## Mac-native verification without a terminal: open this scene in the Godot editor and run it
## (Scene > Run Current Scene). It runs every N14 streaming scenario with the real renderer and
## worker pool, then the whole unit/scenario test suite, and writes:
##   tests/visual/out/n14_mac_probe.json   per-scenario summaries and samples
##   tests/visual/out/n14_mac_probe.log    the probe's progress lines
##   tests/visual/out/n14_mac_tests.log    test results (same format as tests/run_tests.gd)
##   tests/visual/out/n14_mac_DONE         written last
## Set `run_tests = false` in the inspector to run only the probe.

@export var run_probe := true
@export var run_tests := true
const OUT_DIR := "res://tests/visual/out"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_write("n14_mac_DONE", "")
	if run_probe:
		var probe: Node = load("res://tools/n14_stream_probe.gd").new()
		probe.which = "all"
		probe.out_path = ProjectSettings.globalize_path(OUT_DIR.path_join("n14_mac_probe.json"))
		probe.quit_when_done = false
		probe.finished.connect(func(_results: Dictionary) -> void:
			_write("n14_mac_probe.log", "\n".join(probe.log_lines))
			probe.queue_free()
			_after_probe.call_deferred())
		add_child(probe)
	else:
		_after_probe.call_deferred()


func _after_probe() -> void:
	if run_tests:
		_write("n14_mac_tests.log", _run_tests())
	_write("n14_mac_DONE", "done %s" % Time.get_datetime_string_from_system())
	get_tree().quit()


func _write(file_name: String, text: String) -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR.path_join(file_name)), FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


func _run_tests() -> String:
	var lines: Array[String] = []
	var files: Array[String] = []
	for directory_path in ["res://tests/unit", "res://tests/scenario"]:
		_collect(directory_path, files)
	files.sort()
	var tests_run := 0
	var assertions := 0
	var failures: Array[String] = []
	var started := Time.get_ticks_msec()
	for test_file in files:
		var script: GDScript = load(test_file)
		if script == null or not script.can_instantiate():
			failures.append("%s: could not load script (parse error?)" % test_file)
			continue
		var test_case = script.new()
		for method_info in test_case.get_method_list():
			var method_name: String = method_info["name"]
			if not method_name.begins_with("test_"):
				continue
			tests_run += 1
			var before: int = test_case.failures.size()
			test_case.call(method_name)
			lines.append("%s %s::%s" % ["PASS" if test_case.failures.size() == before else "FAIL", test_file.get_file(), method_name])
		assertions += test_case.assertions_run
		for failure in test_case.failures:
			failures.append("%s: %s" % [test_file.get_file(), failure])
	for failure in failures:
		lines.append("  FAILURE " + failure)
	lines.append("---")
	lines.append("Godot %s | %s | files %d | tests %d | assertions %d | failures %d | %.0f s" % [Engine.get_version_info()["string"], OS.get_name(), files.size(), tests_run, assertions, failures.size(), (Time.get_ticks_msec() - started) / 1000.0])
	lines.append("RESULT: %s" % ("FAILED" if not failures.is_empty() or tests_run == 0 else "PASSED"))
	return "\n".join(lines)


func _collect(directory_path: String, found: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	for entry in directory.get_files():
		if entry.ends_with("_test.gd"):
			found.append(directory_path.path_join(entry))
	for sub in directory.get_directories():
		_collect(directory_path.path_join(sub), found)
