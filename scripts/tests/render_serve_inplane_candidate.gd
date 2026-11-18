extends SceneTree



const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Anatomy = preload("res://scripts/arm_anatomy.gd")
const PoseApplier = preload("res://scripts/posture_skeleton_applier.gd")
const Clearance = preload("res://scripts/body_clearance.gd")
const PaddleClearance = preload("res://scripts/paddle_clearance.gd")
const Styles = preload("res://scripts/serve_style.gd")
const OUT: = "/workspace/shared/pickleball-hands/serve-inplane-candidate"
const Orientation = preload("res://scripts/stroke_preparation_orientation.gd")
const FIT_PATH: = "/workspace/shared/pickleball-hands/serve-inplane-wide-feasibility.json"
var game
var overlay: CanvasLayer
var lines: MarkerLines
var records: Array = []
var _saved_processing: Array = []
var metrics_only: bool = false
var candidate_angle: float = -70.0
var fit_path: String = FIT_PATH
var selected_pole: String = "lowest_buffered_clear"
var output_path: String = OUT

class MarkerLines extends Node2D:
	var segments: Array = []
	func _draw() -> void :
		for item in segments:
			draw_line(item.point, item.label, item.color, float(item.get("width", 1.5)), true)
			draw_circle(item.point, 5.0, Color.BLACK)
			draw_circle(item.point, 3.5, item.color)

func _initialize() -> void :
	call_deferred("run")

func _v(p: Vector3) -> Array:
	return [p.x, p.y, p.z]

func _tx(value: Transform3D) -> Array:
	return [_v(value.basis.x), _v(value.basis.y), _v(value.basis.z), _v(value.origin)]

func _text(text: String, position: Vector2, color: Color, font_size: int = 20) -> void :
	var label: = Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	overlay.add_child(label)

func _annotations(camera: Camera3D, points: Dictionary, caption: String, chirality: float) -> void :
	for child in overlay.get_children():
		child.queue_free()
	lines = MarkerLines.new()
	overlay.add_child(lines)
	_text(caption + " | ACTUAL RIGHT ARM", Vector2(22, 18), Color.WHITE, 25)
	_text("Landmark-normal chirality: %+0.5f (right = positive)" % chirality, Vector2(22, 52), Color("bfead9"), 18)
	var colors: Array[Color] = [Color("ffffff"), Color("55e5ff"), Color("ff80e8"), Color("ffb35d"), Color("7cff7b"), Color("d8dff0"), Color("ffe56b"), Color("c8b3ff"), Color("ff5252"), Color("48f5ae"), Color("ffda90"), Color("9fd7ff")]
	var index: = 0
	for name in points:
		var point: Vector2 = camera.unproject_position(points[name])
		var right: = index % 2 == 1
		var label_at: = Vector2(710 if right else 22, 114 + int(index / 2) * 68)
		_text(str(name), label_at, colors[index], 20)
		lines.segments.append({"point": point, "label": label_at + Vector2(-6 if right else 170, 13), "color": colors[index]})
		index += 1
	var wrist_screen: = camera.unproject_position(points["Wrist socket"])
	lines.segments.append({"point": wrist_screen, "label": camera.unproject_position(points["Neutral thumb axis"]), "color": Color("ff5252"), "width": 3.0})
	lines.segments.append({"point": wrist_screen, "label": camera.unproject_position(points["Actual thumb axis"]), "color": Color("48f5ae"), "width": 3.0})
	lines.queue_redraw()
	_text("Cameras use landmark anatomical Z; throat +Y / butt -Y are the original paddle", Vector2(22, 758), Color.WHITE, 17)

func _geometry_end(instance: MeshInstance3D, axis: Vector3, maximum: bool, palm_only: bool) -> Vector3:
	var arrays: Array = instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if palm_only else Clearance.mesh_surface_triangles(instance)
	var bones: = PackedInt32Array()
	var weights: = PackedFloat32Array()
	if palm_only:
		vertices = instance.get_meta("articulated_hand").sampled_vertices()
		bones = arrays[Mesh.ARRAY_BONES]
		weights = arrays[Mesh.ARRAY_WEIGHTS]
	var candidates: Array[Vector3] = []
	var extremum: = - INF if maximum else INF
	for index in range(vertices.size()):
		if palm_only and (bones[index * 4] != 0 or weights[index * 4] < 0.999): continue
		var world: Vector3 = instance.global_transform * vertices[index]
		candidates.append(world)
		var distance: = world.dot(axis)
		extremum = maxf(extremum, distance) if maximum else minf(extremum, distance)
	var centre: = Vector3.ZERO
	var count: = 0
	for point in candidates:
		if absf(point.dot(axis) - extremum) < 1e-05:
			centre += point
			count += 1
	return centre / maxi(count, 1)



func _synchronize_render(player) -> void :
	for tween in get_processed_tweens(): tween.kill()
	game.reset_physics_interpolation()
	player.paddle_node.force_update_transform()
	for arm in [player.right_arm_node, player.left_arm_node]:
		arm.upper_mesh.force_update_transform()
		arm.fore_mesh.force_update_transform()
		arm.hand_mesh.force_update_transform()
		arm.articulated_hand.skeleton.force_update_transform()
	await physics_frame
	await process_frame
	await process_frame
	if not metrics_only: await RenderingServer.frame_post_draw



func _freeze() -> void :


	assert (_saved_processing.is_empty(), "Resume saved process flags before freezing again")
	var nodes: Array = [game]
	nodes.append_array(game.find_children("*", "", true, false))
	for node in nodes:
		_saved_processing.append([node, node.is_processing(), node.is_physics_processing(), node.process_mode])
		node.set_process(false)
		node.set_physics_process(false)
	game.process_mode = Node.PROCESS_MODE_DISABLED
	for tween in get_processed_tweens(): tween.kill()
	game.hud.set_gameplay_elements_visible(false)
	game.mobile_controls.hide()
	for child in game.get_children():
		if child is CanvasLayer: child.hide()

func _apply_contact_pose(player, pose: PostureDefinition) -> void :
	player.current_velocity = Vector3.ZERO
	player.hitting.serving_visual_active = false
	player.hitting.charge_visual_active = false
	player.hitting.is_in_follow_through = false
	player.posture._committed_incoming_posture = -1
	player.posture.editor_preview_mode = false
	player.leg_ik.feet_initialized = false
	player.posture.transition_pose_blend = pose
	player.posture.force_posture_update(pose)

func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _canonical_pole(player, pose: PostureDefinition, world_target: Vector3) -> Vector3:
	var arm = player.right_arm_node
	var fh: Vector3 = player._get_forehand_axis()
	var fw: Vector3 = player._get_forward_axis()
	var stance: = Basis(fh, Vector3.UP, - fw)
	var turn: Basis = stance * Basis.from_euler(pose.right_shoulder_rotation_deg * (PI / 180.0)) * stance.inverse()
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var raw_world: Vector3 = shoulder + turn.inverse() * (world_target - shoulder)
	var relative: Vector3 = raw_world - player.global_position
	return Vector3(relative.dot(fh), relative.y, relative.dot(fw))

func _measure(player, pose: PostureDefinition, baseline: Transform3D, ball: Vector3, desired_elbow: Vector3, canonical: Vector3, head_before: Transform3D) -> Dictionary:
	var arm = player.right_arm_node
	var model = arm.articulated_hand
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var elbow: Vector3 = arm.forearm_pivot.global_position
	var wrist: Vector3 = arm.hand_mesh.global_transform * model.wrist_socket
	var paddle: Transform3D = player.paddle_node.global_transform
	var head: Vector3 = paddle * PaddleSize.HEAD_OFFSET
	var body: Dictionary = Clearance.volumes(player, pose, player.body_pivot.global_transform)
	var upper_surface: Dictionary = Clearance.mesh_surface_margins(arm.upper_mesh, body, shoulder, elbow, 0.08)
	var fore_surface: Dictionary = Clearance.mesh_surface_margins(arm.fore_mesh, body)
	var channels: Dictionary = Anatomy.decompose(Anatomy.forearm_reference(shoulder, elbow, wrist, Vector3.UP, false), arm.hand_mesh.global_basis * model.anatomical_basis, model.radial_sign)
	var surface_ok: = true
	for region in Clearance.REGIONS: surface_ok = surface_ok and upper_surface[region] >= - 3e-05 and fore_surface[region] >= - 3e-05
	var gap: float = PaddleClearance.distance_to_paddle_shape(paddle.affine_inverse() * ball) - 0.0375
	var root_head = player.body_pivot.get_node("TorsoMesh/HeadMesh")
	var actual_head: Transform3D = root_head.global_transform
	assert (head.distance_to(baseline * PaddleSize.HEAD_OFFSET) < 1e-05, "Contact head center must stay fixed")
	assert (paddle.basis.z.distance_to(baseline.basis.z) < 1e-05, "Contact face normal must stay fixed")
	assert (absf(gap) < 1e-05, "Actual shared release-plan ball stays tangent")
	assert (actual_head.is_equal_approx(head_before), "Head and integrated pupils retain their baseline direction")
	return {"canonical_authored_pole": _v(canonical), "desired_elbow": _v(desired_elbow), "actual_elbow": _v(elbow), 
		"conditioner_elbow_shift_m": elbow.distance_to(desired_elbow), "shoulder": _v(shoulder), "wrist": _v(wrist), 
		"head_center": _v(head), "ball_center": _v(ball), "paddle": _tx(paddle), "head_transform": _tx(actual_head), 
		"hand_anatomical_basis": _tx(Transform3D(arm.hand_mesh.global_basis * model.anatomical_basis, Vector3.ZERO)), 
		"head_center_delta_m": head.distance_to(baseline * PaddleSize.HEAD_OFFSET), "face_normal_delta": paddle.basis.z.distance_to(baseline.basis.z), 
		"ball_surface_gap_m": gap, "upper_link_error_m": absf(shoulder.distance_to(elbow) - 0.35), 
		"forearm_link_error_m": absf(elbow.distance_to(wrist) - 0.35), "socket_error_m": wrist.distance_to(arm.anatomical_wrist_world), 
		"elbow_height_from_shoulder_m": elbow.y - shoulder.y, "shaft_headward_world_y": paddle.basis.y.y, "wrist_above_ball_m": wrist.y - ball.y, 
		"anatomical_channels": channels, "upper_surface": upper_surface, "forearm_surface": fore_surface, 
		"body_clear": surface_ok, "wrist_pass": channels.within_animation_budget, 
		"valid": surface_ok and channels.within_animation_budget, "production_conditioner_unchanged": true}

func _plain_overlay(caption: String, isolated: bool = false) -> void :
	for child in overlay.get_children(): child.queue_free()
	_text(caption, Vector2(20, 18), Color.WHITE, 22)
	_text("Diagnostic isolation: torso/head hidden; original hand/arm/paddle geometry" if isolated else "Actual full rig; test-only %.0fdeg shaft tilt; original head/face contact and135deg grip" % candidate_angle, Vector2(20, 764), Color.WHITE, 16)

func _render_views(label: String, player, record: Dictionary) -> void :
	if metrics_only: return
	var arm = player.right_arm_node
	var model = arm.articulated_hand
	var mount: Transform3D = arm.hand_mesh.global_transform
	var paddle: Transform3D = player.paddle_node.global_transform
	var head_node = player.body_pivot.get_node("TorsoMesh/HeadMesh")
	var head_transform: Transform3D = head_node.global_transform
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var elbow: Vector3 = arm.forearm_pivot.global_position
	var wrist: Vector3 = mount * model.wrist_socket
	var dorsal: Vector3 = mount.basis * model.anatomical_basis.z
	var shaft: Vector3 = paddle.basis.y
	var fh: Vector3 = player._get_forehand_axis()
	var fw: Vector3 = player._get_forward_axis()
	var camera: Camera3D = game.main_camera
	var points: = {"Wrist socket": wrist, "Index MCP": mount * model.joint_positions().index_mcp, 
		"Elbow": elbow, "Paddle throat": paddle * Vector3(0, 0.25, 0), 
		"Shoulder": shoulder, "Paddle butt": paddle.origin, 
		"Neutral thumb axis": wrist + Anatomy.forearm_reference(shoulder, elbow, wrist, Vector3.UP, false).y * 0.12, 
		"Actual thumb axis": wrist + mount.basis * model.anatomical_basis.y * 0.12}
	var chirality: float = model.anatomical_basis.x.cross(model.anatomical_basis.y).dot(model.anatomical_basis.z)
	for view in ["full_body_plain", "hand_arm_plain", "anatomy_labeled", "isolated_dorsal_plain"]:
		var focus: Vector3 = player.global_position + Vector3.UP * 0.12
		var offset: Vector3 = (fh * 0.7 + fw * 0.65 + Vector3.UP * 0.1).normalized() * 2.7
		var up: = Vector3.UP
		if view == "hand_arm_plain" or view == "anatomy_labeled":
			focus = shoulder.lerp(wrist, 0.55)
			offset = (fh * 0.8 + fw * 0.4 + Vector3.UP * 0.12).normalized() * 1.15
		if view == "isolated_dorsal_plain":
			focus = mount.origin.lerp(elbow, 0.18) + shaft * 0.06
			offset = dorsal * 0.62
			up = shaft
		camera.global_position = focus + offset
		camera.look_at(focus, up)
		var hidden: Array = []
		if view == "isolated_dorsal_plain":


			for mesh in player.find_children("*", "MeshInstance3D", true, false):
				if mesh == arm.upper_mesh or mesh == arm.fore_mesh or mesh == arm.hand_mesh or player.paddle_node.is_ancestor_of(mesh): continue


				hidden.append([mesh, mesh.layers]);mesh.layers = 0
		if view == "anatomy_labeled": _annotations(camera, points, label + " / unchanged conditioner", chirality)
		else: _plain_overlay(label + " / " + view, view == "isolated_dorsal_plain")
		await process_frame
		await RenderingServer.frame_post_draw
		assert (arm.hand_mesh.global_transform.is_equal_approx(mount), "Camera changes never remount the hand")
		assert (player.paddle_node.global_transform.is_equal_approx(paddle), "Camera changes never move the paddle")
		assert (head_node.global_transform.is_equal_approx(head_transform), "Gaze direction cannot follow the review camera")
		root.get_texture().get_image().save_png(output_path.path_join(label + "_" + view + ".png"))
		for item in hidden: item[0].layers = item[1]

func run() -> void :
	metrics_only = DisplayServer.get_name() == "headless" or "--metrics-only" in OS.get_cmdline_user_args()
	var pole_override: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--raw-poles="): pole_override = JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--raw-poles=")))
		if arg.begins_with("--fit="): fit_path = arg.trim_prefix("--fit=")
		if arg.begins_with("--angle="): candidate_angle = float(arg.trim_prefix("--angle="))
		if arg.begins_with("--selection="): selected_pole = arg.trim_prefix("--selection=")
		if arg.begins_with("--output="): output_path = arg.trim_prefix("--output=")
	create_timer(120).timeout.connect( func(): quit(2))
	DirAccess.make_dir_recursive_absolute(output_path)
	if not metrics_only: DisplayServer.window_set_size(Vector2i(960, 800))
	root.size = Vector2i(960, 800);root.content_scale_size = Vector2i(960, 800);root.content_scale_factor = 1.0
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	root.get_node("Settings")._config.set_value("video", "shadow_quality", 0)
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.serving_team = 0;game._reset_ball()
	await physics_frame; await process_frame
	_freeze();game.game_serve.cleanup();game.ball.freeze = true
	game.main_camera.projection = Camera3D.PROJECTION_PERSPECTIVE;game.main_camera.fov = 48.0;game.main_camera.near = 0.012
	overlay = CanvasLayer.new();overlay.layer = 100;root.add_child(overlay)
	var input: Array = JSON.parse_string(FileAccess.get_file_as_string(fit_path))
	var player = game.player_left
	for style in [Styles.Style.FLAT, Styles.Style.DROP_DRIVE]:
		var label: String = "flat" if style == Styles.Style.FLAT else "drop_drive"
		var fit: Dictionary = {}
		for row in input:
			if is_equal_approx(float(row.inplane_angle_deg), candidate_angle) and ((style == 0 and "flat" in row.pose) or (style == 4 and "drop_drive" in row.pose)): fit = row;break
		assert ( not fit.is_empty(), "Validated numerical contact candidate must exist")
		assert (fit.has(selected_pole), "Requested validated pole selection must exist")
		var plan: Dictionary = Styles.release_plan(player.global_position, false, style)
		var ball: Vector3 = plan.contact_position
		var relative: Vector3 = ball - player.global_position
		var fh: Vector3 = player._get_forehand_axis(); var fw: Vector3 = player._get_forward_axis()
		var local_contact: = Vector3(relative.dot(fh), relative.y, relative.dot(fw))
		var source: PostureDefinition = Motion.serve_style_contact(style, local_contact)
		_apply_contact_pose(player, source)
		var baseline: Transform3D = player.paddle_node.global_transform
		var head_before: Transform3D = player.body_pivot.get_node("TorsoMesh/HeadMesh").global_transform
		var candidate: PostureDefinition = source.duplicate(true)
		var new_basis: Basis = baseline.basis * Basis(Vector3.BACK, deg_to_rad(candidate_angle))
		var stance: = Basis(fh, Vector3.UP, - fw)
		Orientation.set_canonical_basis(candidate, stance.inverse() * new_basis)
		var head: Vector3 = baseline * PaddleSize.HEAD_OFFSET - player.global_position
		candidate.paddle_forehand_mul = head.dot(fh);candidate.paddle_y_offset = head.y;candidate.paddle_forward_mul = head.dot(fw)


		var reference_origin: = Vector3(1.5, 1.0, 6.8)
		var reference_elbow: Vector3 = _vector(fit[selected_pole].elbow) - reference_origin
		var desired_elbow: Vector3 = player.global_position + fh * reference_elbow.x + Vector3.UP * reference_elbow.y - fw * reference_elbow.z
		var canonical: Vector3 = _canonical_pole(player, candidate, desired_elbow)
		if pole_override.has(label): canonical = _vector(pole_override[label])
		candidate.right_elbow_pole = canonical
		_apply_contact_pose(player, candidate)
		game.ball.global_position = ball;game.ball.show()
		await _synchronize_render(player)
		var record: Dictionary = _measure(player, candidate, baseline, ball, desired_elbow, canonical, head_before)
		record["style"] = label;record["inplane_angle_deg"] = candidate_angle;record["raw_pole_override"] = pole_override.has(label)
		records.append(record)
		print("SERVE CONTACT CANDIDATE ", label, " valid=", record.valid, " conditioner_shift=", record.conditioner_elbow_shift_m, " channels=", record.anatomical_channels)
		await _render_views(label, player, record)
	var file: = FileAccess.open(output_path.path_join("results.json"), FileAccess.WRITE);file.store_string(JSON.stringify(records, "\t"));file.close()
	print("SERVE CONTACT CANDIDATE: unchanged production conditioner,2 contacts -> ", output_path)
	quit()
