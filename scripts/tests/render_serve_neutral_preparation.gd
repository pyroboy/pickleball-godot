extends "res://scripts/tests/author_serve_neutral_endpoints.gd"


const OUT: = "/workspace/shared/pickleball-hands/serve-neutral-preparation"
func run():
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	paused = false
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(1000, 900);root.content_scale_size = Vector2i(1000, 900)
	DisplayServer.window_set_size(Vector2i(1000, 900))
	root.get_node("Settings")._config.set_value("video", "shadow_quality", 0)
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	for child in game.get_children():
		if child is CanvasLayer: child.visible = false
	var p = game.player_left;game.player_right.body_pivot.visible = false
	p.posture.editor_preview_mode = false;p.hitting.serving_visual_active = true;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
	p.current_velocity = Vector3.ZERO;p.posture._committed_incoming_posture = -1
	game.serving_team = 0;game.ball.is_in_play = false;game.ball.freeze = true;game.ball.show()
	var camera: Camera3D = game.main_camera;camera.projection = Camera3D.PROJECTION_PERSPECTIVE;camera.fov = 42;camera.near = 0.012
	var overlay: = CanvasLayer.new();root.add_child(overlay)
	var caption: = Label.new();caption.position = Vector2(24, 20);caption.add_theme_font_size_override("font_size", 24);overlay.add_child(caption)
	surface = Paddle.sample_head_surface()
	var configs: Array = JSON.parse_string(FileAccess.get_file_as_string("/workspace/shared/pickleball-hands/neutral-serve-endpoint-candidates.json"))
	for axial in [0.0, -30.0]:
		var config: Dictionary = {}
		for entry in configs:
			if entry.wrist_x == 0.42 and entry.wrist_y == - 0.12 and entry.wrist_forward0 == 0.1 and entry.pole_x == 0.42 and entry.pole_y == 0.04 and entry.pole_forward == - 0.05 and entry.axial == axial: config = entry;break
		assert ( not config.is_empty())
		for charge in [0.0, 1.0]:
			game.game_serve.selected_serve_style = 0
			sample(p, config, 0, charge, 0.0)
			game.ball.global_position = game.game_serve.get_held_ball_position()
			var pose: PostureDefinition = p.posture.transition_pose_blend
			var body: Transform3D = p.body_pivot.global_transform; var paddle: Transform3D = p.paddle_node.global_transform
			for view in ["body_front", "body_side", "hand_arm"]:
				var focus: Vector3 = p.global_position + Vector3.UP * 0.02
				var offset: Vector3 = p._get_forward_axis() * 2.6 + Vector3.UP * 0.12
				if view == "body_side": offset = p._get_forehand_axis() * 2.55 + p._get_forward_axis() * 0.7 + Vector3.UP * 0.1
				if view == "hand_arm":
					focus = p.right_arm_node.upper_pivot.global_position.lerp(p.right_arm_node.anatomical_wrist_world, 0.6)
					offset = p._get_forehand_axis() * 0.8 + p._get_forward_axis() * 0.65 + Vector3.UP * 0.12
				camera.global_position = focus + offset;camera.look_at(focus, Vector3.UP)
				caption.text = "Neutral preparation trial · charge %d%% · axial %d°\nFixed135° grip · actual supported body · %s" % [roundi(charge * 100), roundi(axial), view]
				await process_frame; await RenderingServer.frame_post_draw
				assert (p.body_pivot.global_transform.is_equal_approx(body) and p.paddle_node.global_transform.is_equal_approx(paddle), "Frozen rig changed during capture")
				root.get_texture().get_image().save_png(OUT.path_join("ax%d_q%d_%s.png" % [roundi(axial), roundi(charge * 100), view]))
	var file: = FileAccess.open(OUT.path_join("measurements.json"), FileAccess.WRITE);file.store_string(JSON.stringify(rows, "\t"));file.close()
	print("NEUTRAL PREPARATION CAPTURE ", OUT)
	game.queue_free(); await process_frame;quit()
