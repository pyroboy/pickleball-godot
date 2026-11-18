extends TestBase

func run_all(totals: Dictionary) -> void :
	_run_test_list(totals, [test_up, test_down, test_left, test_right, test_space])

func _has_key(action: String, key: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event.physical_keycode == key or event.keycode == key): return true
	return false

func test_up() -> void :
	_assert_true(_has_key("move_up", KEY_W) and _has_key("move_up", KEY_UP), "W and up arrow both move up")
func test_down() -> void :
	_assert_true(_has_key("move_down", KEY_S) and _has_key("move_down", KEY_DOWN), "S and down arrow both move down")
func test_left() -> void :
	_assert_true(_has_key("move_left", KEY_A) and _has_key("move_left", KEY_LEFT), "A and left arrow both move left")
func test_right() -> void :
	_assert_true(_has_key("move_right", KEY_D) and _has_key("move_right", KEY_RIGHT), "D and right arrow both move right")
func test_space() -> void :
	_assert_true(_has_key("ui_accept", KEY_SPACE), "Space remains the charge/release action")
