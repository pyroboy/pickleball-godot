extends SceneTree
var game
var failures: Array[String] = []
var checks: = 0
func _initialize() -> void : call_deferred("run")
func check(ok: bool, text: String) -> void :
	checks += 1
	if not ok: failures.append(text);print("FAIL: ", text)
func frames(count: int) -> void :
	for i in count: await process_frame; await physics_frame
func tap(button: Button) -> void :
	var point: Vector2 = button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event: = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT;event.position = point;event.global_position = point;event.pressed = pressed
		root.push_input(event, true)
		await process_frame
func find_button(parent: Node, text: String) -> Button:
	for child in parent.get_children():
		if child is Button and child.text == text: return child
		var result: Button = find_button(child, text)
		if result != null: return result
	return null
func run() -> void :
	create_timer(60, true).timeout.connect( func(): quit(2))
	root.size = Vector2i(432, 936);root.content_scale_size = Vector2i(720, 1560)
	var title = load("res://scenes/title.tscn").instantiate()
	root.add_child(title);current_scene = title
	await frames(4)
	var practice: Button = find_button(title, "PRACTICE")
	check(practice != null, "Title Practice button missing")
	await tap(practice)
	var deadline: = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		await frames(1)
		if current_scene != title and current_scene != null and current_scene.get("practice_panel") != null: break
	game = current_scene
	check(game != title and game.get("practice_panel") != null, "Title pointer did not enter game")
	if game.get("practice_panel") == null: quit(1);return
	await frames(5)
	check(paused and game.practice_panel._picker_open, "Title Practice did not open picker")
	check( not has_meta("open_practice"), "Navigation meta leaked")
	await tap(find_button(game.practice_panel, "Wall Practice · solo rebound court"))
	await frames(6)
	check( not paused and game.practice_launcher.is_wall(), "Wall picker pointer failed")
	var pause = root.get_node("PauseController")
	pause.open(); await frames(3)
	check(pause._menu._resume_button.text == "Resume practice", "Pause mislabeled practice")
	check(pause._menu._reset_button.text == "Reset ball", "Wall direct Reset ball missing")
	var attempt: int = game.practice_launcher.attempt_count
	await tap(pause._menu._reset_button); await frames(3)
	check( not paused and game.practice_launcher.attempt_count == attempt + 1, "Direct Reset ball did not refeed")
	pause.open(); await frames(2)
	await tap(find_button(pause._menu, "Practice drills")); await frames(3)
	check(game.practice_panel._picker_open, "Pause practice picker missing")
	await tap(find_button(game.practice_panel, "Return to match")); await frames(3)
	check( not paused and not game.practice_launcher.is_active and not game.ball.wall_practice_active, "Return to match tap failed")
	check(game.score_left == 0 and game.score_right == 0, "Navigation changed match score")
	game.queue_free(); await frames(3)
	print("WALL NAVIGATION ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
