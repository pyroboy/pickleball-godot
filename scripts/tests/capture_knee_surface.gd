extends SceneTree

const Knee = preload("res://scripts/player_leg_visual.gd")
const Before = preload("res://scripts/tests/fixtures/player_leg_visual_before_knee.gd")
const D = preload("res://scripts/player_body_dimensions.gd")
const Paddle = preload("res://scripts/paddle_dimensions.gd")
const Grip = preload("res://scripts/paddle_grip_frame.gd")
var output: = "/workspace/shared/pickleball-hands/postpreview-knees"
var check_only: = false
var failures: Array[String] = []
func _initialize() -> void : call_deferred("run")
func vd(p: Vector3) -> Array: return [p.x, p.y, p.z]
func tx(t: Transform3D) -> Array: return [vd(t.basis.x), vd(t.basis.y), vd(t.basis.z), vd(t.origin)]
func image_skin_pixels(picture: Image, point: Vector2, extent: int) -> Dictionary:
	var skin_pixels: = 0; var nonblack: = 0; var tested: = 0
	for y in range(maxi(90, int(point.y) - extent), mini(picture.get_height(), int(point.y) + extent), 3):
		for x in range(maxi(0, int(point.x) - extent), mini(picture.get_width(), int(point.x) + extent), 3):
			var color: Color = picture.get_pixel(x, y);tested += 1
			if maxf(color.r, maxf(color.g, color.b)) > 0.1: nonblack += 1
			if color.r > 0.12 and color.r > color.b * 1.15 and color.r > color.g * 0.98: skin_pixels += 1
	return {"sampled": tested, "nonblack": nonblack, "skin_colored": skin_pixels}
func neutral_pose() -> PostureDefinition:
	var pose: PostureDefinition = load("res://data/postures/20_ready.tres").duplicate(true)
	pose.body_yaw_deg = 0;pose.hip_yaw_deg = 0;pose.torso_yaw_deg = 0;pose.torso_pitch_deg = -28
	pose.body_pitch_deg = 0;pose.body_roll_deg = 0;pose.torso_roll_deg = 0;pose.spine_curve_deg = 0;pose.crouch_amount = 0
	pose.head_yaw_deg = 0;pose.head_pitch_deg = 0;pose.weight_shift = 0;pose.stance_width = 0.36;pose.shoulder_protraction_m = 0
	pose.front_foot_forward = 0;pose.back_foot_back = 0;pose.right_foot_yaw_deg = 0;pose.left_foot_yaw_deg = 0
	pose.paddle_forehand_mul = 0.25;pose.paddle_forward_mul = 0.05;pose.paddle_y_offset = - 0.48
	pose.paddle_pitch_base_deg = 0;pose.paddle_pitch_signed_deg = 0;pose.paddle_yaw_base_deg = 0;pose.paddle_yaw_signed_deg = 0;pose.paddle_roll_base_deg = 180;pose.paddle_roll_signed_deg = 0
	pose.left_hand_mode = 4;pose.left_hand_offset = Vector3( - 0.1, - 0.3, - 0.5)
	return pose
func run() -> void :
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	check_only = "--check-only" in OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" and not check_only: quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	var sources: Dictionary = {}
	for name in ["player_leg_visual.gd", "leg.gd", "player_athlete_visual.gd", "player_body_dimensions.gd", "player_shoe_visual.gd", "body_clearance.gd", "player_arm_visual.gd", "player_face_visual.gd", "body_surface_profile.gd"]:
		sources[name] = FileAccess.get_sha256("res://scripts/" + name)
	root.size = Vector2i(1050, 1100);root.content_scale_size = Vector2i(1050, 1100)
	if not check_only: DisplayServer.window_set_size(Vector2i(1050, 1100))
	var pause = root.get_node_or_null("PauseController")
	if pause:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
		pause.close()
	paused = false
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for i in range(5): await process_frame
	game.game_serve.cleanup();game.process_mode = Node.PROCESS_MODE_DISABLED
	var frozen: Array = [game];frozen.append_array(game.find_children("*", "", true, false))
	for node in frozen: node.set_process(false);node.set_physics_process(false)
	for tween in get_processed_tweens(): tween.kill()
	game.ball.visible = false;game.player_right.body_pivot.visible = false
	for child in game.get_children():
		if child is CanvasLayer: child.visible = false
	var camera: = Camera3D.new();camera.near = 0.01;camera.projection = Camera3D.PROJECTION_ORTHOGONAL;game.add_child(camera);camera.make_current()
	var fill: = DirectionalLight3D.new();fill.light_energy = 0.7;fill.rotation_degrees = Vector3(-25, 145, 0);game.add_child(fill)
	var layer: = CanvasLayer.new();root.add_child(layer); var caption: = Label.new();caption.position = Vector2(18, 18);caption.add_theme_font_size_override("font_size", 22);layer.add_child(caption)
	caption.add_theme_color_override("font_outline_color", Color.BLACK);caption.add_theme_constant_override("outline_size", 4)
	var p = game.player_left
	p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.posture.editor_preview_mode = false;p.current_velocity = Vector3.ZERO
	var records: Array = []
	for case_name in ["neutral", "planted_wide_bend"]:
		var pose: PostureDefinition = neutral_pose() if case_name == "neutral" else load("res://data/postures/18_low_wide_forehand.tres").duplicate(true)
		p.leg_ik.feet_initialized = false;p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose, false)
		var body_before_fit: Transform3D = p.body_pivot.global_transform
		var main = p.left_arm_node if pose.paddle_hand == 1 else p.right_arm_node
		var offset: Vector3 = pose.left_hand_offset if pose.paddle_hand == 1 else pose.right_hand_offset
		var anchor_before_fit: Vector3 = p.paddle_node.to_global(Paddle.MAIN_GRIP_OFFSET + offset)
		var grip_before_fit: float = main.hand_mesh.global_position.distance_to(anchor_before_fit)
		var socket_before_fit: float = (main.fore_mesh.global_transform * Vector3(0, main.forearm_length * 0.5, 0)).distance_to(main.hand_mesh.global_transform * main.articulated_hand.wrist_socket)
		p.leg_ik.update_leg_ik(0.0, pose)
		var body_after_fit: Transform3D = p.body_pivot.global_transform
		var grip_after_fit_before_arm: float = main.hand_mesh.global_position.distance_to(p.paddle_node.to_global(Paddle.MAIN_GRIP_OFFSET + offset))
		var socket_after_fit_before_arm: float = (main.fore_mesh.global_transform * Vector3(0, main.forearm_length * 0.5, 0)).distance_to(main.hand_mesh.global_transform * main.articulated_hand.wrist_socket)


		p.arm_ik.update_arm_ik(0.0, pose)
		var expected_anchor: Vector3 = p.paddle_node.to_global(Paddle.MAIN_GRIP_OFFSET + offset)
		var expected_basis: Basis = Grip.basis(p.paddle_node.global_basis, pose.paddle_hand == 1)
		var expected_wrist: Vector3 = expected_anchor + expected_basis * main.articulated_hand.wrist_socket
		var grip_error: float = main.hand_mesh.global_position.distance_to(expected_anchor)
		var wrist_error: float = (main.hand_mesh.global_transform * main.articulated_hand.wrist_socket).distance_to(expected_wrist)
		var fore_tip: Vector3 = main.fore_mesh.global_transform * Vector3(0, main.forearm_length * 0.5, 0)
		if grip_error > 1e-05 or wrist_error > 1e-05 or fore_tip.distance_to(expected_wrist) > 1e-05: failures.append("hand/paddle/wrist attachment mismatch")
		if not main.hand_mesh.global_basis.is_equal_approx(expected_basis): failures.append("hand grip basis mismatch")
		var fixed_nodes: Array = [p, p.body_pivot, p.paddle_node, main.hand_mesh, main.fore_mesh]
		var old_meshes: Array = []; var saved: Array = []; var metadata: Array = []; var metrics: Array = []
		var chosen_leg = p.right_leg_node; var largest_bend: = -1.0
		for leg in [p.right_leg_node, p.left_leg_node]:
			Knee.update_leg(leg)
			fixed_nodes.append_array([leg.thigh_pivot, leg.shin_pivot, leg.foot_pivot, leg.foot_mesh])
			metadata.append([leg, leg.get_meta(Knee.BRIDGE_META)]);metadata.append([leg.thigh_mesh, leg.thigh_mesh.get_meta(Knee.BRIDGE_META)])
			var hip: Vector3 = leg.thigh_pivot.global_position; var knee: Vector3 = leg.shin_pivot.global_position; var ankle: Vector3 = leg.foot_pivot.global_position
			var bend: float = rad_to_deg(acos(clampf((knee - hip).normalized().dot((ankle - knee).normalized()), -1, 1)))
			if bend > largest_bend: chosen_leg = leg;largest_bend = bend
			if absf(hip.distance_to(knee) - D.THIGH_LENGTH) > 1e-05 or absf(knee.distance_to(ankle) - D.SHIN_LENGTH) > 1e-05: failures.append("changed link length")
			metrics.append({"side": leg.name, "hip": vd(hip), "knee": vd(knee), "ankle": vd(ankle), "bend_deg": bend, "foot": tx(leg.foot_mesh.global_transform), "shoe_bounds": str(leg.foot_mesh.mesh.get_aabb())})
			for part in [0, 1]:
				var node: MeshInstance3D = leg.thigh_mesh if part == 0 else leg.shin_mesh
				saved.append([node, node.mesh, node.skin, node.skeleton])
				old_meshes.append(Before.mesh(leg.thigh_length, leg.shin_length, part == 0, Color("1650ae"), Color("dbb18b"), Color("e7edf4")))
		var fixed: Array = []
		for node in fixed_nodes: fixed.append([node, node.global_transform])
		var view_records: Array = []
		var names: Array = ["full_front", "full_side", "knee_side", "knee_front"]
		for view in names:
			var close: bool = view.begins_with("knee")
			var center: Vector3 = chosen_leg.shin_pivot.global_position if close else p.global_position + Vector3.UP * 0.025
			var direction: Vector3 = p._get_forward_axis()
			if view.ends_with("side"):
				direction = chosen_leg.thigh_mesh.global_basis.x.normalized() if close else p._get_forehand_axis()
				if direction.dot(p._get_forehand_axis()) < 0: direction = - direction


				if close: direction = Vector3(direction.x, 0, direction.z).normalized()
			camera.size = 0.72 if close else 2.1;camera.global_position = center + direction * (0.8 if close else 3.0) + (Vector3.UP * 0.06 if close else Vector3.ZERO);camera.look_at(center, Vector3.UP)
			var joint_screen: Vector2 = camera.unproject_position(chosen_leg.shin_pivot.global_position)
			if camera.is_position_behind(chosen_leg.shin_pivot.global_position) or not Rect2(Vector2(8, 90), Vector2(root.size) - Vector2(16, 98)).has_point(joint_screen): failures.append("expected knee projects outside review frame")
			for version in ["before", "after"]:
				for item in metadata:
					if version == "before": item[0].remove_meta(Knee.BRIDGE_META)
					else: item[0].set_meta(Knee.BRIDGE_META, item[1])
				for i in range(saved.size()):
					var item: Array = saved[i]; var node: MeshInstance3D = item[0]
					if version == "before": node.skin = null;node.skeleton = NodePath("");node.mesh = old_meshes[i]
					else: node.mesh = item[1];node.skin = item[2];node.skeleton = item[3]
				caption.text = "%s | %s | %s knee surface\nActual solved rig; identical fixed feet and joint transforms" % [case_name, view, version]
				await process_frame
				var pixels: Dictionary = {}
				if not check_only:
					await RenderingServer.frame_post_draw
					var picture: Image = root.get_texture().get_image()
					pixels = image_skin_pixels(picture, joint_screen, 85 if close else 24)
					if pixels.nonblack < 20 or pixels.skin_colored < 10: failures.append("expected knee model area is missing/black: " + case_name + "/" + view + "/" + version)
					picture.save_png(output.path_join("%s_%s_%s.png" % [case_name, view, version]))
				view_records.append({"view": view, "version": version, "knee_pixel": [joint_screen.x, joint_screen.y], "camera_position": vd(camera.global_position), "camera_distance_m": camera.global_position.distance_to(center), "pixels": pixels})
				for item in fixed:
					if not item[0].global_transform.is_equal_approx(item[1]): failures.append("fixed node moved during comparison: " + str(item[0].name))
		records.append({"case": case_name, "legs": metrics, "views": view_records, "chosen_knee": chosen_leg.name, "largest_bend_deg": largest_bend, "grip_anchor_error_m": grip_error, "wrist_error_m": wrist_error, "forearm_socket_error_m": fore_tip.distance_to(expected_wrist), "body_before_secondary_leg_fit": tx(body_before_fit), "body_after_secondary_leg_fit": tx(body_after_fit), "secondary_leg_fit_translation_m": vd(body_after_fit.origin - body_before_fit.origin), "grip_error_before_secondary_fit_m": grip_before_fit, "socket_error_before_secondary_fit_m": socket_before_fit, "grip_error_after_fit_before_arm_resolve_m": grip_after_fit_before_arm, "socket_error_after_fit_before_arm_resolve_m": socket_after_fit_before_arm})
	for name in sources:
		if sources[name] != FileAccess.get_sha256("res://scripts/" + name): failures.append("source drift: " + name)
	var file: = FileAccess.open(output.path_join("report.json"), FileAccess.WRITE);file.store_string(JSON.stringify({"records": records, "failures": failures, "source_hashes": sources, "note": "Static actual solved catalogue/neutral poses; comparison changes only visual leg meshes."}, "  "));file.close()
	print("KNEE CAPTURE records=", records.size(), " failures=", failures)
	game.queue_free(); await preload("res://scripts/tests/audio_teardown.gd").drain(self);quit(0 if failures.is_empty() else 1)
