extends SceneTree
## Headless tests for the human tap / hold shot choice (scripts/human_shot_choice.gd).
## Run: godot --headless --path . -s tools/human_shot_choice_tests.gd

var _fails := 0
var _checks := 0

func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond: _fails += 1
	print("PASS  " if cond else "FAIL  ", label)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var C = load("res://scripts/human_shot_choice.gd")
	var full: float = 1.0
	var tap: float = 0.1     # 0.045 s press
	var aim := Vector3(1.0, 0.11, -4.6)
	# Tap: touch shot by zone / height, always short.
	var r: Dictionary = C.choose(tap, 2.0, 0.5, false, aim, 1.0)
	_check(r.touch and r.name == "DINK" and r.intent == "DROP" and absf(r.target.z) < 1.7, "tap at the kitchen on a low ball = DINK, lands short (%.2f m)" % absf(r.target.z))
	r = C.choose(tap, 2.0, 1.3, false, aim, 1.0)
	_check(r.name == "BLOCK" and absf(r.target.z) < 1.7, "tap on a ball above the net = BLOCK")
	r = C.choose(tap, 4.0, 0.6, false, aim, 1.0)
	_check(r.name == "RESET", "tap from the transition zone = RESET")
	r = C.choose(tap, 6.5, 0.5, false, aim, 1.0)
	_check(r.name == "DROP" and absf(r.target.z) < 1.7, "tap from the baseline = DROP, still short")
	# Hold: power shot, deep.
	r = C.choose(full, 6.5, 0.6, false, aim, 1.0)
	_check(not r.touch and r.name == "DRIVE" and r.intent == "AUTO" and absf(r.target.z) >= 4.5 and r.spin == 1, "hold from the baseline = DRIVE, deep, topspin")
	r = C.choose(full, 2.0, 1.3, false, aim, 1.0)
	_check(r.name == "SPEED_UP", "hold at the kitchen on a high ball = SPEED-UP")
	r = C.choose(full, 3.0, 2.0, true, aim, 1.0)
	_check(r.name == "SMASH" and r.spin == 0, "hold on a smash contact = SMASH, flat")
	# Threshold and court end.
	_check(C.is_tap(0.39) and not C.is_tap(0.41), "tap/hold boundary at 0.18 s of a 0.45 s charge")
	r = C.choose(tap, 2.0, 0.5, false, Vector3(-3.5, 0.11, 4.6), -1.0)
	_check(r.target.z > 0.0 and r.target.x >= -2.201, "other court end: target on +z, kept inside the sideline")
	print("human shot choice tests: %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
