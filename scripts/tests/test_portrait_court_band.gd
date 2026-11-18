extends SceneTree


const Layout = preload("res://scripts/ui/mobile_layout.gd")
var game
var checks: = 0
var failures: Array[String] = []
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(message)
func run() -> void :
	root.get_node("PauseController").set_process_input(false)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	game.input_handler.set_process(false)
	game.set_physics_process(false)
	game.game_state = game.GameState.PLAYING
	game.ball.freeze = true
	game.camera_rig.set_gameplay_camera_mode(0)
	# This suite isolates the conservative whole-court fallback. The adaptive
	# actor/ball view is covered by test_gameplay_camera_modes.
	game.camera_rig.portrait_adaptive_framing = false
	for resolution in [Vector2i(720, 1280), Vector2i(720, 1560), Vector2i(720, 1600), Vector2i(600, 960), Vector2i(1080, 2340), Vector2i(720, 800)]:
		root.content_scale_size = resolution;root.size = resolution
		await process_frame; await process_frame
		game.hud._layout_desktop();game.mobile_controls._layout();game.camera_rig.update(0)
		var viewport: = root.get_visible_rect()
		var scale: = Layout.scale_for(viewport.size)
		var band: = Layout.court_rect(viewport.size, viewport)
		var camera: Camera3D = game.main_camera
		var projected: Rect2 = game.camera_rig._portrait_projected_bounds()
		var hud_bottom: float = maxf(game.hud.speed.get_global_rect().end.y, game.hud.shot_type.get_global_rect().end.y)

		var control_top: float = game.mobile_controls._charge_center.y - 132 * scale
		check(band.position.y >= hud_bottom, "court band crosses HUD at %s" % resolution)
		check(band.end.y <= control_top, "court band crosses top control caption at %s" % resolution)
		check(band.encloses(projected), "player/court envelope leaves band at %s: %s vs %s" % [resolution, projected, band])
		if float(resolution.y) / resolution.x >= 1.5:

			check(projected.size.x >= band.size.x * 0.85, "court unnecessarily narrow at %s" % resolution)
			check(maxf(projected.size.x / band.size.x, projected.size.y / band.size.y) >= 0.97, "framing wastes both available dimensions at %s" % resolution)


			check(projected.size.y >= band.size.y * 0.5, "lower court unnecessarily small at %s" % resolution)
		check(camera.position.z > 7.35 and camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "behind-player perspective lost")
		for x in [-3.05, 3.05]:
			for z in [-6.7, 6.7]:
				check(band.has_point(camera.unproject_position(Vector3(x, 0.075, z))), "playable corner obscured at %s" % resolution)
		for z in [-7.1, 7.1]:
			var foot: = camera.unproject_position(Vector3(0, 0.075, z))
			var head: = camera.unproject_position(Vector3(0, 1.8, z))
			if float(resolution.y) / resolution.x >= 1.5:
				var minimum_height: = 95.0 if z > 0 else 50.0
				check(foot.distance_to(head) >= minimum_height * scale, "player too compressed at %s z=%s" % [resolution, z])
		var eye: = camera.get_camera_transform().origin
		var near_ray: = rad_to_deg(atan2(eye.y - 1, eye.z - 6.8))
		check(near_ray <= 50.01, "near-body ray exceeds raised overview cap")
		var transform: = camera.transform
		var offset: = camera.v_offset
		for i in range(4): game.camera_rig.update(0)
		check(camera.transform.is_equal_approx(transform) and is_equal_approx(camera.v_offset, offset), "cached framing drifts")
		print("COURT BAND %s band=%s projected=%s ray=%.2f" % [resolution, band, projected, near_ray])

	var safe: = Layout.safe_rect_from_pixels(Rect2(0, 0, 720, 1560), Rect2i(0, 90, 1080, 2178), Vector2(1080, 2340))
	var safe_band: = Layout.court_rect(Vector2(720, 1560), safe)
	check(safe_band.position.y >= safe.position.y + 312, "notch-adjusted band overlaps HUD")
	check(safe_band.end.y <= safe.end.y - 284, "navigation-adjusted band overlaps controls")
	game.queue_free(); await process_frame; await process_frame
	for failure in failures: push_error(failure)
	print("PORTRAIT COURT BAND: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
