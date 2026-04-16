extends Node

const EXPECTED_FRAMES = 120
const FAST_SCALE := 10.0

var _game: Node
var _practice: Node
var _poll: int = 0
var _purple_fired: bool = false
var _p0_ready: bool = false
var _p1_ready: bool = false
var _start_time: int = 0

func _ready() -> void:
	_start_time = Time.get_ticks_msec()
	_game = get_node("/root/Game")
	_practice = _game.get_node("practice_launcher")
	TimeScale.set_test_fast_forward(FAST_SCALE)
	print("[E2E] fast mode %.0fx" % FAST_SCALE)
	_practice.launch_ball()
	set_process(true)

func _process(_delta: float) -> void:
	_poll += 1
	var elapsed := (Time.get_ticks_msec() - _start_time) / 1000.0

	if _game.player_left and _game.player_right:
		var p0c = _game.player_left.get("arms_log_count")
		var p1c = _game.player_right.get("arms_log_count")
		if p0c != null and p0c > 0: _p0_ready = true
		if p1c != null and p1c > 0: _p1_ready = true

	if _poll >= EXPECTED_FRAMES or (_purple_fired and _p0_ready and _p1_ready):
		if _purple_fired and _p0_ready and _p1_ready:
			print("[E2E] PASS  %.1fs (frames=%d)" % [elapsed, _poll])
			quit_pass()
		else:
			printerr("[E2E] FAIL  purple=%s p0=%s p1=%s" % [_purple_fired, _p0_ready, _p1_ready])
			quit_fail()

func quit_pass() -> void:
	set_process(false)
	TimeScale.set_test_fast_forward(0.0)
	get_tree().quit(0)

func quit_fail() -> void:
	set_process(false)
	TimeScale.set_test_fast_forward(0.0)
	get_tree().quit(1)
