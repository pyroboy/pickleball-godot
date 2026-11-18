extends SceneTree

var game
func _initialize() -> void : call_deferred("run")
func run() -> void :
	var output: = "/workspace/shared/pickleball-hands/head-current"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(720, 720);root.content_scale_size = Vector2i(720, 720)
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for i in range(6): await process_frame
	await physics_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	for node in game.find_children("*", "Node", true, false):
		node.set_process(false);node.set_physics_process(false)
	for tween in get_processed_tweens(): tween.kill()
	for child in game.get_children():
		if child is CanvasLayer: child.hide()
	game.main_camera.projection = Camera3D.PROJECTION_ORTHOGONAL;game.main_camera.size = 0.43;game.main_camera.near = 0.01
	for player in [game.player_left, game.player_right]:
		var head: MeshInstance3D = player.body_pivot.get_node("TorsoMesh/HeadMesh")
		head.rotation = Vector3.ZERO
		var front: Vector3 = head.global_basis * player._get_forward_axis()
		var right: Vector3 = head.global_basis * player._get_forehand_axis()
		for angle in range(3):
			var direction: Vector3 = [front, right, (front + right * 0.65).normalized()][angle]
			game.main_camera.global_position = head.global_position + direction * 0.75
			game.main_camera.look_at(head.global_position, head.global_basis.y)
			await process_frame; await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("player%d_%s.png" % [player.player_num, ["front", "side", "threequarter"][angle]]))
	print("CURRENT HEAD CAPTURE ", output)
	quit()
