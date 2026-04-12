class_name TestPhysicsUtils extends RefCounted
## Unit tests for PhysicsUtils — pure math damping/smoothing functions.
## All tests are deterministic: no scene, no fakes, no random.
##
## Run via: godot --headless --script scripts/tests/test_runner.gd
## (test_runner.gd auto-discovers and runs this suite)

const _PhysicsUtils := preload("res://scripts/physics.gd")

func run_all(totals: Dictionary) -> void:
	_test_scalar_damp_convergence(totals)
	_test_scalar_damp_edge_cases(totals)
	_test_scalar_damp_rate(totals)
	_test_vector3_damp_convergence(totals)
	_test_vector3_damp_edge_cases(totals)


func _assert_eq_f(actual: float, expected: float, tol: float, label: String, totals: Dictionary) -> void:
	if absf(actual - expected) > tol:
		totals.fail += 1
		totals.errors.append("%s: expected %.6f, got %.6f" % [label, expected, actual])
	else:
		totals.pass += 1


func _assert_eq_v3(actual: Vector3, expected: Vector3, tol: float, label: String, totals: Dictionary) -> void:
	if actual.distance_to(expected) > tol:
		totals.fail += 1
		totals.errors.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])
	else:
		totals.pass += 1


## ── _damp scalar tests ───────────────────────────────────────────────────────

func _test_scalar_damp_convergence(totals: Dictionary) -> void:
	var current: float = 10.0
	var target: float = 20.0
	var halflife: float = 0.1
	var dt: float = 0.016

	for i in range(200):
		current = _PhysicsUtils._damp(current, target, halflife, dt)

	_assert_eq_f(current, target, 0.001, "_damp converges to target after many frames", totals)


func _test_scalar_damp_edge_cases(totals: Dictionary) -> void:
	# dt=0 returns current unchanged
	var r0: float = _PhysicsUtils._damp(5.0, 100.0, 0.1, 0.0)
	_assert_eq_f(r0, 5.0, 0.0, "_damp dt=0 returns current unchanged", totals)

	# current==target stays at target
	var r1: float = _PhysicsUtils._damp(42.0, 42.0, 0.1, 0.016)
	_assert_eq_f(r1, 42.0, 0.0, "_damp current==target is stable", totals)

	# halflife=0 does not divide by zero (protected by maxf(halflife, 0.001))
	var r2: float = _PhysicsUtils._damp(10.0, 20.0, 0.0, 0.016)
	_assert_eq_f(r2, 20.0, 0.001, "_damp halflife=0 snaps to target", totals)

	# very large halflife → barely moves
	var r3: float = _PhysicsUtils._damp(0.0, 100.0, 1000.0, 0.016)
	_assert_eq_f(r3, 0.0, 0.01, "_damp huge halflife barely moves", totals)

	# very small halflife → nearly snaps
	var r4: float = _PhysicsUtils._damp(0.0, 100.0, 0.001, 0.016)
	_assert_eq_f(r4, 100.0, 0.01, "_damp tiny halflife snaps to target", totals)


func _test_scalar_damp_rate(totals: Dictionary) -> void:
	# At halflife=0.1s and dt=0.016s (~60fps), one frame should move ~10.5% of the gap.
	# fraction = 1 - exp(-0.693 * dt / hl) = 1 - exp(-0.693 * 0.016 / 0.1)
	#           = 1 - exp(-0.1109) = 1 - 0.895 = 0.105
	var current: float = 10.0
	var target: float = 20.0
	var halflife: float = 0.1
	var dt: float = 0.016
	var next: float = _PhysicsUtils._damp(current, target, halflife, dt)
	var expected_first: float = 10.0 + 0.105 * (20.0 - 10.0)  # ≈ 11.05
	_assert_eq_f(next, expected_first, 0.01, "_damp one-frame rate matches exponential formula", totals)

	# Two frames: 1 - exp(-2 * 0.1109) = 1 - 0.801 = 0.199
	var next2: float = _PhysicsUtils._damp(next, target, halflife, dt)
	var expected_second: float = 10.0 + 0.199 * (20.0 - 10.0)  # ≈ 11.99
	_assert_eq_f(next2, expected_second, 0.01, "_damp two-frame rate matches exponential formula", totals)


## ── _damp_v3 vector tests ───────────────────────────────────────────────────

func _test_vector3_damp_convergence(totals: Dictionary) -> void:
	var current: Vector3 = Vector3(0.0, 0.0, 0.0)
	var target: Vector3 = Vector3(10.0, 20.0, 30.0)
	var halflife: float = 0.1
	var dt: float = 0.016

	for i in range(200):
		current = _PhysicsUtils._damp_v3(current, target, halflife, dt)

	_assert_eq_v3(current, target, 0.001, "_damp_v3 converges to target after many frames", totals)


func _test_vector3_damp_edge_cases(totals: Dictionary) -> void:
	# dt=0 returns current unchanged
	var r0: Vector3 = _PhysicsUtils._damp_v3(Vector3(1, 2, 3), Vector3(100, 200, 300), 0.1, 0.0)
	_assert_eq_v3(r0, Vector3(1, 2, 3), 0.0, "_damp_v3 dt=0 returns current unchanged", totals)

	# current==target is stable
	var r1: Vector3 = _PhysicsUtils._damp_v3(Vector3(5, 5, 5), Vector3(5, 5, 5), 0.1, 0.016)
	_assert_eq_v3(r1, Vector3(5, 5, 5), 0.0, "_damp_v3 current==target is stable", totals)

	# halflife=0 snaps to target
	var r2: Vector3 = _PhysicsUtils._damp_v3(Vector3.ZERO, Vector3(1, 2, 3), 0.0, 0.016)
	_assert_eq_v3(r2, Vector3(1, 2, 3), 0.001, "_damp_v3 halflife=0 snaps to target", totals)
