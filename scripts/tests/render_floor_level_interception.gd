extends "res://scripts/tests/test_floor_level_interception.gd"

# Native-engine render of automatic preparation and solved contact geometry.
# Contact frames are deliberately posed from the planner, not phone captures.
var output := "/tmp/floor-contact-renders"
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output)
	var pause = root.get_node_or_null("PauseController")
	if pause:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
		pause.close()
	paused = false
	surface = Geometry.sample_head_surface()
	var game = await setup_game()
	var p = game.player_left
	game.player_right.visible = false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 800)
	viewport.world_3d = game.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.50
	camera.near = 0.01
	camera.far = 40.0
	viewport.add_child(camera)
	camera.make_current()
	var label := Label.new()
	label.position = Vector2(22, 18)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	viewport.add_child(label)
	var notes: Array = []
	for lateral in [-0.42, 0.42]:
		var family := "backhand" if lateral < 0.0 else "forehand"
		game.process_mode = Node.PROCESS_MODE_INHERIT
		game.ball.freeze = false
		prepare_live(game, lateral, 0.08, 0.6)
		await physics_frame
		await physics_frame
		game.process_mode = Node.PROCESS_MODE_DISABLED
		game.ball.freeze = true
		for node in game.find_children("*", "MeshInstance3D", true, false):
			if node.get_script() != null and str(node.get_script().resource_path).ends_with("/ball_trail.gd"): node.visible = false
		var center: Vector3 = p.global_position + Vector3(0, -0.16, -0.28)
		camera.global_position = center + p._get_forward_axis() * 0.8 + p._get_forehand_axis() * (3.3 if lateral > 0.0 else -3.3) + Vector3.UP * 0.55
		camera.look_at(center)
		label.text = "%s | start of automatic preparation\nNative Godot render" % family.capitalize()
		await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(output.path_join(family + "-preparation.png"))
		# Continue the actual low approach while holding an early user charge.
		# Capture before the still-legal ball reaches its second bounce.
		game.process_mode = Node.PROCESS_MODE_INHERIT
		game.ball.freeze = false
		Input.action_press("ui_accept")
		game.input_handler._handle_swing_charge(0.08)
		await physics_frame
		await physics_frame
		game.process_mode = Node.PROCESS_MODE_DISABLED
		game.ball.freeze = true
		label.text = "%s | early charge, low-ball approach\nNative Godot render" % family.capitalize()
		check(game.ball.bounces_since_last_hit == 1 and game.ball.last_hit_by == 1, family + " charged capture left legal pre-contact flight")
		await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(output.path_join(family + "-charge.png"))
		Input.action_release("ui_accept")
		game.input_handler._handle_swing_charge(0.0)
		var source: PostureDefinition = PostureLibrary.instance().get_def(5 if lateral > 0.0 else 7)
		var ball_point := point(p, lateral, 0.06, source.zone_forward_offset)
		var pose: PostureDefinition = Planner.pose_at(p, source, ball_point)
		p.posture.human_contact.cancel()
		p.posture.transition_pose_blend = pose
		p.posture.force_posture_update(pose)
		p.refresh_contact_support(pose)
		game.ball.global_position = ball_point
		game.ball.linear_velocity = Vector3.ZERO
		game.ball.visible = true
		if p.debug_visual.human_intercept_indicator: p.debug_visual.human_intercept_indicator.visible = false
		var paddle: Transform3D = p.paddle_node.global_transform
		var floor_min := INF
		for vertex in surface: floor_min = minf(floor_min, (paddle * vertex).y - p.COURT_FLOOR_Y)
		var wrist := Wrist.wrist_world(paddle, pose).distance_to(Wrist.live_shoulder(p, pose))
		var touch := Finite.touches(paddle, ball_point, Ball.BALL_RADIUS)
		label.text = "%s | solved floor-level contact\nBall center 6 cm above court | finite paddle touch\nNative Godot render" % family.capitalize()
		await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(output.path_join(family + "-contact.png"))
		notes.append({"family": family, "ball_height": 0.06, "touch": touch, "paddle_floor": floor_min, "wrist": wrist})
		check(touch and floor_min >= -0.0001 and wrist <= 0.7001, family + " render geometry invalid")
	var evidence := FileAccess.open(output.path_join("geometry.json"), FileAccess.WRITE)
	evidence.store_string(JSON.stringify(notes, "\t")); evidence.close()
	game.queue_free()
	viewport.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("FLOOR CONTACT RENDERS: ", output, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
