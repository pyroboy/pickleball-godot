extends SceneTree

var game
var failures: Array[String] = []
var checks: = 0
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(message)
func snapshot(camera: Camera3D) -> Dictionary:
	return {"transform": camera.global_transform, "fov": camera.fov, "projection": camera.projection, "keep_aspect": camera.keep_aspect, "h": camera.h_offset, "v": camera.v_offset}
func restored(camera: Camera3D, saved: Dictionary, label: String) -> void :
	check(camera.global_transform.is_equal_approx(saved.transform), label + " transform not restored")
	check(is_equal_approx(camera.fov, saved.fov) and camera.projection == saved.projection and camera.keep_aspect == saved.keep_aspect, label + " projection not restored")
	check(is_equal_approx(camera.h_offset, saved.h) and is_equal_approx(camera.v_offset, saved.v), label + " offsets not restored")
func focus() -> Vector3: return game.player_left.global_position
func begin() -> bool:
	game.game_state = 3;game.match_over = false;game._practice_mode = false
	game.ball.is_in_play = false
	return game.camera_rig.begin_between_point_cinematic(focus)
func run() -> void :
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	game.input_handler.set_process(false)
	var rig = game.camera_rig
	var camera: Camera3D = game.main_camera
	rig.update(0)
	var saved: = snapshot(camera)
	check( not rig.begin_between_point_cinematic(focus), "normal serve state allowed cinematic")
	check(begin(), "dead-ball camera did not begin")
	check( not rig.begin_between_point_cinematic(focus), "repeated begin replaced original snapshot")
	var left: Vector3 = game.player_left.global_position
	var right: Vector3 = game.player_right.global_position
	var ball: Vector3 = game.ball.global_position
	for delta in [0.3, 0.55, 0.75, 0.7, 0.7, 0.65]:
		rig.update(delta)
		check(rig.is_between_point_cinematic_active(), "cinematic ended before4seconds")
		check(camera.global_position.is_finite(), "cinematic camera became non-finite")
		var screen: = root.get_visible_rect()
		for y in [0.0, 2.15]:
			var point: = Vector3(left.x, y, left.z)
			check( not camera.is_position_behind(point) and screen.has_point(camera.unproject_position(point)), "focused player's full body clipped")
	check(game.player_left.global_position == left and game.player_right.global_position == right and game.ball.global_position == ball, "camera moved gameplay actors")
	rig.update(0.4)
	check( not rig.is_between_point_cinematic_active(), "camera did not end at4seconds")
	restored(camera, saved, "timed return")
	begin();rig.update(1.3);rig.end_between_point_cinematic();restored(camera, saved, "skip/cancel")
	begin();rig.update(0.8);paused = true
	check( not rig.is_between_point_cinematic_active(), "pause did not end cinematic")
	restored(camera, saved, "pause");paused = false
	begin();rig.update(0.8);game.game_state = 0;rig.update(0)
	check( not rig.is_between_point_cinematic_active(), "reset/serve state did not stop cinematic")
	restored(camera, saved, "state reset")
	begin();rig.update(0.8);game._practice_mode = true;rig.update(0)
	check( not rig.is_between_point_cinematic_active(), "practice did not stop cinematic")
	restored(camera, saved, "practice");game._practice_mode = false
	begin();rig.update(0.8);game.match_over = true;rig.update(0)
	check( not rig.is_between_point_cinematic_active(), "gameover did not stop cinematic")
	restored(camera, saved, "gameover");game.match_over = false
	begin();rig.update(0.8);game.ball.is_in_play = true;rig.update(0)
	check( not rig.is_between_point_cinematic_active(), "liveball did not stop cinematic")
	restored(camera, saved, "liveball");game.ball.is_in_play = false
	begin();rig.update(0.8);rig.begin_editor_view(game.player_left)
	check( not rig.is_between_point_cinematic_active() and rig.editor_active, "editor did not replace cinematic")
	rig.end_editor_view();restored(camera, saved, "editor close")
	begin();rig.update(0.8);root.size_changed.emit()
	check( not rig.is_between_point_cinematic_active(), "resize did not end cinematic")
	restored(camera, saved, "resize")
	game.game_state = 0
	game.queue_free(); await process_frame; await process_frame
	for failure in failures: push_error(failure)
	print("BETWEEN POINT CAMERA: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
