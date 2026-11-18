extends SceneTree


const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Styles = preload("res://scripts/serve_style.gd")
var game
var output: = "/workspace/shared/pickleball-hands/shared-serve-motion"
var records: Array = []
var hits: = 0
func _initialize(): call_deferred("run")
func source_hashes(folder: String = "res://") -> Dictionary:
	var hashes: Dictionary = {}
	for file in DirAccess.get_files_at(folder):
		if file.get_extension() in ["gd", "tres", "tscn", "gdshader", "godot"]:
			var path: String = folder.path_join(file)
			hashes[path] = FileAccess.get_sha256(path)
	for directory in DirAccess.get_directories_at(folder):
		if not directory.begins_with("."): hashes.merge(source_hashes(folder.path_join(directory)))
	return hashes
func run():
	if DisplayServer.get_name() == "headless": quit(2);return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	var hashes_before: Dictionary = source_hashes()
	root.size = Vector2i(960, 900);root.content_scale_size = Vector2i(960, 900)
	DisplayServer.window_set_size(Vector2i(960, 900))
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	paused = false
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(8): await process_frame
	game.reaction_button.auto_fire_on_perfect = false
	game.game_serve.serve_launched.connect( func(_team): hits += 1)
	var inspection_camera: = Camera3D.new();game.add_child(inspection_camera);inspection_camera.make_current()
	for child in game.get_children():
		if child is CanvasLayer: child.visible = false
	var layer: = CanvasLayer.new();root.add_child(layer)
	var caption: = Label.new();caption.position = Vector2(20, 18);caption.add_theme_font_size_override("font_size", 22);layer.add_child(caption)
	for style in [0, 4]:
		game._reset_match();game.game_serve.select_serve_style(style);hits = 0
		for frame in range(12): await process_frame
		var p = game.player_left
		game.player_right.set_ai_movement_enabled(false)
		var camera: Camera3D = inspection_camera
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE;camera.fov = 43;camera.near = 0.01
		var focus: Vector3 = p.global_position + Vector3.UP * 0.02
		camera.global_position = focus + p._get_forward_axis() * 2.65 + p._get_forehand_axis() * 1.25 + Vector3.UP * 0.15
		camera.look_at(focus, Vector3.UP)
		var folder: String = output.path_join("flat" if style == 0 else "drop_drive")
		DirAccess.make_dir_recursive_absolute(folder)
		var saved: = 0
		for frame in range(204):
			if frame == 18: Input.action_press("ui_accept")
			if frame == 48: Input.action_release("ui_accept")
			await process_frame
			var phase: String = game.game_serve.get_serve_timing_state().phase
			caption.text = "%s | actual input and physical contact | %s\nMain arm motion checkpoint; free-hand CUP remains in progress" % [Styles.options()[style].label, phase]
			await RenderingServer.frame_post_draw
			if frame % 2 == 0:
				root.get_texture().get_image().save_png(folder.path_join("frame%04d.png" % saved))
				records.append({"style": style, "frame": saved, "phase": phase, "contacts": hits, "head": p.paddle_node.global_transform * PaddleSize.HEAD_OFFSET, "ball": game.ball.global_position})
				saved += 1
		Input.action_release("ui_accept")
		if hits != 1: push_error("Actual serve capture expected one physical contact, got%d" % hits);quit(3);return
	var file: = FileAccess.open(output.path_join("frames.json"), FileAccess.WRITE);file.store_string(JSON.stringify(records, "\t"));file.close()
	var hashes_after: Dictionary = source_hashes()
	var drift: Array = []
	for path in hashes_before:
		if hashes_before[path] != hashes_after.get(path, ""): drift.append(path)
	for path in hashes_after:
		if not hashes_before.has(path): drift.append(path)
	var manifest: = FileAccess.open(output.path_join("source-manifest.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"before": hashes_before, "after": hashes_after, "source_drift": drift}, "\t"));manifest.close()
	if not drift.is_empty(): push_error("Serve capture source changed during frames");quit(4);return
	print("ACTUAL SERVE MOTION CAPTURE ", output, " frames=", records.size())
	game.queue_free(); await process_frame;quit()
