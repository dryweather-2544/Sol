extends SceneTree
## Headless test runner.
##   godot --headless --path . -s res://tests/run_tests.gd
## Finds every *_test.gd under tests/unit and tests/scenario, runs each test_* method, prints a
## summary and exits with status 1 if anything failed (or if no tests were found).

const TEST_DIRECTORIES := ["res://tests/unit", "res://tests/scenario"]


func _initialize() -> void:
	var test_files: Array[String] = []
	for directory_path in TEST_DIRECTORIES:
		_collect_test_files(directory_path, test_files)
	test_files.sort()

	var tests_run := 0
	var assertions_run := 0
	var failure_lines: Array[String] = []

	for test_file in test_files:
		var test_script: GDScript = load(test_file)
		if test_script == null:
			failure_lines.append("%s: could not load script (parse error?)" % test_file)
			continue
		var test_case = test_script.new()
		for method_info in test_case.get_method_list():
			var method_name: String = method_info["name"]
			if not method_name.begins_with("test_"):
				continue
			tests_run += 1
			var failures_before: int = test_case.failures.size()
			test_case.call(method_name)
			var passed: bool = test_case.failures.size() == failures_before
			print("%s %s::%s" % ["PASS" if passed else "FAIL", test_file.get_file(), method_name])
		assertions_run += test_case.assertions_run
		for failure in test_case.failures:
			failure_lines.append("%s: %s" % [test_file.get_file(), failure])

	for line in failure_lines:
		print("  FAILURE ", line)
	var failed := not failure_lines.is_empty() or tests_run == 0
	print("---")
	print("Godot %s | files %d | tests %d | assertions %d | failures %d" % [Engine.get_version_info()["string"], test_files.size(), tests_run, assertions_run, failure_lines.size()])
	print("RESULT: %s" % ("FAILED" if failed else "PASSED"))
	quit(1 if failed else 0)


func _collect_test_files(directory_path: String, found_files: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	for entry_name in directory.get_files():
		if entry_name.ends_with("_test.gd"):
			found_files.append(directory_path.path_join(entry_name))
	for subdirectory_name in directory.get_directories():
		_collect_test_files(directory_path.path_join(subdirectory_name), found_files)
