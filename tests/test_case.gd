extends RefCounted
## Base class for tests. Methods named test_* are run by tests/run_tests.gd.
## Tests extend this by path (not class_name) so they work before Godot has built its
## global class cache.

var failures: Array[String] = []
var assertions_run := 0


func assert_true(condition: bool, message: String = "") -> void:
	assertions_run += 1
	if not condition:
		failures.append("assert_true failed. %s" % message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	assertions_run += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("expected %s (%s) but got %s (%s). %s" % [str(expected), type_string(typeof(expected)), str(actual), type_string(typeof(actual)), message])


func assert_near(actual: float, expected: float, tolerance: float, message: String = "") -> void:
	assertions_run += 1
	if absf(actual - expected) > tolerance:
		failures.append("expected %s +/- %s but got %s (off by %s). %s" % [str(expected), str(tolerance), str(actual), str(absf(actual - expected)), message])
