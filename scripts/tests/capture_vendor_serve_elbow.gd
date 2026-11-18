extends SceneTree


const D = preload("res://scripts/paddle_dimensions.gd")
const OldArm = preload("res://scripts/tests/fixtures/player_arm_visual_before_bridge.gd")
const Arm = preload("res://scripts/player_arm_visual.gd")
const Drain = preload("res://scripts/tests/audio_teardown.gd")
var game
var camera: Camera3D
var caption: Label
var output: = "/workspace/shared/pickleball-hands/vendor-elbow-motion"
var contacts: = 0
var serve_events: Array = []
var active_style: = 0
var capture_marks: Dictionary = {}
var records: Array = []
var snapshots: Array = []
var failures: Array = []
var check_only: = false
func _initialize() -> void : call_deferred("run")
func hashes(folder: String = "res://") -> Dictionary:
	var result: Dictionary = {}
	for file in DirAccess.get_files_at(folder):
		if file.get_extension() in ["gd", "tres", "tscn", "gdshader", "godot"]:
			var path: String = folder.path_join(file);result[path] = FileAccess.get_sha256(path)
	for directory in DirAccess.get_directories_at(folder):
		if not directory.begins_with("."): result.merge(hashes(folder.path_join(directory)))
	return result
func vd(v: Vector3) -> Array: return [v.x, v.y, v.z]
func snapshot(player, label: String, style: int) -> Dictionary:
	var nodes: Array = []; var bones: Array = []
	var candidates: Array = [player];candidates.append_array(player.find_children("*", "Node3D", true, false))
	for node in candidates:
		nodes.append([node, node.transform])
		if node is Skeleton3D:
			var poses: Array = []
			for index in node.get_bone_count(): poses.append(node.get_bone_pose(index))
			bones.append([node, poses])
	return {"label": label, "style": style, "nodes": nodes, "bones": bones, "ball": game.ball.global_position, 
		"paddle": player.paddle_node.global_transform, "elbow": player.right_arm_node.forearm_pivot.global_position, 
		"wrist": player.right_arm_node.anatomical_wrist_world}
func replay(row: Dictionary) -> void :
	for item in row.nodes: item[0].transform = item[1]
	for item in row.bones:
		for index in item[1].size(): item[0].set_bone_pose(index, item[1][index])
	game.ball.global_position = row.ball
	for arm in [game.player_left.right_arm_node, game.player_left.left_arm_node]: Arm.update_arm(arm)
func set_motion_camera(p) -> void :
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE;camera.fov = 43
	var focus: Vector3 = p.global_position + Vector3.UP * 0.02
	camera.global_position = focus + p._get_forward_axis() * 2.65 + p._get_forehand_axis() * 1.25 + Vector3.UP * 0.15
	camera.look_at(focus, Vector3.UP)
func run() -> void :
	check_only = "--check-only" in OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" and not check_only: quit(2);return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	var before: Dictionary = hashes()
	root.size = Vector2i(1100, 1000);root.content_scale_size = Vector2i(1100, 1000)
	if not check_only: DisplayServer.window_set_size(Vector2i(1100, 1000))
	var pause = root.get_node_or_null("PauseController")
	if pause:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
		pause.close()
	paused = false
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(12): await process_frame
	game.reaction_button.auto_fire_on_perfect = false


	game.pvp_mode = true;game.aim_focus._sync_realtime_mode()
	game.game_serve.serve_launched.connect( func(team):
		contacts += 1
		serve_events.append({"requested_style": active_style, "team": team, "flight": game.ball.flight_id, "physics_tick": Engine.get_physics_frames(), "frame_phase": game.game_serve.get_serve_timing_state().phase})
		if int(team) == 0 and not capture_marks.has("contact"):
			snapshots.append(snapshot(game.player_left, "contact", active_style));capture_marks["contact"] = true)
	camera = Camera3D.new();game.add_child(camera);camera.near = 0.01;camera.make_current()
	for child in game.get_children():
		if child is CanvasLayer: child.visible = false
	var layer: = CanvasLayer.new();root.add_child(layer)
	caption = Label.new();caption.position = Vector2(18, 18);caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_outline_color", Color.BLACK);caption.add_theme_constant_override("outline_size", 4);layer.add_child(caption)
	for style in [0, 4]:
		game._reset_match();game.game_serve.select_serve_style(style);contacts = 0;active_style = style;capture_marks = {}
		for frame in range(12): await process_frame
		var p = game.player_left;game.player_right.set_ai_movement_enabled(false);set_motion_camera(p)
		var name: String = "flat" if style == 0 else "drop_drive"
		var folder: String = output.path_join(name);DirAccess.make_dir_recursive_absolute(folder)
		var captured: Dictionary = capture_marks; var saved: = 0
		for frame in range(216):
			if frame == 18: Input.action_press("ui_accept")
			if frame == 48: Input.action_release("ui_accept")
			await process_frame
			var state: Dictionary = game.game_serve.get_serve_timing_state()
			var phase: String = state.phase
			var label: = ""
			if frame == 46: label = "held"
			elif phase == "SWING" and float(state.progress) > 0.55: label = "approach"
			elif phase == "CONTACT": label = "contact"
			elif phase == "RECOVERY" and contacts == 1 and float(game.game_serve._follow_through.get("elapsed", 0.0)) > 0.3: label = "finish"
			if not label.is_empty() and not captured.has(label):
				snapshots.append(snapshot(p, label, style));captured[label] = true
			caption.text = "%s | actual input at60Hz simulation steps | %s\nOffline render of live gameplay; visual review pending" % [name, phase]
			if not check_only: await RenderingServer.frame_post_draw
			if frame % 2 == 0:
				if not check_only: root.get_texture().get_image().save_png(folder.path_join("frame%04d.png" % saved))
				records.append({"style": style, "frame": saved, "wall_usec": Time.get_ticks_usec(), "physics_tick": Engine.get_physics_frames(), "phase": phase, "contacts": contacts, "head": vd(p.paddle_node.global_transform * D.HEAD_OFFSET), "ball": vd(game.ball.global_position)})
				saved += 1
			if contacts > 0 and captured.has("finish") and game.game_serve._follow_through.is_empty(): break
		Input.action_release("ui_accept")
		if contacts != 1: failures.append("%s expected one real contact, got%d" % [name, contacts])
		for label in ["held", "approach", "contact", "finish"]:
			if not captured.has(label): failures.append("%s missing actual %s snapshot" % [name, label])

	game.process_mode = Node.PROCESS_MODE_DISABLED


	var frozen_nodes: Array = [game];frozen_nodes.append_array(game.find_children("*", "", true, false))
	for node in frozen_nodes: node.set_process(false);node.set_physics_process(false)
	for tween in get_processed_tweens(): tween.kill()
	var p = game.player_left
	var saved_meshes: Array = []
	var old_meshes: Array = []
	var bridge_metadata: Array = []
	for arm in [p.right_arm_node, p.left_arm_node]:
		bridge_metadata.append([arm, arm.get_meta(Arm.BRIDGE_META, null)])
		bridge_metadata.append([arm.upper_mesh, arm.upper_mesh.get_meta(Arm.BRIDGE_META, null)])
		for part in [0, 1]:
			var node: MeshInstance3D = arm.upper_mesh if part == 0 else arm.fore_mesh
			saved_meshes.append([node, node.mesh, node.skin, node.skeleton])
			old_meshes.append(OldArm._build(arm.upper_arm_length if part == 0 else arm.forearm_length, part == 0, Color("168be4"), Color("dbb18b")))
	var stills: = output.path_join("elbow_comparison");DirAccess.make_dir_recursive_absolute(stills)
	for row in ([] if check_only else snapshots):
		replay(row)
		for view in ["front", "hitting_side", "support_front"]:
			var center: Vector3 = (p.left_arm_node.forearm_pivot.global_position if view == "support_front" else row.elbow) + Vector3.UP * 0.045
			var direction: Vector3 = p._get_forward_axis() if view in ["front", "support_front"] else p._get_forehand_axis()
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL;camera.size = 0.77
			camera.global_position = center + direction * 2.0;camera.look_at(center, Vector3.UP)
			for version in ["before", "after"]:

				for entry in bridge_metadata:
					if version == "before": entry[0].remove_meta(Arm.BRIDGE_META)
					elif entry[1] != null: entry[0].set_meta(Arm.BRIDGE_META, entry[1])
				for index in saved_meshes.size():
					var item: Array = saved_meshes[index]; var node: MeshInstance3D = item[0]
					if version == "before": node.skin = null;node.skeleton = NodePath("");node.mesh = old_meshes[index]
					else: node.mesh = item[1];node.skin = item[2];node.skeleton = item[3]
				caption.text = "%s | %s | %s elbow surface\nExact recorded input pose; camera: %s" % ["Flat" if row.style == 0 else "Drop", row.label, version, view]
				await process_frame; await RenderingServer.frame_post_draw
				if not p.paddle_node.global_transform.is_equal_approx(row.paddle): failures.append("paddle moved during still replay")
				if p.right_arm_node.forearm_pivot.global_position.distance_to(row.elbow) > 1e-05: failures.append("elbow moved during still replay")
				root.get_texture().get_image().save_png(stills.path_join("%s_%s_%s_%s.png" % [row.style, row.label, view, version]))
	var after: Dictionary = hashes(); var drift: Array = []
	for path in before:
		if before[path] != after.get(path, ""): drift.append(path)
	for path in after:
		if not before.has(path): drift.append(path)
	if not drift.is_empty(): failures.append("source drift")
	var report: = FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"frames": records, "serve_events": serve_events, "capture_timing": "60Hz simulation steps; images every two render frames; normal-speed control path", "snapshots": snapshots.size(), "failures": failures, "source_before": before, "source_after": after, "source_drift": drift}, "\t"));report.close()
	print("VENDOR SERVE ELBOW CAPTURE frames=", records.size(), " snapshots=", snapshots.size(), " failures=", failures)
	game.queue_free(); await Drain.drain(self);quit(0 if failures.is_empty() else 1)
