extends SceneTree
## Repeated lifecycle diagnosis; never edits runtime code or authored poses.
## The game has no Title-return button, so that final transition is programmatic.
var checks := 0
var failures: Array[String] = []
var snapshots: Array[Dictionary] = []
var cycles := 15
var retain_history := true
var snapshot_sink: FileAccess
var measurement_count := 0
var output := "user://cloud-scene-lifecycle-memory.json"

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func frames(count := 3) -> void:
	for i in count:
		await process_frame

func orphan_details() -> Array:
	var rows: Array = []
	if not root.has_method("get_orphan_node_ids"):
		return rows
	for id in root.call("get_orphan_node_ids"):
		var node = instance_from_id(id)
		if not is_instance_valid(node):
			continue
		rows.append({"id": id, "name": str(node.name), "class": node.get_class(), "script": node.get_script().resource_path if node.get_script() != null else ""})
	return rows

func snapshot(stage: String, cycle: int) -> void:
	var row: Dictionary = {
		"stage": stage, "cycle": cycle,
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_nodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"tree_nodes": get_node_count(),
		"static_memory_bytes": OS.get_static_memory_usage(),
		"posture_definitions": PostureLibrary.instance().all_definitions().size(),
		"base_pose_definitions": BasePoseLibrary.instance().definitions.size(),
		"settings_connections": root.get_node("Settings").settings_changed.get_connections().size(),
		"size_connections": root.size_changed.get_connections().size(),
		"focus_enter_connections": root.focus_entered.get_connections().size(),
		"focus_exit_connections": root.focus_exited.get_connections().size(),
		"orphans": orphan_details()
	}
	measurement_count += 1
	if not retain_history: snapshots.clear()
	snapshots.append(row)
	if snapshot_sink != null:
		snapshot_sink.store_line(JSON.stringify(row))
		snapshot_sink.flush()
	print("LIFECYCLE MEMORY ", JSON.stringify(row))

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--stream": retain_history = false
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
		if arg.begins_with("--cycles="):
			cycles = int(arg.trim_prefix("--cycles="))
	if not retain_history: snapshot_sink = FileAccess.open(output + ".jsonl", FileAccess.WRITE)
	create_timer(240.0, true).timeout.connect(func(): push_error("Lifecycle memory timeout"); quit(2))
	root.size = Vector2i(540, 960)
	root.content_scale_size = Vector2i(720, 1280)
	var pause = root.get_node("PauseController")
	check(change_scene_to_file("res://scenes/title.tscn") == OK, "initial Title loads")
	await frames(6)
	snapshot("initial_title", 0)
	for cycle in range(1, cycles + 1):
		var title = current_scene
		title._play.pressed.emit()
		var deadline := Time.get_ticks_msec() + 15000
		while current_scene == title and Time.get_ticks_msec() < deadline:
			OS.delay_msec(1)
			await process_frame
		check(current_scene != title and current_scene != null and current_scene.get("ball") != null, "cycle %d Play loads Game" % cycle)
		if current_scene == title or current_scene == null:
			break
		await frames(4)
		var game = current_scene
		# Exercise the focus overlay before teardown, without committing a serve.
		Input.action_press("ui_accept")
		game._on_player_swing_press()
		game.aim_controller.update(0.1, true, Vector2.ZERO)
		game.aim_focus._update_presentation(Time.get_ticks_usec())
		pause.open()
		await frames()
		check(paused and is_instance_valid(pause._menu), "cycle %d Pause opens" % cycle)
		var menu = pause._menu
		menu._settings_button.pressed.emit()
		await frames()
		check(is_instance_valid(menu._settings_overlay), "cycle %d Settings opens" % cycle)
		menu.close_settings()
		await frames()
		check(paused and not is_instance_valid(menu._settings_overlay), "cycle %d Settings closes to Pause" % cycle)
		pause.close()
		Input.action_release("ui_accept")
		await frames()
		check(not paused and not is_instance_valid(pause._menu), "cycle %d Resume clears Pause" % cycle)
		snapshot("game_before_exit", cycle)
		# Diagnostic teardown route only: production Quit game exits the process.
		check(change_scene_to_file("res://scenes/title.tscn") == OK, "cycle %d programmatic Title transition" % cycle)
		await frames(12)
		await preload("res://scripts/tests/audio_teardown.gd").drain(self)
		await frames(6)
		check(is_equal_approx(Engine.time_scale, 1.0) and not paused, "cycle %d Title clock restored" % cycle)
		snapshot("stable_title", cycle)
	var file := FileAccess.open(output, FileAccess.WRITE)
	check(file != null, "memory evidence file opens")
	if file != null:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "cycles_requested": cycles, "measurements": measurement_count, "retain_history": retain_history, "stream_path": output + ".jsonl" if snapshot_sink != null else "", "snapshots": snapshots, "scope": "Title Play button signal, held aim, Pause/Settings signals, programmatic scene return to Title. Counts are diagnostic; static library caches are expected."}, "  "))
		file.close()
	print("CLOUD SCENE LIFECYCLE MEMORY: %d checks, %d failures; snapshots=%d; evidence=%s" % [checks, failures.size(), snapshots.size(), output])
	quit(0 if failures.is_empty() else 1)
