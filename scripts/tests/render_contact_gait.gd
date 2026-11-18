extends SceneTree


const Body = preload("res://scripts/stroke_body_pose.gd")
var output: = "/workspace/shared/pickleball-hands/contact-gait"
func _initialize(): call_deferred("run")
func run():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output)
	var pause = root.get_node_or_null("PauseController")
	if pause:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
		pause.close()
	paused = false
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup();game.ball.visible = false
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	var p = game.player_left;game.player_right.body_pivot.visible = false
	for child in game.get_children():
		if child is CanvasLayer: child.visible = false
	p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
	p.posture.editor_preview_mode = false;p.posture._committed_incoming_posture = -1
	var view: = SubViewport.new();view.size = Vector2i(640, 480);view.world_3d = game.get_world_3d();view.render_target_update_mode = SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var camera: = Camera3D.new();camera.projection = Camera3D.PROJECTION_ORTHOGONAL;camera.size = 2.25;camera.near = 0.01;camera.far = 40;view.add_child(camera);camera.make_current()
	var label: = Label.new();label.position = Vector2(12, 8);label.add_theme_font_size_override("font_size", 16);view.add_child(label)
	var records: Array = []
	for mode in ["slow_forward", "half_lateral", "full_lateral", "full_diagonal", "short_drop_step", "long_retreat", "wide_recovery", "jump_landing"]:
		var pose: PostureDefinition = load("res://data/postures/20_ready.tres").duplicate(true)
		p.global_position = Vector3(0, p.ground_y, 3);p.current_velocity = Vector3.ZERO;p.is_jumping = false
		p.leg_ik.feet_initialized = false;p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
		var sheet: = Image.create(1920, 1440, false, Image.FORMAT_RGB8); var index: = 0
		for frame in range(97):
			var velocity: Vector3 = p._get_forward_axis() * p.move_speed * 0.25
			match mode:
				"half_lateral": velocity = p._get_forehand_axis() * p.move_speed * 0.5
				"full_lateral": velocity = p._get_forehand_axis() * p.move_speed
				"full_diagonal": velocity = (p._get_forward_axis() + p._get_forehand_axis()).normalized() * p.move_speed
				"short_drop_step": velocity = ( - p._get_forward_axis() + p._get_forehand_axis() * 0.65).normalized() * (1.1 if frame < 20 else 0.0)
				"long_retreat": velocity = ( - p._get_forward_axis() + p._get_forehand_axis() * 0.65).normalized() * p.move_speed * 0.6
				"wide_recovery": velocity = p._get_forehand_axis() * p.move_speed * 0.5 * (1 if frame < 36 else -1);pose.stance_width = lerpf(0.72, 0.48, smoothstep(0, 0.8, frame / 60.0))
				"jump_landing":
					velocity = p._get_forward_axis() * 0.8
					var phase: float = clampf((frame / 60.0 - 0.2) / 0.72, 0, 1)
					p.is_jumping = phase > 0 and phase < 1;p.global_position.y = p.ground_y + sin(PI * phase) * 0.24
			if frame > 80: velocity = Vector3.ZERO
			p.current_velocity = velocity;p.global_position += velocity / 60.0
			p.posture.force_posture_update(pose, false);p.leg_ik.update_leg_ik(1.0 / 60.0, pose);p.arm_ik.update_arm_ik(1.0 / 60.0, pose)
			if frame % 12 != 0: continue
			var center: Vector3 = p.global_position + Vector3(0, - 0.12, 0)
			camera.global_position = center + p._get_forward_axis() * 2.6 + p._get_forehand_axis() * 1.8 + Vector3.UP * 0.25;camera.look_at(center)
			label.text = "%s | %.2fs\ncontacts R%d L%d | pelvis %.0f°" % [mode, frame / 60.0, p.leg_ik.right_contact_serial, p.leg_ik.left_contact_serial, p.leg_ik.locomotion_hip_yaw_deg]
			await process_frame; await RenderingServer.frame_post_draw
			var image: Image = view.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, view.size), Vector2i((index % 3) * 640, (index / 3) * 480));index += 1
			records.append({"mode": mode, "time": frame / 60.0, "right_yaw": rad_to_deg(p.leg_ik._right_yaw), "left_yaw": rad_to_deg(p.leg_ik._left_yaw), "hip_intent": p.leg_ik.locomotion_hip_yaw_deg, "right_locked": p.leg_ik.right_foot_locked, "left_locked": p.leg_ik.left_foot_locked})
		sheet.save_png(output.path_join(mode + ".png"))
	var file: = FileAccess.open(output.path_join("frames.json"), FileAccess.WRITE);file.store_string(JSON.stringify(records, "\t"));file.close()
	print("CONTACT GAIT CAPTURE ", output);game.queue_free(); await process_frame;quit()
