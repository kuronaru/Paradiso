# test_assertions.gd - Minimal assertion helper for headless GDScript tests.
extends RefCounted

var suite_name: String = ""
var passed: int = 0
var failed: int = 0
var failures: PackedStringArray = []


func _init(name: String = "TestSuite") -> void:
	suite_name = name


func assert_true(condition: bool, message: String) -> void:
	if condition:
		_pass(message)
	else:
		_fail(message)


func assert_false(condition: bool, message: String) -> void:
	assert_true(not condition, message)


func assert_eq(actual, expected, message: String) -> void:
	if actual == expected:
		_pass(message)
	else:
		_fail("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])


func assert_ne(actual, expected, message: String) -> void:
	if actual != expected:
		_pass(message)
	else:
		_fail("%s | both=%s" % [message, str(actual)])


func assert_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if abs(actual - expected) <= tolerance:
		_pass(message)
	else:
		_fail("%s | expected=%s actual=%s tolerance=%s" % [message, str(expected), str(actual), str(tolerance)])


func finish(tree: SceneTree) -> void:
	var status := "PASS" if failed == 0 else "FAIL"
	print("[%s] %s: %d passed, %d failed" % [status, suite_name, passed, failed])
	for failure in failures:
		printerr("  - %s" % failure)
	tree.quit(0 if failed == 0 else 1)


func _pass(_message: String) -> void:
	passed += 1


func _fail(message: String) -> void:
	failed += 1
	failures.append(message)
