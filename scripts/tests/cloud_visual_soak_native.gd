extends "res://scripts/tests/cloud_visual_soak.gd"
## Opt-in native raster capture of the SAME actual-input driver. The parent
## owns native display/CUA launch. Capture overhead is timed, never called FPS.
var capture_hz := 30.0
var capture_index: FileAccess
var next_capture_usec := 0
var capture_count := 0
var capture_size := Vector2i(540, 960)
func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Native visual soak requires native rendering; parent must launch this mode.")
		quit(2)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture-hz="): capture_hz = clampf(float(a.trim_prefix("--capture-hz=")), 1.0, 60.0)
		if a.begins_with("--capture-size="):
			var parts := a.trim_prefix("--capture-size=").split("x")
			capture_size = Vector2i(int(parts[0]), int(parts[1]))
	RenderingServer.frame_post_draw.connect(capture_frame)
	super._initialize()
func spawn_game() -> void:
	await super.spawn_game()
	root.size = capture_size
	root.content_scale_size = Vector2i(720, 1280)
	await frames(3)
func capture_frame() -> void:
	if not monitor or changing_scene or not is_instance_valid(game): return
	var before := Time.get_ticks_usec()
	if before < next_capture_usec: return
	next_capture_usec = before + roundi(1000000.0 / capture_hz)
	if capture_index == null:
		DirAccess.make_dir_recursive_absolute(output.path_join("png"))
		capture_index = FileAccess.open(output.path_join("native_capture_index.jsonl"), FileAccess.WRITE)
	var path := output.path_join("png/frame_%05d.png" % capture_count)
	var raster := root.get_texture().get_image()
	var image_usec := Time.get_ticks_usec()
	var error := raster.save_png(path)
	var after := Time.get_ticks_usec()
	var row := {"index": capture_count, "file": path, "elapsed_before_capture": float(before - start_usec) / 1000000.0, "usec_before_capture": before, "usec_after_capture": after, "texture_read_usec": image_usec - before, "png_write_usec": after - image_usec, "total_capture_usec": after - before, "error": error, "requested_capture_hz": capture_hz, "actual_raster_size": [raster.get_width(), raster.get_height()], "physics_hz": Engine.physics_ticks_per_second, "physics_frame": Engine.get_physics_frames(), "process_frame": Engine.get_process_frames(), "semantic": last_state.duplicate(true)}
	capture_index.store_line(JSON.stringify(row)); capture_index.flush()
	capture_count += 1
	check(error == OK, "native PNG write failed", {"path": path, "code": error})
