extends SceneTree



var output: = "/tmp/player-shoes"
var game
var camera: Camera3D
var captures: Array[Dictionary] = []

func _initialize() -> void : call_deferred("run")

func run() -> void :
	if DisplayServer.get_name() == "headless":
		push_error("Shoe capture requires a rendered display")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size = Vector2i(960, 720)
	root.size = Vector2i(960, 720)
	var pause = root.get_node_or_null("PauseController")
	if pause:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	paused = false
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.game_serve.cleanup()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	for node in game.find_children("*", "Node", true, false):
		node.set_process(false);node.set_physics_process(false)
	for tween in get_processed_tweens(): tween.kill()
	game.ball.hide()
	game._set_debug_visuals_visible(false)
	game._set_debug_zones_visible(false)
	for child in game.get_children():
		if child is CanvasLayer: child.hide()
	var effects = root.get_node_or_null("FXPool")
	if effects: effects.hide()
	for player in [game.player_left, game.player_right]:
		player.hitting.clear_charge_visual()
		player.hitting.is_in_follow_through = false
		player.posture.transition_pose_blend = null
		if player.posture.posture_ghost_root: player.posture.posture_ghost_root.hide()
		player.debug_visual.set_debug_visible(false)
		player.debug_visual.set_intent_indicators_visible(false)
		player.hide()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.005
	game.add_child(camera)
	camera.make_current()
	for player in [game.player_left, game.player_right]:
		player.show()
		_place_pose(player, false)
		var foot: MeshInstance3D = player.right_leg_node.foot_mesh
		var target: Vector3 = foot.global_position + Vector3.UP * 0.045
		var forward: Vector3 = - foot.global_basis.z
		var right: Vector3 = foot.global_basis.x
		await _capture(player, "neutral_toe", target, target + forward * 0.34 + right * 0.22 + Vector3.UP * 0.17, 0.31)
		await _capture(player, "neutral_heel", target, target - forward * 0.3 + right * 0.2 + Vector3.UP * 0.14, 0.31)
		_place_pose(player, true)
		var other: MeshInstance3D = player.left_leg_node.foot_mesh
		var pair_target: Vector3 = (foot.global_position + other.global_position) * 0.5 + Vector3.UP * 0.15
		await _capture(player, "wide_lunge", pair_target, pair_target + player._get_forward_axis() * 0.9 + player._get_forehand_axis() * 0.22 + Vector3.UP * 0.42, 1.05)
		target = foot.global_position + Vector3.UP * 0.045
		forward = - foot.global_basis.z
		right = foot.global_basis.x
		await _capture(player, "wide_lunge_toe", target, target + forward * 0.33 + right * 0.22 + Vector3.UP * 0.16, 0.31)
		player.hide()
	var file: = FileAccess.open(output.path_join("captures.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(captures, "\t"))
	print("SHOE CAPTURES ", output, " count=", captures.size())
	game.queue_free()
	await process_frame
	quit()

func _place_pose(player, wide: bool) -> void :
	var ready: PostureDefinition = PostureLibrary.instance().get_def(20)
	var pose: PostureDefinition = ready.lerp_with(ready, 0.0)
	player.global_position = Vector3(0, player.ground_y, 3.5 if player.player_num == 0 else -3.5)
	player.is_jumping = false
	player.current_velocity = Vector3.ZERO
	if wide:
		pose.stance_width = 0.84
		pose.front_foot_forward = 0.2
		pose.back_foot_back = - 0.16
		pose.crouch_amount = maxf(pose.crouch_amount, 0.18)
		pose.weight_shift = 0.24
		pose.right_foot_yaw_deg = -16
		pose.left_foot_yaw_deg = 8
	player.posture.force_posture_update(pose, false)
	var base: = Vector3(player.global_position.x, player.leg_ik.ANKLE_HEIGHT, player.global_position.z)
	player.leg_ik._reset_feet(player.leg_ik._stance_targets(pose, base))
	player.leg_ik._last_body_position = base
	player.leg_ik._solve_legs(1.0, pose)
	player.arm_ik.update_arm_ik(0.0, pose)

func _capture(player, label: String, target: Vector3, position: Vector3, size: float) -> void :
	camera.size = size
	camera.global_position = position
	camera.look_at(target, Vector3.UP)
	var expected: Transform3D = player.right_leg_node.foot_mesh.global_transform
	await process_frame
	await RenderingServer.frame_post_draw
	assert (player.right_leg_node.foot_mesh.global_transform.is_equal_approx(expected), "Shoe fixture pose must remain frozen")
	var path: = output.path_join("player%d_%s.png" % [player.player_num, label])
	root.get_texture().get_image().save_png(path)
	var foot: MeshInstance3D = player.right_leg_node.foot_mesh
	var head: MeshInstance3D = player.body_pivot.get_node("TorsoMesh/HeadMesh")
	var bounds: = foot.mesh.get_aabb()
	var sole_y: = INF
	for corner in range(8): sole_y = minf(sole_y, (foot.global_transform * bounds.get_endpoint(corner)).y)
	var head_indices: PackedInt32Array = head.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var shoe_indices: PackedInt32Array = foot.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	captures.append({"file": path, "player": player.player_num, "pose": label, 
		"head_triangles": head_indices.size() / 3, "shoe_triangles": shoe_indices.size() / 3, 
		"head_surfaces": head.mesh.get_surface_count(), "shoe_surfaces": foot.mesh.get_surface_count(), 
		"shoe_bounds": bounds, "sole_y": sole_y, "court_floor_y": PickleballConstants.FLOOR_Y})
	print("SHOE CAPTURE ", path, " head_triangles=", head_indices.size() / 3, 
		" shoe_triangles=", shoe_indices.size() / 3, " sole_y=", sole_y)
