extends SceneTree

var game: Node
var failures: Array[String] = []
var checks: = 0
const Layout = preload("res://scripts/ui/mobile_layout.gd")
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(message)
func touch(id: int, point: Vector2, down: bool, canceled: bool = false) -> void :
	var event: = InputEventScreenTouch.new()
	event.index = id;event.position = point;event.pressed = down;event.canceled = canceled
	game.mobile_controls._input(event)
func drag(id: int, point: Vector2) -> void :
	var event: = InputEventScreenDrag.new()
	event.index = id;event.position = point
	game.mobile_controls._input(event)
func run() -> void :
	root.get_node("PauseController").set_process_input(false)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	game.input_handler.set_process(false)
	game.game_state = game.GameState.PLAYING
	game.camera_rig.set_gameplay_camera_mode(0)
	for resolution in [Vector2i(720, 1280), Vector2i(720, 1560), Vector2i(720, 1600), Vector2i(600, 960), Vector2i(1080, 2340)]:
		root.content_scale_size = resolution;root.size = resolution
		await process_frame; await process_frame
		game.hud._layout_desktop();game.mobile_controls._layout();game.camera_rig.update(0.0)
		var screen: = root.get_visible_rect()
		var hud = game.hud
		check(game.main_camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "portrait must be perspective")
		check(game.main_camera.position.z > 7.0, "camera is not behind human baseline")
		var eye: Vector3 = game.main_camera.get_camera_transform().origin
		var baseline_ray: float = rad_to_deg(atan2(eye.y - 1.0, eye.z - 6.8))
		check(baseline_ray <= 50.01, "framing exceeds requested raised overview cap")
		check( not hud._status_panel.visible and not hud._debug_button.visible, "portrait retains opaque status or debug tools")
		check(game.mobile_controls.enabled, "touch disabled in portrait %s" % resolution)
		for control in [hud._score_panel, hud._status_panel, hud._toolbar, hud._charge_bar, hud._controls_hint]:
			check(screen.encloses(control.get_global_rect()), "%s offscreen %s rect=%s" % [control.name, resolution, control.get_global_rect()])
		check( not hud._score_panel.get_global_rect().intersects(hud._toolbar.get_global_rect()), "header/toolbar overlap %s" % resolution)
		check( not hud._status_panel.get_global_rect().intersects(game.mobile_controls._deck_rect), "thumb/status overlap %s" % resolution)
		check(screen.encloses(game.mobile_controls._deck_rect), "thumb deck offscreen %s" % resolution)
		var court: = Layout.court_rect(screen.size, screen)
		for point in game.camera_rig._portrait_action_points():
			var pixel: Vector2 = game.main_camera.unproject_position(point)
			check(court.has_point(pixel), "player/ball/far-court action envelope hidden at %s point=%s pixel=%s" % [resolution, point, pixel])
		check( not hud.debug_mode and not hud._pose_button.is_visible_in_tree(), "debug tools leaked to normal gameplay")
		check(not hud._controls_hint.text.contains("SPACE") and (hud._controls_hint.text.contains("HIT") or hud._controls_hint.text.contains("stick")), "portrait has keyboard-only hint")
	game.game_state = game.GameState.WAITING
	var simulated_safe: = Layout.safe_rect_from_pixels(Rect2(0, 0, 720, 1560), Rect2i(0, 90, 1080, 2178), Vector2(1080, 2340))
	check(simulated_safe.position == Vector2(0, 60), "physical notch not converted to canvas")
	check(is_equal_approx(simulated_safe.end.y, 1512), "navigation inset not converted to canvas")
	check(simulated_safe.encloses(Layout.deck_rect(Vector2(720, 1560), simulated_safe)), "touch deck enters navigation inset")
	check(simulated_safe.encloses(Layout.court_rect(Vector2(720, 1560), simulated_safe)), "court enters unsafe cutout")
	var controls = game.mobile_controls
	var start: Vector3 = game.player_left.global_position
	for action in controls.MOVE_ACTIONS:
		check(is_zero_approx(InputMap.action_get_deadzone(action)), "movement InputMap applied a second analog deadzone")
	touch(22, controls._stick_center + Vector2(controls._stick_radius * 0.12, 0), true)
	check(controls._stick_vector == Vector2.ZERO, "thumb jitter started below13percent")
	controls._drag(22, controls._stick_center + Vector2(controls._stick_radius * 0.14, 0))
	check(is_equal_approx(controls._stick_vector.x, 0.04 / 0.9), "gentle thumb start was not proportional")
	check(Input.get_vector("move_left", "move_right", "move_up", "move_down").is_equal_approx(controls._stick_vector), "shared action vector does not equal filtered touch vector")
	controls._drag(22, controls._stick_center + Vector2(controls._stick_radius * 0.12, 0))
	check(controls._stick_vector.x > 0, "active stick stopped inside hysteresis band")
	controls._drag(22, controls._stick_center + Vector2(controls._stick_radius * 0.09, 0))
	check(controls._stick_vector == Vector2.ZERO, "centered stick did not stop")
	controls._drag(22, controls._stick_center + Vector2(controls._stick_radius * 0.12, 0))
	check(controls._stick_vector == Vector2.ZERO, "stopped stick restarted inside hysteresis band")
	controls._drag(22, controls._stick_center + Vector2(controls._stick_radius * 0.5, 0))
	check(is_equal_approx(Input.get_vector("move_left", "move_right", "move_up", "move_down").x, 0.4 / 0.9), "half stick has a second deadzone/remap")
	controls._drag(22, controls._stick_center + Vector2.ONE * controls._stick_radius)
	check(is_equal_approx(Input.get_vector("move_left", "move_right", "move_up", "move_down").length(), 1), "diagonal stick is not clamped at full magnitude")
	touch(22, controls._stick_center, false, true)
	check( not controls._stick_active and controls._stick_vector == Vector2.ZERO, "cancel retained analog hysteresis state")
	touch(2, controls._stick_center + Vector2(controls._stick_radius * 0.4, 0), true)
	check(Input.get_vector("move_left", "move_right", "move_up", "move_down").x > 0, "analog stick needs too much travel to start")
	touch(2, controls._stick_center, false)
	touch(3, controls._stick_center + Vector2(controls._stick_radius, 0), true)
	check(Input.is_action_pressed("move_right"), "left finger does not drive shared right action")
	touch(8, controls._charge_center, true)
	game.input_handler._process(0.2)
	check(game.input_handler.serve_is_charging, "right finger did not start charge")
	check( not controls._press(98, controls._charge_center), "second HIT finger stole ownership")
	check(game.aim_controller.planted, "touch serve did not use shared aim plant")
	var target: Vector3 = game.aim_controller.get_target()
	game.input_handler._process(0.1)
	check(game.aim_controller.get_target().is_equal_approx(target), "left stick leaked into aim")
	drag(8, controls._charge_center + Vector2(controls._charge_radius, 0))
	game.input_handler._process(0.1)
	check(game.aim_controller.get_target().x > target.x, "right thumb did not nudge shared target while holding")
	touch(99, Vector2(10, 10), false)
	check(Input.is_action_pressed("ui_accept") and Input.is_action_pressed("move_right"), "unrelated release stole finger")
	touch(3, controls._stick_center, false)
	check( not Input.is_action_pressed("move_right") and Input.is_action_pressed("ui_accept"), "stick release ended charge")
	touch(8, controls._charge_center, false, true)
	game.input_handler._process(0)
	check( not Input.is_action_pressed("ui_accept") and not game.input_handler.serve_is_charging, "canceled touch left charge held")
	check(game.game_state == 0 and not game.game_serve.is_charging(), "canceled touch launched a serve")
	check( not game.aim_controller.is_locked(), "canceled touch kept aim locked")
	touch(4, controls._charge_center, true);game.input_handler._process(0.2)
	drag(4, controls._cancel_center)
	touch(4, controls._cancel_center, false)
	game.input_handler._process(0)
	check(game.game_state == 0 and not Input.is_action_pressed("ui_accept"), "explicit-target release cancellation fired serve or stuck")
	touch(5, controls._charge_center, true);game.input_handler._process(0.2)
	controls._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	game.input_handler._process(0)
	check(game.game_state == 0 and controls._owners.is_empty(), "background interruption kept touch/fired")
	touch(11, controls._stick_center + Vector2( - controls._stick_radius, 0), true)
	touch(12, controls._charge_center, true);game.input_handler._process(0.2)
	game.hud._guide.show();controls._process(0)
	game.input_handler._process(0)
	check(controls._owners.is_empty() and not Input.is_action_pressed("move_left") and game.game_state == 0, "guide interruption not canceled")
	game.hud._guide.hide();controls._process(0)
	touch(14, controls._charge_center, true);game.input_handler._process(0.2)
	paused = true
	touch(14, controls._charge_center, false)
	paused = false;game.input_handler._process(0)
	check(game.game_state == 0 and not game.input_handler.serve_is_charging, "release in same frame as pause fired queued serve")
	Input.action_press("ui_accept");game.input_handler._process(0.2)
	game.input_handler.cancel_charge_input();game.input_handler._process(0.1)
	check( not game.input_handler.serve_is_charging, "reset while desktop Space held restarted charge")
	Input.action_release("ui_accept");game.input_handler._process(0)
	check(game.game_state == 0, "release after desktop cancellation launched serve")
	game.game_state = 2
	game.ball.is_in_play = true
	game.ball.last_hit_by = 1

	check( not controls._press(20, (controls._stick_center + controls._charge_center) * 0.5), "middle still activates a third control")
	touch(21, controls._charge_center, true);game.input_handler._process(0.2)
	check(game.selected_spin_mode == 0 and game.selected_shot_intent == "AUTO", "center press must choose Flat")
	drag(21, controls._charge_center + Vector2(-1, -1).normalized() * controls._charge_radius)
	check(game.selected_spin_mode == 0 and controls.aim_direction().x < 0, "HIT drag must aim Flat rather than choose spin")
	drag(21, controls._charge_center + Vector2(-5, 0) * controls._charge_radius)
	check(not controls._cancel_armed and Input.is_action_pressed("ui_accept"), "long aiming drag canceled charge")
	drag(21, controls._cancel_center)
	check(controls._cancel_armed and Input.is_action_pressed("ui_accept"), "cancel target must arm without releasing")
	drag(21, controls._charge_center + Vector2(1, -1).normalized() * controls._charge_radius)
	check(not controls._cancel_armed and game.selected_spin_mode == 0, "leaving cancel failed to resume Flat")
	touch(21, controls._charge_center, false, true);game.input_handler._process(0)
	game.game_state = 0
	game.ball.is_in_play = false
	game.match_over = true
	touch(27, controls._charge_center, true)
	check( not Input.is_action_pressed("ui_accept") and controls._owners.is_empty(), "touch leaked through match result")
	game.match_over = false
	game.hud.set_debug_mode(true)
	check( not game.hud.debug_mode and not game.hud._pose_button.is_visible_in_tree(), "mobile exposed Edit poses")
	game.hud.set_debug_mode(false)
	var edit_event: = InputEventKey.new()
	edit_event.keycode = KEY_F2;edit_event.pressed = true
	game.input_handler._unhandled_key_input(edit_event)
	check(game.posture_editor_v2 == null or not game.posture_editor_v2.visible, "F2 exposed pose editor in portrait")

	touch(31, controls._charge_center, true);game.input_handler._process(0.2)
	drag(31, controls._charge_center + Vector2(-1, -1).normalized() * controls._charge_radius)
	touch(31, controls._charge_center + Vector2(-1, -1).normalized() * controls._charge_radius, false);game.input_handler._process(0)
	check(game.game_state == 1, "normal touch release did not enter serve release")
	check(game.aim_controller.is_locked(), "normal release lost locked target")
	var committed: Dictionary = game.game_serve._pending_release.duplicate(true)
	var frozen_spin: int = game._frozen_spin_mode
	var next_spin: int = game.selected_spin_mode
	check( not controls._show_serve_selector(), "serve selector remained active after release")
	touch(32, controls._charge_center, true)
	drag(32, controls._charge_center + Vector2(1, -1).normalized() * controls._charge_radius)
	check(game.selected_spin_mode == next_spin and not controls._charge_owns_action, "released-serve right drag must not change selection or charge")
	check(game.game_serve._pending_release == committed and game._frozen_spin_mode == frozen_spin, "in-flight drag mutated committed serve")
	touch(32, controls._charge_center, false, true)
	check(game.game_serve._pending_release == committed and game.aim_controller.is_locked(), "canceling next-shot gesture canceled frozen shot")
	controls.cancel_all()
	root.content_scale_size = Vector2i(1280, 800);root.size = Vector2i(1280, 800)
	await process_frame; await process_frame
	game.hud._layout_desktop();controls._layout();game.camera_rig.update(0)
	check( not controls.enabled and not controls.visible, "touch deck remained in desktop landscape")
	check(game.main_camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "desktop camera not restored")
	game.hud.set_debug_mode(true)
	check(game.hud._pose_button.is_visible_in_tree() == bool(preload("res://scripts/runtime_policy.gd").developer_tools), "editor visibility must follow runtime developer policy")
	game.queue_free(); await process_frame; await process_frame
	for failure in failures: push_error(failure)
	print("PORTRAIT MOBILE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
