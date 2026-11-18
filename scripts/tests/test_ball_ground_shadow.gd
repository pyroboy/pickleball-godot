extends SceneTree

const Shadows = preload("res://scripts/fx/ground_shadows.gd")
const Policy = preload("res://scripts/runtime_policy.gd")
var checks := 0
var failures: Array[String] = []
var game
var ball
var shadows
var marker: MeshInstance3D
var output := ""
var report: Array[Dictionary] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); print("FAIL: ", message)
func frames(count := 2) -> void:
	for i in count: await process_frame
func follow(label: String) -> void:
	shadows.update_shadows()
	check(marker.visible, label + " has a shadow")
	check(is_equal_approx(marker.global_position.x, ball.global_position.x) and is_equal_approx(marker.global_position.z, ball.global_position.z), label + " tracks actual XZ without prediction")
	check(is_equal_approx(marker.global_position.y, Ball.FLOOR_Y + 0.0045), label + " stays on physical floor with depth offset")
	check(marker.global_basis.y.normalized().is_equal_approx(Vector3.UP), label + " remains flat despite ball spin")
func place(point: Vector3, label: String) -> void:
	ball.freeze = true
	ball.global_position = point
	follow(label)
func settle_camera() -> void:
	# Real update time is needed to finish FOV/look-target easing after a mode or
	# viewport change; update(0) preserves the preceding camera's transient lens.
	for step in 120: game.camera_rig.update(1.0 / 60.0)
func capture(label: String, compare := false) -> void:
	if output.is_empty(): return
	await frames(2); await RenderingServer.frame_post_draw
	var shown: Image = root.get_texture().get_image()
	check(shown.save_png(output.path_join(label + ".png")) == OK, "save capture " + label)
	if not compare: return
	marker.hide()
	await frames(2); await RenderingServer.frame_post_draw
	var hidden: Image = root.get_texture().get_image()
	check(hidden.save_png(output.path_join(label + "-without-blob.png")) == OK, "save comparison " + label)
	marker.show()
	var projected: Vector2 = game.main_camera.unproject_position(marker.global_position)
	check(not game.main_camera.is_position_behind(marker.global_position) and root.get_visible_rect().has_point(projected), label + " ground sample is actually in view")
	var pixel_scale: Vector2 = Vector2(shown.get_size()) / root.get_visible_rect().size
	var center: Vector2i = Vector2i(projected * pixel_scale)
	var dark_pixels := 0
	var max_change := 0.0
	for y in range(maxi(0, center.y - 24), mini(shown.get_height(), center.y + 25)):
		for x in range(maxi(0, center.x - 24), mini(shown.get_width(), center.x + 25)):
			var a: Color = shown.get_pixel(x, y)
			var b: Color = hidden.get_pixel(x, y)
			var darkness: float = ((b.r - a.r) + (b.g - a.g) + (b.b - a.b)) / 3.0
			max_change = maxf(max_change, darkness)
			if darkness > 0.035: dark_pixels += 1
	check(max_change >= 0.09 and dark_pixels >= 6, label + " visibly darkens actual court pixels (max=%.3f pixels=%d)" % [max_change, dark_pixels])
	report.append({"capture": label, "center_px": [center.x, center.y], "darkened_pixels": dark_pixels, "max_luminance_change": max_change})
func run() -> void:
	create_timer(120, true).timeout.connect(func(): push_error("Ball shadow suite timeout"); quit(2))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): output = arg.trim_prefix("--capture-dir=")
	if not output.is_empty():
		if DisplayServer.get_name() == "headless": push_error("Capture requires native renderer"); quit(2); return
		DirAccess.make_dir_recursive_absolute(output)
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	root.size = Vector2i(540, 960); root.content_scale_size = Vector2i(720, 1280)
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	await frames(3)
	pause.close(); paused = false
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.game_serve.set_process(false)
	ball = game.ball; ball.freeze = true; ball.set_physics_process(false)
	shadows = game.get_node("GroundShadows"); marker = shadows.get_node("BallShadow")
	var material: ShaderMaterial = marker.material_override
	var plane: PlaneMesh = marker.mesh
	check(shadows.get_child_count() == 3 and shadows.find_children("BallShadow", "", false, false).size() == 1, "one existing ball draw, no duplicate blob")
	check(plane.get_faces().size() == 6 and plane.size == Vector2.ONE, "one cached two-triangle plane")
	check(shadows.find_children("*", "CollisionObject3D", true, false).is_empty() and shadows.find_children("*", "CollisionShape3D", true, false).is_empty(), "visual adds no collisions")
	check(marker.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "blob cannot itself cast a light shadow")
	check(material.shader == Shadows.BallShaderSource and shadows._materials[1].shader == Shadows.ShaderSource and shadows._materials[2].shader == Shadows.ShaderSource, "only ball uses stronger shader")
	check(is_equal_approx(Shadows.FLOOR_Y, 0.0795), "court and white lines are below depth offset")
	var surface: MeshInstance3D = game.get_node("Court/CourtSurface")
	check(surface.position.y + surface.mesh.size.y / 2.0 < Shadows.FLOOR_Y, "no court z-fighting")
	var apron: MeshInstance3D = game.get_node("Court/CourtApron")
	check(Vector2(apron.mesh.size.x, apron.mesh.size.z) / 2.0 == Shadows.BALL_APRON_HALF_SIZE, "ball clips to actual visible apron")
	var prior_diameter := 0.0
	var prior_opacity := 1.0
	for height in [-1.0, 0.0, 0.2, 1.0, 2.5, 4.8875, 100.0]:
		var cue: Vector3 = Shadows.cue_for_height(height, true)
		check(cue.x >= Shadows.BALL_MIN_DIAMETER - 0.000001 and cue.x <= Shadows.BALL_MAX_DIAMETER + 0.000001 and cue.x == cue.y, "bounded circular ground footprint %.2f" % height)
		check(cue.z >= Shadows.BALL_MIN_OPACITY - 0.000001 and cue.z <= Shadows.BALL_MAX_OPACITY + 0.000001, "high lob never fades out %.2f" % height)
		check(cue.x >= prior_diameter and cue.z <= prior_opacity, "height grows and lightens shadow monotonically")
		prior_diameter = cue.x; prior_opacity = cue.z
		var player: Vector3 = Shadows.cue_for_height(height, false)
		check(player.x <= 0.88 and player.z <= 0.25, "player cue remains restrained")
	var settings = root.get_node("Settings")
	check(settings.MOBILE_DEFAULTS["video.shadow_quality"] == 0, "mobile policy still defaults general shadows off")
	if Policy.mobile_runtime:
		check(not Policy.developer_tools and root.get_node("McpBridge").udp_server == null, "mobile disables developer overhead")
	# These are rally photometric fixtures. WAITING now intentionally selects
	# the serving camera; with the game disabled it would never transition.
	game.game_state = game.GameState.PLAYING
	game.camera_rig.set_gameplay_camera_mode(0)
	ball.is_in_play = true
	for quality in range(3):
		settings.set_value("video.shadow_quality", quality)
		check(game.get_node("Sun").shadow_enabled == (quality > 0), "general shadow setting actually applied")
		for point in [Vector3(-1.4, Ball.FLOOR_Y + Ball.BALL_RADIUS, 3.8), Vector3(1.4, 1.2, 0.8), Vector3(1.4, 5, -5.0), Vector3(3.4, 2, -6.8)]:
			ball.rotation = Vector3(0.5, 1.1, 2.3)
			place(point, "quality%d" % quality)
			check(marker.material_override == material and marker.mesh == plane, "quality does not replace resources")
		place(Vector3(1.45, 2.6, -4.5), "quality capture")
		settle_camera()
		await capture("portrait-quality-%d" % quality, true)
	settings.set_value("video.shadow_quality", 0)
	game._reset_ball(); ball.freeze = true; game._update_held_ball_position(); follow("held before serve")
	await capture("held-ball")
	ball.serve(0, Vector3(0.1, 0.6, -1)); follow("serve release")
	ball.is_in_play = true; ball.last_hit_by = 1; ball.both_bounces_complete = true
	place(Vector3(1.3, 1.5, 2.0), "rally")
	var unchanged: Array = [ball.global_transform, ball.linear_velocity, ball.angular_velocity, ball.flight_id, ball.bounce_count, ball.collision_layer, ball.collision_mask, ball.mass, ball.gravity_scale]
	var refresh_start: int = Time.get_ticks_usec()
	for iteration in 1000: shadows.update_shadows()
	print("BALL SHADOW PROFILE: mean_us=%.2f, one cached 2-triangle ball draw" % ((Time.get_ticks_usec() - refresh_start) / 1000.0))
	check(unchanged == [ball.global_transform, ball.linear_velocity, ball.angular_velocity, ball.flight_id, ball.bounce_count, ball.collision_layer, ball.collision_mask, ball.mass, ball.gravity_scale], "visual refresh leaves every sampled physics property unchanged")
	check(marker.mesh == plane and marker.material_override == material, "1000 updates allocate no new mesh/material")
	for point in [Vector3(3.5, 1.2, 7.2), Vector3(-7.9, 1.2, 19.9), Vector3(0, 5, -14)]:
		place(point, "out on visible apron")
	for point in [Vector3(8.1, 1, 0), Vector3(0, 1, 20.1), Vector3(-8.1, 1, -20.1)]:
		ball.global_position = point; shadows.update_shadows(); check(not marker.visible, "no floating shadow past apron")
	place(Vector3(1.4, 1.2, 3.0), "visibility fixture")
	paused = true
	ball.hide(); check(not marker.visible, "hidden paused ball hides shadow immediately")
	ball.show(); check(marker.visible, "shown paused ball restores shadow immediately")
	game.hide(); check(not marker.visible, "hidden ball ancestor hides shadow")
	game.show(); check(marker.visible, "visible ball ancestor restores shadow")
	var frozen_shadow: Vector3 = marker.global_position
	ball.global_position.x += 0.4
	await frames(3)
	check(marker.global_position == frozen_shadow, "pause does not advance shadow position")
	paused = false; shadows.update_shadows(); follow("resume")
	ball.reset(); follow("reset refresh")
	# Mobile editor has its own world: never project the live match blob into it.
	if Policy.mobile_runtime:
		pause.open(); game.open_mobile_pose_editor(); await frames(3)
		var editor = game.mobile_pose_editor
		check(is_instance_valid(editor), "real mobile editor opens")
		if is_instance_valid(editor):
			check(editor._preview.viewport.find_world_3d() != game.get_world_3d(), "editor world remains isolated")
			check(editor._preview.viewport.find_children("BallShadow", "", true, false).is_empty(), "live ball marker never leaks into editor preview")
			await capture("mobile-editor-isolated")
			editor.close(); await frames(3)
		pause.close(); paused = false
		check(game.mobile_pose_editor == null, "editor close cleanup")
		follow("editor resume")
	game.practice_launcher.start_drill("WALL")
	check(ball.wall_practice_active, "real wall practice entered")
	shadows.update_shadows(); follow("wall feed held")
	game.camera_rig.update(0.0); await capture("wall-held")
	place(Vector3(1.45, 2.3, 2.2), "wall rebound")
	await capture("wall-return", true)
	game.practice_launcher.stop_practice(); game._reset_ball()
	game.game_state = game.GameState.PLAYING
	ball.is_in_play = true
	for resolution in [Vector2i(432, 936), Vector2i(540, 960), Vector2i(1280, 800)]:
		game._reset_player_positions()
		root.size = resolution; root.content_scale_size = resolution
		await frames(2); game.hud._layout_desktop()
		game.camera_rig.set_gameplay_camera_mode(0); settle_camera()
		for sample in [{"label": "near-low", "point": Vector3(1.4, 0.35, 3.0)}, {"label": "far-low", "point": Vector3(1.4, 0.35, -5.2)}, {"label": "near-lob", "point": Vector3(1.4, 5.0, 3.0)}, {"label": "far-lob", "point": Vector3(1.4, 5.0, -5.2)}]:
			place(sample.point, sample.label)
			settle_camera()
			var center: Vector3 = marker.global_position
			var a: Vector2 = game.main_camera.unproject_position(center + Vector3.RIGHT * marker.scale.x * 0.5)
			var b: Vector2 = game.main_camera.unproject_position(center - Vector3.RIGHT * marker.scale.x * 0.5)
			check(a.distance_to(b) >= 5.0, "ground footprint remains at least 5px wide in gameplay view")
			await capture("%dx%d-%s" % [resolution.x, resolution.y, sample.label], true)
		for mode in [1, 2]:
			# Normal on-court rally positions keep the inherited behind-player
			# cameras in front of the stadium boards. Do not make shadows draw
			# through scenery simply to see from an obstructed baseline camera.
			for player in [game.player_left, game.player_right]:
				player.global_position = Vector3(0, player.ground_y, 3.8 if player.player_num == 0 else -3.8)
				player.leg_ik.feet_initialized = false
				player.posture.force_posture_update(PostureLibrary.instance().get_def(player.PaddlePosture.READY))
			place(Vector3(1.45, 2.6, -2 if mode == 1 else 2), "third person")
			ball.is_in_play = true
			game.camera_rig.orbit_mode = mode; settle_camera()
			await capture("%dx%d-camera-%d" % [resolution.x, resolution.y, mode], true)
		# Exercise actual Settings perspectives as well as retained developer
		# orbit views. A low ball keeps its physical ground point inside POV;
		# a skyward lob need not show the floor while exactly center-locked.
		for mode in [1, 2]:
			game.camera_rig.set_gameplay_camera_mode(mode)
			for sample in [{"label": "near-low", "point": Vector3(1.45, 0.35, 2.0)}, {"label": "far-low", "point": Vector3(1.45, 0.35, -5.2)}]:
				place(sample.point, "selected perspective")
				settle_camera(); game.camera_rig._process(1.0 / 60.0)
				await capture("%dx%d-selected-%d-%s" % [resolution.x, resolution.y, mode, sample.label], true)
	# Repeated rebinds/freeing targets cannot leave stale blobs or signal bindings.
	var old_marker = marker
	shadows.setup(ball, game.player_left, game.player_right)
	marker = shadows.get_node("BallShadow")
	check(not is_instance_valid(old_marker) and shadows.get_child_count() == 3, "rebind releases old draws")
	check(ball.visibility_changed.get_connections().filter(func(c): return c.callable == shadows.update_shadows).size() == 1, "rebind keeps one visibility callback")
	var dummy := Node3D.new(); game.add_child(dummy); dummy.position = Vector3(0, 1, 2)
	shadows.setup(dummy, game.player_left, game.player_right); marker = shadows.get_node("BallShadow")
	dummy.free(); check(not marker.visible, "free ball removes visible marker immediately")
	shadows.update_shadows(); check(not marker.visible, "freed target safe on subsequent update")
	shadows.setup(ball, game.player_left, game.player_right); marker = shadows.get_node("BallShadow"); follow("rebind actual ball")
	var last_marker = marker
	game.queue_free(); await frames(3)
	check(not is_instance_valid(last_marker), "game destruction frees shadow")
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("pixel-evidence.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "captures": report}, "\t")); file.close()
	print("BALL GROUND SHADOW: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
