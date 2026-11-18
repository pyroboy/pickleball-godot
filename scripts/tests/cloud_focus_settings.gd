extends SceneTree

# Run only with the dedicated cloud-pickleball/settings-home HOME/XDG directories.
# Optional --seed / --reload prove persistence across separate Godot processes.
const SettingsScript = preload("res://scripts/ui/settings.gd")
const POSE_SENTINELS: Array[String] = [
	"user://mobile_pose_overrides_v1.json",
	"user://mobile_serve_pose_overrides_v1.json",
]
const POSE_BYTES: String = "{\"cloud_settings_qa\": \"preserve this isolated fixture byte-for-byte\"}\n"
var checks: int = 0
var failures: Array[String] = []
var settings: Node
var emitted: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/settings-home/"):
		push_error("Use the isolated cloud-pickleball/settings-home XDG_DATA_HOME for this test")
		quit(2)
		return
	create_timer(30.0).timeout.connect(func(): quit(2))
	settings = root.get_node("Settings")
	root.get_node("PauseController").set_process_input(false)
	settings.settings_changed.connect(func(key: String, value: Variant): emitted.append([key, value]))
	if OS.get_cmdline_user_args().has("--seed"):
		_seed()
		await process_frame
		_finish("seed")
		return
	if OS.get_cmdline_user_args().has("--reload"):
		_check_saved_fixture("fresh process")
	var original: String = settings._config.encode_to_text()
	_test_defaults_and_validation()
	await _test_reset_and_save()
	await _test_panel()
	# Leave the caller's isolated settings exactly as they were on entry.
	var restored: = ConfigFile.new()
	check(restored.parse(original) == OK, "original isolated config parses")
	settings._config = restored
	settings._do_save()
	await process_frame
	_finish("reload" if OS.get_cmdline_user_args().has("--reload") else "standalone")

func _seed() -> void:
	settings.set_value("video.focus_dim", 0.23)
	settings.set_value("video.focus_blur", 1.15)
	settings.set_value("video.focus_preview", false)
	settings.set_value("gameplay.aim_focus_seconds", 4.5)
	settings.set_value("pose_editor.cloud_settings_sentinel", {"revision": 7, "custom_pose": [1, 2, 3]})
	for path in POSE_SENTINELS:
		var file: = FileAccess.open(path, FileAccess.WRITE)
		check(file != null, "create isolated pose sentinel " + path)
		if file:
			file.store_string(POSE_BYTES)
			file.close()
	settings._do_save()
	_check_saved_fixture("seed save")

func _check_saved_fixture(context: String) -> void:
	check(is_equal_approx(settings.get_value("video.focus_dim"), 0.23), context + ": dim value survives")
	check(is_equal_approx(settings.get_value("video.focus_blur"), 1.15), context + ": blur value survives")
	check(settings.get_value("video.focus_preview") == false, context + ": preview-off survives")
	check(is_equal_approx(settings.get_value("gameplay.aim_focus_seconds"), 4.5), context + ": gameplay survives")
	check(settings.get_value("pose_editor.cloud_settings_sentinel") == {"revision": 7, "custom_pose": [1, 2, 3]}, context + ": unknown config survives")
	for path in POSE_SENTINELS:
		check(FileAccess.get_file_as_string(path) == POSE_BYTES, context + ": pose bytes survive " + path)

func _test_defaults_and_validation() -> void:
	settings._config = ConfigFile.new()
	settings._config.set_value("video", "fov", 73.0)
	check(settings.get_value("video.focus_dim") == 0.14, "older config gets dim default")
	check(settings.get_value("video.focus_blur") == 0.65, "older config gets blur default")
	check(settings.get_value("video.focus_preview") == true, "older config gets preview default")
	check(settings.get_value("video.fov") == 73.0, "older video preference preserved")
	check(not settings._config.has_section_key("video", "focus_dim"), "reading defaults does not rewrite config")
	for key in ["video.focus_dim", "video.focus_blur"]:
		var ceiling: float = 0.35 if key == "video.focus_dim" else 1.5
		var fallback: float = SettingsScript.DEFAULTS[key]
		for amount in [-100.0, -0.01, 0.0, 0.14, ceiling, 999.0, 1]:
			emitted.clear()
			settings.set_value(key, amount)
			var expected: float = clampf(float(amount), 0.0, ceiling)
			check(is_equal_approx(settings.get_value(key), expected), "%s bounds %s" % [key, amount])
			check(emitted.size() == 1 and is_equal_approx(emitted[0][1], expected), "signals carry sanitized " + key)
		for malformed in [NAN, INF, -INF, "0.2", "bad", true, false, null, [], {}]:
			settings.set_value(key, malformed)
			check(is_equal_approx(settings.get_value(key), fallback), "invalid setter falls back: " + key)
			settings._config.set_value("video", key.get_slice(".", 1), malformed)
			check(is_equal_approx(settings.get_value(key), fallback), "invalid saved value falls back: " + key)
	for value in [true, false]:
		settings.set_value("video.focus_preview", value)
		check(settings.get_value("video.focus_preview") == value, "preview bool persists")
	for malformed in [0, 1, "false", "true", null, [], {}]:
		settings.set_value("video.focus_preview", malformed)
		check(settings.get_value("video.focus_preview") == true, "preview invalid setter uses default")
		settings._config.set_value("video", "focus_preview", malformed)
		check(settings.get_value("video.focus_preview") == true, "preview invalid saved value uses default")
	check(settings.get_value("missing.key", 12) == 12, "unrelated fallback semantics unchanged")
	settings.set_value("unknown.nested", {"keep": [true, 2.4]})
	check(settings.get_value("unknown.nested") == {"keep": [true, 2.4]}, "unrelated values pass through unchanged")

func _test_reset_and_save() -> void:
	_seed()
	settings.set_value("video.shake", 0.25)
	settings.set_value("audio.master", 0.33)
	emitted.clear()
	settings.reset_focus_visuals()
	check(emitted.size() == SettingsScript.FOCUS_VISUAL_KEYS.size(), "group reset emits exactly the visual setting changes")
	for event in emitted:
		check(event[0] in SettingsScript.FOCUS_VISUAL_KEYS, "group reset never emits unrelated key")
	for key in SettingsScript.FOCUS_VISUAL_KEYS:
		check(settings.get_value(key) == SettingsScript.DEFAULTS[key], "group reset default: " + key)
	check(settings.get_value("video.shake") == 0.25, "group reset preserves other video setting")
	check(settings.get_value("audio.master") == 0.33, "group reset preserves audio")
	check(settings.get_value("gameplay.aim_focus_seconds") == 4.5, "group reset preserves aim timing")
	await process_frame
	var disk: = ConfigFile.new()
	check(disk.load(SettingsScript.CONFIG_PATH) == OK, "queued save produces reloadable config")
	check(disk.get_value("video", "focus_dim") == 0.14, "queued save contains reset dim")
	check(disk.get_value("video", "focus_blur") == 0.65, "queued save contains reset blur")
	check(disk.get_value("video", "focus_preview") == true, "queued save contains reset preview")
	check(disk.get_value("pose_editor", "cloud_settings_sentinel") == {"revision": 7, "custom_pose": [1, 2, 3]}, "group reset preserves unknown config on disk")
	settings.reset_to_defaults()
	check(settings.get_value("pose_editor.cloud_settings_sentinel") == {"revision": 7, "custom_pose": [1, 2, 3]}, "full settings reset retains unknown pose config")
	for key in SettingsScript.FOCUS_VISUAL_KEYS:
		check(settings.get_value(key) == SettingsScript.DEFAULTS[key], "full reset includes " + key)
	for path in POSE_SENTINELS:
		check(FileAccess.get_file_as_string(path) == POSE_BYTES, "settings resets leave pose bytes unchanged: " + path)
	await process_frame

func _test_panel() -> void:
	paused = true
	for resolution in [Vector2i(720, 1280), Vector2i(540, 960), Vector2i(360, 800), Vector2i(390, 844), Vector2i(1080, 2340), Vector2i(1280, 720)]:
		root.content_scale_size = resolution
		root.size = resolution
		var panel = load("res://scripts/ui/settings_panel.gd").new()
		root.add_child(panel)
		for frame in 6:
			await process_frame
		var dim: HSlider = panel.find_child("video_focus_dim", true, false)
		var blur: HSlider = panel.find_child("video_focus_blur", true, false)
		var preview: CheckButton = panel.find_child("video_focus_preview", true, false)
		var reset: Button = panel.find_child("ResetFocusVisuals", true, false)
		var scroll: ScrollContainer = panel.find_child("Video", true, false)
		var footnote: Label = panel.find_child("SettingsFootnote", true, false)
		check(dim != null and blur != null and preview != null and reset != null, "focus controls exist at %s" % resolution)
		check(root.get_visible_rect().grow(0.5).encloses(panel._panel.get_global_rect()), "settings panel fits %s" % resolution)
		check(footnote.text == "Changes save automatically · Back returns to the previous screen", "Back footer fits both title and pause origins")
		check(footnote.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and panel._panel.get_global_rect().encloses(footnote.get_global_rect()), "wrapped footer stays within panel at %s" % resolution)
		check(scroll.get_h_scroll_bar().max_value <= scroll.get_h_scroll_bar().page + 0.5, "no horizontal scroll at %s" % resolution)
		check(dim.min_value == 0.0 and dim.max_value == 0.35 and is_equal_approx(dim.step, 0.01), "dim UI range and step")
		check(blur.min_value == 0.0 and blur.max_value == 1.5 and is_equal_approx(blur.step, 0.05), "blur UI range and step")
		dim.value = 0.27
		blur.value = 1.25
		preview.button_pressed = false
		check(is_equal_approx(settings.get_value("video.focus_dim"), 0.27), "dim slider persists at %s" % resolution)
		check(is_equal_approx(settings.get_value("video.focus_blur"), 1.25), "blur slider persists at %s" % resolution)
		check(settings.get_value("video.focus_preview") == false, "preview toggle persists at %s" % resolution)
		check(panel._focus_value_labels["video.focus_dim"].text == "27%", "dim value has clear percent unit")
		check(panel._focus_value_labels["video.focus_blur"].text == "1.25", "blur is unitless strength")
		for control in [dim, blur, preview, reset]:
			scroll.ensure_control_visible(control)
			await process_frame
			check(scroll.get_global_rect().grow(0.5).encloses(control.get_global_rect()), "%s reachable in scroll at %s" % [control.name, resolution])
			if control is HSlider:
				var rect: Rect2 = control.get_global_rect()
				await _tap_point(rect.position + Vector2(rect.size.x * 0.25, 2.0))
				check(control.value < (control.min_value + control.max_value) * 0.5, "slider top hit-area edge accepts pointer: %s at %s" % [control.name, resolution])
				await _tap_point(rect.position + Vector2(rect.size.x * 0.75, rect.size.y - 2.0))
				check(control.value > (control.min_value + control.max_value) * 0.5, "slider bottom hit-area edge accepts pointer: %s at %s" % [control.name, resolution])
		settings.set_value("video.focus_dim", 0.11)
		check(is_equal_approx(dim.value, 0.11), "live setting update synchronizes slider")
		check(panel._focus_value_labels["video.focus_dim"].text == "11%", "live setting update synchronizes readout")
		for repeated in 3:
			reset.pressed.emit()
			check(is_equal_approx(dim.value, 0.14) and is_equal_approx(blur.value, 0.65) and preview.button_pressed, "repeat reset synchronizes all controls")
			check(panel._focus_value_labels["video.focus_dim"].text == "14%", "reset synchronizes percent readout")
		var closes: Array[int] = [0]
		panel.set_meta("on_close", func(): closes[0] += 1)
		panel._on_close()
		panel._on_close()
		check(closes[0] == 1, "repeated close emits callback once")
		await process_frame
		settings.set_value("video.focus_dim", 0.14)
		check(not is_instance_valid(panel), "closed panel is freed")
	paused = false

func _tap_point(point: Vector2) -> void:
	for down in [true, false]:
		var event: = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = down
		root.push_input(event, true)
		await process_frame

func _finish(stage: String) -> void:
	for failure in failures:
		push_error(failure)
	print("CLOUD FOCUS SETTINGS (%s): %d checks, %d failures" % [stage, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
