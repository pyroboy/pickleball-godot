extends CanvasLayer
## Pose Studio "Test": the controls over the real game while it plays the studio's working pose.
## Four controls and one line of truth:
##   Back          return to the studio (nothing was saved)
##   Random        the ball arrives the same every time, or a little differently each time
##   Slow          quarter speed (the game's own slow motion)
##   Auto          off = you press Hit yourself; on = the studio holds Hit for the hold length
##                 of the Hold button and lets go in time
## The line reports what the game really did with the last ball: which stroke it chose, at
## what power, and whether the paddle met the ball.

const Ui = preload("res://scripts/ui/game_ui_theme.gd")
const ShotChoice = preload("res://scripts/human_shot_choice.gd")
const AUTO_LEAD := 0.30        # auto swing lets go this long before the planned contact (s)
const SLOW_ID := "pose_test"

signal back_pressed

var studio
var game
var tested_posture := -1
var auto_swing := false
var slow := false
var report := {}               # the last ball: {posture, name, power, tap, hit, match}
var balls: Array = []          # every finished ball's report (tests read it)

var _info: Label
var _random_btn: Button
var _slow_btn: Button
var _auto_btn: Button
var _phase := -99
var _auto_down := false
var _auto_held := 0.0
var _auto_flight := -1

func _ready() -> void:
	layer = 121
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Below the scoreboard and left of the game's own book / pause buttons, so nothing is covered.
	var top: float = 112.0
	if studio and studio.get("phone_ui") != null and studio.phone_ui != null: top += float(studio.phone_ui.insets.x)
	else: top = 200.0   # the desktop scoreboard is taller
	var box := VBoxContainer.new(); box.name = "PoseTestBar"
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	box.position = Vector2(12, top); box.custom_minimum_size.x = 484; box.size.x = 484
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 6); box.add_child(row)
	var back := _btn("Back", func(): back_pressed.emit(), "TestBack"); row.add_child(back)
	_random_btn = _btn("Same ball", _toggle_random, "TestRandom"); row.add_child(_random_btn)
	_slow_btn = _btn("Slow", _toggle_slow, "TestSlow"); row.add_child(_slow_btn)
	_auto_btn = _btn("Auto: off", _toggle_auto, "TestAuto"); row.add_child(_auto_btn)
	_info = Label.new(); _info.name = "TestInfo"
	_info.add_theme_font_size_override("font_size", 22)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.05, 0.12, 0.17, 0.82); sb.set_corner_radius_all(10)
	sb.content_margin_left = 12; sb.content_margin_right = 12; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	panel.add_child(_info); box.add_child(panel)
	_refresh_buttons()
	_say("Real balls on your unsaved pose. Press HIT yourself, or turn Auto on.", false)

func _btn(text: String, cb: Callable, n: String) -> Button:
	var b := Button.new(); b.name = n; b.text = text; b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 64); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 20)
	b.clip_text = true
	b.pressed.connect(cb)
	return b

func _tint(b: Button, on: bool) -> void:
	b.modulate = Color(1.0, 0.92, 0.55) if on else Color.WHITE

func _refresh_buttons() -> void:
	var pl = game.practice_launcher if game else null
	var random: bool = pl != null and pl.pose_test_random
	_random_btn.text = "Random" if random else "Same ball"
	_tint(_random_btn, random)
	_tint(_slow_btn, slow)
	_auto_btn.text = "Auto: on" if auto_swing else "Auto: off"
	_tint(_auto_btn, auto_swing)

func _toggle_random() -> void:
	if game and game.practice_launcher: game.practice_launcher.pose_test_random = not game.practice_launcher.pose_test_random
	_refresh_buttons()

func _toggle_slow() -> void:
	set_slow(not slow)

func set_slow(on: bool) -> void:
	slow = on
	if on: TimeScale.request_slowmo(SLOW_ID, 0.25)
	else: TimeScale.release(SLOW_ID)
	_refresh_buttons()

func _toggle_auto() -> void:
	auto_swing = not auto_swing
	_release_auto()
	_refresh_buttons()

func _say(text: String, amber: bool) -> void:
	_info.text = text
	_info.add_theme_color_override("font_color", Color("ffcf6b") if amber else Color("eef5fa"))

func _human():
	if game == null or game.player_left == null or game.player_left.posture == null: return null
	return game.player_left.posture.human_contact

func _exit_tree() -> void:
	_release_auto()
	if slow: TimeScale.release(SLOW_ID)

func _release_auto() -> void:
	if _auto_down and game: game._on_player_swing_release(clampf(_auto_held / PickleballConstants.MAX_SERVE_CHARGE_TIME, 0.0, 1.0))
	_auto_down = false; _auto_held = 0.0

func _physics_process(delta: float) -> void:
	if game == null or get_tree().paused: return
	var human = _human()
	if human == null: return
	_watch(human)
	if not auto_swing or game.game_state != game.GameState.PLAYING:
		if _auto_down: _release_auto()
		return
	var ball = game.ball
	if human.phase >= 1 or ball == null or ball.flight_id == _auto_flight and not _auto_down: return
	if not _auto_down:
		var prep: Dictionary = human.preparation_contact()
		if prep.is_empty(): return
		if float(prep.time) > studio.hold_seconds + AUTO_LEAD: return
		game._on_player_swing_press()   # Hit goes down, as the input handler does it
		_auto_down = true; _auto_held = 0.0; _auto_flight = ball.flight_id
		return
	_auto_held += delta
	var ratio: float = clampf(_auto_held / PickleballConstants.MAX_SERVE_CHARGE_TIME, 0.0, 1.0)
	game.player_left.set_serve_charge_visual(ratio, delta)
	if _auto_held >= studio.hold_seconds:
		game._on_player_swing_release(clampf(studio.hold_seconds / PickleballConstants.MAX_SERVE_CHARGE_TIME, 0.0, 1.0))
		_auto_down = false

## What the game did with this ball, read from the live swing.
func _watch(human) -> void:
	var phase: int = int(human.phase)
	if phase == _phase: return
	var before := _phase
	_phase = phase
	if phase == 1 and human.swing_def != null:   # the strike began: the stroke and the power are decided
		var id: int = int(human.swing_def.posture_id)
		var def = PostureLibrary.instance().get_def(id)
		var power: float = float(human.charge_ratio)
		report = {"posture": id, "name": String(def.display_name) if def else "pose %d" % id, "power": power,
			"tap": ShotChoice.is_tap(power), "match": id == tested_posture, "hit": false, "done": false}
		_show()
	elif phase >= 2 and before == 1 and not report.is_empty():   # contact window over
		report["hit"] = bool(human.hit)
		report["done"] = true
		balls.append(report.duplicate())
		_show()

func _show() -> void:
	var tested = PostureLibrary.instance().get_def(tested_posture)
	var tested_name: String = String(tested.display_name) if tested else "this stroke"
	var how: String = "tap, touch shot" if bool(report.tap) else "power %d %%" % roundi(float(report.power) * 100.0)
	var result: String = "" if not bool(report.done) else (" · hit" if bool(report.hit) else " · missed")
	if bool(report.match): _say("Game chose: %s · %s%s" % [report.name, how, result], false)
	else: _say("Game chose %s, not %s · %s%s" % [report.name, tested_name, how, result], true)
