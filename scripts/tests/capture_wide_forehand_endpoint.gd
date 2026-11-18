extends "res://scripts/tests/diagnose_receiving_face_candidate.gd"

const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const CAPTURE_OUT: = "/workspace/shared/pickleball-hands/wide-forehand-endpoint-candidate"
const CANDIDATES: = "/workspace/shared/pickleball-hands/palmar-pose10-protraction-selected.json"
const VALIDATED: = "/workspace/shared/pickleball-hands/palmar-pose10-actual.json"
const TITLE: = "Wide forehand endpoint candidate, motion not yet integrated"
var game
var overlay: CanvasLayer
var camera: Camera3D
var frames: Dictionary = {}

class LandmarkLines extends Node2D:
	var segments: Array = []
	func _draw() -> void :
		for item in segments:
			draw_line(item[0], item[1], item[2], 2.0, true)
			draw_circle(item[0], 5.0, Color.BLACK)
			draw_circle(item[0], 3.0, item[2])

func text_label(value: String, location: Vector2, color: Color, size: int = 21) -> void :
	var label: = Label.new()
	label.text = value
	label.position = location
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	overlay.add_child(label)

func add_overlay(label: String, p, annotated: bool, metrics: Dictionary) -> void :
	for node in overlay.get_children():
		overlay.remove_child(node)
		node.queue_free()
	text_label(TITLE, Vector2(18, 16), Color.WHITE, 24)
	text_label(label, Vector2(18, 51), Color(0.75, 0.96, 0.45), 24)
	text_label("Actual fitted body + production IK | same ball, head center and physical face plane", Vector2(18, 86), Color.WHITE, 19)
	text_label("Elbow below shoulder: %.0f mm | Wrist bend: %.1f deg" % [metrics.elbow_below_shoulder_m * 1000.0, metrics.channels.net_hand_forearm_bend_deg], Vector2(18, 860), Color.WHITE, 20)
	if not annotated: return
	var arm = p.right_arm_node
	var mount: Transform3D = arm.hand_mesh.global_transform
	var joints: Dictionary = arm.articulated_hand.joint_positions()
	var handle: MeshInstance3D = p.paddle_node.get_node("Handle")
	var points: Array = [arm.forearm_pivot.global_position, mount * joints.thumb_tip, 
		mount * arm.articulated_hand.palm_contact_point, 
		handle.to_global(Vector3(0, handle.mesh.get_aabb().end.y, 0))]
	var labels: Array[String] = ["Elbow", "Thumb tip", "Palm center", "Paddle throat"]
	var positions: Array[Vector2] = [Vector2(22, 170), Vector2(745, 175), Vector2(745, 245), Vector2(745, 315)]
	var colors: Array[Color] = [Color(1, 0.5, 0.85), Color(1, 0.7, 0.3), Color(0.4, 1, 0.8), Color(0.4, 0.9, 1)]
	var lines: = LandmarkLines.new()
	overlay.add_child(lines)
	for index in range(points.size()):
		var endpoint: = positions[index] + Vector2(-5 if index > 0 else 120, 14)
		lines.segments.append([camera.unproject_position(points[index]), endpoint, colors[index]])
		text_label(labels[index], positions[index], colors[index])

func capture_state(label: String, p, pose: PostureDefinition, row: Dictionary, context: Dictionary) -> void :
	var metrics: Dictionary = measured(p, pose)
	var body: Transform3D = p.body_pivot.global_transform
	var paddle: Transform3D = p.paddle_node.global_transform
	var hand: Transform3D = p.right_arm_node.hand_mesh.global_transform
	var elbow: Vector3 = p.right_arm_node.forearm_pivot.global_position
	for view in ["body", "hand", "hand_labeled"]:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 1.75 if view == "body" else 0.7
		var target: Vector3 = context.body_target if view == "body" else context.hand_target
		var offset: Vector3 = context.body_offset if view == "body" else context.hand_offset
		camera.global_position = target + offset
		camera.look_at(target, Vector3.UP)
		camera.force_update_transform()
		add_overlay(("BEFORE: current production" if label == "before" else "AFTER: selected endpoint candidate") + " | " + view, p, view == "hand_labeled", metrics)
		await process_frame
		await RenderingServer.frame_post_draw
		check(p.body_pivot.global_transform.is_equal_approx(body), label + " frozen body changed")
		check(p.paddle_node.global_transform.is_equal_approx(paddle), label + " frozen paddle changed")
		check(p.right_arm_node.hand_mesh.global_transform.is_equal_approx(hand), label + " frozen hand changed")
		check(p.right_arm_node.forearm_pivot.global_position.distance_to(elbow) < 1e-05, label + " frozen elbow changed")
		var image: Image = root.get_texture().get_image()
		image.convert(Image.FORMAT_RGB8)
		image.save_png(CAPTURE_OUT.path_join(label + "_" + view + ".png"))
		frames[label + "_" + view] = image
	metrics["label"] = label
	metrics["ball_surface_gap_m"] = P.distance_to_head_shape(paddle.affine_inverse() * v(row.ball_position)) - 0.0375
	metrics["paddle_head"] = vd(paddle * PaddleSize.HEAD_OFFSET)
	metrics["physical_face_normal"] = vd(paddle.basis.z)
	records.append(metrics)

func run() -> void :
	if DisplayServer.get_name() == "headless":
		push_error("This helper requires the real desktop renderer")
		quit(2)
		return
	create_timer(90).timeout.connect( func(): quit(2))
	DirAccess.make_dir_recursive_absolute(CAPTURE_OUT)
	root.size = Vector2i(1000, 900)
	root.content_scale_size = Vector2i(1000, 900)
	DisplayServer.window_set_size(Vector2i(1000, 900))
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	paused = false
	var candidate: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CANDIDATES))[1]
	var validated: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(VALIDATED)).records[1]
	var exported: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	var row: Dictionary = {}
	for item in exported.snapshots:
		if item.case == "pose_10": row = item
	assert ( not row.is_empty() and candidate.case == "pose_10")
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false):
		node.set_process(false)
		node.set_physics_process(false)
	for child in game.get_children():
		if child is CanvasLayer: child.visible = false
	game.player_right.body_pivot.visible = false
	game.ball.freeze = true
	game.ball.global_position = v(row.ball_position)
	game.ball.show()
	var p = game.player_left
	p.hitting.serving_visual_active = false
	p.hitting.charge_visual_active = false
	p.hitting.is_in_follow_through = false
	p.current_velocity = Vector3.ZERO
	p.posture.editor_preview_mode = true
	var pose: PostureDefinition = PostureLibrary.instance().get_def(10).duplicate(true)
	apply_fields(pose, row.review_pose_fields)
	apply_fields(pose, row.pose_fields)
	pose.set_meta("visual_wrist_lag_deg", float(row.visual_wrist_lag_deg))
	p.global_position = v(row.player_origin)
	p.posture.transition_pose_blend = pose
	p.posture.force_posture_update(pose)
	p.body_pivot.global_transform = tt(row.body_transform)
	p.paddle_node.global_transform = tt(row.paddle_transform)
	p.arm_ik.update_arm_ik(0.0, pose)
	var baseline: Dictionary = measured(p, pose)
	for key in ["shoulder", "elbow", "wrist"]:
		check(v(baseline[key]).distance_to(v(row[key])) < 0.0001, "baseline reconstruction " + key)
	check(bt(baseline.hand_basis).is_equal_approx(tt(row.hand_transform).basis), "baseline hand frame")
	var original: Transform3D = tt(row.paddle_transform)
	var head: Vector3 = original * PaddleSize.HEAD_OFFSET
	var face_side: Vector3 = original.basis.z * signf((v(row.ball_position) - head).dot(original.basis.z))
	var context: = {"body_target": v(row.shoulder).lerp(head, 0.33) + Vector3.DOWN * 0.2, 
		"hand_target": (v(row.wrist) + v(candidate.wrist)) * 0.5 + Vector3.RIGHT * 0.035, 
		"body_offset": face_side * 2.5 + p._get_forehand_axis() * 0.55 + Vector3.UP * 0.2, 
		"hand_offset": face_side * 1.2 + p._get_forehand_axis() * 0.15}
	camera = Camera3D.new()
	game.add_child(camera)
	camera.near = 0.01
	camera.make_current()
	overlay = CanvasLayer.new()
	overlay.layer = 100
	root.add_child(overlay)
	await capture_state("before", p, pose, row, context)
	pose.shoulder_protraction_m = float(candidate.shoulder_protraction_m)
	Body.apply(p, pose)
	p.body_pivot.global_transform = tt(row.body_transform)
	var paddle: = Transform3D(bt(candidate.paddle_basis), v(candidate.paddle_origin))
	var stance: = Basis(p._get_forehand_axis(), Vector3.UP, - p._get_forward_axis())
	O.set_canonical_basis(pose, stance.inverse() * paddle.basis)
	var offset: Vector3 = head - p.global_position
	pose.paddle_forehand_mul = offset.dot(p._get_forehand_axis())
	pose.paddle_y_offset = offset.y
	pose.paddle_forward_mul = offset.dot(p._get_forward_axis())
	pose.right_elbow_pole = canonical_pole(p, pose, v(candidate.elbow))
	p.paddle_node.global_transform = paddle
	p.arm_ik.update_arm_ik(0.0, pose)
	var actual: Dictionary = measured(p, pose)
	for key in ["shoulder", "elbow", "wrist"]:
		check(v(actual[key]).distance_to(v(validated[key])) < 0.0001, "selected candidate reconstruction " + key)
	check(actual.channels.within_animation_budget, "candidate wrist budget")
	check(actual.body_margin_m >= - 3e-05 and actual.paddle_limb_margin_m >= - 3e-05, "candidate geometry")
	check((paddle * PaddleSize.HEAD_OFFSET).distance_to(head) < 1e-05, "same head center")
	check(absf(paddle.basis.z.dot(original.basis.z)) > 0.99999, "same physical face plane")
	await capture_state("after", p, pose, row, context)
	for view in ["body", "hand", "hand_labeled"]:
		var pair: = Image.create(2000, 900, false, Image.FORMAT_RGB8)
		pair.blit_rect(frames["before_" + view], Rect2i(0, 0, 1000, 900), Vector2i.ZERO)
		pair.blit_rect(frames["after_" + view], Rect2i(0, 0, 1000, 900), Vector2i(1000, 0))
		pair.save_png(CAPTURE_OUT.path_join("comparison_" + view + ".png"))
	var report: = FileAccess.open(CAPTURE_OUT.path_join("replay-report.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"label": TITLE, "records": records, "errors": errors, 
		"candidate_path": CANDIDATES, "candidate_index": 1, "baseline_path": source_path, 
		"candidate_sha256": FileAccess.get_sha256(CANDIDATES), "baseline_sha256": FileAccess.get_sha256(source_path)}, "\t"))
	report.close()
	for error in errors: push_error(error)
	print("WIDE FOREHAND ENDPOINT CAPTURE: ", errors.size(), " errors -> ", CAPTURE_OUT)
	game.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
