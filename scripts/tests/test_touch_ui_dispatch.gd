extends SceneTree

var checks: = 0
var failures: Array[String] = []
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func send_touch(id: int, point: Vector2, pressed: bool) -> void :
	var event: = InputEventScreenTouch.new()
	event.index = id;event.position = point;event.pressed = pressed
	root.push_input(event, true)
func run() -> void :
	root.size = Vector2i(720, 1280);root.content_scale_size = Vector2i(720, 1280)
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	print("DISPATCH ready enabled=", game.mobile_controls.enabled, " blocked=", game.mobile_controls._blocked(), " viewport=", root.get_visible_rect(), " size=", root.size)
	var hit: Vector2 = game.mobile_controls._charge_center
	var guide: Vector2 = game.hud._guide_button.get_global_rect().get_center()
	send_touch(0, hit, true)
	await process_frame
	check(game.mobile_controls._charge_id == 0 and Input.is_action_pressed("ui_accept"), "engine touch did not hold HIT")
	send_touch(1, guide, true)
	await process_frame
	send_touch(1, guide, false)
	await process_frame; await process_frame
	check(game.hud._guide.visible, "Guide cannot open while another finger holds HIT")
	check( not Input.is_action_pressed("ui_accept"), "opening Guide did not cancel held charge")
	for down in [true, false]:
		var mouse: = InputEventMouseButton.new()
		mouse.device = InputEvent.DEVICE_ID_EMULATION;mouse.position = guide
		mouse.button_index = MOUSE_BUTTON_LEFT;mouse.pressed = down
		root.push_input(mouse, true)
	await process_frame
	check(game.hud._guide.visible, "emulated mouse toggled Guide twice")
	send_touch(0, hit, false)
	send_touch(2, guide, true);send_touch(2, guide, false)
	await process_frame
	check( not game.hud._guide.visible, "Guide could not close through touch while blocking gameplay")
	send_touch(3, guide, true)
	var canceled: = InputEventScreenTouch.new()
	canceled.index = 3;canceled.position = guide;canceled.canceled = true;canceled.pressed = false
	root.push_input(canceled, true)
	await process_frame
	check( not game.hud._guide.visible and game.mobile_controls._toolbar_touches.is_empty(), "canceled menu finger activated Guide or stuck")
	send_touch(4, hit, true)
	await process_frame
	var pause_button: Button = game.hud._toolbar.get_child(2)
	var pause_point: Vector2 = pause_button.get_global_rect().get_center()
	send_touch(5, pause_point, true);send_touch(5, pause_point, false)
	await process_frame
	check(paused and not Input.is_action_pressed("ui_accept"), "second-finger Pause did not safely cancel HIT")
	root.get_node("PauseController").close()
	send_touch(4, hit, false)
	await process_frame
	var skips: Dictionary = {"count": 0}
	game.hud.skip_retrieval_requested.connect( func(): skips.count += 1;game.hud.set_between_point_active(false))
	game.hud.set_between_point_active(true)
	await process_frame
	check( not game.mobile_controls.visible and game.hud._skip_button.is_visible_in_tree(), "retrieval did not show only Skip action")
	check(root.get_visible_rect().encloses(game.hud._skip_button.get_global_rect()), "Skip offscreen in compact toolbar")
	var skip_point: Vector2 = game.hud._skip_button.get_global_rect().get_center()
	send_touch(6, skip_point, true);send_touch(6, skip_point, false)
	await process_frame
	check(skips.count == 1 and not game.hud._skip_button.visible, "Skip touch failed or fired more than once")
	var mouse_down: = InputEventMouseButton.new()
	mouse_down.button_index = MOUSE_BUTTON_LEFT;mouse_down.pressed = true;mouse_down.position = hit
	root.push_input(mouse_down, true)
	await process_frame
	check(game.mobile_controls._charge_id == -100 and Input.is_action_pressed("ui_accept"), "desktop pointer did not use HIT adapter")
	mouse_down.pressed = false;root.push_input(mouse_down, true)
	await process_frame
	check( not Input.is_action_pressed("ui_accept"), "desktop pointer release left HIT stuck")
	game.queue_free(); await process_frame; await process_frame
	for failure in failures: push_error(failure)
	print("TOUCH UI DISPATCH: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
