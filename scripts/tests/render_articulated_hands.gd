extends SceneTree


const OUT: = "/workspace/shared/pickleball-hands/screens"
var game
func _initialize() -> void : call_deferred("run")
func capture(label: String, arm) -> void :
	var pivot: Transform3D = arm.hand_mesh.global_transform
	var socket: Vector3 = pivot * arm.articulated_hand.wrist_socket
	var target: Vector3 = pivot.origin.lerp(socket, 0.3)
	for angle in range(3):
		var offsets: Array[Vector3] = [pivot.basis.z * 0.4 + pivot.basis.y * 0.1, - pivot.basis.z * 0.42 + pivot.basis.x * 0.05, (pivot.basis.z + pivot.basis.x * 0.6).normalized() * 0.45]
		game.main_camera.global_position = target + offsets[angle]
		game.main_camera.look_at(target, Vector3.UP if absf(offsets[angle].normalized().dot(Vector3.UP)) < 0.9 else Vector3.FORWARD)
		await process_frame; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT.path_join(label + "_%d.png" % angle))
func run() -> void :
	create_timer(60).timeout.connect( func(): quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(640, 640);root.content_scale_size = Vector2i(640, 640)
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	root.get_node("Settings")._config.set_value("video", "shadow_quality", 0)
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	await physics_frame; await process_frame
	game.input_handler.set_process(false)
	game.game_serve.start_charge();game.game_serve.tick_charge(0.6)
	await physics_frame; await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	for node in game.find_children("*", "Node", true, false):
		node.set_process(false);node.set_physics_process(false)
	for tween in get_processed_tweens(): tween.kill()
	game.hud.set_gameplay_elements_visible(false);game.mobile_controls.hide()
	for child in game.get_children():
		if child is CanvasLayer: child.hide()
	game.main_camera.projection = Camera3D.PROJECTION_PERSPECTIVE;game.main_camera.fov = 46;game.main_camera.near = 0.015
	await capture("serve_main", game.player_left.right_arm_node)
	await capture("serve_cup", game.player_left.left_arm_node)
	var p = game.player_left
	game.game_serve.cleanup();p.hitting.serving_visual_active = false
	p.posture.editor_preview_mode = true
	p.posture.transition_pose_blend = PostureLibrary.instance().get_def(20)
	p.posture.force_posture_update(p.posture.transition_pose_blend)
	await capture("ready_main", p.right_arm_node)
	await capture("ready_support", p.left_arm_node)
	print("HAND STATIC CAPTURES DONE")
	quit()
