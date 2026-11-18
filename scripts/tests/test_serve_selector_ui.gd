extends SceneTree

class ServeOptionsFixture extends RefCounted:
	var selected_serve_style: = 10
	var phase: = "HELD"
	var progress: = 0.0
	func get_serve_style_options() -> Array:
		return [{"id": 10, "key": "FLAT", "label": "Flat", "delivery": "Volley"}, {"id": 20, "key": "TOPSPIN", "label": "Topspin", "delivery": "Volley"}, {"id": 30, "key": "SLICE", "label": "Slice", "delivery": "Drop"}, {"id": 40, "key": "HIGH_SOFT", "label": "High Soft", "delivery": "Volley"}, {"id": 50, "key": "DROP_DRIVE", "label": "Drop Drive", "delivery": "Drop"}, {"id": 60, "key": "BANANA", "label": "Banana", "delivery": "Volley"}, {"id": 70, "key": "SCREWBALL", "label": "Screwball", "delivery": "Volley"}]
	func select_serve_style(id: int) -> void : selected_serve_style = id
	func get_serve_timing_state() -> Dictionary:
		return {"phase": phase, "progress": progress, "style": selected_serve_style, "locked": phase != "HELD", "can_release": phase == "HELD"}
	func cleanup() -> void : pass
var failures: Array[String] = []
var checks: = 0
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func run() -> void :
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	game.input_handler.set_process(false)
	var original = game.game_serve
	var fixture: = ServeOptionsFixture.new()

	game.game_serve = fixture
	var ui = game.mobile_controls
	check(ui._show_serve_selector(), "human pre-serve must expose center wheel")
	var center: Vector2 = ui._serve_selector_center
	var radius: float = ui._serve_selector_radius * 0.9
	var step: float = TAU / 7.0
	check(ui._press(70, center + Vector2.RIGHT * radius), "wheel did not capture its own finger")
	check( not Input.is_action_pressed("ui_accept"), "touching wheel charged HIT")
	ui._drag(70, center + Vector2.from_angle(step * 0.8) * radius)
	check(fixture.selected_serve_style == 20, "clockwise rotation did not select next style")
	for offset in [0.01, - 0.01, 0.02, - 0.02]: ui._drag(70, center + Vector2.from_angle(step * 0.8 + offset) * radius)
	check(fixture.selected_serve_style == 20, "tiny angle jitter changed selected style")
	ui._drag(70, center)
	ui._drag(70, center + Vector2.LEFT * radius)
	check(fixture.selected_serve_style == 20, "crossing center caused discontinuous rotation")
	check( not ui._press(71, center + Vector2.RIGHT * radius), "second selector finger stole wheel")
	check(ui._press(71, ui._charge_center), "independent right finger failed")
	check(Input.is_action_pressed("ui_accept") and ui._gesture_is_serve, "HIT did not keep serve charge input")
	ui._press(72, ui._stick_center + Vector2.RIGHT * ui._stick_radius)
	check(Input.is_action_pressed("move_right"), "left stick failed beside charge and selector")
	ui._release(70)
	check(Input.is_action_pressed("ui_accept") and Input.is_action_pressed("move_right"), "wheel release canceled other fingers")
	ui._release(71)
	check( not Input.is_action_pressed("ui_accept") and Input.is_action_pressed("move_right"), "HIT release stole movement")
	ui._release(72)
	check(ui._owners.is_empty(), "finger ownership leaked after independent releases")
	game.game_state = 2
	check( not ui._show_serve_selector() and not ui._press(73, center), "serve selector appeared in rally")
	ui._press(74, ui._charge_center)
	ui._drag(74, ui._charge_center + Vector2.DOWN * ui._charge_radius)
	check(game.selected_shot_intent == "DROP" and fixture.selected_serve_style == 20, "rally Drop changed serve delivery")
	ui._release(74)
	game.game_state = 0
	ui._press(75, center + Vector2.RIGHT * radius)
	game.game_state = 1
	ui._process(0)
	check(ui._serve_selector_id == -1 and ui._owners.is_empty(), "selector stayed captured after serve commitment")
	fixture.phase = "SWING";fixture.progress = 0.6
	ui._process(0)
	check(ui._serve_timing.phase == "SWING" and is_equal_approx(ui._serve_timing.progress, 0.6), "timing display ignored supplied actual phase/progress")
	fixture.phase = "CONTACT";fixture.progress = 1
	ui._process(0)
	check(ui._serve_contact_flash > 0, "contact did not trigger timing flash")
	ui._process(0.3)
	check(is_zero_approx(ui._serve_contact_flash), "unchanged contact phase repeatedly flashed")
	game.game_serve = original
	game.game_state = 0
	ui.cancel_all()
	game.queue_free(); await process_frame; await process_frame
	for failure in failures: push_error(failure)
	print("SERVE SELECTOR UI CONTRACT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
