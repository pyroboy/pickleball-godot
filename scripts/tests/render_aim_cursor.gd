extends SceneTree

var game
var output_dir: = OS.get_environment("AIM_QA_OUTPUT")
func _initialize() -> void : call_deferred("run")
func snap(label: String) -> void :
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir.path_join(label + ".png"))
	print("AIM VISUAL ", label, " target=", game.aim_controller.get_target(), " player=", game.player_left.global_position, " mode=", game.aim_controller.mode)
func run() -> void :
	if output_dir.is_empty(): output_dir = "user://aim_visual"
	DirAccess.make_dir_recursive_absolute(output_dir)
	var pause = root.get_node_or_null("PauseController")
	if pause: pause.queue_free()
	await process_frame
	paused = false
	root.size = Vector2i(1280, 800)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.input_handler.set_process(false)
	for i in range(5): await physics_frame
	game.input_handler._process(0.0)
	await snap("aim_01_default")
	Input.action_press("ui_accept")
	game.input_handler._process(0.25)
	for i in range(5): await physics_frame
	await snap("aim_02_center")
	Input.action_press("move_right")
	for i in range(9):
		game.input_handler._process(1.0 / 60.0)
		await physics_frame
	await snap("aim_03_right")
	Input.action_release("move_right")
	Input.action_press("move_up")
	for i in range(10):
		game.input_handler._process(1.0 / 60.0)
		await physics_frame
	await snap("aim_04_deeper")
	Input.action_release("move_up")
	Input.action_release("ui_accept")
	game.input_handler._process(0.0)
	game.game_serve.set_physics_process(false)
	game.game_trajectory._update_player_cursor()
	await snap("aim_05_locked")
	quit()
