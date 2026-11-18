extends SceneTree

const Feeds = preload("res://scripts/debug/kitchen_review_feeds.gd")
var game
var output: = "/tmp/dynamic-kitchen-captures"
var captures: Array = []
var hit_count: = 0
func _initialize(): call_deferred("run")
func run() -> void :
	if DisplayServer.get_name() == "headless":
		push_error("Kitchen capture needs a rendered display")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size = Vector2i(720, 1560)
	root.size = Vector2i(720, 1560)
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.ball.hit_by_paddle.connect( func(_team): hit_count += 1)
	for setup in [{"kind": "WIDE", "receiver": 0}, {"kind": "CENTER", "receiver": 0}, 
		{"kind": "ACUTE", "receiver": 1}, {"kind": "HIGH_POPUP", "receiver": 1}]:
		hit_count = 0
		Feeds.scenario(game, setup.kind, setup.receiver, 1, 110)
		game.practice_launcher.demo_enabled = true
		var saved_hits: = 0
		for frame in range(300):
			await physics_frame
			if frame == 24: await capture("%s_p%d_approach" % [setup.kind.to_lower(), setup.receiver])
			if hit_count > saved_hits:
				saved_hits = hit_count
				await capture("%s_p%d_contact%d_%s" % [setup.kind.to_lower(), setup.receiver, hit_count, game.practice_launcher.last_response_kind.to_lower()])
			if game.practice_launcher._attempt_finished or hit_count >= (2 if setup.kind == "HIGH_POPUP" else 1): break
		game.practice_launcher.stop_practice()
		await physics_frame
	var file = FileAccess.open(output.path_join("captures.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(captures, "\t"))
	print("KITCHEN CAPTURES ", output, " count=", captures.size())
	game.queue_free()
	await process_frame
	quit()
func capture(label: String) -> void :
	await RenderingServer.frame_post_draw
	var path: String = output.path_join(label + ".png")
	root.get_texture().get_image().save_png(path)
	captures.append({"label": label, "file": path, "ball": game.ball.global_position, 
		"blue": game.player_left.global_position, "red": game.player_right.global_position, 
		"response": game.practice_launcher.last_response_kind, "hits": hit_count})
