extends SceneTree

var output: = "/workspace/shared/pickleball-hands/postpreview-anatomy/after"
var label: = "Post-preview shape candidate"
var check_only: = false
func _initialize() -> void : call_deferred("run")
func run() -> void :
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	check_only = "--check-only" in OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" and not check_only: quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	var sources: Dictionary = {}
	for file in ["player_face_visual.gd", "body_surface_profile.gd", "articulated_torso_mesh.gd", "body_clearance.gd", "player_arm_visual.gd", "articulated_hand.gd"]:
		sources[file] = FileAccess.get_sha256("res://scripts/" + file)
	root.size = Vector2i(1000, 1000);root.content_scale_size = Vector2i(1000, 1000)
	if not check_only: DisplayServer.window_set_size(Vector2i(1000, 1000))
	var pause = root.get_node_or_null("PauseController")
	if pause:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
		pause.close()
	paused = false
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in 5: await process_frame
	game.game_serve.cleanup();game.process_mode = Node.PROCESS_MODE_DISABLED
	var nodes: Array = [game];nodes.append_array(game.find_children("*", "", true, false))
	for node in nodes: node.set_process(false);node.set_physics_process(false)
	for tween in get_processed_tweens(): tween.kill()
	game.ball.visible = false;game.player_right.body_pivot.visible = false
	for child in game.get_children():
		if child is CanvasLayer: child.visible = false
	var p = game.player_left
	var pose = load("res://data/postures/20_ready.tres").duplicate(true)
	pose.body_yaw_deg = 0;pose.hip_yaw_deg = 0;pose.torso_yaw_deg = 0;pose.torso_pitch_deg = -28
	pose.body_pitch_deg = 0;pose.body_roll_deg = 0;pose.torso_roll_deg = 0;pose.spine_curve_deg = 0;pose.crouch_amount = 0
	pose.head_yaw_deg = 0;pose.head_pitch_deg = 0;pose.weight_shift = 0;pose.stance_width = 0.36;pose.shoulder_protraction_m = 0
	pose.front_foot_forward = 0;pose.back_foot_back = 0;pose.right_foot_yaw_deg = 0;pose.left_foot_yaw_deg = 0
	pose.paddle_forehand_mul = 0.25;pose.paddle_forward_mul = 0.05;pose.paddle_y_offset = - 0.48
	pose.paddle_pitch_base_deg = 0;pose.paddle_pitch_signed_deg = 0;pose.paddle_yaw_base_deg = 0;pose.paddle_yaw_signed_deg = 0;pose.paddle_roll_base_deg = 180;pose.paddle_roll_signed_deg = 0
	pose.left_hand_mode = 4;pose.left_hand_offset = Vector3( - 0.1, - 0.3, - 0.5)
	p.posture.editor_preview_mode = false;p.current_velocity = Vector3.ZERO;p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false
	p.leg_ik.feet_initialized = false;p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
	var chest: Node3D = p.body_pivot.get_node("TorsoMesh"); var head: MeshInstance3D = chest.get_node("HeadMesh")
	var expected: Transform3D = p.body_pivot.global_transform
	var camera: = Camera3D.new();camera.projection = Camera3D.PROJECTION_ORTHOGONAL;camera.near = 0.01;game.add_child(camera);camera.make_current()

	var fill: = DirectionalLight3D.new();fill.light_energy = 0.7;fill.rotation_degrees = Vector3(-25, 145, 0);game.add_child(fill)
	var layer: = CanvasLayer.new();root.add_child(layer); var caption: = Label.new();caption.position = Vector2(18, 18);caption.add_theme_font_size_override("font_size", 22);layer.add_child(caption)
	caption.add_theme_color_override("font_outline_color", Color.BLACK);caption.add_theme_constant_override("outline_size", 4)
	var failures: Array = []; var views: Array = []
	for name in ["head_front", "head_side", "head_threequarter", "torso_front", "torso_back", "torso_threequarter"]:
		var face: bool = name.begins_with("head")
		var center: Vector3 = head.global_position + Vector3.DOWN * 0.025 if face else chest.global_position + Vector3.DOWN * 0.04
		var direction: Vector3 = p._get_forward_axis()
		if name.ends_with("side"): direction = p._get_forehand_axis()
		elif name.ends_with("back"): direction = - p._get_forward_axis()
		elif name.ends_with("threequarter"): direction = (p._get_forward_axis() + p._get_forehand_axis()).normalized()
		camera.size = 0.4 if face else 0.85;camera.global_position = center + direction * 3.0;camera.look_at(center, Vector3.UP)
		caption.text = label + "\n" + name + " | actual mesh, neutral inspection lighting"
		await process_frame
		if not check_only:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join(name + ".png"))
		if not expected.is_equal_approx(p.body_pivot.global_transform): failures.append("body owner changed during static capture")
		views.append(name)
	for file in sources:
		if sources[file] != FileAccess.get_sha256("res://scripts/" + file): failures.append("source drift: " + file)
	var f: = FileAccess.open(output.path_join("report.json"), FileAccess.WRITE);f.store_string(JSON.stringify({"label": label, "project": ProjectSettings.globalize_path("res://"), "views": views, "source_hashes": sources, "failures": failures}, "\t"));f.close()
	print("POSTPREVIEW ANATOMY CAPTURE views=", views.size(), " failures=", failures)
	game.queue_free(); await preload("res://scripts/tests/audio_teardown.gd").drain(self);quit(0 if failures.is_empty() else 1)
