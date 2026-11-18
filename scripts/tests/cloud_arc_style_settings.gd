extends SceneTree
## Actual integrated settings, isolated persistence, and live panel synchronization.
const SettingsScript = preload("res://scripts/ui/settings.gd")
var checks := 0
var failures: Array[String] = []
var output := "/tmp/cloud_arc_style_settings.json"
var phase := "verify"
var emitted: Array = []
var settings: Node
const POSE_FILE := "user://mobile_pose_overrides_v1.json"
const POSE_BYTES := "{\"arc_style_test\":\"leave this isolated pose file untouched\"}\n"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=" )
		if arg == "--seed": phase = "seed"
		if arg == "--reload": phase = "reload"
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL: ", label)
func finish() -> void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"phase":phase,"checks":checks,"failures":failures},"\t"))
	print("ARC STYLE SETTINGS: %s, %d checks, %d failures" % [phase,checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	if not OS.get_user_data_dir().contains("arc-style-settings-"):
		push_error("This fixture requires the isolated arc-style-settings- HOME/XDG directory")
		quit(2); return
	settings = root.get_node("Settings")
	settings.settings_changed.connect(func(key: String,value: Variant): emitted.append([key,value]))
	if phase == "seed":
		check(settings.get_value("video.focus_arc_style") == 0,"missing/older configuration defaults to steady dashed")
		check(not settings._config.has_section_key("video","focus_arc_style"),"reading default does not write config")
		settings.set_value("video.focus_arc_style",1)
		settings.set_value("gameplay.aim_focus_seconds",4.5)
		settings.set_value("video.shake",0.25)
		settings.set_value("audio.master",0.33)
		settings.set_value("pose_editor.arc_style_sentinel",{"revision":7,"custom_pose":[1,2,3]})
		FileAccess.open(POSE_FILE,FileAccess.WRITE).store_string(POSE_BYTES)
		await process_frame
		var disk := ConfigFile.new()
		check(disk.load(SettingsScript.CONFIG_PATH)==OK,"queued save produces readable settings")
		check(disk.get_value("video","focus_arc_style")==1,"solid written to actual settings file")
		finish();return
	if phase == "reload":
		check(settings.get_value("video.focus_arc_style")==1,"new process reloads solid")
		check(settings.get_value("gameplay.aim_focus_seconds")==4.5,"new process preserves gameplay timing")
		check(FileAccess.get_file_as_string(POSE_FILE)==POSE_BYTES,"new process preserves pose bytes")
	for value in [0,1]:
		emitted.clear();settings.set_value("video.focus_arc_style",value)
		check(settings.get_value("video.focus_arc_style")==value,"valid style persists")
		check(emitted==[["video.focus_arc_style",value]],"one correctly valued change event")
	for value in [-1,2,100,0.0,1.0,NAN,INF,-INF,"solid","1",true,false,null,[],{}]:
		emitted.clear();settings.set_value("video.focus_arc_style",value)
		check(settings.get_value("video.focus_arc_style")==0,"invalid setter defaults to steady dashed")
		check(emitted==[["video.focus_arc_style",0]],"invalid setter emits sanitized default")
		settings._config.set_value("video","focus_arc_style",value)
		check(settings.get_value("video.focus_arc_style")==0,"invalid saved value reads as steady dashed")
	settings.set_value("video.focus_arc_style",1)
	emitted.clear();settings.reset_focus_visuals()
	check(emitted.size()==4 and emitted.size()==SettingsScript.FOCUS_VISUAL_KEYS.size(),"visual reset covers exactly dim, blur, preview, style")
	for event in emitted: check(event[0] in SettingsScript.FOCUS_VISUAL_KEYS,"visual reset never changes unrelated key")
	check(settings.get_value("video.focus_arc_style")==0,"visual reset returns dashed")
	check(settings.get_value("video.shake")==0.25,"visual reset leaves shake")
	check(settings.get_value("audio.master")==0.33,"visual reset leaves audio")
	check(settings.get_value("gameplay.aim_focus_seconds")==4.5,"visual reset leaves gameplay timing")
	check(settings.get_value("pose_editor.arc_style_sentinel")=={"revision":7,"custom_pose":[1,2,3]},"visual reset leaves pose config")
	check(FileAccess.get_file_as_string(POSE_FILE)==POSE_BYTES,"visual reset leaves pose file")
	await process_frame
	var disk := ConfigFile.new();check(disk.load(SettingsScript.CONFIG_PATH)==OK,"reset settings reload")
	check(disk.get_value("video","focus_arc_style")==0,"reset dashed persists on disk")
	await panel_cases()
	settings.set_value("video.focus_arc_style",1);settings.reset_to_defaults()
	check(settings.get_value("video.focus_arc_style")==0,"full defaults include steady dashed")
	check(settings.get_value("pose_editor.arc_style_sentinel")=={"revision":7,"custom_pose":[1,2,3]},"full reset preserves unknown authored config")
	check(FileAccess.get_file_as_string(POSE_FILE)==POSE_BYTES,"full reset preserves pose bytes")
	await process_frame
	finish()

func panel_cases() -> void:
	paused = true
	root.get_node("PauseController").set_process_input(false)
	for resolution in [Vector2i(360,800),Vector2i(390,844),Vector2i(540,960),Vector2i(720,1280),Vector2i(1080,2340),Vector2i(1280,720)]:
		root.size=resolution;root.content_scale_size=resolution
		var panel = load("res://scripts/ui/settings_panel.gd").new();root.add_child(panel)
		for i in 6: await process_frame
		var option: OptionButton = panel.find_child("video_focus_arc_style",true,false)
		var reset: Button = panel.find_child("ResetFocusVisuals",true,false)
		var scroll: ScrollContainer = panel.find_child("Video",true,false)
		check(option!=null and reset!=null,"arc style controls exist at "+str(resolution))
		check(option.item_count==2 and option.get_item_text(0)=="Steady dashed" and option.get_item_text(1)=="Solid","two concise stable styles")
		check(panel._focus_controls.get("video.focus_arc_style")==option,"option registered for external/reset synchronization")
		settings.set_value("video.focus_arc_style",1)
		check(option.selected==1,"live setting updates dropdown")
		option.select(0);option.item_selected.emit(0)
		check(settings.get_value("video.focus_arc_style")==0,"dropdown selection writes actual setting")
		for i in 3:
			settings.set_value("video.focus_arc_style",1);reset.pressed.emit()
			check(option.selected==0 and settings.get_value("video.focus_arc_style")==0,"repeated reset synchronizes dropdown and settings")
		scroll.ensure_control_visible(option);await process_frame
		check(scroll.get_global_rect().grow(0.5).encloses(option.get_global_rect()),"arc style reachable in scroll at "+str(resolution))
		check(scroll.get_h_scroll_bar().max_value<=scroll.get_h_scroll_bar().page+0.5,"arc row adds no horizontal scrolling at "+str(resolution))
		check(root.get_visible_rect().grow(0.5).encloses(panel._panel.get_global_rect()),"panel fits viewport at "+str(resolution))
		settings.set_value("video.focus_arc_style",1)
		panel._on_close();await process_frame
		check(not is_instance_valid(panel),"panel closes cleanly")
		var reopened = load("res://scripts/ui/settings_panel.gd").new();root.add_child(reopened)
		for i in 3: await process_frame
		check(reopened.find_child("video_focus_arc_style",true,false).selected==1,"reopened dropdown retains selected solid")
		reopened._on_close();await process_frame
	paused = false
