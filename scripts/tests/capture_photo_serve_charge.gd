extends "res://scripts/tests/author_photo_serve_charge.gd"

const OUT: = "/workspace/shared/pickleball-hands/photo-serve-charge-comparison"
const TITLE: = "Charged serve pose candidate, full motion not integrated"
var captures: Dictionary = {}
var errors: Array[String] = []
var source_paths: Array[String] = ["res://scripts/tests/author_photo_serve_charge.gd", "res://scripts/tests/author_serve_neutral_endpoints.gd", "res://scripts/serve_pose_presentation.gd", "res://scripts/articulated_hand.gd", "res://scripts/player_arm_visual.gd", "res://scripts/tests/capture_photo_serve_charge.gd"]

func hashes() -> Dictionary:
	var result: = {}
	for path in source_paths: result[path] = FileAccess.get_sha256(path)
	return result

func capture_pose(game, p, camera: Camera3D, caption: Label, label: String) -> void :
	var body: Transform3D = p.body_pivot.global_transform
	var paddle: Transform3D = p.paddle_node.global_transform
	var main: Transform3D = p.right_arm_node.hand_mesh.global_transform
	var support: Transform3D = p.left_arm_node.hand_mesh.global_transform
	var focus: Vector3 = p.global_position + Vector3.UP * 0.03
	for view in ["front", "hitting_side"]:
		var offset: Vector3 = p._get_forward_axis() * 3.0 if view == "front" else p._get_forehand_axis() * 3.0
		camera.global_position = focus + offset + Vector3.UP * 0.08
		camera.look_at(focus, Vector3.UP)
		caption.text = TITLE + "\n" + ("BEFORE: current production at full charge" if label == "before" else "AFTER: validated standalone charged pose") + "\nFixed 135-degree grip; actual rig and held ball | " + view
		await process_frame
		await RenderingServer.frame_post_draw
		if not p.body_pivot.global_transform.is_equal_approx(body): errors.append(label + " body moved")
		if not p.paddle_node.global_transform.is_equal_approx(paddle): errors.append(label + " paddle moved")
		if not p.right_arm_node.hand_mesh.global_transform.is_equal_approx(main) or not p.left_arm_node.hand_mesh.global_transform.is_equal_approx(support): errors.append(label + " hand moved")
		var frame: Image = root.get_texture().get_image()
		frame.convert(Image.FORMAT_RGB8)
		frame.save_png(OUT.path_join(label + "_" + view + ".png"))
		captures[label + "_" + view] = frame

func run() -> void :
	if DisplayServer.get_name() == "headless": quit(2);return
	create_timer(90).timeout.connect( func(): quit(2))
	var before_hashes: = hashes()
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(1000, 1000)
	root.content_scale_size = Vector2i(1000, 1000)
	DisplayServer.window_set_size(Vector2i(1000, 1000))
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	paused = false
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	for frame in range(5): await process_frame
	game._reset_match()
	game.game_serve.select_serve_style(0)
	game.game_serve.start_charge()
	game.game_serve.tick_charge(PickleballConstants.MAX_SERVE_CHARGE_TIME)
	await physics_frame
	await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false):
		node.set_process(false)
		node.set_physics_process(false)
	for child in game.get_children():
		if child is CanvasLayer: child.visible = false
	game.player_right.body_pivot.visible = false
	var p = game.player_left
	game.ball.is_in_play = false
	game.ball.freeze = true
	game.ball.global_position = game.game_serve.get_held_ball_position()
	game.ball.show()
	var camera: = Camera3D.new()
	game.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.near = 0.01
	camera.make_current()
	var overlay: = CanvasLayer.new()
	root.add_child(overlay)
	var caption: = Label.new()
	caption.position = Vector2(20, 18)
	caption.add_theme_font_size_override("font_size", 23)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 4)
	overlay.add_child(caption)
	await capture_pose(game, p, camera, caption, "before")
	game.game_serve.cleanup()
	p.posture.editor_preview_mode = false
	p.hitting.serving_visual_active = true
	p.hitting.charge_visual_active = false
	p.hitting.is_in_follow_through = false
	p.current_velocity = Vector3.ZERO
	p.posture._committed_incoming_posture = -1
	game.serving_team = 0
	game.game_state = game.GameState.WAITING
	surface = Paddle.sample_head_surface()
	sample(p, CONFIG, 0, 1.0, 0.0)
	game.ball.global_position = game.game_serve.get_held_ball_position()
	await capture_pose(game, p, camera, caption, "after")
	for view in ["front", "hitting_side"]:
		var pair: = Image.create(2000, 1000, false, Image.FORMAT_RGB8)
		pair.blit_rect(captures["before_" + view], Rect2i(0, 0, 1000, 1000), Vector2i.ZERO)
		pair.blit_rect(captures["after_" + view], Rect2i(0, 0, 1000, 1000), Vector2i(1000, 0))
		pair.save_png(OUT.path_join("comparison_" + view + ".png"))
	var after_hashes: = hashes()
	if before_hashes != after_hashes: errors.append("source changed during capture")
	var report: = FileAccess.open(OUT.path_join("replay-report.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"label": TITLE, "errors": errors, "candidate_records": rows, 
		"source_hashes_before": before_hashes, "source_hashes_after": after_hashes, 
		"validated_metrics_path": "/workspace/shared/pickleball-hands/photo-serve-charge-candidate.json"}, "\t"))
	report.close()
	for error in errors: push_error(error)
	print("PHOTO CHARGE COMPARISON: ", errors.size(), " errors -> ", OUT)
	game.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
