extends SceneTree


class LateFrame extends Node:
	signal presented
	func _process(_delta: float) -> void : presented.emit()
var game
var late: LateFrame
var failures: Array[String] = []
var checks: = 0
var last_fault_view: Dictionary = {}
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(message);print("FAIL: ", message)
func frames(count: int) -> void :
	for i in range(count): await physics_frame; await late.presented
func view() -> Dictionary:
	var camera: Camera3D = game.main_camera
	return {"transform": camera.global_transform, "projection": camera.projection, "aspect": camera.keep_aspect, "fov": camera.fov, "h": camera.h_offset, "v": camera.v_offset}
func restored(saved: Dictionary, tag: String) -> void :
	var now: = view()
	check(now.transform.is_equal_approx(saved.transform), tag + " exact transform")
	check(now.projection == saved.projection and now.aspect == saved.aspect and is_equal_approx(now.fov, saved.fov), tag + " exact projection")
	check(is_equal_approx(now.h, saved.h) and is_equal_approx(now.v, saved.v), tag + " exact framing offsets")
func fault() -> void :
	game.score_left = 2;game.score_right = 3;game.serving_team = 0
	game._reset_ball()
	game.ball.global_position = Vector3(0.7, Ball.FLOOR_Y + Ball.BALL_RADIUS, -3.6)
	game.ball.linear_velocity = Vector3.ZERO
	last_fault_view = view()
	game._on_point_scored(0)
func run() -> void :
	create_timer(50).timeout.connect( func(): quit(2))
	root.size = Vector2i(432, 936)
	root.content_scale_size = Vector2i(720, 1560)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	late = LateFrame.new();late.process_priority = 10000;root.add_child(late)
	await frames(2)
	var rig = game.camera_rig
	var controller = game.between_point_controller
	# A point normally begins from the centered rally camera, not the new
	# temporary serving perspective. Establish that genuine pre-point state.
	game.game_state = game.GameState.PLAYING
	game.ball.is_in_play = false
	rig.set_gameplay_camera_mode(0)
	rig.update(1.0)
	var saved: = view()
	fault()
	check(controller.is_active() and rig.is_between_point_cinematic_active(), "real scoring starts retrieval and camera together")
	check(game.hud._between_point_active and game.hud._skip_button.visible, "real retrieval shows Skip")
	check(game.mobile_controls._blocked(), "retrieval blocks touch gameplay")
	await frames(78)
	var angle_a: = view()
	check(rig.is_between_point_cinematic_active() and not angle_a.transform.is_equal_approx(saved.transform), "first actual camera angle moves")
	await frames(98)
	var angle_b: = view()
	check(rig.is_between_point_cinematic_active() and not angle_b.transform.is_equal_approx(angle_a.transform), "second actual camera angle moves")
	check( not game.ball.is_in_play, "camera montage remains dead ball")
	await frames(77)
	check( not rig.is_between_point_cinematic_active(), "actual elapsed4seconds ends montage")
	check(rig.gameplay_camera.active_kind == "center" and game.main_camera.global_transform.is_finite(), "four-second return resumes adaptive centered view")
	check(controller.is_active(), "longer physical retrieval can continue in gameplay view")
	for i in range(650):
		if not controller.is_active(): break
		await frames(1)
	check( not controller.is_active() and game.game_state == 0 and not game.ball.is_in_play, "natural handover restores serve readiness")
	check(rig.gameplay_camera.mode == 0, "natural handover retains centered preference")
	check(not game.main_camera.is_position_behind(game.ball.global_position), "natural handover ball remains in view")
	check( not game.hud._between_point_active and not game.hud._skip_button.visible, "natural completion hides Skip")
	fault(); await frames(30)
	game.hud.skip_retrieval_requested.emit()
	check( not rig.is_between_point_cinematic_active() and not controller.is_active() and game.game_state == 0, "HUD Skip restores camera and serve readiness")
	await frames(3)
	check(rig.gameplay_camera.active_kind == "serve0", "HUD Skip returns to behind-server setup")
	fault(); await frames(30);paused = true
	check( not rig.is_between_point_cinematic_active(), "real pause restores camera immediately")
	restored(last_fault_view, "pause")
	var elapsed: float = controller.elapsed
	await create_timer(0.1, true).timeout
	check(is_equal_approx(controller.elapsed, elapsed), "paused retrieval timer stops")
	paused = false; await frames(3)
	check( not rig.is_between_point_cinematic_active(), "resume does not restart cancelled montage")
	controller.skip()
	fault(); await frames(30);game._reset_ball()
	check( not rig.is_between_point_cinematic_active() and not controller.is_active(), "reset cancels both owners")
	restored(last_fault_view, "reset")
	fault(); await frames(30);game.practice_launcher.start_drill("DRIVE")
	check( not rig.is_between_point_cinematic_active() and not controller.is_active(), "practice cancels both owners")
	restored(last_fault_view, "practice")
	game.practice_launcher.stop_practice()
	game.score_left = 10;game.score_right = 8;game.serving_team = 0;game._reset_ball();game._on_point_scored(0)
	check(game.match_over and not rig.is_between_point_cinematic_active() and not controller.is_active(), "winning point never begins montage")
	game.request_rematch()
	check( not game.match_over and game.game_state == 0, "rematch leaves normal court")
	check(rig.gameplay_camera.mode == 0, "rematch retains centered preference")
	game._set_game_state(game.GameState.PLAYING);game.ball.is_in_play = true
	check( not controller.begin() and not rig.begin_between_point_cinematic(controller.get_cinematic_focus), "live rally rejects both cinematic entrypoints")
	game.ball.is_in_play = false;game._set_game_state(game.GameState.WAITING)
	print("BETWEEN POINT CAMERA LIVE: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures: push_error(failure)
	game.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
