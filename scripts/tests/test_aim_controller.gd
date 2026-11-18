extends TestBase
const Aim = preload("res://scripts/aim_controller.gd")

func run_all(totals: Dictionary) -> void :
	_run_test_list(totals, [test_safe_ranges, test_motion_and_lock, test_drop_range, test_serve_boxes, test_reset])

func test_safe_ranges() -> void :
	var target: Vector3 = Aim.clamp_target(Vector3(100, 99, -100))
	_assert_eq_f(target.x, 2.45, 0.001, "safe sideline margin")
	_assert_eq_f(target.z, -6.1, 0.001, "safe baseline margin")
	_assert_eq_f(Aim.clamp_target(Vector3(0, 0, 20)).z, -0.65, 0.001, "opponent side only")

func test_motion_and_lock() -> void :
	var aim = Aim.new()
	var before: Vector3 = aim.get_target()
	aim.nudge(Vector2(1, -1), 0.1)
	_assert_gt(aim.target.x, before.x, "right moves cursor right")
	_assert_lt(aim.target.z, before.z, "up moves cursor deeper")
	var frozen: Vector3 = aim.capture()
	aim.nudge(Vector2(-1, 1), 3)
	_assert_true(aim.get_target().is_equal_approx(frozen), "committed cursor immutable")
	_assert_true(aim.should_plant_player(), "committed strike plants feet")
	aim.release()
	_assert_true( not aim.should_plant_player(), "contact immediately restores movement")

func test_drop_range() -> void :
	var shallow: Vector3 = Aim.clamp_target(Vector3(-100, 0, 10), "DROP")
	var deep: Vector3 = Aim.clamp_target(Vector3(100, 0, -100), "DROP")
	_assert_eq_f(shallow.z, -0.65, 0.001, "drop near limit")
	_assert_eq_f(deep.z, -1.55, 0.001, "drop remains inside kitchen")
	_assert_eq_f(deep.x, 2.45, 0.001, "drop lateral safety")

func test_serve_boxes() -> void :
	for even in [true, false]:
		var point: Vector3 = Aim.clamp_target(Vector3(0, 0, 0), "DROP", true, even)
		_assert_eq_f(point.z, -2.6, 0.001, "serve never lands kitchen even with Drop selected")
		_assert_true(point.x < 0 if even else point.x > 0, "serve keeps required diagonal box")

func test_reset() -> void :
	var aim = Aim.new()
	aim.capture()
	aim.reset()
	_assert_true( not aim.should_plant_player() and not aim.cursor_visible, "reset clears lock and cursor")
