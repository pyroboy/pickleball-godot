extends SceneTree
## Full opt-in editor flow, with a rendering subclass for mobile layout evidence.
const Store = preload("res://scripts/mobile_pose_store.gd")
const ServeStore = preload("res://scripts/mobile_serve_pose_store.gd")
const GripStore = preload("res://scripts/mobile_paddle_grip_store.gd")
const ViewSettings = preload("res://scripts/mobile_pose_view_settings.gd")
var test_id := "%d_%d" % [OS.get_process_id(), int(Time.get_unix_time_from_system() * 1000000.0)]
var checks := 0
var failures: Array[String] = []
var capture := false
var game
var editor
var pause
var output := "/workspace/scratch/6b6e64f75bd2/verification/inbetween-ghosts"
var settings_path := ""
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func frames(count: int = 3) -> void:
	for i in range(count): await process_frame
func select_id(id: int) -> void:
	for i in range(editor._definitions.size()):
		if editor._definitions[i].posture_id == id: editor._select_pose(i); return
	check(false, "requested pose exists %d" % id)
func file_bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
func snapshot_files() -> Array:
	return [file_bytes(Store.storage_path()), file_bytes(ServeStore.storage_path()), file_bytes(GripStore.storage_path())]
func assert_count(count: int, label: String) -> void:
	check(is_equal_approx(editor._ghost_slider.value, count) and editor._preview.inbetween_count == count, label + ": slider and actual preview agree")
	check(ViewSettings.load_inbetween_count() == count, label + ": viewing setting saved independently")
	var text: String = editor._ghost_label.text.to_lower()
	check(text.contains("off") if count == 0 else text.contains("gap") and text.contains(str(count)) and text.contains(str(2 * count)), label + ": label explains off or count per gap and total")
func snap(name: String) -> void:
	await frames(5)
	var bounds: Rect2 = root.get_visible_rect()
	for target in [editor._preview, editor._ghost_slider, editor._ghost_label, editor._scroll, editor._save]:
		if editor._visual_scroll.is_ancestor_of(target):
			editor._visual_scroll.ensure_control_visible(target)
			await frames(2)
		check(bounds.encloses(target.get_global_rect()), name + ": control fits viewport " + str(target.get_class()))
	check(editor._ghost_slider.get_global_rect().size.x > 80 * editor._s, name + ": count slider has usable width")
	check(editor._preview.size.y >= 150 * editor._s and editor._scroll.size.y >= 80 * editor._s, name + ": preview and editing remain usable")
	if capture:
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(output + "/" + name + ".png") == OK, name + ": screenshot saved")
func close_reopen(expected: int, reload_settings: bool) -> void:
	var ghost_root: WeakRef = weakref(editor._preview._inbetween_root)
	var refs: Array[WeakRef] = []
	for child in editor._preview._inbetween_root.find_children("*", "", true, false): refs.append(weakref(child))
	editor._finish_close(); await frames(4)
	check(game.mobile_pose_editor == null and ghost_root.get_ref() == null, "close frees editor and ghost root")
	for ref in refs: check(ref.get_ref() == null, "close releases pooled mesh and skeleton nodes")
	await process_frame; pause.close(); await frames(2)
	if reload_settings: check(ViewSettings.set_test_path(settings_path) == OK, "reset in-memory settings before reopening")
	pause.open(); game.open_mobile_pose_editor(); await frames(4); editor = game.mobile_pose_editor
	check(is_instance_valid(editor), "editor reopens")
	assert_count(expected, "reopen")
func run() -> void:
	create_timer(180, true).timeout.connect(func(): quit(2))
	DirAccess.make_dir_recursive_absolute(output)
	var isolate := "user://pose_store_tests/inbetween_ui_%s/" % test_id
	check(Store.set_test_path(isolate + "poses.json") == OK, "isolated pose save")
	check(ServeStore.set_test_path(isolate + "serves.json") == OK, "isolated serve save")
	check(GripStore.set_test_path(isolate + "grips.json") == OK, "isolated grip save")
	settings_path = isolate + "view.json"
	check(ViewSettings.set_test_path(settings_path) == OK, "isolated view settings")
	root.size = Vector2i(432, 936); root.content_scale_size = Vector2i(720, 1560)
	pause = root.get_node("PauseController")
	if capture:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game; await frames(4)
	pause.open(); game.open_mobile_pose_editor(); await frames(4); editor = game.mobile_pose_editor
	select_id(0); editor._view_toggle.button_pressed = true; await frames()
	assert_count(2, "new editor")
	check(editor._ghost_slider.min_value == 0 and editor._ghost_slider.max_value == 6 and editor._ghost_slider.step == 1, "integer slider bounds are zero to six per gap")
	check(editor._ghost_slider.is_visible_in_tree() and editor._ghost_slider.editable, "slider discoverable for motion pose")
	var original: String = Store.export_pose_json(editor._current)
	var files: Array = snapshot_files()
	var dirty: Dictionary = editor._dirty.duplicate(true)
	var rebuilds: int = editor._preview.motion_rebuild_count
	var cached: PackedByteArray = var_to_bytes(editor._preview._inbetween_root.samples)
	for count in [0, 1, 6]:
		editor._ghost_slider.value = count; await frames()
		assert_count(count, "slider %d" % count)
		check(editor._preview.inbetween_sample_indices.size() == 2 * count, "actual ghost positions equal two gaps times slider count")
		check(editor._preview._inbetween_root.is_visible_in_tree() == (count > 0), "zero slider hides all in-between geometry")
		check(editor._preview.motion_rebuild_count == rebuilds, "slider does not rebuild motion")
		check(var_to_bytes(editor._preview._inbetween_root.samples) == cached, "slider keeps cached rig snapshots")
		check(Store.export_pose_json(editor._current) == original and editor._dirty == dirty and not editor._dirty.has(editor._key), "view setting never authors or dirties a pose")
		check(snapshot_files() == files, "view setting leaves saved pose, serve and grip files unchanged")
		await snap("portrait-count-%d" % count)
	for stage in range(3):
		editor._select_stage(stage); await frames()
		assert_count(6, "phase switch")
		check(editor._preview.motion_rebuild_count == rebuilds, "authored phase selection reuses cached in-between rig")
	for progress in [0.0, .1, .27, .5, .88, 1.0]: editor._scrubbed(progress)
	editor._preview.view("side"); editor._preview.zoom(.1)
	editor._toggle_play(); editor._last_tick -= 50000; editor._process(0); editor._toggle_play()
	check(editor._preview.motion_rebuild_count == rebuilds and var_to_bytes(editor._preview._inbetween_root.samples) == cached, "scrub, play and camera preserve in-between cache")
	editor._select_stage(0); editor._changed("body_yaw_deg", float(editor._edit.body_yaw_deg) + 15.0); await frames()
	check(editor._preview.motion_rebuild_count > rebuilds and var_to_bytes(editor._preview._inbetween_root.samples) != cached, "real body edit refreshes actual in-between geometry")
	var authored: String = Store.export_pose_json(editor._current)
	for mode in [1, 2]:
		rebuilds = editor._preview.motion_rebuild_count
		editor._play_variant(mode); editor._stop(); await frames()
		check(editor._preview.motion_rebuild_count == rebuilds + 1, "Strong/Weak sampler changes rebuild body snapshots once")
		check(editor._variant_mode == mode and editor._preview.inbetween_sample_indices.size() == 12, "generated motion keeps twelve requested body ghosts")
		check(Store.export_pose_json(editor._current) == authored, "generated body ghosts do not author keys")
		await snap("portrait-variant-%d" % mode)
	editor._reset_default(); await frames()
	assert_count(6, "pose Default leaves view preference alone")
	check(not editor._dirty.has(editor._key), "pose Default clears only pose dirty state")
	editor._preview.view("reset")
	select_id(1); await frames(); assert_count(6, "different stroke")
	check(editor._preview._inbetween_root.is_visible_in_tree(), "different stroke refreshes and displays ghosts")
	select_id(20); await frames()
	check(not editor._preview._inbetween_root.is_visible_in_tree(), "Ready hides whole-body in-betweens")
	check(not editor._ghost_slider.is_visible_in_tree() or not editor._ghost_slider.editable, "Ready cannot suggest editable motion ghosts")
	editor._select_workspace(1); await frames()
	check(not editor._preview._inbetween_root.is_visible_in_tree(), "Body stances hide whole-body in-betweens")
	check(not editor._ghost_slider.is_visible_in_tree() or not editor._ghost_slider.editable, "Body stance does not expose active motion setting")
	editor._select_workspace(2); editor._view_toggle.button_pressed = true; await frames()
	assert_count(6, "serve workspace")
	check(editor._ghost_slider.is_visible_in_tree() and editor._ghost_slider.editable and editor._preview._inbetween_root.is_visible_in_tree(), "serve restores motion control and ghosts")
	for style in range(editor._definitions.size()):
		editor._select_pose(style); await frames(1)
		check(editor._preview._inbetween_root.samples.size() == 65 and editor._preview.inbetween_sample_indices.size() == 12, "serve style regenerates complete cache")
	await snap("portrait-serve-count-6")
	editor._select_workspace(0); select_id(0); editor._ghost_slider.value = 1
	root.size = Vector2i(432, 768); root.content_scale_size = Vector2i(720, 1280); await snap("short-portrait-count-1")
	root.size = Vector2i(936, 432); root.content_scale_size = Vector2i(1560, 720); editor._ghost_slider.value = 6; await snap("landscape-count-6")
	root.size = Vector2i(432, 936); root.content_scale_size = Vector2i(720, 1560)
	await close_reopen(6, false)
	editor._ghost_slider.value = 0; await close_reopen(0, true)
	editor._ghost_slider.value = 1; await close_reopen(1, true)
	editor._ghost_slider.value = 6; await close_reopen(6, true)
	editor._finish_close(); await frames(4); await process_frame; pause.close(); await frames(3)
	game.queue_free(); await frames(4)
	var report := {"suite": "inbetween-ui-render" if capture else "inbetween-ui", "checks": checks, "failures": failures}
	var report_file := FileAccess.open(output + ("/render-results.json" if capture else "/ui-results.json"), FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t")); report_file.close()
	print("[MOBILE INBETWEEN CONTROLS] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
