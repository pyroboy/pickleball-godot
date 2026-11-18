extends SceneTree
var game
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func settle() -> void:
	for frame in 50: game.camera_rig.update(1.0 / 60.0)
func receiving(label: String) -> void:
	settle()
	check(game.camera_rig.gameplay_camera.active_kind == "center", label + " centered")
	check(game.main_camera.global_position.z > 0.0, label + " Blue side")
	check(not game.main_camera.is_position_behind(game.ball.global_position), label + " ball in front")
func run() -> void:
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	root.size = Vector2i(432,936); root.content_scale_size = Vector2i(720,1560)
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	paused = false
	game.set_physics_process(false); game.game_serve.set_process(false); game.game_serve.set_physics_process(false)
	game.input_handler.set_process(false)
	for player in [game.player_left,game.player_right]: player.set_physics_process(false)
	for score in [0,1]:
		game.score_right = score; game.serving_team = 1; game._reset_ball(); game.ball.freeze = true
		game.camera_rig.set_gameplay_camera_mode(0)
		receiving("Red setup service-court %d" % score)
		game.game_state = 1; receiving("Red delivery")
		game.game_state = 2; receiving("Red contact")
		game._reset_ball(); receiving("Red reset")
		# Settings are applied through the actual load/apply route.
		root.get_node("Settings").set_value("video.camera_mode",0)
		game._apply_setting("video.camera_mode",0); receiving("Red loaded preference")
		for repeat in 3:
			for mode in [2,1,0,1,2,0]:
				game.camera_rig.set_gameplay_camera_mode(mode); settle()
				var camera: Camera3D = game.main_camera
				check(camera.global_position.z > 0, "Repeated mode stays Blue-owned")
				if mode == 2: check(camera.unproject_position(game.ball.global_position).distance_to(root.get_visible_rect().get_center()) < 0.05,"POV exact center")
				if mode == 0: receiving("Repeated Center during Red serve")
		game.serving_team = 0; game.game_state = 2; game.match_over = false
		game._on_point_scored(1); game.between_point_controller.skip(); game.ball.freeze = true
		check(game.serving_team == 1, "Actual sideout awards Red serve")
		receiving("Sideout to Red")
		game.serving_team = 0; game.score_left = score; game._reset_ball(); game.ball.freeze = true; settle()
		check(game.camera_rig.gameplay_camera.active_kind == "serve0", "Blue setup behind Blue")
		game.game_state = 1; settle()
		check(game.camera_rig.gameplay_camera.active_kind == "serve0", "Blue delivery behind Blue")
		game.game_state = 2
		game.camera_rig.update(1.0/60.0)
		check(game.camera_rig.gameplay_camera.active_kind == "center" and game.camera_rig.gameplay_camera._transition_elapsed < 0.65,"Blue contact starts smooth return")
		settle(); check(game.camera_rig.gameplay_camera._transition_elapsed == 0.65,"Blue contact completes return")
	print("RECEIVING CAMERA: %d checks, %d failures" % [checks,failures.size()])
	game.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
