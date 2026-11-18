class_name TestBase extends RefCounted
## Base class for all pickleball test suites.
## Provides common assertion helpers and test-list iteration logic.
##
## Subclasses override run_all(totals), build their own Array[Callable] of
## test methods, and call _run_test_list(totals, tests) to execute them.
##
## Example:
##   class_name TestMyFeature extends TestBase
##   func run_all(totals: Dictionary) -> void:
##       var tests: Array[Callable] = [test_foo, test_bar]
##       _run_test_list(totals, tests)

var _current_failures: Array[String] = []
var _current_test_name: String = ""


## Iterate an Array[Callable] of test methods, tracking pass/fail per method.
## Each callable that finishes with zero failures counts as 1 pass.
## Any failure appends descriptive errors to totals.errors.
func _run_test_list(totals: Dictionary, tests: Array[Callable]) -> void:
	for t in tests:
		_current_test_name = t.get_method()
		_current_failures = []
		t.call()
		if _current_failures.is_empty():
			totals.pass += 1
		else:
			totals.fail += 1
			for f in _current_failures:
				totals.errors.append("%s: %s" % [_current_test_name, f])


## ── Assertion helpers ────────────────────────────────────────────────────────

func _assert_true(cond: bool, msg: String = "") -> void:
	if not cond:
		_current_failures.append("expected true: " + msg)


func _assert_false(cond: bool, msg: String = "") -> void:
	if cond:
		_current_failures.append("expected false: " + msg)


func _assert_eq(a: Variant, b: Variant, msg: String = "") -> void:
	if a != b:
		_current_failures.append("expected " + str(b) + ", got " + str(a) + ": " + msg)


func _assert_eq_f(a: float, b: float, tol: float, msg: String = "") -> void:
	if absf(a - b) > tol:
		_current_failures.append("expected " + String.num(b, 4) + ", got " + String.num(a, 4) + " (tol=" + String.num(tol, 4) + "): " + msg)


func _assert_eq_v3(a: Vector3, b: Vector3, tol: float, msg: String = "") -> void:
	if a.distance_to(b) > tol:
		_current_failures.append("expected " + str(b) + ", got " + str(a) + " (tol=" + String.num(tol, 4) + "): " + msg)


func _assert_gt(a: float, b: float, msg: String = "") -> void:
	if not (a > b):
		_current_failures.append("expected " + String.num(a, 4) + " > " + String.num(b, 4) + ": " + msg)


func _assert_ge(a: float, b: float, msg: String = "") -> void:
	if a < b:
		_current_failures.append("expected " + String.num(a, 4) + " >= " + String.num(b, 4) + ": " + msg)


func _assert_lt(a: float, b: float, msg: String = "") -> void:
	if not (a < b):
		_current_failures.append("expected " + String.num(a, 4) + " < " + String.num(b, 4) + ": " + msg)


func _assert_le(a: float, b: float, msg: String = "") -> void:
	# Tiny epsilon for floating-point safety (e.g. normalized()*cap can overshoot)
	if a > b + 0.0001:
		_current_failures.append("expected " + String.num(a, 4) + " <= " + String.num(b, 4) + ": " + msg)


func _assert_in_range(val: float, lo: float, hi: float, msg: String = "") -> void:
	if val < lo or val > hi:
		_current_failures.append("expected " + String.num(val, 4) + " in [" + String.num(lo, 4) + ", " + String.num(hi, 4) + "]: " + msg)
