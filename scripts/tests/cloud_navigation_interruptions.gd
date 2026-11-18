extends SceneTree
## Independent cloud QA: real pointer dispatch through title and paused Settings.
## Runs only against disposable HOME/XDG state and never edits authored poses.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func frames(count := 2) -> void:
	for i in count:
		await process_frame

func button_named(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text:
			return child
		var found := button_named(child, text)
		if found != null:
			return found
	return null

func tap(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await frames()

func run() -> void:
	create_timer(60.0, true).timeout.connect(func(): quit(2))
	root.size = Vector2i(540, 960)
	root.content_scale_size = Vector2i(720, 1280)
	var pause = root.get_node("PauseController")
	var title = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	current_scene = title
	await frames(4)
	for cycle in range(3):
		await tap(title._settings)
		check(is_instance_valid(title._overlay), "title Settings opens by pointer, cycle %d" % cycle)
		if not is_instance_valid(title._overlay):
			continue
		var overlay = title._overlay
		print("TITLE SETTINGS STATE: paused=", paused, " process_mode=", overlay.process_mode, " can_process=", overlay.can_process())
		title._open_settings()
		check(title._overlay == overlay, "repeated Settings request preserves a single overlay")
		var back := button_named(overlay, "Back")
		check(back != null, "title Settings has Back button")
		if back != null:
			await tap(back)
		check(not is_instance_valid(title._overlay), "title Settings Back responds to pointer, cycle %d" % cycle)
		check(not paused, "title Settings leaves title unpaused")
		if is_instance_valid(title._overlay):
			# Recover through the existing Back controller so subsequent checks run.
			pause._handle_back_request()
			await frames()
		check(not is_instance_valid(title._overlay), "native Back recovers title Settings")
		check(root.gui_get_focus_owner() == title._settings, "title Settings restores button focus")
	title.queue_free()
	await frames()
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(3)
	for cycle in range(3):
		pause.open()
		await frames()
		var menu = pause._menu
		await tap(menu._settings_button)
		check(is_instance_valid(menu._settings_overlay), "paused Settings opens by pointer, cycle %d" % cycle)
		if is_instance_valid(menu._settings_overlay):
			var back := button_named(menu._settings_overlay, "Back")
			if back != null:
				await tap(back)
			check(not is_instance_valid(menu._settings_overlay), "paused Settings Back responds to pointer, cycle %d" % cycle)
		check(paused and menu._panel.visible, "paused Settings returns to visible Pause menu")
		pause._handle_back_request()
		await frames()
		check(not paused and not is_instance_valid(pause._menu), "Back resumes after repeated Settings cycle")
	game.queue_free()
	await frames(3)
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	print("CLOUD NAVIGATION INTERRUPTIONS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
