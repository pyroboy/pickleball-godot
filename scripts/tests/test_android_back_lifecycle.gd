extends SceneTree

var game
var controller
var checks: = 0
var failures: Array[String] = []
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(message);print("FAIL: ", message)
func frames(count: int) -> void :
	for i in range(count): await process_frame; await physics_frame
func back() -> void :
	controller._last_back_msec = -1000
	root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
func touch(id: int, point: Vector2, pressed: bool) -> void :
	var event: = InputEventScreenTouch.new();event.index = id;event.position = point;event.pressed = pressed
	root.push_input(event, true)
func run() -> void :
	create_timer(40, true).timeout.connect( func(): quit(2))
	root.size = Vector2i(432, 936);root.content_scale_size = Vector2i(720, 1560)
	controller = root.get_node("PauseController")
	check( not quit_on_go_back and not ProjectSettings.get_setting("application/config/quit_on_go_back", true), "Android Back still auto-quits")
	var title = load("res://scenes/title.tscn").instantiate();root.add_child(title);current_scene = title
	await frames(2)
	title._open_settings(); await process_frame
	back()
	check( not is_instance_valid(title._overlay) and not paused, "title Back closes Settings before exit")
	title._toggle_controls();back()
	check( not title._hint.text.begins_with("MOVE"), "title Back closes Controls")
	check( not controller._handle_back_request(), "bare title Back does not request exit")
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(paused and not is_instance_valid(controller._menu), "background title showed an in-match pause menu")
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check( not paused, "title did not recover from background")
	title.queue_free(); await process_frame
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await frames(3)
	var ui = game.mobile_controls
	touch(1, ui._charge_center, true); await frames(4)
	check(Input.is_action_pressed("ui_accept"), "held touch fixture failed")
	back()
	check(paused and is_instance_valid(controller._menu), "native Back did not pause gameplay")
	check( not Input.is_action_pressed("ui_accept") and not game.serve_is_charging, "native Back retained held charge")
	var escape: = InputEventKey.new();escape.pressed = true;escape.keycode = KEY_ESCAPE
	controller._unhandled_input(escape)
	check(paused and is_instance_valid(controller._menu), "duplicate native/keyboard Back toggled twice")
	controller._menu._on_settings(); await process_frame
	back()
	check(paused and not is_instance_valid(controller._menu._settings_overlay), "Back did not return Settings to Pause")
	game.practice_panel.open_practice();back()
	check( not game.practice_panel._picker_open and paused, "Back did not close practice picker first")
	back(); await frames(2)
	check( not paused and not is_instance_valid(controller._menu), "second Back did not resume Pause")
	touch(1, ui._charge_center, false); await frames(3)
	check(game.game_state == 0 and not game.ball.is_in_play, "old release after Back created a ghost serve")
	game.hud._guide.show();back()
	check( not game.hud._guide.visible and not paused, "guide Back paused instead of closing guide")

	touch(2, ui._stick_center + Vector2.RIGHT * ui._stick_radius, true)
	touch(3, ui._charge_center, true); await frames(3)
	var fps: = Engine.max_fps
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(paused and controller._manual_paused and controller._focus_paused, "application suspension did not retain a resumable pause")
	check( not Input.is_action_pressed("ui_accept") and Input.get_vector("move_left", "move_right", "move_up", "move_down") == Vector2.ZERO, "background left touch actions held")
	controller._on_window_focus_exited()
	check(controller._previous_max_fps == fps, "duplicate suspension overwrote saved frame cap")
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(paused and not controller._focus_paused and Engine.max_fps == fps, "resume did not restore frame cap and retain manual pause")
	controller.close(); await frames(2)
	touch(2, ui._stick_center, false);touch(3, ui._charge_center, false); await frames(3)
	check(game.game_state == 0 and not game.ball.is_in_play, "background release created a ghost serve")

	touch(4, ui._charge_center, true); await frames(18);touch(4, ui._charge_center, false); await frames(1)
	check(game.game_state == 1, "committed serve fixture failed")
	var target: Vector3 = game.aim_controller.get_target()
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(game.aim_controller.is_locked() and game.aim_controller.get_target() == target, "suspension unlocked committed serve aim")
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(paused and game.game_state == 1, "committed serve resumed behind menu")
	controller.close()
	for i in range(120):
		await frames(1)
		if game.game_state == 2: break
	check(game.game_state == 2 and game.ball.last_hit_by == 0, "committed serve did not continue after Resume")
	game._reset_ball(); await frames(2)
	var camera: Camera3D = game.main_camera
	var saved: = camera.global_transform
	var saved_offset: = Vector2(camera.h_offset, camera.v_offset)
	game.ball.global_position = Vector3(0.7, Ball.FLOOR_Y + Ball.BALL_RADIUS, -3.6);game.ball.linear_velocity = Vector3.ZERO
	game._on_point_scored(0); await frames(22)
	check(game.camera_rig.is_between_point_cinematic_active(), "retrieval montage fixture failed")
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check( not game.camera_rig.is_between_point_cinematic_active(), "suspension retained cinematic")
	check(camera.global_transform.is_equal_approx(saved) and Vector2(camera.h_offset, camera.v_offset).is_equal_approx(saved_offset), "suspension did not restore exact gameplay camera")
	var elapsed: float = game.between_point_controller.elapsed
	await create_timer(0.05, true).timeout
	check(is_equal_approx(elapsed, game.between_point_controller.elapsed), "suspended retrieval time advanced")
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED);controller.close(); await frames(2)
	check( not game.camera_rig.is_between_point_cinematic_active(), "resume restarted cancelled montage")
	game.between_point_controller.skip()
	check(game.game_state == 0 and not game.hud._between_point_active, "skip after resume did not reach serve")
	game.queue_free(); await process_frame
	for failure in failures: push_error(failure)
	print("ANDROID BACK LIFECYCLE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
