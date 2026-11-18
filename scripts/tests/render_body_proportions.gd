extends SceneTree


const Body = preload("res://scripts/stroke_body_pose.gd")
var output: = "/workspace/shared/pickleball-hands/proportions-before"
var game
var views: Array[SubViewport] = []
var cameras: Array[Camera3D] = []
var labels: Array[Label] = []
func _initialize() -> void : call_deferred("run")
func v(p: Vector3) -> Array: return [p.x, p.y, p.z]
func bounds(mesh: MeshInstance3D) -> AABB:
	var box: AABB = mesh.mesh.get_aabb()
	var first: Vector3 = mesh.global_transform * box.position
	var result: = AABB(first, Vector3.ZERO)
	for x in [0, 1]:
		for y in [0, 1]:
			for z in [0, 1]:
				result = result.expand(mesh.global_transform * (box.position + box.size * Vector3(x, y, z)))
	return result
func measure(p, tag: String) -> Dictionary:
	var chest: Node3D = p.body_pivot.get_node("TorsoMesh")
	var head: MeshInstance3D = chest.get_node("HeadMesh")
	var hip: Vector3 = p.right_leg_node.thigh_pivot.global_position
	var shoulder: Vector3 = p.right_arm_node.upper_pivot.global_position
	var soles: float = minf(bounds(p.right_leg_node.foot_mesh).position.y, bounds(p.left_leg_node.foot_mesh).position.y)
	var crown: float = bounds(head).end.y
	var height: float = crown - soles
	var actual_thigh: float = hip.distance_to(p.right_leg_node.shin_pivot.global_position)
	var actual_shin: float = p.right_leg_node.shin_pivot.global_position.distance_to(p.right_leg_node.foot_pivot.global_position)
	return {"pose": tag, "sole_y": soles, "crown_y": crown, "visible_height_m": height, 
		"hip": v(hip), "shoulder": v(shoulder), "head_center": v(head.global_position), 
		"hip_height_m": hip.y - soles, "shoulder_height_m": shoulder.y - soles, 
		"hip_to_shoulder_vertical_m": shoulder.y - hip.y, 
		"thigh_length_m": p.right_leg_node.thigh_length, "shin_length_m": p.right_leg_node.shin_length, 
		"actual_thigh_m": actual_thigh, "actual_shin_m": actual_shin, 
		"maximum_link_scale": maxf(actual_thigh / p.right_leg_node.thigh_length, actual_shin / p.right_leg_node.shin_length), 
		"leg_links_to_height": (p.right_leg_node.thigh_length + p.right_leg_node.shin_length) / height, 
		"head_height_m": head.mesh.get_aabb().size.y, "head_width_m": head.mesh.get_aabb().size.x, 
		"query_shoulder_error_m": shoulder.distance_to(Body.shoulder_world(p, p.posture.transition_pose_blend)), 
		"knee": v(p.right_leg_node.shin_pivot.global_position), "ankle": v(p.right_leg_node.foot_pivot.global_position)}
func run() -> void :
	var pause = root.get_node_or_null("PauseController")
	if pause:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
		pause.close()
	paused = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 900)
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for settle_frame in range(5): await process_frame
	await physics_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.game_serve.cleanup()
	game.ball.visible = false


	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false):
		node.set_process(false);node.set_physics_process(false)
	var p = game.player_left
	game.player_right.body_pivot.visible = false
	for child in game.get_children():
		if child is CanvasLayer: child.visible = false
	for index in range(2):
		var view: = SubViewport.new();view.size = Vector2i(640, 900);view.world_3d = game.get_world_3d()
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS;root.add_child(view);views.append(view)
		var camera: = Camera3D.new();camera.projection = Camera3D.PROJECTION_ORTHOGONAL;camera.size = 1.95;camera.near = 0.01;camera.far = 30
		view.add_child(camera);camera.make_current();cameras.append(camera)
		var label: = Label.new();label.position = Vector2(18, 14);label.add_theme_font_size_override("font_size", 22);view.add_child(label);labels.append(label)
	var records: Array = []
	for tag in ["neutral", "ready"]:
		var pose: PostureDefinition = load("res://data/postures/20_ready.tres").duplicate(true)
		if tag == "neutral":
			if "shoulder_protraction_m" in pose: pose.set("shoulder_protraction_m", 0.0)
			pose.body_yaw_deg = 0;pose.hip_yaw_deg = 0;pose.torso_yaw_deg = 0;pose.torso_pitch_deg = -28
			pose.body_pitch_deg = 0;pose.body_roll_deg = 0;pose.torso_roll_deg = 0;pose.spine_curve_deg = 0;pose.crouch_amount = 0
			pose.head_yaw_deg = 0;pose.head_pitch_deg = 0;pose.weight_shift = 0;pose.stance_width = 0.36
			pose.front_foot_forward = 0;pose.back_foot_back = 0;pose.right_foot_yaw_deg = 0;pose.left_foot_yaw_deg = 0
			pose.paddle_forehand_mul = 0.25;pose.paddle_forward_mul = 0.05;pose.paddle_y_offset = - 0.48
			pose.paddle_pitch_base_deg = 0;pose.paddle_pitch_signed_deg = 0;pose.paddle_yaw_base_deg = 0;pose.paddle_yaw_signed_deg = 0;pose.paddle_roll_base_deg = 180;pose.paddle_roll_signed_deg = 0
			pose.left_hand_mode = 4;pose.left_hand_offset = Vector3( - 0.1, - 0.3, - 0.5)


		p.posture.editor_preview_mode = false;p.current_velocity = Vector3.ZERO;p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false
		p.leg_ik.feet_initialized = false;p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
		var expected_body: Transform3D = p.body_pivot.global_transform
		var expected_chest: Transform3D = p.body_pivot.get_node("TorsoMesh").global_transform
		var center: = Vector3(p.global_position.x, p.COURT_FLOOR_Y + 0.86, p.global_position.z)
		for index in range(2):
			cameras[index].global_position = center + (p._get_forward_axis() if index == 0 else p._get_forehand_axis()) * 3.0
			cameras[index].look_at(center);labels[index].text = "%s | %s" % [tag.capitalize(), "Front" if index == 0 else "Side"]
		await process_frame; await RenderingServer.frame_post_draw; await process_frame; await RenderingServer.frame_post_draw
		if not p.body_pivot.global_transform.is_equal_approx(expected_body) or not p.body_pivot.get_node("TorsoMesh").global_transform.is_equal_approx(expected_chest):
			push_error("Neutral fixture pose was overwritten after its final solve: " + tag)
			quit(3);return
		var image: = Image.create(1280, 900, false, Image.FORMAT_RGB8)
		for index in range(2):
			var frame: Image = views[index].get_texture().get_image();frame.convert(Image.FORMAT_RGB8)
			image.blit_rect(frame, Rect2i(Vector2i.ZERO, views[index].size), Vector2i(index * 640, 0))
		var measured: Dictionary = measure(p, tag)
		if float(measured.maximum_link_scale) > 1.001:
			push_error("Proportion fixture stretched a supported leg: " + tag)
			quit(4);return
		image.save_png(output.path_join(tag + ".png"));records.append(measured)
	var file: = FileAccess.open(output.path_join("measurements.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"project": ProjectSettings.globalize_path("res://"), "measurements": records}, "\t"));file.close()
	print("BODY PROPORTIONS CAPTURE ", output)
	game.queue_free(); await process_frame;quit()
