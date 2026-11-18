extends SceneTree

const Layout = preload("res://scripts/ui/mobile_layout.gd")
var game
var checks: = 0
var failures: Array[String] = []
var capture_dir: = ""
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); print("FAIL: ", message)
func capture(label: String) -> void:
	if capture_dir.is_empty(): return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir.path_join(label + ".png"))
func settle(count: int = 50) -> void:
	for i in count: game.camera_rig.update(1.0 / 60.0)
func ball_visible(label: String, centered: bool = false) -> void:
	var camera: Camera3D = game.main_camera
	var screen: Rect2 = root.get_visible_rect()
	var projected: Vector2 = camera.unproject_position(game.ball.global_position)
	check(camera.global_transform.is_finite(), label + " finite transform")
	check(not camera.is_position_behind(game.ball.global_position), label + " target in front")
	check(screen.grow(-2).has_point(projected), label + " target on screen " + str(projected))
	if centered: check(projected.distance_to(screen.get_center()) < 0.05, label + " exact center lock " + str(projected))
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	root.size = Vector2i(432, 936); root.content_scale_size = Vector2i(720, 1560)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	paused = false
	game.set_physics_process(false)
	game.game_serve.set_process(false)
	game.game_serve.set_physics_process(false)
	game.input_handler.set_process(false)
	game.ball.freeze = true
	for player in [game.player_left, game.player_right]: player.set_physics_process(false)
	var rig = game.camera_rig
	var camera: Camera3D = game.main_camera
	var settings = root.get_node("Settings")
	for team in [0, 1]:
		game.serving_team = team; game.game_state = 0
		game.ball.is_in_play = false
		var server = game.player_left if team == 0 else game.player_right
		game.ball.global_position = server.global_position + Vector3(0.4, 0.0, -0.3 if team == 0 else 0.3)
		rig.set_gameplay_camera_mode(0); settle()
		check(rig.gameplay_camera.active_kind == ("serve0" if team == 0 else "center"), "Blue-owned serve/receiving camera")
		check(camera.global_position.z > -9.4 and absf(camera.global_position.x) < 5.5, "camera inside arena boards")
		ball_visible("serve%d" % team)
		await capture("01-serve-%d" % team)
		game.game_state = 1; settle(5)
		check(rig.gameplay_camera.active_kind == ("serve0" if team == 0 else "center"), "delivery preserves Blue viewpoint")
		game.game_state = 2; game.ball.is_in_play = true
		var before: Transform3D = camera.global_transform
		rig.update(1.0 / 60.0)
		check(rig.gameplay_camera.active_kind == "center", "contact begins centered return")
		check(camera.global_position.distance_to(before.origin) < 0.25, "serve contact transition no positional cut")
		for i in 45:
			rig.update(1.0 / 60.0); ball_visible("serve transition %d/%d" % [team, i])
		check(is_equal_approx(rig.gameplay_camera._transition_elapsed, rig.gameplay_camera.TRANSITION_SECONDS), "serve return completes")
		await capture("02-center-return-%d" % team)
	settings.set_value("video.camera_mode", 1)
	check(rig.gameplay_camera.mode == 1, "settings apply live")
	await process_frame
	var config: = ConfigFile.new()
	check(config.load("user://settings.cfg") == OK and int(config.get_value("video", "camera_mode", -1)) == 1, "settings persisted")
	for mode in [0, 1, 2]:
		rig.set_gameplay_camera_mode(mode)
		game.game_state = 2; game.ball.is_in_play = true
		for depth in [2.4, 6.9]:
			game.player_left.global_position = Vector3(1.5, 1.0, depth)
			await process_frame
			for target in [Vector3(0, 1, -5), Vector3(4.4, 0.35, 1), Vector3(-4.4, 3, -3), Vector3(0, 8, 0), Vector3(0, 1, 9), Vector3(0, 0.12, depth)]:
				game.ball.global_position = target
				settle()
				rig._process(1.0 / 60.0)
				ball_visible("mode%d depth%.1f target%s" % [mode, depth, target], mode == 2)
				if mode == 0:
					var band: Rect2 = Layout.court_rect(root.get_visible_rect().size, Layout.safe_rect(root))
					check(rig._action_points_fit(rig._portrait_action_points(), band), "adaptive frame keeps both players, ball, opposite court and net")
				check(camera.h_offset == 0.0, "no unwanted horizontal shake")
				if target == Vector3(0, 1, -5): await capture("03-mode%d-depth%.1f" % [mode, depth])
				if target == Vector3(0, 8, 0): await capture("04-mode%d-high" % mode)
				if target == Vector3(4.4, 0.35, 1): await capture("05-mode%d-wide" % mode)
		game.game_state = 3; game.ball.is_in_play = false
		if mode != 0: check(not rig.begin_between_point_cinematic(), "persistent view blocks cinematic override")
		game._reset_ball(); game.game_serve.set_process(false); game.ball.freeze = true
		settle(); check(rig.gameplay_camera.mode == mode, "reset preserves preference")
	# Continuous trajectories cross inner/outer margins without settling between
	# samples, including high lobs and lateral player travel at net/backcourt.
	game.game_state = 2; game.ball.is_in_play = true
	for mode in [0, 1, 2]:
		rig.set_gameplay_camera_mode(mode)
		for frame in 180:
			var phase: float = float(frame) / 179.0 * TAU
			game.player_left.position = Vector3(2.5 * sin(phase), 1.0, 6.8 - 4.4 * absf(sin(phase * 0.5)))
			game.player_right.position = Vector3(-2.5 * sin(phase + 0.3), 1.0, -6.8 + 4.4 * absf(sin(phase * 0.5)))
			game.ball.global_position = Vector3(4.8 * sin(phase * 2.0), 0.15 + 7.8 * absf(sin(phase * 0.7)), 7.2 * cos(phase))
			rig.update(1.0 / 60.0); rig._process(1.0 / 60.0)
			ball_visible("transient mode%d frame%d" % [mode, frame], mode == 2)
			if mode == 0:
				check(rig._action_points_fit(rig._portrait_action_points(), Layout.court_rect(root.get_visible_rect().size, Layout.safe_rect(root))), "transient adaptive action envelope stays visible")
	game._reset_player_positions()
	# POV must survive a render-late target change, vertical and coincident ball.
	rig.set_gameplay_camera_mode(2); settle()
	for target in [camera.global_position, camera.global_position + Vector3.UP * 2.0, camera.global_position + Vector3.DOWN * 2.0]:
		game.ball.global_position = target
		rig.add_shake(1.0); rig._process(1.0 / 60.0)
		ball_visible("POV coincident/vertical/late", true)
	check(not rig.gameplay_camera._hidden_meshes.is_empty(), "POV avatar hidden to prevent clipping")
	rig.begin_editor_view(game.player_left)
	check(rig.gameplay_camera._hidden_meshes.is_empty(), "editor restores avatar")
	rig.end_editor_view(); settle()
	check(rig.gameplay_camera.mode == 2, "editor preserves POV preference")
	rig.set_gameplay_camera_mode(0); settle()
	check(rig.gameplay_camera._hidden_meshes.is_empty(), "leaving POV restores avatar")
	# Compare the old overview to the raised overview with identical actors.
	game.game_state = 2; game.ball.global_position = Vector3(0, 1, 0)
	for spec in [[40.0, 43.0, "07-overview-before"], [48.0, 50.0, "08-overview-raised"]]:
		rig.portrait_elevation_degrees = spec[0]; rig.portrait_max_baseline_view_angle = spec[1]
		rig.portrait_adaptive_framing = float(spec[0]) > 40.0
		settle(180)
		var foot: Vector2 = camera.unproject_position(Vector3(game.player_left.position.x, 0.08, game.player_left.position.z))
		var head: Vector2 = camera.unproject_position(game.player_left.get_node("BodyPivot/TorsoMesh/HeadMesh").global_position + Vector3.UP * 0.12)
		print("OVERVIEW ", spec[2], " eye=", camera.get_camera_transform().origin, " player_pixels=", foot.distance_to(head) * 432.0 / 720.0, " zoom=", rig._portrait_action_zoom)
		await capture(spec[2])
	# Mode changes in both editor routes must take effect after closing.
	rig.orbit_mode = 1; rig.begin_editor_view(game.player_left)
	rig.set_gameplay_camera_mode(2); rig.end_editor_view(); settle()
	check(rig.orbit_mode == 0 and rig.gameplay_camera.active_kind == "pov", "new editor returns to selected POV")
	rig.orbit_mode = 3; game._editor_previous_camera_mode = 1
	rig.set_gameplay_camera_mode(1)
	check(rig.orbit_mode == 3 and game._editor_previous_camera_mode == 0, "legacy editor preserves editing and changes return mode")
	rig.orbit_mode = 0; settle()
	# A wall-practice override must not inherit portrait or shake offsets.
	rig.set_gameplay_camera_mode(0); camera.v_offset = 1.3; camera.h_offset = 0.2
	game.practice_launcher.start_drill("WALL"); rig.update(1.0 / 60.0)
	check(camera.v_offset == 0 and camera.h_offset == 0 and camera.frustum_offset == Vector2.ZERO, "wall center clears old framing")
	rig.set_gameplay_camera_mode(2); rig.update(1.0 / 60.0); rig._process(1.0 / 60.0)
	ball_visible("wall POV", true)
	game.practice_launcher.stop_practice(); game._reset_ball(); game.ball.freeze = true
	# Keep apparent FOV continuous across landscape projection conventions.
	root.size = Vector2i(1280, 720); root.content_scale_size = Vector2i(1280, 720)
	await process_frame; await process_frame
	game.serving_team = 0
	rig.set_gameplay_camera_mode(0); game.game_state = 0; settle()
	var previous_horizontal: float = camera.fov
	game.game_state = 2; rig.update(1.0 / 60.0)
	var current_horizontal: float = rig.GameplayCamera.convert_fov(camera.fov, camera.keep_aspect, Camera3D.KEEP_WIDTH, root.get_visible_rect().size)
	check(absf(previous_horizontal - current_horizontal) < 0.25, "landscape serve return preserves apparent FOV")
	root.size = Vector2i(432, 936); root.content_scale_size = Vector2i(720, 1560)
	await process_frame; await process_frame
	rig.set_gameplay_camera_mode(0); settle()
	var panel = load("res://scripts/ui/settings_panel.gd").new(); game.add_child(panel)
	await process_frame
	var selector = panel.find_child("video_camera_mode", true, false)
	check(selector != null and selector.item_count == 3, "settings offers three camera modes")
	await capture("06-camera-settings")
	panel.queue_free()
	settings.set_value("video.camera_mode", 0)
	print("GAMEPLAY CAMERA MODES: %d checks, %d failures" % [checks, failures.size()])
	game.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
