extends SceneTree
## Headless tests for the retro LED scoreboard (scripts/ui/digital_scoreboard.gd).
## Run: godot --headless --path . -s tools/digital_scoreboard_tests.gd

var _fails := 0
var _checks := 0

func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond: _fails += 1
	print("PASS  " if cond else "FAIL  ", label)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var board = load("res://scripts/ui/digital_scoreboard.gd").new()
	board.size = Vector2(300, 92)
	root.add_child(board)
	board.set_scores(0, 0, false)
	_check(not board.is_animating() and not board.is_processing(), "no animation and no per-frame work at rest")
	board.set_scores(1, 0)
	_check(board.is_animating() and board.is_processing(), "a new point starts the roll + flash")
	_check(board._roll[0] == 0.0 and board._roll[1] == 1.0 and board._flash[0] > 0.0 and board._flash[1] == 0.0, "only the scoring team's box animates")
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 1300: await process_frame
	_check(not board.is_animating() and not board.is_processing(), "animation ends and processing stops (~0.9 s)")
	_check(board._scores == [1, 0], "board shows 1 - 0")
	board.set_scores(10, 9)
	_check(board._previous == [1, 0] and board._scores == [10, 9], "two-digit scores keep the previous value for the roll")
	board.set_server(1, 2)
	_check(board.serving_team == 1 and board.server_number == 2, "server dot and server number")
	print("digital scoreboard tests: %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
